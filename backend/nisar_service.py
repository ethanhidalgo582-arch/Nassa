"""NISAR L2 GUNW access and InSAR measurements (subsidence and glaciers).

Product layout follows JPL D-102272 Rev E (NISAR L2 GUNW Product Specification):
  /science/LSAR/GUNW/grids/frequencyA/centerFrequency                (Hz)
  /science/LSAR/GUNW/grids/frequencyA/unwrappedInterferogram/{x,y}Coordinates, projection (EPSG)
  /science/LSAR/GUNW/grids/frequencyA/unwrappedInterferogram/<POL>/unwrappedPhase       (rad, fill NaN)
  /science/LSAR/GUNW/grids/frequencyA/unwrappedInterferogram/<POL>/coherenceMagnitude   (fill NaN)
  /science/LSAR/GUNW/grids/frequencyA/unwrappedInterferogram/<POL>/connectedComponents  (fill 65535)
  /science/LSAR/GUNW/grids/frequencyA/pixelOffsets/<POL>/{slantRange,alongTrack}Offset (m)
  /science/LSAR/GUNW/metadata/radarGrid/incidenceAngle (height, y, x) + x/yCoordinates, projection
  /science/LSAR/identification/{reference,secondary}ZeroDopplerStartTime

Only the sub-window that covers the selection (plus a reference ring) is read, using
authenticated HTTP range requests, so the ~1.4 GB products are never fully downloaded
in the default "stream" mode.

What is measured: change of the satellite-to-ground distance along the line of sight
(LOS) between two acquisitions. Unwrapped phase has an arbitrary constant per connected
component, so every value is referenced to the median of a ring of stable-looking pixels
around the selection (same connected component). Values are therefore *relative*.
"""
from __future__ import annotations

import contextlib
import math
import os
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Callable, Iterator

import numpy as np
import shapely
from pyproj import Transformer
from shapely.geometry import Polygon, shape

from errors import AnalysisError, no_data, not_configured, provider
from geo import reproject, Selection, mask_inside, mercator_grid, nearest_index, png_overlay, reference_ring, round_sig

CMR_GRANULES = "https://cmr.earthdata.nasa.gov/search/granules.umm_json"
NISAR_FIRST_DATE = date(2025, 10, 28)  # first GUNW in CMR collections (checked 2026-11-15)
GRID = "/science/LSAR/GUNW/grids/frequencyA"
IDENT = "/science/LSAR/identification"
RADAR_GRID = "/science/LSAR/GUNW/metadata/radarGrid"
CC_FILL = 65535
MIN_REF_PIXELS = 30
# Phase-to-LOS sign. d_los = SIGN * lambda/(4*pi) * phase. With SIGN = -1 a positive LOS
# value means the ground moved towards the satellite. D-102272 Rev E does not state the
# convention explicitly; keep it configurable and document it as a limitation.
PHASE_SIGN = float(os.getenv("NISAR_PHASE_SIGN", "-1"))

SOURCE_BASE = {
    "name": "NASA-ISRO NISAR L2 GUNW (Geocoded Unwrapped Interferogram)",
    "provider": "NASA Earthdata / ASF DAAC",
    "spec": "JPL D-102272 Rev E",
    "band": "L-band (~24 cm)",
}


# ---------------------------------------------------------------------------
# Catalogue search (public CMR API, no credentials needed)
# ---------------------------------------------------------------------------

@dataclass
class Granule:
    granule_id: str
    collection: str
    url: str
    ref_start: datetime
    sec_start: datetime
    track: str
    frame: str
    direction: str
    stack_id: str
    polarization: str
    footprint: Polygon
    size_bytes: int | None = None
    coverage: float = 0.0  # fraction of the selection inside the footprint

    @property
    def ref_date(self) -> date:
        return self.ref_start.date()

    @property
    def sec_date(self) -> date:
        return self.sec_start.date()

    @property
    def days(self) -> int:
        return (self.sec_date - self.ref_date).days

    def describe(self) -> dict:
        return {
            "granule": self.granule_id,
            "collection": self.collection,
            "reference_date": self.ref_date.isoformat(),
            "secondary_date": self.sec_date.isoformat(),
            "days": self.days,
            "track": self.track,
            "frame": self.frame,
            "direction": self.direction,
            "polarization": self.polarization,
            "coverage_pct": round(100 * self.coverage, 1),
        }


def _parse_time(text: str) -> datetime:
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def parse_umm(item: dict, collection: str) -> Granule | None:
    umm = item.get("umm", {})
    attrs = {a.get("Name"): (a.get("Values") or [None])[0] for a in umm.get("AdditionalAttributes", [])}
    url = next(
        (u["URL"] for u in umm.get("RelatedUrls", [])
         if u.get("URL", "").startswith("https://") and u["URL"].endswith(".h5")
         and u.get("Type") in (None, "GET DATA") and "QA_STATS" not in u["URL"]),
        None,
    )
    try:
        pts = umm["SpatialExtent"]["HorizontalSpatialDomain"]["Geometry"]["GPolygons"][0]["Boundary"]["Points"]
        footprint = Polygon([(p["Longitude"], p["Latitude"]) for p in pts])
        ref = attrs.get("REFERENCE_ZERO_DOPPLER_START_TIME")
        sec = attrs.get("SECONDARY_ZERO_DOPPLER_START_TIME")
        if not (url and ref and sec):
            return None
        size = next(
            (int(a.get("SizeInBytes")) for a in umm.get("DataGranule", {}).get("ArchiveAndDistributionInformation", [])
             if str(a.get("Name", "")).endswith(".h5") and a.get("SizeInBytes")),
            None,
        )
        return Granule(
            granule_id=umm.get("GranuleUR", ""),
            collection=collection,
            url=url,
            ref_start=_parse_time(ref),
            sec_start=_parse_time(sec),
            track=str(attrs.get("TRACK_NUMBER", "")),
            frame=str(attrs.get("FRAME_NUMBER", "")),
            direction=str(attrs.get("ASCENDING_DESCENDING", "")),
            stack_id=str(attrs.get("STACK_ID") or f"{attrs.get('TRACK_NUMBER')}_{attrs.get('ASCENDING_DESCENDING')}_{attrs.get('FRAME_NUMBER')}"),
            polarization=str(attrs.get("FREQUENCY_A_POLARIZATION", "")),
            footprint=footprint if footprint.is_valid else footprint.buffer(0),
            size_bytes=size,
        )
    except (KeyError, IndexError, TypeError, ValueError):
        return None


