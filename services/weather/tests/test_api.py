"""1. API shape and auth."""

from app.services import ingestion
from tests.conftest import ADMIN, FakeProvider


def test_health(client, seeded):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_openapi_lists_v1_routes(client):
    paths = client.get("/openapi.json").json()["paths"]
    for p in ("/api/v1/weather/current", "/api/v1/weather/forecast/daily", "/api/v1/weather/history/daily",
              "/api/v1/weather/hourly", "/api/v1/weather/accuracy", "/api/v1/weather/sync", "/api/v1/locations",
              "/api/v1/locations/search", "/api/v1/locations/nearest"):
        assert p in paths


def test_providers_report_stub_status(client):
    by_name = {p["name"]: p for p in client.get("/api/v1/providers").json()}
    assert by_name["open_meteo_ecmwf"]["model"] == "ecmwf_ifs025"
    assert by_name["open_meteo_ecmwf"]["status"] == "available"
    for stub in ("nasa_gpm_imerg", "jma_himawari", "tmd"):
        assert by_name[stub]["status"] == "not_implemented"


def test_current_and_forecast_response_shape(client, seeded):
    ingestion.sync_current(seeded, FakeProvider(), None)
    ingestion.sync_forecast(seeded, FakeProvider(), None)

    cur = client.get("/api/v1/weather/current", params={"code": "nakhon-sawan"}).json()
    assert cur["location"]["code"] == "nakhon-sawan"
    assert cur["current"]["temperature_c"] == 26.1
    assert cur["current"]["visibility_m"] is None
    assert cur["current"]["unavailable_params"] == ["visibility", "uv_index"]

    fc = client.get("/api/v1/weather/forecast/daily", params={"code": "nakhon-sawan"}).json()
    assert len(fc["days"]) == 7
    assert fc["run"]["run_id"].startswith("fake_model@")
    assert {"forecast_date", "forecast_lead_days", "temperature_max_c", "precipitation_sum_mm", "provider",
            "model", "is_fallback"} <= fc["days"][0].keys()

    hr = client.get("/api/v1/weather/hourly", params={"code": "nakhon-sawan"}).json()
    assert hr["kind"] == "forecast" and len(hr["hours"]) > 0
    assert all(h["data_kind"] == "FORECAST" for h in hr["hours"])


def test_location_by_gps_on_weather_endpoint(client, seeded):
    ingestion.sync_current(seeded, FakeProvider(), None)
    r = client.get("/api/v1/weather/current", params={"lat": 15.70, "lon": 100.13})
    assert r.json()["location"]["code"] == "nakhon-sawan"


def test_missing_location_params(client):
    assert client.get("/api/v1/weather/current").status_code == 422
    assert client.get("/api/v1/weather/current", params={"location_id": 999}).status_code == 404


def test_sync_requires_api_key(client, seeded):
    assert client.post("/api/v1/weather/sync", json={"job": "current"}).status_code == 401
    bad = client.post("/api/v1/weather/sync", json={"job": "current"}, headers={"X-API-Key": "wrong"})
    assert bad.status_code == 401
    assert client.get("/api/v1/weather/ingestion-logs").status_code == 401


def test_sync_with_api_key_runs_job(client, seeded, monkeypatch):
    from app.services import jobs

    monkeypatch.setattr(jobs, "primary_and_secondary", lambda: (FakeProvider(), None))
    r = client.post("/api/v1/weather/sync", json={"job": "current"}, headers=ADMIN)
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "SUCCESS"
    assert len(body["results"]) == 7
    logs = client.get("/api/v1/weather/ingestion-logs", headers={"Authorization": "Bearer test-admin-key"})
    assert logs.status_code == 200 and len(logs.json()) == 7


def test_backfill_requires_dates(client, seeded):
    r = client.post("/api/v1/weather/sync", json={"job": "backfill"}, headers=ADMIN)
    assert r.status_code == 422
