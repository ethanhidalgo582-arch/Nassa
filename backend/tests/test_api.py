"""API, job and interpretation tests. All data here is TEST-ONLY and synthetic."""
import time
import types

import numpy as np
import pytest
from fastapi.testclient import TestClient

import forest_service
import gemini_service
import main
import summaries
from config import Settings
from errors import AnalysisError
from geo import parse_selection

POLY = [[17.30, -90.10], [17.30, -90.05], [17.25, -90.05], [17.25, -90.10]]


def wait(client, job, timeout=10):
    t = time.time()
    while job["status"] in ("queued", "running"):
        assert time.time() - t < timeout, job
        time.sleep(0.05)
        job = client.get(f"/api/v1/analyses/{job['job_id']}").json()
    return job


def synthetic_reader(layer, win):
    """TEST-ONLY Hansen-like layers: land everywhere, forest in the west half, loss in 2018 in a stripe."""
    h, w = win.height, win.width
    if layer == "datamask":
        a = np.ones((h, w), np.uint8)
        a[: h // 10] = 0  # top 10 % without data
        return a
    if layer == "treecover2000":
        a = np.zeros((h, w), np.uint8)
        a[:, : w // 2] = 80
        return a
    a = np.zeros((h, w), np.uint8)
    a[h // 2: h // 2 + h // 10, : w // 2] = 18  # loss in 2018
    return a


@pytest.fixture
def client(monkeypatch, tmp_path):
    real = forest_service.analyze
    monkeypatch.setattr(forest_service, "analyze", lambda *a, **k: real(*a, **{**k, "reader": synthetic_reader}))
    app = main.create_app(Settings(job_timeout_seconds=60), web_dir=tmp_path / "noweb")
    with TestClient(app) as c:
        yield c


def test_health_is_light(client):
    r = client.get("/health")
    assert r.status_code == 200 and r.json()["status"] == "ok"
    cfg = client.get("/api/v1/config").json()
    assert cfg["app"] == "IMPACT" and "gemini_api_key" not in str(cfg).lower()


def test_forest_flow_real_math_on_test_layers(client):
    job = client.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY, "start_year": 2016, "end_year": 2020}).json()
    job = wait(client, job)
    assert job["status"] == "done", job
    r = job["result"]
    m = r["metrics"]
    # no data is excluded, not counted as forest or zero loss
    assert 85 < m["valid_data_pct"] < 95 and m["no_data_area_ha"] > 0
    assert 0 < m["loss_ha"] < m["forest_start_ha"]
    assert abs(m["loss_pct_of_forest_start"] - 100 * m["loss_ha"] / m["forest_start_ha"]) < 0.2
    years = {a["year"]: a["loss_ha"] for a in r["annual_loss"]}
    assert set(years) == {2016, 2017, 2018, 2019, 2020} and years[2018] > 0 and years[2017] == 0
    assert r["layers"]["loss"]["image_base64"] and r["legend"]["loss_classes"]
    assert r["summary"]["es"]["speech"] and r["summary"]["en"]["speech"] != r["summary"]["es"]["speech"]
    assert "2018" in r["summary"]["en"]["headline"] + " ".join(r["summary"]["en"]["points"])


def test_duplicate_requests_share_job(client):
    body = {"module": "bosques", "polygon": POLY, "start_year": 2016, "end_year": 2018}
    a = client.post("/api/v1/analyses", json=body).json()
    b = client.post("/api/v1/analyses", json=body).json()
    assert a["job_id"] == b["job_id"]


def test_errors_are_not_sticky_and_can_retry(client, monkeypatch):
    calls = {"n": 0}

    def flaky(*a, **k):
        calls["n"] += 1
        if calls["n"] == 1:
            raise AnalysisError("provider_error", "x", "y", retryable=True)
        return {"module": "bosques", "metrics": {"forest_start_ha": 0, "loss_ha": 0, "valid_data_pct": 100, "selected_area_ha": 1},
                "period": {"start_year": 2016, "end_year": 2017}, "parameters": {"canopy_threshold_pct": 30}, "annual_loss": []}
    monkeypatch.setattr(forest_service, "analyze", flaky)
    body = {"module": "bosques", "polygon": POLY, "start_year": 2016, "end_year": 2017}
    j1 = wait(client, client.post("/api/v1/analyses", json=body).json())
    assert j1["status"] == "error" and j1["error"]["retryable"]
    j2 = wait(client, client.post("/api/v1/analyses", json=body).json())
    assert j2["job_id"] != j1["job_id"] and j2["status"] == "done"


def test_timeout_releases_slot(monkeypatch, tmp_path):
    def slow(*a, stage=None, **k):
        time.sleep(1.5)
        stage("processing")
    monkeypatch.setattr(forest_service, "analyze", slow)
    app = main.create_app(Settings(job_timeout_seconds=1), web_dir=tmp_path)
    with TestClient(app) as c:
        j = wait(c, c.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY}).json())
        assert j["status"] == "error" and j["error"]["kind"] == "timeout"
        assert app.state.jobs.stats()["running"] == 0


