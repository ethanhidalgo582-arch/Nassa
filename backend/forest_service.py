"""Forest-cover loss from Hansen/UMD/Google/USGS/NASA Global Forest Change (GFC).

Data: https://storage.googleapis.com/earthenginepartners-hansen/ (CC BY 4.0)
Citation: Hansen, M. C. et al. 2013. High-Resolution Global Maps of 21st-Century
Forest Cover Change. Science 342: 850-853.

Only the window of each 10°x10° GeoTIFF that covers the selection is read
(HTTP range requests through GDAL /vsicurl/). Nothing is invented: every pixel
painted on the map comes from the lossyear/treecover2000/datamask layers.
"""
from __future__ import annotations

import math
import os
from dataclasses import dataclass
from typing import Callable

import numpy as np

from errors import AnalysisError, invalid, no_data, provider
from geo import Selection, mask_inside, mercator_grid, nearest_index, png_overlay, round_sig

HANSEN_VERSION = os.getenv("HANSEN_VERSION", "GFC-2025-v1.13")
HANSEN_LAST_YEAR = int(os.getenv("HANSEN_LAST_YEAR", "2025"))
HANSEN_FIRST_YEAR = 2001
HANSEN_BASE = "https://storage.googleapis.com/earthenginepartners-hansen"
RES = 0.00025  # degrees (1 arc-second, ~30 m at the equator)
AUTHALIC_R = 6371007.181

SOURCE = {
    "name": "Hansen/UMD/Google/USGS/NASA Global Forest Change",
    "version": HANSEN_VERSION,
    "sensor": "Landsat (30 m), annual product",
    "license": "CC BY 4.0",
    "citation": "Hansen et al. (2013) Science 342:850-853",
    "url": "https://glad.earthengine.app/view/global-forest-change",
}

# Loss-share classes per displayed cell (fraction of the cell's valid land).
LOSS_CLASSES = [
    (0.0, 0.05, (253, 224, 71)),
    (0.05, 0.20, (249, 115, 22)),
    (0.20, 0.50, (220, 38, 38)),
    (0.50, 1.01, (127, 29, 29)),
]


def tile_name(north: int, west: int) -> str:
    ns = f"{abs(north):02d}{'N' if north >= 0 else 'S'}"
    ew = f"{abs(west):03d}{'E' if west >= 0 else 'W'}"
    return f"{ns}_{ew}"


def tile_url(layer: str, north: int, west: int) -> str:
    return f"{HANSEN_BASE}/{HANSEN_VERSION}/Hansen_{HANSEN_VERSION}_{layer}_{tile_name(north, west)}.tif"


@dataclass
class Window:
    col0: int  # global column index of the first pixel (from -180)
    row0: int  # global row index of the first pixel (from +80)
    width: int
    height: int

    @property
    def west(self) -> float:
        return -180 + self.col0 * RES

    @property
    def north(self) -> float:
        return 80 - self.row0 * RES

    def lon_axis(self) -> np.ndarray:
        return self.west + (np.arange(self.width) + 0.5) * RES

    def lat_axis(self) -> np.ndarray:
        return self.north - (np.arange(self.height) + 0.5) * RES


def window_for(bounds) -> Window:
    west, south, east, north = bounds
    if north > 80 or south < -60:
        raise no_data(
            "Hansen GFC solo cubre entre 80° N y 60° S. Elige otra zona.",
            "Hansen GFC only covers 80° N to 60° S. Choose another area.",
        )
    col0 = int(math.floor((west + 180) / RES))
    col1 = int(math.ceil((east + 180) / RES))
    row0 = int(math.floor((80 - north) / RES))
    row1 = int(math.ceil((80 - south) / RES))
    return Window(col0, row0, max(1, col1 - col0), max(1, row1 - row0))


