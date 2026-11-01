"""CoworkingView data for the Calc add-in.

Talks to the public API with the standard library only. Field names below
were checked against live responses on 2026-11-01:

* ``GET /v1/market/rates?locale=en&city=berlin`` returns ``data.cities[]``
  with ``currency``, ``figures[]`` (``optionType``, ``median``, ``p25``,
  ``p75``, ``sampleSize``), ``byType[]`` (``optionType``, ``median``,
  ``min``, ``max``, ``sampleSize``), ``dayPass`` and ``meetingRoom``
  (each ``median`` and ``sampleSize``), plus top-level ``asOf`` and
  ``attribution``.
* ``GET /v1/properties?locale=en&city=berlin&page=1&pageSize=1`` returns
  ``meta.pagination.total`` (the catalogue size). That number is not the
  price index ``propertyCount``.

Nothing is requested when this module is imported.
"""

from __future__ import annotations

import json
import math
import os
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Callable, Mapping, Sequence

VERSION = "0.1.0"
IDENTIFIER = "com.coworkingview.calc"
SOURCE = "Data: CoworkingView https://coworkingview.com"
DEFAULT_CITY = "berlin"
DEFAULT_BASE_URL = "https://api.coworkingview.com"
USER_AGENT = (
    "coworkingview-calc/"
    + VERSION
    + " (+https://github.com/coworkingview/flex-office-data)"
)
LOCALE = "en"
TIMEOUT_SECONDS = 20.0
DEFAULT_CACHE_SECONDS = 600.0
MAX_RESPONSE_BYTES = 2_000_000
MAX_RETRY_WAIT = 10.0
FALLBACK_RETRY_WAIT = 2.0

# Sort products that are actually present. This does not add products.
_PRODUCT_ORDER = (
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
_STATS = ("median", "min", "max", "p25", "p75")
_STAT_SET = frozenset(_STATS)

_CITY_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
_PRODUCT_RE = re.compile(r"^[a-z][a-z0-9_]*$")
_MAX_AGE_RE = re.compile(r"max-age=(\d+)")

FUNCTIONS = (
    (
        "CWV_SPACES",
        {
            "description": (
                "Number of coworking workspace listings published for a city."
            ),
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
            ),
        },
    ),
    (
        "CWV_PRICE",
        {
            "description": (
                "Median market rate for one product in a city. "
                "The amount is in that city's currency."
            ),
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
                (
                    "Product",
                    ("Product code, for example flex_desk, fix_desk, "
                    "private_office, day_pass, or meeting_room."),
                ),
            ),
        },
    ),
    (
        "CWV_RATE",
        {
            "description": (
                "One published price statistic for a product: "
                "median, min, max, p25, or p75."
            ),
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
                (
                    "Product",
                    "Product code, for example flex_desk or day_pass.",
                ),
                (
                    "Stat",
                    "One of median, min, max, p25, p75.",
                ),
            ),
        },
    ),
    (
        "CWV_CURRENCY",
        {
            "description": (
                "ISO currency code of the city price index, for example EUR."
            ),
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
            ),
        },
    ),
    (
        "CWV_SAMPLE",
        {
            "description": "Number of price observations behind that product.",
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
                (
                    "Product",
                    "Product code, for example flex_desk or day_pass.",
                ),
            ),
        },
    ),
    (
        "CWV_ASOF",
        {
            "description": "Publication timestamp of the price index (asOf).",
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
            ),
        },
    ),
    (
        "CWV_SOURCE",
        {
            "description": "Credit line for the CoworkingView data.",
            "params": (),
        },
    ),
    (
        "CWV_ATTRIBUTION",
        {
            "description": (
                "Attribution text shipped with the price index. "
                "Keep it with any figure you publish."
            ),
            "params": (
                (
                    "City",
                    "City slug, for example berlin. Blank uses berlin.",
                ),
            ),
        },
    ),
)


class CwvError(Exception):
    """Failure text the spreadsheet should show, without a CWV prefix."""


def source() -> str:
    """Credit line. Does not call the network."""
    return SOURCE


