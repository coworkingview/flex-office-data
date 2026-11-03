"""Bar charts of the CoworkingView Price Index."""

from __future__ import annotations

from collections.abc import Sequence

import matplotlib as mpl
from matplotlib.axes import Axes
from matplotlib.container import BarContainer
from matplotlib.lines import Line2D
from matplotlib.patches import Patch

from ._http import Client, prepare_market_query, require_city
from ._parse import MarketRates
from .exceptions import CoworkingViewError

#: Text drawn on every chart. The Price Index is CC BY 4.0.
ATTRIBUTION = "Data: CoworkingView Price Index (CC BY 4.0)"


def plot_city_rates(
    ax: Axes,
    city: str,
    *,
    currency: str | None = None,
    locale: str = "en",
    country: str | None = None,
    products: str | Sequence[str] | None = None,
    client: Client | None = None,
) -> BarContainer:
    """Bar chart of Price Index medians for one city.

    The bars are one per product. The height is ``median`` (the API's
    ``median.amount``). When both ``p25`` and ``p75`` are present they are
    drawn as an interval around the median. The default selection is the
    monthly products (``unit == "month"``), which are the ``figures`` rows
    (or ``byType`` when ``figures`` is absent). Pass ``products`` to choose
    ``optionType`` values, including ``day_pass`` or ``meeting_room``.

    A product with ``sample_size`` below 10 (``low_confidence``) is hatched.

    Parameters
    ----------
    ax : matplotlib.axes.Axes
        Axes to draw on.
    city : str
        City slug, sent as the ``city`` query parameter. Examples from the
        recorded fixture: ``berlin``, ``madrid``, ``abu-dhabi``.
    currency : str, optional
        ``currency`` query parameter. One of ``EUR``, ``GBP``, ``USD``,
        ``CHF``, ``AED``, ``VES``. Omit it to keep the city's currency.
    locale : {"en", "es", "de"}, default "en"
        ``locale`` query parameter. The API rejects a request without it.
    country : str, optional
        ``country`` query parameter, passed through unchanged.
    products : str or sequence of str, optional
        ``product`` values to plot, in this order. The default is every
        monthly product for the city.
    client : Client, optional
        Defaults to a client for ``https://api.coworkingview.com``. Tests
        pass a client whose ``market_rates`` returns a fixture.

    Returns
    -------
    matplotlib.container.BarContainer
        The bars. The x-axis label is the CC BY 4.0 attribution line.
    """
    query = prepare_market_query(city=city, country=country, currency=currency, locale=locale)
    result = (client or Client()).market_rates(**query)
    rows = _rows_for_city(result, query["city"])
    selected = _select_products(rows, products, city=query["city"])
    _require_one_unit(selected)
    return _draw_bars(
        ax,
        labels=[row["product"] for row in selected],
        rows=selected,
        title=selected[0]["city_name"],
    )


def plot_rate_comparison(
    ax: Axes,
    cities: Sequence[str],
    product: str = "flex_desk",
    *,
    currency: str | None = None,
    locale: str = "en",
    country: str | None = None,
    client: Client | None = None,
) -> BarContainer:
    """Bar chart comparing one product's median across cities.

    One ``GET /v1/market/rates`` request is made (the ``city`` parameter is
    a single slug, so a comparison does not send it). The response is then
    filtered to ``cities``, in the order given. ``product`` defaults to
    ``flex_desk`` and is matched to the row's ``product`` (the API's
    ``optionType``, or the snake_case city-level key).

    Every selected row must share one ``currency`` and one ``unit``. Pass
    ``currency`` to ask the API for a single currency.

    Parameters
    ----------
    ax : matplotlib.axes.Axes
        Axes to draw on.
    cities : sequence of str
        City slugs. A string is rejected so it is not iterated character by
        character.
    product : str, default "flex_desk"
        Product to compare.
    currency, locale, country :
        Query parameters. See :func:`plot_city_rates`.
    client : Client, optional
        See :func:`plot_city_rates`.

    Returns
    -------
    matplotlib.container.BarContainer
        The bars. Tick labels are ``city_name``. The x-axis label is the
        CC BY 4.0 attribution line.
    """
    slugs = _require_cities(cities)
    if not isinstance(product, str) or not product.strip():
        raise ValueError(f"product must be a non-empty string, got {product!r}.")
    query = prepare_market_query(country=country, currency=currency, locale=locale)
    result = (client or Client()).market_rates(**query)
    rows = [_row_for(result, slug, product) for slug in slugs]
    _require_one_unit(rows)
    _require_one_currency(rows)
    return _draw_bars(
        ax,
        labels=[row["city_name"] for row in rows],
        rows=rows,
        title=product,
    )


def _require_cities(cities: Sequence[str]) -> list[str]:
    if isinstance(cities, str) or not isinstance(cities, Sequence):
        raise ValueError(f"cities must be a sequence of city slugs, got {cities!r}.")
    slugs = [require_city(city) for city in cities]
    if not slugs:
        raise ValueError("cities must name at least one city.")
    if len(set(slugs)) != len(slugs):
        raise ValueError(f"cities contains a duplicate slug: {slugs!r}.")
    return slugs


