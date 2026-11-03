"""HTTP transport for ``GET /v1/market/rates``.

Behaviour matches ``spec/SPEC.md`` section 2. No other path is requested.
Nothing is fetched when a :class:`Client` is constructed.
"""

from __future__ import annotations

import json
import os
import re
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from datetime import datetime, timezone
from email.message import Message
from email.utils import parsedate_to_datetime
from typing import Any

from ._parse import MarketRates, parse_market_rates
from ._version import __version__
from .exceptions import APIError, CoworkingViewError

DEFAULT_BASE_URL = "https://api.coworkingview.com"
ENV_BASE_URL = "COWORKINGVIEW_API_URL"
RATES_PATH = "/v1/market/rates"
DEFAULT_TIMEOUT = 20.0
FALLBACK_WAIT = 2.0
MAX_WAIT = 10.0
USER_AGENT = f"mpl-coworkingview/{__version__} (+https://github.com/coworkingview/flex-office-data)"

LOCALES: tuple[str, ...] = ("en", "es", "de")
#: ``VES`` is accepted by the API and rejected with HTTP 400 where it has no
#: conversion rate. Pass it through; do not hide that response.
CURRENCIES: tuple[str, ...] = ("EUR", "GBP", "USD", "CHF", "AED", "VES")
_SLUG = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _choices(values: tuple[str, ...]) -> str:
    return ", ".join(repr(value) for value in values)


def require_locale(value: object) -> str:
    """``locale`` query parameter. The API rejects a call that omits it."""
    if not isinstance(value, str) or value not in LOCALES:
        raise ValueError(f"locale={value!r} is not supported; use one of {_choices(LOCALES)}.")
    return value


def require_city(value: object) -> str:
    """City slug sent as the ``city`` query parameter."""
    if not isinstance(value, str) or _SLUG.fullmatch(value) is None:
        raise ValueError(f"city must be a slug matching {_SLUG.pattern}, got {value!r}.")
    return value


def optional_country(value: object) -> str | None:
    """``country`` query parameter. ``None`` is omitted.

    The parameter name is ``country``. Checked against the live API on
    2026-11-03, the value must match ``^[a-z0-9-]+$`` (``DE`` is rejected,
    ``de`` is accepted). This client does not rewrite the string.
    """
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"country must be a non-empty string, got {value!r}.")
    return value.strip()


def optional_currency(value: object) -> str | None:
    """``currency`` query parameter, upper-cased. ``None`` keeps each city's currency."""
    if value is None:
        return None
    normalised = value.upper() if isinstance(value, str) else value
    if not isinstance(normalised, str) or normalised not in CURRENCIES:
        raise ValueError(f"currency={value!r} is not supported; use one of {_choices(CURRENCIES)}.")
    return normalised


def prepare_market_query(
    *,
    city: str | None = None,
    country: str | None = None,
    currency: str | None = None,
    locale: str = "en",
) -> dict[str, str]:
    """Query string for ``GET /v1/market/rates``, with absent filters omitted.

    Keys are the API's names: ``locale``, ``city``, ``country``, ``currency``.
    ``locale`` is always sent.
    """
    params = {"locale": require_locale(locale)}
    if city is not None:
        params["city"] = require_city(city)
    country_value = optional_country(country)
    if country_value is not None:
        params["country"] = country_value
    currency_value = optional_currency(currency)
    if currency_value is not None:
        params["currency"] = currency_value
    return params


def normalize_base_url(value: str) -> str:
    """API root, with no path, query, fragment, or embedded userinfo."""
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


def _seconds(value: str | None, *, now: datetime | None = None) -> float | None:
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
    current = now or datetime.now(timezone.utc)
    return max(0.0, (when - current).total_seconds())


def retry_wait(headers: Message | Mapping[str, str]) -> float:
    """Seconds to wait before the single retry, capped at 10.

    The wait is ``Retry-After``, else ``RateLimit-Reset``, else 2 seconds.
    """
    wait = _seconds(headers.get("Retry-After"))
    if wait is None:
        wait = _seconds(headers.get("RateLimit-Reset"))
    if wait is None:
        wait = FALLBACK_WAIT
    return min(wait, MAX_WAIT)


def _is_retryable(status: int) -> bool:
    return status == 429 or 500 <= status <= 599


def _decode(raw: bytes, status: int, reason: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise APIError(
            status,
            "BAD_RESPONSE",
            "The API returned a body that is not valid JSON",
            f"HTTP {status} {reason}".strip(),
        ) from None


def _problem(status: int, reason: str, raw: bytes) -> APIError:
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
    errors = body.get("errors")
    return APIError(
        status=status,
        code=code if isinstance(code, str) and code else f"HTTP_{status}",
        title=title if isinstance(title, str) and title else (reason or f"HTTP {status}"),
        detail=detail if isinstance(detail, str) else None,
        errors=(
            [item for item in errors if isinstance(item, dict)]
            if isinstance(errors, list)
            else None
        ),
    )


class Client:
    """GET ``/v1/market/rates`` and parse the Price Index.

    Parameters
    ----------
    base_url : str, optional
        API root. Defaults to ``COWORKINGVIEW_API_URL`` or
        ``https://api.coworkingview.com``.
    timeout : float, default 20
        Socket timeout in seconds.
    opener : optional
        Object with ``open(request, timeout=...)``, used in tests. The
        default is :func:`urllib.request.build_opener`.
    sleep : callable, optional
        Used for the single retry wait. Tests pass a recorder.
    """

    def __init__(
        self,
        base_url: str | None = None,
        *,
        timeout: float = DEFAULT_TIMEOUT,
        opener: Any = None,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if base_url is None:
            base_url = os.environ.get(ENV_BASE_URL, DEFAULT_BASE_URL)
        self.base_url = normalize_base_url(base_url)
        self.timeout = timeout
        self._opener = opener if opener is not None else urllib.request.build_opener()
        self._sleep = sleep

    def market_rates(
        self,
        *,
        city: str | None = None,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
    ) -> MarketRates:
        """Fetch and parse ``GET /v1/market/rates``."""
        params = prepare_market_query(city=city, country=country, currency=currency, locale=locale)
        return parse_market_rates(self._get(params))

    def _url(self, params: Mapping[str, str]) -> str:
        return f"{self.base_url}{RATES_PATH}?{urllib.parse.urlencode(params)}"

    def _get(self, params: Mapping[str, str]) -> dict[str, Any]:
        url = self._url(params)
        for attempt in (1, 2):
            status, reason, headers, raw = self._fetch(url)
            if 200 <= status <= 299:
                payload = _decode(raw, status, reason)
                if not isinstance(payload, dict):
                    raise APIError(
                        status,
                        "BAD_RESPONSE",
                        "The API returned JSON that is not an object",
                        f"GET {RATES_PATH}",
                    )
                return payload
            if attempt == 1 and _is_retryable(status):
                self._sleep(retry_wait(headers))
                continue
            raise _problem(status, reason, raw)
        raise AssertionError("unreachable")  # pragma: no cover

    def _fetch(self, url: str) -> tuple[int, str, Message, bytes]:
        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "User-Agent": USER_AGENT},
            method="GET",
        )
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                return response.status, response.reason or "", response.headers, response.read()
        except urllib.error.HTTPError as err:
            try:
                raw = err.read()
            finally:
                err.close()
            return err.code, str(err.reason or ""), err.headers, raw
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as err:
            reason = getattr(err, "reason", err)
            raise CoworkingViewError(f"Could not reach {self.base_url}: {reason}") from err