_SEARCH_CACHE: dict[tuple, tuple[float, list[Granule]]] = {}


def search_granules(sel: Selection, start: date, end: date, collection: str, *,
                    user_agent: str, max_results: int = 600) -> list[Granule]:
    import httpx

    west, south, east, north = sel.bounds
    key = (collection, round(west, 4), round(south, 4), round(east, 4), round(north, 4), start, end)
    hit = _SEARCH_CACHE.get(key)
    if hit and time.time() - hit[0] < 600:
        return hit[1]
    params = {
        "short_name": collection,
        "bounding_box": f"{west},{south},{east},{north}",
        "temporal": f"{start.isoformat()}T00:00:00Z,{end.isoformat()}T23:59:59Z",
        "page_size": 200,
        "sort_key": "-start_date",
    }
    out: list[Granule] = []
    headers = {"User-Agent": user_agent}
    try:
        with httpx.Client(timeout=40, headers=headers) as client:
            search_after = None
            while len(out) < max_results:
                h = dict(headers)
                if search_after:
                    h["CMR-Search-After"] = search_after
                r = client.get(CMR_GRANULES, params=params, headers=h)
                r.raise_for_status()
                items = r.json().get("items", [])
                for it in items:
                    g = parse_umm(it, collection)
                    if g:
                        out.append(g)
                search_after = r.headers.get("CMR-Search-After")
                if not items or not search_after:
                    break
    except httpx.HTTPError as e:
        raise provider(
            "No se pudo consultar el catálogo de NASA (CMR). Vuelve a intentarlo en unos minutos.",
            "The NASA catalogue (CMR) could not be reached. Try again in a few minutes.",
        ) from e
    _SEARCH_CACHE[key] = (time.time(), out)
    return out


def select_stack(granules: list[Granule], sel: Selection, min_coverage: float = 0.5) -> list[Granule]:
    """Keep the observation geometry (same track/direction/frame and polarization) that
    covers the selection best. Products from different geometries are never mixed."""
    area = sel.polygon.area
    groups: dict[tuple, list[Granule]] = {}
    for g in granules:
        inter = g.footprint.intersection(sel.polygon).area if g.footprint.intersects(sel.polygon) else 0
        g.coverage = inter / area if area else 0
        if g.coverage >= min_coverage:
            groups.setdefault((g.collection, g.stack_id, g.polarization), []).append(g)
    if not groups:
        return []

    def score(items):
        full = sum(1 for g in items if g.coverage >= 0.98)
        return (full, len(items), max(g.sec_start for g in items))

    best = max(groups.values(), key=score)
    # Same pair may appear several times (reprocessing): keep the latest granule id.
    unique: dict[tuple, Granule] = {}
    for g in sorted(best, key=lambda g: g.granule_id):
        unique[(g.ref_date, g.sec_date)] = g
    return sorted(unique.values(), key=lambda g: (g.ref_date, g.sec_date))


def build_chain(pairs: list[Granule], max_pairs: int) -> list[Granule]:
    """Longest run of consecutive pairs (secondary date of one == reference date of the next),
    preferring the most recent. Only consecutive pairs can be added without double counting."""
    if not pairs:
        return []
    by_ref: dict[date, list[Granule]] = {}
    for p in pairs:
        by_ref.setdefault(p.ref_date, []).append(p)
    best: dict[date, list[Granule]] = {}

    def longest_from(d: date) -> list[Granule]:
        if d in best:
            return best[d]
        options = [[p] + longest_from(p.sec_date) for p in by_ref.get(d, [])]
        best[d] = max(options, key=lambda c: (len(c), c[-1].sec_date), default=[])
        return best[d]

    chains = [longest_from(p.ref_date) for p in pairs]
    chain = max(chains, key=lambda c: (min(len(c), max_pairs), c[-1].sec_date))
    return chain[-max_pairs:]


# ---------------------------------------------------------------------------
# Remote access
# ---------------------------------------------------------------------------

Opener = Callable[[Granule], "contextlib.AbstractContextManager"]


def earthdata_opener(settings) -> Opener:
    if not settings.earthdata_configured:
        raise not_configured(
            "El servidor no tiene credenciales de NASA Earthdata (EARTHDATA_TOKEN o EARTHDATA_USERNAME/EARTHDATA_PASSWORD).",
            "The server has no NASA Earthdata credentials (EARTHDATA_TOKEN or EARTHDATA_USERNAME/EARTHDATA_PASSWORD).",
        )

    @contextlib.contextmanager
    def _open(g: Granule) -> Iterator:
        import earthaccess
        import h5py

        try:
            auth = earthaccess.login(strategy="environment")
            if not getattr(auth, "authenticated", False):
                raise RuntimeError("not authenticated")
        except Exception as e:
            raise not_configured(
                "Las credenciales de NASA Earthdata no son válidas o el servicio no responde.",
                "NASA Earthdata credentials are invalid or the service is not responding.",
            ) from e
        if settings.nisar_access_mode == "download":
            folder = settings.cache_dir / "nisar"
            folder.mkdir(parents=True, exist_ok=True)
            paths = earthaccess.download([g.url], local_path=str(folder), show_progress=False)
            if not paths:
                raise provider("No se pudo descargar el producto NISAR.", "The NISAR product could not be downloaded.")
            try:
                with h5py.File(paths[0], "r") as f:
                    yield f
            finally:
                with contextlib.suppress(OSError):
                    os.remove(paths[0])  # ephemeral disk: never keep 1.4 GB files
            return
        fs = earthaccess.get_fsspec_https_session()
        try:
            fobj = fs.open(g.url, mode="rb", block_size=4 * 1024 * 1024, cache_type="blockcache")
        except Exception as e:
            raise provider(
                "No se pudo abrir el producto NISAR en NASA Earthdata.",
                "The NISAR product could not be opened on NASA Earthdata.",
            ) from e
        try:
            with h5py.File(fobj, "r", rdcc_nbytes=32 * 1024 * 1024) as f:
                yield f
        finally:
            fobj.close()

    return _open


