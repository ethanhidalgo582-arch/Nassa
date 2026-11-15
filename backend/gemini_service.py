"""Gemini AI interpretation service for NISAR and OSM metrics."""
import json
import os
from google import genai
from google.genai import types


def interpret_metrics(context: dict, user_context: str = "", locale: str = "es") -> dict:
    """
    Genera una interpretación clara y científica de las métricas calculadas
    usando Gemini y devuelve un diccionario con 'summary' y 'observations'.
    """
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("Falta GEMINI_API_KEY en el archivo backend/.env.")

    client = genai.Client(api_key=api_key)
    model_name = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

    lang_instruction = (
        "Responde completamente en español."
        if locale == "es"
        else "Respond completely in English."
    )

    prompt = f"""
Eres un científico especialista en observación de la Tierra, interferometría radar NISAR (NASA-ISRO) y análisis ambiental.
Analiza los siguientes datos obtenidos del módulo '{context.get("module", "")}':

Métricas calculadas:
{json.dumps(context, ensure_ascii=False, indent=2)}

Consulta adicional del usuario:
{user_context.strip() if user_context.strip() else "Ninguna consulta adicional."}

Instrucciones:
1. {lang_instruction}
2. Explica de forma clara y accesible qué significan estos números para el ecosistema, la infraestructura o las comunidades humanas cercanas.
3. Menciona siempre las limitaciones técnicas del sensor si están presentes en los datos (por ejemplo, que los datos de OSM reflejan cobertura cartografiada o que los valores LOS requieren validación).
4. Devuelve EXCLUSIVAMENTE un objeto JSON válido con esta estructura exacta:
{{
  "summary": "Un párrafo claro y bien redactado resumiendo el hallazgo principal e impacto humano.",
  "observations": [
    "Punto clave 1 sobre la magnitud o tendencia observada",
    "Punto clave 2 sobre el impacto o zonas vulnerables",
    "Punto clave 3 sobre recomendaciones o limitaciones"
  ]
}}
"""

    response = client.models.generate_content(
        model=model_name,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            temperature=0.3,
        ),
    )

    raw_text = (response.text or "").strip()
    try:
        parsed = json.loads(raw_text)
        summary = str(parsed.get("summary", "")).strip()
        observations = parsed.get("observations", [])
        if not isinstance(observations, list):
            observations = [str(observations)]
        return {
            "summary": summary or raw_text,
            "observations": [str(item) for item in observations],
        }
    except Exception:
        return {
            "summary": raw_text,
            "observations": [],
        }