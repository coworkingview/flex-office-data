"""Turn CoworkingView API payloads into stream records.

This is the tap's reading of ``spec/SPEC.md`` sections 3 and 5: Price Index
rows (one per published city and product) and catalogue-search rows (one per
listing). It does no I/O. Photos, descriptions and logos are not copied onto
the records.
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
LOW_CONFIDENCE_BELOW = 10
SITE_URL = "https://coworkingview.com"
LISTING_PATH = {"en": "workspace", "es": "oficina", "de": "buero"}

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
    """``camelCase`` to ``snake_case`` (``dayPass`` to ``day_pass``)."""
    return re.sub(r"(?<!^)(?=[A-Z])", "_", key).lower()


def amount(money: Any) -> Any:
    """``money["amount"]``, or ``None`` when the money object is absent."""
    if money is None:
        return None
    return money["amount"]


def _product_key(product: str) -> tuple[int, int, str]:
    if product in PRODUCT_ORDER:
        return (0, PRODUCT_ORDER.index(product), "")
    return (1, 0, product)


def _is_stat(value: Any) -> bool:
    return isinstance(value, dict) and "median" in value and "sampleSize" in value


def _sub(obj: Any, key: str) -> Any:
    return obj.get(key) if isinstance(obj, dict) else None


def listing_url(slug: str, locale: str = "en") -> str:
    """Public listing page on coworkingview.com."""
    segment = LISTING_PATH[locale]
    return f"{SITE_URL}/{locale}/{segment}/{slug}"


def rate_rows(data: Row) -> list[Row]:
    """Price Index rows: one per published city and product.

    Cities listed under ``unpublished`` produce no rows. ``figures`` is used
    when present; otherwise ``byType``. Extra city-level statistics such as
    ``dayPass`` and ``meetingRoom`` become their own products.
    """
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
            if not _is_stat(value):
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
    rows.sort(key=lambda row: (row["city_slug"], _product_key(row["product"])))
    return [{column: row[column] for column in RATE_COLUMNS} for row in rows]


def workspace_row(card: Row, locale: str = "en") -> Row:
    """One catalogue-search row. Images, excerpts and logos are left out."""
    market = card.get("marketPosition") or {}
    coordinates = card.get("coordinates")
    return {
        "slug": card["slug"],
        "title": card["title"],
        "city_slug": _sub(card.get("city"), "slug"),
        "zone_slug": _sub(card.get("zone"), "slug"),
        "operator_slug": _sub(card.get("operator"), "slug"),
        "operator_name": _sub(card.get("operator"), "name"),
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
