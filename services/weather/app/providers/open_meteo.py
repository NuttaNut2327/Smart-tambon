"""Open-Meteo providers.

Model identifiers and per-model parameter availability were verified against
https://open-meteo.com/en/docs and https://open-meteo.com/en/docs/ecmwf-api
(and live responses) on 2026-10-16:

* ``ecmwf_ifs025`` – ECMWF IFS 0.25° open data. Returns null for ``visibility``,
  ``uv_index`` / ``uv_index_max`` (no such fields in ECMWF open data) — those are
  stored as NULL and listed in ``unavailable_params``.
* ``gfs_global`` – NCEP GFS (0.11°/0.25°). Provides visibility and UV.

The model is always passed explicitly (never ``best_match``) so Open-Meteo does
not silently blend or substitute models. Run ids come from the per-model
metadata endpoint ``/data/<meta_id>/static/meta.json`` (last_run_initialisation_time).
"""

from __future__ import annotations

import logging
import time
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.providers.base import (
    CurrentData,
    ForecastData,
    LocationLike,
    ObservationData,
    ObservationProvider,
    ProviderError,
    WeatherProvider,
)
from app.providers.http import RetryingClient

log = logging.getLogger(__name__)

FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
META_URL = "https://api.open-meteo.com/data/{meta_id}/static/meta.json"

# Open-Meteo variable -> column name
CURRENT_PARAMS = {
    "temperature_2m": "temperature_c",
    "apparent_temperature": "apparent_temperature_c",
    "relative_humidity_2m": "relative_humidity_pct",
    "dew_point_2m": "dew_point_c",
    "precipitation": "precipitation_mm",
    "rain": "rain_mm",
    "weather_code": "weather_code",
    "cloud_cover": "cloud_cover_pct",
    "pressure_msl": "pressure_msl_hpa",
    "surface_pressure": "surface_pressure_hpa",
    "wind_speed_10m": "wind_speed_kmh",
    "wind_direction_10m": "wind_direction_deg",
    "wind_gusts_10m": "wind_gusts_kmh",
    "visibility": "visibility_m",
    "uv_index": "uv_index",
    "is_day": "is_day",
}

DAILY_FORECAST_PARAMS = {
    "weather_code": "weather_code",
    "temperature_2m_max": "temperature_max_c",
    "temperature_2m_min": "temperature_min_c",
    "apparent_temperature_max": "apparent_temperature_max_c",
    "apparent_temperature_min": "apparent_temperature_min_c",
    "precipitation_sum": "precipitation_sum_mm",
    "rain_sum": "rain_sum_mm",
    "precipitation_hours": "precipitation_hours",
    "precipitation_probability_max": "precipitation_probability_max_pct",
    "wind_speed_10m_max": "wind_speed_max_kmh",
    "wind_gusts_10m_max": "wind_gusts_max_kmh",
    "wind_direction_10m_dominant": "wind_direction_dominant_deg",
    "relative_humidity_2m_mean": "relative_humidity_mean_pct",
    "cloud_cover_mean": "cloud_cover_mean_pct",
    "shortwave_radiation_sum": "shortwave_radiation_sum_mj_m2",
    "et0_fao_evapotranspiration": "et0_mm",
    "uv_index_max": "uv_index_max",
    "sunrise": "sunrise",
    "sunset": "sunset",
    "daylight_duration": "daylight_duration_s",
}

HOURLY_FORECAST_PARAMS = {
    "temperature_2m": "temperature_c",
    "apparent_temperature": "apparent_temperature_c",
    "relative_humidity_2m": "relative_humidity_pct",
    "dew_point_2m": "dew_point_c",
    "precipitation": "precipitation_mm",
    "precipitation_probability": "precipitation_probability_pct",
    "weather_code": "weather_code",
    "cloud_cover": "cloud_cover_pct",
    "pressure_msl": "pressure_msl_hpa",
    "wind_speed_10m": "wind_speed_kmh",
    "wind_direction_10m": "wind_direction_deg",
    "wind_gusts_10m": "wind_gusts_kmh",
    "visibility": "visibility_m",
    "uv_index": "uv_index",
    "is_day": "is_day",
}

DAILY_ARCHIVE_PARAMS = {
    "weather_code": "weather_code",
    "temperature_2m_max": "temperature_max_c",
    "temperature_2m_min": "temperature_min_c",
    "temperature_2m_mean": "temperature_mean_c",
    "precipitation_sum": "precipitation_sum_mm",
    "rain_sum": "rain_sum_mm",
    "precipitation_hours": "precipitation_hours",
    "wind_speed_10m_max": "wind_speed_max_kmh",
    "wind_gusts_10m_max": "wind_gusts_max_kmh",
    "wind_direction_10m_dominant": "wind_direction_dominant_deg",
    "relative_humidity_2m_mean": "relative_humidity_mean_pct",
    "shortwave_radiation_sum": "shortwave_radiation_sum_mj_m2",
    "et0_fao_evapotranspiration": "et0_mm",
}

