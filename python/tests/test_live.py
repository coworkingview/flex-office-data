"""End-to-end checks against the real API.

Opt-in only: ``COWORKINGVIEW_LIVE_TESTS=1 pytest -m live``. The whole module
makes exactly three requests, because the API runs on a small server.
"""

from __future__ import annotations

import os

import pytest

import coworkingview as cwv

pytestmark = [
    pytest.mark.live,
    pytest.mark.skipif(
        os.environ.get("COWORKINGVIEW_LIVE_TESTS") != "1",
        reason="live API tests are opt-in (COWORKINGVIEW_LIVE_TESTS=1)",
    ),
]


def test_live_end_to_end() -> None:
    # Request 1: the Price Index for one city.
    rates = cwv.rates(city="berlin")
    assert not rates.empty
    assert set(rates["city_slug"]) == {"berlin"}
    assert "flex_desk" in set(rates["product"])
    assert "CC BY 4.0" in rates.attrs["attribution"]

    # Request 2: a small catalogue search (one page).
    found = cwv.spaces(city="berlin", limit=3)
    assert 1 <= len(found) <= 3
    assert found.attrs["notice"]

    # Request 3: one space with its pricing table.
    detail = cwv.space(found["slug"].iloc[0])
    assert detail.slug == found["slug"].iloc[0]
    assert detail.url.startswith("https://coworkingview.com/")
    assert list(detail.pricing.columns)[:3] == ["product", "title", "price"]
