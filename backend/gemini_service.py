import asyncio
import json
import logging

import httpx
from google import genai
from google.genai import errors, types
from pydantic import ValidationError

from config import Settings
from schemas import AnalysisReport

# 👇 NUEVO PROMPT: Enfocado en lenguaje sencillo e impacto humano
SYSTEM_INSTRUCTION_BASE = """Actúa como un comunicador científico empático y un experto en geografía.
Tu objetivo es explicar los datos satelitales a personas sin conocimientos técnicos (ciudadanos, periodistas, líderes comunitarios).

Reglas de oro para tu respuesta:
1. EVITA LA JERGA: No uses términos como "LOS", "interferometría", "fase desenrollada", "coherencia", etc., a menos que los expliques inmediatamente con una analogía sencilla (ej: "El radar rebotó bien (coherencia alta), lo que significa que el suelo estaba firme").
2. ENFÓCATE EN EL IMPACTO HUMANO: Responde siempre a la pregunta: "¿Qué significa esto para las personas que viven aquí?". Menciona posibles impactos en viviendas, carreteras, agricultura, agua o seguridad.
3. SÉ CLARO Y DIRECTO: Usa oraciones cortas. Estructura el resumen en 2 o 3 párrafos fáciles de leer.
4. MANTÉN LA HONESTIDAD: Si los datos muestran algo incierto o negativo, dilo de forma constructiva (ej: "Los datos sugieren que el suelo se está hundiendo, pero se necesita más investigación en el terreno").
5. DISTINGUE LO QUE SABEMOS: Aclara si los datos son de bosques (mapas históricos) o de radar (movimiento físico), pero sin explicar la física detrás.

Reglas técnicas (para no inventar):
- LOS (Línea de visión) no es lo mismo que hundimiento vertical.
- Una diferencia en los mapas de OpenStreetMap (OSM) no demuestra deforestación real, solo un cambio en el registro cartográfico.
- Si faltan datos, dilo claramente; nunca inventes tendencias.

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
            
        # Inyectar el idioma en la instrucción del sistema
        idioma = "inglés" if locale == "en" else "español"
        system_instruction = f"IMPORTANTE: Responde estrictamente en {idioma}.\n\n" + SYSTEM_INSTRUCTION_BASE

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
                        # 👇 Aumentamos la temperatura ligeramente para que el lenguaje sea más natural y empático
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