# ---------------------------------------------------------------------------
# Reading one interferometric pair
# ---------------------------------------------------------------------------

def _text(ds) -> str:
    v = ds[()]
    if isinstance(v, bytes):
        return v.decode(errors="replace")
    if isinstance(v, np.ndarray) and v.dtype.kind in "SO":
        v = v.flat[0]
        return v.decode(errors="replace") if isinstance(v, bytes) else str(v)
    return str(v)


def _epsg(ds) -> int:
    try:
        value = int(np.asarray(ds[()]).item())
        if value > 0:
            return value
    except (TypeError, ValueError):
        pass
    code = ds.attrs.get("epsg_code")
    if code is None:
        raise AnalysisError("provider_error", "El producto no indica su proyección.", "The product does not state its projection.")
    return int(np.asarray(code).item())


def _axis_slice(axis: np.ndarray, lo: float, hi: float) -> slice | None:
    idx = np.where((axis >= lo) & (axis <= hi))[0]
    if not len(idx):
        return None
    return slice(int(idx.min()), int(idx.max()) + 1)


@dataclass
class PairData:
    granule: Granule | None
    ref_date: date
    sec_date: date
    polarization: str
    epsg: int
    x: np.ndarray
    y: np.ndarray
    los_rel_mm: np.ndarray  # referenced LOS (NaN = not usable)
    in_sel: np.ndarray
    usable_sel: np.ndarray
    coherence: np.ndarray
    wavelength_m: float
    referenced: bool
    ref_pixels: int
    ref_noise_mm: float | None
    incidence_deg: tuple[float, float, float] | None  # mean, min, max
    selected_area_km2: float
    footprint_area_km2: float
    valid_area_km2: float
    other_component_pixels: int
    offsets: dict | None = None
    notes: list[str] = field(default_factory=list)

    @property
    def days(self) -> int:
        return (self.sec_date - self.ref_date).days

    def values(self) -> np.ndarray:
        return self.los_rel_mm[self.usable_sel]


