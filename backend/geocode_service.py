"""Place search through the server (no autocomplete, cached, <= 1 request/second).

Nominatim usage policy: identify the app, max 1 req/s, cache results, no autocomplete.
Photon (komoot) is used as fallback when Nominatim fails.
"""
from __future__ import annotations

import threading
import time
from collections import OrderedDict

from errors import provider

_LOCK = threading.Lock()
_LAST = [0.0]
_CACHE: OrderedDict[tuple, list] = OrderedDict()


def _throttle():
    with _LOCK:
        wait = 1.05 - (time.time() - _LAST[0])
        if wait > 0:
            time.sleep(wait)
        _LAST[0] = time.time()


def search(query: str, lang: str, user_agent: str) -> list[dict]:
    import httpx

    q = " ".join(query.split())[:120]
    if len(q) < 2:
        return []
    key = (q.lower(), lang)
    if key in _CACHE:
        _CACHE.move_to_end(key)
        return _CACHE[key]
    headers = {"User-Agent": user_agent, "Accept-Language": lang}
    results: list[dict] | None = None
    try:
        _throttle()
        r = httpx.get("https://nominatim.openstreetmap.org/search",
                      params={"q": q, "format": "jsonv2", "limit": 6, "polygon_geojson": 0},
                      headers=headers, timeout=12)
        r.raise_for_status()
        results = []
        for it in r.json():
            bb = it.get("boundingbox")  # [south, north, west, east] as strings
            results.append({
                "name": it.get("display_name", ""),
                "lat": float(it["lat"]), "lon": float(it["lon"]),
                "bounds": [float(bb[0]), float(bb[2]), float(bb[1]), float(bb[3])] if bb else None,
                "kind": it.get("type"),
            })
    except (httpx.HTTPError, ValueError, KeyError):
        results = None
    if results is None:
        try:
            r = httpx.get("https://photon.komoot.io/api/", params={"q": q, "limit": 6,
                          "lang": lang if lang in ("en", "de", "fr") else "default"},
                          headers=headers, timeout=12)
            r.raise_for_status()
            results = []
            for f in r.json().get("features", []):
                lon, lat = f["geometry"]["coordinates"]
                p = f.get("properties", {})
                ext = p.get("extent")  # [west, north, east, south]
                name = ", ".join(x for x in (p.get("name"), p.get("state"), p.get("country")) if x)
                results.append({"name": name, "lat": lat, "lon": lon,
                                "bounds": [ext[3], ext[0], ext[1], ext[2]] if ext else None, "kind": p.get("osm_value")})
        except (httpx.HTTPError, ValueError, KeyError) as e:
            raise provider("La búsqueda de lugares no está disponible ahora. Puedes dibujar el área en el mapa.",
                           "Place search is unavailable right now. You can draw the area on the map.") from e
    _CACHE[key] = results
    while len(_CACHE) > 500:
        _CACHE.popitem(last=False)
    return results
