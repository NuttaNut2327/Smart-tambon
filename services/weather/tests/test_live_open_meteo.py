"""Opt-in live integration test against the real Open-Meteo API:

    WEATHER_LIVE_TESTS=1 pytest -m live
"""

import os
from datetime import timedelta

import pytest

from app.providers import observation_provider, registry
from tests.conftest import local_today

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(os.environ.get("WEATHER_LIVE_TESTS") != "1", reason="set WEATHER_LIVE_TESTS=1"),
]


class NakhonSawan:
    latitude, longitude, timezone = 15.7047, 100.1372, "Asia/Bangkok"


@pytest.mark.parametrize("name", ["open_meteo_ecmwf", "open_meteo_gfs"])
def test_live_forecast(name):
    data = registry()[name].fetch_forecast(NakhonSawan(), 8)
    assert len(data.daily) == 8
    assert data.daily[0]["forecast_date"] == local_today()
    assert all(d["temperature_max_c"] is not None for d in data.daily[:7])
    assert data.run_id_source == "model_metadata"
    assert len(data.hourly) == 8 * 24


def test_live_ecmwf_documented_gaps():
    data = registry()["open_meteo_ecmwf"].fetch_forecast(NakhonSawan(), 3)
    # ECMWF open data has no UV index; must be reported, not zero-filled
    assert "uv_index_max" in data.unavailable_params
    assert all(d["uv_index_max"] is None for d in data.daily)


def test_live_current():
    cur = registry()["open_meteo_ecmwf"].fetch_current(NakhonSawan())
    assert cur.values["temperature_c"] is not None


def test_live_archive():
    today = local_today()
    obs = observation_provider().fetch_observations(NakhonSawan(), today - timedelta(days=14), today - timedelta(days=1))
    assert obs.daily
    assert any(d["is_final"] for d in obs.daily)
