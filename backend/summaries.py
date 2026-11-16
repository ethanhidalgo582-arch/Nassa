# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Deterministic, bilingual summaries built only from backend metrics.

The same text is shown on screen and read aloud. A "speech" variant spells out units
and dates so that speech synthesis reads them naturally ("12,5 milímetros",
"21 de julio de 2026") instead of symbols ("12.5 mm", "2026-07-21").
"""
from __future__ import annotations

from datetime import date

MONTHS = {
    "es": ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
           "octubre", "noviembre", "diciembre"],
    "en": ["January", "February", "March", "April", "May", "June", "July", "August", "September",
           "October", "November", "December"],
}
UNITS = {
    "mm": {"es": ("mm", "milímetros"), "en": ("mm", "millimetres")},
    "ha": {"es": ("ha", "hectáreas"), "en": ("ha", "hectares")},
    "%": {"es": ("%", "por ciento"), "en": ("%", "percent")},
    "mm/yr": {"es": ("mm/año", "milímetros por año"), "en": ("mm/yr", "millimetres per year")},
    "m/yr": {"es": ("m/año", "metros por año"), "en": ("m/yr", "metres per year")},
    "km2": {"es": ("km²", "kilómetros cuadrados"), "en": ("km²", "square kilometres")},
    "days": {"es": ("días", "días"), "en": ("days", "days")},
}


def num(v: float, lang: str, decimals: int = 1, speech: bool = False) -> str:
    r = round(float(v), decimals)
    if r == 0:
        r = 0.0
    text = f"{r:,.{decimals}f}"
    if decimals:
        text = text.rstrip("0").rstrip(".")
    if speech:
        text = text.replace(",", "")  # "12345" is read as one number; "12 345" would not be
    elif lang == "es":
        text = text.replace(",", "\u202f")  # narrow no-break space for thousands
    if lang == "es":
        text = text.replace(".", ",")
    return text


def q(v, unit: str, lang: str, speech: bool, decimals: int = 1, signed: bool = False) -> str:
    sym, word = UNITS[unit][lang]
    s = num(v, lang, decimals, speech)
    if signed and v > 0:
        s = "+" + s
    if speech and s.startswith("-"):
        s = ("menos " if lang == "es" else "minus ") + s[1:]
    return f"{s} {word}" if speech else (f"{s}{sym}" if unit == "%" and lang == "en" else f"{s} {sym}")


def day(iso: str, lang: str, speech: bool) -> str:
    d = date.fromisoformat(iso)
    if not speech:
        return d.strftime("%d/%m/%Y") if lang == "es" else d.isoformat()
    m = MONTHS[lang][d.month - 1]
    return f"{d.day} de {m} de {d.year}" if lang == "es" else f"{m} {d.day}, {d.year}"


def _build(lang: str, speech: bool, module: str, r: dict) -> dict:
    fn = {"bosques": _forest, "hundimiento": _subsidence, "glaciares": _glacier}[module]
    headline, points = fn(lang, speech, r)
    return {"headline": headline, "points": points}


def build(result: dict) -> dict:
    out = {}
    for lang in ("es", "en"):
        screen = _build(lang, False, result["module"], result)
        spoken = _build(lang, True, result["module"], result)
        out[lang] = {**screen, "speech": " ".join([spoken["headline"], *spoken["points"]])}
    return out


# ---------------------------------------------------------------------------

def _forest(lang, sp, r):
    m = r["metrics"]
    a, b = r["period"]["start_year"], r["period"]["end_year"]
    thr = r["parameters"]["canopy_threshold_pct"]
    es = lang == "es"
    span = (f"entre {a} y {b}" if a != b else f"en {a}") if es else (f"between {a} and {b}" if a != b else f"in {a}")
    if m["forest_start_ha"] <= 0:
        head = (f"Hansen GFC no registra bosque con dosel de al menos {thr} % en esta área al inicio de {a}; no hay base para medir pérdida."
                if es else f"Hansen GFC records no forest with at least {thr} % canopy here at the start of {a}; there is no baseline to measure loss.")
        return head, []
    if m["loss_ha"] <= 0:
        head = (f"No se detectó pérdida de cobertura arbórea {span} en los datos válidos del área."
                if es else f"No tree-cover loss was detected {span} in the valid data of the area.")
    else:
        pct = m["loss_pct_of_forest_start"]
        head = (f"Se detectó pérdida de cobertura arbórea en {q(m['loss_ha'], 'ha', lang, sp, 0)} {span}, "
                f"el {q(pct, '%', lang, sp)} del bosque que había al inicio de {a} ({q(m['forest_start_ha'], 'ha', lang, sp, 0)})."
                if es else
                f"Tree-cover loss was detected on {q(m['loss_ha'], 'ha', lang, sp, 0)} {span}, "
                f"{q(pct, '%', lang, sp)} of the forest present at the start of {a} ({q(m['forest_start_ha'], 'ha', lang, sp, 0)}).")
    pts = []
    if m.get("peak_loss_year"):
        peak = next(x for x in r["annual_loss"] if x["year"] == m["peak_loss_year"])
        pts.append(f"El año con más pérdida fue {peak['year']}, con {q(peak['loss_ha'], 'ha', lang, sp, 0)}."
                   if es else f"The year with most loss was {peak['year']}, with {q(peak['loss_ha'], 'ha', lang, sp, 0)}.")
    pts.append(
        f"Hay datos válidos en el {q(m['valid_data_pct'], '%', lang, sp)} del área seleccionada ({q(m['selected_area_ha'], 'ha', lang, sp, 0)})."
        if es else f"Valid data cover {q(m['valid_data_pct'], '%', lang, sp)} of the selected area ({q(m['selected_area_ha'], 'ha', lang, sp, 0)}).")
    pts.append("Es pérdida de cobertura arbórea compatible con deforestación, no deforestación confirmada: también incluye incendios, tormentas y cosecha de plantaciones."
               if es else "This is tree-cover loss compatible with deforestation, not confirmed deforestation: it also includes fire, storms and plantation harvest.")
    return head, pts


def _direction(v, noise, lang, kind="ground"):
    es = lang == "es"
    if noise is not None and abs(v) <= noise:
        return "no mostró un cambio distinguible del ruido estimado" if es else "showed no change distinguishable from the estimated noise"
    if v < 0:
        return ("se alejó del satélite (compatible con hundimiento)" if kind == "ground" else "se alejó del satélite") if es \
            else ("moved away from the satellite (consistent with subsidence)" if kind == "ground" else "moved away from the satellite")
    return ("se acercó al satélite (compatible con elevación del terreno)" if kind == "ground" else "se acercó al satélite") if es \
        else ("moved towards the satellite (consistent with uplift)" if kind == "ground" else "moved towards the satellite")


def _subsidence(lang, sp, r):
    m, p = r["metrics"], r["period"]
    es = lang == "es"
    cum = m["cumulative_los_mm"]
    noise = m.get("uncertainty_indicative_mm")
    head = (f"Entre el {day(p['start'], lang, sp)} y el {day(p['end'], lang, sp)} ({p['days']} días, {m['observations']} fechas de observación), "
            f"la zona {_direction(cum, noise, lang)}: {q(cum, 'mm', lang, sp, signed=True)} en la línea de visión, mediana relativa al entorno."
            if es else
            f"Between {day(p['start'], lang, sp)} and {day(p['end'], lang, sp)} ({p['days']} days, {m['observations']} observation dates), "
            f"the area {_direction(cum, noise, lang)}: {q(cum, 'mm', lang, sp, signed=True)} along the line of sight, median relative to its surroundings.")
    pts = []
    if m.get("rate_los_mm_per_year") is not None:
        if m["rate_method"] == "linear_fit":
            pts.append(f"Ritmo estimado con un ajuste lineal: {q(m['rate_los_mm_per_year'], 'mm/yr', lang, sp, signed=True)}."
                       if es else f"Rate estimated with a linear fit: {q(m['rate_los_mm_per_year'], 'mm/yr', lang, sp, signed=True)}.")
        else:
            pts.append(f"Con solo dos fechas, el ritmo medio equivalente sería {q(m['rate_los_mm_per_year'], 'mm/yr', lang, sp, signed=True)}; no indica si el cambio fue gradual."
                       if es else f"With only two dates, the equivalent average rate would be {q(m['rate_los_mm_per_year'], 'mm/yr', lang, sp, signed=True)}; it does not show whether the change was gradual.")
    if m.get("cumulative_vertical_estimate_mm") is not None:
        pts.append(f"Si no hubiera movimiento horizontal, equivaldría a unos {q(m['cumulative_vertical_estimate_mm'], 'mm', lang, sp, signed=True)} en vertical."
                   if es else f"Assuming no horizontal motion, this would equal about {q(m['cumulative_vertical_estimate_mm'], 'mm', lang, sp, signed=True)} vertically.")
    if noise:
        pts.append(f"Nivel de ruido orientativo de la referencia: ±{q(noise, 'mm', lang, sp)}."
                   if es else f"Indicative reference noise level: ±{q(noise, 'mm', lang, sp)}.")
    lo, hi = m.get("valid_coverage_pct_min"), m.get("valid_coverage_pct_max")
    if lo is not None:
        cov = q(lo, '%', lang, sp) if lo == hi else (f"entre {q(lo, '%', lang, sp)} y {q(hi, '%', lang, sp)}" if es else f"between {q(lo, '%', lang, sp)} and {q(hi, '%', lang, sp)}")
        pts.append(f"Píxeles válidos: {cov} del área en cada período." if es else f"Valid pixels: {cov} of the area in each period.")
    return head, pts


def _glacier(lang, sp, r):
    m, p = r["metrics"], r["period"]
    es = lang == "es"
    med = m["median_los_mm"]
    ref = ("la roca fuera del glaciar" if m.get("reference") == "off_glacier" else "el entorno del área") if es else \
          ("off-glacier rock" if m.get("reference") == "off_glacier" else "the surroundings of the area")
    head = (f"Entre el {day(p['start'], lang, sp)} y el {day(p['end'], lang, sp)} ({p['days']} días), la mediana del hielo medido "
            f"{_direction(med, m.get('reference_noise_mm'), lang, 'ice')}: {q(med, 'mm', lang, sp, signed=True)} en la línea de visión, respecto a {ref}."
            if es else
            f"Between {day(p['start'], lang, sp)} and {day(p['end'], lang, sp)} ({p['days']} days), the median of the measured ice "
            f"{_direction(med, m.get('reference_noise_mm'), lang, 'ice')}: {q(med, 'mm', lang, sp, signed=True)} along the line of sight, relative to {ref}.")
    pts = []
    if m.get("p10_los_mm") is not None:
        pts.append(f"El 80 % central de los píxeles está entre {q(m['p10_los_mm'], 'mm', lang, sp)} y {q(m['p90_los_mm'], 'mm', lang, sp)}."
                   if es else f"The central 80 % of pixels lie between {q(m['p10_los_mm'], 'mm', lang, sp)} and {q(m['p90_los_mm'], 'mm', lang, sp)}.")
    if m.get("p90_abs_rate_los_m_per_year") is not None:
        pts.append(f"A ese ritmo, el 10 % más rápido superaría {q(m['p90_abs_rate_los_m_per_year'], 'm/yr', lang, sp, 2)} en la línea de visión."
                   if es else f"At that pace, the fastest 10 % would exceed {q(m['p90_abs_rate_los_m_per_year'], 'm/yr', lang, sp, 2)} along the line of sight.")
    pts.append(f"Píxeles válidos: {q(m['valid_coverage_pct'], '%', lang, sp)} del área; las zonas sin datos suelen ser las de hielo más rápido."
               if es else f"Valid pixels: {q(m['valid_coverage_pct'], '%', lang, sp)} of the area; no-data zones are often the fastest ice.")
    return head, pts
