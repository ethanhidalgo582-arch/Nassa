"""Gemini explains backend metrics. It never measures, never invents numbers.

The model only receives the computed facts (no imagery, no coordinates list) and must
answer five questions in the requested language. Every number in its answer is checked
against the numbers present in the facts; unknown numbers are reported to the user.
"""
from __future__ import annotations

import json
import re

from errors import AnalysisError, not_configured

FIELDS = ("what_changed", "how_much", "pattern", "meaning")

PROMPT = {
    "es": """Eres un divulgador científico. Explica a una persona sin formación técnica los resultados de un análisis satelital.
Usa EXCLUSIVAMENTE los datos del bloque HECHOS. Reglas obligatorias:
- No inventes mediciones, porcentajes, niveles de confianza, causas concretas, riesgos ni recomendaciones de seguridad.
- Copia las cifras tal como aparecen en HECHOS (puedes redondearlas) y menciona siempre su unidad y el período.
- Si un dato falta, dilo; no lo supongas. La ausencia de datos no es ausencia de cambio.
- Respeta las limitaciones indicadas: si es desplazamiento en la línea de visión, no lo llames hundimiento vertical medido; si es pérdida de cobertura arbórea, no la llames deforestación confirmada.
- Lenguaje cotidiano, frases cortas, sin jerga. Responde en español.
Responde en JSON con estas claves: summary (2-3 frases), what_changed (¿qué cambió?), how_much (¿cuánto y en qué período?),
pattern (¿qué patrón permiten observar los datos?), meaning (¿qué podría significar para comprender el terreno?, como posibilidad, no como conclusión),
cannot_conclude (lista de 2-4 cosas que NO pueden concluirse).""",
    "en": """You explain satellite analysis results to a non-specialist audience.
Use ONLY the data in the FACTS block. Mandatory rules:
- Do not invent measurements, percentages, confidence levels, specific causes, risks or safety advice.
- Copy figures as they appear in FACTS (you may round them) and always state their unit and period.
- If something is missing, say so; do not assume it. Missing data is not absence of change.
- Respect the stated limitations: line-of-sight displacement is not measured vertical subsidence; tree-cover loss is not confirmed deforestation.
- Everyday language, short sentences, no jargon. Answer in English.
Answer in JSON with keys: summary (2-3 sentences), what_changed, how_much (how much and over which period),
pattern (what pattern the data show), meaning (what it could mean for understanding the land, as a possibility, not a conclusion),
cannot_conclude (list of 2-4 things that can NOT be concluded).""",
}


def facts_for(result: dict, locale: str) -> dict:
    """Compact, model-safe view of a result (no imagery, no grids, no geometry)."""
    keep = ("module", "period", "parameters", "metrics", "geometry", "stats_scope", "series", "annual_loss",
            "available_pairs")
    out = {k: result[k] for k in keep if k in result}
    out["measurement"] = result.get("measurement", {}).get(locale)
    out["source"] = {k: v for k, v in result.get("source", {}).items() if k != "products"}
    out["limitations"] = result.get("limitations", {}).get(locale, [])
    if "pairs" in result:
        out["pairs"] = [{k: p.get(k) for k in ("reference_date", "secondary_date", "days", "median_los_mm",
                                                "spatial_std_mm", "valid_coverage_pct", "mean_coherence")}
                        for p in result["pairs"]]
    if "summary" in result:
        out["backend_summary"] = {k: v for k, v in result["summary"].get(locale, {}).items() if k != "speech"}
    for k in ("stats_scope",):
        if isinstance(out.get(k), dict):
            out[k] = out[k].get(locale)
    if isinstance(out.get("metrics", {}).get("loss_pct_denominator"), dict):
        out["metrics"] = dict(out["metrics"])
        out["metrics"]["loss_pct_denominator"] = out["metrics"]["loss_pct_denominator"][locale]
    return out


_NUM = re.compile(r"(?<![\w.])[-+−]?\d+(?:[.,]\d+)?")


