import asyncio
from unittest.mock import AsyncMock
import pytest
from pydantic import ValidationError
from fastapi import HTTPException
import main
from config import Settings
from metrics_schemas import MetricsRequest, InterpretRequest
from schemas import AnalysisReport
from analysis_service import DataUnavailable

def req(**changes):
    data=dict(module="bosques",polygon=[(14.60,-90.5),(14.60,-90.4),(14.7,-90.4)],date_a="2025-01-01",date_b="2025-02-01")
    return MetricsRequest(**(data|changes))
def complete(coro):
    try: coro.send(None)
    except StopIteration as e: return e.value
    raise AssertionError("Unexpected asynchronous suspension")
@pytest.fixture
def routes(monkeypatch):
    app=main.create_app(Settings())
    async def inline(fn,*a): return fn(*a)
    monkeypatch.setattr(asyncio,"to_thread",inline)
    return app,{r.path:r.endpoint for r in app.routes}
@pytest.mark.parametrize("change",[
    {"date_a":"2025-03-01"},{"date_b":"2099-01-01"},{"polygon":[(0,0)]*3},
    {"polygon":[(float("nan"),0),(1,1),(2,2)]},{"min_coherence":2},
    {"incidence_deg":90},{"module":"unknown"}])
def test_reject_invalid(change):
    with pytest.raises(ValidationError): req(**change)
def test_no_fabricated_metrics(routes):
    app,r=routes
    assert r["/api/v1/dashboard-stats"]()["criticalAreaKm2"] is None
    assert r["/api/v1/classified-zones"]()["features"]==[]
    with pytest.raises(HTTPException) as e:r["/api/v1/displacement"](0,0)
    assert e.value.status_code==409
def test_metrics_survive_ai_failure(routes,monkeypatch):
    app,r=routes
    monkeypatch.setattr(main,"calculate",lambda p:{"module":p.module,"chart":[{"label":"fixture","value":3}],"limitations":["fixture"]})
    result=complete(r["/api/v1/metrics"](req()))
    with pytest.raises(HTTPException) as e:
        complete(r["/api/v1/ai/interpret"](InterpretRequest(result_id=result["result_id"])))
    assert e.value.status_code==503
    assert app.state.results[result["result_id"]][1]["chart"][0]["value"]==3
def test_provider_failure_is_not_zero(routes,monkeypatch):
    app,r=routes
    def fail(p):raise DataUnavailable("OSM unavailable")
    monkeypatch.setattr(main,"calculate",fail)
    with pytest.raises(HTTPException) as e:complete(r["/api/v1/metrics"](req()))
    assert e.value.status_code==422
    assert not app.state.busy and not app.state.results
def test_server_owns_context(routes,monkeypatch):
    app,r=routes
    monkeypatch.setattr(main,"calculate",lambda p:{"measurement":"fixture","points":[{"value":4}],"source":"test"})
    result=complete(r["/api/v1/metrics"](req()))
    app.state.gemini.analyze=AsyncMock(return_value=AnalysisReport(summary="test",observations=["test"],limitations=["test"],suggested_next_steps=["test"]))
    complete(r["/api/v1/ai/interpret"](InterpretRequest(result_id=result["result_id"])))
    context=app.state.gemini.analyze.call_args.args[0]
    assert context["source"]=="test" and "points" not in context
def test_expired_result(routes):
    app,r=routes
    with pytest.raises(HTTPException) as e:complete(r["/api/v1/ai/interpret"](InterpretRequest(result_id="missing")))
    assert e.value.status_code==404
def test_busy_guard(routes):
    app,r=routes;app.state.busy=True
    with pytest.raises(HTTPException) as e:complete(r["/api/v1/metrics"](req()))
    assert e.value.status_code==429

def test_gunw_crop_and_units(tmp_path,monkeypatch):
    np=pytest.importorskip("numpy");h5py=pytest.importorskip("h5py")
    pytest.importorskip("shapely");pytest.importorskip("pyproj")
    import analysis_service as service
    path=tmp_path/"fixture.h5"
    with h5py.File(path,"w") as f:
        ident=f.create_group("/science/LSAR/identification")
        ident["referenceZeroDopplerStartTime"]=b"2025-02-01T00:00:00"
        ident["secondaryZeroDopplerStartTime"]=b"2025-01-01T00:00:00"
        grid=f.create_group("/science/LSAR/GUNW/grids/frequencyA")
        grid["xCoordinates"]=np.array([-90.52,-90.48,-90.44,-90.40])
        grid["yCoordinates"]=np.array([14.58,14.62,14.66,14.70])
        grid["projection"]=4326;grid["centerFrequency"]=1.25e9
        pol=grid.create_group("unwrappedInterferogram/HH")
        pol["unwrappedPhase"]=np.ones((4,4))
        pol["coherenceMagnitude"]=np.ones((4,4))*.9
        pol["connectedComponents"]=np.ones((4,4),dtype="uint8")
    monkeypatch.setattr(service,"matching_file",lambda r:path)
    result=service.radar_metrics(req(module="desplazamiento"))
    assert result["valid_pixels"]>0
    assert result["mean"]==pytest.approx(-299792458/1.25e9/(4*np.pi)*1000,abs=.001)
    assert len(result["points"])<=900
    with pytest.raises(DataUnavailable):service.radar_metrics(req(module="hundimiento"))

