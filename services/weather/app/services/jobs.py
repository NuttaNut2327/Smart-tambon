"""Job entry points shared by the scheduler and POST /api/v1/weather/sync.
Every job runs under a Postgres advisory lock named after the job type."""

import logging
from datetime import UTC, date, datetime

from app import db as db_module
from app.models import WeatherIngestionLog
from app.providers import observation_provider, primary_and_secondary
from app.services import ingestion
from app.services.locks import advisory_lock

log = logging.getLogger(__name__)

JOB_TYPES = ("current", "forecast", "observation", "backfill")


def run_job(job_type: str, *, location_ids=None, start: date | None = None, end: date | None = None,
            providers=None, obs_provider=None) -> dict:
    if job_type not in JOB_TYPES:
        raise ValueError(f"unknown job type '{job_type}'")
    engine = db_module.engine
    with advisory_lock(engine, job_type) as acquired:
        session = db_module.SessionLocal()
        try:
            if not acquired:
                now = datetime.now(UTC)
                session.add(WeatherIngestionLog(job_type=job_type, status="SKIPPED", started_at=now, finished_at=now,
                                                duration_ms=0, error="another run holds the advisory lock"))
                session.commit()
                log.info("job skipped: already running", extra={"job_type": job_type})
                return {"job_type": job_type, "status": "SKIPPED", "reason": "already running", "results": []}

            primary, secondary = providers or primary_and_secondary()
            obs = obs_provider or observation_provider()
            if job_type == "current":
                results = ingestion.sync_current(session, primary, secondary, location_ids)
            elif job_type == "forecast":
                results = ingestion.sync_forecast(session, primary, secondary, location_ids)
            elif job_type == "observation":
                results = ingestion.finalize_observations(session, obs, location_ids)
            else:
                if start is None or end is None:
                    raise ValueError("backfill requires start and end dates")
                results = ingestion.backfill_history(session, obs, start, end, location_ids)
        finally:
            session.close()

    statuses = {r.status for r in results}
    status = "SUCCESS" if statuses <= {"SUCCESS"} else ("FAILED" if statuses == {"FAILED"} else "PARTIAL")
    if any(r.is_fallback for r in results) and status == "SUCCESS":
        status = "SUCCESS_WITH_FALLBACK"
    return {"job_type": job_type, "status": status, "results": [r.as_dict() for r in results]}