def read_pair(f, sel: Selection, ring: Polygon, min_coherence: float, granule: Granule | None = None,
              reference_mask_fn: Callable[[np.ndarray, np.ndarray, int], np.ndarray] | None = None,
              read_offsets: bool = False) -> PairData:
    if f"{GRID}/unwrappedInterferogram" not in f:
        raise AnalysisError("provider_error", "El archivo no es un GUNW de NISAR reconocible.",
                            "The file is not a recognisable NISAR GUNW.")
    base = f[f"{GRID}/unwrappedInterferogram"]
    pol = next((p for p in ("HH", "VV") if p in base), None)
    if pol is None:
        raise no_data("El producto no tiene polarización HH ni VV.", "The product has no HH or VV polarisation.")
    group = base[pol]

    def locate(name):
        for obj in (group, base):
            if name in obj:
                return obj[name]
        raise AnalysisError("provider_error", f"Falta {name} en el producto.", f"{name} missing from the product.")

    x = np.asarray(locate("xCoordinates")[()], dtype="float64")
    y = np.asarray(locate("yCoordinates")[()], dtype="float64")
    epsg = _epsg(locate("projection"))
    try:
        freq = float(np.asarray(f[f"{GRID}/centerFrequency"][()]).item())
    except KeyError as e:
        raise AnalysisError("provider_error", "Falta la frecuencia central; no se asumirá una longitud de onda.",
                            "Centre frequency missing; no wavelength will be assumed.") from e
    if not (math.isfinite(freq) and 0.5e9 < freq < 4e9):
        raise AnalysisError("provider_error", "Frecuencia central fuera del rango de banda L/S.",
                            "Centre frequency outside L/S band.")
    wavelength = 299_792_458.0 / freq

    try:
        ref_date = date.fromisoformat(_text(f[f"{IDENT}/referenceZeroDopplerStartTime"])[:10])
        sec_date = date.fromisoformat(_text(f[f"{IDENT}/secondaryZeroDopplerStartTime"])[:10])
    except (KeyError, ValueError):
        if granule is None:
            raise AnalysisError("provider_error", "El producto no identifica sus fechas.", "The product does not state its dates.")
        ref_date, sec_date = granule.ref_date, granule.sec_date
    ref_date, sec_date = min(ref_date, sec_date), max(ref_date, sec_date)

    to_prod = Transformer.from_crs(4326, epsg, always_xy=True).transform
    sel_p = reproject(to_prod, sel.polygon)
    ring_p = reproject(to_prod, ring)
    left, bottom, right, top = ring_p.union(sel_p).bounds
    sx = _axis_slice(x, left, right)
    sy = _axis_slice(y, bottom, top)
    if sx is None or sy is None:
        raise no_data("Este producto no cubre el área seleccionada.", "This product does not cover the selected area.")
    if (sx.stop - sx.start) * (sy.stop - sy.start) > 8_000_000:
        raise AnalysisError("invalid_input", "El área es demasiado grande para leerla en este servidor.",
                            "The area is too large to read on this server.")

    phase_ds = group["unwrappedPhase"]
    units = phase_ds.attrs.get("units", b"radians")
    units = units.decode() if isinstance(units, bytes) else str(units)
    if "rad" not in units.lower():
        raise AnalysisError("provider_error", "La fase no está en radianes.", "Phase is not in radians.")
    phase = np.asarray(phase_ds[sy, sx], dtype="float64")
    coh_name = "coherenceMagnitude" if "coherenceMagnitude" in group else "coherence"
    coh = np.asarray(group[coh_name][sy, sx], dtype="float64")
    cc = np.asarray(group["connectedComponents"][sy, sx]) if "connectedComponents" in group else None

    xs, ys = x[sx], y[sy]
    xx, yy = np.meshgrid(xs, ys)
    in_sel = shapely.contains_xy(sel_p, xx, yy)
    in_ring = shapely.contains_xy(ring_p, xx, yy)
    if not in_sel.any():
        raise no_data("Este producto no tiene píxeles dentro del área.", "This product has no pixels inside the area.")

    valid = np.isfinite(phase) & np.isfinite(coh) & (coh >= min_coherence) & (coh <= 1.0)
    if cc is not None:
        valid &= (cc != CC_FILL) & (cc > 0)
    los = PHASE_SIGN * wavelength / (4 * math.pi) * phase * 1000.0  # mm

    main_cc = None
    usable = valid & in_sel
    other = 0
    if cc is not None and usable.any():
        labels, counts = np.unique(cc[usable], return_counts=True)
        main_cc = labels[np.argmax(counts)]
        other = int(usable.sum() - counts.max())
        usable &= cc == main_cc

    ref_mask = valid & in_ring
    if reference_mask_fn is not None:
        ref_mask = valid & (in_ring | in_sel) & reference_mask_fn(xx, yy, epsg)
    if main_cc is not None:
        ref_mask &= cc == main_cc
    ref_pixels = int(ref_mask.sum())
    referenced = ref_pixels >= MIN_REF_PIXELS and usable.any()
    rel = np.full(los.shape, np.nan)
    noise = None
    if referenced:
        ref_vals = los[ref_mask]
        ref_value = float(np.median(ref_vals))
        noise = float(1.4826 * np.median(np.abs(ref_vals - ref_value)))
        rel[usable] = los[usable] - ref_value

    # Areas (equal-area projection).
    to_ea = Transformer.from_crs(epsg, 6933, always_xy=True).transform
    sel_area = reproject(to_ea, sel_p).area / 1e6
    dx = abs(float(x[1] - x[0])) if len(x) > 1 else 80.0
    dy = abs(float(y[1] - y[0])) if len(y) > 1 else 80.0
    footprint = shapely.box(x.min() - dx / 2, y.min() - dy / 2, x.max() + dx / 2, y.max() + dy / 2)
    if granule is not None and granule.footprint is not None:
        fp_area = reproject(to_ea, reproject(to_prod, granule.footprint).intersection(sel_p)).area / 1e6
    else:
        fp_area = reproject(to_ea, footprint.intersection(sel_p)).area / 1e6
    # Pixel area in the product CRS is dx*dy m² (UTM/polar stereographic grids are conformal,
    # scale error < 0.1 % in UTM; polar stereographic scale is accounted for by EASE area of the polygon).
    valid_area = min(sel_area, usable.sum() * dx * dy / 1e6) if usable.any() else 0.0

    incidence = _incidence(f, epsg, xx[usable] if usable.any() else xx[in_sel], yy[usable] if usable.any() else yy[in_sel])

    offsets = _offsets(f, pol, sel_p, epsg) if read_offsets else None

    return PairData(
        granule=granule, ref_date=ref_date, sec_date=sec_date, polarization=pol, epsg=epsg,
        x=xs, y=ys, los_rel_mm=rel, in_sel=in_sel, usable_sel=usable & referenced if referenced else usable & False,
        coherence=np.where(in_sel, coh, np.nan), wavelength_m=wavelength, referenced=referenced,
        ref_pixels=ref_pixels, ref_noise_mm=noise, incidence_deg=incidence,
        selected_area_km2=sel_area, footprint_area_km2=fp_area, valid_area_km2=valid_area,
        other_component_pixels=other, offsets=offsets,
    )


def _incidence(f, epsg, px, py):
    path = f"{RADAR_GRID}/incidenceAngle"
    if path not in f or not len(px):
        return None
    g = f[RADAR_GRID]
    try:
        ax = np.asarray(g["xCoordinates"][()], dtype="float64")
        ay = np.asarray(g["yCoordinates"][()], dtype="float64")
        cube = np.asarray(g["incidenceAngle"][()], dtype="float64")
        cepsg = _epsg(g["projection"]) if "projection" in g else epsg
    except (KeyError, AnalysisError):
        return None
    if cube.ndim != 3 or cube.shape[1:] != (len(ay), len(ax)):
        return None
    if cepsg != epsg:
        px, py = Transformer.from_crs(epsg, cepsg, always_xy=True).transform(px, py)
    sample = np.linspace(0, len(px) - 1, min(len(px), 2000)).astype(int)
    ix = np.abs(ax[None, :] - np.asarray(px)[sample][:, None]).argmin(axis=1)
    iy = np.abs(ay[None, :] - np.asarray(py)[sample][:, None]).argmin(axis=1)
    vals = cube[:, iy, ix]
    vals = vals[np.isfinite(vals) & (vals > 0) & (vals < 80)]
    if not vals.size:
        return None
    return float(np.mean(vals)), float(np.min(vals)), float(np.max(vals))


