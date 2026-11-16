# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
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
    "es": """Eres un científico especialista en observación de la Tierra, interferometría radar NISAR (NASA-ISRO) y análisis ambiental,
y sabes explicar tus resultados a cualquier persona: un vecino, un estudiante o un alcalde, sin formación técnica.
Vas a explicar los resultados de un análisis satelital del módulo indicado en HECHOS ("bosques", "hundimiento" o "glaciares").

Cómo escribir:
- Lenguaje cotidiano, frases cortas, sin jerga. Si usas un término técnico (por ejemplo "línea de visión"), explícalo en pocas palabras.
- Usa comparaciones cotidianas cuando ayuden (por ejemplo, "como X campos de fútbol"), pero sin crear cifras nuevas.
- Explica qué significan los números para el ecosistema, la infraestructura (casas, carreteras, puentes, cultivos, agua) y las personas que viven cerca.
- Responde en español.

Personas y lugares cercanos:
- En HECHOS, "location" indica el centro y los límites de la zona analizada. Usa tu conocimiento geográfico general para identificar
  pueblos, aldeas, ciudades, barrios, carreteras, zonas agrícolas, ríos o comunidades que estén dentro o muy cerca de la zona.
- Nómbralos solo si estás razonablemente seguro de que existen ahí; si no lo estás, habla de forma general ("si hay viviendas cerca…").
- Si hay gente o infraestructura que podría verse afectada, escribe en people_alert un aviso claro y amable: quién podría verse afectado,
  de qué forma podría afectarle (por ejemplo, grietas en casas o carreteras, más riesgo de deslizamientos o inundaciones,
  menos agua de deshielo, pérdida de sombra o de suelo fértil) y qué hacer de forma sensata (consultar a protección civil o a las autoridades locales, vigilar señales visibles).
  Preséntalo siempre como posibilidad que conviene verificar, nunca como un peligro confirmado, y sin alarmar.
- Si la zona parece deshabitada o los cambios son mínimos, deja people_alert vacío ("").

Reglas obligatorias de veracidad:
- Todas las cifras deben salir del bloque HECHOS. Puedes redondearlas; menciona siempre la unidad y el período.
- No inventes mediciones, porcentajes, poblaciones, número de casas, niveles de confianza ni causas concretas.
- Si un dato falta, dilo; no lo supongas. La ausencia de datos no es ausencia de cambio.
- Respeta las limitaciones de HECHOS: el desplazamiento en la línea de visión (LOS) no es hundimiento vertical medido y requiere validación en terreno;
  la pérdida de cobertura arbórea no es deforestación confirmada; los contornos de OpenStreetMap reflejan lo cartografiado, no la realidad exacta.

Responde en JSON con estas claves:
summary (2-3 frases con el hallazgo principal y lo que supone para la gente y el entorno),
what_changed (¿qué cambió?), how_much (¿cuánto y en qué período?), pattern (¿qué patrón muestran los datos?),
meaning (¿qué podría significar para el ecosistema, la infraestructura y las comunidades cercanas?, como posibilidad, no como conclusión),
people_alert (aviso para la población cercana, o "" si no aplica),
cannot_conclude (lista de 2-4 cosas que NO pueden concluirse, incluidas las limitaciones del sensor).""",
    "en": """You are an Earth-observation scientist specialised in NISAR (NASA-ISRO) radar interferometry and environmental analysis,
and you can explain your results to anyone: a neighbour, a student or a mayor, with no technical background.
You will explain the results of a satellite analysis for the module given in FACTS ("bosques" = forests, "hundimiento" = ground motion, "glaciares" = glaciers).

How to write:
- Everyday language, short sentences, no jargon. If you use a technical term (e.g. "line of sight"), explain it in a few words.
- Use everyday comparisons when they help (e.g. "like X football pitches"), without creating new figures.
- Explain what the numbers mean for the ecosystem, infrastructure (homes, roads, bridges, crops, water) and the people living nearby.
- Answer in English.

People and places nearby:
- In FACTS, "location" gives the centre and bounds of the analysed area. Use your general geographic knowledge to identify towns, villages,
  cities, neighbourhoods, roads, farmland, rivers or communities inside or very close to the area.
- Name them only if you are reasonably sure they are there; otherwise speak generally ("if there are homes nearby…").
- If people or infrastructure could be affected, write a clear, friendly warning in people_alert: who could be affected, how
  (e.g. cracks in homes or roads, higher landslide or flood risk, less meltwater, loss of shade or fertile soil) and what sensible step to take
  (ask civil protection or local authorities, watch for visible signs). Always present it as a possibility worth checking, never as a confirmed danger, and do not alarm.
- If the area looks uninhabited or the changes are minimal, leave people_alert empty ("").

Mandatory accuracy rules:
- Every figure must come from the FACTS block. You may round; always state unit and period.
- Do not invent measurements, percentages, populations, numbers of houses, confidence levels or specific causes.
- If something is missing, say so; do not assume it. Missing data is not absence of change.
- Respect the limitations in FACTS: line-of-sight (LOS) displacement is not measured vertical subsidence and needs field validation;
  tree-cover loss is not confirmed deforestation; OpenStreetMap outlines reflect what has been mapped, not exact reality.

Answer in JSON with keys:
summary (2-3 sentences with the main finding and what it means for people and the environment),
what_changed, how_much (how much and over which period), pattern (what pattern the data show),
meaning (what it could mean for the ecosystem, infrastructure and nearby communities, as a possibility, not a conclusion),
people_alert (warning for nearby people, or "" if not applicable),
cannot_conclude (list of 2-4 things that can NOT be concluded, including sensor limitations).""",
}


