"""Provider interface. Providers only fetch and normalise; persistence lives in
app.services.ingestion so every provider gets the same idempotency rules."""

from __future__ import annotations

import abc
from dataclasses import dataclass, field
from datetime import date, datetime
from typing import Protocol


class ProviderError(Exception):
    """A provider could not deliver data (after its own retries)."""

    def __init__(self, message: str, *, attempts: int = 1, retryable: bool = True):
        super().__init__(message)
        self.attempts = attempts
        self.retryable = retryable


class ProviderNotImplementedError(ProviderError):
    def __init__(self, provider: str, note: str):
        super().__init__(f"provider '{provider}' is not implemented: {note}", attempts=0, retryable=False)


class LocationLike(Protocol):
    latitude: float
    longitude: float
    timezone: str


@dataclass
class CurrentData:
    provider: str
    model: str
    fetched_at: datetime
    observed_at: datetime
    interval_seconds: int | None
    values: dict
    unavailable_params: list[str] = field(default_factory=list)
    attempts: int = 1
    elevation_m: float | None = None


@dataclass
class ForecastData:
    provider: str
    model: str
    fetched_at: datetime
    run_id: str
    run_init_time: datetime | None
    run_id_source: str
    issue_date: date
    daily: list[dict]  # each has forecast_date + metric columns
    hourly: list[dict]  # each has valid_time (UTC) + metric columns
    unavailable_params: list[str] = field(default_factory=list)
    attempts: int = 1


@dataclass
class ObservationData:
    provider: str
    fetched_at: datetime
    daily: list[dict]  # forecast-free; each has observation_date, model, is_final, data_quality, source_type
    hourly: list[dict]
    unavailable_params: list[str] = field(default_factory=list)
    attempts: int = 1


class WeatherProvider(abc.ABC):
    """Forecast provider. `name` + `model` are the provenance stored on every row."""

    name: str
    model: str
    description: str = ""
    implemented: bool = True

    @abc.abstractmethod
    def fetch_current(self, location: LocationLike) -> CurrentData: ...

    @abc.abstractmethod
    def fetch_forecast(self, location: LocationLike, days: int) -> ForecastData: ...

    def info(self) -> dict:
        return {
            "name": self.name,
            "model": self.model,
            "description": self.description,
            "status": "available" if self.implemented else "not_implemented",
        }


class ObservationProvider(abc.ABC):
    name: str
    source_type: str

    @abc.abstractmethod
    def fetch_observations(self, location: LocationLike, start: date, end: date) -> ObservationData: ...