def read_layer_http(layer: str, win: Window) -> np.ndarray:
    """Mosaic the requested window from the 10° tiles. Missing tiles -> 0 (datamask 0 = no data)."""
    import rasterio
    from rasterio.errors import RasterioIOError
    from rasterio.windows import Window as RWindow

    out = np.zeros((win.height, win.width), dtype=np.uint8)
    tile_px = 40000
    tc0, tc1 = win.col0 // tile_px, (win.col0 + win.width - 1) // tile_px
    tr0, tr1 = win.row0 // tile_px, (win.row0 + win.height - 1) // tile_px
    env = dict(
        GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR",
        CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
        GDAL_HTTP_TIMEOUT="60",
        GDAL_HTTP_MAX_RETRY="3",
        GDAL_HTTP_RETRY_DELAY="2",
        VSI_CACHE="TRUE",
    )
    with rasterio.Env(**env):
        for tr in range(tr0, tr1 + 1):
            for tc in range(tc0, tc1 + 1):
                north = 80 - tr * 10
                west = -180 + tc * 10
                c0 = max(win.col0, tc * tile_px)
                c1 = min(win.col0 + win.width, (tc + 1) * tile_px)
                r0 = max(win.row0, tr * tile_px)
                r1 = min(win.row0 + win.height, (tr + 1) * tile_px)
                url = "/vsicurl/" + tile_url(layer, north, west)
                try:
                    with rasterio.open(url) as src:
                        data = src.read(
                            1,
                            window=RWindow(c0 - tc * tile_px, r0 - tr * tile_px, c1 - c0, r1 - r0),
                        )
                except RasterioIOError as e:
                    if "404" in str(e) or "not recognized" in str(e) or "does not exist" in str(e):
                        continue  # ocean tile without product: stays 0 / no data
                    raise provider(
                        "No se pudo leer Hansen GFC. Vuelve a intentarlo en unos minutos.",
                        "Hansen GFC could not be read. Try again in a few minutes.",
                    ) from e
                out[r0 - win.row0 : r1 - win.row0, c0 - win.col0 : c1 - win.col0] = data
    return out


Reader = Callable[[str, Window], np.ndarray]


def _block_reduce(a: np.ndarray, f: int, func=np.sum) -> np.ndarray:
    if f <= 1:
        return a.astype("float64")
    h, w = a.shape
    H, W = math.ceil(h / f), math.ceil(w / f)
    pad = np.zeros((H * f, W * f), dtype="float64")
    pad[:h, :w] = a
    return func(pad.reshape(H, f, W, f), axis=(1, 3))