HOURLY_ARCHIVE_PARAMS = {
    k: v
    for k, v in HOURLY_FORECAST_PARAMS.items()
    if k not in ("precipitation_probability", "visibility", "uv_index")
}

INT_COLUMNS = {"weather_code"}
BOOL_COLUMNS = {"is_day"}
TIME_COLUMNS = {"sunrise", "sunset"}


def _utc(ts: int | float) -> datetime:
    return datetime.fromtimestamp(ts, UTC)


def _local_date(ts: int | float, offset_s: int) -> date:
    return datetime.fromtimestamp(ts + offset_s, UTC).date()


def _convert(column: str, value):
    if value is None:
        return None
    if column in INT_COLUMNS:
        return int(value)
    if column in BOOL_COLUMNS:
        return bool(value)
    if column in TIME_COLUMNS:
        return _utc(value)
    return float(value)


def _unavailable(block: dict, units: dict, mapping: dict) -> list[str]:
    """A parameter is unavailable for a model when Open-Meteo reports its unit
    as 'undefined' or returns it null for every timestep."""
    missing = []
    for param in mapping:
        values = block.get(param)
        unit = (units or {}).get(param)
        if values is None or unit == "undefined":
            missing.append(param)
        elif isinstance(values, list) and values and all(v is None for v in values):
            missing.append(param)
        elif not isinstance(values, list) and values is None:
            missing.append(param)
    return missing


def _rows(block: dict, mapping: dict) -> list[dict]:
    times = block.get("time") or []
    rows = []
    for i, t in enumerate(times):
        row = {"_ts": t}
        for param, column in mapping.items():
            series = block.get(param)
            row[column] = _convert(column, series[i] if series is not None and i < len(series) else None)
        rows.append(row)
    return rows


class OpenMeteoForecastProvider(WeatherProvider):
    def __init__(self, *, name: str, model: str, meta_id: str, description: str, client: RetryingClient):
        self.name = name
        self.model = model
        self.meta_id = meta_id
        self.description = description
        self.client = client
        self._meta_cache: tuple[float, datetime | None] | None = None

    def _params(self, location: LocationLike, **extra) -> dict:
        return {
            "latitude": location.latitude,
            "longitude": location.longitude,
            "timezone": location.timezone,
            "timeformat": "unixtime",
            "models": self.model,
            "wind_speed_unit": "kmh",
            "precipitation_unit": "mm",
            "temperature_unit": "celsius",
            **extra,
        }

    def fetch_current(self, location: LocationLike) -> CurrentData:
        body, attempts = self.client.get_json(
            FORECAST_URL, self._params(location, current=",".join(CURRENT_PARAMS))
        )
        current = body.get("current")
        if not current or current.get("time") is None:
            raise ProviderError(f"{self.name}: response has no 'current' block", attempts=attempts)
        values = {col: _convert(col, current.get(param)) for param, col in CURRENT_PARAMS.items()}
        missing = [p for p in CURRENT_PARAMS if current.get(p) is None or body.get("current_units", {}).get(p) == "undefined"]
        return CurrentData(
            provider=self.name,
            model=self.model,
            fetched_at=datetime.now(UTC),
            observed_at=_utc(current["time"]),
            interval_seconds=current.get("interval"),
            values=values,
            unavailable_params=missing,
            attempts=attempts,
            elevation_m=body.get("elevation"),
        )

    def run_metadata(self) -> datetime | None:
        """Model run initialisation time from Open-Meteo metadata (cached 10 min)."""
        now = time.monotonic()
        if self._meta_cache and now - self._meta_cache[0] < 600:
            return self._meta_cache[1]
        init = None
        try:
            body, _ = self.client.get_json(META_URL.format(meta_id=self.meta_id), {})
            if body.get("last_run_initialisation_time"):
                init = _utc(body["last_run_initialisation_time"])
        except ProviderError as exc:
            log.warning("model metadata unavailable", extra={"provider": self.name, "error": str(exc)})
        self._meta_cache = (now, init)
        return init

    def fetch_forecast(self, location: LocationLike, days: int) -> ForecastData:
        body, attempts = self.client.get_json(
            FORECAST_URL,
            self._params(
                location,
                forecast_days=days,
                daily=",".join(DAILY_FORECAST_PARAMS),
                hourly=",".join(HOURLY_FORECAST_PARAMS),
            ),
        )
        daily_block, hourly_block = body.get("daily"), body.get("hourly")
        if not daily_block or not daily_block.get("time"):
            raise ProviderError(f"{self.name}: response has no daily forecast", attempts=attempts)
        fetched_at = datetime.now(UTC)
        offset = int(body.get("utc_offset_seconds") or 0)
        tz = ZoneInfo(location.timezone)

        init = self.run_metadata()
        if init is not None:
            run_id = f"{self.model}@{init:%Y%m%dT%H%MZ}"
            source = "model_metadata"
        else:
            bucket = fetched_at.replace(hour=fetched_at.hour - fetched_at.hour % 6, minute=0, second=0, microsecond=0)
            run_id = f"{self.model}@fetch-{bucket:%Y%m%dT%H%MZ}"
            source = "fetch_time_bucket"
        issue_date = (init or fetched_at).astimezone(tz).date()

        daily = []
        for row in _rows(daily_block, DAILY_FORECAST_PARAMS):
            row["forecast_date"] = _local_date(row.pop("_ts"), offset)
            row["forecast_lead_days"] = (row["forecast_date"] - issue_date).days
            daily.append(row)
        hourly = []
        for row in _rows(hourly_block or {}, HOURLY_FORECAST_PARAMS):
            row["valid_time"] = _utc(row.pop("_ts"))
            hourly.append(row)

        missing = _unavailable(daily_block, body.get("daily_units"), DAILY_FORECAST_PARAMS)
        missing += [
            f"hourly.{p}" for p in _unavailable(hourly_block or {}, body.get("hourly_units"), HOURLY_FORECAST_PARAMS)
        ]
        return ForecastData(
            provider=self.name,
            model=self.model,
            fetched_at=fetched_at,
            run_id=run_id,
            run_init_time=init,
            run_id_source=source,
            issue_date=issue_date,
            daily=daily,
            hourly=hourly,
            unavailable_params=missing,
            attempts=attempts,
        )


