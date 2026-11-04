"""Price Index download and parsing for CoworkingView Rates.

The request behaviour follows the shared specification in ``spec/SPEC.md``:
one GET, JSON in, at most one retry on HTTP 429 or 5xx. Parsing follows
section 3 (one row per city and product) and the city fields of section 4.
"""

from __future__ import annotations

import json
import os
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable

from coworkingview_rates import USER_AGENT

DEFAULT_BASE_URL = "https://api.coworkingview.com"
ENV_BASE_URL = "COWORKINGVIEW_API_URL"
DEFAULT_TIMEOUT = 20.0
FALLBACK_WAIT = 2.0
MAX_WAIT = 10.0
LOW_CONFIDENCE_BELOW = 10

PRODUCT_ORDER = (
    "flex_desk",
    "fix_desk",
    "private_office",
    "exclusive_bereich",
    "day_pass",
    "meeting_room",
    "event_space",
    "virtual_office",
    "membership",
)
STAT_UNITS = {
    "day_pass": "day",
    "meeting_room": "hour",
    "event_space": "hour",
    "virtual_office": "month",
}

Sleep = Callable[[float], None]


class RatesError(Exception):
    """A download failed, or the body could not be read as a Price Index."""


@dataclass(frozen=True)
class Figure:
    """One published price statistic for a city."""

    product: str
    unit: str | None
    median: int | float | None
    p25: int | float | None
    p75: int | float | None
    sample_size: int
    property_count: int | None
    operator_count: int | None
    low_confidence: bool


@dataclass(frozen=True)
class City:
    """A city row from the Price Index, with its product figures."""

    slug: str
    name: str
    country_code: str | None
    currency: str | None
    published: bool
    property_count: int | None
    operator_count: int | None
    entry_median: int | float | None
    figures: tuple[Figure, ...]


@dataclass(frozen=True)
class PriceIndex:
    """A parsed ``GET /v1/market/rates`` data object."""

    cities: tuple[City, ...]
    as_of: str | None
    attribution: str | None
    license_url: str | None


def resolve_base_url(value: str | None = None) -> str:
    """API origin: the argument, else ``COWORKINGVIEW_API_URL``, else the public API."""
    raw = (value if value is not None else os.environ.get(ENV_BASE_URL) or DEFAULT_BASE_URL).strip()
    raw = raw.rstrip("/")
    parsed = urllib.parse.urlparse(raw)
    if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.username or parsed.password:
        raise RatesError("The API address must be an http or https origin without a username or password.")
    return raw


def _snake(key: str) -> str:
    out: list[str] = []
    for char in key:
        if char.isupper() and out:
            out.append("_")
        out.append(char.lower())
    return "".join(out)


def _amount(money: Any) -> int | float | None:
    if not isinstance(money, dict) or "amount" not in money:
        return None
    amount = money["amount"]
    if isinstance(amount, bool) or not isinstance(amount, (int, float)):
        return None
    return amount


