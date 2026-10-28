"""ORM models. All timestamps are stored in UTC (timestamptz); calendar dates
(forecast_date / observation_date) are local dates in the location's timezone."""

from datetime import date, datetime

from geoalchemy2 import Geometry
from sqlalchemy import (
    BigInteger,
    Boolean,
    Date,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

SOURCE_TYPES = ("GROUND_STATION", "SATELLITE_ESTIMATE", "REANALYSIS", "MODEL_DERIVED")
DATA_QUALITY = ("PROVISIONAL", "FINAL", "SUSPECT")
HOURLY_KINDS = ("FORECAST", "OBSERVED")


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ProvenanceMixin:
    """Where a row came from. is_fallback marks rows fetched from the secondary
    provider because the primary failed; fallback_reason keeps the primary's error."""

    provider: Mapped[str] = mapped_column(String(64))
    model: Mapped[str] = mapped_column(String(64))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_fallback: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    fallback_reason: Mapped[str | None] = mapped_column(Text)
    # Parameters requested but not provided by this model (stored as NULL, never 0)
    unavailable_params: Mapped[list] = mapped_column(JSONB, default=list, server_default="[]")


class WeatherLocation(TimestampMixin, Base):
    __tablename__ = "weather_locations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    code: Mapped[str] = mapped_column(String(64), unique=True)
    name: Mapped[str] = mapped_column(String(255))
    name_th: Mapped[str | None] = mapped_column(String(255))
    province: Mapped[str | None] = mapped_column(String(128), index=True)
    district: Mapped[str | None] = mapped_column(String(128))
    subdistrict: Mapped[str | None] = mapped_column(String(128))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    geom = mapped_column(Geometry("POINT", srid=4326, spatial_index=False), nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Bangkok")
    elevation_m: Mapped[float | None] = mapped_column(Float)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")

    __table_args__ = (Index("ix_weather_locations_geom", "geom", postgresql_using="gist"),)

    current = relationship("WeatherCurrent", back_populates="location", cascade="all, delete-orphan")


class WeatherCurrent(ProvenanceMixin, Base):
    """Latest model-derived conditions, one row per provider/model/valid time."""

    __tablename__ = "weather_current"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("weather_locations.id", ondelete="CASCADE"), index=True)
    observed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    interval_seconds: Mapped[int | None] = mapped_column(Integer)
    temperature_c: Mapped[float | None] = mapped_column(Float)
    apparent_temperature_c: Mapped[float | None] = mapped_column(Float)
    relative_humidity_pct: Mapped[float | None] = mapped_column(Float)
    dew_point_c: Mapped[float | None] = mapped_column(Float)
    precipitation_mm: Mapped[float | None] = mapped_column(Float)
    rain_mm: Mapped[float | None] = mapped_column(Float)
    weather_code: Mapped[int | None] = mapped_column(Integer)
    cloud_cover_pct: Mapped[float | None] = mapped_column(Float)
    pressure_msl_hpa: Mapped[float | None] = mapped_column(Float)
    surface_pressure_hpa: Mapped[float | None] = mapped_column(Float)
    wind_speed_kmh: Mapped[float | None] = mapped_column(Float)
    wind_direction_deg: Mapped[float | None] = mapped_column(Float)
    wind_gusts_kmh: Mapped[float | None] = mapped_column(Float)
    visibility_m: Mapped[float | None] = mapped_column(Float)
    uv_index: Mapped[float | None] = mapped_column(Float)
    is_day: Mapped[bool | None] = mapped_column(Boolean)

    location = relationship("WeatherLocation", back_populates="current")

    __table_args__ = (
        UniqueConstraint("location_id", "provider", "model", "observed_at", name="uq_weather_current_obs"),
        Index("ix_weather_current_loc_time", "location_id", "observed_at"),
    )


class WeatherDailyForecast(ProvenanceMixin, Base):
    """Append-only archive: every forecast run is kept; rows are never updated."""

    __tablename__ = "weather_daily_forecast"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("weather_locations.id", ondelete="CASCADE"))
    run_id: Mapped[str] = mapped_column(String(128))
    run_init_time: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    run_id_source: Mapped[str] = mapped_column(String(32))  # model_metadata | fetch_time_bucket
    issue_date: Mapped[date] = mapped_column(Date)  # local date the forecast was issued
    forecast_date: Mapped[date] = mapped_column(Date)  # local calendar date
    forecast_lead_days: Mapped[int] = mapped_column(Integer)

    weather_code: Mapped[int | None] = mapped_column(Integer)
    temperature_max_c: Mapped[float | None] = mapped_column(Float)
    temperature_min_c: Mapped[float | None] = mapped_column(Float)
    apparent_temperature_max_c: Mapped[float | None] = mapped_column(Float)
    apparent_temperature_min_c: Mapped[float | None] = mapped_column(Float)
    precipitation_sum_mm: Mapped[float | None] = mapped_column(Float)
    rain_sum_mm: Mapped[float | None] = mapped_column(Float)
    precipitation_hours: Mapped[float | None] = mapped_column(Float)
    precipitation_probability_max_pct: Mapped[float | None] = mapped_column(Float)
    wind_speed_max_kmh: Mapped[float | None] = mapped_column(Float)
    wind_gusts_max_kmh: Mapped[float | None] = mapped_column(Float)
    wind_direction_dominant_deg: Mapped[float | None] = mapped_column(Float)
    relative_humidity_mean_pct: Mapped[float | None] = mapped_column(Float)
    cloud_cover_mean_pct: Mapped[float | None] = mapped_column(Float)
    shortwave_radiation_sum_mj_m2: Mapped[float | None] = mapped_column(Float)
    et0_mm: Mapped[float | None] = mapped_column(Float)
    uv_index_max: Mapped[float | None] = mapped_column(Float)
    sunrise: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    sunset: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    daylight_duration_s: Mapped[float | None] = mapped_column(Float)

    __table_args__ = (
        UniqueConstraint(
            "provider", "model", "run_id", "location_id", "forecast_date", name="uq_weather_daily_forecast_run"
        ),
        Index("ix_weather_daily_forecast_lookup", "location_id", "forecast_date", "fetched_at"),
        Index("ix_weather_daily_forecast_lead", "forecast_lead_days"),
    )


