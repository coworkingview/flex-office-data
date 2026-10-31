"""Read-only client for the public CoworkingView API.

The same endpoints the other packages in this repository call:

* ``GET /v1/properties`` — catalogue search (``spaces()``)
* ``GET /v1/properties/{slug}`` — one listing (``space()``)
* ``GET /v1/geo/bootstrap`` — countries, cities, and zones

Nothing in this module invents a price, an address, or a workspace type.
A field the response does not contain is ``None``.
"""

from __future__ import annotations

import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping
from typing import Any

API_URL = "https://api.coworkingview.com"
SITE_URL = "https://coworkingview.com"
ENV_BASE_URL = "COWORKINGVIEW_API_URL"
USER_AGENT = (
    "coworkingview-dify/0.0.1 (+https://github.com/coworkingview/flex-office-data)"
)
DEFAULT_TIMEOUT = 20.0
MAX_BODY_BYTES = 5 * 1024 * 1024
MAX_WAIT = 10.0
FALLBACK_WAIT = 2.0
DEFAULT_LIMIT = 10
MAX_LIMIT = 20

# Listing path segment per API locale. Matches spec/SPEC.md section 5.
WORKSPACE_PATH = {"en": "workspace", "es": "oficina", "de": "buero"}

# Product codes accepted by ``pricingOptionType``, with the label shown in Dify.
WORKSPACE_TYPES: tuple[tuple[str, str], ...] = (
    ("flex_desk", "Flex desk"),
    ("fix_desk", "Fixed desk"),
    ("private_office", "Private office"),
    ("exclusive_bereich", "Exclusive area"),
    ("day_pass", "Day pass"),
    ("meeting_room", "Meeting room"),
    ("event_space", "Event space"),
    ("virtual_office", "Virtual office"),
    ("membership", "Membership"),
)

_LOCALE_ALIASES = {
    "en": "en",
    "en_us": "en",
    "de": "de",
    "de_de": "de",
    "es": "es",
    "es_es": "es",
}
_SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
_CITY_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

Opener = Callable[[urllib.request.Request, float], Any]
Sleeper = Callable[[float], None]


class CoworkingViewError(Exception):
    """The public API could not answer, or an argument is not usable."""


class APIError(CoworkingViewError):
    """The API returned an error or a body that is not the expected JSON."""

    def __init__(self, status: int, code: str, title: str, detail: str) -> None:
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        message = detail or title or "request failed"
        super().__init__(f"CoworkingView API {status} {code}: {message}")


def workspace_type_codes() -> tuple[str, ...]:
    return tuple(code for code, _label in WORKSPACE_TYPES)


def normalize_locale(value: object) -> str:
    """Map a tool locale to ``en``, ``de``, or ``es``."""
    if value is None:
        return "en"
    if not isinstance(value, str) or not value.strip():
        if value == "":
            return "en"
        raise CoworkingViewError("locale must be en, de, or es.")
    key = value.strip().lower().replace("-", "_")
    if key not in _LOCALE_ALIASES:
        raise CoworkingViewError("locale must be en, de, or es.")
    return _LOCALE_ALIASES[key]


def normalize_city(value: object) -> str:
    """City slug. A display name is lowercased and its spaces become hyphens."""
    if not isinstance(value, str) or not value.strip():
        raise CoworkingViewError(
            "city is required. Use a slug from list_cities, for example berlin or abu-dhabi."
        )
    slug = re.sub(r"[\s_]+", "-", value.strip().lower())
    if not _CITY_RE.fullmatch(slug):
        raise CoworkingViewError(
            "city must be a CoworkingView city slug such as berlin or abu-dhabi. "
            "Call list_cities for the supported slugs."
        )
    return slug


def normalize_workspace_type(value: object) -> str | None:
    """A published product code, or ``None`` when the caller did not filter."""
    if value is None:
        return None
    if not isinstance(value, str):
        raise CoworkingViewError(
            "workspace_type must be one of: " + ", ".join(workspace_type_codes()) + "."
        )
    text = re.sub(r"[\s_]+", " ", value.strip().lower().replace("-", " "))
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return None
    by_code = {code.replace("_", " "): code for code, _label in WORKSPACE_TYPES}
    by_label = {label.lower(): code for code, label in WORKSPACE_TYPES}
    code = by_code.get(text) or by_label.get(text)
    if code is None:
        raise CoworkingViewError(
            f"workspace_type {value!r} is not a CoworkingView product. "
            "Use one of: " + ", ".join(workspace_type_codes()) + "."
        )
    return code


