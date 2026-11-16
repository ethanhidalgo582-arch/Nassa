# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""IMPACT API (FastAPI). Serves the Flutter web build from the same origin when available."""
from __future__ import annotations

import logging
import os
import time
from concurrent.futures import TimeoutError as FutureTimeout
from contextlib import asynccontextmanager
from datetime import date, timedelta
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, ConfigDict, Field, model_validator

import forest_service
import gemini_service
import geocode_service
import glacier_outlines
import nisar_service
import respaldo
import summaries
import tts_service
from config import APP_NAME, APP_VERSION, BACKEND_DIR, Settings, user_agent
from errors import AnalysisError, invalid
from geo import parse_selection
from jobs import JobManager

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger("impact")


class AnalysisRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    module: Literal["bosques", "hundimiento", "glaciares"]
    polygon: list[list[float]] = Field(min_length=3, max_length=200)
    start_date: date | None = None
    end_date: date | None = None
    start_year: int | None = Field(default=None, ge=2001, le=2100)
    end_year: int | None = Field(default=None, ge=2001, le=2100)
    canopy_threshold: int = Field(default=30, ge=10, le=75)
    min_coherence: float | None = Field(default=None, ge=0.1, le=0.95)

    @model_validator(mode="after")
    def _dates(self):
        if self.start_date and self.end_date and self.start_date >= self.end_date:
            raise ValueError("start_date must be before end_date")
        if self.end_date and self.end_date > date.today():
            raise ValueError("end_date cannot be in the future")
        return self


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    result_id: str = Field(min_length=8, max_length=64)
    locale: Literal["es", "en"] = "es"
    part: int = Field(default=0, ge=0, le=1)


class InterpretRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    result_id: str = Field(min_length=8, max_length=64)
    locale: Literal["es", "en"] = "es"


def default_period(module: str, today: date | None = None) -> dict:
    today = today or date.today()
    if module == "bosques":
        last = forest_service.HANSEN_LAST_YEAR
        return {"start_year": last - 9, "end_year": last}
    if module == "hundimiento":
        return {"start_date": nisar_service.NISAR_FIRST_DATE.isoformat(), "end_date": today.isoformat()}
    return {"start_date": (today - timedelta(days=120)).isoformat(), "end_date": today.isoformat()}


def _err(e: AnalysisError, status: int) -> HTTPException:
    return HTTPException(status_code=status, detail=e.to_dict())


