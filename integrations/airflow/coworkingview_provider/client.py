"""HTTP client for ``GET /v1/market/rates``.

The public API root is ``https://api.coworkingview.com``. There is no API
key. Behaviour matches ``spec/SPEC.md`` section 2: ``Accept: application/json``,
a 20 second timeout, and one retry on HTTP 429 or 5xx. The wait is
``Retry-After``, else ``RateLimit-Reset``, else 2 seconds, and never more
than 10 seconds.

No other path is requested. Catalogue search (``GET /v1/properties``) is out
of scope for this provider.
"""

from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Mapping
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any

from coworkingview_provider._version import __version__
from coworkingview_provider.exceptions import CoworkingViewApiError, CoworkingViewError
from coworkingview_provider.parse import (
    CURRENCIES,
    LOCALES,
    PRODUCT_ORDER,
    city_rates_document,
)

DEFAULT_BASE_URL = "https://api.coworkingview.com"
DEFAULT_TIMEOUT = 20.0
ENV_BASE_URL = "COWORKINGVIEW_API_URL"
RATES_PATH = "/v1/market/rates"
FALLBACK_WAIT = 2.0
MAX_WAIT = 10.0
USER_AGENT = (
    f"airflow-provider-coworkingview/{__version__} "
    "(+https://github.com/coworkingview/flex-office-data)"
)

logger = logging.getLogger(__name__)


def _choices(values: tuple[str, ...]) -> str:
    return ", ".join(repr(value) for value in values)


def require_city(value: object) -> str:
    """City slug sent as the ``city`` query parameter."""
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"city must be a non-empty string, got {value!r}.")
    return value.strip()


def optional_text(name: str, value: object) -> str | None:
    """Optional free-text query parameter. ``None`` is omitted from the request."""
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string, got {value!r}.")
    return value.strip()


def require_locale(value: object) -> str:
    """``locale`` query parameter. The API rejects a call that omits it."""
    if not isinstance(value, str) or value not in LOCALES:
        raise ValueError(f"locale={value!r} is not supported; use one of {_choices(LOCALES)}.")
    return value


def optional_currency(value: object) -> str | None:
    """``currency`` query parameter, upper-cased. ``None`` keeps the city's currency."""
    if value is None:
        return None
    normalised = value.upper() if isinstance(value, str) else value
    if not isinstance(normalised, str) or normalised not in CURRENCIES:
        raise ValueError(f"currency={value!r} is not supported; use one of {_choices(CURRENCIES)}.")
    return normalised


def optional_product(value: object) -> str | None:
    """Product filter applied to the response. The rates endpoint has no product query."""
    if value is None:
        return None
    if not isinstance(value, str) or value not in PRODUCT_ORDER:
        raise ValueError(
            f"product={value!r} is not supported; use one of {_choices(PRODUCT_ORDER)}."
        )
    return value


def normalize_base_url(value: str) -> str:
    """API root, with no path, query, fragment, or embedded userinfo.

    A host without a scheme is treated as ``https``.
    """
    if not isinstance(value, str) or not value.strip():
        raise CoworkingViewError(f"API base URL must be an http(s) URL, got {value!r}.")
    raw = value.strip()
    if "://" not in raw:
        raw = "https://" + raw
    parsed = urllib.parse.urlparse(raw)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise CoworkingViewError(f"API base URL must be an http(s) URL, got {value!r}.")
    if parsed.username or parsed.password:
        raise CoworkingViewError("API base URL must not include a username or password.")
    if parsed.query or parsed.fragment:
        raise CoworkingViewError("API base URL must not include a query string or fragment.")
    if parsed.path not in {"", "/"}:
        raise CoworkingViewError(
            "API base URL must be the API root "
            "(for example https://api.coworkingview.com), not a path."
        )
    return raw.rstrip("/")


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


def _header(headers: Mapping[str, str] | None, name: str) -> str | None:
    if not headers:
        return None
    direct = headers.get(name)
    if direct is not None:
        return direct
    lowered = name.lower()
    for key, value in headers.items():
        if key.lower() == lowered:
            return value
    return None


def retry_wait_seconds(headers: Mapping[str, str] | None) -> float:
    """Seconds to wait before the single retry, capped at 10."""
    wait = _delay_seconds(_header(headers, "Retry-After"))
    if wait is None:
        wait = _delay_seconds(_header(headers, "RateLimit-Reset"))
    if wait is None:
        wait = FALLBACK_WAIT
    return min(wait, MAX_WAIT)


