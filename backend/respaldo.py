# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Saved NISAR results ("respaldo") used when the live satellite download is too slow or fails.

NISAR products are streamed from NASA Earthdata in 4 MB blocks; on a slow connection or a
busy server one analysis can take many minutes. Every successful live analysis is saved
here (one JSON per module + area). The next request for the same area tries the live data
for a short time budget and, if it is not ready, answers at once with the saved result,
clearly marked as a backup with its date. The live download keeps running in the
background and refreshes the backup when it finishes.
"""
from __future__ import annotations

import json
import logging
import os
import re
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from config import BACKEND_DIR

log = logging.getLogger("impact.respaldo")

DIR = Path(os.getenv("RESPALDO_DIR", str(BACKEND_DIR / "datos_precargados")))
_lock = threading.Lock()
# Live downloads that keep running after the backup was returned.
background = ThreadPoolExecutor(max_workers=2, thread_name_prefix="impact-live")


def _path(module: str, sel) -> Path:
    west, south, east, north = sel.bounds
    name = f"{module}_{south:.3f}_{west:.3f}_{north:.3f}_{east:.3f}"
    return DIR / (re.sub(r"[^0-9A-Za-z_.-]", "m", name) + ".json")


def load(module: str, sel) -> dict | None:
    path = _path(module, sel)
    try:
        with _lock, path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        log.warning("backup %s is unreadable; ignoring it", path.name)
        return None


def save(module: str, sel, result: dict) -> None:
    data = {k: v for k, v in result.items() if k not in ("result_id", "backup")}
    path = _path(module, sel)
    try:
        DIR.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".tmp")
        with _lock:
            tmp.write_text(json.dumps(data, ensure_ascii=False, default=str), encoding="utf-8")
            tmp.replace(path)
    except OSError:
        log.warning("could not save backup %s", path.name, exc_info=True)


def as_backup(saved: dict, reason: str) -> dict:
    """Mark a saved result so the app and the AI know it is not live data."""
    result = dict(saved)
    when = (saved.get("generated_at") or "")[:10] or "?"
    why = {
        "slow": ("la descarga en vivo del satélite está tardando demasiado",
                 "the live satellite download is taking too long"),
        "error": ("el servicio de datos del satélite no respondió correctamente",
                  "the satellite data service did not answer correctly"),
    }[reason]
    result["backup"] = {"saved_at": when, "reason": reason}
    note = {
        "es": f"Datos de respaldo guardados el {when}: se muestran porque {why[0]}. Vuelve a analizar más tarde para datos actualizados.",
        "en": f"Backup data saved on {when}: shown because {why[1]}. Analyse again later for updated data.",
    }
    lim = dict(result.get("limitations") or {})
    for lang, text in note.items():
        lim[lang] = [text, *(lim.get(lang) or [])]
    result["limitations"] = lim
    summary = dict(result.get("summary") or {})
    for lang, text in note.items():
        if isinstance(summary.get(lang), dict):
            s = dict(summary[lang])
            s["points"] = [text, *(s.get("points") or [])]
            if s.get("speech"):
                s["speech"] = f"{s['speech']} {text}"
            summary[lang] = s
    result["summary"] = summary
    return result
