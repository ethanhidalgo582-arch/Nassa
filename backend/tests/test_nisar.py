# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
import contextlib
from datetime import date, timedelta

import h5py
import numpy as np
import pytest
from pyproj import Transformer

import nisar_service as ns
from config import Settings
from errors import AnalysisError
from geo import parse_selection, reference_ring
from tests.fixtures_gunw import granule_for, make_gunw


def _selection_in_grid(x, y, epsg=32614, half=1200):
    inv = Transformer.from_crs(epsg, 4326, always_xy=True).transform
    cx, cy = x.mean(), y.mean()
    pts = []
    for dx, dy in ((-half, -half), (half, -half), (half, half), (-half, half)):
        lon, lat = inv(cx + dx, cy + dy)
        pts.append([lat, lon])
    return parse_selection(pts, 10_000)


def test_read_pair_references_and_converts(tmp_path):
    x, y = make_gunw(tmp_path / "a.h5", date(2026, 1, 1), date(2026, 1, 13), subsidence_mm=-20)
    sel = _selection_in_grid(x, y)
    with h5py.File(tmp_path / "a.h5") as f:
        p = ns.read_pair(f, sel, reference_ring(sel.polygon), 0.35)
    assert p.referenced and p.days == 12
    v = p.values()
    # Bowl centre = -20 mm, reference ring is stable ground; the unwrapping offset must cancel.
    assert -21 < v.min() < -18
    assert -6 < v.mean() < -3
    assert p.incidence_deg and abs(p.incidence_deg[0] - 38) < 1e-3
    assert 0 < p.valid_area_km2 <= p.selected_area_km2


def test_low_coherence_is_no_data_not_zero(tmp_path):
    x, y = make_gunw(tmp_path / "a.h5", date(2026, 1, 1), date(2026, 1, 13), subsidence_mm=-20, coherence=0.1)
    sel = _selection_in_grid(x, y)
    with h5py.File(tmp_path / "a.h5") as f:
        p = ns.read_pair(f, sel, reference_ring(sel.polygon), 0.35)
    assert not p.referenced and p.values().size == 0


def test_chain_only_consecutive_pairs():
    d = date(2026, 1, 1)
    fp = (-1, -1, 1, 1)
    gs = [granule_for("u", d + timedelta(12 * i), d + timedelta(12 * (i + 1)), fp) for i in range(4)]
    gs.append(granule_for("u", d + timedelta(100), d + timedelta(112), fp))  # isolated pair after a gap
    chain = ns.build_chain(gs, 10)
    assert [g.ref_date for g in chain] == [d + timedelta(12 * i) for i in range(4)]
    assert ns.build_chain(gs, 2)[-1].sec_date == d + timedelta(48)


def test_stack_never_mixes_geometries():
    sel = parse_selection([[0.1, 0.1], [0.1, 0.3], [0.3, 0.3], [0.3, 0.1]], 10_000)
    d = date(2026, 1, 1)
    a = [granule_for("u", d + timedelta(12 * i), d + timedelta(12 * (i + 1)), (0, 0, 1, 1), "A") for i in range(3)]
    b = [granule_for("u", d, d + timedelta(12), (0, 0, 1, 1), "B")]
    assert {g.stack_id for g in ns.select_stack(a + b, sel)} == {"A"}


def test_subsidence_series_two_dates_and_chain(tmp_path):
    d0 = date(2026, 1, 1)
    files = {}
    for i, mm in enumerate([-10, -12, -8]):
        p = tmp_path / f"p{i}.h5"
        x, y = make_gunw(p, d0 + timedelta(12 * i), d0 + timedelta(12 * (i + 1)), subsidence_mm=mm)
        files[f"url{i}"] = p
    sel = _selection_in_grid(x, y)
    w, s, e, n = sel.polygon.buffer(0.2).bounds
    granules = [granule_for(f"url{i}", d0 + timedelta(12 * i), d0 + timedelta(12 * (i + 1)), (w, s, e, n)) for i in range(3)]

    @contextlib.contextmanager
    def opener(g):
        with h5py.File(files[g.url]) as f:
            yield f

    settings = Settings(nisar_collections=("TEST",), nisar_max_pairs=6)
    res = ns.analyze_subsidence(sel, d0, d0 + timedelta(60), settings=settings, opener=opener,
                                searcher=lambda *a: granules)
    assert res["metrics"]["observations"] == 4 and len(res["series"]) == 4
    assert res["series"][0]["cumulative_los_mm"] == 0.0
    assert res["series"][-1]["cumulative_los_mm"] < 0
    assert res["metrics"]["rate_method"] == "linear_fit"
    assert res["metrics"]["map_kind"] == "cumulative"
    assert res["layers"]["displacement"]["image_base64"]

    # Only two observations: no invented intermediate points.
    res2 = ns.analyze_subsidence(sel, d0, d0 + timedelta(60), settings=settings, opener=opener,
                                 searcher=lambda *a: granules[:1])
    assert [s["date"] for s in res2["series"]] == [d0.isoformat(), (d0 + timedelta(12)).isoformat()]
    assert res2["metrics"]["rate_method"] == "two_dates"


def test_no_coverage_is_explained():
    sel = parse_selection([[10, 10], [10, 10.1], [10.1, 10.1], [10.1, 10]], 10_000)
    with pytest.raises(AnalysisError) as e:
        ns.analyze_subsidence(sel, date(2026, 1, 1), date(2026, 2, 1), settings=Settings(nisar_collections=("TEST",)),
                              opener=None, searcher=lambda *a: [])
    assert e.value.kind == "no_data" and e.value.en


def test_parse_real_umm_shape():
    item = {"umm": {
        "GranuleUR": "G1",
        "AdditionalAttributes": [
            {"Name": "REFERENCE_ZERO_DOPPLER_START_TIME", "Values": ["2026-10-09T23:53:35.000000Z"]},
            {"Name": "SECONDARY_ZERO_DOPPLER_START_TIME", "Values": ["2026-10-21T23:53:35.000000Z"]},
            {"Name": "TRACK_NUMBER", "Values": ["141"]}, {"Name": "FRAME_NUMBER", "Values": ["85"]},
            {"Name": "ASCENDING_DESCENDING", "Values": ["DESCENDING"]}, {"Name": "STACK_ID", "Values": ["141_D_085"]},
            {"Name": "FREQUENCY_A_POLARIZATION", "Values": ["HH"]}],
        "RelatedUrls": [{"URL": "https://x/G1.h5", "Type": "GET DATA"}, {"URL": "s3://x/G1.h5"}],
        "SpatialExtent": {"HorizontalSpatialDomain": {"Geometry": {"GPolygons": [{"Boundary": {"Points": [
            {"Latitude": 0, "Longitude": 0}, {"Latitude": 0, "Longitude": 1}, {"Latitude": 1, "Longitude": 1},
            {"Latitude": 0, "Longitude": 0}]}}]}}},
    }}
    g = ns.parse_umm(item, "C")
    assert g.url == "https://x/G1.h5" and g.days == 12 and g.stack_id == "141_D_085"
