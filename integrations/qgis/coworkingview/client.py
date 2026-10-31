# -*- coding: utf-8 -*-
"""Read CoworkingView workspaces from the public API.

This module is pure Python (no QGIS, no third-party packages) so it can be
tested and so a QGIS install does not need extra dependencies. It follows the
same public API as the rest of this repository: ``https://api.coworkingview.com``.

Prices, photos and descriptions are not copied onto the records the map uses.
Names, city, address, workspace type and the listing URL are.
"""

from __future__ import annotations

import json
import math
import os
import re
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

VERSION = "0.1.0"
DEFAULT_BASE_URL = "https://api.coworkingview.com"
SITE_URL = "https://coworkingview.com"
USER_AGENT = (
    "coworkingview-qgis/{0} (+https://github.com/coworkingview/flex-office-data)"
).format(VERSION)
LOCALE = "en"
PAGE_SIZE = 50
MAX_SPACES = 200
TIMEOUT = 20.0
MIN_INTERVAL = 0.55
MAX_RETRY_WAIT = 10.0

# Product codes published by the API (spec section 1). Labels match the
# names used in this repository's documentation.
WORKSPACE_TYPES = (
    ("flex_desk", "Flex desk"),
    ("fix_desk", "Dedicated desk"),
    ("private_office", "Private office"),
    ("exclusive_bereich", "Exclusive area"),
    ("day_pass", "Day pass"),
    ("meeting_room", "Meeting room"),
    ("event_space", "Event space"),
    ("virtual_office", "Virtual office"),
    ("membership", "Membership"),
)
TYPE_LABELS = dict(WORKSPACE_TYPES)

SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$")
CITY_RE = re.compile(r"^[a-z0-9-]{1,200}$")
LISTING_HOSTS = ("coworkingview.com", "www.coworkingview.com")


class CoworkingViewError(Exception):
    """The plugin could not complete a CoworkingView request."""

    def __init__(self, message, status=None, code=None):
        super().__init__(message)
        self.status = status
        self.code = code


class Cancelled(Exception):
    """The user cancelled a city or workspace load."""


@dataclass(frozen=True)
class City:
    """One city from the public places index or price-index city list."""

    slug: str
    name: str
    country_code: str | None
    property_count: int | None


@dataclass(frozen=True)
class Workspace:
    """One workspace ready to draw. No prices, photos or descriptions."""

    name: str
    city: str
    address: str | None
    workspace_type: str | None
    url: str
    lat: float
    lng: float
    slug: str


@dataclass(frozen=True)
class SearchResult:
    """A filtered workspace search and the attribution that came with it."""

    city_slug: str
    city_name: str
    type_code: str | None
    type_label: str | None
    workspaces: tuple
    total: int | None
    truncated: bool
    skipped: int
    detail_failures: int
    citation: str | None
    notice: str | None


def type_label(code):
    """Human label for a workspace-type code. Unknown codes stay as returned."""
    return TYPE_LABELS.get(code, code)


def format_types(codes):
    """Comma-separated labels in the documented product order, duplicates dropped."""
    seen = []
    for code in codes:
        if isinstance(code, str) and code and code not in seen:
            seen.append(code)
    if not seen:
        return None
    order = {code: index for index, (code, _label) in enumerate(WORKSPACE_TYPES)}

    def sort_key(code):
        if code in order:
            return (0, order[code], "")
        return (1, 0, code)

    seen.sort(key=sort_key)
    return ", ".join(type_label(code) for code in seen)


def listing_url(slug):
    """Canonical English listing page for a workspace slug."""
    return "{0}/{1}/workspace/{2}".format(SITE_URL, LOCALE, slug)


