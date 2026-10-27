"""Parse every fixture through the public API and compare with spec/golden/*.csv."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Callable

import pandas as pd
import pandas.testing as pdt
import pytest

from coworkingview._frames import (
    CITIES_SCHEMA,
    PRICING_SCHEMA,
    RATES_SCHEMA,
    SPACES_SCHEMA,
    Schema,
    column,
)

from .conftest import FakeAPI, Reply

Loader = Callable[[str], Any]


def read_golden(spec_dir: Path, name: str, schema: Schema) -> pd.DataFrame:
    """Read a golden CSV with the spec's conventions: empty = null, ``true``/``false``."""
    raw = pd.read_csv(spec_dir / "golden" / name, dtype=str, keep_default_na=False)
    assert list(raw.columns) == list(schema), f"{name}: golden columns differ from the schema"

    def cell(value: str, dtype: str) -> Any:
        if value == "":
            return None
        if dtype == "boolean":
            assert value in ("true", "false"), value
            return value == "true"
        if dtype == "Int64":
            return int(value)
        if dtype == "Float64":
            return float(value)
        return value

    df: pd.DataFrame = pd.DataFrame(
        {
            name: column([cell(v, dtype) for v in raw[name]], dtype)
            for name, dtype in schema.items()
        },
        columns=list(schema),
    )
    return df


def test_rates_match_golden(api: FakeAPI, load_fixture: Loader, spec_dir: Path) -> None:
    payload = load_fixture("market_rates.json")
    api.queue(Reply(body=payload))
    df = api.client().rates()
    pdt.assert_frame_equal(df, read_golden(spec_dir, "rates.csv", RATES_SCHEMA))
    data = payload["data"]
    assert df.attrs == {
        "attribution": data["attribution"],
        "license": data["licenseUrl"],
        "as_of": data["asOf"],
    }


def test_cities_match_golden(api: FakeAPI, load_fixture: Loader, spec_dir: Path) -> None:
    api.queue(Reply(body=load_fixture("market_rates.json")))
    df = api.client().cities()
    pdt.assert_frame_equal(df, read_golden(spec_dir, "cities.csv", CITIES_SCHEMA))
    assert df.attrs["attribution"].startswith("Source: CoworkingView Price Index")
    assert df.attrs["license"] == "https://creativecommons.org/licenses/by/4.0/"


def test_spaces_match_golden(api: FakeAPI, load_fixture: Loader, spec_dir: Path) -> None:
    payload = load_fixture("properties_berlin.json")
    payload["meta"]["pagination"]["pageCount"] = 1
    api.queue(Reply(body=payload))
    df = api.client().spaces(city="berlin")
    pdt.assert_frame_equal(df, read_golden(spec_dir, "spaces.csv", SPACES_SCHEMA))
    assert df.attrs["attribution"] == payload["meta"]["citation"]["text"]
    assert df.attrs["notice"] == payload["meta"]["catalogueNotice"]
    assert df.attrs["total"] == 110


def test_space_pricing_matches_golden(api: FakeAPI, load_fixture: Loader, spec_dir: Path) -> None:
    payload = load_fixture("property_detail.json")
    api.queue(Reply(body=payload))
    result = api.client().space("sankt-oberholz-rosenthaler-berlin")
    pdt.assert_frame_equal(
        result.pricing, read_golden(spec_dir, "space_pricing.csv", PRICING_SCHEMA)
    )


def test_usd_fixture_parses(api: FakeAPI, load_fixture: Loader) -> None:
    api.queue(Reply(body=load_fixture("market_rates_berlin_usd.json")))
    df = api.client().rates(city="berlin", currency="usd")
    assert set(df["currency"]) == {"USD"}
    assert df["city_slug"].unique().tolist() == ["berlin"]
    assert df.loc[df["product"] == "day_pass", "median"].item() == 38
    assert api.requests[0].query == {"locale": "en", "city": "berlin", "currency": "USD"}


def test_empty_properties_fixture(api: FakeAPI, load_fixture: Loader) -> None:
    payload = load_fixture("properties_empty.json")
    api.queue(Reply(body=payload))
    df = api.client().spaces(city="nowhere-xyz")
    assert df.empty
    assert list(df.columns) == list(SPACES_SCHEMA)
    assert str(df["updated_at"].dtype) == "datetime64[ns, UTC]"
    assert df.attrs["notice"] == payload["meta"]["catalogueNotice"]
    assert len(api.requests) == 1


def test_validation_problem_fixture(api: FakeAPI, load_fixture: Loader) -> None:
    from coworkingview import APIError

    problem = load_fixture("error_validation.json")
    api.queue(Reply(400, problem))
    with pytest.raises(APIError) as info:
        api.client().rates(city="berlin", currency="VES")
    err = info.value
    assert (err.status, err.code, err.title) == (400, "VALIDATION_FAILED", "Validation failed")
    assert err.detail == problem["detail"]
    assert err.errors == problem["errors"]
    assert len(api.requests) == 1  # 4xx is never retried
