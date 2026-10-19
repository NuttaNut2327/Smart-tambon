"""Idempotent persistence of provider data.

Rules:
* forecasts are append-only per run (ON CONFLICT DO NOTHING on provider/model/run/location/date);
* current conditions are keyed by provider/model/valid time;
* observations are revisable until final, every change is kept in the revision table;
* backfill only touches observations — archived forecasts are never rewritten.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Iterable
from contextlib import contextmanager
from dataclasses import dataclass, field
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import delete, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.config import get_settings
from app.models import (
    WeatherCurrent,
    WeatherDailyForecast,
    WeatherDailyObservation,
    WeatherDailyObservationRevision,
    WeatherHourly,
    WeatherIngestionLog,
    WeatherLocation,
)
from app.providers.base import ObservationProvider, ProviderError, WeatherProvider
from app.providers.open_meteo import DAILY_ARCHIVE_PARAMS

log = logging.getLogger(__name__)

OBSERVATION_COLUMNS = list(DAILY_ARCHIVE_PARAMS.values())


@dataclass
class JobResult:
    job_type: str
    location_id: int | None
    status: str
    provider: str | None = None
    model: str | None = None
    run_id: str | None = None
    is_fallback: bool = False
    inserted: int = 0
    skipped: int = 0
    error: str | None = None
    details: dict = field(default_factory=dict)

    def as_dict(self) -> dict:
        return self.__dict__.copy()


@contextmanager
def ingestion_log(db: Session, job_type: str, location_id: int | None):
    started = datetime.now(UTC)
    result = JobResult(job_type=job_type, location_id=location_id, status="SUCCESS")
    try:
        yield result
    except ProviderError as exc:
        db.rollback()
        result.status = "FAILED"
        result.error = str(exc)
        result.details.setdefault("attempts", exc.attempts)
    except Exception as exc:  # keep one location's failure from stopping the batch
        db.rollback()
        log.exception("ingestion failed", extra={"job_type": job_type, "location_id": location_id})
        result.status = "FAILED"
        result.error = f"{type(exc).__name__}: {exc}"
    finished = datetime.now(UTC)
    db.add(
        WeatherIngestionLog(
            job_type=job_type,
            status=result.status,
            provider=result.provider,
            model=result.model,
            location_id=location_id,
            run_id=result.run_id,
            is_fallback=result.is_fallback,
            attempts=result.details.get("attempts", 0),
            records_inserted=result.inserted,
            records_skipped=result.skipped,
            started_at=started,
            finished_at=finished,
            duration_ms=int((finished - started).total_seconds() * 1000),
            error=result.error,
            details=result.details,
        )
    )
    db.commit()
    log.info(
        "ingestion finished",
        extra={k: v for k, v in result.as_dict().items() if k != "details"} | {"details": result.details},
    )


def _with_fallback(call: Callable[[WeatherProvider], object], primary: WeatherProvider,
                   secondary: WeatherProvider | None):
    """Returns (data, is_fallback, primary_error). Raises if both fail."""
    try:
        return call(primary), False, None
    except ProviderError as primary_exc:
        if secondary is None or secondary.name == primary.name:
            raise
        log.warning("primary provider failed, using secondary",
                    extra={"primary": primary.name, "secondary": secondary.name, "error": str(primary_exc)})
        try:
            return call(secondary), True, f"{primary.name}: {primary_exc}"
        except ProviderError as secondary_exc:
            raise ProviderError(
                f"primary {primary.name} failed ({primary_exc}); secondary {secondary.name} failed ({secondary_exc})",
                attempts=primary_exc.attempts + secondary_exc.attempts,
            ) from secondary_exc


def _active_locations(db: Session, location_ids: Iterable[int] | None = None) -> list[WeatherLocation]:
    stmt = select(WeatherLocation).where(WeatherLocation.is_active.is_(True)).order_by(WeatherLocation.id)
    if location_ids:
        stmt = select(WeatherLocation).where(WeatherLocation.id.in_(list(location_ids))).order_by(WeatherLocation.id)
    return list(db.scalars(stmt))


def _insert_ignore(db: Session, model, rows: list[dict], constraint: str) -> int:
    if not rows:
        return 0
    inserted = 0
    for i in range(0, len(rows), 500):
        stmt = insert(model).values(rows[i : i + 500]).on_conflict_do_nothing(constraint=constraint)
        inserted += len(db.execute(stmt.returning(model.id)).all())
    return inserted


# --------------------------------------------------------------------- current
def sync_current(db: Session, primary: WeatherProvider, secondary: WeatherProvider | None,
                 location_ids: Iterable[int] | None = None) -> list[JobResult]:
    results = []
    for loc in _active_locations(db, location_ids):
        with ingestion_log(db, "current", loc.id) as res:
            data, fallback, reason = _with_fallback(lambda p: p.fetch_current(loc), primary, secondary)
            row = dict(
                location_id=loc.id,
                provider=data.provider,
                model=data.model,
                fetched_at=data.fetched_at,
                observed_at=data.observed_at,
                interval_seconds=data.interval_seconds,
                is_fallback=fallback,
                fallback_reason=reason,
                unavailable_params=data.unavailable_params,
                **data.values,
            )
            n = _insert_ignore(db, WeatherCurrent, [row], "uq_weather_current_obs")
            if loc.elevation_m is None and data.elevation_m is not None:
                loc.elevation_m = data.elevation_m
            db.commit()
            res.provider, res.model, res.is_fallback = data.provider, data.model, fallback
            res.inserted, res.skipped = n, 1 - n
            res.details = {"attempts": data.attempts, "unavailable_params": data.unavailable_params,
                           "fallback_reason": reason}
        results.append(res)
    return results


# -------------------------------------------------------------------- forecast
def sync_forecast(db: Session, primary: WeatherProvider, secondary: WeatherProvider | None,
                  location_ids: Iterable[int] | None = None, days: int | None = None) -> list[JobResult]:
    days = days or get_settings().forecast_days
    results = []
    for loc in _active_locations(db, location_ids):
        with ingestion_log(db, "forecast", loc.id) as res:
            data, fallback, reason = _with_fallback(lambda p: p.fetch_forecast(loc, days), primary, secondary)
            common = dict(location_id=loc.id, provider=data.provider, model=data.model, fetched_at=data.fetched_at,
                          is_fallback=fallback)
            daily_rows = [
                dict(
                    **common,
                    fallback_reason=reason,
                    unavailable_params=[p for p in data.unavailable_params if not p.startswith("hourly.")],
                    run_id=data.run_id,
                    run_init_time=data.run_init_time,
                    run_id_source=data.run_id_source,
                    issue_date=data.issue_date,
                    **d,
                )
                for d in data.daily
            ]
            hourly_rows = [dict(**common, data_kind="FORECAST", run_id=data.run_id, source_type="MODEL_DERIVED", **h)
                           for h in data.hourly]
            n_daily = _insert_ignore(db, WeatherDailyForecast, daily_rows, "uq_weather_daily_forecast_run")
            n_hourly = _insert_ignore(db, WeatherHourly, hourly_rows, "uq_weather_hourly")
            db.commit()
            res.provider, res.model, res.run_id, res.is_fallback = data.provider, data.model, data.run_id, fallback
            res.inserted = n_daily + n_hourly
            res.skipped = len(daily_rows) + len(hourly_rows) - res.inserted
            res.details = {
                "attempts": data.attempts,
                "daily_inserted": n_daily,
                "hourly_inserted": n_hourly,
                "run_id_source": data.run_id_source,
                "unavailable_params": data.unavailable_params,
                "fallback_reason": reason,
            }
        results.append(res)
    return results


# ----------------------------------------------------------------- observation
def _metric_values(row) -> dict:
    get = row.get if isinstance(row, dict) else lambda c: getattr(row, c)
    return {c: get(c) for c in OBSERVATION_COLUMNS}


def store_observations(db: Session, loc: WeatherLocation, data) -> tuple[int, int, int]:
    """Returns (inserted, revised, unchanged)."""
    inserted = revised = unchanged = 0
    for row in data.daily:
        existing = db.scalar(
            select(WeatherDailyObservation).where(
                WeatherDailyObservation.location_id == loc.id,
                WeatherDailyObservation.observation_date == row["observation_date"],
                WeatherDailyObservation.source_type == row["source_type"],
                WeatherDailyObservation.source_name == row["source_name"],
            )
        )
        values = _metric_values(row)
        if existing is None:
            db.add(
                WeatherDailyObservation(
                    location_id=loc.id,
                    observation_date=row["observation_date"],
                    source_type=row["source_type"],
                    source_name=row["source_name"],
                    model=row["model"],
                    data_quality=row["data_quality"],
                    is_final=row["is_final"],
                    revision=1,
                    fetched_at=data.fetched_at,
                    finalized_at=data.fetched_at if row["is_final"] else None,
                    unavailable_params=data.unavailable_params,
                    **values,
                )
            )
            inserted += 1
            continue
        if existing.is_final:
            unchanged += 1  # final values are immutable
            continue
        old = _metric_values(existing)
        if old == values and existing.is_final == row["is_final"] and existing.model == row["model"]:
            unchanged += 1
            continue
        db.add(
            WeatherDailyObservationRevision(
                observation_id=existing.id,
                revision=existing.revision,
                data_quality=existing.data_quality,
                is_final=existing.is_final,
                model=existing.model,
                values={k: v for k, v in old.items()},
                fetched_at=existing.fetched_at,
            )
        )
        for k, v in values.items():
            setattr(existing, k, v)
        existing.model = row["model"]
        existing.data_quality = row["data_quality"]
        existing.is_final = row["is_final"]
        existing.revision += 1
        existing.fetched_at = data.fetched_at
        existing.unavailable_params = data.unavailable_params
        if row["is_final"]:
            existing.finalized_at = data.fetched_at
        revised += 1

    # Hourly observed: ERA5 supersedes provisional best_match rows for the same hour.
    hourly_rows = [
        dict(location_id=loc.id, data_kind="OBSERVED", provider=data.provider, run_id="observed",
             fetched_at=data.fetched_at, source_type="REANALYSIS", **h)
        for h in data.hourly
    ]
    era5_times = [h["valid_time"] for h in hourly_rows if h["model"] == "era5"]
    if era5_times:
        db.execute(
            delete(WeatherHourly).where(
                WeatherHourly.location_id == loc.id,
                WeatherHourly.data_kind == "OBSERVED",
                WeatherHourly.model == "best_match",
                WeatherHourly.valid_time.in_(era5_times),
            )
        )
    for i in range(0, len(hourly_rows), 500):
        stmt = insert(WeatherHourly).values(hourly_rows[i : i + 500])
        update_cols = {c: stmt.excluded[c] for c in hourly_rows[0] if c not in ("location_id", "data_kind",
                                                                               "provider", "model", "run_id",
                                                                               "valid_time")}
        db.execute(stmt.on_conflict_do_update(constraint="uq_weather_hourly", set_=update_cols))
    return inserted, revised, unchanged


def finalize_observations(db: Session, provider: ObservationProvider, location_ids: Iterable[int] | None = None,
                          today: date | None = None, lookback_days: int | None = None) -> list[JobResult]:
    """Nightly job: (re)fetch the last N local days; provisional days are revisited
    every night until ERA5 makes them final."""
    lookback = lookback_days or get_settings().observation_lookback_days
    results = []
    for loc in _active_locations(db, location_ids):
        local_today = today or datetime.now(ZoneInfo(loc.timezone)).date()
        non_final = db.scalars(
            select(WeatherDailyObservation.observation_date).where(
                WeatherDailyObservation.location_id == loc.id,
                WeatherDailyObservation.is_final.is_(False),
            )
        ).all()
        start = min([local_today - timedelta(days=lookback), *non_final])
        end = local_today - timedelta(days=1)
        with ingestion_log(db, "observation", loc.id) as res:
            data = provider.fetch_observations(loc, start, end)
            ins, rev, same = store_observations(db, loc, data)
            db.commit()
            res.provider, res.model = provider.name, "era5|best_match"
            res.inserted, res.skipped = ins + rev, same
            pending = sorted(d["observation_date"].isoformat() for d in data.daily if not d["is_final"])
            res.details = {"attempts": data.attempts, "start": start.isoformat(), "end": end.isoformat(),
                           "inserted": ins, "revised": rev, "unchanged": same, "provisional_dates": pending,
                           "unavailable_params": data.unavailable_params}
        results.append(res)
    return results


def backfill_history(db: Session, provider: ObservationProvider, start: date, end: date,
                     location_ids: Iterable[int] | None = None) -> list[JobResult]:
    """Manual historical backfill of observations. Deliberately never writes to
    weather_daily_forecast: past forecasts cannot be re-created after the fact."""
    if end < start:
        raise ValueError("end must be on or after start")
    results = []
    for loc in _active_locations(db, location_ids):
        local_yesterday = datetime.now(ZoneInfo(loc.timezone)).date() - timedelta(days=1)
        stop = min(end, local_yesterday)
        cursor = start
        while cursor <= stop:
            chunk_end = min(cursor + timedelta(days=89), stop)
            with ingestion_log(db, "backfill", loc.id) as res:
                data = provider.fetch_observations(loc, cursor, chunk_end)
                ins, rev, same = store_observations(db, loc, data)
                db.commit()
                res.provider, res.model = provider.name, "era5|best_match"
                res.inserted, res.skipped = ins + rev, same
                res.details = {"attempts": data.attempts, "start": cursor.isoformat(), "end": chunk_end.isoformat(),
                               "inserted": ins, "revised": rev, "unchanged": same}
            results.append(res)
            cursor = chunk_end + timedelta(days=1)
    return results
