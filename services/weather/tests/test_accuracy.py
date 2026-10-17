"""10. accuracy metrics."""

import math
from datetime import UTC, datetime, timedelta

import pytest

from app.services import accuracy, ingestion
from tests.conftest import FakeObservations, FakeProvider, local_today, make_forecast, obs_row


def test_continuous_metrics():
    m = accuracy.continuous([(30.0, 32.0), (34.0, 33.0), (31.0, 31.0), (None, 30.0)])
    # errors: -2, +1, 0
    assert m["n"] == 3
    assert m["mae"] == pytest.approx(1.0)
    assert m["rmse"] == pytest.approx(round(math.sqrt(5 / 3), 3))
    assert m["mbe"] == pytest.approx(round(-1 / 3, 3))


def test_contingency_scores():
    # (forecast mm, observed mm), threshold 1 mm
    pairs = [(5, 3), (2, 0), (0, 4), (0, 0), (3, 1), (0.5, 0.2)]
    m = accuracy.categorical(pairs, 1.0)
    assert (m["hits"], m["misses"], m["false_alarms"], m["correct_negatives"]) == (2, 1, 1, 2)
    assert m["pod"] == pytest.approx(0.667)
    assert m["far"] == pytest.approx(0.333)
    assert m["csi"] == pytest.approx(0.5)


def test_contingency_no_events_is_null_not_zero():
    m = accuracy.categorical([(0, 0), (0, 0)], 1.0)
    assert m["pod"] is None and m["far"] is None and m["csi"] is None


def test_brier_score():
    m = accuracy.brier([(100, 5), (0, 0), (50, 3), (None, 1)], 1.0)
    assert m["n"] == 3
    assert m["brier_score"] == pytest.approx(round((0 + 0 + 0.25) / 3, 4))


def test_report_pairs_by_lead_day_and_groups(seeded):
    today = local_today()
    target = today - timedelta(days=1)
    # Forecast issued 3 days before the target and 1 day before it, by two models
    for lead in (1, 3):
        issue = target - timedelta(days=lead)
        for model, tmax in (("m_a", 34.0), ("m_b", 31.0)):
            fc = make_forecast(provider="p", model=model, today=issue, issue=issue, days=lead + 1, tmax=tmax,
                               run_init=datetime.combine(issue, datetime.min.time(), UTC))
            ingestion.sync_forecast(seeded, FakeProvider(forecast=fc), None, location_ids=[1])
    ingestion.finalize_observations(seeded, FakeObservations([obs_row(target, tmax=32.0, rain=3.0)]), [1],
                                    lookback_days=5)

    rep = accuracy.report(seeded, start=target, end=target, group_by=["model", "season"], lead_days=[1, 3])
    assert rep["pairs_with_final_observation"] == rep["pairs_total"]
    res = {(r["group"]["model"], r["lead_days"]): r for r in rep["results"]}
    assert set(res) == {("m_a", 1), ("m_a", 3), ("m_b", 1), ("m_b", 3)}
    # make_forecast adds 0.1 °C per day offset: lead L -> tmax + 0.1*L
    assert res[("m_a", 1)]["temperature_max"]["mbe"] == pytest.approx(2.1)
    assert res[("m_b", 3)]["temperature_max"]["mbe"] == pytest.approx(-0.7)
    assert res[("m_a", 1)]["rain_occurrence"]["hits"] == 1
    assert res[("m_a", 1)]["group"]["season"] == accuracy.SEASONS[target.month]


def test_accuracy_endpoint_validates_group_by(client):
    assert client.get("/api/v1/weather/accuracy", params={"group_by": "planet"}).status_code == 422
    r = client.get("/api/v1/weather/accuracy", params={"group_by": "province,month"})
    assert r.status_code == 200 and r.json()["results"] == []
