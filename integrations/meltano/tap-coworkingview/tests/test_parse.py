"""Parser output matches the shared golden files."""

from __future__ import annotations

import csv
import json
from pathlib import Path

from tap_coworkingview.parse import rate_rows, workspace_row
from tests.support import FIXTURES, GOLDEN

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
SPACE_COLUMNS = [
    "slug",
    "title",
    "city_slug",
    "zone_slug",
    "operator_slug",
    "operator_name",
    "country_code",
    "lat",
    "lng",
    "featured",
    "market_verdict",
    "market_median",
    "market_sample_size",
    "url",
    "updated_at",
]


def _cell(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return str(value)


def _golden(name: str) -> list[dict[str, str]]:
    with (GOLDEN / name).open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def _fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def test_rate_rows_match_golden() -> None:
    payload = _fixture("market_rates.json")
    rows = rate_rows(payload["data"])
    expected = _golden("rates.csv")
    assert [_cell(row[column]) for row in rows for column in RATE_COLUMNS] == [
        record[column] for record in expected for column in RATE_COLUMNS
    ]
    assert [row["product"] for row in rows if row["city_slug"] == "berlin"] == [
        "flex_desk",
        "fix_desk",
        "private_office",
        "day_pass",
        "meeting_room",
    ]


def test_workspace_rows_match_golden() -> None:
    payload = _fixture("properties_berlin.json")
    rows = [workspace_row(card) for card in payload["data"]]
    expected = _golden("spaces.csv")
    assert [[_cell(row[column]) for column in SPACE_COLUMNS] for row in rows] == [
        [record[column] for column in SPACE_COLUMNS] for record in expected
    ]


def test_workspace_row_drops_operator_content() -> None:
    card = _fixture("properties_berlin.json")["data"][0]
    row = workspace_row(card)
    assert "images" not in row
    assert "excerpt" not in row
    assert "logo" not in row
    assert "amenities" not in row
    assert row["url"] == (
        "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin"
    )
    assert Path(row["url"]).name == card["slug"]
