"""9. scheduler registration, advisory locks, observation retry; 6. timezone in API."""

from datetime import UTC, datetime, timedelta

from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger

from app import scheduler as sched
from app.db import engine
from app.services import ingestion
from app.services.jobs import run_job
from app.services.locks import advisory_lock
from tests.conftest import FakeProvider


def test_jobs_registered_in_bangkok_time():
    s = sched.build_scheduler()
    jobs = {j.id: j for j in s.get_jobs()}
    assert set(jobs) == {"current", "forecast", "observation", "gistda-prune"}
    assert str(s.timezone) == "Asia/Bangkok"

    cur = jobs["current"].trigger
    assert isinstance(cur, IntervalTrigger) and cur.interval == timedelta(minutes=30)

    fc = jobs["forecast"].trigger
    assert isinstance(fc, CronTrigger) and str(fc.timezone) == "Asia/Bangkok"
    assert str(fc.fields[fc.FIELD_NAMES.index("hour")]) == "*/6"

    ob = jobs["observation"].trigger
    assert str(ob.fields[ob.FIELD_NAMES.index("hour")]) == "2"
    assert str(ob.fields[ob.FIELD_NAMES.index("minute")]) == "0"


def test_api_does_not_start_a_scheduler():
    import app.main as main_module

    assert not any("scheduler" in name.lower() for name in vars(main_module))


def test_advisory_lock_blocks_duplicate_run(seeded):
    provider = FakeProvider()
    with advisory_lock(engine, "current") as got:
        assert got
        result = run_job("current", providers=(provider, None))
    assert result["status"] == "SKIPPED"
    assert provider.calls == 0
    # released afterwards
    assert run_job("current", providers=(provider, None))["status"] == "SUCCESS"


def test_lock_is_per_job_type(seeded):
    with advisory_lock(engine, "forecast") as got:
        assert got
        assert run_job("current", providers=(FakeProvider(), None))["status"] == "SUCCESS"


def test_observation_retry_scheduled_when_provisional(monkeypatch):
    s = sched.build_scheduler()
    monkeypatch.setattr(sched, "_run", lambda job: {"results": [{"status": "SUCCESS",
                                                                "details": {"provisional_dates": ["2026-10-15"]}}]})
    monkeypatch.setattr(sched, "datetime", type("D", (), {"now": staticmethod(
        lambda tz=None: datetime(2026, 10, 16, 2, 0, tzinfo=UTC).astimezone(tz))}))
    sched.observation_job(s)
    assert s.get_job("observation-retry") is not None


def test_no_retry_when_everything_final(monkeypatch):
    s = sched.build_scheduler()
    monkeypatch.setattr(sched, "_run", lambda job: {"results": [{"status": "SUCCESS",
                                                                "details": {"provisional_dates": []}}]})
    sched.observation_job(s)
    assert s.get_job("observation-retry") is None


def test_hourly_naive_times_are_local(client, seeded):
    ingestion.sync_forecast(seeded, FakeProvider(), None, location_ids=[1])
    first_hour = datetime.now(UTC).replace(minute=0, second=0, microsecond=0)
    local_naive = (first_hour + timedelta(hours=7)).replace(tzinfo=None)
    r = client.get("/api/v1/weather/hourly", params={"code": "nakhon-sawan", "start": local_naive.isoformat(),
                                                     "end": local_naive.isoformat()}).json()
    assert len(r["hours"]) == 1
    assert r["hours"][0]["valid_time"] == first_hour.strftime("%Y-%m-%dT%H:%M:%SZ")