def test_auto_dates_and_selection():
    from metrics_schemas import MetricsRequest
    r=MetricsRequest(module="desplazamiento",polygon=[(14.6,-90.5),(14.6,-90.4),(14.7,-90.4)])
    assert r.date_a is None and r.date_b is None
    with pytest.raises(ValidationError):
        MetricsRequest(module="bosques",polygon=r.polygon,date_a="2025-01-01")

def test_incidence_cube_and_projection(tmp_path):
    np=pytest.importorskip("numpy");h5py=pytest.importorskip("h5py")
    pytest.importorskip("pyproj");pytest.importorskip("shapely")
    import math, analysis_service as service
    path=tmp_path/"angle.h5"
    with h5py.File(path,"w") as f:
        g=f.create_group("/science/LSAR/GUNW/metadata/radarGrid")
        g["xCoordinates"]=np.array([-90.6,-90.4]);g["yCoordinates"]=np.array([14.6,14.8]);g["projection"]=4326
        d=g.create_dataset("incidenceAngle",data=np.full((2,2,2),35.0));d.attrs["units"]="degrees"
    with h5py.File(path,"r") as f:
        angle,lo,hi=service.incidence_for_valid_pixels(f,4326,np.array([[-90.5]]),np.array([[14.7]]),np.array([[True]]))
        assert (angle,lo,hi)==(35,35,35)
        assert 10/math.cos(math.radians(angle))==pytest.approx(12.2077458876)
    with h5py.File(path,"a") as f:f["/science/LSAR/GUNW/metadata/radarGrid/incidenceAngle"][1,0,0]=40
    with h5py.File(path,"r") as f:
        with pytest.raises(DataUnavailable):service.incidence_for_valid_pixels(f,4326,np.array([[-90.5]]),np.array([[14.7]]),np.array([[True]]))

def test_forest_comparison_unions_overlapping_polygons(monkeypatch):
    pytest.importorskip("osmnx");pytest.importorskip("pyproj")
    import analysis_service as service, httpx
    # Two identical ways represent the same forest. Area must not be counted twice.
    nodes=[{"type":"node","id":1,"lat":14.600,"lon":-90.500},{"type":"node","id":2,"lat":14.600,"lon":-90.490},
           {"type":"node","id":3,"lat":14.610,"lon":-90.490},{"type":"node","id":4,"lat":14.610,"lon":-90.500}]
    ways=[{"type":"way","id":10,"nodes":[1,2,3,4,1],"tags":{"natural":"wood"}},
          {"type":"way","id":11,"nodes":[1,2,3,4,1],"tags":{"natural":"wood"}}]
    class Response:
        def raise_for_status(self):pass
        def json(self):
            from copy import deepcopy
            return {"elements":deepcopy(nodes+ways)}
    monkeypatch.setattr(httpx,"post",lambda *a,**k:Response())
    result=service.forest_metrics(req(polygon=[(14.59,-90.51),(14.59,-90.48),(14.62,-90.48),(14.62,-90.51)]))
    assert result["snapshots"][0]["area_ha"]==pytest.approx(119.3,rel=0.04)
    assert result["delta"]==0
    assert result["chart"][0]["value"]==result["snapshots"][0]["area_ha"]

def test_full_hundimiento_automatic(tmp_path,monkeypatch):
    np=pytest.importorskip("numpy");h5py=pytest.importorskip("h5py")
    pytest.importorskip("pyproj");pytest.importorskip("shapely")
    import math,analysis_service as service
    path=tmp_path/"product.h5"
    with h5py.File(path,"w") as f:
        ident=f.create_group("/science/LSAR/identification")
        ident["referenceZeroDopplerStartTime"]=b"2025-01-01T00:00:00"
        ident["secondaryZeroDopplerStartTime"]=b"2025-02-01T00:00:00"
        grid=f.create_group("/science/LSAR/GUNW/grids/frequencyA")
        grid["xCoordinates"]=np.array([-90.52,-90.48,-90.44,-90.40])
        grid["yCoordinates"]=np.array([14.58,14.62,14.66,14.70])
        grid["projection"]=4326;grid["centerFrequency"]=1.25e9
        pol=grid.create_group("unwrappedInterferogram/HH")
        pol["unwrappedPhase"]=np.ones((4,4));pol["coherenceMagnitude"]=np.ones((4,4))*.9
        pol["connectedComponents"]=np.ones((4,4),dtype="uint8")
        g=f.create_group("/science/LSAR/GUNW/metadata/radarGrid")
        g["xCoordinates"]=np.array([-90.53,-90.39]);g["yCoordinates"]=np.array([14.57,14.71]);g["projection"]=4326
        d=g.create_dataset("incidenceAngle",data=np.full((2,2,2),35.0));d.attrs["units"]="degrees"
    monkeypatch.setattr(service,"matching_file",lambda r:path)
    los=service.radar_metrics(req(module="desplazamiento"))
    vertical=service.radar_metrics(req(module="hundimiento"))
    assert vertical["incidence_deg"]==35
    assert vertical["mean"]==pytest.approx(los["mean"]/math.cos(math.radians(35)),abs=.002)
    assert vertical["date_a"]=="2025-01-01" and vertical["date_b"]=="2025-02-01"
    assert 0<vertical["valid_coverage_pct"]<=100

