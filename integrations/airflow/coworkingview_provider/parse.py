"""Turn a ``GET /v1/market/rates`` payload into Price Index rows.

This is the provider's reading of ``spec/SPEC.md`` section 3, the same
reading as the Python client and the Meltano tap. It does no I/O. Cities
under ``unpublished`` produce no rows. ``buildings`` and any other catalogue
fields on the city object are not copied onto the rows.
"""

from __future__ import annotations

import re
from typing import Any

from coworkingview_provider.exceptions import CoworkingViewError

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

LOCALES: tuple[str, ...] = ("en", "es", "de")
#: ``VES`` is accepted by the API and rejected with HTTP 400 where it has no
#: conversion rate. Pass it through; do not hide that response.
CURRENCIES: tuple[str, ...] = ("EUR", "GBP", "USD", "CHF", "AED", "VES")

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


def _slug_of(city: Any) -> str | None:
    if not isinstance(city, dict):
        return None
    inner = city.get("city")
    if not isinstance(inner, dict):
        return None
    slug = inner.get("slug")
    return slug if isinstance(slug, str) else None


def rate_rows(data: Row) -> list[Row]:
    """One row per published city and product.

    ``figures`` is used when it is present and non-empty; otherwise
    ``byType``. A city-level object that has ``median`` and ``sampleSize``
    (``dayPass``, ``meetingRoom``, and any later aggregate) becomes its own
    product.
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


def city_rates_document(
    payload: Row,
    *,
    city: str,
    locale: str,
    product: str | None = None,
) -> dict[str, Any]:
    """JSON document for one city's rates, with the CC BY attribution kept.

    Each row carries ``attribution`` and ``license`` as well as the document,
    so a downstream task that keeps only ``rates`` still has the licence.
    """
    data = payload.get("data")
    if not isinstance(data, dict):
        raise CoworkingViewError("The Price Index response has no data object.")
    meta = payload.get("meta")
    meta = meta if isinstance(meta, dict) else {}
    try:
        rows = rate_rows(data)
    except (KeyError, TypeError) as err:
        raise CoworkingViewError(
            f"The Price Index response did not match the expected shape ({err})."
        ) from err

    matched = [row for row in rows if row["city_slug"] == city]
    if not matched:
        unpublished = data.get("unpublished") or []
        slugs = [_slug_of(item) for item in unpublished] if isinstance(unpublished, list) else []
        if city in slugs:
            raise CoworkingViewError(
                f"{city} is listed in the Price Index but is unpublished: "
                "it does not have enough prices for a rate yet."
            )
        raise CoworkingViewError(f"No published Price Index rates for city {city!r}.")

    available = [row["product"] for row in matched]
    if product is not None:
        matched = [row for row in matched if row["product"] == product]
        if not matched:
            raise CoworkingViewError(
                f"No {product} rate for city {city!r}. Published products: {', '.join(available)}."
            )

    attribution = data.get("attribution")
    license_url = data.get("licenseUrl")
    attribution = attribution if isinstance(attribution, str) else None
    license_url = license_url if isinstance(license_url, str) else None
    stamped = [{**row, "attribution": attribution, "license": license_url} for row in matched]
    first = stamped[0]
    contract = meta.get("contractVersion")
    return {
        "city": city,
        "city_name": first["city_name"],
        "country_code": first["country_code"],
        "currency": first["currency"],
        "locale": locale,
        "as_of": first["as_of"],
        "attribution": attribution,
        "license": license_url,
        "contract_version": contract if isinstance(contract, str) else None,
        "rates": stamped,
    }
