from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.services.accuracy import GROUP_KEYS


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class LocationBase(BaseModel):
    code: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9_-]*$")
    name: str = Field(min_length=1, max_length=255)
    name_th: str | None = None
    province: str | None = None
    district: str | None = None
    subdistrict: str | None = None
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    timezone: str = "Asia/Bangkok"
    is_active: bool = True

    @field_validator("timezone")
    @classmethod
    def valid_tz(cls, v: str) -> str:
        from zoneinfo import ZoneInfo

        try:
            ZoneInfo(v)
        except Exception as exc:
            raise ValueError(f"unknown timezone '{v}'") from exc
        return v


class LocationCreate(LocationBase):
    pass


class LocationUpdate(BaseModel):
    name: str | None = None
    name_th: str | None = None
    province: str | None = None
    district: str | None = None
    subdistrict: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    timezone: str | None = None
    is_active: bool | None = None

    @field_validator("timezone")
    @classmethod
    def valid_tz(cls, v):
        return v if v is None else LocationBase.valid_tz(v)


class LocationOut(ORM):
    id: int
    code: str
    name: str
    name_th: str | None
    province: str | None
    district: str | None
    subdistrict: str | None
    latitude: float
    longitude: float
    timezone: str
    elevation_m: float | None
    is_active: bool


class NearestLocationOut(LocationOut):
    distance_km: float


class Provenance(ORM):
    provider: str
    model: str
    fetched_at: datetime
    is_fallback: bool
    fallback_reason: str | None
    unavailable_params: list[str]


class CurrentOut(Provenance):
    observed_at: datetime
    interval_seconds: int | None
    temperature_c: float | None
    apparent_temperature_c: float | None
    relative_humidity_pct: float | None
    dew_point_c: float | None
    precipitation_mm: float | None
    rain_mm: float | None
    weather_code: int | None
    cloud_cover_pct: float | None
    pressure_msl_hpa: float | None
    surface_pressure_hpa: float | None
    wind_speed_kmh: float | None
    wind_direction_deg: float | None
    wind_gusts_kmh: float | None
    visibility_m: float | None
    uv_index: float | None
    is_day: bool | None


class CurrentResponse(BaseModel):
    location: LocationOut
    current: CurrentOut | None
    note: str = "Model-derived current conditions (not a ground-station observation)."


class DailyForecastOut(Provenance):
    run_id: str
    run_init_time: datetime | None
    run_id_source: str
    issue_date: date
    forecast_date: date
    forecast_lead_days: int
    weather_code: int | None
    temperature_max_c: float | None
    temperature_min_c: float | None
    apparent_temperature_max_c: float | None
    apparent_temperature_min_c: float | None
    precipitation_sum_mm: float | None
    rain_sum_mm: float | None
    precipitation_hours: float | None
    precipitation_probability_max_pct: float | None
    wind_speed_max_kmh: float | None
    wind_gusts_max_kmh: float | None
    wind_direction_dominant_deg: float | None
    relative_humidity_mean_pct: float | None
    cloud_cover_mean_pct: float | None
    shortwave_radiation_sum_mj_m2: float | None
    et0_mm: float | None
    uv_index_max: float | None
    sunrise: datetime | None
    sunset: datetime | None
    daylight_duration_s: float | None


class DailyForecastResponse(BaseModel):
    location: LocationOut
    run: dict | None
    days: list[DailyForecastOut]


class ObservationOut(ORM):
    observation_date: date
    source_type: str
    source_name: str
    model: str | None
    data_quality: str
    is_final: bool
    revision: int
    fetched_at: datetime
    finalized_at: datetime | None
    unavailable_params: list[str]
    weather_code: int | None
    temperature_max_c: float | None
    temperature_min_c: float | None
    temperature_mean_c: float | None
    precipitation_sum_mm: float | None
    rain_sum_mm: float | None
    precipitation_hours: float | None
    wind_speed_max_kmh: float | None
    wind_gusts_max_kmh: float | None
    wind_direction_dominant_deg: float | None
    relative_humidity_mean_pct: float | None
    shortwave_radiation_sum_mj_m2: float | None
    et0_mm: float | None


class HistoryResponse(BaseModel):
    location: LocationOut
    days: list[ObservationOut]


class HourlyOut(ORM):
    valid_time: datetime
    data_kind: str
    provider: str
    model: str
    run_id: str
    is_fallback: bool
    source_type: str | None
    temperature_c: float | None
    apparent_temperature_c: float | None
    relative_humidity_pct: float | None
    dew_point_c: float | None
    precipitation_mm: float | None
    precipitation_probability_pct: float | None
    weather_code: int | None
    cloud_cover_pct: float | None
    pressure_msl_hpa: float | None
    wind_speed_kmh: float | None
    wind_direction_deg: float | None
    wind_gusts_kmh: float | None
    visibility_m: float | None
    uv_index: float | None
    is_day: bool | None


class HourlyResponse(BaseModel):
    location: LocationOut
    kind: str
    run_id: str | None
    hours: list[HourlyOut]


class SyncRequest(BaseModel):
    job: Literal["current", "forecast", "observation", "backfill"]
    location_ids: list[int] | None = None
    start: date | None = Field(default=None, description="backfill only")
    end: date | None = Field(default=None, description="backfill only")


class AccuracyQuery(BaseModel):
    group_by: list[str] = []

    @field_validator("group_by")
    @classmethod
    def valid_groups(cls, v):
        bad = [g for g in v if g not in GROUP_KEYS]
        if bad:
            raise ValueError(f"invalid group_by {bad}; allowed: {list(GROUP_KEYS)}")
        return v
