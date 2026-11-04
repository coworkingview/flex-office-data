#!/usr/bin/env python3
"""Write the bundled Price Index snapshot used by the Clojure library.

Rows come from spec/golden/rates.csv and spec/golden/cities.csv. Attribution,
licence and scope come from spec/fixtures/market_rates.json, the recorded
GET /v1/market/rates response those tables are generated from. This script
copies those values. It does not compute or fill in a price.

    python3 integrations/clojure/tools/build_snapshot.py
    python3 integrations/clojure/tools/build_snapshot.py --check
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from decimal import Decimal
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLOJURE_DIR = HERE.parent
DATA_PATH = CLOJURE_DIR / "resources" / "coworkingview" / "price-index.edn"
REPO_ROOT = CLOJURE_DIR.parents[1]
FIXTURE = REPO_ROOT / "spec" / "fixtures" / "market_rates.json"
RATES = REPO_ROOT / "spec" / "golden" / "rates.csv"
CITIES = REPO_ROOT / "spec" / "golden" / "cities.csv"

RATE_COLUMNS = [
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
]
CITY_COLUMNS = [
    "city_slug",
    "city_name",
    "country_code",
    "currency",
    "published",
    "property_count",
    "operator_count",
    "entry_median",
    "entry_min",
    "entry_max",
    "p25",
    "p75",
    "sample_size",
    "as_of",
]
TEXT_COLUMNS = {
    "city_slug",
    "city_name",
    "country_code",
    "currency",
    "product",
    "unit",
    "as_of",
}
BOOL_COLUMNS = {"low_confidence", "published"}
INTEGER = re.compile(r"-?\d+")
DECIMAL = re.compile(r"-?\d+\.\d+")


def parse_number(column: str, raw: str):
    if INTEGER.fullmatch(raw):
        return int(raw)
    if DECIMAL.fullmatch(raw):
        rendered = json.dumps(float(raw))
        if Decimal(rendered) != Decimal(raw):
            raise SystemExit(
                f"{column}: refusing to rewrite {raw!r} as a number {rendered}"
            )
        return float(raw)
    raise SystemExit(f"{column}: expected a number, got {raw!r}")


def cell(column: str, raw: str):
    if raw == "":
        return None
    if column in BOOL_COLUMNS:
        if raw not in ("true", "false"):
            raise SystemExit(f"{column}: expected true or false, got {raw!r}")
        return raw == "true"
    if column in TEXT_COLUMNS:
        return raw
    return parse_number(column, raw)


def read_table(path: Path, columns: list[str]) -> list[dict]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != columns:
            raise SystemExit(
                f"{path}: expected columns {columns}, got {reader.fieldnames}"
            )
        rows = []
        for line_number, record in enumerate(reader, start=2):
            row = {}
            for column in columns:
                if column not in record:
                    raise SystemExit(f"{path}:{line_number}: missing {column}")
                row[column] = cell(column, record[column])
            rows.append(row)
        return rows


def build_payload() -> dict:
    fixture = json.loads(FIXTURE.read_text())
    data = fixture["data"]
    for key in ("asOf", "license", "licenseUrl", "attribution", "scope"):
        if not data.get(key):
            raise SystemExit(f"fixture is missing data.{key}")
    rates = read_table(RATES, RATE_COLUMNS)
    cities = read_table(CITIES, CITY_COLUMNS)
    if not rates or not cities:
        raise SystemExit("golden tables are empty")
    as_of = data["asOf"]
    for label, rows in (("rates", rates), ("cities", cities)):
        for row in rows:
            if row["as_of"] != as_of:
                raise SystemExit(
                    f"{label}: as_of {row['as_of']!r} does not match fixture {as_of!r}"
                )
    city_slugs = {row["city_slug"] for row in cities}
    for row in rates:
        if row["city_slug"] not in city_slugs:
            raise SystemExit(f"rate city {row['city_slug']!r} is not in cities.csv")
        if row["median"] is None:
            raise SystemExit(f"{row['city_slug']} {row['product']}: median is empty")
    return {
        "as_of": as_of,
        "license": data["license"],
        "license_url": data["licenseUrl"],
        "attribution": data["attribution"],
        "scope": data["scope"],
        "source": (
            "Rows copied from spec/golden/rates.csv and spec/golden/cities.csv, "
            "generated from spec/fixtures/market_rates.json "
            "(GET /v1/market/rates). Attribution, licence and scope are that "
            "response's own fields."
        ),
        "rates": rates,
        "cities": cities,
    }


def edn_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return '"' + escaped + '"'


def edn_value(value, indent: int) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return edn_string(value)
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        rendered = json.dumps(value)
        if Decimal(rendered) != Decimal(str(value)):
            raise SystemExit(f"refusing to emit inexact float {value!r}")
        return rendered
    if isinstance(value, list):
        if not value:
            return "[]"
        pad = " " * indent
        inner = " " * (indent + 1)
        lines = [inner + edn_value(item, indent + 1) for item in value]
        return "[\n" + "\n".join(lines) + "\n" + pad + "]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        pad = " " * indent
        inner = " " * (indent + 1)
        lines = []
        for key, item in value.items():
            lines.append(inner + ":" + key + " " + edn_value(item, indent + 1))
        return "{\n" + "\n".join(lines) + "\n" + pad + "}"
    raise SystemExit(f"cannot encode {type(value).__name__}")


def render(payload: dict) -> str:
    header = (
        ";; Bundled CoworkingView Price Index snapshot.\n"
        ";; Rows are copied from spec/golden/rates.csv and spec/golden/cities.csv.\n"
        ";; Attribution, licence and scope are copied from spec/fixtures/market_rates.json.\n"
        ";; Regenerate with tools/build_snapshot.py. Do not type figures in by hand.\n"
    )
    return header + edn_value(payload, 0) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(build_payload())
    if args.check:
        current = DATA_PATH.read_text() if DATA_PATH.exists() else ""
        if current != text:
            print(
                "resources/coworkingview/price-index.edn does not match the golden tables",
                file=sys.stderr,
            )
            return 1
        return 0
    DATA_PATH.parent.mkdir(parents=True, exist_ok=True)
    DATA_PATH.write_text(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
