import asyncio
import json

import httpx
from google import genai
from google.genai import errors, types
from pydantic import ValidationError

from config import Settings
from schemas import AnalysisReport

SYSTEM_INSTRUCTION = """Explica en español sencillo exclusivamente las métricas del contexto.
Distingue observaciones, cálculos y supuestos. Nunca inventes riesgo, causalidad o confianza.
LOS no equivale a hundimiento vertical. Una proyección vertical depende de supuestos y no prueba hundimiento.
Una diferencia de cartografía OSM no demuestra deforestación. Respeta todas las limitaciones del contexto.
No conviertas datos faltantes en ceros. No inventes tendencias ni atribuyas datos OSM a NISAR.
Devuelve summary, observations, limitations y suggested_next_steps conforme al esquema."""


class GeminiServiceError(Exception):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


class GeminiService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = (
            genai.Client(
                api_key=settings.gemini_api_key,
                vertexai=False,
                http_options=types.HttpOptions(
                    timeout=int(settings.gemini_timeout_seconds * 1000),
                    retry_options=types.HttpRetryOptions(attempts=1),
                ),
            )
            if settings.gemini_api_key else None
        )

    async def close(self):
        if self.client is not None:
            await self.client.aio.aclose()
            self.client.close()

    async def analyze(self, context: dict, question: str) -> AnalysisReport:
        if self.client is None:
            raise GeminiServiceError(503, "Gemini aún no está configurado en el servidor.")
        try:
            async with asyncio.timeout(self.settings.gemini_timeout_seconds):
                response = await self.client.aio.models.generate_content(
                    model=self.settings.gemini_model,
                    contents=json.dumps({"context": context, "question": question}, ensure_ascii=False),
                    config=types.GenerateContentConfig(
                        system_instruction=SYSTEM_INSTRUCTION,
                        response_mime_type="application/json",
                        response_schema=AnalysisReport,
                        max_output_tokens=4096,
                        candidate_count=1,
                    ),
                )
        except (TimeoutError, httpx.TimeoutException) as exc:
            raise GeminiServiceError(504, "Gemini tardó demasiado. Intenta nuevamente.") from exc
        except errors.APIError as exc:
            if exc.code == 429:
                raise GeminiServiceError(429, "Se alcanzó el límite de uso de Gemini. Intenta más tarde.") from exc
            if exc.code in (400, 401, 403, 404):
                raise GeminiServiceError(503, "Revisa la clave, los permisos y el modelo de Gemini en el servidor.") from exc
            raise GeminiServiceError(502, "Gemini no está disponible en este momento.") from exc
        except httpx.RequestError as exc:
            raise GeminiServiceError(502, "No se pudo conectar con Gemini.") from exc
        try:
            if not response.text:
                raise ValueError("Respuesta vacía o bloqueada")
            return AnalysisReport.model_validate_json(response.text)
        except (ValidationError, ValueError) as exc:
            raise GeminiServiceError(502, "Gemini no devolvió un análisis válido. Intenta nuevamente.") from exc