def city_slug(value: Any) -> str:
    """Normalise a Calc argument to a city slug. Blank means Berlin."""
    if value is None:
        return DEFAULT_CITY
    text = str(value).strip().lower()
    if text in ("", "none"):
        return DEFAULT_CITY
    text = text.replace("_", "-").replace(" ", "-")
    while "--" in text:
        text = text.replace("--", "-")
    if not _CITY_RE.fullmatch(text):
        raise CwvError("city must be a slug such as berlin")
    return text


def product_code(value: Any) -> str:
    """Normalise a product argument to the API's snake_case code."""
    if value is None:
        raise CwvError("product is required, for example flex_desk")
    text = str(value).strip().lower().replace("-", " ").replace("_", " ")
    text = "_".join(text.split())
    if not text:
        raise CwvError("product is required, for example flex_desk")
    if not _PRODUCT_RE.fullmatch(text):
        raise CwvError("product must be a code such as flex_desk")
    return text


def stat_name(value: Any, *, default: str | None = None) -> str:
    """One of the statistic names the price index actually uses."""
    if value is None or str(value).strip() == "":
        if default is not None:
            return default
        raise CwvError("stat is required: median, min, max, p25, or p75")
    text = str(value).strip().lower()
    if text not in _STAT_SET:
        raise CwvError("stat must be one of median, min, max, p25, p75")
    return text


def camel_to_snake(key: str) -> str:
    """``dayPass`` to ``day_pass``."""
    pieces = []
    for char in key:
        if char.isupper():
            pieces.append("_")
            pieces.append(char.lower())
        else:
            pieces.append(char)
    return "".join(pieces).lstrip("_")


def _as_number(value: Any, what: str) -> Any:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise CwvError(what + " was not a number")
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            raise CwvError(what + " was not a number")
        if value.is_integer():
            return int(value)
    return value


def _money_amount(node: Any) -> Any:
    if not isinstance(node, dict) or "amount" not in node:
        return None
    return _as_number(node["amount"], "amount")


def _copy_stats(slot: dict, item: Mapping[str, Any], keys: Sequence[str]) -> None:
    for key in keys:
        if key not in item:
            continue
        amount = _money_amount(item.get(key))
        if amount is not None and key not in slot:
            slot[key] = amount


def _remember_sample(slot: dict, item: Mapping[str, Any]) -> None:
    if "sample_size" in slot or "sampleSize" not in item:
        return
    slot["sample_size"] = _as_number(item["sampleSize"], "sampleSize")


def products_from_city(city: Mapping[str, Any]) -> dict:
    """Map product code to the statistics that object actually carries.

    ``figures`` is preferred for median, p25, p75 and sample size.
    ``byType`` fills min and max, which ``figures`` does not carry.
    A city field whose value has both ``median`` and ``sampleSize``
    (``dayPass``, ``meetingRoom``, and any later aggregate of that shape)
    is included under its snake_case name.
    """
    found: dict = {}

    def slot_for(product: str) -> dict:
        return found.setdefault(product, {})

    for item in city.get("figures") or []:
        if not isinstance(item, dict) or not isinstance(item.get("optionType"), str):
            continue
        slot = slot_for(item["optionType"])
        _copy_stats(slot, item, ("median", "p25", "p75"))
        _remember_sample(slot, item)
    for item in city.get("byType") or []:
        if not isinstance(item, dict) or not isinstance(item.get("optionType"), str):
            continue
        slot = slot_for(item["optionType"])
        _copy_stats(slot, item, ("median", "min", "max"))
        _remember_sample(slot, item)
    for key, value in city.items():
        if not isinstance(value, dict):
            continue
        if "median" not in value or "sampleSize" not in value:
            continue
        slot = slot_for(camel_to_snake(key))
        _copy_stats(slot, value, _STATS)
        _remember_sample(slot, value)
    return found


def _ordered(names: Sequence[str]) -> list:
    rank = {name: index for index, name in enumerate(_PRODUCT_ORDER)}
    return sorted(names, key=lambda name: (name not in rank, rank.get(name, 0), name))


def _data(payload: Mapping[str, Any]) -> Mapping[str, Any]:
    data = payload.get("data") if isinstance(payload, Mapping) else None
    if not isinstance(data, dict):
        raise CwvError("rates response has no data object")
    return data


