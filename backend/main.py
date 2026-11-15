"""FastAPI application for the NISAR monitoring app."""
from datetime import date, datetime
from pathlib import Path
from typing import Literal, Optional
import os
import time
import uuid

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

load_dotenv(Path(__file__).parent / ".env")

import analysis_service
from gemini_service import interpret_metrics

app = FastAPI(title="NISAR Monitoring API", version="0.2.0")

# Configuración de CORS
origins = [
    o.strip()
    for o in os.getenv("ALLOWED_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080").split(",")
    if o.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Almacenamiento en memoria de los resultados generados
_RESULTS: dict[str, dict] = {}
_RESULT_TTL_SECONDS = 3600
_MAX_RESULTS = 200


def _purge_expired_results() -> None:
    now = time.time()
    expired = [
        k for k, v in _RESULTS.items()
        if now - v.get("_timestamp", 0) > _RESULT_TTL_SECONDS
    ]
    for k in expired:
        _RESULTS.pop(k, None)


class MetricsRequest(BaseModel):
    module: Literal["bosques", "hundimiento", "glaciares"]
    polygon: list[list[float]] = Field(..., min_length=3, max_length=50)
    date_a: Optional[date] = None
    date_b: Optional[date] = None
    min_coherence: float = Field(default=0.35, ge=0.0, le=1.0)


class InterpretRequest(BaseModel):
    result_id: str = Field(..., min_length=1, max_length=100)
    user_context: str = Field(default="", max_length=1000)
    locale: Literal["es", "en"] = "es"


@app.get("/health")
@app.get("/api/v1/health")
def health() -> dict:
    return {
        "status": "ok",
        "service": "nisar-backend",
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


@app.post("/api/v1/metrics")
def get_metrics(req: MetricsRequest) -> dict:
    if req.date_a and req.date_b and req.date_a >= req.date_b:
        raise HTTPException(
            status_code=400,
            detail="date_a debe ser anterior a date_b.",
        )

    for pt in req.polygon:
        if len(pt) != 2:
            raise HTTPException(
                status_code=400,
                detail="Cada vértice del polígono debe tener exactamente [lat, lon].",
            )
        lat, lon = pt
        if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
            raise HTTPException(
                status_code=400,
                detail="Coordenadas fuera de rango válido.",
            )

    try:
        result = analysis_service.calculate(req)
    except analysis_service.DataUnavailable as e:
        raise HTTPException(status_code=422, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error interno calculando métricas: {e}")

    _purge_expired_results()
    if len(_RESULTS) >= _MAX_RESULTS:
        oldest_key = next(iter(_RESULTS))
        _RESULTS.pop(oldest_key, None)

    result_id = str(uuid.uuid4())
    stored = dict(result)
    stored["result_id"] = result_id
    stored["_timestamp"] = time.time()
    _RESULTS[result_id] = stored

    response_payload = dict(result)
    response_payload["result_id"] = result_id
    return response_payload


@app.post("/api/v1/ai/interpret")
def interpret(req: InterpretRequest) -> dict:
    _purge_expired_results()
    encontrado = _RESULTS.get(req.result_id)
    if not encontrado:
        raise HTTPException(
            status_code=404,
            detail="El resultado solicitado no existe o ha expirado. Recalcula las métricas primero.",
        )

    # Excluimos geometrías extensas, puntos crudos y la imagen Base64 (raster_overlay)
    # para enviar solo las métricas estadísticas limpias a Gemini
    context = {
        k: v
        for k, v in encontrado.items()
        if k not in ("map", "map_a", "map_b", "points", "snapshots", "_timestamp", "raster_overlay")
    }

    try:
        analysis = interpret_metrics(
            context=context,
            user_context=req.user_context,
            locale=req.locale,
        )
        return {
            "result_id": req.result_id,
            "locale": req.locale,
            "analysis": analysis,
        }
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Error interpretando resultados con Gemini: {e}")