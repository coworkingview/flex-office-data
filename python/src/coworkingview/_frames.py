"""Typed pandas frames: every column gets a nullable dtype, even when empty."""

from __future__ import annotations

from collections.abc import Iterable, Mapping, Sequence
from typing import Any

import pandas as pd

Schema = Mapping[str, str]

#: Logical dtype used for timestamp columns.
DATETIME = "datetime"

RATES_SCHEMA: Schema = {
    "city_slug": "string",
    "city_name": "string",
    "country_code": "string",
    "currency": "string",
    "product": "string",
    "unit": "string",
    "median": "Float64",
    "p25": "Float64",
    "p75": "Float64",
    "sample_size": "Int64",
    "property_count": "Int64",
    "operator_count": "Int64",
    "low_confidence": "boolean",
    "as_of": DATETIME,
}

CITIES_SCHEMA: Schema = {
    "city_slug": "string",
    "city_name": "string",
    "country_code": "string",
    "currency": "string",
    "published": "boolean",
    "property_count": "Int64",
    "operator_count": "Int64",
    "entry_median": "Float64",
    "entry_min": "Float64",
    "entry_max": "Float64",
    "p25": "Float64",
    "p75": "Float64",
    "sample_size": "Int64",
    "as_of": DATETIME,
}

SPACES_SCHEMA: Schema = {
    "slug": "string",
    "title": "string",
    "city_slug": "string",
    "zone_slug": "string",
    "operator_slug": "string",
    "operator_name": "string",
    "country_code": "string",
    "lat": "Float64",
    "lng": "Float64",
    "featured": "boolean",
    "market_verdict": "string",
    "market_median": "Float64",
    "market_sample_size": "Int64",
    "url": "string",
    "updated_at": DATETIME,
}

PRICING_SCHEMA: Schema = {
    "product": "string",
    "title": "string",
    "price": "Float64",
    "currency": "string",
    "billing_period": "string",
    "price_on_request": "boolean",
    "min_capacity": "Int64",
    "max_capacity": "Int64",
}


def to_timestamp(value: Any) -> pd.Timestamp | None:
    """Parse one ISO 8601 string into a UTC :class:`pandas.Timestamp` (``None`` passes)."""
    if value is None:
        return None
    ts: pd.Timestamp = pd.Timestamp(value)
    utc: pd.Timestamp = ts.tz_localize("UTC") if ts.tzinfo is None else ts.tz_convert("UTC")
    return utc


def column(values: Sequence[Any], dtype: str) -> pd.Series[Any]:
    """Build one typed column; ``dtype`` is a pandas dtype name or :data:`DATETIME`."""
    series: pd.Series[Any]
    if dtype == DATETIME:
        stamps = [to_timestamp(v) for v in values]
        series = pd.Series(pd.DatetimeIndex(stamps, dtype="datetime64[ns, UTC]"))
    else:
        series = pd.Series(list(values), dtype=dtype)
    return series


def frame(rows: Iterable[Mapping[str, Any]], schema: Schema) -> pd.DataFrame:
    """Build a DataFrame with exactly ``schema``'s columns, in order, with its dtypes."""
    materialised = list(rows)
    data = {
        name: column([row.get(name) for row in materialised], dtype)
        for name, dtype in schema.items()
    }
    df: pd.DataFrame = pd.DataFrame(data, columns=list(schema))
    return df