def published_city(payload: Mapping[str, Any], slug: str) -> Mapping[str, Any]:
    """The published city row, or an error when the slug is not in it."""
    for row in _data(payload).get("cities") or []:
        if not isinstance(row, dict):
            continue
        city = row.get("city")
        if isinstance(city, dict) and city.get("slug") == slug:
            return row
    raise CwvError("unknown city '" + slug + "'")


def _product_slot(city: Mapping[str, Any], product: str) -> dict:
    found = products_from_city(city)
    if product not in found:
        available = ", ".join(_ordered(found)) or "none"
        raise CwvError(
            "unknown product '" + product + "'. Available: " + available
        )
    return found[product]


def rate_amount(payload: Mapping[str, Any], slug: str, product: str, stat: str) -> Any:
    slot = _product_slot(published_city(payload, slug), product)
    if stat not in slot:
        have = [name for name in _STATS if name in slot]
        listed = ", ".join(have) or "none"
        raise CwvError(
            "'" + stat + "' is not published for '" + product + "'. Available: " + listed
        )
    return slot[stat]


def sample_size(payload: Mapping[str, Any], slug: str, product: str) -> Any:
    slot = _product_slot(published_city(payload, slug), product)
    if "sample_size" not in slot:
        raise CwvError("sample size is not published for '" + product + "'")
    return slot["sample_size"]


def currency_code(payload: Mapping[str, Any], slug: str) -> str:
    city = published_city(payload, slug)
    code = city.get("currency")
    if not isinstance(code, str) or not code:
        raise CwvError("currency is not published for '" + slug + "'")
    return code


def as_of(payload: Mapping[str, Any], slug: str) -> str:
    published_city(payload, slug)
    stamp = _data(payload).get("asOf")
    if not isinstance(stamp, str) or not stamp:
        raise CwvError("asOf is not in the response")
    return stamp


def attribution(payload: Mapping[str, Any], slug: str) -> str:
    published_city(payload, slug)
    text = _data(payload).get("attribution")
    if not isinstance(text, str) or not text.strip():
        raise CwvError("attribution is not in the response")
    return text


def pagination_total(payload: Mapping[str, Any]) -> int:
    meta = payload.get("meta") if isinstance(payload, Mapping) else None
    pagination = meta.get("pagination") if isinstance(meta, dict) else None
    total = pagination.get("total") if isinstance(pagination, dict) else None
    if isinstance(total, bool) or not isinstance(total, int):
        raise CwvError("properties response has no pagination total")
    return total


def _slim_rates(payload: Any) -> Any:
    """Drop building names and the long legal copies before caching."""
    if not isinstance(payload, dict):
        return payload
    data = payload.get("data")
    if not isinstance(data, dict):
        return {"data": data, "meta": payload.get("meta")}
    cities = []
    for city in data.get("cities") or []:
        if isinstance(city, dict):
            cities.append({key: value for key, value in city.items() if key != "buildings"})
    kept = {
        "cities": cities,
        "asOf": data.get("asOf"),
        "attribution": data.get("attribution"),
        "license": data.get("license"),
        "licenseUrl": data.get("licenseUrl"),
    }
    return {"data": kept, "meta": payload.get("meta")}


def _slim_properties(payload: Any) -> Any:
    """Keep the catalogue count only. Do not cache a listing."""
    if not isinstance(payload, dict):
        return {"meta": {"pagination": {"total": None}}}
    meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
    pagination = meta.get("pagination") if isinstance(meta.get("pagination"), dict) else {}
    return {"meta": {"pagination": {"total": pagination.get("total")}}}


def _header(headers: Any, name: str) -> str | None:
    if headers is None:
        return None
    getter = getattr(headers, "get", None)
    if getter is None:
        return None
    value = getter(name)
    if value is None:
        return None
    return str(value)


def max_age(headers: Any, default: float = DEFAULT_CACHE_SECONDS) -> float:
    raw = _header(headers, "Cache-Control")
    if not raw:
        return default
    match = _MAX_AGE_RE.search(raw)
    if match is None:
        return default
    return float(match.group(1))


