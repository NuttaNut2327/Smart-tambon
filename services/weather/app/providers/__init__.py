from functools import lru_cache

from app.config import get_settings
from app.providers.base import ObservationProvider, WeatherProvider
from app.providers.http import RetryingClient
from app.providers.open_meteo import OpenMeteoArchiveProvider, OpenMeteoForecastProvider
from app.providers.stubs import HimawariProvider, NasaGpmProvider, TmdProvider


def _client() -> RetryingClient:
    s = get_settings()
    return RetryingClient(
        timeout=s.http_timeout_seconds, max_attempts=s.http_max_attempts, backoff_base=s.http_backoff_base_seconds
    )


@lru_cache
def registry() -> dict[str, WeatherProvider]:
    client = _client()
    providers: list[WeatherProvider] = [
        OpenMeteoForecastProvider(
            name="open_meteo_ecmwf",
            model="ecmwf_ifs025",
            meta_id="ecmwf_ifs025",
            description="ECMWF IFS 0.25° open-data forecast via Open-Meteo",
            client=client,
        ),
        OpenMeteoForecastProvider(
            name="open_meteo_gfs",
            model="gfs_global",
            meta_id="ncep_gfs013",
            description="NCEP GFS global forecast via Open-Meteo",
            client=client,
        ),
        NasaGpmProvider(),
        HimawariProvider(),
        TmdProvider(),
    ]
    return {p.name: p for p in providers}


@lru_cache
def observation_provider() -> ObservationProvider:
    return OpenMeteoArchiveProvider(_client())


def get_provider(name: str) -> WeatherProvider:
    try:
        return registry()[name]
    except KeyError:
        raise KeyError(f"unknown provider '{name}'") from None


def primary_and_secondary() -> tuple[WeatherProvider, WeatherProvider | None]:
    s = get_settings()
    primary = get_provider(s.primary_provider)
    secondary = get_provider(s.secondary_provider) if s.secondary_provider else None
    return primary, secondary
