"""GISTDA Disaster Open API (https://disaster.gistda.or.th/services/open-api).

Base URL https://api-gateway.gistda.or.th/api/2.0/resources; the key goes in the `API-Key` header
(no key -> HTTP 407, bad key -> 401). Verified against the published OpenAPI spec and live calls on 2026-10-23:
- features/flood/{1day,3days,7days,30days}  flood polygons, GeoJSON FeatureCollection (numberMatched, limit <= 10000, offset)
- features/viirs/{1day,3days,7days,30days}  VIIRS hotspot points, same paging; ct_tn defaults to Thailand
- maps/dri/7days/tms/{z}/{x}/{y}            drought risk (DRI+) PNG tiles, XYZ scheme (no vector features published)
- maps/flood/{period}/tms/{z}/{x}/{y}       flood PNG tiles
Responses echo the key in `links`/OnlineResource, so callers must only keep features and tile bytes.
"""

import logging
import time
from collections.abc import Callable

import httpx

from app.providers.base import ProviderError

log = logging.getLogger(__name__)

BASE_URL = "https://api-gateway.gistda.or.th/api/2.0/resources"
PERIODS = {1: "1day", 3: "3days", 7: "7days", 30: "30days"}
FEATURE_PATHS = {"flood": "features/flood", "hotspots": "features/viirs"}
TILE_PATHS = {"drought": "maps/dri/7days/tms", "flood": "maps/flood/{period}/tms"}
PAGE_SIZE = 10_000
RETRYABLE_STATUS = {429, 500, 502, 503, 504}


class GistdaKeyError(ProviderError):
    """GISTDA rejected the API key (401/403/407)."""


class GistdaApi:
    def __init__(self, *, timeout: float = 60.0, max_attempts: int = 2, transport: httpx.BaseTransport | None = None,
                 sleep: Callable[[float], None] = time.sleep):
        self.max_attempts = max_attempts
        self.sleep = sleep
        self.client = httpx.Client(timeout=timeout, transport=transport,
                                   headers={"User-Agent": "smart-tambon-weather/1.0"})

    def features_page(self, dataset: str, period_days: int, *, bbox: str, limit: int, offset: int,
                      api_key: str) -> dict:
        path = f"{FEATURE_PATHS[dataset]}/{PERIODS[period_days]}"
        resp = self._get(path, {"bbox": bbox, "limit": limit, "offset": offset}, api_key)
        if resp.status_code == 404:
            return {"type": "FeatureCollection", "features": [], "numberMatched": 0}
        try:
            body = resp.json()
        except ValueError as exc:
            raise ProviderError("GISTDA returned invalid JSON", retryable=False) from exc
        if not isinstance(body, dict) or body.get("type") != "FeatureCollection":
            raise ProviderError("GISTDA returned an unexpected payload", retryable=False)
        return body

    def tile(self, layer: str, period_days: int, z: int, x: int, y: int, *, api_key: str) -> tuple[bytes | None, str | None]:
        path = f"{TILE_PATHS[layer].format(period=PERIODS[period_days])}/{z}/{x}/{y}"
        resp = self._get(path, {}, api_key, accept="image/png")
        if resp.status_code in (204, 404):
            return None, None
        content_type = resp.headers.get("content-type", "")
        if not content_type.startswith("image/"):
            raise ProviderError(f"GISTDA tile returned {content_type or 'no content type'}", retryable=False)
        return resp.content, content_type.split(";")[0]

    def _get(self, path: str, params: dict, api_key: str, accept: str = "application/geo+json") -> httpx.Response:
        url = f"{BASE_URL}/{path}"
        last_error = "unknown error"
        for attempt in range(1, self.max_attempts + 1):
            try:
                resp = self.client.get(url, params=params, headers={"API-Key": api_key, "Accept": accept})
            except httpx.HTTPError as exc:
                last_error = type(exc).__name__
            else:
                if resp.status_code in (401, 403, 407):
                    raise GistdaKeyError(f"GISTDA rejected the API key (HTTP {resp.status_code})", attempts=attempt,
                                         retryable=False)
                if resp.status_code not in RETRYABLE_STATUS:
                    if resp.status_code not in (200, 204, 404):
                        raise ProviderError(f"GISTDA HTTP {resp.status_code}", attempts=attempt, retryable=False)
                    return resp
                last_error = f"HTTP {resp.status_code}"
            if attempt < self.max_attempts:
                # never log params/headers: the key travels in the header
                log.warning("gistda request failed, retrying", extra={"path": path, "attempt": attempt, "error": last_error})
                self.sleep(attempt)
        raise ProviderError(f"GISTDA unreachable after {self.max_attempts} attempts: {last_error}",
                            attempts=self.max_attempts)
