# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Manual end-to-end check (consumes one Gemini request and reads real Hansen data).

Usage (from backend/):  python scripts/check_gemini.py
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402

from main import create_app  # noqa: E402


def main() -> int:
    with TestClient(create_app()) as c:
        if not c.get("/api/v1/config").json()["gemini_configured"]:
            print("GEMINI_API_KEY is not set in backend/.env")
            return 1
        poly = [[17.30, -90.10], [17.30, -90.05], [17.25, -90.05], [17.25, -90.10]]
        job = c.post("/api/v1/analyses", json={"module": "bosques", "polygon": poly}).json()
        while job["status"] in ("queued", "running"):
            time.sleep(1)
            job = c.get(f"/api/v1/analyses/{job['job_id']}").json()
        if job["status"] != "done":
            print(job["error"])
            return 1
        for locale in ("es", "en"):
            r = c.post("/api/v1/interpret", json={"result_id": job["result"]["result_id"], "locale": locale})
            print(locale, r.status_code, r.json())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
