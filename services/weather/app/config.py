from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://weather:weather@localhost:5442/weather"
    admin_api_key: str = Field(default="", alias="WEATHER_ADMIN_API_KEY")

    primary_provider: str = Field(default="open_meteo_ecmwf", alias="WEATHER_PRIMARY_PROVIDER")
    secondary_provider: str = Field(default="open_meteo_gfs", alias="WEATHER_SECONDARY_PROVIDER")
    # today + 7 days ahead, so lead days 1..7 are all archived for accuracy scoring
    forecast_days: int = Field(default=8, ge=1, le=16, alias="WEATHER_FORECAST_DAYS")
    default_timezone: str = Field(default="Asia/Bangkok", alias="WEATHER_DEFAULT_TIMEZONE")
    initial_sync: bool = Field(default=True, alias="WEATHER_INITIAL_SYNC")

    http_timeout_seconds: float = 20.0
    http_max_attempts: int = 4
    http_backoff_base_seconds: float = 1.0

    # Observation finalization: days back that are re-checked until is_final
    observation_lookback_days: int = 10

    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
