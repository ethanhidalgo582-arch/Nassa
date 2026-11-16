"""Geometry helpers: validation, equal-area measurements and map rasters.

All user polygons arrive as [[lat, lon], ...]. Internally shapely uses (lon, lat).
Rasters sent to the map are resampled onto a regular Web Mercator grid so that
flutter_map can stretch them between their south-west / north-east corners
without distortion (the base maps are Web Mercator too).
"""
from __future__ import annotations

import base64
import io
import math
from dataclasses import dataclass

import numpy as np
from pyproj import CRS, Transformer
from shapely.geometry import Polygon, mapping

from errors import invalid

MERCATOR_MAX_LAT = 85.0
_EQUAL_AREA = 6933  # WGS 84 / NSIDC EASE-Grid 2.0 Global (equal-area)


def reproject(func, geom):
    """Apply a pyproj ``Transformer.transform``-like function (x, y) -> (x, y) to a geometry."""
    import shapely

    return shapely.transform(geom, lambda x, y: tuple(np.asarray(v) for v in func(x, y)), interleaved=False)


@dataclass(frozen=True)
class Selection:
    polygon: Polygon  # lon/lat
    area_km2: float

    @property
    def bounds(self) -> tuple[float, float, float, float]:
        return self.polygon.bounds  # west, south, east, north

    def geojson(self) -> dict:
        return mapping(self.polygon)


def equal_area_km2(geom_lonlat) -> float:
    tr = Transformer.from_crs(4326, _EQUAL_AREA, always_xy=True)
    return reproject(tr.transform, geom_lonlat).area / 1e6


def parse_selection(points: list[list[float]], max_area_km2: float) -> Selection:
    if len(points) < 3:
        raise invalid("Dibuja un área con al menos tres puntos.", "Draw an area with at least three points.")
    ring = []
    for pt in points:
        if len(pt) != 2:
            raise invalid("Cada vértice debe tener latitud y longitud.", "Each vertex needs latitude and longitude.")
        lat, lon = float(pt[0]), float(pt[1])
        if not (math.isfinite(lat) and math.isfinite(lon)):
            raise invalid("Hay coordenadas no válidas.", "Some coordinates are not valid.")
        if not (-MERCATOR_MAX_LAT <= lat <= MERCATOR_MAX_LAT and -180 <= lon <= 180):
            raise invalid(
                "Las coordenadas deben estar entre 85° S y 85° N (límite del mapa web).",
                "Coordinates must lie between 85° S and 85° N (web map limit).",
            )
        ring.append((lon, lat))
    if len(set(ring)) < 3:
        raise invalid("Se necesitan tres vértices distintos.", "Three distinct vertices are needed.")
    poly = Polygon(ring)
    if not poly.is_valid or poly.area <= 0:
        raise invalid(
            "El área no puede cruzarse consigo misma. Vuelve a dibujarla.",
            "The area cannot cross itself. Please draw it again.",
        )
    west, south, east, north = poly.bounds
    if east - west > 180:
        raise invalid("El área no puede cruzar el antimeridiano.", "The area cannot cross the antimeridian.")
    area = equal_area_km2(poly)
    if area > max_area_km2:
        raise invalid(
            f"El área mide {area:,.0f} km²; el máximo es {max_area_km2:,.0f} km². Selecciona una zona más pequeña.",
            f"The area is {area:,.0f} km²; the maximum is {max_area_km2:,.0f} km². Select a smaller zone.",
        )
    return Selection(poly, area)


def local_metric_crs(poly: Polygon) -> CRS:
    """Azimuthal equal-area projection centred on the polygon (works near the poles)."""
    c = poly.centroid
    return CRS.from_proj4(f"+proj=laea +lat_0={c.y:.6f} +lon_0={c.x:.6f} +datum=WGS84 +units=m +no_defs")


def reference_ring(poly: Polygon, min_width_m: float = 500.0, factor: float = 0.5) -> Polygon:
    """Ring around the selection used as local reference for relative InSAR values."""
    crs = local_metric_crs(poly)
    fwd = Transformer.from_crs(4326, crs, always_xy=True).transform
    inv = Transformer.from_crs(crs, 4326, always_xy=True).transform
    p = reproject(fwd, poly)
    radius = math.sqrt(p.area / math.pi)
    width = max(min_width_m, factor * radius)
    ring = p.buffer(width).difference(p)
    return reproject(inv, ring)


# ---------------------------------------------------------------------------
# Web Mercator raster rendering
# ---------------------------------------------------------------------------

def _merc_y(lat):
    lat = np.clip(lat, -MERCATOR_MAX_LAT, MERCATOR_MAX_LAT)
    return np.log(np.tan(np.pi / 4 + np.radians(lat) / 2))


def _inv_merc_y(y):
    return np.degrees(2 * np.arctan(np.exp(y)) - np.pi / 2)


def mercator_grid(bounds: tuple[float, float, float, float], max_px: int = 768):
    """Regular Web Mercator grid of pixel centres covering bounds (west, south, east, north)."""
    west, south, east, north = bounds
    ys, yn = float(_merc_y(south)), float(_merc_y(north))
    xw, xe = math.radians(west), math.radians(east)
    span_x, span_y = xe - xw, yn - ys
    if span_x <= 0 or span_y <= 0:
        raise ValueError("empty bounds")
    if span_x >= span_y:
        w = max_px
        h = max(2, int(round(max_px * span_y / span_x)))
    else:
        h = max_px
        w = max(2, int(round(max_px * span_x / span_y)))
    xc = xw + (np.arange(w) + 0.5) * span_x / w
    yc = yn - (np.arange(h) + 0.5) * span_y / h  # row 0 = north
    lon = np.degrees(xc)
    lat = _inv_merc_y(yc)
    lon2d, lat2d = np.meshgrid(lon, lat)
    return lon2d, lat2d


def nearest_index(axis: np.ndarray, values: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Index of the nearest regular-axis cell for each value and an in-range mask."""
    axis = np.asarray(axis, dtype="float64")
    if len(axis) < 2:
        raise ValueError("axis too short")
    step = axis[1] - axis[0]
    idx = np.rint((values - axis[0]) / step).astype(np.int64)
    ok = (idx >= 0) & (idx < len(axis))
    return np.clip(idx, 0, len(axis) - 1), ok


def png_overlay(rgba: np.ndarray, bounds: tuple[float, float, float, float]) -> dict:
    from PIL import Image

    img = Image.fromarray(rgba.astype(np.uint8), mode="RGBA")
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    west, south, east, north = bounds
    return {
        "image_base64": base64.b64encode(buf.getvalue()).decode("ascii"),
        "bounds": [south, west, north, east],
        "width": int(rgba.shape[1]),
        "height": int(rgba.shape[0]),
        "projection": "EPSG:3857 grid, corners in EPSG:4326",
    }


def mask_inside(poly: Polygon, lon2d: np.ndarray, lat2d: np.ndarray) -> np.ndarray:
    import shapely

    return shapely.contains_xy(poly, lon2d, lat2d)


def round_sig(value, digits: int = 3):
    """Round for display without inventing precision; None stays None."""
    if value is None:
        return None
    value = float(value)
    if not math.isfinite(value):
        return None
    if value == 0:
        return 0.0
    return round(value, max(0, digits - int(math.floor(math.log10(abs(value)))) - 1))