def accepted_listing_url(url, slug):
    """Use ``url`` when it is an https page on coworkingview.com, else build one."""
    fallback = listing_url(slug)
    if not isinstance(url, str):
        return fallback
    cleaned = url.strip()
    parsed = urllib.parse.urlparse(cleaned)
    host = parsed.netloc.lower()
    if parsed.scheme != "https" or host not in LISTING_HOSTS:
        return fallback
    if not parsed.path or parsed.path == "/":
        return fallback
    return cleaned


def status_message(result):
    """One status sentence for a finished search. Counts come from the result."""
    count = len(result.workspaces)
    place = result.city_name
    if count == 0:
        if result.type_label:
            text = "No {0} workspaces matched in {1}.".format(result.type_label, place)
        else:
            text = "No workspaces in {0} matched this filter.".format(place)
    elif result.total is not None and result.total > count:
        if result.type_label:
            text = "Showing {0} of {1} {2} workspaces in {3}.".format(
                count, result.total, result.type_label, place
            )
        else:
            text = "Showing {0} of {1} workspaces in {2}.".format(count, result.total, place)
    elif result.type_label:
        text = "Added {0} {1} workspaces in {2}.".format(count, result.type_label, place)
    else:
        text = "Added {0} workspaces in {1}.".format(count, place)
    if count >= MAX_SPACES:
        text += " The plugin loads at most {0} spaces per search.".format(MAX_SPACES)
    if result.skipped:
        text += (
            " {0} listings were left off the map because they had no usable coordinates."
        ).format(result.skipped)
    if result.detail_failures:
        text += (
            " {0} listings could not be read in full, so address or type may be empty."
        ).format(result.detail_failures)
    return text


def layer_abstract(result):
    """Attribution stored on the layer: the API citation and catalogue notice."""
    parts = []
    if result.citation:
        parts.append(result.citation)
    if result.notice:
        parts.append(result.notice)
    parts.append("Listings open on {0}.".format(SITE_URL))
    return "\n\n".join(parts)


