"""6. timezone handling, 7. missing params parsing, 8. retry/backoff (HTTP layer mocked with respx)."""

from datetime import UTC, date, datetime

import httpx
import pytest
import respx

from app.providers.base import ProviderError
from app.providers.http import RetryingClient
from app.providers.open_meteo import (
    FORECAST_URL,
    META_URL,
    OpenMeteoArchiveProvider,
    OpenMeteoForecastProvider,
    ARCHIVE_URL,
)


class Loc:
    latitude, longitude, timezone = 15.7047, 100.1372, "Asia/Bangkok"


OFFSET = 7 * 3600
# 2026-10-16 00:00 Asia/Bangkok == 2026-10-15T17:00Z
MIDNIGHT_BKK = int(datetime(2026, 10, 15, 17, tzinfo=UTC).timestamp())


def provider(sleeps=None):
    client = RetryingClient(max_attempts=3, backoff_base=0.5, sleep=(sleeps.append if sleeps is not None else
                                                                      lambda s: None))
    return OpenMeteoForecastProvider(name="open_meteo_ecmwf", model="ecmwf_ifs025", meta_id="ecmwf_ifs025",
                                     description="", client=client)


def forecast_body(uv_unit="", uv=(None, None)):
    return {
        "utc_offset_seconds": OFFSET,
        "daily_units": {"uv_index_max": uv_unit or "undefined", "temperature_2m_max": "°C"},
        "daily": {
            "time": [MIDNIGHT_BKK, MIDNIGHT_BKK + 86400],
            "temperature_2m_max": [33.6, 32.5],
            "temperature_2m_min": [25.3, 25.0],
            "precipitation_sum": [0.0, 1.9],
            "uv_index_max": list(uv),
            "wind_gusts_10m_max": [None, 20.0],
            "sunrise": [MIDNIGHT_BKK + 6 * 3600 + 660, MIDNIGHT_BKK + 86400 + 6 * 3600 + 671],
        },
        "hourly_units": {},
        "hourly": {"time": [MIDNIGHT_BKK, MIDNIGHT_BKK + 3600], "temperature_2m": [26.2, 26.0]},
    }


@respx.mock
def test_unixtime_parsed_to_utc_and_local_dates():
    respx.get(META_URL.format(meta_id="ecmwf_ifs025")).respond(
        json={"last_run_initialisation_time": int(datetime(2026, 10, 15, 18, tzinfo=UTC).timestamp())})
    respx.get(FORECAST_URL).respond(json=forecast_body())
    data = provider().fetch_forecast(Loc(), 2)

    # 17:00Z belongs to the next local (Bangkok) day
    assert [d["forecast_date"] for d in data.daily] == [date(2026, 10, 16), date(2026, 10, 17)]
    assert data.hourly[0]["valid_time"] == datetime(2026, 10, 15, 17, tzinfo=UTC)
    assert data.daily[0]["sunrise"] == datetime(2026, 10, 15, 23, 11, tzinfo=UTC)  # 06:11 local
    # run initialised 18Z on the 15th == 01:00 on the 16th in Bangkok -> issue date 16th
    assert data.issue_date == date(2026, 10, 16)
    assert [d["forecast_lead_days"] for d in data.daily] == [0, 1]
    assert data.run_id == "ecmwf_ifs025@20261015T1800Z"


@respx.mock
def test_run_id_falls_back_to_fetch_bucket_when_metadata_missing():
    respx.get(META_URL.format(meta_id="ecmwf_ifs025")).respond(404, json={"error": True, "reason": "Not Found"})
    respx.get(FORECAST_URL).respond(json=forecast_body())
    data = provider().fetch_forecast(Loc(), 2)
    assert data.run_id_source == "fetch_time_bucket" and "@fetch-" in data.run_id


@respx.mock
def test_unavailable_params_detected_and_null():
    respx.get(META_URL.format(meta_id="ecmwf_ifs025")).respond(json={})
    respx.get(FORECAST_URL).respond(json=forecast_body())
    data = provider().fetch_forecast(Loc(), 2)
    assert "uv_index_max" in data.unavailable_params
    assert all(d["uv_index_max"] is None for d in data.daily)
    # partially-missing values stay NULL (not 0) without flagging the whole parameter
    assert data.daily[0]["wind_gusts_max_kmh"] is None and data.daily[1]["wind_gusts_max_kmh"] == 20.0
    assert "wind_gusts_10m_max" not in data.unavailable_params
    # a genuine 0.0 stays 0.0
    assert data.daily[0]["precipitation_sum_mm"] == 0.0


@respx.mock
def test_model_is_always_explicit():
    respx.get(META_URL.format(meta_id="ecmwf_ifs025")).respond(json={})
    route = respx.get(FORECAST_URL).respond(json=forecast_body())
    provider().fetch_forecast(Loc(), 2)
    assert route.calls.last.request.url.params["models"] == "ecmwf_ifs025"


@respx.mock
def test_retry_with_exponential_backoff_then_success():
    route = respx.get(FORECAST_URL).mock(side_effect=[httpx.Response(503), httpx.ConnectError("x"),
                                                      httpx.Response(200, json={"current": {"time": MIDNIGHT_BKK,
                                                                                            "temperature_2m": 26}})])
    sleeps = []
    data = provider(sleeps).fetch_current(Loc())
    assert route.call_count == 3 and data.attempts == 3
    assert len(sleeps) == 2 and 0.5 <= sleeps[0] < 0.75 and 1.0 <= sleeps[1] < 1.25
    assert data.values["temperature_c"] == 26.0 and data.values["uv_index"] is None


@respx.mock
def test_permanent_error_is_not_retried():
    route = respx.get(FORECAST_URL).respond(400, json={"error": True, "reason": "Invalid model"})
    with pytest.raises(ProviderError, match="Invalid model"):
        provider().fetch_current(Loc())
    assert route.call_count == 1


@respx.mock
def test_gives_up_after_max_attempts():
    respx.get(FORECAST_URL).respond(502)
    with pytest.raises(ProviderError) as exc:
        provider().fetch_current(Loc())
    assert exc.value.attempts == 3


@respx.mock
def test_archive_marks_era5_final_and_best_match_provisional():
    d1, d2, d3 = MIDNIGHT_BKK, MIDNIGHT_BKK + 86400, MIDNIGHT_BKK + 2 * 86400

    def body(tmax, rain):
        return {"utc_offset_seconds": OFFSET, "daily_units": {}, "daily": {
            "time": [d1, d2, d3], "temperature_2m_max": tmax, "precipitation_sum": rain}, "hourly": {}}

    def respond(request):
        if request.url.params["models"] == "era5":
            return httpx.Response(200, json=body([31.0, None, None], [2.0, None, None]))
        return httpx.Response(200, json=body([31.5, 32.0, None], [2.1, 0.0, None]))

    respx.get(ARCHIVE_URL).mock(side_effect=respond)
    data = OpenMeteoArchiveProvider(RetryingClient(sleep=lambda s: None)).fetch_observations(
        Loc(), date(2026, 10, 16), date(2026, 10, 18))
    by_day = {d["observation_date"]: d for d in data.daily}
    assert by_day[date(2026, 10, 16)]["is_final"] and by_day[date(2026, 10, 16)]["model"] == "era5"
    assert by_day[date(2026, 10, 16)]["temperature_max_c"] == 31.0
    assert not by_day[date(2026, 10, 17)]["is_final"] and by_day[date(2026, 10, 17)]["data_quality"] == "PROVISIONAL"
    assert date(2026, 10, 18) not in by_day  # nothing published -> nothing stored
