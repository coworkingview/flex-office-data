"""Price Index rows match spec/golden/rates.csv."""

from __future__ import annotations

from mpl_coworkingview._parse import RATE_COLUMNS, parse_market_rates

from .conftest import GOLDEN, load_fixture


def _cell(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def test_market_rates_fixture_matches_golden() -> None:
    result = parse_market_rates(load_fixture("market_rates.json"))
    golden = (GOLDEN / "rates.csv").read_text(encoding="utf-8").splitlines()
    header = golden[0].split(",")
    assert header == list(RATE_COLUMNS)
    rendered = [",".join(_cell(row[column]) for column in header) for row in result.rows]
    assert rendered == golden[1:]
    assert result.unpublished == ("example-town",)


def test_berlin_usd_fixture_uses_response_currency() -> None:
    result = parse_market_rates(load_fixture("market_rates_berlin_usd.json"))
    flex = next(row for row in result.rows if row["product"] == "flex_desk")
    assert flex["city_slug"] == "berlin"
    assert flex["city_name"] == "Berlin"
    assert flex["currency"] == "USD"
    assert flex["median"] == 233
    assert flex["p25"] == 216
    assert flex["p75"] == 317
    assert flex["sample_size"] == 72
    assert flex["unit"] == "month"
    assert flex["low_confidence"] is False
