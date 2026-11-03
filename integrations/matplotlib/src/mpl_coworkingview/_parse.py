"""Turn ``GET /v1/market/rates`` into Price Index rows.

The column names and the reading of ``figures``, ``byType`` and city-level
statistics are the ones in ``spec/SPEC.md`` section 3, the same reading as
``spec/tools/make_golden.py``. Cities under ``unpublished`` produce no rows.
``buildings`` and other catalogue fields are not copied onto the rows.
"""

from __future__ import annotations

import re
from typing import Any

from .exceptions import CoworkingViewError

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


class MarketRates:
    """Rows from one Price Index response, plus unpublished city slugs."""

    def __init__(self, rows: list[Row], unpublished: tuple[str, ...]) -> None:
        self.rows = rows
        self.unpublished = unpublished


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


def _slug_of(city: Any) -> str | None:
    if not isinstance(city, dict):
        return None
    inner = city.get("city")
    if not isinstance(inner, dict):
        return None
    slug = inner.get("slug")
    return slug if isinstance(slug, str) else None


def rate_rows(data: dict[str, Any]) -> list[Row]:
    """One row per published city and product.

    ``figures`` is used when it is present and non-empty; otherwise
    ``byType``. A city-level object that has ``median`` and ``sampleSize``
    (``dayPass``, ``meetingRoom``, and any later aggregate) becomes its own
    product. ``unit`` for those keys follows ``STAT_UNITS``.
    """
    rows: list[Row] = []
    for city in data["cities"]:
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
        row["as_of"] = data["asOf"]
    rows.sort(key=lambda row: (row["city_slug"], _product_key(row["product"])))
    return [{column: row[column] for column in RATE_COLUMNS} for row in rows]


def parse_market_rates(payload: Any) -> MarketRates:
    """Parse a ``GET /v1/market/rates`` JSON envelope."""
    if not isinstance(payload, dict):
        raise CoworkingViewError("The Price Index response is not a JSON object.")
    data = payload.get("data")
    if not isinstance(data, dict):
        raise CoworkingViewError("The Price Index response has no data object.")
    try:
        rows = rate_rows(data)
        unpublished: list[str] = []
        for item in data.get("unpublished") or []:
            slug = _slug_of(item)
            if slug:
                unpublished.append(slug)
    except (KeyError, TypeError) as err:
        raise CoworkingViewError(
            f"The Price Index response did not match the expected shape ({err})."
        ) from err
    return MarketRates(rows, tuple(unpublished))
