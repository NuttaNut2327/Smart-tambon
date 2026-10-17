"""Providers planned but not implemented. They are registered so the API can
report them honestly; calling them always raises ProviderNotImplementedError."""

from app.providers.base import LocationLike, ProviderNotImplementedError, WeatherProvider


class _NotImplementedProvider(WeatherProvider):
    implemented = False
    note = ""

    def fetch_current(self, location: LocationLike):
        raise ProviderNotImplementedError(self.name, self.note)

    def fetch_forecast(self, location: LocationLike, days: int):
        raise ProviderNotImplementedError(self.name, self.note)

    def info(self) -> dict:
        return {**super().info(), "note": self.note}


class NasaGpmProvider(_NotImplementedProvider):
    name = "nasa_gpm_imerg"
    model = "imerg"
    description = "NASA GPM IMERG satellite precipitation estimate (SATELLITE_ESTIMATE)"
    note = "Requires NASA Earthdata credentials and HDF5/NetCDF ingestion; not implemented."


class HimawariProvider(_NotImplementedProvider):
    name = "jma_himawari"
    model = "himawari9"
    description = "JMA Himawari-9 geostationary satellite products (SATELLITE_ESTIMATE)"
    note = "Requires a satellite product feed (e.g. JAXA P-Tree account); not implemented."


class TmdProvider(_NotImplementedProvider):
    name = "tmd"
    model = "tmd_station"
    description = "Thai Meteorological Department station data (GROUND_STATION)"
    note = "Requires a TMD API key and station-to-location matching; not implemented."