def _seconds(value: str) -> float | None:
    try:
        return max(0.0, float(value.strip()))
    except ValueError:
        pass
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max(0.0, (when - datetime.now(timezone.utc)).total_seconds())


def retry_wait(headers: Any) -> float:
    """``Retry-After``, else ``RateLimit-Reset``, else 2 seconds, capped at 10."""
    for name in ("Retry-After", "RateLimit-Reset"):
        raw = _header(headers, name)
        if raw is None:
            continue
        seconds = _seconds(raw)
        if seconds is not None:
            return min(seconds, MAX_RETRY_WAIT)
    return FALLBACK_RETRY_WAIT


def _problem(status: int, raw: bytes) -> str:
    body: Any = None
    try:
        body = json.loads(raw.decode("utf-8")) if raw else None
    except (UnicodeDecodeError, ValueError):
        body = None
    if not isinstance(body, dict):
        return "HTTP " + str(status)
    code = body.get("code") if isinstance(body.get("code"), str) else "HTTP_" + str(status)
    title = body.get("title") if isinstance(body.get("title"), str) else "request failed"
    extra = ""
    errors = body.get("errors")
    if isinstance(errors, list) and errors and isinstance(errors[0], dict):
        path = errors[0].get("path") or ""
        message = errors[0].get("message") or ""
        if path or message:
            extra = " (" + str(path) + ": " + str(message) + ")"
    return title + " [" + code + "]" + extra


def _decode(raw: bytes) -> Any:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise CwvError("response was not valid JSON") from None
    if not isinstance(payload, dict):
        raise CwvError("response was not a JSON object")
    return payload


class Client:
    """GET JSON from the public API, with one retry and a process-local cache."""

    def __init__(
        self,
        base_url: str | None = None,
        urlopen: Callable[..., Any] | None = None,
        sleep: Callable[[float], None] | None = None,
        clock: Callable[[], float] | None = None,
        timeout: float = TIMEOUT_SECONDS,
    ) -> None:
        chosen = base_url if base_url is not None else os.environ.get("COWORKINGVIEW_API_URL")
        self.base_url = (chosen or DEFAULT_BASE_URL).rstrip("/")
        self._urlopen = urlopen or urllib.request.urlopen
        self._sleep = sleep or time.sleep
        self._clock = clock or time.monotonic
        self.timeout = timeout
        self._cache: dict = {}
        self._lock = threading.Lock()

    def url(self, path: str, params: Mapping[str, Any]) -> str:
        query = urllib.parse.urlencode([(key, params[key]) for key in params])
        return self.base_url + path + ("?" + query if query else "")

    def get_json(
        self,
        path: str,
        params: Mapping[str, Any],
        reduce: Callable[[Any], Any] | None = None,
    ) -> Any:
        key = self.url(path, params)
        now = self._clock()
        with self._lock:
            hit = self._cache.get(key)
            if hit is not None and now < hit[0]:
                return hit[1]
        payload, ttl = self._fetch(key)
        if reduce is not None:
            payload = reduce(payload)
        if ttl > 0:
            with self._lock:
                self._cache[key] = (self._clock() + ttl, payload)
        return payload

    def rates(self, slug: str) -> Any:
        return self.get_json(
            "/v1/market/rates",
            {"locale": LOCALE, "city": slug},
            reduce=_slim_rates,
        )

    def properties(self, slug: str) -> Any:
        return self.get_json(
            "/v1/properties",
            {"locale": LOCALE, "city": slug, "page": 1, "pageSize": 1},
            reduce=_slim_properties,
        )

    def _fetch(self, url: str) -> tuple:
        delay = 0.0
        last_status = 0
        last_raw = b""
        for attempt in range(2):
            if delay:
                self._sleep(delay)
            status, headers, raw = self._open(url)
            if status == 200:
                return _decode(raw), max_age(headers)
            last_status = status
            last_raw = raw
            retry = status == 429 or 500 <= status <= 599
            if attempt == 0 and retry:
                delay = retry_wait(headers)
                continue
            break
        raise CwvError(_problem(last_status, last_raw))

    def _open(self, url: str) -> tuple:
        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "User-Agent": USER_AGENT},
            method="GET",
        )
        try:
            response = self._urlopen(request, timeout=self.timeout)
        except urllib.error.HTTPError as exc:
            raw = exc.read(MAX_RESPONSE_BYTES + 1)
            return exc.code, exc.headers, _bounded(raw)
        except urllib.error.URLError as exc:
            raise CwvError("network error: " + str(exc.reason)) from None
        except CwvError:
            raise
        except (OSError, ValueError, TypeError) as exc:
            raise CwvError("network error: " + str(exc)) from None
        with response:
            status = getattr(response, "status", None) or response.getcode()
            raw = response.read(MAX_RESPONSE_BYTES + 1)
            return status, response.headers, _bounded(raw)