class Client:
    """Public read-only client. No network call happens in ``__init__``."""

    def __init__(
        self,
        base_url=None,
        request_fn=None,
        sleep=time.sleep,
        now=time.monotonic,
        min_interval=MIN_INTERVAL,
        timeout=TIMEOUT,
        max_spaces=MAX_SPACES,
    ):
        if base_url is None:
            base_url = os.environ.get("COWORKINGVIEW_API_URL", DEFAULT_BASE_URL)
        self.base_url = str(base_url).rstrip("/")
        self._check_base_url()
        self._request = request_fn or _urllib_request
        self._sleep = sleep
        self._now = now
        self.min_interval = min_interval
        self.timeout = timeout
        self.max_spaces = max_spaces
        self._last = None
        self._remaining = None
        self._reset = None
        self._should_cancel = None

    def list_cities(self, should_cancel=None):
        """Cities that have at least one listed space, sorted by name.

        Tries the places index first (``/v1/geo/bootstrap``). If that request
        fails, uses the published cities on ``/v1/market/rates``.
        """
        self._should_cancel = should_cancel
        try:
            return self._list_cities()
        finally:
            self._should_cancel = None

    def load_spaces(
        self,
        city_slug,
        city_name,
        pricing_option_type=None,
        on_progress=None,
        should_cancel=None,
    ):
        """Workspaces in one city, optionally limited to one workspace type.

        At most ``max_spaces`` listings (200 by default, the same cap as the
        other clients in this repository). Each listing is requested once so
        the address and workspace type can be read. The caller should pass
        ``should_cancel`` and may pass ``on_progress(done, total, message)``.
        """
        self._check_city(city_slug)
        type_code = self._check_type(pricing_option_type)
        self._should_cancel = should_cancel
        try:
            cards, total, citation, notice = self._collect_cards(
                city_slug, city_name, type_code, on_progress
            )
            workspaces, skipped, failures = self._read_details(
                cards, city_name, type_code, on_progress
            )
        finally:
            self._should_cancel = None
        label = type_label(type_code) if type_code else None
        return SearchResult(
            city_slug=city_slug,
            city_name=city_name,
            type_code=type_code,
            type_label=label,
            workspaces=tuple(workspaces),
            total=total,
            truncated=total is not None and len(workspaces) + skipped < total,
            skipped=skipped,
            detail_failures=failures,
            citation=citation,
            notice=notice,
        )

    def _list_cities(self):
        try:
            payload = self._get("/v1/geo/bootstrap", {"locale": LOCALE})
            return cities_from_bootstrap(payload)
        except Cancelled:
            raise
        except CoworkingViewError as first:
            return self._cities_from_rates(first)

    def _cities_from_rates(self, first):
        try:
            payload = self._get("/v1/market/rates", {"locale": LOCALE})
            return cities_from_rates(payload)
        except Cancelled:
            raise
        except CoworkingViewError as second:
            raise CoworkingViewError(
                "Could not load cities from the CoworkingView API. {0}".format(first),
                status=first.status,
                code=first.code,
            ) from second

    def _collect_cards(self, city_slug, city_name, type_code, on_progress):
        cards = []
        seen = set()
        total = None
        citation = None
        notice = None
        page = 1
        while len(cards) < self.max_spaces and page <= 20:
            self._report(on_progress, 0, 0, self._list_message(city_name, page))
            payload = self._get(
                "/v1/properties", self._list_params(city_slug, type_code, page)
            )
            if citation is None:
                citation = _citation(payload)
            if notice is None:
                notice = _notice(payload)
            rows, page_total, page_count = _list_payload(payload)
            if page_total is not None:
                total = page_total
            for row in rows:
                card = _card(row)
                if card is None or card["slug"] in seen:
                    continue
                seen.add(card["slug"])
                cards.append(card)
                if len(cards) >= self.max_spaces:
                    break
            if len(cards) >= self.max_spaces or len(rows) < PAGE_SIZE:
                break
            if page_count is not None and page >= page_count:
                break
            page += 1
        return cards, total, citation, notice

    def _read_details(self, cards, city_name, type_code, on_progress):
        workspaces = []
        skipped = 0
        failures = 0
        total = len(cards)
        for index, card in enumerate(cards, start=1):
            self._report(
                on_progress,
                index - 1,
                total,
                "Reading address {0} of {1}.".format(index, total),
            )
            detail, failed = self._read_detail(card["slug"])
            if failed:
                failures += 1
            workspace = _workspace(card, detail, city_name, type_code)
            if workspace is None:
                skipped += 1
            else:
                workspaces.append(workspace)
        self._report(
            on_progress,
            total,
            total,
            "Adding {0} workspaces to the map.".format(len(workspaces)),
        )
        return workspaces, skipped, failures

    def _read_detail(self, slug):
        path = "/v1/properties/{0}".format(urllib.parse.quote(slug, safe="-._"))
        try:
            payload = self._get(path, {"locale": LOCALE})
        except Cancelled:
            raise
        except CoworkingViewError:
            return None, True
        data = payload.get("data")
        if not isinstance(data, dict):
            return None, True
        return _detail_fields(data), False

    def _report(self, on_progress, done, total, message):
        self._check_cancel()
        if on_progress is not None:
            on_progress(done, total, message)

    def _list_message(self, city_name, page):
        if page == 1:
            return (
                "Fetching the workspace list for {0}. Each workspace is requested "
                "once for its address. The public API allows 120 requests a minute."
            ).format(city_name)
        return "Fetching the workspace list for {0} (page {1}).".format(city_name, page)

    def _list_params(self, city_slug, type_code, page):
        params = {
            "locale": LOCALE,
            "city": city_slug,
            "page": page,
            "pageSize": PAGE_SIZE,
            "sortBy": "date-desc",
        }
        if type_code:
            params["pricingOptionType"] = type_code
        return params

    def _get(self, path, params):
        url = self._url(path, params)
        for attempt in (1, 2):
            self._check_cancel()
            self._pace()
            status, headers, body = self._fetch(url)
            self._note_rate_limit(headers)
            if 200 <= status <= 299:
                return _decode(status, body)
            if attempt == 1 and _retryable(status):
                self._interruptible_sleep(_retry_wait(headers))
                continue
            raise _problem(status, body)
        raise CoworkingViewError(
            "The CoworkingView API request failed.",
            code="HTTP",
        )

    def _fetch(self, url):
        try:
            status, headers, body = self._request(url, _request_headers(), self.timeout)
        except Cancelled:
            raise
        except CoworkingViewError:
            raise
        except Exception as err:
            raise CoworkingViewError(
                "Could not reach the CoworkingView API at {0}. "
                "Check the network connection and try again.".format(self.base_url)
            ) from err
        return status, _header_map(headers), body

    def _pace(self):
        wait = 0.0
        if self._last is not None:
            wait = self.min_interval - (self._now() - self._last)
        if self._remaining is not None and self._remaining <= 0 and self._reset:
            wait = max(wait, min(float(self._reset), 60.0))
        if wait > 0:
            self._interruptible_sleep(wait)
        self._last = self._now()

    def _interruptible_sleep(self, seconds):
        if seconds <= 1:
            self._sleep(seconds)
            self._check_cancel()
            return
        remaining = seconds
        while remaining > 0:
            self._check_cancel()
            step = min(0.25, remaining)
            self._sleep(step)
            remaining -= step

    def _note_rate_limit(self, headers):
        self._remaining = _optional_float(headers.get("ratelimit-remaining"))
        self._reset = _optional_float(headers.get("ratelimit-reset"))

    def _check_cancel(self):
        if self._should_cancel is not None and self._should_cancel():
            raise Cancelled("Load cancelled.")

    def _url(self, path, params):
        pairs = [(key, value) for key, value in params.items() if value is not None]
        url = self.base_url + path
        if pairs:
            url += "?" + urllib.parse.urlencode(pairs)
        return url

    def _check_base_url(self):
        parsed = urllib.parse.urlparse(self.base_url)
        if parsed.scheme not in ("https", "http") or not parsed.netloc:
            raise CoworkingViewError(
                "COWORKINGVIEW_API_URL must be an http(s) URL.",
                code="BAD_BASE_URL",
            )

    @staticmethod
    def _check_city(city_slug):
        if not isinstance(city_slug, str) or not CITY_RE.fullmatch(city_slug):
            raise CoworkingViewError(
                "Choose a city from the list. The city id is not valid.",
                code="BAD_CITY",
            )

    @staticmethod
    def _check_type(type_code):
        if type_code is None or type_code == "":
            return None
        if type_code not in TYPE_LABELS:
            raise CoworkingViewError(
                "That workspace type is not a CoworkingView product code.",
                code="BAD_TYPE",
            )
        return type_code