def _numbers_in(obj, acc: set[float]):
    if isinstance(obj, bool) or obj is None:
        return
    if isinstance(obj, (int, float)):
        acc.add(abs(float(obj)))
    elif isinstance(obj, str):
        for t in _NUM.findall(re.sub(r"(\d)[\s  ](\d{3})\b", r"\1\2", obj)):
            acc.add(abs(float(t.replace(",", ".").replace("−", "-"))))
    elif isinstance(obj, dict):
        for v in obj.values():
            _numbers_in(v, acc)
    elif isinstance(obj, (list, tuple)):
        for v in obj:
            _numbers_in(v, acc)


def unverified_numbers(text: str, facts: dict) -> list[str]:
    allowed: set[float] = set()
    _numbers_in(facts, allowed)
    found = []
    clean = re.sub(r"(\d)[\s  ](\d{3})\b", r"\1\2", text)
    for token in _NUM.findall(clean):
        v = abs(float(token.replace(",", ".").replace("−", "-")))
        decimals = len(token.split(".")[-1]) if "." in token else (len(token.split(",")[-1]) if "," in token else 0)
        tol = 0.5 * 10 ** (-decimals) + 1e-9
        ok = v <= 10 or any(abs(v - a) <= max(tol, 0.01 * a) for a in allowed)
        if not ok:
            found.append(token)
    return sorted(set(found))


def interpret(result: dict, locale: str, settings) -> dict:
    if not settings.gemini_configured:
        raise not_configured(
            "La interpretación con IA no está configurada en el servidor (falta GEMINI_API_KEY). El resumen calculado sigue disponible.",
            "AI interpretation is not configured on the server (GEMINI_API_KEY missing). The computed summary is still available.",
        )
    from google import genai
    from google.genai import types

    facts = facts_for(result, locale)
    schema = types.Schema(
        type=types.Type.OBJECT,
        properties={
            "summary": types.Schema(type=types.Type.STRING),
            **{k: types.Schema(type=types.Type.STRING) for k in FIELDS},
            "cannot_conclude": types.Schema(type=types.Type.ARRAY, items=types.Schema(type=types.Type.STRING)),
        },
        required=["summary", *FIELDS, "cannot_conclude"],
    )
    try:
        client = genai.Client(
            api_key=settings.gemini_api_key,
            http_options=types.HttpOptions(timeout=int(settings.gemini_timeout_seconds * 1000)),
        )
        response = client.models.generate_content(
            model=settings.gemini_model,
            contents=PROMPT[locale] + "\n\nHECHOS / FACTS:\n" + json.dumps(facts, ensure_ascii=False, default=str),
            config=types.GenerateContentConfig(
                response_mime_type="application/json", response_schema=schema, temperature=0.2,
            ),
        )
        data = json.loads(response.text or "{}")
    except Exception as e:  # network, quota, auth, malformed JSON — never leak the key or raw error
        raise AnalysisError(
            "provider_error",
            "Gemini no respondió correctamente. El resumen calculado sigue disponible; vuelve a intentarlo más tarde.",
            "Gemini did not answer correctly. The computed summary is still available; try again later.",
            retryable=True,
        ) from e
    answer = {k: str(data.get(k, "")).strip() for k in ("summary", *FIELDS)}
    cc = data.get("cannot_conclude") or []
    answer["cannot_conclude"] = [str(x).strip() for x in cc if str(x).strip()][:5]
    if not answer["summary"]:
        raise AnalysisError("provider_error", "Gemini devolvió una respuesta vacía.", "Gemini returned an empty answer.",
                            retryable=True)
    text = " ".join([*(answer[k] for k in ("summary", *FIELDS)), *answer["cannot_conclude"]])
    bad = unverified_numbers(text, facts)
    return {
        "locale": locale,
        "model": settings.gemini_model,
        "answer": answer,
        "verification": {"ok": not bad, "unverified_numbers": bad},
    }
