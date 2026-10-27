"""Row-level parsing rules, including aggregates the fixtures do not contain yet."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

from coworkingview import _parse


def money(x: float) -> dict[str, Any]:
    return {"amount": x, "currency": "EUR"}


def stat(median: float, n: int, **extra: Any) -> dict[str, Any]:
    return {"median": money(median), "sampleSize": n, **extra}


def test_by_type_fallback_and_future_aggregates() -> None:
    data = {
        "asOf": "2026-10-27T00:00:00Z",
        "cities": [
            {
                "city": {"slug": "zurich", "name": "Zurich"},
                "currency": "CHF",
                "figures": [],
                "byType": [
                    {"optionType": "private_office", **stat(900, 12)},
                    {"optionType": "flex_desk", **stat(400, 4)},
                ],
                "eventSpace": stat(150, 3, p25=money(100), p75=money(200)),
                "virtualOffice": stat(60, 20),
                "parkingSpot": stat(120, 5),
                "aRooftop": stat(10, 1),
                "p25": money(1),  # money, not a stat: ignored
                "insufficientData": False,
            }
        ],
        "unpublished": [{"city": {"slug": "bern", "name": "Bern"}}],
    }
    rows = _parse.rate_rows(data)
    got = [(r["product"], r["unit"], r["median"], r["p25"], r["low_confidence"]) for r in rows]
    assert got == [
        ("flex_desk", "month", 400, None, True),
        ("private_office", "month", 900, None, False),
        ("event_space", "hour", 150, 100, True),
        ("virtual_office", "month", 60, None, False),
        ("a_rooftop", None, 10, None, True),
        ("parking_spot", None, 120, None, True),
    ]
    assert {r["city_slug"] for r in rows} == {"zurich"}  # unpublished cities give no rates
    assert rows[0]["country_code"] is None
    assert rows[0]["property_count"] is None


def test_city_without_figures_or_by_type() -> None:
    data = {"cities": [{"city": {"slug": "x", "name": "X"}, "currency": "EUR"}]}
    assert _parse.rate_rows(data) == []
    (row,) = _parse.city_rows(data)
    assert row["published"] is True
    assert row["as_of"] is None
    assert row["entry_median"] is None


@pytest.mark.parametrize(
    ("key", "expected"), [("dayPass", "day_pass"), ("eventSpace", "event_space"), ("x", "x")]
)
def test_snake(key: str, expected: str) -> None:
    assert _parse.snake(key) == expected


def _reference(spec_dir: Path) -> ModuleType:
    path = spec_dir / "tools" / "make_golden.py"
    if not path.is_file():
        pytest.skip("spec/tools/make_golden.py not available")
    spec = importlib.util.spec_from_file_location("make_golden", path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_rows_identical_to_reference_script(spec_dir: Path) -> None:
    """Row dicts equal the reference implementation's on every fixture and locale."""
    ref = _reference(spec_dir)
    fixtures = spec_dir / "fixtures"

    def load(name: str) -> Any:
        return json.loads((fixtures / name).read_text(encoding="utf-8"))["data"]

    for name in ("market_rates.json", "market_rates_berlin_usd.json"):
        assert _parse.rate_rows(load(name)) == ref.rate_rows(load(name))
        assert _parse.city_rows(load(name)) == ref.city_rows(load(name))
    for locale in ("en", "es", "de"):
        cards = load("properties_berlin.json")
        assert [_parse.space_row(c, locale) for c in cards] == [
            ref.space_row(c, locale) for c in cards
        ]
    assert _parse.pricing_rows(load("property_detail.json")) == ref.pricing_rows(
        load("property_detail.json")
    )
