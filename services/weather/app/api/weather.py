from datetime import UTC, date, datetime, time, timedelta
from typing import Literal
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import require_admin, resolve_location
from app.db import get_db
from app.models import (
    SOURCE_TYPES,
    WeatherCurrent,
    WeatherDailyForecast,
    WeatherDailyObservation,
    WeatherHourly,
    WeatherIngestionLog,
    WeatherLocation,
)
from app.providers import registry
from app.schemas import (
    AccuracyQuery,
    CurrentResponse,
    DailyForecastResponse,
    HistoryResponse,
    HourlyResponse,
    LocationOut,
    SyncRequest,
)
from app.services import accuracy
from app.services.jobs import run_job

router = APIRouter(tags=["weather"])


def _local_today(loc: WeatherLocation) -> date:
    return datetime.now(ZoneInfo(loc.timezone)).date()


def _as_utc(value: datetime, tz: str) -> datetime:
    return value.replace(tzinfo=ZoneInfo(tz)).astimezone(UTC) if value.tzinfo is None else value.astimezone(UTC)


@router.get("/providers", tags=["meta"], summary="Registered providers and their implementation status")
def providers():
    return [p.info() for p in registry().values()]


@router.get("/weather/current", response_model=CurrentResponse)
def current(loc: WeatherLocation = Depends(resolve_location), provider: str | None = None,
            db: Session = Depends(get_db)):
    stmt = select(WeatherCurrent).where(WeatherCurrent.location_id == loc.id)
    if provider:
        stmt = stmt.where(WeatherCurrent.provider == provider)
    row = db.scalar(stmt.order_by(WeatherCurrent.observed_at.desc(), WeatherCurrent.is_fallback.asc()).limit(1))
    return {"location": loc, "current": row}


def _latest_run(db: Session, loc_id: int, provider: str | None, model: str | None, table=WeatherDailyForecast):
    stmt = select(table.run_id, table.provider, table.model).where(table.location_id == loc_id)
    if table is WeatherHourly:
        stmt = stmt.where(WeatherHourly.data_kind == "FORECAST")
    if provider:
        stmt = stmt.where(table.provider == provider)
    if model:
        stmt = stmt.where(table.model == model)
    return db.execute(stmt.order_by(table.fetched_at.desc(), table.id.desc()).limit(1)).first()


@router.get("/weather/forecast/daily", response_model=DailyForecastResponse,
            summary="Daily forecast from the latest (or a given archived) run")
def forecast_daily(
    loc: WeatherLocation = Depends(resolve_location),
    days: int = Query(default=7, ge=1, le=16),
    provider: str | None = None,
    model: str | None = None,
    run_id: str | None = Query(default=None, description="Archived run id; defaults to the latest run"),
    start_date: date | None = Query(default=None, description="Defaults to today in the location's timezone"),
    db: Session = Depends(get_db),
):
    if run_id is None:
        latest = _latest_run(db, loc.id, provider, model)
        if latest is None:
            return {"location": loc, "run": None, "days": []}
        run_id, provider, model = latest.run_id, latest.provider, latest.model
    stmt = (
        select(WeatherDailyForecast)
        .where(WeatherDailyForecast.location_id == loc.id, WeatherDailyForecast.run_id == run_id,
               WeatherDailyForecast.forecast_date >= (start_date or _local_today(loc)))
        .order_by(WeatherDailyForecast.forecast_date)
        .limit(days)
    )
    if provider:
        stmt = stmt.where(WeatherDailyForecast.provider == provider)
    rows = db.scalars(stmt).all()
    run = None
    if rows:
        r = rows[0]
        run = {"run_id": r.run_id, "provider": r.provider, "model": r.model, "run_init_time": r.run_init_time,
               "run_id_source": r.run_id_source, "issue_date": r.issue_date, "is_fallback": r.is_fallback,
               "fallback_reason": r.fallback_reason, "unavailable_params": r.unavailable_params,
               "timezone": loc.timezone}
    return {"location": loc, "run": run, "days": rows}


@router.get("/weather/forecast/runs", summary="Archived forecast runs for a location")
def forecast_runs(loc: WeatherLocation = Depends(resolve_location), limit: int = Query(default=50, ge=1, le=500),
                  db: Session = Depends(get_db)):
    f = WeatherDailyForecast
    rows = db.execute(
        select(f.run_id, f.provider, f.model, f.run_init_time, f.issue_date, f.is_fallback,
               func.min(f.fetched_at).label("first_fetched_at"), func.count().label("days"))
        .where(f.location_id == loc.id)
        .group_by(f.run_id, f.provider, f.model, f.run_init_time, f.issue_date, f.is_fallback)
        .order_by(func.min(f.fetched_at).desc())
        .limit(limit)
    ).mappings().all()
    return {"location": LocationOut.model_validate(loc), "runs": [dict(r) for r in rows]}


@router.get("/weather/history/daily", response_model=HistoryResponse,
            summary="Daily observations (reanalysis now; ground stations/satellite when providers exist)")
