from contextlib import asynccontextmanager
import asyncio, time, uuid
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from config import Settings
from gemini_service import GeminiService, GeminiServiceError
from metrics_schemas import MetricsRequest, InterpretRequest
from schemas import AnalysisRequest
from analysis_service import calculate, DataUnavailable

def create_app(settings=None):
    settings=settings or Settings.from_env()
    @asynccontextmanager
    async def lifespan(app):
        yield
        await app.state.gemini.close()
    app=FastAPI(title="NISAR App",lifespan=lifespan)
    app.state.gemini=GeminiService(settings)
    app.state.results={}
    app.state.busy=False
    app.add_middleware(GZipMiddleware,minimum_size=1024)
    app.add_middleware(CORSMiddleware,allow_origins=list(settings.cors_origins),allow_methods=["GET","POST"],allow_headers=["Content-Type"])
    
    @app.get("/")
    def root(): return {"status":"ok","message":"NISAR App"}
    
    @app.get("/api/v1/health")
    def health():
        return {"status":"ok","data_mode":"on_demand","gemini":{"configured":bool(settings.gemini_api_key),"model":settings.gemini_model,"connection_verified":False},
          "capabilities":{"bosques":"osm_historical_mapping","glaciares":"gunw_phase_derived_los","hundimiento":"conditional_vertical_projection"}}
    
    @app.get("/api/v1/classified-zones")
    @app.get("/api/v1/disaster-zones")
    def zones(): return {"type":"FeatureCollection","features":[],"note":"Selecciona un área y consulta métricas."}
    
    @app.get("/api/v1/dashboard-stats")
    def stats(): return {"activeAlerts":None,"criticalAreaKm2":None,"affectedPopulation":None,"lastUpdate":None,"source":None,"is_simulated":False}
    
    @app.get("/api/v1/displacement")
    def displacement_route(lat:float=Query(ge=-90,le=90,allow_inf_nan=False),lng:float=Query(ge=-180,le=180,allow_inf_nan=False)):
        raise HTTPException(409,"Selecciona área y fechas en /api/v1/metrics. No hay una serie temporal validada.")
    
    @app.post("/api/v1/ai/analyze")
    async def legacy_analyze(payload:AnalysisRequest):
        raise HTTPException(409,"Calcula /api/v1/metrics y envía su result_id a /api/v1/ai/interpret.")
    
    @app.get("/api/v1/multiregion/comparacion")
    def multi(): raise HTTPException(409,"Analiza cada región con área y fechas explícitas mediante /api/v1/metrics.")
    
    @app.post("/api/v1/metrics")
    async def metrics(payload:MetricsRequest):
        if app.state.busy: raise HTTPException(429,"Hay un análisis en curso.")
        app.state.busy=True
        try:
            result=await asyncio.to_thread(calculate,payload)
            now=time.time()
            app.state.results={k:v for k,v in app.state.results.items() if now-v[0]<3600}
            while len(app.state.results)>=20: app.state.results.pop(next(iter(app.state.results)))
            result_id=uuid.uuid4().hex
            result.update(result_id=result_id,selection=payload.model_dump(mode="json"))
            app.state.results[result_id]=(now,result)
            return result
        except DataUnavailable as e: raise HTTPException(422,str(e)) from e
        except Exception as e:
            import logging
            logging.exception("Error de análisis")
            raise HTTPException(502,"No se pudo procesar el producto. Revisa el formato y el registro del servidor.") from e
        finally: app.state.busy=False
        
    @app.post("/api/v1/ai/interpret")
    async def interpret(payload:InterpretRequest):
        item=app.state.results.get(payload.result_id)
        if not item or time.time()-item[0]>=3600: raise HTTPException(404,"El resultado expiró. Vuelve a calcular.")
        context={k:v for k,v in item[1].items() if k not in ("map","map_a","map_b","points","snapshots")}
        
        # 👇 AQUÍ ESTÁ EL CAMBIO: Unimos la pregunta con el contexto del usuario
        pregunta_final = payload.question
        if payload.user_context:
            pregunta_final += f"\n\n[CONTEXTO DEL USUARIO]: El usuario indica lo siguiente sobre su situación: '{payload.user_context}'. Por favor, responde explicando cómo le afecta esto directamente a él o a su comunidad."
            
        try:
            report=await app.state.gemini.analyze(context, pregunta_final)
            return {"analysis":report.model_dump(),"notice":"Interpretación de IA; las métricas se conservan por separado.","model":settings.gemini_model}
        except GeminiServiceError as e: raise HTTPException(e.status_code,str(e)) from e
        
    return app
app=create_app()