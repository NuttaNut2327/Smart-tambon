"""The only process that registers recurring jobs (the API never does).
All triggers use Asia/Bangkok; each job also takes a Postgres advisory lock so a
second scheduler replica or a concurrent manual sync cannot double-run it."""

import logging
import signal
from datetime import datetime, timedelta

from apscheduler.schedulers.blocking import BlockingScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app.config import get_settings
from app.logging_setup import setup_logging
from app.services.jobs import run_job

log = logging.getLogger("app.scheduler")
TZ = "Asia/Bangkok"
RETRY_DELAY = timedelta(hours=3)


def _run(job_type: str) -> dict | None:
    try:
        return run_job(job_type)
    except Exception:
        log.exception("scheduled job crashed", extra={"job_type": job_type})
        return None


def observation_job(scheduler: BlockingScheduler | None = None) -> None:
    """02:00 finalisation. If any day is still provisional (ERA5 not yet
    published), schedule a one-off retry a few hours later."""
    summary = _run("observation")
    pending = any(
        r.get("status") == "FAILED" or r.get("details", {}).get("provisional_dates")
        for r in (summary or {}).get("results", [])
    ) or summary is None
    if pending and scheduler is not None:
        when = datetime.now(scheduler.timezone) + RETRY_DELAY
        if when.hour < 23:  # don't retry past the end of the local day; tomorrow's 02:00 run picks it up
            scheduler.add_job(_run, "date", run_date=when, args=["observation"], id="observation-retry",
                              replace_existing=True)
            log.info("observation retry scheduled", extra={"run_date": when.isoformat()})


def build_scheduler() -> BlockingScheduler:
    scheduler = BlockingScheduler(timezone=TZ, job_defaults={"coalesce": True, "max_instances": 1,
                                                             "misfire_grace_time": 600})
    scheduler.add_job(_run, IntervalTrigger(minutes=30, timezone=TZ), args=["current"], id="current")
    scheduler.add_job(_run, CronTrigger(hour="*/6", minute=15, timezone=TZ), args=["forecast"], id="forecast")
    scheduler.add_job(observation_job, CronTrigger(hour=2, minute=0, timezone=TZ), args=[scheduler],
                      id="observation")
    return scheduler


def main() -> None:
    settings = get_settings()
    setup_logging(settings.log_level)
    scheduler = build_scheduler()
    if settings.initial_sync:
        log.info("initial sync starting")
        for job in ("forecast", "current", "observation"):
            _run(job)
    signal.signal(signal.SIGTERM, lambda *_: scheduler.shutdown(wait=False))
    log.info("scheduler started", extra={"jobs": [j.id for j in scheduler.get_jobs()]})
    scheduler.start()


if __name__ == "__main__":
    main()