def analyze(
    sel: Selection,
    start_year: int,
    end_year: int,
    canopy_threshold: int = 30,
    *,
    max_pixels: int = 12_000_000,
    reader: Reader = read_layer_http,
    stage: Callable[[str], None] = lambda s: None,
) -> dict:
    if not (HANSEN_FIRST_YEAR <= start_year <= end_year <= HANSEN_LAST_YEAR):
        raise invalid(
            f"Elige años entre {HANSEN_FIRST_YEAR} y {HANSEN_LAST_YEAR}, con el inicial antes o igual al final.",
            f"Choose years between {HANSEN_FIRST_YEAR} and {HANSEN_LAST_YEAR}, start not after end.",
        )
    if not (10 <= canopy_threshold <= 75):
        raise invalid("El umbral de dosel debe estar entre 10 % y 75 %.", "Canopy threshold must be 10–75 %.")

    win = window_for(sel.bounds)
    if win.width * win.height > max_pixels:
        raise invalid(
            "El área es demasiado grande para el análisis forestal a 30 m en este servidor. Selecciona una zona más pequeña.",
            "The area is too large for the 30 m forest analysis on this server. Select a smaller zone.",
        )

    stage("reading")
    datamask = reader("datamask", win)
    treecover = reader("treecover2000", win)
    lossyear = reader("lossyear", win)

    stage("processing")
    lon = win.lon_axis()
    lat = win.lat_axis()
    import shapely

    inside = shapely.contains_xy(sel.polygon, lon[None, :], lat[:, None])
    if not inside.any():
        raise invalid("El área es más pequeña que un píxel de 30 m.", "The area is smaller than one 30 m pixel.")

    px_ha = ((AUTHALIC_R * math.radians(RES)) ** 2 * np.cos(np.radians(lat)) / 1e4)[:, None]
    area = np.broadcast_to(px_ha, inside.shape)

    has_data = inside & (datamask > 0)
    land = inside & (datamask == 1)
    water = inside & (datamask == 2)
    nodata = inside & (datamask == 0)

    s_code = start_year - 2000
    e_code = end_year - 2000
    forest2000 = land & (treecover >= canopy_threshold)
    lost_before = forest2000 & (lossyear > 0) & (lossyear < s_code)
    forest_start = forest2000 & ~lost_before
    loss = forest_start & (lossyear >= s_code) & (lossyear <= e_code)

    def ha(mask):
        return float(np.sum(area[mask]))

    selected_ha = ha(inside)
    valid_ha = ha(has_data)
    land_ha = ha(land)
    nodata_ha = ha(nodata)
    forest_start_ha = ha(forest_start)
    loss_ha = ha(loss)

    if valid_ha <= 0:
        raise no_data(
            "Hansen GFC no tiene datos válidos dentro de esta selección. Elige otra zona.",
            "Hansen GFC has no valid data inside this selection. Choose another area.",
        )

    annual = []
    for y in range(start_year, end_year + 1):
        m = forest_start & (lossyear == y - 2000)
        annual.append({"year": y, "loss_ha": round(ha(m), 2)})

    loss_pct = (100 * loss_ha / forest_start_ha) if forest_start_ha > 0 else None

    stage("rendering")
    layers, legend, grid = _render(sel, win, lon, lat, inside, land, nodata, forest_start, loss, lossyear, area)

    return {
        "module": "bosques",
        "measurement": {
            "es": "Pérdida de cobertura arbórea detectada (Hansen GFC)",
            "en": "Detected tree-cover loss (Hansen GFC)",
        },
        "source": SOURCE,
        "period": {"start_year": start_year, "end_year": end_year,
                   "label": {"es": f"{start_year}–{end_year} (años completos)",
                             "en": f"{start_year}–{end_year} (full years)"}},
        "parameters": {"canopy_threshold_pct": canopy_threshold, "resolution_m": 30},
        "metrics": {
            "selected_area_ha": round(selected_ha, 1),
            "valid_data_area_ha": round(valid_ha, 1),
            "valid_data_pct": round(100 * valid_ha / selected_ha, 1) if selected_ha else None,
            "no_data_area_ha": round(nodata_ha, 1),
            "land_area_ha": round(land_ha, 1),
            "water_area_ha": round(ha(water), 1),
            "forest_start_ha": round(forest_start_ha, 1),
            "loss_ha": round(loss_ha, 1),
            "loss_pct_of_forest_start": round_sig(loss_pct, 3) if loss_pct is not None else None,
            "loss_pct_denominator": {
                "es": f"bosque al inicio de {start_year} (dosel ≥ {canopy_threshold} % en 2000, menos pérdidas 2001–{start_year - 1})",
                "en": f"forest at the start of {start_year} (canopy ≥ {canopy_threshold} % in 2000, minus 2001–{start_year - 1} losses)",
            },
            "peak_loss_year": max(annual, key=lambda a: a["loss_ha"])["year"] if loss_ha > 0 else None,
        },
        "annual_loss": annual,
        "layers": layers,
        "legend": legend,
        "grid": grid,
        "limitations": {
            "es": [
                "Hansen GFC registra la eliminación de más del 50 % del dosel en píxeles de 30 m. Incluye tala, incendios, tormentas y cosecha de plantaciones: es pérdida de cobertura arbórea compatible con deforestación, no deforestación confirmada.",
                "El bosque inicial se estima con la cobertura de 2000 menos las pérdidas previas; no incluye bosque que haya crecido después de 2000.",
                "El año asignado a cada pérdida puede tener un desfase de ±1 año.",
                "Las zonas grises no tienen datos: no significan ausencia de pérdida.",
                "Es un producto óptico de Landsat, no una medición de NISAR.",
            ],
            "en": [
                "Hansen GFC records removal of more than 50 % of the canopy in 30 m pixels. It includes logging, fire, storms and plantation harvest: it is tree-cover loss compatible with deforestation, not confirmed deforestation.",
                "Initial forest is 2000 tree cover minus earlier losses; forest grown after 2000 is not included.",
                "The year assigned to each loss may be off by ±1 year.",
                "Grey areas have no data: they do not mean absence of loss.",
                "This is an optical Landsat product, not a NISAR measurement.",
            ],
        },
    }


