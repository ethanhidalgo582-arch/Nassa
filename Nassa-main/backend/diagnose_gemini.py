"""Diagnóstico local: nunca imprime la clave. --generate consume una solicitud."""
import argparse
import asyncio
import json
import re

from google import genai
from google.genai import errors, types
from config import Settings
from data_service import displacement
from gemini_service import GeminiService, GeminiServiceError

settings = Settings.from_env()


def show_error(exc):
    message = str(getattr(exc, "message", str(exc)) or "")
    if settings.gemini_api_key:
        message = message.replace(settings.gemini_api_key, "[REDACTED]")
    message = re.sub(r"[A-Za-z0-9_-]{30,}", "[REDACTED]", message)
    print(json.dumps({"code": getattr(exc, "code", None), "message": message[:1000]}, ensure_ascii=True))


async def generate():
    service = GeminiService(settings)
    try:
        report = await service.analyze(displacement(14.6349, -90.5069), "Explica esta demostración.")
        print(report.model_dump_json())
    except GeminiServiceError as exc:
        show_error(exc.__cause__ or exc)
    finally:
        await service.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    if not settings.gemini_api_key:
        raise SystemExit("Falta GEMINI_API_KEY.")
    if args.generate:
        asyncio.run(generate())
    else:
        try:
            with genai.Client(api_key=settings.gemini_api_key, vertexai=False,
                              http_options=types.HttpOptions(timeout=20000,
                                  retry_options=types.HttpRetryOptions(attempts=1))) as client:
                model = client.models.get(model=settings.gemini_model)
                print(json.dumps({"status": "ok", "model": model.name}))
        except errors.APIError as exc:
            show_error(exc)