def _offsets(f, pol, sel_p, epsg):
    base = f"{GRID}/pixelOffsets"
    if base not in f or pol not in f[base]:
        return None
    g = f[base]
    grp = g[pol]
    try:
        x = np.asarray((grp["xCoordinates"] if "xCoordinates" in grp else g["xCoordinates"])[()], dtype="float64")
        y = np.asarray((grp["yCoordinates"] if "yCoordinates" in grp else g["yCoordinates"])[()], dtype="float64")
        oepsg = _epsg(grp["projection"] if "projection" in grp else g["projection"])
    except (KeyError, AnalysisError):
        return None
    poly = sel_p if oepsg == epsg else reproject(Transformer.from_crs(epsg, oepsg, always_xy=True).transform, sel_p)
    left, bottom, right, top = poly.bounds
    sx, sy = _axis_slice(x, left, right), _axis_slice(y, bottom, top)
    if sx is None or sy is None or "slantRangeOffset" not in grp or "alongTrackOffset" not in grp:
        return None
    rg = np.asarray(grp["slantRangeOffset"][sy, sx], dtype="float64")
    az = np.asarray(grp["alongTrackOffset"][sy, sx], dtype="float64")
    xx, yy = np.meshgrid(x[sx], y[sy])
    m = shapely.contains_xy(poly, xx, yy) & np.isfinite(rg) & np.isfinite(az)
    if m.sum() < 10:
        return None
    mag = np.hypot(rg[m], az[m])
    return {
        "pixels": int(m.sum()),
        "median_m": float(np.median(mag)),
        "p90_m": float(np.percentile(mag, 90)),
        "median_range_m": float(np.median(rg[m])),
        "median_along_track_m": float(np.median(az[m])),
    }


# ---------------------------------------------------------------------------
# Statistics, series and map layers
# ---------------------------------------------------------------------------

def spatial_stats(values: np.ndarray) -> dict:
    if not values.size:
        return {"pixels": 0}
    return {
        "pixels": int(values.size),
        "mean": float(np.mean(values)),
        "median": float(np.median(values)),
        "p10": float(np.percentile(values, 10)),
        "p90": float(np.percentile(values, 90)),
        "std": float(np.std(values)),
        "min": float(np.min(values)),
        "max": float(np.max(values)),
    }


def nice_limit(v: float) -> float:
    if v <= 0 or not math.isfinite(v):
        return 5.0
    exp = 10 ** math.floor(math.log10(v))
    for m in (1, 2, 2.5, 5, 10):
        if v <= m * exp:
            return m * exp
    return 10 * exp


DIVERGING = [  # from "away from satellite" (red) to "towards satellite" (blue)
    (165, 0, 38), (215, 48, 39), (244, 109, 67), (253, 174, 97),
    (247, 247, 247),
    (171, 217, 233), (116, 173, 209), (69, 117, 180), (49, 54, 149),
]