def normalize_slug(value: object) -> str:
    if not isinstance(value, str) or not _SLUG_RE.fullmatch(value.strip()):
        raise CoworkingViewError(
            "slug must be the listing slug returned by search_workspaces "
            "(letters, digits, and . _ -)."
        )
    return value.strip()


def normalize_limit(value: object) -> int:
    if value is None or value == "":
        return DEFAULT_LIMIT
    number = value
    if isinstance(number, str):
        stripped = number.strip()
        if not stripped:
            return DEFAULT_LIMIT
        if not re.fullmatch(r"\d+", stripped):
            raise CoworkingViewError("limit must be an integer from 1 to 20.")
        number = int(stripped)
    if isinstance(number, float):
        if not number.is_integer():
            raise CoworkingViewError("limit must be an integer from 1 to 20.")
        number = int(number)
    if isinstance(number, bool) or not isinstance(number, int) or not 1 <= number <= MAX_LIMIT:
        raise CoworkingViewError("limit must be an integer from 1 to 20.")
    return number


def normalize_country(value: object) -> str | None:
    if value is None or value == "":
        return None
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z]{2}", value.strip()):
        raise CoworkingViewError("country must be an ISO 3166-1 alpha-2 code such as DE.")
    return value.strip().upper()


def listing_url(slug: str, locale: str, web_url: object = None) -> str:
    """Public listing URL on coworkingview.com, without a www host."""
    if isinstance(web_url, str) and web_url.strip():
        parts = urllib.parse.urlsplit(web_url.strip())
        host = (parts.hostname or "").lower()
        if parts.scheme == "https" and host in {"coworkingview.com", "www.coworkingview.com"}:
            path = parts.path or "/"
            return urllib.parse.urlunsplit(
                ("https", "coworkingview.com", path, parts.query, "")
            )
    segment = WORKSPACE_PATH[locale]
    return f"{SITE_URL}/{locale}/{segment}/{slug}"


def _clean(value: object) -> str | None:
    if isinstance(value, str):
        text = value.strip()
        return text or None
    return None


def _whole_number(value: object) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _nested_name(value: object) -> tuple[str | None, str | None]:
    if not isinstance(value, dict):
        return None, None
    return _clean(value.get("slug")), _clean(value.get("name"))


def workspace_record(
    card: Mapping[str, Any],
    locale: str,
    *,
    filtered_type: str | None = None,
    from_detail: bool = False,
) -> dict[str, Any] | None:
    """Fields a tool may return. Prices, photos, and descriptions are dropped."""
    slug = _clean(card.get("slug"))
    if slug is None:
        return None
    city_slug, city_name = _nested_name(card.get("city"))
    _zone_slug, zone_name = _nested_name(card.get("zone"))
    _operator_slug, operator_name = _nested_name(card.get("operator"))
    if from_detail:
        types: list[str] = []
        options = card.get("pricingOptions")
        if isinstance(options, list):
            for option in options:
                if not isinstance(option, dict):
                    continue
                code = _clean(option.get("optionType"))
                if code and code not in types:
                    types.append(code)
        workspace_type: list[str] | None = types or None
    else:
        workspace_type = [filtered_type] if filtered_type else None
    return {
        "name": _clean(card.get("title")),
        "city": city_name,
        "city_slug": city_slug,
        "zone": zone_name,
        "address": _clean(card.get("address")),
        "type": workspace_type,
        "url": listing_url(slug, locale, card.get("webUrl")),
        "slug": slug,
        "operator": operator_name,
    }


def _citation(meta: object) -> str | None:
    if not isinstance(meta, dict):
        return None
    citation = meta.get("citation")
    if isinstance(citation, dict):
        return _clean(citation.get("text"))
    return None


def _notice(meta: object) -> str | None:
    if not isinstance(meta, dict):
        return None
    return _clean(meta.get("catalogueNotice"))