class OpenMeteoArchiveProvider(ObservationProvider):
    """Reanalysis from the Open-Meteo historical weather API.

    * ``era5`` (ECMWF ERA5/ERA5T, ~5 day delay) → data_quality FINAL, is_final.
    * ``best_match`` fills the most recent days from ECMWF IFS analysis before
      ERA5 arrives → PROVISIONAL, re-checked nightly until ERA5 is available.
    """

    name = "open_meteo_archive"
    source_type = "REANALYSIS"

    def __init__(self, client: RetryingClient):
        self.client = client

    def _fetch(self, location: LocationLike, start: date, end: date, model: str) -> tuple[dict, int]:
        return self.client.get_json(
            ARCHIVE_URL,
            {
                "latitude": location.latitude,
                "longitude": location.longitude,
                "timezone": location.timezone,
                "timeformat": "unixtime",
                "start_date": start.isoformat(),
                "end_date": end.isoformat(),
                "models": model,
                "wind_speed_unit": "kmh",
                "daily": ",".join(DAILY_ARCHIVE_PARAMS),
                "hourly": ",".join(HOURLY_ARCHIVE_PARAMS),
            },
        )

    def fetch_observations(self, location: LocationLike, start: date, end: date) -> ObservationData:
        era5, a1 = self._fetch(location, start, end, "era5")
        best, a2 = self._fetch(location, start, end, "best_match")
        fetched_at = datetime.now(UTC)
        offset = int(era5.get("utc_offset_seconds") or best.get("utc_offset_seconds") or 0)

        def has_core(row: dict) -> bool:
            return row.get("temperature_max_c") is not None and row.get("precipitation_sum_mm") is not None

        era5_daily = {_local_date(r["_ts"], offset): r for r in _rows(era5.get("daily") or {}, DAILY_ARCHIVE_PARAMS)}
        best_daily = {_local_date(r["_ts"], offset): r for r in _rows(best.get("daily") or {}, DAILY_ARCHIVE_PARAMS)}
        daily = []
        for day in sorted(set(era5_daily) | set(best_daily)):
            if day in era5_daily and has_core(era5_daily[day]):
                row, model, final = era5_daily[day], "era5", True
            elif day in best_daily and has_core(best_daily[day]):
                row, model, final = best_daily[day], "best_match", False
            else:
                continue  # nothing published yet: store nothing rather than zeros
            row = {k: v for k, v in row.items() if k != "_ts"}
            row.update(
                observation_date=day,
                model=model,
                is_final=final,
                data_quality="FINAL" if final else "PROVISIONAL",
                source_type=self.source_type,
                source_name=self.name,
            )
            daily.append(row)

        era5_hourly = {r["_ts"]: r for r in _rows(era5.get("hourly") or {}, HOURLY_ARCHIVE_PARAMS)}
        hourly = []
        for r in _rows(best.get("hourly") or {}, HOURLY_ARCHIVE_PARAMS):
            ts = r["_ts"]
            e = era5_hourly.get(ts)
            if e is not None and e.get("temperature_c") is not None:
                chosen, model = e, "era5"
            elif r.get("temperature_c") is not None:
                chosen, model = r, "best_match"
            else:
                continue
            row = {k: v for k, v in chosen.items() if k != "_ts"}
            row.update(valid_time=_utc(ts), model=model)
            hourly.append(row)

        missing = sorted(
            set(_unavailable(era5.get("daily") or {}, era5.get("daily_units"), DAILY_ARCHIVE_PARAMS))
            & set(_unavailable(best.get("daily") or {}, best.get("daily_units"), DAILY_ARCHIVE_PARAMS))
        )
        return ObservationData(
            provider=self.name,
            fetched_at=fetched_at,
            daily=daily,
            hourly=hourly,
            unavailable_params=missing,
            attempts=a1 + a2,
        )


def window(today: date, lookback_days: int) -> tuple[date, date]:
    return today - timedelta(days=lookback_days), today - timedelta(days=1)