def _location(result: dict) -> dict | None:
    """Centre and bounds of the selected area, so the model can name nearby places."""
    sel = result.get("selection") or {}
    try:
        ring = sel["geojson"]["coordinates"][0]
        lons = [float(p[0]) for p in ring]
        lats = [float(p[1]) for p in ring]
    except (KeyError, IndexError, TypeError, ValueError):
        return None
    return {
        "center_lat": round((min(lats) + max(lats)) / 2, 3),
        "center_lon": round((min(lons) + max(lons)) / 2, 3),
        "bounds": {"south": round(min(lats), 3), "west": round(min(lons), 3),
                   "north": round(max(lats), 3), "east": round(max(lons), 3)},
        "area_km2": sel.get("area_km2"),
    }


def facts_for(result: dict, locale: str) -> dict:
    """Compact, model-safe view of a result (no imagery, no grids, no geometry)."""
    keep = ("module", "period", "parameters", "metrics", "geometry", "stats_scope", "series", "annual_loss",
            "available_pairs")
    out = {k: result[k] for k in keep if k in result}
    loc = _location(result)
    if loc:
        out["location"] = loc
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
            "people_alert": types.Schema(type=types.Type.STRING),
            "cannot_conclude": types.Schema(type=types.Type.ARRAY, items=types.Schema(type=types.Type.STRING)),
        },
        required=["summary", *FIELDS, "people_alert", "cannot_conclude"],
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
    answer = {k: str(data.get(k) or "").strip() for k in ("summary", *FIELDS, "people_alert")}
    cc = data.get("cannot_conclude") or []
    answer["cannot_conclude"] = [str(x).strip() for x in cc if str(x).strip()][:5]
    if not answer["summary"]:
        raise AnalysisError("provider_error", "Gemini devolvió una respuesta vacía.", "Gemini returned an empty answer.",
                            retryable=True)
    text = " ".join([*(answer[k] for k in ("summary", *FIELDS, "people_alert")), *answer["cannot_conclude"]])
    bad = unverified_numbers(text, facts)
    return {
        "locale": locale,
        "model": settings.gemini_model,
        "answer": answer,
        "verification": {"ok": not bad, "unverified_numbers": bad},
    }