def test_invalid_selection(client):
    r = client.post("/api/v1/analyses", json={"module": "bosques", "polygon": [[0, 0], [0, 1], [0, 0]]})
    assert r.status_code == 422
    big = [[10, 10], [10, 20], [0, 20], [0, 10]]
    r = client.post("/api/v1/analyses", json={"module": "bosques", "polygon": big})
    assert r.status_code == 422 and r.json()["detail"]["message"]["en"]


def test_nisar_without_credentials_is_explicit(client):
    r = client.post("/api/v1/analyses", json={"module": "hundimiento", "polygon": POLY})
    assert r.status_code == 503 and r.json()["detail"]["kind"] == "not_configured"


def test_unknown_job_and_result(client):
    assert client.get("/api/v1/analyses/nope").status_code == 404
    assert client.post("/api/v1/interpret", json={"result_id": "missing-123", "locale": "es"}).status_code == 404


def test_interpret_not_configured_keeps_results(client):
    job = wait(client, client.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY}).json())
    r = client.post("/api/v1/interpret", json={"result_id": job["result"]["result_id"], "locale": "en"})
    assert r.status_code == 503 and r.json()["detail"]["kind"] == "not_configured"


def test_interpret_verifies_numbers(monkeypatch, tmp_path):
    monkeypatch.setattr(forest_service, "analyze", lambda *a, **k: _fake_forest_result())
    captured = {}

    class FakeModels:
        def generate_content(self, model, contents, config):
            captured["contents"] = contents
            return types.SimpleNamespace(text='{"summary":"Se perdieron 999 ha (inventado) y 12 ha.","what_changed":"a",'
                                              '"how_much":"12 ha entre 2016 y 2020","pattern":"p","meaning":"m","cannot_conclude":["c"]}')

    class FakeClient:
        def __init__(self, **k):
            self.models = FakeModels()
    import google.genai
    monkeypatch.setattr(google.genai, "Client", FakeClient)
    app = main.create_app(Settings(gemini_api_key="test-key"), web_dir=tmp_path)
    with TestClient(app) as c:
        job = wait(c, c.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY}).json())
        out = c.post("/api/v1/interpret", json={"result_id": job["result"]["result_id"], "locale": "es"}).json()
    assert out["verification"]["unverified_numbers"] == ["999"]
    assert "image_base64" not in captured["contents"] and "test-key" not in captured["contents"]


def _fake_forest_result():
    return {"module": "bosques", "metrics": {"forest_start_ha": 100.0, "loss_ha": 12.0, "loss_pct_of_forest_start": 12.0,
                                             "valid_data_pct": 100.0, "selected_area_ha": 200.0, "peak_loss_year": 2018},
            "period": {"start_year": 2016, "end_year": 2020}, "parameters": {"canopy_threshold_pct": 30},
            "annual_loss": [{"year": 2018, "loss_ha": 12.0}], "layers": {"loss": {"image_base64": "AAAA"}},
            "measurement": {"es": "x", "en": "x"}, "limitations": {"es": ["l"], "en": ["l"]}}