def cities_from_bootstrap(payload):
    """Cities from ``GET /v1/geo/bootstrap``."""
    data = _data_dict(payload, "city list")
    cities = data.get("cities")
    if not isinstance(cities, list):
        raise CoworkingViewError(
            "The CoworkingView API returned an unexpected city list.",
            code="BAD_RESPONSE",
        )
    return _normalize_cities(cities)


def cities_from_rates(payload):
    """Published cities from ``GET /v1/market/rates``."""
    data = _data_dict(payload, "city list")
    rows = data.get("cities")
    if not isinstance(rows, list):
        raise CoworkingViewError(
            "The CoworkingView API returned an unexpected city list.",
            code="BAD_RESPONSE",
        )
    flat = []
    for item in rows:
        if not isinstance(item, dict):
            continue
        city = item.get("city") if isinstance(item.get("city"), dict) else {}
        flat.append(
            {
                "slug": city.get("slug"),
                "name": city.get("name"),
                "countryCode": item.get("countryCode"),
                "propertyCount": item.get("propertyCount"),
            }
        )
    return _normalize_cities(flat)


def _normalize_cities(rows):
    found = {}
    for row in rows:
        city = _city(row)
        if city is not None and city.slug not in found:
            found[city.slug] = city
    return tuple(sorted(found.values(), key=lambda city: (city.name.casefold(), city.slug)))