def _render(sel, win, lon, lat, inside, land, nodata, forest_start, loss, lossyear, area):
    west, south, east, north = sel.bounds
    bounds = (west, south, east, north)
    lon2d, lat2d = mercator_grid(bounds, 768)
    out_h, out_w = lon2d.shape
    f = max(1, int(math.floor(min(win.height / out_h, win.width / out_w))))

    inside_a = _block_reduce(inside * area, f)
    land_a = _block_reduce(land * area, f)
    nodata_a = _block_reduce(nodata * area, f)
    forest_a = _block_reduce(forest_start * area, f)
    loss_a = _block_reduce(loss * area, f)

    lon_r = win.west + (np.arange(inside_a.shape[1]) + 0.5) * RES * f
    lat_r = win.north - (np.arange(inside_a.shape[0]) + 0.5) * RES * f
    ix, okx = nearest_index(lon_r, lon2d)
    iy, oky = nearest_index(lat_r, lat2d)
    in_poly = mask_inside(sel.polygon, lon2d, lat2d) & okx & oky

    with np.errstate(invalid="ignore", divide="ignore"):
        loss_frac = np.where(land_a > 0, loss_a / land_a, 0)[iy, ix]
        forest_frac = np.where(land_a > 0, forest_a / land_a, 0)[iy, ix]
        nodata_frac = np.where(inside_a > 0, nodata_a / inside_a, 0)[iy, ix]

    loss_rgba = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    has_loss = in_poly & (loss_frac > 0)
    for lo, hi, rgb in LOSS_CLASSES:
        m = has_loss & (loss_frac > lo if lo == 0 else loss_frac >= lo) & (loss_frac < hi)
        loss_rgba[m, :3] = rgb
        loss_rgba[m, 3] = 235

    forest_rgba = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    fm = in_poly & (forest_frac > 0)
    forest_rgba[fm, :3] = (22, 131, 74)
    forest_rgba[fm, 3] = (40 + 130 * np.clip(forest_frac[fm], 0, 1)).astype(np.uint8)

    nodata_rgba = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    nm = in_poly & (nodata_frac >= 0.5)
    yy, xx = np.mgrid[0:out_h, 0:out_w]
    stripes = ((xx + yy) // 4) % 2 == 0
    nodata_rgba[nm, :3] = (107, 114, 128)
    nodata_rgba[nm, 3] = np.where(stripes[nm], 200, 90).astype(np.uint8)

    layers = {
        "loss": png_overlay(loss_rgba, bounds),
        "forest_start": png_overlay(forest_rgba, bounds),
        "no_data": png_overlay(nodata_rgba, bounds),
        "display_cell_m": round(30 * f),
    }
    legend = {
        "loss_classes": [
            {"min_pct": round(lo * 100), "max_pct": min(100, round(hi * 100)), "color": "#%02x%02x%02x" % rgb}
            for lo, hi, rgb in LOSS_CLASSES
        ],
        "cell_m": round(30 * f),
        "es": f"Cada celda del mapa (~{round(30 * f)} m) se colorea según la proporción de su tierra con pérdida detectada. Transparente: sin pérdida detectada. Gris rayado: sin datos.",
        "en": f"Each map cell (~{round(30 * f)} m) is coloured by the share of its land with detected loss. Transparent: no loss detected. Grey stripes: no data.",
    }

    # Coarse query grid (for tapping on the map).
    n = 32
    gf_y = max(1, math.ceil(win.height / n))
    gf_x = max(1, math.ceil(win.width / n))
    g = max(gf_x, gf_y)
    gi = _block_reduce(inside * area, g)
    gl = _block_reduce(land * area, g)
    gn = _block_reduce(nodata * area, g)
    gfo = _block_reduce(forest_start * area, g)
    glo = _block_reduce(loss * area, g)
    cells = []
    years = np.where(loss, lossyear, 0)
    for r in range(gi.shape[0]):
        for c in range(gi.shape[1]):
            if gi[r, c] <= 0:
                continue
            ys = years[r * g:(r + 1) * g, c * g:(c + 1) * g]
            ys = ys[ys > 0]
            top = None
            if ys.size:
                vals, counts = np.unique(ys, return_counts=True)
                top = int(vals[np.argmax(counts)]) + 2000
            cells.append({
                "s": round(win.north - (r + 1) * g * RES, 6), "w": round(win.west + c * g * RES, 6),
                "n": round(win.north - r * g * RES, 6), "e": round(win.west + (c + 1) * g * RES, 6),
                "area_ha": round(float(gi[r, c]), 1), "land_ha": round(float(gl[r, c]), 1),
                "no_data_pct": round(100 * float(gn[r, c] / gi[r, c]), 1),
                "forest_start_ha": round(float(gfo[r, c]), 1), "loss_ha": round(float(glo[r, c]), 1),
                "main_loss_year": top,
            })
    return layers, legend, {"cell_deg": round(g * RES, 6), "cells": cells}