def test_summary_zero_vs_missing():
    r = _fake_forest_result()
    r["metrics"].update(loss_ha=0.0, loss_pct_of_forest_start=0.0, peak_loss_year=None)
    s = summaries.build(r)
    assert "No se detectó" in s["es"]["headline"] and "No tree-cover loss" in s["en"]["headline"]
    r["metrics"]["forest_start_ha"] = 0
    assert "no hay base" in summaries.build(r)["es"]["headline"]


def test_spa_fallback(tmp_path):
    (tmp_path / "index.html").write_text("<html>IMPACT</html>")
    (tmp_path / "assets").mkdir()
    with TestClient(main.create_app(Settings(), web_dir=tmp_path)) as c:
        assert "IMPACT" in c.get("/hundimiento").text
        assert c.get("/api/v1/nope").status_code == 404
        assert c.get("/../../etc/passwd").status_code in (200, 404)
        assert "root:" not in c.get("/..%2F..%2Fetc%2Fpasswd").text


def test_gemini_number_check_unit():
    facts = {"metrics": {"loss_ha": 12485.6, "pct": 49.4}, "period": {"start_year": 2015}}
    assert gemini_service.unverified_numbers("Se perdieron 12 486 ha (49,4 %) desde 2015.", facts) == []
    assert gemini_service.unverified_numbers("Riesgo del 73 %.", facts) == ["73"]


def test_gemini_speech_returns_wav_in_requested_language(monkeypatch, tmp_path):
    import tts_service
    monkeypatch.setattr(forest_service, "analyze", lambda *a, **k: {
        **_fake_forest_result(), "summary": None})
    sent = {}

    class Part:
        inline_data = types.SimpleNamespace(data=b"\x00\x01" * 2400, mime_type="audio/L16;codec=pcm;rate=24000")

    class FakeModels:
        def list(self):
            return [types.SimpleNamespace(name="models/gemini-2.5-flash-preview-tts")]

        def generate_content(self, model, contents, config):
            sent["model"], sent["text"] = model, contents
            sent["voice"] = config.speech_config.voice_config.prebuilt_voice_config.voice_name
            return types.SimpleNamespace(candidates=[types.SimpleNamespace(content=types.SimpleNamespace(parts=[Part]))])

    class FakeClient:
        def __init__(self, **k):
            self.models = FakeModels()

    import google.genai
    monkeypatch.setattr(google.genai, "Client", FakeClient)
    monkeypatch.setitem(tts_service._model, "name", None)
    app = main.create_app(Settings(gemini_api_key="test-key"), web_dir=tmp_path)
    with TestClient(app) as c:
        job = wait(c, c.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY}).json())
        rid = job["result"]["result_id"]
        r = c.post("/api/v1/speech", json={"result_id": rid, "locale": "en"})
        assert r.status_code == 200 and r.headers["content-type"] == "audio/wav"
        assert r.content[:4] == b"RIFF" and r.content[8:12] == b"WAVE"
        assert sent["model"] == "gemini-2.5-flash-preview-tts"
        assert "Read in English" in sent["text"] and "hectares" in sent["text"]  # English text, spelled-out units
        r_es = c.post("/api/v1/speech", json={"result_id": rid, "locale": "es"})
        assert r_es.status_code == 200 and "hectáreas" in sent["text"]


def test_speech_without_key_is_explicit(client):
    job = wait(client, client.post("/api/v1/analyses", json={"module": "bosques", "polygon": POLY}).json())
    r = client.post("/api/v1/speech", json={"result_id": job["result"]["result_id"], "locale": "es"})
    assert r.status_code == 503 and r.json()["detail"]["kind"] == "not_configured"