def render_workspaces(payload: Mapping[str, Any]) -> str:
    """Plain-text view of a search or a single listing. No prices."""
    rows = payload.get("workspaces")
    if rows is None and isinstance(payload.get("workspace"), dict):
        rows = [payload["workspace"]]
    if not isinstance(rows, list):
        rows = []
    lines: list[str] = []
    if not rows:
        lines.append("No matching workspaces were returned by the CoworkingView API.")
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = row.get("name") or "name not in this response"
        city = row.get("city") or "city not in this response"
        types = row.get("type")
        type_text = ", ".join(types) if isinstance(types, list) and types else "type not in this response"
        address = row.get("address") or "street address not in this response"
        lines.append(
            f"{name} | {city} | {type_text} | {address} | {row.get('url')} | slug {row.get('slug')}"
        )
    total = payload.get("total")
    if isinstance(total, int) and not isinstance(total, bool):
        lines.append(f"Matches reported by the API: {total}. This tool returns one page only.")
    citation = payload.get("citation")
    if isinstance(citation, str) and citation:
        lines.append(citation)
    notice = payload.get("notice")
    if isinstance(notice, str) and notice:
        lines.append(notice)
    lines.append("This response does not include prices. Do not invent one.")
    return "\n".join(lines)


def render_cities(payload: Mapping[str, Any]) -> str:
    cities = payload.get("cities")
    if not isinstance(cities, list) or not cities:
        return "No cities were returned by the CoworkingView API."
    lines = ["Supported cities. Use the slug as the city argument of search_workspaces."]
    for city in cities:
        if not isinstance(city, dict):
            continue
        count = city.get("property_count")
        count_text = str(count) if isinstance(count, int) and not isinstance(count, bool) else "n/a"
        name = city.get("name") or "name not in this response"
        lines.append(f"{city.get('slug')} — {name} — {city.get('country_code') or ''} — {count_text} listings")
    return "\n".join(lines)


def _retry_wait(headers: object) -> float:
    getter = getattr(headers, "get", None)
    if not callable(getter):
        return FALLBACK_WAIT
    for key in ("Retry-After", "RateLimit-Reset"):
        raw = getter(key)
        if raw is None:
            continue
        try:
            seconds = float(str(raw).strip())
        except ValueError:
            continue
        if seconds >= 0:
            return min(seconds, MAX_WAIT)
    return FALLBACK_WAIT


def _base_url(value: str) -> str:
    parts = urllib.parse.urlsplit(value.strip())
    if parts.scheme not in {"https", "http"} or not parts.hostname or parts.username or parts.password:
        raise CoworkingViewError("base_url must be an http(s) origin without userinfo.")
    host = parts.hostname
    if parts.port:
        host = f"{host}:{parts.port}"
    return urllib.parse.urlunsplit((parts.scheme, host, "", "", ""))


