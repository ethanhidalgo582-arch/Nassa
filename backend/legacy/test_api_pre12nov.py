import asyncio
import json
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient
from google import genai
from google.genai import types

from config import Settings
from main import create_app

REPORT = {
    "summary": "Esta es una demostración con datos simulados.",
    "observations": ["Desplazamiento LOS ilustrativo de -22.9 mm."],
    "limitations": ["No es una medición satelital."],
    "suggested_next_steps": ["Validar productos NISAR y su georreferenciación."],
}
POINT = {"latitude": 14.6349, "longitude": -90.5069}


@pytest.fixture
def client():
    with TestClient(create_app(Settings())) as test_client:
        yield test_client


def test_demo_starts_without_earthdata_or_gemini(client):
    health = client.get("/api/v1/health").json()
    assert health["data_mode"] == "demo"
    assert health["gemini"]["configured"] is False
    zones = client.get("/api/v1/classified-zones").json()
    assert zones["features"][0]["properties"]["is_simulated"] is True
    assert client.get("/api/v1/disaster-zones").json() == zones
    data = client.get("/api/v1/displacement?lat=14.6349&lng=-90.5069").json()
    assert data["source"] == "demo_simulada"
    assert data["history"][-1]["displacement_mm"] == data["current_displacement_mm"]
    assert client.get("/api/v1/dashboard-stats").json()["criticalAreaKm2"] is None


def test_missing_key_is_actionable(client):
    response = client.post("/api/v1/ai/analyze", json=POINT)
    assert response.status_code == 503
    assert "configurado" in response.json()["detail"]


@pytest.mark.parametrize("payload", [
    {"latitude": 91, "longitude": -90},
    {"latitude": 14, "longitude": -181},
    {**POINT, "question": ""},
    {**POINT, "question": "   "},
    {**POINT, "question": "x" * 1001},
    {**POINT, "context": {"is_simulated": False}},
    {**POINT, "latitude": "NaN"},
    {**POINT, "longitude": "Infinity"},
])
def test_rejects_invalid_requests(client, payload):
    assert client.post("/api/v1/ai/analyze", json=payload).status_code == 422


@pytest.mark.parametrize("query", ["lat=91&lng=0", "lat=NaN&lng=0", "lat=0&lng=Infinity"])
def test_rejects_invalid_map_coordinates(client, query):
    assert client.get("/api/v1/displacement?" + query).status_code == 422


def test_outside_coverage_does_not_call_gemini(client):
    mocked = AsyncMock()
    client.app.state.gemini.analyze = mocked
    assert client.get("/api/v1/displacement?lat=0&lng=0").status_code == 404
    assert client.post("/api/v1/ai/analyze", json={"latitude": 0, "longitude": 0}).status_code == 404
    mocked.assert_not_awaited()


def sdk_response(text):
    return {
        "candidates": [{
            "content": {"role": "model", "parts": [{"text": text}]},
            "finishReason": "STOP",
        }]
    }


def install_transport(client, handler):
    # Exercise the real SDK serialization while blocking all external network.
    client.app.state.gemini.client = genai.Client(
        api_key="test-key-only",
        vertexai=False,
        http_options=types.HttpOptions(
            retry_options=types.HttpRetryOptions(attempts=1),
            async_client_args={"transport": httpx.MockTransport(handler)},
        ),
    )


def test_sdk_request_and_response_keep_server_provenance(client):
    captured = []

    def handler(request):
        captured.append(request)
        return httpx.Response(200, json=sdk_response(json.dumps(REPORT)))

    install_transport(client, handler)
    response = client.post("/api/v1/ai/analyze", json={**POINT, "question": "Explica la zona"})
    assert response.status_code == 200
    assert response.json()["analysis"] == REPORT
    assert response.json()["is_simulated"] is True
    assert response.json()["data_source"] == "demo_simulada"
    assert "simulados" in response.json()["notice"]
    request = captured[0]
    assert request.url.host == "generativelanguage.googleapis.com"
    assert "generateContent" in request.url.path
    assert request.headers["x-goog-api-key"] == "test-key-only"
    body = json.loads(request.content)
    contents = json.loads(body["contents"][0]["parts"][0]["text"])
    assert contents["context"]["is_simulated"] is True
    assert contents["context"]["latitude"] == POINT["latitude"]
    assert contents["question"] == "Explica la zona"
    assert body["generationConfig"]["responseMimeType"] == "application/json"
    assert body["systemInstruction"]
    assert len(captured) == 1


@pytest.mark.parametrize(("upstream_status", "expected"), [
    (400, 503), (401, 503), (403, 503), (404, 503), (429, 429), (500, 502), (503, 502),
])
def test_provider_errors_are_sanitized(client, upstream_status, expected):
    def handler(request):
        return httpx.Response(upstream_status, json={
            "error": {"code": upstream_status, "message": "secret-upstream-detail"}
        })

    install_transport(client, handler)
    response = client.post("/api/v1/ai/analyze", json=POINT)
    assert response.status_code == expected
    assert "secret-upstream-detail" not in response.text
    assert "test-key-only" not in response.text


@pytest.mark.parametrize("text", ["", "not json", "{}", '{"summary": ""}'])
def test_empty_or_invalid_model_output(client, text):
    install_transport(client, lambda request: httpx.Response(200, json=sdk_response(text)))
    assert client.post("/api/v1/ai/analyze", json=POINT).status_code == 502


def test_network_error(client):
    def handler(request):
        raise httpx.ConnectError("private connection detail", request=request)

    install_transport(client, handler)
    response = client.post("/api/v1/ai/analyze", json=POINT)
    assert response.status_code == 502
    assert "private" not in response.text


def test_timeout(client):
    async def handler(request):
        await asyncio.sleep(1)
        return httpx.Response(200, json=sdk_response(json.dumps(REPORT)))

    install_transport(client, handler)
    client.app.state.gemini.settings = Settings(gemini_timeout_seconds=0.01)
    assert client.post("/api/v1/ai/analyze", json=POINT).status_code == 504


def test_health_does_not_disclose_credentials():
    with TestClient(create_app(Settings(gemini_api_key="test-secret"))) as client:
        response = client.get("/api/v1/health")
        assert response.json()["gemini"]["configured"] is True
        assert response.json()["gemini"]["connection_verified"] is False
        assert "test-secret" not in response.text


def test_only_configured_web_origins_are_allowed(client):
    allowed = client.options("/api/v1/ai/analyze", headers={
        "Origin": "http://localhost:3000",
        "Access-Control-Request-Method": "POST",
        "Access-Control-Request-Headers": "content-type",
    })
    assert allowed.status_code == 200
    blocked = client.options("/api/v1/ai/analyze", headers={
        "Origin": "https://untrusted.example",
        "Access-Control-Request-Method": "POST",
    })
    assert blocked.status_code == 400