class WeatherDailyObservation(TimestampMixin, Base):
    """Best-available observed/estimated daily values. Revisable until is_final;
    each change appends to weather_daily_observation_revisions."""

    __tablename__ = "weather_daily_observation"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("weather_locations.id", ondelete="CASCADE"))
    observation_date: Mapped[date] = mapped_column(Date)
    source_type: Mapped[str] = mapped_column(String(32))  # see SOURCE_TYPES
    source_name: Mapped[str] = mapped_column(String(64))  # e.g. open_meteo_archive
    model: Mapped[str | None] = mapped_column(String(64))  # e.g. era5, best_match
    data_quality: Mapped[str] = mapped_column(String(16))  # see DATA_QUALITY
    is_final: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    revision: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    finalized_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    unavailable_params: Mapped[list] = mapped_column(JSONB, default=list, server_default="[]")

    weather_code: Mapped[int | None] = mapped_column(Integer)
    temperature_max_c: Mapped[float | None] = mapped_column(Float)
    temperature_min_c: Mapped[float | None] = mapped_column(Float)
    temperature_mean_c: Mapped[float | None] = mapped_column(Float)
    precipitation_sum_mm: Mapped[float | None] = mapped_column(Float)
    rain_sum_mm: Mapped[float | None] = mapped_column(Float)
    precipitation_hours: Mapped[float | None] = mapped_column(Float)
    wind_speed_max_kmh: Mapped[float | None] = mapped_column(Float)
    wind_gusts_max_kmh: Mapped[float | None] = mapped_column(Float)
    wind_direction_dominant_deg: Mapped[float | None] = mapped_column(Float)
    relative_humidity_mean_pct: Mapped[float | None] = mapped_column(Float)
    shortwave_radiation_sum_mj_m2: Mapped[float | None] = mapped_column(Float)
    et0_mm: Mapped[float | None] = mapped_column(Float)

    __table_args__ = (
        UniqueConstraint(
            "location_id", "observation_date", "source_type", "source_name", name="uq_weather_daily_observation"
        ),
        Index("ix_weather_daily_observation_lookup", "location_id", "observation_date"),
    )


class WeatherDailyObservationRevision(Base):
    __tablename__ = "weather_daily_observation_revisions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    observation_id: Mapped[int] = mapped_column(
        ForeignKey("weather_daily_observation.id", ondelete="CASCADE"), index=True
    )
    revision: Mapped[int] = mapped_column(Integer)
    data_quality: Mapped[str] = mapped_column(String(16))
    is_final: Mapped[bool] = mapped_column(Boolean)
    model: Mapped[str | None] = mapped_column(String(64))
    values: Mapped[dict] = mapped_column(JSONB)  # the superseded metric values
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    superseded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WeatherHourly(Base):
    __tablename__ = "weather_hourly"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    location_id: Mapped[int] = mapped_column(ForeignKey("weather_locations.id", ondelete="CASCADE"))
    data_kind: Mapped[str] = mapped_column(String(16))  # FORECAST | OBSERVED
    provider: Mapped[str] = mapped_column(String(64))
    model: Mapped[str] = mapped_column(String(64))
    # Forecast rows carry their run id; observed rows use the literal "observed"
    run_id: Mapped[str] = mapped_column(String(128))
    valid_time: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    is_fallback: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    source_type: Mapped[str | None] = mapped_column(String(32))

    temperature_c: Mapped[float | None] = mapped_column(Float)
    apparent_temperature_c: Mapped[float | None] = mapped_column(Float)
    relative_humidity_pct: Mapped[float | None] = mapped_column(Float)
    dew_point_c: Mapped[float | None] = mapped_column(Float)
    precipitation_mm: Mapped[float | None] = mapped_column(Float)
    precipitation_probability_pct: Mapped[float | None] = mapped_column(Float)
    weather_code: Mapped[int | None] = mapped_column(Integer)
    cloud_cover_pct: Mapped[float | None] = mapped_column(Float)
    pressure_msl_hpa: Mapped[float | None] = mapped_column(Float)
    wind_speed_kmh: Mapped[float | None] = mapped_column(Float)
    wind_direction_deg: Mapped[float | None] = mapped_column(Float)
    wind_gusts_kmh: Mapped[float | None] = mapped_column(Float)
    visibility_m: Mapped[float | None] = mapped_column(Float)
    uv_index: Mapped[float | None] = mapped_column(Float)
    is_day: Mapped[bool | None] = mapped_column(Boolean)

    __table_args__ = (
        UniqueConstraint(
            "location_id", "data_kind", "provider", "model", "run_id", "valid_time", name="uq_weather_hourly"
        ),
        Index("ix_weather_hourly_lookup", "location_id", "data_kind", "valid_time"),
    )


