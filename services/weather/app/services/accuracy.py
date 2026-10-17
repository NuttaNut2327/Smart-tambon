"""Forecast verification against daily observations.

Continuous (temperature max/min, rainfall): MAE, RMSE, MBE (forecast − observed).
Rain occurrence (precipitation ≥ threshold): POD, FAR, CSI from the 2×2
contingency table, and Brier score using precipitation_probability_max.

For each (location, provider, model, issue_date, forecast_date) only the latest
run issued that day is scored, so 4 runs/day do not count four times.
"""

from __future__ import annotations

import math
from collections import defaultdict
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date

from sqlalchemy import text
from sqlalchemy.orm import Session

GROUP_KEYS = ("location", "province", "provider", "model", "month", "season")

# Thai Meteorological Department seasons, approximated to whole months
SEASONS = {11: "winter", 12: "winter", 1: "winter", 2: "winter",
           3: "summer", 4: "summer", 5: "summer",
           6: "rainy", 7: "rainy", 8: "rainy", 9: "rainy", 10: "rainy"}


@dataclass
class Pair:
    location_id: int
    location_code: str
    province: str | None
    provider: str
    model: str
    forecast_date: date
    lead_days: int
    f_tmax: float | None
    f_tmin: float | None
    f_rain: float | None
    f_rain_prob: float | None  # percent
    o_tmax: float | None
    o_tmin: float | None
    o_rain: float | None
    obs_final: bool


def continuous(pairs: Iterable[tuple[float | None, float | None]]) -> dict:
    errors = [f - o for f, o in pairs if f is not None and o is not None]
    n = len(errors)
    if n == 0:
        return {"n": 0, "mae": None, "rmse": None, "mbe": None}
    return {
        "n": n,
        "mae": round(sum(abs(e) for e in errors) / n, 3),
        "rmse": round(math.sqrt(sum(e * e for e in errors) / n), 3),
        "mbe": round(sum(errors) / n, 3),
    }


def categorical(pairs: Iterable[tuple[float | None, float | None]], threshold: float) -> dict:
    hits = misses = false_alarms = correct_neg = 0
    for f, o in pairs:
        if f is None or o is None:
            continue
        fy, oy = f >= threshold, o >= threshold
        if fy and oy:
            hits += 1
        elif oy:
            misses += 1
        elif fy:
            false_alarms += 1
        else:
            correct_neg += 1

    def ratio(a: int, b: int) -> float | None:
        return round(a / b, 3) if b else None

    return {
        "threshold_mm": threshold,
        "hits": hits,
        "misses": misses,
        "false_alarms": false_alarms,
        "correct_negatives": correct_neg,
        "pod": ratio(hits, hits + misses),
        "far": ratio(false_alarms, hits + false_alarms),
        "csi": ratio(hits, hits + misses + false_alarms),
    }


def brier(pairs: Iterable[tuple[float | None, float | None]], threshold: float) -> dict:
    """pairs of (probability %, observed mm)."""
    terms = [((p / 100.0) - (1.0 if o >= threshold else 0.0)) ** 2 for p, o in pairs if p is not None and o is not None]
    return {"n": len(terms), "brier_score": round(sum(terms) / len(terms), 4) if terms else None}


def score(pairs: list[Pair], threshold: float) -> dict:
    return {
        "n_pairs": len(pairs),
        "temperature_max": continuous((p.f_tmax, p.o_tmax) for p in pairs),
        "temperature_min": continuous((p.f_tmin, p.o_tmin) for p in pairs),
        "rainfall": continuous((p.f_rain, p.o_rain) for p in pairs),
        "rain_occurrence": categorical(((p.f_rain, p.o_rain) for p in pairs), threshold),
        "rain_probability": brier(((p.f_rain_prob, p.o_rain) for p in pairs), threshold),
    }


def group_value(pair: Pair, key: str):
    return {
        "location": pair.location_code,
        "province": pair.province,
        "provider": pair.provider,
        "model": pair.model,
        "month": pair.forecast_date.strftime("%Y-%m"),
        "season": SEASONS[pair.forecast_date.month],
    }[key]


def aggregate(pairs: list[Pair], group_by: list[str], threshold: float, lead_days: Iterable[int]) -> list[dict]:
    buckets: dict[tuple, list[Pair]] = defaultdict(list)
    wanted = set(lead_days)
    for p in pairs:
        if p.lead_days not in wanted:
            continue
        key = tuple(group_value(p, k) for k in group_by) + (p.lead_days,)
        buckets[key].append(p)
    out = []
    for key in sorted(buckets, key=lambda k: tuple("" if v is None else str(v) for v in k)):
        group = dict(zip(group_by, key[:-1], strict=True))
        out.append({"group": group, "lead_days": key[-1], **score(buckets[key], threshold)})
    return out


PAIRS_SQL = text(
    """
    WITH latest AS (
        SELECT DISTINCT ON (f.location_id, f.provider, f.model, f.issue_date, f.forecast_date)
               f.*
        FROM weather_daily_forecast f
        WHERE f.forecast_date BETWEEN :start AND :end
          AND (CAST(:provider AS text) IS NULL OR f.provider = :provider)
          AND (CAST(:model AS text) IS NULL OR f.model = :model)
          AND (CAST(:location_id AS integer) IS NULL OR f.location_id = :location_id)
        ORDER BY f.location_id, f.provider, f.model, f.issue_date, f.forecast_date, f.fetched_at DESC
    )
    SELECT l.id AS location_id, l.code AS location_code, l.province,
           f.provider, f.model, f.forecast_date, f.forecast_lead_days AS lead_days,
           f.temperature_max_c AS f_tmax, f.temperature_min_c AS f_tmin,
           f.precipitation_sum_mm AS f_rain, f.precipitation_probability_max_pct AS f_rain_prob,
           o.temperature_max_c AS o_tmax, o.temperature_min_c AS o_tmin,
           o.precipitation_sum_mm AS o_rain, o.is_final AS obs_final
    FROM latest f
    JOIN weather_locations l ON l.id = f.location_id
    JOIN weather_daily_observation o
      ON o.location_id = f.location_id AND o.observation_date = f.forecast_date
     AND (NOT CAST(:final_only AS boolean) OR o.is_final)
    WHERE (CAST(:province AS text) IS NULL OR l.province = :province)
    """
)


def load_pairs(db: Session, *, start: date, end: date, provider=None, model=None, location_id=None,
               province=None, final_only=False) -> list[Pair]:
    rows = db.execute(
        PAIRS_SQL,
        dict(start=start, end=end, provider=provider, model=model, location_id=location_id, province=province,
             final_only=final_only),
    ).mappings()
    return [Pair(**r) for r in rows]


def report(db: Session, *, start: date, end: date, group_by: list[str], lead_days: list[int],
           threshold: float = 1.0, **filters) -> dict:
    pairs = load_pairs(db, start=start, end=end, **filters)
    return {
        "start": start,
        "end": end,
        "group_by": group_by,
        "rain_threshold_mm": threshold,
        "pairs_total": len(pairs),
        "pairs_with_final_observation": sum(1 for p in pairs if p.obs_final),
        "results": aggregate(pairs, group_by, threshold, lead_days),
    }