def history_daily(
    loc: WeatherLocation = Depends(resolve_location),
    start: date | None = Query(default=None, description="Default: 30 days ago (local)"),
    end: date | None = Query(default=None, description="Default: yesterday (local)"),
    source_type: Literal[SOURCE_TYPES] | None = None,  # type: ignore[valid-type]
    final_only: bool = False,
    db: Session = Depends(get_db),
):
    today = _local_today(loc)
    end = end or today - timedelta(days=1)
    start = start or end - timedelta(days=29)
    if end < start:
        raise HTTPException(422, "end must be on or after start")
    stmt = (
        select(WeatherDailyObservation)
        .where(WeatherDailyObservation.location_id == loc.id,
               WeatherDailyObservation.observation_date.between(start, end))
        .order_by(WeatherDailyObservation.observation_date, WeatherDailyObservation.source_type)
    )
    if source_type:
        stmt = stmt.where(WeatherDailyObservation.source_type == source_type)
    if final_only:
        stmt = stmt.where(WeatherDailyObservation.is_final.is_(True))
    return {"location": loc, "days": db.scalars(stmt).all()}


@router.get("/weather/hourly", response_model=HourlyResponse)
def hourly(
    loc: WeatherLocation = Depends(resolve_location),
    kind: Literal["forecast", "observed"] = "forecast",
    start: datetime | None = Query(default=None, description="ISO datetime; naive = location local time"),
    end: datetime | None = Query(default=None),
    provider: str | None = None,
    run_id: str | None = None,
    db: Session = Depends(get_db),
):
    now = datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
    if kind == "forecast":
        start_utc = _as_utc(start, loc.timezone) if start else now
        end_utc = _as_utc(end, loc.timezone) if end else start_utc + timedelta(hours=48)
    else:
        local_midnight = datetime.combine(_local_today(loc), time.min)
        end_utc = _as_utc(end, loc.timezone) if end else _as_utc(local_midnight, loc.timezone)
        start_utc = _as_utc(start, loc.timezone) if start else end_utc - timedelta(hours=48)
    if end_utc - start_utc > timedelta(days=31):
        raise HTTPException(422, "range limited to 31 days")

    stmt = select(WeatherHourly).where(WeatherHourly.location_id == loc.id,
                                       WeatherHourly.valid_time >= start_utc, WeatherHourly.valid_time <= end_utc)
    if kind == "forecast":
        if run_id is None:
            latest = _latest_run(db, loc.id, provider, None, WeatherHourly)
            if latest is None:
                return {"location": loc, "kind": kind, "run_id": None, "hours": []}
            run_id = latest.run_id
        stmt = stmt.where(WeatherHourly.data_kind == "FORECAST", WeatherHourly.run_id == run_id)
    else:
        stmt = stmt.where(WeatherHourly.data_kind == "OBSERVED")
    if provider:
        stmt = stmt.where(WeatherHourly.provider == provider)
    rows = db.scalars(stmt.order_by(WeatherHourly.valid_time)).all()
    return {"location": loc, "kind": kind, "run_id": run_id if kind == "forecast" else None, "hours": rows}


@router.get("/weather/accuracy", summary="Forecast verification per lead day (MAE/RMSE/MBE, POD/FAR/CSI, Brier)")
def weather_accuracy(
    start: date | None = Query(default=None, description="Default: 30 days ago"),
    end: date | None = Query(default=None, description="Default: yesterday"),
    provider: str | None = None,
    model: str | None = None,
    location_id: int | None = None,
    province: str | None = None,
    group_by: str = Query(default="", description="Comma list of: location, province, provider, model, month, season"),
    lead_days: str = Query(default="1,2,3,4,5,6,7"),
    rain_threshold_mm: float = Query(default=1.0, ge=0),
    final_only: bool = Query(default=False, description="Only score against FINAL observations"),
    db: Session = Depends(get_db),
):
    try:
        groups = AccuracyQuery(group_by=[g.strip() for g in group_by.split(",") if g.strip()]).group_by
        leads = [int(x) for x in lead_days.split(",") if x.strip()]
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from None
    today = datetime.now(ZoneInfo("Asia/Bangkok")).date()
    end = end or today - timedelta(days=1)
    start = start or end - timedelta(days=29)
    return accuracy.report(db, start=start, end=end, group_by=groups, lead_days=leads, threshold=rain_threshold_mm,
                           provider=provider, model=model, location_id=location_id, province=province,
                           final_only=final_only)


@router.post("/weather/sync", dependencies=[Depends(require_admin)], summary="Run an ingestion job now (admin)")
def sync(body: SyncRequest):
    if body.job == "backfill" and (body.start is None or body.end is None):
        raise HTTPException(422, "backfill requires start and end")
    return run_job(body.job, location_ids=body.location_ids, start=body.start, end=body.end)


@router.get("/weather/ingestion-logs", dependencies=[Depends(require_admin)], summary="Recent ingestion logs (admin)")
def ingestion_logs(job_type: str | None = None, status_: str | None = Query(default=None, alias="status"),
                   limit: int = Query(default=100, ge=1, le=1000), db: Session = Depends(get_db)):
    stmt = select(WeatherIngestionLog).order_by(WeatherIngestionLog.started_at.desc()).limit(limit)
    if job_type:
        stmt = stmt.where(WeatherIngestionLog.job_type == job_type)
    if status_:
        stmt = stmt.where(WeatherIngestionLog.status == status_)
    return [{c.name: getattr(r, c.name) for c in WeatherIngestionLog.__table__.columns} for r in db.scalars(stmt)]
