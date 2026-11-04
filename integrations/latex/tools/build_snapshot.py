#!/usr/bin/env python3
"""Build the LaTeX package rates snapshot from the open dataset.

Rows are copied from spec/golden/rates.csv. The snapshot date and the
CC BY 4.0 licence come from spec/fixtures/market_rates.json, the recorded
GET /v1/market/rates response those tables are generated from. This script
copies the figures. It does not compute or fill in a price.

    python3 integrations/latex/tools/build_snapshot.py
    python3 integrations/latex/tools/build_snapshot.py --check
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
LATEX_DIR = HERE.parent
SNAPSHOT = LATEX_DIR / "coworkingview-rates.csv"
REPO_ROOT = LATEX_DIR.parents[1]
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


def read_table(path: Path, columns: list[str]) -> tuple[str, list[dict[str, str]]]:
    raw = path.read_text(encoding="utf-8")
    if "\r" in raw:
        raise SystemExit(f"{path}: expected LF line endings")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != columns:
            raise SystemExit(
                f"{path}: expected columns {columns}, got {reader.fieldnames}"
            )
        rows = []
        for line_number, record in enumerate(reader, start=2):
            row = {}
            for column in columns:
                if column not in record or record[column] is None:
                    raise SystemExit(f"{path}:{line_number}: missing {column}")
                row[column] = record[column]
            rows.append(row)
    if not raw.endswith("\n"):
        raw += "\n"
    return raw, rows


def build_text() -> str:
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    data = fixture["data"]
    for key in ("asOf", "license", "licenseUrl", "attribution", "scope"):
        if not data.get(key):
            raise SystemExit(f"fixture is missing data.{key}")
    if data["license"] != "CC-BY-4.0":
        raise SystemExit(
            f"fixture license is {data['license']!r}, expected 'CC-BY-4.0'"
        )
    as_of = data["asOf"]
    raw, rates = read_table(RATES, RATE_COLUMNS)
    _, cities = read_table(CITIES, CITY_COLUMNS)
    if not rates or not cities:
        raise SystemExit("golden tables are empty")
    city_slugs = {row["city_slug"] for row in cities}
    published = {
        row["city_slug"] for row in cities if row["published"] == "true"
    }
    seen: list[str] = []
    for row in rates:
        if row["as_of"] != as_of:
            raise SystemExit(
                f"rates: as_of {row['as_of']!r} does not match fixture {as_of!r}"
            )
        if row["city_slug"] not in city_slugs:
            raise SystemExit(f"rate city {row['city_slug']!r} is not in cities.csv")
        if row["median"] == "":
            raise SystemExit(f"{row['city_slug']} {row['product']}: median is empty")
        if row["currency"] == "" or row["unit"] == "":
            raise SystemExit(
                f"{row['city_slug']} {row['product']}: currency or unit is empty"
            )
        if row["city_slug"] not in seen:
            seen.append(row["city_slug"])
    for row in cities:
        if row["as_of"] != as_of:
            raise SystemExit(
                f"cities: as_of {row['as_of']!r} does not match fixture {as_of!r}"
            )
    missing = published - set(seen)
    if missing:
        raise SystemExit(
            "published cities with no rate row: " + ", ".join(sorted(missing))
        )
    # The body is the golden file itself. Comments carry the date and licence.
    preamble = (
        f"# snapshot: {as_of}\n"
        "# source: spec/golden/rates.csv, generated from spec/fixtures/market_rates.json\n"
        "# license: CC BY 4.0\n"
        "# Figures are copied, not recomputed.\n"
    )
    return preamble + raw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = build_text()
    if args.check:
        current = SNAPSHOT.read_text(encoding="utf-8") if SNAPSHOT.exists() else ""
        if current != text:
            print(
                "coworkingview-rates.csv does not match the golden rates table",
                file=sys.stderr,
            )
            return 1
        return 0
    SNAPSHOT.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
