from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from config import Settings
from data_service import NOTICE, OutsideCoverageError, classified_zones, dashboard_stats, displacement
from gemini_service import GeminiService, GeminiServiceError
from schemas import AnalysisRequest, AnalysisResponse


def create_app(settings: Settings | None = None):
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.gemini = GeminiService(settings)
        try:
            yield
        finally:
            await app.state.gemini.close()

    app = FastAPI(title="NISAR Demo + Gemini API", lifespan=lifespan)
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )

    def get_context(lat: float, lng: float):
        try:
            return displacement(lat, lng)
        except OutsideCoverageError as exc:
            msg = str(exc)
            if "No hay productos" in msg or "Credenciales" in msg or "descarga" in msg.lower():
                raise HTTPException(status_code=503, detail=msg) from exc
            raise HTTPException(status_code=404, detail=msg) from exc

    @app.get("/")
    def root():
        return {"status": "ok", "message": "NISAR Demo + Gemini API"}

    @app.get("/api/v1/health")
    def health():
        return {
            "status": "ok",
            "data_mode": "demo",
            "gemini": {
                "configured": bool(settings.gemini_api_key),
                "model": settings.gemini_model,
                "connection_verified": False,
            },
        }

    @app.get("/api/v1/classified-zones")
    @app.get("/api/v1/disaster-zones", include_in_schema=False)
    def get_zones():
        return classified_zones()

    @app.get("/api/v1/displacement")
    def get_displacement(
        lat: float = Query(ge=-90, le=90, allow_inf_nan=False),
        lng: float = Query(ge=-180, le=180, allow_inf_nan=False),
    ):
        return get_context(lat, lng)

    @app.get("/api/v1/dashboard-stats")
    def get_stats():
        return dashboard_stats()

    @app.post("/api/v1/ai/analyze", response_model=AnalysisResponse)
    async def analyze(payload: AnalysisRequest):
        context = get_context(payload.latitude, payload.longitude)
        try:
            report = await app.state.gemini.analyze(context, payload.question)
        except GeminiServiceError as exc:
            raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
        return AnalysisResponse(
            model=settings.gemini_model,
            latitude=payload.latitude,
            longitude=payload.longitude,
            data_source=context["source"],
            is_simulated=context["is_simulated"],
            notice=NOTICE,
            analysis=report,
        )

    return app


app = create_app()

