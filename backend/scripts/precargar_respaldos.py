# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Pre-load the NISAR backups for the example areas (run once, it can take a while).

Usage (from the project root):  backend\\.venv\\Scripts\\python.exe backend\\scripts\\precargar_respaldos.py
Each example area is analysed with live satellite data; every success is saved in
backend/datos_precargados/ and used as a backup when the live download is slow.
Prints how long each area took so slow areas are easy to spot.
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)
os.environ.setdefault("JOB_TIMEOUT_SECONDS", "3600")

from fastapi.testclient import TestClient  # noqa: E402

import main  # noqa: E402

# Same rectangles as mobile/lib/session.dart (south, west, north, east).
PRESETS = {
    "hundimiento": {
        "Ciudad de México (oriente)": (19.34, -99.10, 19.40, -99.04),
        "Valle de San Joaquín": (36.05, -119.65, 36.15, -119.50),
        "Yakarta norte": (-6.16, 106.75, -6.10, 106.85),
    },
    "glaciares": {
        "Sermeq Kujalleq / Jakobshavn": (69.10, -49.95, 69.25, -49.40),
        "Perito Moreno": (-50.58, -73.32, -50.42, -73.00),
        "Gran Glaciar de Aletsch": (46.40, 7.95, 46.55, 8.10),
    },
}


def polygon(s, w, n, e):
    # Same corner order and [lat, lon] format the app sends.
    return [[n, w], [n, e], [s, e], [s, w]]


def main_():
    only = set(sys.argv[1:])
    app = main.create_app()
    with TestClient(app) as c:
        for module, areas in PRESETS.items():
            for name, box in areas.items():
                if only and name not in only:
                    continue
                t0 = time.time()
                job = c.post("/api/v1/analyses", json={"module": module, "polygon": polygon(*box)}).json()
                while job.get("status") in ("queued", "running"):
                    time.sleep(5)
                    job = c.get(f"/api/v1/analyses/{job['job_id']}").json()
                took = time.time() - t0
                if job.get("status") == "done":
                    tag = "RESPALDO (live lento)" if job["result"].get("backup") else "OK en vivo, respaldo guardado"
                else:
                    tag = f"ERROR {(job.get('error') or {}).get('kind')}: {(job.get('error') or {}).get('es')}"
                print(f"[{module}] {name}: {took:.0f} s -> {tag}", flush=True)


if __name__ == "__main__":
    main_()
