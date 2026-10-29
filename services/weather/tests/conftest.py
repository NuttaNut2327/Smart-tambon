"""Tests run against a dedicated PostGIS database (weather_test), never the real one.
Providers are replaced by in-memory fakes; no network unless -m live."""

import os

TEST_DB = os.environ.get("TEST_DATABASE_URL")
if not TEST_DB:
    raise RuntimeError("TEST_DATABASE_URL must be set (see README: docker compose run --rm weather-api pytest)")
os.environ["DATABASE_URL"] = TEST_DB
os.environ["WEATHER_ADMIN_API_KEY"] = "test-admin-key"
os.environ["WEATHER_INITIAL_SYNC"] = "false"

from datetime import UTC, date, datetime, timedelta  # noqa: E402
from zoneinfo import ZoneInfo  # noqa: E402

import pytest  # noqa: E402
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.db import SessionLocal, engine  # noqa: E402
from app.providers.base import (  # noqa: E402
    CurrentData,
    ForecastData,
    ObservationData,
    ObservationProvider,
    ProviderError,
    WeatherProvider,
)
from app.seed import seed_locations  # noqa: E402

ADMIN = {"X-API-Key": "test-admin-key"}
TABLES = ("weather_daily_observation_revisions weather_daily_observation weather_daily_forecast weather_hourly "
          "weather_current weather_ingestion_logs weather_locations gistda_features gistda_fetches gistda_tiles").split()


@pytest.fixture(scope="session", autouse=True)
def migrated():
    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(os.path.dirname(__file__), "..", "alembic"))
    cfg.set_main_option("sqlalchemy.url", TEST_DB)
    command.upgrade(cfg, "head")
    yield


@pytest.fixture(autouse=True)
def clean_db():
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {', '.join(TABLES)} RESTART IDENTITY CASCADE"))
    yield


@pytest.fixture
def db():
    session = SessionLocal()
    yield session
    session.close()


@pytest.fixture
def seeded(db):
    seed_locations(db)
    return db


@pytest.fixture
def client():
    from app.main import app

    return TestClient(app)


def local_today() -> date:
    return datetime.now(ZoneInfo("Asia/Bangkok")).date()


DAILY_KEYS = [
    "weather_code", "temperature_max_c", "temperature_min_c", "apparent_temperature_max_c",
    "apparent_temperature_min_c", "precipitation_sum_mm", "rain_sum_mm", "precipitation_hours",
    "precipitation_probability_max_pct", "wind_speed_max_kmh", "wind_gusts_max_kmh", "wind_direction_dominant_deg",
    "relative_humidity_mean_pct", "cloud_cover_mean_pct", "shortwave_radiation_sum_mj_m2", "et0_mm",
    "uv_index_max", "sunrise", "sunset", "daylight_duration_s",
]


def make_forecast(provider="fake_primary", model="fake_model", run_init=None, issue=None, days=8, tmax=33.0,
                  unavailable=(), today=None):
    today = today or local_today()
    run_init = run_init or datetime.combine(today, datetime.min.time(), UTC)
    issue = issue or today
    daily = []
    for i in range(days):
        d = {k: None for k in DAILY_KEYS}
        d.update(weather_code=3, temperature_max_c=tmax + i * 0.1, temperature_min_c=25.0, precipitation_sum_mm=2.0,
                 precipitation_probability_max_pct=60.0)
        for p in unavailable:
            d[p] = None
        d["forecast_date"] = today + timedelta(days=i)
        d["forecast_lead_days"] = (d["forecast_date"] - issue).days
        daily.append(d)
    hourly = [
        {"valid_time": datetime.now(UTC).replace(minute=0, second=0, microsecond=0) + timedelta(hours=h), "temperature_c": 26.0 + h % 5,
         "weather_code": 3, "precipitation_probability_pct": 20.0}
        for h in range(24)
    ]
    return ForecastData(
        provider=provider, model=model, fetched_at=datetime.now(UTC), run_id=f"{model}@{run_init:%Y%m%dT%H%MZ}",
        run_init_time=run_init, run_id_source="model_metadata", issue_date=issue, daily=daily, hourly=hourly,
        unavailable_params=list(unavailable),
    )


class FakeProvider(WeatherProvider):
    def __init__(self, name="fake_primary", model="fake_model", fail=False, forecast=None):
        self.name, self.model, self.fail = name, model, fail
        self.forecast = forecast
        self.calls = 0

    def fetch_current(self, location):
        self.calls += 1
        if self.fail:
            raise ProviderError(f"{self.name} down", attempts=4)
        return CurrentData(provider=self.name, model=self.model, fetched_at=datetime.now(UTC),
                           observed_at=datetime(2026, 10, 16, 16, 30, tzinfo=UTC), interval_seconds=900,
                           values={"temperature_c": 26.1, "visibility_m": None, "uv_index": None},
                           unavailable_params=["visibility", "uv_index"])

    def fetch_forecast(self, location, days):
        self.calls += 1
        if self.fail:
            raise ProviderError(f"{self.name} down", attempts=4)
        return self.forecast or make_forecast(self.name, self.model)


class FakeObservations(ObservationProvider):
    name = "fake_archive"
    source_type = "REANALYSIS"

    def __init__(self, rows):
        self.rows = rows

    def fetch_observations(self, location, start, end):
        daily = [r for r in self.rows if start <= r["observation_date"] <= end]
        return ObservationData(provider=self.name, fetched_at=datetime.now(UTC), daily=[dict(r) for r in daily],
                               hourly=[])


def obs_row(day, tmax=32.0, tmin=25.0, rain=0.0, final=True, model="era5"):
    from app.services.ingestion import OBSERVATION_COLUMNS

    row = {c: None for c in OBSERVATION_COLUMNS}
    row.update(temperature_max_c=tmax, temperature_min_c=tmin, precipitation_sum_mm=rain, observation_date=day,
               model=model, is_final=final, data_quality="FINAL" if final else "PROVISIONAL",
               source_type="REANALYSIS", source_name="fake_archive")
    return row
