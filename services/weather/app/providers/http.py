import logging
import random
import time
from collections.abc import Callable

import httpx

from app.providers.base import ProviderError

log = logging.getLogger(__name__)

RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504}


class RetryingClient:
    """GET JSON with exponential backoff (base * 2^n + jitter). 4xx other than
    408/425/429 are permanent and raise immediately."""

    def __init__(
        self,
        *,
        timeout: float = 20.0,
        max_attempts: int = 4,
        backoff_base: float = 1.0,
        sleep: Callable[[float], None] = time.sleep,
        transport: httpx.BaseTransport | None = None,
    ):
        self.max_attempts = max_attempts
        self.backoff_base = backoff_base
        self.sleep = sleep
        self.client = httpx.Client(
            timeout=timeout,
            transport=transport,
            headers={"User-Agent": "smart-tambon-weather/1.0"},
        )

    def get_json(self, url: str, params: dict) -> tuple[dict, int]:
        last_error = "unknown error"
        for attempt in range(1, self.max_attempts + 1):
            try:
                resp = self.client.get(url, params=params)
            except httpx.HTTPError as exc:
                last_error = f"{type(exc).__name__}: {exc}"
            else:
                if resp.status_code == 200:
                    try:
                        body = resp.json()
                    except ValueError:
                        last_error = "invalid JSON in response"
                    else:
                        if isinstance(body, dict) and body.get("error"):
                            raise ProviderError(f"API error: {body.get('reason')}", attempts=attempt, retryable=False)
                        return body, attempt
                else:
                    reason = _reason(resp)
                    last_error = f"HTTP {resp.status_code}: {reason}"
                    if resp.status_code not in RETRYABLE_STATUS:
                        raise ProviderError(last_error, attempts=attempt, retryable=False)
            if attempt < self.max_attempts:
                delay = self.backoff_base * (2 ** (attempt - 1)) + random.uniform(0, self.backoff_base / 2)
                log.warning("provider request failed, retrying", extra={"url": url, "attempt": attempt,
                                                                       "error": last_error, "delay_s": round(delay, 2)})
                self.sleep(delay)
        raise ProviderError(f"gave up after {self.max_attempts} attempts: {last_error}", attempts=self.max_attempts)


def _reason(resp: httpx.Response) -> str:
    try:
        body = resp.json()
        if isinstance(body, dict) and body.get("reason"):
            return str(body["reason"])
    except ValueError:
        pass
    return resp.text[:200]