def _city(row):
    if not isinstance(row, dict):
        return None
    slug = row.get("slug")
    name = row.get("name")
    if not isinstance(slug, str) or not CITY_RE.fullmatch(slug):
        return None
    if not isinstance(name, str) or not name.strip():
        return None
    count = _optional_int(row.get("propertyCount"))
    if count == 0:
        return None
    country = row.get("countryCode")
    if not isinstance(country, str) or len(country.strip()) != 2:
        country = None
    else:
        country = country.strip().upper()
    return City(slug=slug, name=name.strip(), country_code=country, property_count=count)


def _data_dict(payload, what):
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        raise CoworkingViewError(
            "The CoworkingView API returned an unexpected {0}.".format(what),
            code="BAD_RESPONSE",
        )
    return data


def _list_payload(payload):
    rows = payload.get("data")
    if not isinstance(rows, list):
        raise CoworkingViewError(
            "The CoworkingView API returned an unexpected workspace list.",
            code="BAD_RESPONSE",
        )
    pagination = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
    pagination = pagination.get("pagination") if isinstance(pagination, dict) else None
    total = None
    page_count = None
    if isinstance(pagination, dict):
        total = _optional_int(pagination.get("total"))
        page_count = _optional_int(pagination.get("pageCount"))
    return rows, total, page_count


def _card(row):
    if not isinstance(row, dict):
        return None
    slug = row.get("slug")
    if not isinstance(slug, str) or not SLUG_RE.fullmatch(slug):
        return None
    city = row.get("city") if isinstance(row.get("city"), dict) else None
    coordinates = row.get("coordinates") if isinstance(row.get("coordinates"), dict) else None
    return {
        "slug": slug,
        "title": row.get("title"),
        "city": city,
        "coordinates": coordinates,
    }


def _detail_fields(data):
    options = []
    for option in data.get("pricingOptions") or []:
        if isinstance(option, dict) and isinstance(option.get("optionType"), str):
            options.append(option["optionType"])
    city = data.get("city") if isinstance(data.get("city"), dict) else None
    coordinates = data.get("coordinates") if isinstance(data.get("coordinates"), dict) else None
    return {
        "title": data.get("title"),
        "city": city,
        "coordinates": coordinates,
        "address": data.get("address"),
        "option_types": options,
        "webUrl": data.get("webUrl"),
    }


def _workspace(card, detail, city_name, type_code):
    source = detail or card
    coordinates = _coordinates(source) or _coordinates(card)
    if coordinates is None:
        return None
    lat, lng = coordinates
    name = _text(source.get("title")) or _text(card.get("title")) or card["slug"]
    city = _city_label(source) or _city_label(card) or city_name
    address = None
    kinds = format_types([type_code] if type_code else [])
    url = listing_url(card["slug"])
    if detail is not None:
        address = _text(detail.get("address"))
        from_detail = format_types(detail.get("option_types") or [])
        if from_detail:
            kinds = from_detail
        url = accepted_listing_url(detail.get("webUrl"), card["slug"])
    return Workspace(
        name=name,
        city=city,
        address=address,
        workspace_type=kinds,
        url=url,
        lat=lat,
        lng=lng,
        slug=card["slug"],
    )


def _coordinates(source):
    if not isinstance(source, dict):
        return None
    coordinates = source.get("coordinates")
    if not isinstance(coordinates, dict):
        return None
    lat = coordinates.get("lat")
    lng = coordinates.get("lng")
    if isinstance(lat, bool) or isinstance(lng, bool):
        return None
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        return None
    lat = float(lat)
    lng = float(lng)
    if not math.isfinite(lat) or not math.isfinite(lng):
        return None
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lng <= 180.0):
        return None
    # The places index uses 0,0 when a coordinate is unknown.
    if lat == 0.0 and lng == 0.0:
        return None
    return lat, lng


