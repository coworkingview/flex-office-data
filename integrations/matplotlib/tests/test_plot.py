"""Bar heights, query parameters and the CC BY attribution line."""

from __future__ import annotations

import matplotlib.pyplot as plt
import pytest

from mpl_coworkingview import ATTRIBUTION, CoworkingViewError, plot_city_rates, plot_rate_comparison

from .conftest import load_fixture
from .support import RecordingClient


def _heights(container) -> list[float]:
    return [float(value) for value in container.datavalues]


def test_plot_city_rates_uses_fixture_medians_and_attribution() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    bars = plot_city_rates(ax, "berlin", client=client)
    assert _heights(bars) == [214, 310, 480]
    assert [tick.get_text() for tick in ax.get_xticklabels()] == [
        "flex_desk",
        "fix_desk",
        "private_office",
    ]
    assert ax.get_title() == "Berlin"
    assert ax.get_ylabel() == "median (EUR per month)"
    assert ax.get_xlabel() == ATTRIBUTION
    assert ATTRIBUTION == "Data: CoworkingView Price Index (CC BY 4.0)"
    assert client.calls == [{"locale": "en", "city": "berlin"}]
    assert bars.errorbar is not None
    assert all(bar.get_hatch() in (None, "") for bar in bars)


def test_plot_city_rates_sends_currency_and_reads_amounts() -> None:
    client = RecordingClient(load_fixture("market_rates_berlin_usd.json"))
    _fig, ax = plt.subplots()
    bars = plot_city_rates(ax, "berlin", currency="USD", locale="de", client=client)
    assert _heights(bars) == [233, 337, 522]
    assert ax.get_ylabel() == "median (USD per month)"
    assert client.calls == [{"locale": "de", "city": "berlin", "currency": "USD"}]
    assert "product" not in client.calls[0]
    assert "products" not in client.calls[0]


def test_plot_city_rates_hatches_low_confidence() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    bars = plot_city_rates(ax, "abu-dhabi", client=client)
    assert _heights(bars) == [1400, 1800, 2057]
    assert all(bar.get_hatch() == "///" for bar in bars)
    labels = [text.get_text() for text in ax.get_legend().get_texts()]
    assert "sample_size < 10" in labels


def test_plot_city_rates_day_pass_has_no_percentile_interval() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    bars = plot_city_rates(ax, "berlin", products="day_pass", client=client)
    assert _heights(bars) == [35]
    assert ax.get_ylabel() == "median (EUR per day)"
    assert bars.errorbar is None


def test_plot_city_rates_rejects_mixed_units() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    with pytest.raises(ValueError, match="unit"):
        plot_city_rates(ax, "berlin", products=["flex_desk", "day_pass"], client=client)


def test_plot_city_rates_unpublished_and_missing() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    with pytest.raises(CoworkingViewError, match="unpublished"):
        plot_city_rates(ax, "example-town", client=client)
    with pytest.raises(CoworkingViewError, match="no-such-city"):
        plot_city_rates(ax, "no-such-city", client=client)


def test_plot_rate_comparison_keeps_caller_order() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    bars = plot_rate_comparison(ax, ["madrid", "berlin"], client=client)
    assert _heights(bars) == [175, 214]
    assert [tick.get_text() for tick in ax.get_xticklabels()] == ["Madrid", "Berlin"]
    assert ax.get_title() == "flex_desk"
    assert ax.get_ylabel() == "median (EUR per month)"
    assert ax.get_xlabel() == ATTRIBUTION
    assert client.calls == [{"locale": "en"}]
    assert "city" not in client.calls[0]


def test_plot_rate_comparison_refuses_mixed_currencies() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    with pytest.raises(ValueError, match="AED"):
        plot_rate_comparison(ax, ["abu-dhabi", "berlin"], client=client)


def test_plot_rate_comparison_rejects_a_bare_string() -> None:
    client = RecordingClient(load_fixture("market_rates.json"))
    _fig, ax = plt.subplots()
    with pytest.raises(ValueError, match="cities"):
        plot_rate_comparison(ax, "berlin", client=client)  # type: ignore[arg-type]
    assert client.calls == []