def diverging_layer(sel: Selection, pair_like, values2d: np.ndarray, x: np.ndarray, y: np.ndarray, epsg: int,
                    limit: float):
    bounds = sel.bounds
    lon2d, lat2d = mercator_grid(bounds, 640)
    px, py = Transformer.from_crs(4326, epsg, always_xy=True).transform(lon2d, lat2d)
    ix, okx = nearest_index(x, np.asarray(px))
    iy, oky = nearest_index(y, np.asarray(py))
    inside = mask_inside(sel.polygon, lon2d, lat2d)
    vals = np.where(okx & oky, values2d[iy, ix], np.nan)
    n = len(DIVERGING)
    edges = np.linspace(-limit, limit, n + 1)
    rgba = np.zeros(lon2d.shape + (4,), dtype=np.uint8)
    ok = inside & np.isfinite(vals)
    cls = np.clip(np.digitize(vals, edges[1:-1]), 0, n - 1)
    for k, rgb in enumerate(DIVERGING):
        m = ok & (cls == k)
        rgba[m, :3] = rgb
        rgba[m, 3] = 225
    nod = np.zeros_like(rgba)
    nm = inside & ~np.isfinite(vals)
    yy, xx = np.mgrid[0:rgba.shape[0], 0:rgba.shape[1]]
    stripes = ((xx + yy) // 4) % 2 == 0
    nod[nm, :3] = (107, 114, 128)
    nod[nm, 3] = np.where(stripes[nm], 190, 80).astype(np.uint8)
    classes = [
        {"min": round(float(edges[k]), 2), "max": round(float(edges[k + 1]), 2), "color": "#%02x%02x%02x" % rgb}
        for k, rgb in enumerate(DIVERGING)
    ]
    return png_overlay(rgba, bounds), png_overlay(nod, bounds), classes


def _r(v, d=1):
    return None if v is None else round(float(v), d)


def _source(pairs: list[PairData], collection: str | None) -> dict:
    s = dict(SOURCE_BASE)
    s["collection"] = collection
    s["products"] = [p.granule.granule_id for p in pairs if p.granule]
    return s


def _common_limitations_es():
    return [
        "La medición es el cambio de distancia entre el suelo y el satélite en la línea de visión (LOS), no un hundimiento vertical medido directamente.",
        "Los valores son relativos: cada par se refiere a la mediana de un anillo de píxeles alrededor del área. Si toda la región se mueve igual, ese movimiento no aparece.",
        "No se aplicaron correcciones ionosféricas ni troposféricas (el producto las incluye como capas separadas); pueden quedar señales atmosféricas de varios milímetros o más.",
        "Convención de signo usada: valores negativos = alejamiento del satélite (compatible con hundimiento). La especificación D-102272 no la declara explícitamente; verifícala con un punto de referencia conocido.",
        "Las zonas grises no tienen datos válidos (baja coherencia, agua o fuera del producto): no significan ausencia de movimiento.",
    ]


def _common_limitations_en():
    return [
        "The measurement is the change in ground-to-satellite distance along the line of sight (LOS), not directly measured vertical subsidence.",
        "Values are relative: each pair is referenced to the median of a ring of pixels around the area. If the whole region moves together, that motion is not shown.",
        "No ionospheric or tropospheric corrections were applied (the product ships them as separate layers); atmospheric signals of several millimetres or more may remain.",
        "Sign convention used: negative values = moving away from the satellite (consistent with subsidence). Spec D-102272 does not state it explicitly; verify it against a known reference point.",
        "Grey areas have no valid data (low coherence, water or outside the product): they do not mean no motion.",
    ]


def _find_pairs(sel, settings, start, end, stage, searcher, min_coverage=0.5):
    stage("searching")
    tried = []
    for collection in settings.nisar_collections:
        granules = searcher(sel, start, end, collection)
        tried.append((collection, len(granules)))
        stack = select_stack(granules, sel, min_coverage)
        if stack:
            return collection, stack, tried
    raise no_data(
        f"No hay productos NISAR GUNW que cubran al menos la mitad de esta área entre {start} y {end}. "
        f"Los productos existen desde {NISAR_FIRST_DATE} y no cubren todas las zonas en cada ciclo. "
        "Prueba otra zona, un período más largo o un área más pequeña.",
        f"No NISAR GUNW products cover at least half of this area between {start} and {end}. "
        f"Products exist since {NISAR_FIRST_DATE} and do not cover every area in every cycle. "
        "Try another area, a longer period or a smaller area.",
    )


def analyze_subsidence(sel: Selection, start: date, end: date, *, settings, opener: Opener,
                       searcher=None, stage=lambda s: None, min_coherence: float = 0.35,
                       check_cancel=lambda: None) -> dict:
    from config import user_agent

    searcher = searcher or (lambda s, a, b, c: search_granules(s, a, b, c, user_agent=user_agent(settings)))
    collection, stack, tried = _find_pairs(sel, settings, start, end, stage, searcher)
    chain = build_chain(stack, settings.nisar_max_pairs)
    ring = reference_ring(sel.polygon)

    stage("reading")
    pairs: list[PairData] = []
    skipped: list[dict] = []
    for g in chain:
        check_cancel()
        try:
            with opener(g) as f:
                pairs.append(read_pair(f, sel, ring, min_coherence, g))
        except AnalysisError as e:
            if e.kind in ("not_configured",):
                raise
            skipped.append({**g.describe(), "reason": {"es": e.es, "en": e.en}})
            break  # a gap breaks the chain: stop here, never bridge missing pairs
    if not pairs:
        raise no_data(
            "Se encontraron productos, pero ninguno tiene píxeles válidos para esta área.",
            "Products were found, but none has valid pixels for this area.",
        )

    stage("processing")
    series = [{"date": pairs[0].ref_date.isoformat(), "cumulative_los_mm": 0.0, "cumulative_vertical_mm": 0.0}]
    cum = 0.0
    cum_v = 0.0
    var = 0.0
    used: list[PairData] = []
    vertical_ok = True
    for p in pairs:
        if not p.referenced or not p.values().size:
            skipped.append({"reference_date": p.ref_date.isoformat(), "secondary_date": p.sec_date.isoformat(),
                            "reason": {"es": "Sin píxeles de referencia suficientes.",
                                       "en": "Not enough reference pixels."}})
            break
        med = float(np.median(p.values()))
        cum += med
        if p.incidence_deg:
            cum_v += med / math.cos(math.radians(p.incidence_deg[0]))
        else:
            vertical_ok = False
        if p.ref_noise_mm is not None:
            var += p.ref_noise_mm ** 2
        used.append(p)
        series.append({"date": p.sec_date.isoformat(), "cumulative_los_mm": round(cum, 2),
                       "cumulative_vertical_mm": round(cum_v, 2) if vertical_ok else None})
    if not used:
        raise no_data(
            "Ningún par tiene suficientes píxeles estables alrededor del área para usarlos como referencia. Amplía un poco el área o elige otra zona.",
            "No pair has enough stable pixels around the area to use as reference. Enlarge the area slightly or choose another zone.",
        )
    if not vertical_ok:
        for s in series:
            s["cumulative_vertical_mm"] = None

    first, last = used[0], used[-1]
    days = (last.sec_date - first.ref_date).days
    rate = None
    rate_method = None
    rate_se = None
    if len(series) >= 3:
        t = np.array([(date.fromisoformat(s["date"]) - first.ref_date).days / 365.25 for s in series])
        v = np.array([s["cumulative_los_mm"] for s in series])
        A = np.vstack([t, np.ones_like(t)]).T
        coef, res, *_ = np.linalg.lstsq(A, v, rcond=None)
        rate = float(coef[0])
        if len(series) > 2:
            resid = v - A @ coef
            s2 = float(resid @ resid) / (len(series) - 2)
            rate_se = math.sqrt(s2 / float(((t - t.mean()) ** 2).sum())) if ((t - t.mean()) ** 2).sum() > 0 else None
        rate_method = "linear_fit"
    elif days > 0:
        rate = cum / days * 365.25
        rate_method = "two_dates"

    # Cumulative map when all pairs share the same grid window; otherwise latest pair only.
    same_grid = all(p.x.shape == first.x.shape and p.y.shape == first.y.shape
                    and np.allclose(p.x, first.x) and np.allclose(p.y, first.y) for p in used)
    if same_grid:
        stack_arr = np.stack([np.where(p.usable_sel, p.los_rel_mm, np.nan) for p in used])
        map_values = np.sum(stack_arr, axis=0)  # NaN if any pair lacks the pixel
        map_kind = "cumulative"
    else:
        map_values = np.where(last.usable_sel, last.los_rel_mm, np.nan)
        map_kind = "latest_pair"
    finite = map_values[np.isfinite(map_values)]
    stats_map = spatial_stats(finite)
    limit = nice_limit(max(abs(stats_map.get("p10", 5)), abs(stats_map.get("p90", 5)), 2 * (stats_map.get("std", 0) or 0), 5))
    layer, nod, classes = diverging_layer(sel, last, map_values, first.x, first.y, first.epsg, limit)

    inc = [p.incidence_deg for p in used if p.incidence_deg]
    pair_rows = []
    for p in used:
        st = spatial_stats(p.values())
        pair_rows.append({
            "reference_date": p.ref_date.isoformat(), "secondary_date": p.sec_date.isoformat(), "days": p.days,
            "median_los_mm": _r(st.get("median"), 2), "mean_los_mm": _r(st.get("mean"), 2),
            "spatial_std_mm": _r(st.get("std"), 2), "p10_mm": _r(st.get("p10"), 2), "p90_mm": _r(st.get("p90"), 2),
            "valid_pixels": st["pixels"], "valid_coverage_pct": _r(100 * p.valid_area_km2 / p.selected_area_km2, 1),
            "mean_coherence": _r(np.nanmean(p.coherence[p.usable_sel]) if p.usable_sel.any() else None, 2),
            "reference_noise_mm": _r(p.ref_noise_mm, 2), "reference_pixels": p.ref_pixels,
            "incidence_deg": _r(p.incidence_deg[0], 2) if p.incidence_deg else None,
            "granule": p.granule.granule_id if p.granule else None,
        })

    total_v = series[-1]["cumulative_vertical_mm"]
    cov = [r["valid_coverage_pct"] for r in pair_rows if r["valid_coverage_pct"] is not None]
    g0 = first.granule
    return {
        "module": "hundimiento",
        "measurement": {"es": "Desplazamiento relativo en la línea de visión del satélite (LOS)",
                        "en": "Relative displacement along the satellite line of sight (LOS)"},
        "source": _source(used, collection),
        "geometry": {"track": g0.track if g0 else None, "frame": g0.frame if g0 else None,
                     "direction": g0.direction if g0 else None, "polarization": first.polarization,
                     "wavelength_cm": round(first.wavelength_m * 100, 2), "epsg": first.epsg,
                     "incidence_deg_range": [round(min(i[1] for i in inc), 2), round(max(i[2] for i in inc), 2)] if inc else None},
        "period": {"start": first.ref_date.isoformat(), "end": last.sec_date.isoformat(), "days": days,
                   "requested_start": start.isoformat(), "requested_end": end.isoformat()},
        "metrics": {
            "observations": len(series),
            "pairs_used": len(used),
            "cumulative_los_mm": _r(cum, 1),
            "cumulative_vertical_estimate_mm": _r(total_v, 1) if total_v is not None else None,
            "rate_los_mm_per_year": _r(rate, 1),
            "rate_standard_error_mm_per_year": _r(rate_se, 1),
            "rate_method": rate_method,
            "uncertainty_indicative_mm": _r(math.sqrt(var), 1) if var else None,
            "selected_area_km2": _r(first.selected_area_km2, 2),
            "valid_coverage_pct_min": min(cov) if cov else None,
            "valid_coverage_pct_max": max(cov) if cov else None,
            "map_spatial": {k: _r(v, 1) if k != "pixels" else v for k, v in stats_map.items()},
            "map_kind": map_kind,
            "other_component_pixels_excluded": int(sum(p.other_component_pixels for p in used)),
        },
        "stats_scope": {
            "es": "Mediana, percentiles y desviación son espaciales (píxeles del área en cada período). La tasa es temporal (cambio por año).",
            "en": "Median, percentiles and deviation are spatial (pixels inside the area for each period). The rate is temporal (change per year).",
        },
        "series": series,
        "pairs": pair_rows,
        "skipped": skipped,
        "available_pairs": len(stack),
        "catalogue": [{"collection": c, "granules_found": n} for c, n in tried],
        "layers": {"displacement": layer, "no_data": nod},
        "legend": {
            "classes": classes, "unit": "mm",
            "es": ("Desplazamiento acumulado LOS relativo" if map_kind == "cumulative" else "Desplazamiento LOS del último par")
                  + ". Rojo: alejamiento del satélite (compatible con hundimiento). Azul: acercamiento. Gris rayado: sin datos.",
            "en": ("Relative cumulative LOS displacement" if map_kind == "cumulative" else "LOS displacement of the latest pair")
                  + ". Red: away from the satellite (consistent with subsidence). Blue: towards it. Grey stripes: no data.",
        },
        "limitations": {
            "es": _common_limitations_es() + [
                "La estimación vertical divide el LOS por el coseno del ángulo de incidencia del producto y supone que no hay movimiento horizontal." if vertical_ok
                else "El producto no trae ángulo de incidencia utilizable: solo se muestra el desplazamiento LOS.",
                "Con solo dos fechas no se puede saber si el cambio fue gradual o repentino." if len(series) == 2
                else "La tasa es un ajuste lineal; no describe aceleraciones ni movimientos estacionales.",
            ],
            "en": _common_limitations_en() + [
                "The vertical estimate divides LOS by the cosine of the product incidence angle and assumes no horizontal motion." if vertical_ok
                else "The product has no usable incidence angle: only LOS displacement is shown.",
                "With only two dates it is impossible to tell whether the change was gradual or sudden." if len(series) == 2
                else "The rate is a linear fit; it does not describe acceleration or seasonal motion.",
            ],
        },
    }


def analyze_glacier(sel: Selection, start: date, end: date, *, settings, opener: Opener, searcher=None,
                    outlines: dict | None = None, stage=lambda s: None, min_coherence: float = 0.3,
                    check_cancel=lambda: None) -> dict:
    """Latest usable pair over the glacier. Reference = off-glacier pixels when outlines exist."""
    from config import user_agent

    searcher = searcher or (lambda s, a, b, c: search_granules(s, a, b, c, user_agent=user_agent(settings)))
    collection, stack, tried = _find_pairs(sel, settings, start, end, stage, searcher)
    ice_poly = shape(outlines["union"]) if outlines and outlines.get("union") else None

    ref_fn = None
    if ice_poly is not None and not ice_poly.is_empty:
        def ref_fn(xx, yy, epsg):
            ice_p = reproject(Transformer.from_crs(4326, epsg, always_xy=True).transform, ice_poly)
            return ~shapely.contains_xy(ice_p, xx, yy)

    ring = reference_ring(sel.polygon)
    stage("reading")
    pair = None
    errors = []
    for g in sorted(stack, key=lambda g: g.sec_date, reverse=True)[:3]:
        check_cancel()
        try:
            with opener(g) as f:
                p = read_pair(f, sel, ring, min_coherence, g, reference_mask_fn=ref_fn, read_offsets=True)
            if p.referenced and p.values().size:
                pair = p
                break
            errors.append(g.describe())
        except AnalysisError as e:
            if e.kind == "not_configured":
                raise
            errors.append({**g.describe(), "reason": {"es": e.es, "en": e.en}})
    if pair is None:
        raise no_data(
            "Los productos más recientes no tienen suficientes píxeles coherentes sobre esta zona. "
            "Sobre hielo rápido la señal radar suele perder coherencia en 12 días. Prueba un área con borde rocoso o elige otro glaciar.",
            "The latest products do not have enough coherent pixels over this area. "
            "Over fast ice the radar signal often decorrelates within 12 days. Try an area including rocky margins or another glacier.",
        )

    stage("processing")
    vals = pair.values()
    st = spatial_stats(vals)
    on_ice = None
    if ice_poly is not None:
        ice_p = reproject(Transformer.from_crs(4326, pair.epsg, always_xy=True).transform, ice_poly)
        xx, yy = np.meshgrid(pair.x, pair.y)
        ice_mask = shapely.contains_xy(ice_p, xx, yy) & pair.usable_sel
        on_ice = spatial_stats(pair.los_rel_mm[ice_mask])
    limit = nice_limit(max(abs(st.get("p10", 5)), abs(st.get("p90", 5)), 5))
    layer, nod, classes = diverging_layer(sel, pair, np.where(pair.usable_sel, pair.los_rel_mm, np.nan),
                                          pair.x, pair.y, pair.epsg, limit)
    days = max(1, pair.days)
    rate = lambda mm: None if mm is None else mm / days * 365.25 / 1000  # m/yr
    off = pair.offsets
    g0 = pair.granule
    return {
        "module": "glaciares",
        "measurement": {"es": "Desplazamiento relativo del hielo en la línea de visión (LOS)",
                        "en": "Relative ice displacement along the line of sight (LOS)"},
        "source": _source([pair], collection),
        "geometry": {"track": g0.track if g0 else None, "frame": g0.frame if g0 else None,
                     "direction": g0.direction if g0 else None, "polarization": pair.polarization,
                     "wavelength_cm": round(pair.wavelength_m * 100, 2), "epsg": pair.epsg,
                     "projection_note": {"es": f"Producto en EPSG:{pair.epsg}; reproyectado a Web Mercator solo para el mapa.",
                                         "en": f"Product in EPSG:{pair.epsg}; reprojected to Web Mercator only for the map."}},
        "period": {"start": pair.ref_date.isoformat(), "end": pair.sec_date.isoformat(), "days": pair.days,
                   "requested_start": start.isoformat(), "requested_end": end.isoformat()},
        "metrics": {
            "observations": 2,
            "median_los_mm": _r(st.get("median"), 1), "p10_los_mm": _r(st.get("p10"), 1),
            "p90_los_mm": _r(st.get("p90"), 1), "spatial_std_mm": _r(st.get("std"), 1),
            "median_rate_los_m_per_year": _r(rate(st.get("median")), 3),
            "p90_abs_rate_los_m_per_year": _r(rate(float(np.percentile(np.abs(vals), 90))) if vals.size else None, 3),
            "on_ice_median_los_mm": _r(on_ice.get("median"), 1) if on_ice and on_ice["pixels"] else None,
            "on_ice_pixels": on_ice["pixels"] if on_ice else None,
            "valid_pixels": st["pixels"],
            "valid_coverage_pct": _r(100 * pair.valid_area_km2 / pair.selected_area_km2, 1),
            "selected_area_km2": _r(pair.selected_area_km2, 2),
            "mean_coherence": _r(np.nanmean(pair.coherence[pair.usable_sel]), 2),
            "reference": "off_glacier" if ref_fn else "ring",
            "reference_noise_mm": _r(pair.ref_noise_mm, 1),
            "offsets_median_m": _r(off["median_m"], 2) if off else None,
            "offsets_p90_m": _r(off["p90_m"], 2) if off else None,
            "offsets_pixels": off["pixels"] if off else None,
            "glacier_outline_area_km2": outlines.get("area_km2") if outlines else None,
        },
        "stats_scope": {
            "es": "Las estadísticas son espaciales: describen los píxeles válidos del área durante un único par de fechas.",
            "en": "Statistics are spatial: they describe the valid pixels of the area for a single pair of dates.",
        },
        "spatial": {k: _r(v, 1) if k != "pixels" else v for k, v in st.items()},
        "available_pairs": len(stack),
        "skipped": errors,
        "catalogue": [{"collection": c, "granules_found": n} for c, n in tried],
        "layers": {"displacement": layer, "no_data": nod},
        "legend": {
            "classes": classes, "unit": "mm",
            "es": f"Desplazamiento LOS entre {pair.ref_date} y {pair.sec_date}. Rojo: alejamiento del satélite. Azul: acercamiento. Gris rayado: sin datos (frecuente sobre hielo rápido).",
            "en": f"LOS displacement between {pair.ref_date} and {pair.sec_date}. Red: away from the satellite. Blue: towards it. Grey stripes: no data (common over fast ice).",
        },
        "limitations": {
            "es": _common_limitations_es()[:4] + [
                "Sobre glaciares rápidos la fase puede perder coherencia o desenrollarse mal; las zonas sin datos suelen ser las de mayor velocidad.",
                "El LOS no da la dirección del flujo: un mismo flujo puede verse como acercamiento o alejamiento según la órbita.",
                "La tasa anual extrapola un intervalo de pocos días y no incluye variaciones estacionales.",
                "Los desplazamientos por correlación (offsets) están en metros y en geometría radar; son una indicación de la magnitud, no la velocidad del hielo en el terreno.",
            ],
            "en": _common_limitations_en()[:4] + [
                "Over fast glaciers the phase may decorrelate or unwrap incorrectly; no-data areas are often the fastest ones.",
                "LOS does not give the flow direction: the same flow can look like approaching or receding depending on the orbit.",
                "The annual rate extrapolates an interval of a few days and does not include seasonal changes.",
                "Correlation offsets are in metres in radar geometry; they indicate magnitude, not ground ice velocity.",
            ],
        },
    }