def _city_label(source):
    if not isinstance(source, dict):
        return None
    city = source.get("city")
    if not isinstance(city, dict):
        return None
    return _text(city.get("name"))


def _text(value):
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _citation(payload):
    meta = payload.get("meta") if isinstance(payload, dict) else None
    if not isinstance(meta, dict):
        return None
    citation = meta.get("citation")
    if isinstance(citation, dict):
        return _text(citation.get("text"))
    return _text(citation)


def _notice(payload):
    meta = payload.get("meta") if isinstance(payload, dict) else None
    if not isinstance(meta, dict):
        return None
    return _text(meta.get("catalogueNotice"))


def _optional_int(value):
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value


def _optional_float(value):
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _request_headers():
    return {"Accept": "application/json", "User-Agent": USER_AGENT}


def _header_map(headers):
    if not headers:
        return {}
    return {str(key).lower(): value for key, value in dict(headers).items()}


def _decode(status, body):
    try:
        text = body.decode("utf-8") if body else ""
        payload = json.loads(text) if text else None
    except (UnicodeDecodeError, ValueError) as err:
        raise CoworkingViewError(
            "The CoworkingView API returned a response that is not valid JSON.",
            status=status,
            code="BAD_RESPONSE",
        ) from err
    if not isinstance(payload, dict):
        raise CoworkingViewError(
            "The CoworkingView API returned a response that is not a JSON object.",
            status=status,
            code="BAD_RESPONSE",
        )
    return payload


def _problem(status, body):
    payload = {}
    if body:
        try:
            parsed = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            parsed = None
        if isinstance(parsed, dict):
            payload = parsed
    code = payload.get("code")
    if not isinstance(code, str) or not code:
        code = "HTTP_{0}".format(status)
    title = payload.get("title")
    if not isinstance(title, str) or not title:
        title = "HTTP {0}".format(status)
    detail = payload.get("detail") if isinstance(payload.get("detail"), str) else None
    if detail and len(detail) > 400:
        detail = detail[:400].rstrip() + "..."
    message = "The CoworkingView API returned {0} ({1}): {2}".format(status, code, title)
    if detail:
        message = "{0}. {1}".format(message, detail)
    return CoworkingViewError(message, status=status, code=code)


def _retryable(status):
    return status == 429 or 500 <= status <= 599


def _retry_wait(headers):
    retry_after = headers.get("retry-after")
    seconds = _seconds(retry_after, allow_date=True)
    if seconds is None:
        seconds = _seconds(headers.get("ratelimit-reset"), allow_date=False)
    if seconds is None:
        seconds = 2.0
    return min(max(0.0, seconds), MAX_RETRY_WAIT)


def _seconds(value, allow_date):
    if value is None:
        return None
    text = str(value).strip()
    try:
        return max(0.0, float(text))
    except ValueError:
        pass
    if not allow_date:
        return None
    try:
        when = parsedate_to_datetime(text)
    except (TypeError, ValueError, IndexError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    return max(0.0, (when - datetime.now(timezone.utc)).total_seconds())


def _urllib_request(url, headers, timeout):
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.headers, response.read()
    except urllib.error.HTTPError as err:
        try:
            raw = err.read()
        finally:
            err.close()
        return err.code, err.headers, raw
    except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError, OSError) as err:
        reason = getattr(err, "reason", err)
        host = urllib.parse.urlparse(url).netloc or DEFAULT_BASE_URL
        raise CoworkingViewError(
            "Could not reach the CoworkingView API at {0}. "
            "Check the network connection and try again. ({1})".format(host, reason)
        ) from err
