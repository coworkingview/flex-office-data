"""Regenerate spec/golden/*.csv from spec/fixtures/*.json.

This is the reference reading of SPEC.md. The Python, R and Rust packages
must produce the same rows from the same fixtures; their test suites compare
against these files. Standard library only.

    python3 spec/tools/make_golden.py
"""

from __future__ import annotations

import csv
import json
import re
from pathlib import Path

SPEC = Path(__file__).resolve().parent.parent
FIXTURES = SPEC / "fixtures"
GOLDEN = SPEC / "golden"

PRODUCT_ORDER = [
    "flex_desk",
    "fix_desk",
    "private_office",
    "exclusive_bereich",
    "day_pass",
    "meeting_room",
    "event_space",
    "virtual_office",
    "membership",
]
STAT_UNITS = {"day_pass": "day", "meeting_room": "hour", "event_space": "hour", "virtual_office": "month"}
WORKSPACE_PATH = {"en": "workspace", "es": "oficina", "de": "buero"}
LOW_CONFIDENCE_BELOW = 10


def snake(key: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", key).lower()


def amount(money):
    return None if money is None else money["amount"]


def product_key(product: str):
    if product in PRODUCT_ORDER:
        return (0, PRODUCT_ORDER.index(product), "")
    return (1, 0, product)


def is_stat(value) -> bool:
    return isinstance(value, dict) and "median" in value and "sampleSize" in value


def rate_rows(data: dict) -> list[dict]:
    rows = []
    for city in data["cities"]:
        base = {
            "city_slug": city["city"]["slug"],
            "city_name": city["city"]["name"],
            "country_code": city.get("countryCode"),
            "currency": city["currency"],
        }
        per_city = []
        monthly = city.get("figures") or city.get("byType") or []
        for item in monthly:
            per_city.append({
                **base,
                "product": item["optionType"],
                "unit": "month",
                "median": amount(item["median"]),
                "p25": amount(item.get("p25")),
                "p75": amount(item.get("p75")),
                "sample_size": item["sampleSize"],
                "property_count": item.get("propertyCount"),
                "operator_count": item.get("operatorCount"),
            })
        for key, value in city.items():
            if not is_stat(value):
                continue
            product = snake(key)
            per_city.append({
                **base,
                "product": product,
                "unit": STAT_UNITS.get(product),
                "median": amount(value["median"]),
                "p25": amount(value.get("p25")),
                "p75": amount(value.get("p75")),
                "sample_size": value["sampleSize"],
                "property_count": value.get("propertyCount"),
                "operator_count": value.get("operatorCount"),
            })
        rows.extend(per_city)
    for row in rows:
        row["low_confidence"] = row["sample_size"] < LOW_CONFIDENCE_BELOW
        row["as_of"] = data["asOf"]
    rows.sort(key=lambda r: (r["city_slug"], product_key(r["product"])))
    columns = ["city_slug", "city_name", "country_code", "currency", "product", "unit", "median", "p25", "p75",
               "sample_size", "property_count", "operator_count", "low_confidence", "as_of"]
    return [{c: r[c] for c in columns} for r in rows]


def city_rows(data: dict) -> list[dict]:
    rows = []
    for city in data["cities"]:
        rows.append({
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
            "as_of": data["asOf"],
        })
    for city in data.get("unpublished") or []:
        rows.append({
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
            "as_of": data["asOf"],
        })
    rows.sort(key=lambda r: (not r["published"], r["city_slug"]))
    return rows


def space_row(card: dict, locale: str) -> dict:
    market = card.get("marketPosition") or {}
    return {
        "slug": card["slug"],
        "title": card["title"],
        "city_slug": (card.get("city") or {}).get("slug"),
        "zone_slug": (card.get("zone") or {}).get("slug"),
        "operator_slug": (card.get("operator") or {}).get("slug"),
        "operator_name": (card.get("operator") or {}).get("name"),
        "country_code": card.get("countryCode"),
        "lat": (card.get("coordinates") or {}).get("lat"),
        "lng": (card.get("coordinates") or {}).get("lng"),
        "featured": card.get("featured"),
        "market_verdict": market.get("verdict"),
        "market_median": amount(market.get("median")),
        "market_sample_size": market.get("sampleSize"),
        "url": f"https://coworkingview.com/{locale}/{WORKSPACE_PATH[locale]}/{card['slug']}",
        "updated_at": card.get("updatedAt"),
    }


def pricing_rows(detail: dict) -> list[dict]:
    rows = []
    for option in detail.get("pricingOptions") or []:
        price = option.get("price")
        rows.append({
            "product": option["optionType"],
            "title": option["title"],
            "price": amount(price),
            "currency": None if price is None else price["currency"],
            "billing_period": option["billingPeriod"],
            "price_on_request": option["priceOnRequest"],
            "min_capacity": option.get("minCapacity"),
            "max_capacity": option.get("maxCapacity"),
        })
    return rows


def cell(value) -> str:
    if value is None:
        return ""
    if value is True:
        return "true"
    if value is False:
        return "false"
    return str(value)


def write(name: str, rows: list[dict]) -> None:
    GOLDEN.mkdir(exist_ok=True)
    with open(GOLDEN / name, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(rows[0].keys())
        for row in rows:
            writer.writerow([cell(v) for v in row.values()])
    print(f"{name}: {len(rows)} rows")


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def main() -> None:
    rates = load("market_rates.json")["data"]
    write("rates.csv", rate_rows(rates))
    write("cities.csv", city_rows(rates))
    write("spaces.csv", [space_row(c, "en") for c in load("properties_berlin.json")["data"]])
    write("space_pricing.csv", pricing_rows(load("property_detail.json")["data"]))


if __name__ == "__main__":
    main()