def _count(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _text(value: Any) -> str | None:
    if isinstance(value, str) and value:
        return value
    return None


def _product_key(product: str) -> tuple[int, int, str]:
    if product in PRODUCT_ORDER:
        return (0, PRODUCT_ORDER.index(product), "")
    return (1, 0, product)


def _is_stat(value: Any) -> bool:
    return isinstance(value, dict) and "median" in value and "sampleSize" in value


def _figure(product: str, unit: str | None, item: dict[str, Any]) -> Figure | None:
    sample = _count(item.get("sampleSize"))
    median = _amount(item.get("median"))
    if sample is None or median is None:
        return None
    return Figure(
        product=product,
        unit=unit,
        median=median,
        p25=_amount(item.get("p25")),
        p75=_amount(item.get("p75")),
        sample_size=sample,
        property_count=_count(item.get("propertyCount")),
        operator_count=_count(item.get("operatorCount")),
        low_confidence=sample < LOW_CONFIDENCE_BELOW,
    )


def _city_figures(city: dict[str, Any]) -> tuple[Figure, ...]:
    figures: list[Figure] = []
    for item in city.get("figures") or city.get("byType") or []:
        if not isinstance(item, dict):
            continue
        product = item.get("optionType")
        if not isinstance(product, str):
            continue
        figure = _figure(product, "month", item)
        if figure is not None:
            figures.append(figure)
    for key, value in city.items():
        if not _is_stat(value):
            continue
        product = _snake(key)
        figure = _figure(product, STAT_UNITS.get(product), value)
        if figure is not None:
            figures.append(figure)
    figures.sort(key=lambda figure: _product_key(figure.product))
    return tuple(figures)


def _one_city(raw: Any, *, published: bool) -> City | None:
    if not isinstance(raw, dict):
        return None
    city = raw.get("city")
    if not isinstance(city, dict):
        return None
    slug = _text(city.get("slug"))
    name = _text(city.get("name"))
    if slug is None or name is None:
        return None
    return City(
        slug=slug,
        name=name,
        country_code=_text(raw.get("countryCode")),
        currency=_text(raw.get("currency")),
        published=published,
        property_count=_count(raw.get("propertyCount")) if published else None,
        operator_count=_count(raw.get("operatorCount")) if published else None,
        entry_median=_amount(raw.get("entryMedian")) if published else None,
        figures=_city_figures(raw) if published else (),
    )


def parse_index(data: dict[str, Any]) -> PriceIndex:
    """Build a :class:`PriceIndex` from the ``data`` object of a rates response."""
    if not isinstance(data, dict):
        raise RatesError("The Price Index response is not an object.")
    cities: list[City] = []
    for raw in data.get("cities") or []:
        city = _one_city(raw, published=True)
        if city is not None:
            cities.append(city)
    for raw in data.get("unpublished") or []:
        city = _one_city(raw, published=False)
        if city is not None:
            cities.append(city)
    cities.sort(key=lambda city: (not city.published, city.name.casefold(), city.slug))
    attribution = data.get("attribution")
    license_url = data.get("licenseUrl")
    as_of = data.get("asOf")
    return PriceIndex(
        cities=tuple(cities),
        as_of=as_of if isinstance(as_of, str) else None,
        attribution=attribution if isinstance(attribution, str) else None,
        license_url=license_url if isinstance(license_url, str) else None,
    )


def _wait_seconds(headers: Any) -> float:
    for name in ("Retry-After", "RateLimit-Reset"):
        raw = headers.get(name) if headers is not None else None
        if raw is None:
            continue
        text = str(raw).strip()
        try:
            return min(MAX_WAIT, max(0.0, float(text)))
        except ValueError:
            pass
        if name != "Retry-After":
            continue
        try:
            when = parsedate_to_datetime(text)
        except (TypeError, ValueError, IndexError):
            continue
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        return min(MAX_WAIT, max(0.0, (when - datetime.now(timezone.utc)).total_seconds()))
    return FALLBACK_WAIT


def _problem_message(status: int, reason: str, raw: bytes) -> str:
    detail = ""
    try:
        body = json.loads(raw.decode("utf-8")) if raw else None
    except (UnicodeDecodeError, ValueError):
        body = None
    if isinstance(body, dict):
        text = body.get("detail") if isinstance(body.get("detail"), str) else body.get("title")
        if isinstance(text, str) and text:
            detail = text
    if not detail:
        detail = reason or "the request was rejected"
    return f"The CoworkingView API returned HTTP {status}: {detail}"


def fetch_market(
    *,
    base_url: str | None = None,
    timeout: float = DEFAULT_TIMEOUT,
    sleep: Sleep = time.sleep,
) -> dict[str, Any]:
    """GET ``/v1/market/rates`` and return the ``data`` object.

    Retries once after HTTP 429 or 5xx. ``sleep`` is injectable so tests do
    not wait.
    """
    origin = resolve_base_url(base_url)
    url = origin + "/v1/market/rates?" + urllib.parse.urlencode({"locale": "en"})
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
        method="GET",
    )
    for attempt in (1, 2):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                status = response.status
                reason = response.reason or ""
                headers = response.headers
                raw = response.read()
        except urllib.error.HTTPError as err:
            try:
                raw = err.read()
            finally:
                err.close()
            status = err.code
            reason = str(err.reason or "")
            headers = err.headers
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as err:
            cause = getattr(err, "reason", err)
            raise RatesError(f"Could not reach the CoworkingView API ({origin}). {cause}") from err
        if 200 <= status <= 299:
            return _data_object(raw)
        if attempt == 1 and (status == 429 or 500 <= status <= 599):
            sleep(_wait_seconds(headers))
            continue
        raise RatesError(_problem_message(status, reason, raw))
    raise RatesError("The CoworkingView API did not return a Price Index.")


def _data_object(raw: bytes) -> dict[str, Any]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as err:
        raise RatesError("The CoworkingView API returned a body that is not valid JSON.") from err
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict):
        raise RatesError("The CoworkingView API response has no data object.")
    return payload["data"]


def cache_file(root: str | None = None) -> str:
    """Path of the last successful download."""
    base = root or os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "com.coworkingview.Rates", "market-rates.json")


def save_cache(data: dict[str, Any], path: str, saved_at: str | None = None) -> None:
    """Write ``data`` so a later launch can show it without a network."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    document = {
        "saved_at": saved_at or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "data": data,
    }
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False)
    os.replace(temporary, path)


def load_cache(path: str) -> tuple[PriceIndex, str] | None:
    """Return a saved index and its timestamp, or ``None`` when there is nothing usable."""
    try:
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, UnicodeError, ValueError):
        return None
    if not isinstance(document, dict) or not isinstance(document.get("data"), dict):
        return None
    saved_at = document.get("saved_at")
    try:
        return parse_index(document["data"]), saved_at if isinstance(saved_at, str) else ""
    except RatesError:
        return None


def format_amount(value: int | float | None, currency: str | None) -> str:
    """Render a price as ``1,800 EUR``. A missing amount is an em dash."""
    if value is None:
        return "—"
    if isinstance(value, float) and value.is_integer():
        number = f"{int(value):,}"
    elif isinstance(value, int):
        number = f"{value:,}"
    else:
        number = f"{value:,.2f}"
    if currency:
        return f"{number} {currency}"
    return number
