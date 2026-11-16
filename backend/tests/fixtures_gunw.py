"""TEST-ONLY synthetic GUNW files following the JPL D-102272 layout.

These files exist only inside pytest temporary folders. They are never used by the
application at runtime and every value they contain is artificial.
"""
from __future__ import annotations

import math
from datetime import date, datetime, timezone

import h5py
import numpy as np
from shapely.geometry import box

from nisar_service import Granule

FREQ = 1.257e9
WAVELENGTH = 299_792_458.0 / FREQ


def make_gunw(path, ref: date, sec: date, *, subsidence_mm: float, x0=480_000.0, y0=2_150_000.0,
              n=120, step=80.0, epsg=32614, coherence=0.8, incidence=38.0, with_cc=True, bowl_m=1100.0):
    """Bowl of LOS displacement (`subsidence_mm`, negative = away) centred in the grid; stable rim."""
    x = x0 + np.arange(n) * step
    y = y0 + (n - 1 - np.arange(n)) * step  # descending, as in north-up products
    xx, yy = np.meshgrid(x, y)
    cx, cy = x.mean(), y.mean()
    r = np.hypot(xx - cx, yy - cy)
    los_mm = subsidence_mm * np.clip(1 - r / bowl_m, 0, 1)
    phase = los_mm / 1000.0 * 4 * math.pi / WAVELENGTH / -1.0  # inverse of d = -lambda/4pi * phase
    phase += 3.0  # arbitrary constant offset of the unwrapping (must cancel after referencing)
    with h5py.File(path, "w") as f:
        f["/science/LSAR/identification/referenceZeroDopplerStartTime"] = np.bytes_(f"{ref.isoformat()}T12:00:00.000000000")
        f["/science/LSAR/identification/secondaryZeroDopplerStartTime"] = np.bytes_(f"{sec.isoformat()}T12:00:00.000000000")
        g = f.create_group("/science/LSAR/GUNW/grids/frequencyA")
        g["centerFrequency"] = FREQ
        u = g.create_group("unwrappedInterferogram")
        u["xCoordinates"] = x
        u["yCoordinates"] = y
        u["projection"] = np.uint32(epsg)
        hh = u.create_group("HH")
        ds = hh.create_dataset("unwrappedPhase", data=phase.astype("float32"))
        ds.attrs["units"] = np.bytes_("radians")
        coh = np.full((n, n), coherence, dtype="float32")
        coh[:5, :5] = np.nan
        hh["coherenceMagnitude"] = coh
        if with_cc:
            cc = np.ones((n, n), dtype="uint16")
            cc[-3:, -3:] = 65535
            hh["connectedComponents"] = cc
        rg = f.create_group("/science/LSAR/GUNW/metadata/radarGrid")
        rg["xCoordinates"] = x[::10]
        rg["yCoordinates"] = y[::10]
        rg["projection"] = np.uint32(epsg)
        rg["incidenceAngle"] = np.full((3, len(y[::10]), len(x[::10])), incidence, dtype="float32")
    return x, y


def granule_for(url: str, ref: date, sec: date, footprint_lonlat, stack="141_D_085") -> Granule:
    return Granule(
        granule_id=f"TEST_GUNW_{ref:%Y%m%d}_{sec:%Y%m%d}", collection="TEST", url=url,
        ref_start=datetime(ref.year, ref.month, ref.day, tzinfo=timezone.utc),
        sec_start=datetime(sec.year, sec.month, sec.day, tzinfo=timezone.utc),
        track="141", frame="85", direction="DESCENDING", stack_id=stack, polarization="HH",
        footprint=box(*footprint_lonlat),
    )
