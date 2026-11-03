#!/usr/bin/env python3
"""Write sql/coworkingview--0.1.0.sql from the open dataset in this repo.

The Ruby client and the Airflow provider both read GET /v1/market/rates.
Their tests lock that response to spec/fixtures/market_rates.json and to the
tidy tables spec/golden/rates.csv and spec/golden/cities.csv. This script
copies those tables and the attribution block from the same fixture. It does
not compute or fill in a price.

    python3 tools/build_sql.py
    python3 tools/build_sql.py --check
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXTENSION_DIR = HERE.parent
REPO_ROOT = EXTENSION_DIR.parents[1]
FIXTURE = REPO_ROOT / "spec" / "fixtures" / "market_rates.json"
RATES = REPO_ROOT / "spec" / "golden" / "rates.csv"
CITIES = REPO_ROOT / "spec" / "golden" / "cities.csv"
SQL_PATH = EXTENSION_DIR / "sql" / "coworkingview--0.1.0.sql"

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
TEXT_COLUMNS = {"city_slug", "city_name", "country_code", "currency", "product", "unit", "as_of"}
BOOL_COLUMNS = {"low_confidence", "published"}
INT_COLUMNS = {"sample_size", "property_count", "operator_count"}


def sql_literal(column: str, raw: str) -> str:
    if raw == "":
        return "NULL"
    if column in BOOL_COLUMNS:
        if raw not in ("true", "false"):
            raise SystemExit(f"{column}: expected true or false, got {raw!r}")
        return raw
    if column in TEXT_COLUMNS:
        return "'" + raw.replace("'", "''") + "'"
    if column in INT_COLUMNS:
        if not raw.isdigit():
            raise SystemExit(f"{column}: expected an integer, got {raw!r}")
        return raw
    # Money figures are written exactly as the golden file records them.
    if not raw.replace(".", "", 1).isdigit():
        raise SystemExit(f"{column}: expected a number, got {raw!r}")
    return raw


def load_csv(path: Path, columns: list[str]) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != columns:
            raise SystemExit(f"{path.name}: columns {reader.fieldnames} != {columns}")
        return list(reader)


def values_sql(rows: list[dict[str, str]], columns: list[str]) -> str:
    lines = []
    for row in rows:
        values = ", ".join(sql_literal(column, row[column]) for column in columns)
        lines.append(f"    ({values})")
    return ",\n".join(lines)


def build() -> str:
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))["data"]
    rates = load_csv(RATES, RATE_COLUMNS)
    cities = load_csv(CITIES, CITY_COLUMNS)
    if not rates or not cities:
        raise SystemExit("the open dataset snapshot is empty")

    as_of = payload["asOf"]
    for label, rows in (("rates", rates), ("cities", cities)):
        for row in rows:
            if row["as_of"] != as_of:
                raise SystemExit(f"{label} row {row['city_slug']} as_of does not match the fixture")
            if "low_confidence" in row:
                expected = "true" if int(row["sample_size"]) < 10 else "false"
                if row["low_confidence"] != expected:
                    raise SystemExit(
                        f"{row['city_slug']} {row['product']}: low_confidence {row['low_confidence']} "
                        f"does not match sample_size {row['sample_size']}"
                    )

    attribution = payload["attribution"].replace("'", "''")
    license_name = payload["license"].replace("'", "''")
    license_url = payload["licenseUrl"].replace("'", "''")
    scope = payload["scope"].replace("'", "''")
    rate_values = values_sql(rates, RATE_COLUMNS)
    city_values = values_sql(cities, CITY_COLUMNS)
    rate_column_list = ", ".join(RATE_COLUMNS)
    city_column_list = ", ".join(CITY_COLUMNS)

    return f"""-- CoworkingView Price Index snapshot for PostgreSQL.
-- Rows copied from spec/golden/rates.csv and spec/golden/cities.csv, which
-- are generated from spec/fixtures/market_rates.json (recorded
-- GET /v1/market/rates). Attribution, licence and scope are the fixture's
-- own fields. Regenerate with tools/build_sql.py. Do not type prices in.

CREATE TABLE coworkingview_about (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    as_of timestamptz NOT NULL,
    attribution text NOT NULL,
    license text NOT NULL,
    license_url text NOT NULL,
    scope text NOT NULL
);

COMMENT ON TABLE coworkingview_about IS
    'Licence and attribution for the embedded CoworkingView Price Index snapshot';

CREATE TABLE coworkingview_price_index (
    city_slug text NOT NULL,
    city_name text NOT NULL,
    country_code text,
    currency text NOT NULL,
    product text NOT NULL,
    unit text,
    median numeric NOT NULL,
    p25 numeric,
    p75 numeric,
    sample_size integer NOT NULL,
    property_count integer,
    operator_count integer,
    low_confidence boolean NOT NULL,
    as_of timestamptz NOT NULL,
    PRIMARY KEY (city_slug, product)
);

