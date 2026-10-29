from contextlib import asynccontextmanager
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from config import Settings

from nisar_service import descargar_gunw_real, get_classified_zones, get_displacement, get_stats 
from gemini_service import GeminiService, GeminiServiceError
from schemas import AnalysisRequest, AnalysisResponse

NOTICE = "Análisis generado a partir de datos satelitales NISAR reales. Requiere validación técnica."

def create_app(settings: Settings | None = None):
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
      
        print("Iniciando conexión con NASA Earthdata...")
        try:
            descargar_gunw_real()
        except Exception as e:
            print(f"Error al descargar de la NASA: {e}")
            
        app.state.gemini = GeminiService(settings)
        try:
            yield
        finally:
            await app.state.gemini.close()

    app = FastAPI(title="NISAR API Real", lifespan=lifespan)
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )

    @app.get("/")
    def root():
        return {"status": "ok", "message": "NISAR API Real"}

    @app.get("/api/v1/health")
    def health():
        return {
            "status": "ok",
            "data_mode": "real",
            "gemini": {
                "configured": bool(settings.gemini_api_key),
                "model": settings.gemini_model,
                "connection_verified": False,
            },
        }

    @app.get("/api/v1/classified-zones")
    def zones():
        return get_classified_zones()

    @app.get("/api/v1/displacement")
    def displacement_route(
        lat: float = Query(ge=-90, le=90, allow_inf_nan=False),
        lng: float = Query(ge=-180, le=180, allow_inf_nan=False),
    ):
        try:
            return get_displacement(lat, lng)
        except Exception as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc

    @app.get("/api/v1/dashboard-stats")
    def stats():
        return get_stats()

    @app.post("/api/v1/ai/analyze", response_model=AnalysisResponse)
    async def analyze(payload: AnalysisRequest):
        try:
            context = get_displacement(payload.latitude, payload.longitude)
        except Exception as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
            
        try:
            report = await app.state.gemini.analyze(context, payload.question)
        except GeminiServiceError as exc:
            raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc
            
        return AnalysisResponse(
            model=settings.gemini_model,
            latitude=payload.latitude,
            longitude=payload.longitude,
            data_source=context.get("source", "NISAR"),
            is_simulated=False, 
            notice=NOTICE,
            analysis=report,
        )

    return app

app = create_app()