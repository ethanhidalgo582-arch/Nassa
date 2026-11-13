"""Prueba real de extremo a extremo; consume una solicitud de Gemini."""
import json
import sys

from fastapi.testclient import TestClient

from main import app


def main():
    with TestClient(app, raise_server_exceptions=False) as client:
        health = client.get("/api/v1/health").json()
        if not health["gemini"]["configured"]:
            print("Falta GEMINI_API_KEY en backend/.env.")
            return 1
        response = client.post("/api/v1/ai/analyze", json={
            "latitude": 14.6349,
            "longitude": -90.5069,
            "question": "Resume el ejemplo e indica si son datos reales.",
        })
        if response.status_code != 200:
            try:
                detail = response.json().get("detail", "Error sin detalle público.")
            except ValueError:
                detail = "Error interno; consulta la configuración del servidor."
            print(json.dumps({"status": response.status_code, "detail": detail}, ensure_ascii=True))
            return 1
        result = response.json()
        print(json.dumps({
            "status": "ok",
            "model": result["model"],
            "data_source": result["data_source"],
            "is_simulated": result["is_simulated"],
            "summary": result["analysis"]["summary"],
        }, ensure_ascii=True))
        return 0


if __name__ == "__main__":
    sys.exit(main())