COMMENT ON TABLE coworkingview_price_index IS
    'Snapshot of the CoworkingView Price Index, one row per city and product (CC BY 4.0)';

CREATE TABLE coworkingview_cities (
    city_slug text PRIMARY KEY,
    city_name text NOT NULL,
    country_code text,
    currency text,
    published boolean NOT NULL,
    property_count integer,
    operator_count integer,
    entry_median numeric,
    entry_min numeric,
    entry_max numeric,
    p25 numeric,
    p75 numeric,
    sample_size integer,
    as_of timestamptz NOT NULL
);

COMMENT ON TABLE coworkingview_cities IS
    'Snapshot of CoworkingView Price Index cities, including unpublished cities (CC BY 4.0)';

INSERT INTO coworkingview_about (
    singleton, as_of, attribution, license, license_url, scope
) VALUES (
    true,
    '{as_of}',
    '{attribution}',
    '{license_name}',
    '{license_url}',
    '{scope}'
);

INSERT INTO coworkingview_price_index ({rate_column_list}) VALUES
{rate_values};

INSERT INTO coworkingview_cities ({city_column_list}) VALUES
{city_values};

CREATE VIEW coworkingview_rates AS
SELECT
    price_index.city_slug,
    price_index.city_name,
    price_index.country_code,
    price_index.currency,
    price_index.product,
    price_index.unit,
    price_index.median,
    price_index.p25,
    price_index.p75,
    price_index.sample_size,
    price_index.property_count,
    price_index.operator_count,
    price_index.low_confidence,
    price_index.as_of,
    about.attribution,
    about.license,
    about.license_url
FROM coworkingview_price_index AS price_index
CROSS JOIN coworkingview_about AS about;

COMMENT ON VIEW coworkingview_rates IS
    'CoworkingView Price Index snapshot. attribution is the CC BY 4.0 credit; keep it with any figure you republish.';

-- SQL-standard bodies are parsed at CREATE EXTENSION time, so the table
-- references are pinned by OID and stay valid if the extension is relocated.
CREATE FUNCTION coworkingview_rate(city text, product_code text)
RETURNS numeric
LANGUAGE sql
STABLE
PARALLEL SAFE
STRICT
BEGIN ATOMIC
    SELECT median
    FROM coworkingview_price_index AS price_index
    WHERE price_index.city_slug = lower(btrim(city))
      AND price_index.product = lower(btrim(product_code));
END;

CREATE FUNCTION coworkingview_rate(city text)
RETURNS numeric
LANGUAGE sql
STABLE
PARALLEL SAFE
STRICT
BEGIN ATOMIC
    SELECT median
    FROM coworkingview_price_index AS price_index
    WHERE price_index.city_slug = lower(btrim(city))
      AND price_index.product = 'flex_desk';
END;

COMMENT ON FUNCTION coworkingview_rate(text, text) IS
    'Median from the embedded Price Index for a city slug and product (flex_desk, fix_desk, private_office, day_pass, meeting_room). NULL when that row is not in the snapshot.';

COMMENT ON FUNCTION coworkingview_rate(text) IS
    'Flex-desk median from the embedded Price Index for a city slug. NULL when the city is not in the snapshot.';

CREATE FUNCTION coworkingview_attribution()
RETURNS text
LANGUAGE sql
STABLE
PARALLEL SAFE
BEGIN ATOMIC
    SELECT attribution FROM coworkingview_about;
END;

COMMENT ON FUNCTION coworkingview_attribution() IS
    'CC BY 4.0 attribution for the embedded CoworkingView Price Index snapshot. Keep it with any figure you republish.';

GRANT SELECT ON coworkingview_about TO PUBLIC;
GRANT SELECT ON coworkingview_price_index TO PUBLIC;
GRANT SELECT ON coworkingview_cities TO PUBLIC;
GRANT SELECT ON coworkingview_rates TO PUBLIC;
"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if sql/coworkingview--0.1.0.sql does not match the open dataset",
    )
    args = parser.parse_args()
    sql = build()
    if not sql.endswith("\n"):
        sql += "\n"
    if args.check:
        current = SQL_PATH.read_text(encoding="utf-8") if SQL_PATH.exists() else ""
        if current != sql:
            raise SystemExit(f"{SQL_PATH} is out of date. Run python3 tools/build_sql.py")
        print(f"{SQL_PATH.name} matches {RATES.name} and {CITIES.name}")
        return
    SQL_PATH.parent.mkdir(parents=True, exist_ok=True)
    SQL_PATH.write_text(sql, encoding="utf-8")
    print(f"wrote {SQL_PATH}")


if __name__ == "__main__":
    main()