def _rows_for_city(result: MarketRates, city: str) -> list[dict]:
    matched = [row for row in result.rows if row["city_slug"] == city]
    if matched:
        return matched
    if city in result.unpublished:
        raise CoworkingViewError(
            f"{city} is listed in the Price Index but is unpublished: "
            "it does not have enough prices for a rate yet."
        )
    raise CoworkingViewError(f"No published Price Index rates for city {city!r}.")


def _select_products(
    rows: list[dict],
    products: str | Sequence[str] | None,
    *,
    city: str,
) -> list[dict]:
    if products is None:
        selected = [row for row in rows if row["unit"] == "month"]
        if not selected:
            raise CoworkingViewError(f"No monthly rates for city {city!r}.")
        return selected
    if isinstance(products, str):
        wanted = [products]
    elif isinstance(products, Sequence):
        wanted = list(products)
    else:
        raise ValueError(f"products must be a string or a sequence of strings, got {products!r}.")
    if not wanted or any(not isinstance(name, str) or not name for name in wanted):
        raise ValueError(f"products must name at least one product, got {products!r}.")
    by_product = {row["product"]: row for row in rows}
    missing = [name for name in wanted if name not in by_product]
    if missing:
        published = ", ".join(row["product"] for row in rows)
        raise CoworkingViewError(
            f"No {', '.join(missing)} rate for city {city!r}. Published products: {published}."
        )
    return [by_product[name] for name in wanted]


def _row_for(result: MarketRates, city: str, product: str) -> dict:
    rows = _rows_for_city(result, city)
    matched = [row for row in rows if row["product"] == product]
    if not matched:
        published = ", ".join(row["product"] for row in rows)
        raise CoworkingViewError(
            f"No {product} rate for city {city!r}. Published products: {published}."
        )
    return matched[0]


def _require_one_unit(rows: list[dict]) -> None:
    units = {row["unit"] for row in rows}
    if len(units) != 1:
        listed = ", ".join(sorted(str(unit) for unit in units))
        raise ValueError(
            f"These products use more than one unit ({listed}). Plot one unit at a time."
        )


def _require_one_currency(rows: list[dict]) -> None:
    currencies = {row["currency"] for row in rows}
    if len(currencies) != 1:
        listed = ", ".join(sorted(str(currency) for currency in currencies))
        raise ValueError(
            f"These rates use more than one currency ({listed}). "
            "Pass currency= to request one currency from the API."
        )


def _draw_bars(ax: Axes, *, labels: list[str], rows: list[dict], title: str) -> BarContainer:
    if any(row["median"] is None for row in rows):
        raise CoworkingViewError("A Price Index row is missing median.")
    color = mpl.rcParams["axes.prop_cycle"].by_key()["color"][0]
    heights = [float(row["median"]) for row in rows]
    lower: list[float] = []
    upper: list[float] = []
    has_interval = False
    for row, height in zip(rows, heights):
        p25 = row["p25"]
        p75 = row["p75"]
        if p25 is None or p75 is None:
            lower.append(0.0)
            upper.append(0.0)
        else:
            lower.append(height - float(p25))
            upper.append(float(p75) - height)
            has_interval = True
    kwargs: dict = {"color": color, "width": 0.72, "zorder": 3}
    if has_interval:
        kwargs["yerr"] = [lower, upper]
        kwargs["capsize"] = 3
        kwargs["ecolor"] = "0.35"
        kwargs["error_kw"] = {"linewidth": 0.8, "zorder": 4}
    container = ax.bar(range(len(rows)), heights, **kwargs)
    for bar, row in zip(container, rows):
        bar.set_edgecolor(color)
        bar.set_linewidth(0.6)
        if row["low_confidence"]:
            bar.set_hatch("///")
    ax.set_xticks(range(len(labels)), labels)
    if any(len(str(label)) > 14 for label in labels):
        for tick in ax.get_xticklabels():
            tick.set_rotation(20)
            tick.set_ha("right")
    currency = rows[0]["currency"]
    unit = rows[0]["unit"]
    if unit:
        ax.set_ylabel(f"median ({currency} per {unit})")
    else:
        ax.set_ylabel(f"median ({currency})")
    ax.set_title(title)
    ax.set_xlabel(ATTRIBUTION, fontsize=8, color="0.35", labelpad=12, loc="left")
    ax.set_ylim(bottom=0)
    ax.set_axisbelow(True)
    ax.yaxis.grid(True, linestyle=":", linewidth=0.6, color="0.75")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.tick_params(axis="x", length=0)
    _legend(ax, rows, color=color, has_interval=has_interval)
    return container


def _legend(ax: Axes, rows: list[dict], *, color: str, has_interval: bool) -> None:
    lows = [bool(row["low_confidence"]) for row in rows]
    handles = []
    if any(lows) and not all(lows):
        handles.append(Patch(facecolor=color, edgecolor=color, label="sample_size >= 10"))
        handles.append(
            Patch(facecolor=color, edgecolor=color, hatch="///", label="sample_size < 10")
        )
    elif any(lows):
        handles.append(
            Patch(facecolor=color, edgecolor=color, hatch="///", label="sample_size < 10")
        )
    if has_interval:
        handles.append(Line2D([0], [0], color="0.35", linewidth=0.8, label="p25-p75"))
    if handles:
        ax.legend(handles=handles, frameon=False)
