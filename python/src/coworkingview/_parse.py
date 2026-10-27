"""Pure functions turning API payloads into row dicts.

This module is the Python reading of SPEC sections 3-6 and must stay
row-for-row identical to ``spec/tools/make_golden.py``. It does no I/O and
knows nothing about pandas; :mod:`coworkingview._frames` types the rows.
"""

from __future__ import annotations

import re
from typing import Any

Row = dict[str, Any]

PRODUCT_ORDER: tuple[str, ...] = (
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
STAT_UNITS: dict[str, str] = {
    "day_pass": "day",
    "meeting_room": "hour",
    "event_space": "hour",
    "virtual_office": "month",
}
WORKSPACE_PATH: dict[str, str] = {"en": "workspace", "es": "oficina", "de": "buero"}
SITE_URL = "https://coworkingview.com"
LOW_CONFIDENCE_BELOW = 10

RATE_COLUMNS: tuple[str, ...] = (
    "city_slug",
    "city_name",
    "country_code",
    "currency",
    "product",
    "unit",
    "median",
    "p25",
    "p75",
    "sample_size",
    "property_count",
    "operator_count",
    "low_confidence",
    "as_of",
)


def snake(key: str) -> str:
    """``camelCase`` to ``snake_case`` (``dayPass`` -> ``day_pass``)."""
    return re.sub(r"(?<!^)(?=[A-Z])", "_", key).lower()


def amount(money: Any) -> Any:
    """``money["amount"]``, or ``None`` when the money object is absent."""
    return None if money is None else money["amount"]


def product_key(product: str) -> tuple[int, int, str]:
    """Sort key: the documented product order, then unknown products alphabetically."""
    if product in PRODUCT_ORDER:
        return (0, PRODUCT_ORDER.index(product), "")
    return (1, 0, product)


def is_stat(value: Any) -> bool:
    """Whether a city-level value is a price statistic (has ``median`` and ``sampleSize``)."""
    return isinstance(value, dict) and "median" in value and "sampleSize" in value


def _sub(obj: Any, key: str) -> Any:
    """``obj[key]`` when ``obj`` is a dict, else ``None``."""
    return obj.get(key) if isinstance(obj, dict) else None


def rate_rows(data: Row) -> list[Row]:
    """Rows of ``rates()``: one per published city x product (SPEC section 3)."""
    rows: list[Row] = []
    for city in data.get("cities") or []:
        base = {
            "city_slug": city["city"]["slug"],
            "city_name": city["city"]["name"],
            "country_code": city.get("countryCode"),
            "currency": city["currency"],
        }
        for item in city.get("figures") or city.get("byType") or []:
            rows.append(
                {
                    **base,
                    "product": item["optionType"],
                    "unit": "month",
                    "median": amount(item["median"]),
                    "p25": amount(item.get("p25")),
                    "p75": amount(item.get("p75")),
                    "sample_size": item["sampleSize"],
                    "property_count": item.get("propertyCount"),
                    "operator_count": item.get("operatorCount"),
                }
            )
        for key, value in city.items():
            if not is_stat(value):
                continue
            product = snake(key)
            rows.append(
                {
                    **base,
                    "product": product,
                    "unit": STAT_UNITS.get(product),
                    "median": amount(value["median"]),
                    "p25": amount(value.get("p25")),
                    "p75": amount(value.get("p75")),
                    "sample_size": value["sampleSize"],
                    "property_count": value.get("propertyCount"),
                    "operator_count": value.get("operatorCount"),
                }
            )
    for row in rows:
        row["low_confidence"] = row["sample_size"] < LOW_CONFIDENCE_BELOW
        row["as_of"] = data.get("asOf")
    rows.sort(key=lambda r: (r["city_slug"], product_key(r["product"])))
    return [{c: r[c] for c in RATE_COLUMNS} for r in rows]


def city_rows(data: Row) -> list[Row]:
    """Rows of ``cities()``: published cities first, then unpublished (SPEC section 4)."""
    as_of = data.get("asOf")
    rows: list[Row] = []
    for city in data.get("cities") or []:
        rows.append(
            {
                "city_slug": city["city"]["slug"],
                "city_name": city["city"]["name"],
                "country_code": city.get("countryCode"),
                "currency": city["currency"],
                "published": True,
                "property_count": city.get("propertyCount"),
                "operator_count": city.get("operatorCount"),
                "entry_median": amount(city.get("entryMedian")),
                "entry_min": amount(city.get("entryMin")),
                "entry_max": amount(city.get("entryMax")),
                "p25": amount(city.get("p25")),
                "p75": amount(city.get("p75")),
                "sample_size": city.get("sampleSize"),
                "as_of": as_of,
            }
        )
    for city in data.get("unpublished") or []:
        rows.append(
            {
                "city_slug": city["city"]["slug"],
                "city_name": city["city"]["name"],
                "country_code": city.get("countryCode"),
                "currency": city.get("currency"),
                "published": False,
                "property_count": None,
                "operator_count": None,
                "entry_median": None,
                "entry_min": None,
                "entry_max": None,
                "p25": None,
                "p75": None,
                "sample_size": None,
                "as_of": as_of,
            }
        )
    rows.sort(key=lambda r: (not r["published"], r["city_slug"]))
    return rows


def listing_url(slug: str, locale: str) -> str:
    """Public listing page of a space on coworkingview.com."""
    return f"{SITE_URL}/{locale}/{WORKSPACE_PATH[locale]}/{slug}"


def space_row(card: Row, locale: str) -> Row:
    """One ``spaces()`` row from a catalogue card (SPEC section 5)."""
    market = card.get("marketPosition") or {}
    operator = card.get("operator")
    coordinates = card.get("coordinates")
    return {
        "slug": card["slug"],
        "title": card["title"],
        "city_slug": _sub(card.get("city"), "slug"),
        "zone_slug": _sub(card.get("zone"), "slug"),
        "operator_slug": _sub(operator, "slug"),
        "operator_name": _sub(operator, "name"),
        "country_code": card.get("countryCode"),
        "lat": _sub(coordinates, "lat"),
        "lng": _sub(coordinates, "lng"),
        "featured": card.get("featured"),
        "market_verdict": market.get("verdict"),
        "market_median": amount(market.get("median")),
        "market_sample_size": market.get("sampleSize"),
        "url": listing_url(card["slug"], locale),
        "updated_at": card.get("updatedAt"),
    }


def pricing_rows(detail: Row) -> list[Row]:
    """Rows of the ``space()`` pricing table: one per pricing option (SPEC section 6)."""
    rows: list[Row] = []
    for option in detail.get("pricingOptions") or []:
        price = option.get("price")
        rows.append(
            {
                "product": option["optionType"],
                "title": option["title"],
                "price": amount(price),
                "currency": None if price is None else price["currency"],
                "billing_period": option["billingPeriod"],
                "price_on_request": option["priceOnRequest"],
                "min_capacity": option.get("minCapacity"),
                "max_capacity": option.get("maxCapacity"),
            }
        )
    return rows


def space_fields(detail: Row, locale: str) -> Row:
    """Scalar fields of ``space()``: the card fields plus address, capacity, amenities."""
    fields = space_row(detail, locale)
    web_url: str | None = detail.get("webUrl")
    if web_url:
        fields["url"] = web_url
    fields["address"] = detail.get("address")
    capacity = detail.get("capacity")
    fields["capacity"] = capacity if isinstance(capacity, int) else None
    amenities = detail.get("amenities") or []
    fields["amenities"] = tuple(str(a) for a in amenities)
    return fields