class Client:
    """One-shot GETs against the public API. No network call at import time."""

    def __init__(
        self,
        base_url: str | None = None,
        timeout: float = DEFAULT_TIMEOUT,
        user_agent: str | None = None,
        opener: Opener | None = None,
        sleeper: Sleeper | None = None,
    ) -> None:
        raw = base_url or os.environ.get(ENV_BASE_URL) or API_URL
        self.base_url = _base_url(raw)
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise CoworkingViewError("timeout must be a positive number of seconds.")
        self.timeout = float(timeout)
        self.user_agent = user_agent or USER_AGENT
        self._opener = opener or urllib.request.urlopen
        self._sleeper = sleeper or time.sleep

    def search_workspaces(
        self,
        city: object,
        workspace_type: object = None,
        locale: object = None,
        limit: object = None,
    ) -> dict[str, Any]:
        """One page of listings for a city, optionally limited to one product."""
        city_slug = normalize_city(city)
        product = normalize_workspace_type(workspace_type)
        loc = normalize_locale(locale)
        page_size = normalize_limit(limit)
        params: dict[str, str] = {
            "locale": loc,
            "city": city_slug,
            "page": "1",
            "pageSize": str(page_size),
            "sortBy": "date-desc",
        }
        if product:
            params["pricingOptionType"] = product
        payload = self._get("/v1/properties", params)
        data = payload.get("data")
        if not isinstance(data, list):
            raise APIError(200, "BAD_RESPONSE", "Bad response", "Unexpected shape for properties.")
        meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
        pagination = meta.get("pagination") if isinstance(meta.get("pagination"), dict) else {}
        workspaces = []
        for card in data:
            if not isinstance(card, dict):
                continue
            record = workspace_record(card, loc, filtered_type=product, from_detail=False)
            if record is not None:
                workspaces.append(record)
        return {
            "workspaces": workspaces[:page_size],
            "total": _whole_number(pagination.get("total")),
            "citation": _citation(meta),
            "notice": _notice(meta),
        }

    def get_workspace(self, slug: object, locale: object = None) -> dict[str, Any]:
        """One listing, including the street address when the API publishes it."""
        loc = normalize_locale(locale)
        safe_slug = normalize_slug(slug)
        payload = self._get("/v1/properties/" + urllib.parse.quote(safe_slug, safe=""), {"locale": loc})
        detail = payload.get("data")
        if not isinstance(detail, dict):
            raise APIError(200, "BAD_RESPONSE", "Bad response", "Unexpected shape for a property.")
        record = workspace_record(detail, loc, from_detail=True)
        if record is None:
            raise APIError(200, "BAD_RESPONSE", "Bad response", "The property has no slug.")
        meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
        return {
            "workspace": record,
            "citation": _citation(meta),
            "notice": _notice(meta),
        }

    def list_cities(self, locale: object = None, country: object = None) -> dict[str, Any]:
        """Cities in the catalogue index. ``property_count`` is the API's figure."""
        loc = normalize_locale(locale)
        country_code = normalize_country(country)
        payload = self._get("/v1/geo/bootstrap", {"locale": loc})
        data = payload.get("data")
        if not isinstance(data, dict) or not isinstance(data.get("cities"), list):
            raise APIError(200, "BAD_RESPONSE", "Bad response", "Unexpected shape for the places index.")
        cities: list[dict[str, Any]] = []
        for item in data["cities"]:
            if not isinstance(item, dict):
                continue
            slug = _clean(item.get("slug"))
            if slug is None:
                continue
            code = _clean(item.get("countryCode"))
            if country_code and (code or "").upper() != country_code:
                continue
            cities.append(
                {
                    "slug": slug,
                    "name": _clean(item.get("name")),
                    "country_code": code,
                    "property_count": _whole_number(item.get("propertyCount")),
                }
            )
        cities.sort(key=lambda row: row["slug"])
        meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
        return {"cities": cities, "citation": _citation(meta)}

    def _get(self, path: str, params: Mapping[str, str]) -> dict[str, Any]:
        query = urllib.parse.urlencode(params)
        url = self.base_url + path + ("?" + query if query else "")
        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "User-Agent": self.user_agent},
            method="GET",
        )
        for attempt in (0, 1):
            try:
                raw, status, headers = self._read(request)
            except urllib.error.URLError as exc:
                raise CoworkingViewError(
                    "The CoworkingView API could not be reached. Try again in a moment."
                ) from exc
            if status == 429 or 500 <= status <= 599:
                if attempt == 0:
                    self._sleeper(_retry_wait(headers))
                    continue
            if status < 200 or status >= 300:
                raise self._problem(status, raw)
            return self._json_object(status, raw)
        raise CoworkingViewError("The CoworkingView API failed after one retry.")

    def _read(self, request: urllib.request.Request) -> tuple[bytes, int, object]:
        try:
            response = self._opener(request, self.timeout)
        except urllib.error.HTTPError as exc:
            raw = exc.read(MAX_BODY_BYTES + 1)
            status = int(exc.code)
            headers = exc.headers
        else:
            try:
                raw = response.read(MAX_BODY_BYTES + 1)
                status = int(getattr(response, "status", 200))
                headers = getattr(response, "headers", {})
            finally:
                close = getattr(response, "close", None)
                if callable(close):
                    close()
        if len(raw) > MAX_BODY_BYTES:
            raise CoworkingViewError("The CoworkingView API response was larger than 5 MB.")
        return raw, status, headers

    @staticmethod
    def _json_object(status: int, raw: bytes) -> dict[str, Any]:
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise APIError(
                status,
                "BAD_RESPONSE",
                "Bad response",
                "The API returned a body that is not valid JSON.",
            ) from None
        if not isinstance(payload, dict) or "data" not in payload:
            raise APIError(
                status,
                "BAD_RESPONSE",
                "Bad response",
                "The API response has no data member.",
            )
        return payload

    @staticmethod
    def _problem(status: int, raw: bytes) -> APIError:
        code = f"HTTP_{status}"
        title = "Request failed"
        detail = ""
        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            body = None
        if isinstance(body, dict):
            if isinstance(body.get("code"), str) and body["code"].strip():
                code = body["code"].strip()
            if isinstance(body.get("title"), str) and body["title"].strip():
                title = body["title"].strip()
            if isinstance(body.get("detail"), str):
                detail = body["detail"].strip()
        return APIError(status, code, title, detail or title)
