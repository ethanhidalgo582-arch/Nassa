"""In-process job manager for long analyses.

* POST returns immediately with a job id; the client polls the status.
* Identical requests (same signature) share one job instead of running twice.
* Every job has a deadline: a stuck provider can never leave the app permanently
  "busy" — the job is marked as timed out and its slot is released.
* State lives in memory: after a restart the client receives 404 and is told to retry.
  (Render free instances restart and sleep; nothing here needs to persist.)
"""
from __future__ import annotations

import hashlib
import json
import logging
import threading
import time
import traceback
import uuid
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Callable

from errors import AnalysisError

log = logging.getLogger("impact.jobs")

STAGES = ("queued", "searching", "reading", "processing", "rendering", "done")


class Cancelled(Exception):
    pass


@dataclass
class Job:
    job_id: str
    signature: str
    module: str
    created: float = field(default_factory=time.time)
    started: float | None = None
    finished: float | None = None
    status: str = "queued"  # queued | running | done | error
    stage: str = "queued"
    result: dict | None = None
    error: dict | None = None
    deadline: float | None = None
    cancelled: bool = False

    def public(self) -> dict:
        now = time.time()
        return {
            "job_id": self.job_id,
            "module": self.module,
            "status": self.status,
            "stage": self.stage,
            "elapsed_seconds": round((self.finished or now) - (self.started or self.created), 1),
            "result": self.result if self.status == "done" else None,
            "error": self.error if self.status == "error" else None,
        }


def signature(payload: dict) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, default=str).encode()).hexdigest()[:32]


class JobManager:
    def __init__(self, max_workers: int, timeout_s: int, ttl_s: int):
        self._pool = ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="impact-job")
        self._jobs: dict[str, Job] = {}
        self._by_sig: dict[str, str] = {}
        self._results: dict[str, dict] = {}  # result_id -> result (kept for interpretation)
        self._lock = threading.Lock()
        self.timeout_s = timeout_s
        self.ttl_s = ttl_s

    # -- lifecycle -------------------------------------------------------
    def submit(self, module: str, payload: dict, fn: Callable[[Callable[[str], None], Callable[[], None]], dict]) -> Job:
        sig = signature({"module": module, **payload})
        with self._lock:
            self._purge()
            existing = self._jobs.get(self._by_sig.get(sig, ""))
            if existing and (existing.status in ("queued", "running") or existing.status == "done"):
                return existing
            job = Job(job_id=uuid.uuid4().hex, signature=sig, module=module)
            self._jobs[job.job_id] = job
            self._by_sig[sig] = job.job_id
        self._pool.submit(self._run, job, fn)
        return job

    def _run(self, job: Job, fn):
        if job.cancelled:
            return
        job.status, job.stage, job.started = "running", "searching", time.time()
        job.deadline = job.started + self.timeout_s

        def stage(name: str):
            check()
            job.stage = name

        def check():
            if job.cancelled:
                raise Cancelled()
            if job.deadline and time.time() > job.deadline:
                raise AnalysisError(
                    "timeout",
                    "El análisis superó el tiempo máximo. Prueba con un área más pequeña o un período más corto.",
                    "The analysis exceeded the time limit. Try a smaller area or a shorter period.",
                    retryable=True,
                )

        try:
            result = fn(stage, check)
            check()
            result_id = uuid.uuid4().hex
            result["result_id"] = result_id
            result["generated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            with self._lock:
                self._results[result_id] = {"result": result, "t": time.time(), "interpretations": {}}
            job.result, job.status, job.stage = result, "done", "done"
        except Cancelled:
            job.status = "error"
            job.error = AnalysisError("cancelled", "Análisis cancelado.", "Analysis cancelled.").to_dict()
        except AnalysisError as e:
            job.status, job.error = "error", e.to_dict()
            log.info("job %s ended: %s", job.job_id, e.kind)
        except Exception:  # unexpected: log server-side, show a generic message
            log.error("job %s failed\n%s", job.job_id, traceback.format_exc())
            job.status = "error"
            job.error = AnalysisError(
                "internal_error",
                "Ocurrió un error inesperado al procesar los datos. Vuelve a intentarlo.",
                "An unexpected error occurred while processing the data. Please try again.",
                retryable=True,
            ).to_dict()
        finally:
            job.finished = time.time()
            if job.status == "error":
                with self._lock:  # failed jobs can be retried with the same parameters
                    if self._by_sig.get(job.signature) == job.job_id:
                        self._by_sig.pop(job.signature, None)

    def get(self, job_id: str) -> Job | None:
        with self._lock:
            job = self._jobs.get(job_id)
        if job and job.status == "running" and job.deadline and time.time() > job.deadline + 30:
            # Worker thread is blocked in a provider call: report the timeout now; the
            # thread result is discarded when (if) it finishes.
            job.cancelled = True
            job.status = "error"
            job.finished = time.time()
            job.error = AnalysisError(
                "timeout",
                "El proveedor de datos no respondió a tiempo. Vuelve a intentarlo más tarde.",
                "The data provider did not answer in time. Try again later.",
                retryable=True,
            ).to_dict()
            with self._lock:
                if self._by_sig.get(job.signature) == job.job_id:
                    self._by_sig.pop(job.signature, None)
        return job

    def cancel(self, job_id: str) -> bool:
        job = self.get(job_id)
        if not job or job.status not in ("queued", "running"):
            return False
        job.cancelled = True
        if job.status == "queued":
            job.status = "error"
            job.error = AnalysisError("cancelled", "Análisis cancelado.", "Analysis cancelled.").to_dict()
            with self._lock:
                self._by_sig.pop(job.signature, None)
        return True

    def stored(self, result_id: str) -> dict | None:
        with self._lock:
            self._purge()
            return self._results.get(result_id)

    def stats(self) -> dict:
        with self._lock:
            return {
                "queued": sum(j.status == "queued" for j in self._jobs.values()),
                "running": sum(j.status == "running" for j in self._jobs.values()),
            }

    def _purge(self):
        now = time.time()
        for jid, j in list(self._jobs.items()):
            if j.finished and now - j.finished > self.ttl_s:
                self._jobs.pop(jid, None)
                if self._by_sig.get(j.signature) == jid:
                    self._by_sig.pop(j.signature, None)
        for rid, r in list(self._results.items()):
            if now - r["t"] > self.ttl_s:
                self._results.pop(rid, None)
        # keep memory bounded on small instances
        if len(self._results) > 60:
            for rid in sorted(self._results, key=lambda k: self._results[k]["t"])[: len(self._results) - 60]:
                self._results.pop(rid, None)

    def shutdown(self):
        self._pool.shutdown(wait=False, cancel_futures=True)


