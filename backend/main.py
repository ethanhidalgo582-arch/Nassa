from contextlib import asynccontextmanager
import asyncio, time, uuid
from fastapi import FastAPI, HTTPException, Query, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from config import Settings
from gemini_service import GeminiService, GeminiServiceError
from metrics_schemas import MetricsRequest, InterpretRequest
from schemas import AnalysisRequest
from analysis_service import calculate, DataUnavailable

def create_app(settings=None):
    settings = settings or Settings.from_env()
    
    @asynccontextmanager
    async def lifespan(app):
        yield
        await app.state.gemini.close()
        
    app = FastAPI(title="NISAR App", lifespan=lifespan)
    app.state.gemini = GeminiService(settings)
    app.state.results = {}
    app.state.busy = False
    
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    app.add_middleware(
        CORSMiddleware, 
        allow_origins=list(settings.cors_origins), 
        allow_methods=["GET", "POST"], 
        allow_headers=["Content-Type"]
    )
    
    @app.get("/")
    def root(): return {"status":"ok","message":"NISAR App"}
    
    @app.get("/api/v1/health")
    def health():
        return {
            "status": "ok",
            "data_mode": "on_demand",
            "gemini": {
                "configured": bool(settings.gemini_api_key),
                "model": settings.gemini_model,
                "connection_verified": False
            },
            "capabilities": {
                "bosques": "osm_historical_mapping",
                "glaciares": "gunw_phase_derived_los",
                "hundimiento": "conditional_vertical_projection"
            }
        }
    
    @app.get("/api/v1/classified-zones")
    @app.get("/api/v1/disaster-zones")
    def zones(): 
        return {"type":"FeatureCollection","features":[],"note":"Selecciona un área y consulta métricas."}
    
    @app.get("/api/v1/dashboard-stats")
    def stats(): 
        return {"activeAlerts":None,"criticalAreaKm2":None,"affectedPopulation":None,"lastUpdate":None,"source":None,"is_simulated":False}
    
    @app.get("/api/v1/displacement")
    def displacement_route(lat:float=Query(ge=-90,le=90,allow_inf_nan=False),lng:float=Query(ge=-180,le=180,allow_inf_nan=False)):
        raise HTTPException(409, "Selecciona área y fechas en /api/v1/metrics. No hay una serie temporal validada.")
    
    @app.post("/api/v1/ai/analyze")
    async def legacy_analyze(payload: AnalysisRequest):
        raise HTTPException(409, "Calcula /api/v1/metrics y envía su result_id a /api/v1/ai/interpret.")
    
    @app.get("/api/v1/multiregion/comparacion")
    def multi(): 
        raise HTTPException(409, "Analiza cada región con área y fechas explícitas mediante /api/v1/metrics.")
    
    @app.post("/api/v1/metrics")
    async def metrics(payload: MetricsRequest):
        # 1. Crear firma única
        firma = f"{payload.module}|{payload.date_a}|{payload.date_b}|{str(payload.polygon)}"
        
        # 2. Si ya está en caché, devolver al instante
        if firma in app.state.results:
            print("⚡ Respondiendo al instante desde caché en main.py")
            return app.state.results[firma]

        # 3. Si el servidor está ocupado, avisamos (202)
        if app.state.busy:
            return JSONResponse(
                status_code=202, 
                content={"status": "processing", "message": "El servidor está procesando otra solicitud. Espera un momento."}
            )

        # 4. Si no está en caché, procesamos de forma normal (síncrona)
        app.state.busy = True
        try:
            print("🚀 Iniciando cálculo...")
            result = await asyncio.to_thread(calculate, payload)
            
            now = time.time()
            result_id = uuid.uuid4().hex
            result.update(result_id=result_id, _timestamp=now)
            
            # Guardamos en la caché de main.py
            app.state.results[firma] = result
            print("✅ Cálculo completado y guardado en caché.")
            return result
            
        except Exception as e:
            print(f"❌ Error en cálculo: {e}")
            raise HTTPException(502, "Error al procesar los datos. Revisa la consola.")
        finally:
            app.state.busy = False
        
    @app.post("/api/v1/ai/interpret")
    async def interpret(payload: InterpretRequest):
        # Buscamos el resultado iterando sobre la caché usando el result_id real
        encontrado = None
        for firma, datos in app.state.results.items():
            if isinstance(datos, dict) and datos.get("result_id") == payload.result_id:
                encontrado = datos
                break
                
        if not encontrado: 
            raise HTTPException(404, "El resultado expiró o no existe. Vuelve a calcular.")
            
        context = {k:v for k,v in encontrado.items() if k not in ("map","map_a","map_b","points","snapshots","_timestamp")}
        
        pregunta_final = payload.question
        if payload.user_context:
            pregunta_final += f"\n\n[CONTEXTO DEL USUARIO]: El usuario indica lo siguiente sobre su situación: '{payload.user_context}'. Por favor, responde explicando cómo le afecta esto directamente a él o a su comunidad."
            
        try:
            report = await app.state.gemini.analyze(context, pregunta_final)
            return {
                "analysis": report.model_dump(),
                "notice": "Interpretación de IA; las métricas se conservan por separado.",
                "model": settings.gemini_model
            }
        except GeminiServiceError as e: 
            raise HTTPException(e.status_code, str(e)) from e
    return app

app = create_app()