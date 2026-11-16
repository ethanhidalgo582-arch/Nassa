# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Glacier outlines mapped in OpenStreetMap (natural=glacier), clipped to the selection.

Used as a thematic layer and to separate on-ice from off-ice pixels. OSM outlines are
volunteer mapping (ODbL): their date and accuracy vary and they are not a NISAR product.
"""
from __future__ import annotations

import time

from shapely.geometry import LineString, MultiPolygon, Polygon, mapping
from shapely.ops import polygonize, unary_union

from geo import Selection, equal_area_km2

OVERPASS_URLS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]
_CACHE: dict[tuple, tuple[float, dict | None]] = {}


def _ways_to_polys(elements):
    nodes = {e["id"]: (e["lon"], e["lat"]) for e in elements if e["type"] == "node"}
    ways = {e["id"]: e for e in elements if e["type"] == "way"}
    polys = []
    used_in_rel = set()
    for rel in (e for e in elements if e["type"] == "relation"):
        outer, inner = [], []
        for m in rel.get("members", []):
            w = ways.get(m.get("ref")) if m.get("type") == "way" else None
            if not w:
                continue
            used_in_rel.add(w["id"])
            coords = [nodes[n] for n in w.get("nodes", []) if n in nodes]
            if len(coords) >= 2:
                (inner if m.get("role") == "inner" else outer).append(LineString(coords))
        outs = list(polygonize(outer))
        ins = list(polygonize(inner))
        for o in outs:
            for i in ins:
                if o.contains(i):
                    o = o.difference(i)
            polys.append(o)
    for w in ways.values():
        if w["id"] in used_in_rel or w.get("tags", {}).get("natural") != "glacier":
            continue
        coords = [nodes[n] for n in w.get("nodes", []) if n in nodes]
        if len(coords) >= 4 and coords[0] == coords[-1]:
            p = Polygon(coords)
            polys.append(p if p.is_valid else p.buffer(0))
    return polys


def fetch(sel: Selection, user_agent: str) -> dict | None:
    """Return {'features', 'union', 'area_km2', 'source'} or None if unavailable (never zero by default)."""
    import httpx

    west, south, east, north = sel.bounds
    key = tuple(round(v, 4) for v in (west, south, east, north))
    hit = _CACHE.get(key)
    if hit and time.time() - hit[0] < 3600:
        return hit[1]
    q = (f'[out:json][timeout:25];(way["natural"="glacier"]({south},{west},{north},{east});'
         f'relation["natural"="glacier"]({south},{west},{north},{east}););(._;>;);out body;')
    data = None
    for url in OVERPASS_URLS:
        try:
            r = httpx.post(url, data={"data": q}, timeout=30, headers={"User-Agent": user_agent})
            r.raise_for_status()
            data = r.json()
            break
        except (httpx.HTTPError, ValueError):
            continue
    if data is None:
        _CACHE[key] = (time.time(), None)
        return None
    polys = [p.intersection(sel.polygon) for p in _ways_to_polys(data.get("elements", []))]
    polys = [p for p in polys if not p.is_empty and p.area > 0]
    union = unary_union(polys) if polys else MultiPolygon()
    if union.geom_type == "GeometryCollection":
        union = unary_union([g for g in union.geoms if g.geom_type in ("Polygon", "MultiPolygon")])
    result = {
        "features": [{"type": "Feature", "geometry": mapping(union.simplify(0.0003, preserve_topology=True)),
                      "properties": {"kind": "glacier"}}] if not union.is_empty else [],
        "union": mapping(union) if not union.is_empty else None,
        "area_km2": round(equal_area_km2(union), 2) if not union.is_empty else 0.0,
        "mapped": not union.is_empty,
        "source": {"name": "OpenStreetMap (natural=glacier)", "license": "ODbL",
                   "attribution": "© OpenStreetMap contributors"},
    }
    _CACHE[key] = (time.time(), result)
    return result