def create_app(settings: Settings | None = None, web_dir: Path | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    jobs = JobManager(settings.max_concurrent_jobs, settings.job_timeout_seconds, settings.result_ttl_seconds)

    @asynccontextmanager
    async def lifespan(_app):
        yield
        jobs.shutdown()

    app = FastAPI(title=f"{APP_NAME} API", version=APP_VERSION, docs_url="/api/docs", openapi_url="/api/openapi.json",
                  lifespan=lifespan)
    app.state.settings = settings
    app.state.jobs = jobs
    ua = user_agent(settings)

    if settings.allowed_origins:
        app.add_middleware(CORSMiddleware, allow_origins=list(settings.allowed_origins), allow_methods=["GET", "POST", "DELETE"],
                           allow_headers=["Content-Type"], allow_credentials=False)
    else:  # local development: any localhost port
        app.add_middleware(CORSMiddleware, allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
                           allow_methods=["GET", "POST", "DELETE"], allow_headers=["Content-Type"])
    app.add_middleware(GZipMiddleware, minimum_size=1024)

    @app.middleware("http")
    async def security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
        response.headers.setdefault("X-Frame-Options", "DENY")
        if request.url.path.startswith("/api/"):
            response.headers.setdefault("Cache-Control", "no-store")
        return response

    @app.exception_handler(HTTPException)
    async def http_error(_, exc: HTTPException):
        detail = exc.detail
        if not isinstance(detail, dict):
            detail = {"kind": "http_error", "message": {"es": str(detail), "en": str(detail)}, "retryable": False}
        return JSONResponse(status_code=exc.status_code, content={"detail": detail})

    # -- light endpoints ----------------------------------------------------
    @app.get("/health")
    @app.get("/api/v1/health")
    def health():
        return {"status": "ok", "service": APP_NAME.lower(), "version": APP_VERSION}

    @app.get("/api/v1/config")
    def config():
        today = date.today()
        return {
            "app": APP_NAME, "version": APP_VERSION,
            "gemini_configured": settings.gemini_configured,
            "tts": {"gemini": settings.gemini_configured},
            "earthdata_configured": settings.earthdata_configured,
            "jobs": app.state.jobs.stats(),
            "tiles": {"carto_key": settings.carto_api_key or None},
            "limits": {"max_area_km2": settings.max_area_km2},
            "modules": {
                "bosques": {"source": forest_service.SOURCE["name"], "version": forest_service.HANSEN_VERSION,
                            "first_year": forest_service.HANSEN_FIRST_YEAR, "last_year": forest_service.HANSEN_LAST_YEAR,
                            "default": default_period("bosques", today), "requires": []},
                "hundimiento": {"source": nisar_service.SOURCE_BASE["name"], "first_date": nisar_service.NISAR_FIRST_DATE.isoformat(),
                                "default": default_period("hundimiento", today), "requires": ["earthdata"]},
                "glaciares": {"source": nisar_service.SOURCE_BASE["name"], "first_date": nisar_service.NISAR_FIRST_DATE.isoformat(),
                              "default": default_period("glaciares", today), "requires": ["earthdata"]},
            },
        }

    @app.get("/api/v1/geocode")
    def geocode(q: str = Query(min_length=2, max_length=120), lang: Literal["es", "en"] = "es"):
        try:
            return {"results": geocode_service.search(q, lang, ua)}
        except AnalysisError as e:
            raise _err(e, 503)

    # -- analyses -----------------------------------------------------------
    @app.post("/api/v1/analyses", status_code=202)
    def create_analysis(req: AnalysisRequest):
        try:
            sel = parse_selection(req.polygon, settings.max_area_km2)
        except AnalysisError as e:
            raise _err(e, 422)
        defaults = default_period(req.module)
        if req.module == "bosques":
            a = req.start_year or defaults["start_year"]
            b = req.end_year or defaults["end_year"]
            params = {"start_year": a, "end_year": b, "canopy_threshold": req.canopy_threshold}
        else:
            a = req.start_date or date.fromisoformat(defaults["start_date"])
            b = req.end_date or date.fromisoformat(defaults["end_date"])
            if a < nisar_service.NISAR_FIRST_DATE - timedelta(days=60):
                a = nisar_service.NISAR_FIRST_DATE - timedelta(days=60)
            params = {"start": a.isoformat(), "end": b.isoformat(),
                      "min_coherence": req.min_coherence or (0.35 if req.module == "hundimiento" else 0.3)}
            if not settings.earthdata_configured:
                raise _err(AnalysisError(
                    "not_configured",
                    "Este servidor no tiene credenciales de NASA Earthdata configuradas; el análisis NISAR no está disponible.",
                    "This server has no NASA Earthdata credentials configured; NISAR analysis is unavailable.",
                ), 503)
        payload = {"polygon": [[round(p[0], 6), round(p[1], 6)] for p in req.polygon], **params}

        def run(stage, check):
            if req.module == "bosques":
                return live(stage, check)
            # NISAR: try live data for a short budget; if it is slow or fails, answer with the
            # saved backup of this area (when one exists). The live download keeps going in the
            # background and refreshes the backup when it finishes.
            backup = respaldo.load(req.module, sel)
            answered = []  # set once the job has answered; the background download stops touching it

            def bg_stage(name):
                if not answered:
                    stage(name)

            def live_and_save():
                result = live(bg_stage, check)
                result.setdefault("generated_at", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
                respaldo.save(req.module, sel, result)
                return result

            if backup is None:
                return live_and_save()
            future = respaldo.background.submit(live_and_save)
            try:
                return future.result(timeout=settings.nisar_live_budget_seconds)
            except FutureTimeout:
                log.info("live NISAR data is slow; answering with the saved backup")
                answered.append(True)
                return respaldo.as_backup(backup, "slow")
            except AnalysisError as e:
                if e.kind in ("invalid_input", "cancelled"):
                    raise
                log.info("live NISAR data failed (%s); answering with the saved backup", e.kind)
                answered.append(True)
                return respaldo.as_backup(backup, "error")
            except Exception as e:
                if type(e).__name__ == "Cancelled":
                    raise
                log.warning("live NISAR data failed; answering with the saved backup", exc_info=True)
                answered.append(True)
                return respaldo.as_backup(backup, "error")

        def live(stage, check):
            if req.module == "bosques":
                result = forest_service.analyze(sel, params["start_year"], params["end_year"], params["canopy_threshold"],
                                                max_pixels=settings.max_forest_pixels, stage=stage)
            elif req.module == "hundimiento":
                result = nisar_service.analyze_subsidence(
                    sel, date.fromisoformat(params["start"]), date.fromisoformat(params["end"]), settings=settings,
                    opener=nisar_service.earthdata_opener(settings), stage=stage, min_coherence=params["min_coherence"],
                    check_cancel=check)
            else:
                stage("searching")
                outlines = glacier_outlines.fetch(sel, ua)
                result = nisar_service.analyze_glacier(
                    sel, date.fromisoformat(params["start"]), date.fromisoformat(params["end"]), settings=settings,
                    opener=nisar_service.earthdata_opener(settings), outlines=outlines, stage=stage,
                    min_coherence=params["min_coherence"], check_cancel=check)
                result["outlines"] = ({k: outlines[k] for k in ("features", "area_km2", "mapped", "source")}
                                      if outlines else None)
            result["selection"] = {"geojson": sel.geojson(), "area_km2": round(sel.area_km2, 3)}
            result["request"] = params
            result["summary"] = summaries.build(result)
            return result

        job = app.state.jobs.submit(req.module, payload, run)
        return job.public()

    @app.get("/api/v1/analyses/{job_id}")
    def get_analysis(job_id: str):
        job = app.state.jobs.get(job_id)
        if not job:
            raise _err(AnalysisError(
                "expired",
                "Este análisis ya no existe en el servidor (pudo reiniciarse o expirar). Vuelve a analizar.",
                "This analysis no longer exists on the server (it may have restarted or expired). Please analyse again.",
                retryable=True), 404)
        return job.public()

    @app.delete("/api/v1/analyses/{job_id}")
    def cancel_analysis(job_id: str):
        return {"cancelled": app.state.jobs.cancel(job_id)}

    @app.post("/api/v1/interpret")
    def interpret(req: InterpretRequest):
        stored = app.state.jobs.stored(req.result_id)
        if not stored:
            raise _err(AnalysisError(
                "expired", "El resultado expiró o el servidor se reinició. Vuelve a analizar.",
                "The result expired or the server restarted. Please analyse again.", retryable=True), 404)
        cached = stored["interpretations"].get(req.locale)
        if cached:
            return cached
        try:
            out = gemini_service.interpret(stored["result"], req.locale, settings)
        except AnalysisError as e:
            raise _err(e, 503 if e.kind == "not_configured" else 502)
        out["result_id"] = req.result_id
        stored["interpretations"][req.locale] = out
        return out

    @app.post("/api/v1/speech")
    def speech(req: SpeechRequest):
        """Gemini voice for the summary (+ interpretation if already generated) in the requested locale."""
        stored = app.state.jobs.stored(req.result_id)
        if not stored:
            raise _err(AnalysisError(
                "expired", "El resultado expiró o el servidor se reinició. Vuelve a analizar.",
                "The result expired or the server restarted. Please analyse again.", retryable=True), 404)
        try:
            audio, meta = tts_service.synthesize(stored["result"], stored["interpretations"].get(req.locale),
                                                 req.locale, settings, part=req.part)
        except AnalysisError as e:
            raise _err(e, {"not_configured": 503, "no_data": 404}.get(e.kind, 502))
        return Response(content=audio, media_type="audio/wav", headers={
            "X-TTS-Parts": str(meta.get("parts", 1)),
            "Cache-Control": "no-store",
            "X-TTS-Model": str(meta.get("model") or ""),
            "X-TTS-Includes-Interpretation": "1" if stored["interpretations"].get(req.locale) else "0",
        })

    # -- frontend -------------------------------------------------------------
    web = web_dir or Path(os.getenv("WEB_DIR", str(BACKEND_DIR.parent / "mobile" / "build" / "web")))
    if web.is_dir() and (web / "index.html").exists():
        index = web / "index.html"
        app.mount("/assets", StaticFiles(directory=web / "assets", check_dir=False), name="assets")

        @app.get("/{path:path}", include_in_schema=False)
        def spa(path: str):
            if path.startswith("api/"):
                raise HTTPException(404, "Not found")
            candidate = (web / path).resolve()
            if path and candidate.is_file() and web.resolve() in candidate.parents:
                headers = {"Cache-Control": "no-cache"} if path in ("flutter_service_worker.js", "flutter_bootstrap.js",
                                                                    "main.dart.js", "version.json", "manifest.json") else {}
                return FileResponse(candidate, headers=headers)
            return FileResponse(index, headers={"Cache-Control": "no-cache"})  # SPA fallback: refresh never 404s
    else:
        log.info("No web build found at %s; serving API only.", web)

    return app


app = create_app()