def _is_retryable(status: int) -> bool:
    return status == 429 or 500 <= status <= 599


def _problem(status: int, reason: str, raw: bytes) -> CoworkingViewApiError:
    body: Any = None
    try:
        body = json.loads(raw.decode("utf-8")) if raw else None
    except (UnicodeDecodeError, ValueError):
        body = None
    if not isinstance(body, dict):
        body = {}
    title = body.get("title")
    detail = body.get("detail")
    code = body.get("code")
    return CoworkingViewApiError(
        status=status,
        code=code if isinstance(code, str) and code else f"HTTP_{status}",
        title=title if isinstance(title, str) and title else (reason or f"HTTP {status}"),
        detail=detail if isinstance(detail, str) else None,
    )


class CoworkingViewClient:
    """GET the Price Index and return one city's rates as a JSON document."""

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        timeout: float = DEFAULT_TIMEOUT,
        logger: logging.Logger | None = None,
    ) -> None:
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError(f"timeout must be a positive number of seconds, got {timeout!r}.")
        self.base_url = normalize_base_url(base_url)
        self.timeout = float(timeout)
        self._log = logger or logging.getLogger(__name__)
        self._sleep = time.sleep

    def _url(self, params: Mapping[str, Any]) -> str:
        query = {key: value for key, value in params.items() if value is not None}
        url = f"{self.base_url}{RATES_PATH}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        return url

    def _fetch(self, url: str) -> tuple[int, str, Mapping[str, str], bytes]:
        # The base URL was checked in normalize_base_url. Refuse anything else
        # again here so a later change cannot hand urlopen a file: URL.
        if urllib.parse.urlparse(url).scheme not in {"http", "https"}:
            raise CoworkingViewError(f"Refusing non-HTTP URL {url!r}.")
        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "User-Agent": USER_AGENT},
            method="GET",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                status = getattr(response, "status", None) or response.getcode()
                reason = getattr(response, "reason", "") or ""
                return int(status), str(reason), response.headers, response.read()
        except urllib.error.HTTPError as err:
            raw = err.read()
            return err.code, str(err.reason or ""), err.headers, raw
        except (urllib.error.URLError, TimeoutError, OSError) as err:
            reason = getattr(err, "reason", err)
            raise CoworkingViewError(
                f"Could not reach the CoworkingView API at {self.base_url}: {reason}"
            ) from err

    def get_rates_payload(self, params: Mapping[str, Any]) -> dict[str, Any]:
        """GET ``/v1/market/rates`` and return the JSON object.

        Retries once on 429 or 5xx. Any other non-2xx becomes
        :class:`CoworkingViewApiError`.
        """
        url = self._url(params)
        for attempt in (1, 2):
            status, reason, headers, raw = self._fetch(url)
            if 200 <= status <= 299:
                return self._decode(status, reason, raw)
            if attempt == 1 and _is_retryable(status):
                wait = retry_wait_seconds(headers)
                self._log.info(
                    "CoworkingView HTTP %s from %s; retrying once after %.1fs.",
                    status,
                    RATES_PATH,
                    wait,
                )
                self._sleep(wait)
                continue
            raise _problem(status, reason, raw)
        raise AssertionError("unreachable")  # pragma: no cover

    def _decode(self, status: int, reason: str, raw: bytes) -> dict[str, Any]:
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as err:
            raise CoworkingViewApiError(
                status,
                "BAD_RESPONSE",
                "The API returned a body that is not valid JSON",
                f"HTTP {status} {reason}".strip(),
            ) from err
        if not isinstance(payload, dict):
            raise CoworkingViewApiError(
                status,
                "BAD_RESPONSE",
                "The API returned JSON that is not an object",
                f"GET {RATES_PATH}",
            )
        return payload

    def city_rates(
        self,
        *,
        city: str,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
        product: str | None = None,
    ) -> dict[str, Any]:
        """Price Index for one city.

        Arguments are checked before any request is sent. ``product`` filters
        the rows after the response arrives; the rates endpoint does not
        accept a product parameter.
        """
        city = require_city(city)
        locale = require_locale(locale)
        params = {
            "locale": locale,
            "city": city,
            "country": optional_text("country", country),
            "currency": optional_currency(currency),
        }
        product = optional_product(product)
        payload = self.get_rates_payload(params)
        return city_rates_document(payload, city=city, locale=locale, product=product)