class WeatherIngestionLog(Base):
    __tablename__ = "weather_ingestion_logs"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    job_type: Mapped[str] = mapped_column(String(32), index=True)
    status: Mapped[str] = mapped_column(String(16))  # SUCCESS | FALLBACK | FAILED | SKIPPED
    provider: Mapped[str | None] = mapped_column(String(64))
    model: Mapped[str | None] = mapped_column(String(64))
    location_id: Mapped[int | None] = mapped_column(ForeignKey("weather_locations.id", ondelete="SET NULL"))
    run_id: Mapped[str | None] = mapped_column(String(128))
    is_fallback: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    records_inserted: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    records_skipped: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    finished_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    duration_ms: Mapped[int | None] = mapped_column(Integer)
    error: Mapped[str | None] = mapped_column(Text)
    details: Mapped[dict] = mapped_column(JSONB, default=dict, server_default="{}")

    __table_args__ = (Index("ix_weather_ingestion_logs_started", "started_at"),)


class GistdaFetch(Base):
    """One cached GISTDA Disaster API query (dataset + period + bbox). Its features are kept until a newer
    fetch of the same query replaces them; the cache is shared because the data is the same for every API key."""

    __tablename__ = "gistda_fetches"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    dataset: Mapped[str] = mapped_column(String(32))  # flood | hotspots
    period_days: Mapped[int] = mapped_column(Integer)
    bbox_key: Mapped[str] = mapped_column(String(96))
    bbox = mapped_column(Geometry(geometry_type="POLYGON", srid=4326, spatial_index=False), nullable=False)
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    number_matched: Mapped[int | None] = mapped_column(Integer)
    number_stored: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    truncated: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    # GISTDA's own response timeStamp (when the upstream answered), kept as sent
    data_timestamp: Mapped[str | None] = mapped_column(String(40))

    features: Mapped[list["GistdaFeature"]] = relationship(back_populates="fetch", cascade="all, delete-orphan",
                                                          passive_deletes=True)

    __table_args__ = (Index("ix_gistda_fetches_lookup", "dataset", "period_days", "bbox_key", "fetched_at"),)


class GistdaFeature(Base):
    __tablename__ = "gistda_features"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    fetch_id: Mapped[int] = mapped_column(ForeignKey("gistda_fetches.id", ondelete="CASCADE"), index=True)
    feature_id: Mapped[str | None] = mapped_column(String(64))
    geom = mapped_column(Geometry(geometry_type="GEOMETRY", srid=4326, spatial_index=False), nullable=False)
    # Whitelisted upstream properties only; missing values are NULL
    properties: Mapped[dict] = mapped_column(JSONB, default=dict, server_default="{}")

    fetch: Mapped[GistdaFetch] = relationship(back_populates="features")

    __table_args__ = (Index("ix_gistda_features_geom", "geom", postgresql_using="gist"),)


class GistdaTile(Base):
    """Cached GISTDA map tile (PNG). content NULL means GISTDA had no tile there."""

    __tablename__ = "gistda_tiles"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    layer: Mapped[str] = mapped_column(String(32))
    period_days: Mapped[int] = mapped_column(Integer)
    z: Mapped[int] = mapped_column(Integer)
    x: Mapped[int] = mapped_column(Integer)
    y: Mapped[int] = mapped_column(Integer)
    content: Mapped[bytes | None] = mapped_column(LargeBinary)
    content_type: Mapped[str | None] = mapped_column(String(64))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)

    __table_args__ = (UniqueConstraint("layer", "period_days", "z", "x", "y", name="uq_gistda_tiles"),)