def _bounded(raw: bytes) -> bytes:
    if len(raw) > MAX_RESPONSE_BYTES:
        raise CwvError("response was larger than 2 MB")
    return raw


def spaces(client: Client, city: Any) -> int:
    slug = city_slug(city)
    rates_payload = client.rates(slug)
    published_city(rates_payload, slug)
    return pagination_total(client.properties(slug))


def price(client: Client, city: Any, product: Any) -> Any:
    return rate_amount(
        client.rates(city_slug(city)),
        city_slug(city),
        product_code(product),
        "median",
    )


def rate(client: Client, city: Any, product: Any, stat: Any) -> Any:
    slug = city_slug(city)
    return rate_amount(
        client.rates(slug),
        slug,
        product_code(product),
        stat_name(stat),
    )


def currency(client: Client, city: Any) -> str:
    slug = city_slug(city)
    return currency_code(client.rates(slug), slug)


def sample(client: Client, city: Any, product: Any) -> Any:
    slug = city_slug(city)
    return sample_size(client.rates(slug), slug, product_code(product))


def index_as_of(client: Client, city: Any) -> str:
    slug = city_slug(city)
    return as_of(client.rates(slug), slug)


def index_attribution(client: Client, city: Any) -> str:
    slug = city_slug(city)
    return attribution(client.rates(slug), slug)


def _xml(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def render_xcu() -> str:
    """``CalcAddIns.xcu`` body. The function wizard reads this file."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        ('<oor:component-data xmlns:oor="http://openoffice.org/2001/registry"'
        ' xmlns:xs="http://www.w3.org/2001/XMLSchema"'
        ' oor:name="CalcAddIns" oor:package="org.openoffice.Office">'),
        ' <node oor:name="AddInInfo">',
        '  <node oor:name="com.coworkingview.calc.CoworkingView" oor:op="replace">',
        '   <node oor:name="AddInFunctions">',
    ]
    for name, spec in FUNCTIONS:
        lines.append('    <node oor:name="' + name + '" oor:op="replace">')
        lines.append('     <prop oor:name="DisplayName">')
        lines.append('      <value xml:lang="en">' + name + "</value>")
        lines.append("     </prop>")
        lines.append('     <prop oor:name="Description">')
        lines.append(
            '      <value xml:lang="en">' + _xml(spec["description"]) + "</value>"
        )
        lines.append("     </prop>")
        lines.append('     <prop oor:name="Category">')
        lines.append("      <value>Add-In</value>")
        lines.append("     </prop>")
        lines.append('     <prop oor:name="CompatibilityName">')
        lines.append('      <value xml:lang="en">' + name + "</value>")
        lines.append("     </prop>")
        if spec["params"]:
            lines.append('     <node oor:name="Parameters">')
            for param, description in spec["params"]:
                lines.append('      <node oor:name="' + param + '" oor:op="replace">')
                lines.append('       <prop oor:name="DisplayName">')
                lines.append('        <value xml:lang="en">' + param + "</value>")
                lines.append("       </prop>")
                lines.append('       <prop oor:name="Description">')
                lines.append(
                    '        <value xml:lang="en">' + _xml(description) + "</value>"
                )
                lines.append("       </prop>")
                lines.append("      </node>")
            lines.append("     </node>")
        lines.append("    </node>")
    lines.extend(
        [
            "   </node>",
            "  </node>",
            " </node>",
            "</oor:component-data>",
            "",
        ]
    )
    return "\n".join(lines)
