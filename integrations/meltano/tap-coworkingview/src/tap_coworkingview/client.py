"""HTTP behaviour shared by the streams.

Mirrors the contract in ``spec/SPEC.md`` section 2: public API, no key,
``Accept: application/json``, a 20 second timeout, and a single retry on
``429`` or ``5xx`` after ``Retry-After`` (else ``RateLimit-Reset``, else 2
seconds, never more than 10).
"""

from __future__ import annotations

from collections.abc import Callable, Generator, Mapping
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any
from urllib.parse import urlparse

import backoff
import requests
from singer_sdk.exceptions import FatalAPIError, RetriableAPIError
from singer_sdk.streams import RESTStream

from tap_coworkingview import __version__

DEFAULT_API_URL = "https://api.coworkingview.com"
DEFAULT_CITY = "berlin"
DEFAULT_LOCALE = "en"
PAGE_SIZE = 50
#: Catalogue search ceiling. The same limit as the other clients in this repo.
MAX_SPACES = 200
REQUEST_TIMEOUT = 20
FALLBACK_WAIT = 2.0
MAX_WAIT = 10.0
USER_AGENT = (
    f"tap-coworkingview/{__version__} (+https://github.com/coworkingview/flex-office-data)"
)


def city_slug(config: Mapping[str, Any]) -> str:
    """City configured for this sync. Blank values fall back to Berlin."""
    city = config.get("city") or DEFAULT_CITY
    if not isinstance(city, str) or not city.strip():
        raise ValueError(f"city must be a non-empty string, got {city!r}.")
    return city.strip()


def api_root(config: Mapping[str, Any]) -> str:
    """API root, without a trailing slash."""
    raw = config.get("api_url") or DEFAULT_API_URL
    if not isinstance(raw, str) or not raw.strip():
        raise ValueError(f"api_url must be an http(s) URL, got {raw!r}.")
    url = raw.strip().rstrip("/")
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"api_url must be an http(s) URL, got {raw!r}.")
    return url


def _delay_seconds(value: str | None) -> float | None:
    """Parse a delay header: delta-seconds, or an HTTP date."""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return max(0.0, float(text))
    except ValueError:
        pass
    try:
        when = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max(0.0, (when - datetime.now(timezone.utc)).total_seconds())


def retry_wait_seconds(headers: Mapping[str, str]) -> float:
    """Seconds to wait before the single retry, capped at 10."""
    wait = _delay_seconds(headers.get("Retry-After"))
    if wait is None:
        wait = _delay_seconds(headers.get("RateLimit-Reset"))
    if wait is None:
        wait = FALLBACK_WAIT
    return min(wait, MAX_WAIT)


class CoworkingViewStream(RESTStream):
    """REST stream aimed at the public CoworkingView API."""

    records_jsonpath = "$.data[*]"
    _emitted = 0

    @property
    def url_base(self) -> str:
        """Configured API root."""
        return api_root(self.config)

    @property
    def http_headers(self) -> dict[str, str]:
        """Headers sent on every request. There is no API key."""
        return {"Accept": "application/json"}

    @property
    def user_agent(self) -> str:
        """Identify this tap on requests."""
        return USER_AGENT

    @property
    def timeout(self) -> int:
        """Per-request timeout in seconds."""
        return REQUEST_TIMEOUT

    def backoff_max_tries(self) -> int:
        """One retry, then give up. Two attempts in total."""
        return 2

    def backoff_jitter(self, value: float) -> float:
        """Keep the spec's wait. No extra jitter, and never above 10 seconds."""
        return min(max(value, 0.0), MAX_WAIT)

    def backoff_wait_generator(self) -> Generator[float, BaseException | None, None]:
        """Wait ``Retry-After``, else ``RateLimit-Reset``, else 2 seconds."""
        return self.backoff_runtime(value=self._retry_wait)

    def _retry_wait(self, exception: BaseException) -> float:
        response = getattr(exception, "response", None)
        headers = getattr(response, "headers", None) or {}
        return retry_wait_seconds(headers)

    def request_decorator(self, func: Callable) -> Callable:
        """Retry ``429`` and ``5xx`` once. Connection failures are not retried."""
        return backoff.on_exception(
            self.backoff_wait_generator,
            RetriableAPIError,
            max_tries=self.backoff_max_tries(),
            on_backoff=self.backoff_handler,
            jitter=self.backoff_jitter,
            logger=self.logger,
        )(func)

    def response_error_message(self, response: requests.Response) -> str:
        """Error text that includes the API's problem ``code`` when present."""
        message = super().response_error_message(response)
        try:
            body = response.json()
        except ValueError:
            return message
        if isinstance(body, dict) and isinstance(body.get("code"), str):
            return f"{message} (code={body['code']})"
        return message

    def _payload(self, response: requests.Response) -> dict[str, Any]:
        """Decoded JSON object, or a fatal error when the body is not one."""
        try:
            payload = response.json()
        except ValueError as err:
            raise FatalAPIError(
                f"The API returned a body that is not valid JSON for path: {self.path}"
            ) from err
        if not isinstance(payload, dict) or "data" not in payload:
            raise FatalAPIError(
                f"The API response has no 'data' member for path: {self.path}"
            )
        return payload
