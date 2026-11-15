import asyncio
import json
import logging

import httpx
from google import genai
from google.genai import errors, types
from pydantic import ValidationError

from config import Settings
from schemas import AnalysisReport

SYSTEM_INSTRUCTION_BASE = """Actúa como un analista geoespacial experto y comunicador empático. Tu objetivo es explicar los datos satelitales de forma directa, sencilla y fácil de entender a primera vista, evitando textos largos o confusos.

Reglas obligatorias para tu respuesta:
1. NOMBRES EXACTOS DE LUGARES, ZONAS Y COMUNIDADES: 
   - En **BOSQUES**: Menciona explícitamente los estados, departamentos, municipios, reservas naturales y comunidades afectadas, incluyendo las **especies animales en peligro de extinción** propias de esa región.
   - En **GLACIARES**: Menciona el nombre del glaciar, las áreas críticas cercanas y qué **lugares, zonas costeras o comunidades están en riesgo de inundación o de hundirse** por el incremento del nivel del mar.
   - En **HUNDIMIENTO**: Identifica y nombra explícitamente los **municipios, alcaldías, zonas urbanas, colonias, barrios o estados afectados** por el descenso o colapso del terreno (por ejemplo, especificando zonas o alcaldías críticas si es en Ciudad de México, Yakarta u otra región analizada).
2. ENFÓCATE EN EL IMPACTO HUMANO Y NATURAL: Explica de forma clara y cercana qué significa esto para las personas, sus viviendas, carreteras, agua y seguridad local.
3. EXPLICACIONES CLARAS Y DIRECTAS: Ve directo al grano con la información más importante. Organiza el contenido usando listas y puntos clave para que se lea fácilmente a vista rápida, evitando textos complejos o técnicos.
4. HONESTIDAD: Si los datos muestran algo incierto, dilo de forma constructiva. Nunca inventes nombres de lugares ni datos falsos.

Devuelve tu respuesta estrictamente en el formato JSON solicitado (summary, observations, limitations, suggested_next_steps)."""

logger = logging.getLogger(__name__)

class GeminiServiceError(Exception):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code

class GeminiService:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.client = genai.Client(
            api_key=settings.gemini_api_key,
            vertexai=False,
            http_options=types.HttpOptions(
                api_version='v1',
                timeout=int(settings.gemini_timeout_seconds * 1000),
                retry_options=types.HttpRetryOptions(attempts=1),
            ),
        )

    async def close(self):
        if self.client is not None:
            await self.client.aio.aclose()
            self.client.close()

    async def analyze(self, context: dict, question: str, locale: str = "es") -> AnalysisReport:
        if self.client is None:
            raise GeminiServiceError(503, "Gemini aún no está configurado en el servidor.")
            
        idioma = "inglés" if locale == "en" else "español"
        system_instruction = f"IMPORTANTE: Responde estrictamente en {idioma} con lenguaje simple, incluyendo obligatoriamente nombres de municipios, zonas, colonias y comunidades afectadas tanto para bosques, glaciares como para hundimientos.\n\n" + SYSTEM_INSTRUCTION_BASE

        try:
            async with asyncio.timeout(self.settings.gemini_timeout_seconds):
                response = await self.client.aio.models.generate_content(
                    model=self.settings.gemini_model,
                    contents=json.dumps({"context": context, "question": question}, ensure_ascii=False),
                    config=types.GenerateContentConfig(
                        system_instruction=system_instruction,
                        response_mime_type="application/json",
                        response_schema=AnalysisReport,
                        max_output_tokens=4096,
                        candidate_count=1,
                        temperature=0.3, 
                    ),
                )
        except (TimeoutError, httpx.TimeoutException) as exc:
            logger.error("Gemini timeout: %s", exc)
            raise GeminiServiceError(504, "Gemini tardó demasiado. Intenta nuevamente.") from exc
        except errors.APIError as exc:
            logger.error(
                "Gemini APIError code=%s status=%s message=%s",
                getattr(exc, "code", None),
                getattr(exc, "status", None),
                str(getattr(exc, "message", str(exc)))[:500],
            )
            if exc.code == 429:
                raise GeminiServiceError(429, "Se alcanzó el límite de uso de Gemini. Intenta más tarde.") from exc
            if exc.code in (400, 401, 403, 404):
                raise GeminiServiceError(503, "Revisa la clave, los permisos y el modelo de Gemini en el servidor.") from exc
            raise GeminiServiceError(502, "Gemini no está disponible en este momento.") from exc
        except httpx.RequestError as exc:
            logger.error("Gemini request error: %s", exc)
            raise GeminiServiceError(502, "No se pudo conectar con Gemini.") from exc
        try:
            if not response.text:
                raise ValueError("Respuesta vacía o bloqueada")
            return AnalysisReport.model_validate_json(response.text)
        except (ValidationError, ValueError) as exc:
            logger.error("Gemini respuesta inválida: %s", str(exc)[:500])
            raise GeminiServiceError(502, "Gemini no devolvió un análisis válido. Intenta nuevamente.") from exc