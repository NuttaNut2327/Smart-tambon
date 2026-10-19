"""3. forecast storage, 4. historical preservation, 5. duplicates, 7. missing params, 8. fallback."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.models import (
    WeatherCurrent,
    WeatherDailyForecast,
    WeatherDailyObservation,
    WeatherDailyObservationRevision,
    WeatherHourly,
    WeatherIngestionLog,
)
from app.services import ingestion
from tests.conftest import FakeObservations, FakeProvider, local_today, make_forecast, obs_row


def count(db, model, *where):
    return db.scalar(select(func.count()).select_from(model).where(*where))


# 3 ---------------------------------------------------------------------------
def test_forecast_storage(seeded):
    res = ingestion.sync_forecast(seeded, FakeProvider(), None, location_ids=[1])
    assert res[0].status == "SUCCESS"
    rows = seeded.scalars(select(WeatherDailyForecast).order_by(WeatherDailyForecast.forecast_date)).all()
    assert len(rows) == 8
    assert [r.forecast_lead_days for r in rows] == list(range(8))
    assert rows[0].run_id_source == "model_metadata"
    assert rows[0].provider == "fake_primary" and rows[0].model == "fake_model"
    assert count(seeded, WeatherHourly, WeatherHourly.data_kind == "FORECAST") == 24


# 4 ---------------------------------------------------------------------------
def test_new_run_does_not_overwrite_archived_run(seeded):
    today = local_today()
    run1 = make_forecast(run_init=datetime.combine(today, datetime.min.time(), UTC), tmax=30.0)
    run2 = make_forecast(run_init=datetime.combine(today, datetime.min.time(), UTC) + timedelta(hours=6), tmax=35.0)
    ingestion.sync_forecast(seeded, FakeProvider(forecast=run1), None, location_ids=[1])
    ingestion.sync_forecast(seeded, FakeProvider(forecast=run2), None, location_ids=[1])

    assert count(seeded, WeatherDailyForecast) == 16
    old = seeded.scalars(select(WeatherDailyForecast).where(WeatherDailyForecast.run_id == run1.run_id)).all()
    assert all(r.temperature_max_c < 31 for r in old)  # untouched


def test_backfill_never_touches_forecasts(seeded):
    ingestion.sync_forecast(seeded, FakeProvider(), None, location_ids=[1])
    before = [(r.id, r.temperature_max_c, r.fetched_at) for r in seeded.scalars(select(WeatherDailyForecast))]
    today = local_today()
    obs = FakeObservations([obs_row(today - timedelta(days=d)) for d in range(1, 40)])
    res = ingestion.backfill_history(seeded, obs, today - timedelta(days=39), today, location_ids=[1])
    assert all(r.status == "SUCCESS" for r in res)
    assert count(seeded, WeatherDailyObservation) == 39
    after = [(r.id, r.temperature_max_c, r.fetched_at) for r in seeded.scalars(select(WeatherDailyForecast))]
    assert before == after


# 5 ---------------------------------------------------------------------------
def test_duplicate_runs_and_current_are_idempotent(seeded):
    fc = make_forecast()
    first = ingestion.sync_forecast(seeded, FakeProvider(forecast=fc), None, location_ids=[1])[0]
    second = ingestion.sync_forecast(seeded, FakeProvider(forecast=fc), None, location_ids=[1])[0]
    assert first.inserted == 32 and second.inserted == 0 and second.skipped == 32
    assert count(seeded, WeatherDailyForecast) == 8

    ingestion.sync_current(seeded, FakeProvider(), None, location_ids=[1])
    ingestion.sync_current(seeded, FakeProvider(), None, location_ids=[1])
    assert count(seeded, WeatherCurrent) == 1


def test_observation_revision_history_and_finalisation(seeded):
    day = local_today() - timedelta(days=2)
    ingestion.finalize_observations(seeded, FakeObservations([obs_row(day, rain=4.0, final=False,
                                                                      model="best_match")]), [1], lookback_days=3)
    ingestion.finalize_observations(seeded, FakeObservations([obs_row(day, rain=4.0, final=False,
                                                                      model="best_match")]), [1], lookback_days=3)
    o = seeded.scalar(select(WeatherDailyObservation))
    assert o.revision == 1 and not o.is_final and o.data_quality == "PROVISIONAL"

    ingestion.finalize_observations(seeded, FakeObservations([obs_row(day, rain=6.5, final=True)]), [1],
                                    lookback_days=3)
    seeded.expire_all()
    o = seeded.scalar(select(WeatherDailyObservation))
    assert o.is_final and o.revision == 2 and o.precipitation_sum_mm == 6.5 and o.model == "era5"
    rev = seeded.scalar(select(WeatherDailyObservationRevision))
    assert rev.values["precipitation_sum_mm"] == 4.0 and rev.model == "best_match"

    # final values are immutable
    ingestion.finalize_observations(seeded, FakeObservations([obs_row(day, rain=99.0, final=True)]), [1],
                                    lookback_days=3)
    seeded.expire_all()
    assert seeded.scalar(select(WeatherDailyObservation)).precipitation_sum_mm == 6.5


# 7 ---------------------------------------------------------------------------
def test_missing_params_are_null_not_zero(seeded):
    fc = make_forecast(unavailable=("uv_index_max", "wind_gusts_max_kmh"))
    ingestion.sync_forecast(seeded, FakeProvider(forecast=fc), None, location_ids=[1])
    rows = seeded.scalars(select(WeatherDailyForecast)).all()
    assert all(r.uv_index_max is None and r.wind_gusts_max_kmh is None for r in rows)
    assert rows[0].unavailable_params == ["uv_index_max", "wind_gusts_max_kmh"]
    log = seeded.scalar(select(WeatherIngestionLog))
    assert log.details["unavailable_params"] == ["uv_index_max", "wind_gusts_max_kmh"]


# 8 ---------------------------------------------------------------------------
def test_fallback_to_secondary_preserves_provenance(seeded):
    primary = FakeProvider("fake_primary", "model_a", fail=True)
    secondary = FakeProvider("fake_secondary", "model_b")
    res = ingestion.sync_forecast(seeded, primary, secondary, location_ids=[1])[0]
    assert res.status == "SUCCESS" and res.is_fallback
    row = seeded.scalar(select(WeatherDailyForecast).limit(1))
    assert row.provider == "fake_secondary" and row.model == "model_b"
    assert row.is_fallback and "fake_primary" in row.fallback_reason
    log = seeded.scalar(select(WeatherIngestionLog))
    assert log.is_fallback and log.provider == "fake_secondary"


def test_both_providers_fail_logs_failure(seeded):
    res = ingestion.sync_current(seeded, FakeProvider(fail=True), FakeProvider("b", "m", fail=True), [1])[0]
    assert res.status == "FAILED"
    assert "primary" in res.error and "secondary" in res.error
    assert count(seeded, WeatherCurrent) == 0
    assert seeded.scalar(select(WeatherIngestionLog.status)) == "FAILED"


def test_one_location_failure_does_not_stop_batch(seeded):
    class Flaky(FakeProvider):
        def fetch_current(self, location):
            if location.code == "bangkok":
                from app.providers.base import ProviderError
                raise ProviderError("boom")
            return super().fetch_current(location)

    res = ingestion.sync_current(seeded, Flaky(), None)
    assert [r.status for r in res].count("FAILED") == 1
    assert count(seeded, WeatherCurrent) == 6
