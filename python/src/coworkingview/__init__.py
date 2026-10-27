"""Flexible-office prices and coworking catalogue search from CoworkingView.

One call returns a tidy :class:`pandas.DataFrame`:

>>> import coworkingview as cwv
>>> cwv.rates(city="berlin")  # doctest: +SKIP

Functions
---------
rates
    The CoworkingView Price Index: one row per city x product (CC BY 4.0).
cities
    One row per city covered by the Price Index.
spaces
    Catalogue search: one row per coworking space (at most 200 per call).
space
    One space with its pricing table, as a :class:`Space`.

The data come from the public, keyless API at https://api.coworkingview.com.
Price Index figures are licensed CC BY 4.0: keep ``df.attrs["attribution"]``
next to anything you publish. Catalogue content belongs to the operators
and is not licensed for reuse; link to the listing ``url`` instead.
See https://coworkingview.com/en/tools/price-index.
"""

from __future__ import annotations

import threading
from typing import Union

import pandas as pd

from ._version import __version__
from .client import Client
from .exceptions import APIError, CoworkingViewError
from .models import Space

__all__ = [
    "APIError",
    "Client",
    "CoworkingViewError",
    "Space",
    "__version__",
    "cities",
    "rates",
    "space",
    "spaces",
]

Number = Union[int, float]

_default: Client | None = None
_default_lock = threading.Lock()


def _client() -> Client:
    """Return the shared default :class:`Client`, created on first use (no I/O at import)."""
    global _default  # noqa: PLW0603
    with _default_lock:
        if _default is None:
            _default = Client()
        return _default


def rates(
    city: str | None = None,
    country: str | None = None,
    currency: str | None = None,
    locale: str = "en",
) -> pd.DataFrame:
    """Flexible-office prices from the CoworkingView Price Index.

    One row per published city and product: monthly medians for flex desks,
    fixed desks and private offices, a daily median for day passes and an
    hourly median for meeting rooms (new aggregates appear automatically).

    Parameters
    ----------
    city : str, optional
        City slug, e.g. ``"berlin"``, ``"madrid"``, ``"abu-dhabi"``.
    country : str, optional
        ISO 3166-1 alpha-2 country code, e.g. ``"DE"``.
    currency : {"EUR", "GBP", "USD", "CHF", "AED", "VES"}, optional
        Present prices in this currency (approximate conversion by the API).
        Default: each city's own currency. ``VES`` is passed through; the
        API answers 400 for cities it cannot convert.
    locale : {"en", "es", "de"}, default "en"
        Language of city names.

    Returns
    -------
    pandas.DataFrame
        Columns ``city_slug``, ``city_name``, ``country_code``, ``currency``,
        ``product``, ``unit`` (``month``/``day``/``hour``), ``median``,
        ``p25``, ``p75`` (Float64), ``sample_size``, ``property_count``,
        ``operator_count`` (Int64), ``low_confidence`` (boolean,
        ``sample_size < 10``) and ``as_of`` (UTC datetime). Sorted by city,
        then product. ``df.attrs`` holds ``attribution``, ``license`` (licence
        URL) and ``as_of``.

    Raises
    ------
    ValueError
        An argument is not one of the accepted values.
    APIError
        The API rejected the request or answered with an error.
    CoworkingViewError
        The API could not be reached.

    See Also
    --------
    cities : one row per city, with entry-level prices.

    Notes
    -----
    The Price Index is licensed CC BY 4.0. Credit it with
    ``df.attrs["attribution"]`` wherever you publish derived figures.

    Examples
    --------
    >>> import coworkingview as cwv
    >>> df = cwv.rates(city="berlin")  # doctest: +SKIP
    >>> df[["product", "unit", "median", "sample_size"]]  # doctest: +SKIP
              product   unit  median  sample_size
    0       flex_desk  month   214.0           72
    1        fix_desk  month   310.0           60
    2  private_office  month   480.0           59
    3        day_pass    day    35.0           59
    4    meeting_room   hour    32.0           79
    """
    return _client().rates(city=city, country=country, currency=currency, locale=locale)


def cities(
    city: str | None = None,
    country: str | None = None,
    currency: str | None = None,
    locale: str = "en",
) -> pd.DataFrame:
    """Cities covered by the CoworkingView Price Index.

    Parameters
    ----------
    city : str, optional
        City slug, e.g. ``"berlin"``.
    country : str, optional
        ISO 3166-1 alpha-2 country code, e.g. ``"ES"``.
    currency : {"EUR", "GBP", "USD", "CHF", "AED", "VES"}, optional
        Present prices in this currency. Default: each city's own currency.
    locale : {"en", "es", "de"}, default "en"
        Language of city names.

    Returns
    -------
    pandas.DataFrame
        One row per city: ``city_slug``, ``city_name``, ``country_code``,
        ``currency``, ``published`` (boolean; unpublished cities have too
        few prices for an index), ``property_count``, ``operator_count``
        (Int64), ``entry_median``, ``entry_min``, ``entry_max`` (Float64,
        the cheapest monthly option per space), ``p25``, ``p75`` (Float64),
        ``sample_size`` (Int64) and ``as_of`` (UTC datetime). Published
        cities first, then by slug. ``df.attrs`` holds ``attribution``,
        ``license`` and ``as_of``.

    Raises
    ------
    ValueError
        An argument is not one of the accepted values.
    APIError
        The API rejected the request or answered with an error.
    CoworkingViewError
        The API could not be reached.

    See Also
    --------
    rates : figures per city and product.

    Examples
    --------
    >>> import coworkingview as cwv
    >>> cwv.cities()[["city_slug", "published", "entry_median"]]  # doctest: +SKIP
          city_slug  published  entry_median
    0     abu-dhabi       True        1453.0
    1        berlin       True         265.0
    2        madrid       True         325.0
    """
    return _client().cities(city=city, country=country, currency=currency, locale=locale)


def spaces(
    city: str | None = None,
    country: str | None = None,
    zone: str | None = None,
    operator: str | None = None,
    product: str | None = None,
    min_capacity: int | None = None,
    min_price: Number | None = None,
    max_price: Number | None = None,
    currency: str | None = None,
    sort: str = "random",
    limit: int = 50,
    locale: str = "en",
) -> pd.DataFrame:
    """Search the CoworkingView catalogue of flexible workspaces.

    Coworking spaces, business centres, private offices, meeting rooms,
    event spaces and virtual offices. Returns identifiers, location, the
    space's position against the city median and a link to its listing;
    no descriptions, photos or logos (operators' content, not licensed).

    Parameters
    ----------
    city : str, optional
        City slug, e.g. ``"berlin"``.
    country : str, optional
        ISO 3166-1 alpha-2 country code.
    zone : str, optional
        Neighbourhood slug within the city, e.g. ``"mitte"``.
    operator : str, optional
        Operator slug, e.g. ``"regus"``.
    product : str, optional
        Only spaces offering this product: ``"flex_desk"``, ``"fix_desk"``,
        ``"private_office"``, ``"exclusive_bereich"``, ``"day_pass"``,
        ``"meeting_room"``, ``"event_space"``, ``"virtual_office"`` or
        ``"membership"``.
    min_capacity : int, optional
        Only options for at least this many people.
    min_price, max_price : float, optional
        Price bounds, in ``currency`` when given.
    currency : {"EUR", "GBP", "USD", "CHF", "AED", "VES"}, optional
        Currency for the price bounds.
    sort : {"random", "price-asc", "date-desc", "date-asc"}, default "random"
        Result order. ``"random"`` is stable across the pages of one call.
    limit : int, default 50
        Maximum number of spaces, 1-200. The cap is deliberate: the
        catalogue may be searched and linked to, not bulk-copied.
    locale : {"en", "es", "de"}, default "en"
        Language of titles and of the listing ``url``.

    Returns
    -------
    pandas.DataFrame
        One row per space: ``slug``, ``title``, ``city_slug``,
        ``zone_slug``, ``operator_slug``, ``operator_name``,
        ``country_code``, ``lat``, ``lng`` (Float64), ``featured``
        (boolean), ``market_verdict`` (``below``/``around``/``above``),
        ``market_median`` (Float64), ``market_sample_size`` (Int64), ``url``
        and ``updated_at`` (UTC datetime). ``df.attrs`` holds
        ``attribution``, ``notice`` (the catalogue notice) and ``total``
        (number of matches, which may exceed ``limit``).

    Raises
    ------
    ValueError
        An argument is not one of the accepted values, or ``limit > 200``.
    APIError
        The API rejected the request or answered with an error.
    CoworkingViewError
        The API could not be reached.

    See Also
    --------
    space : one space with its full pricing table.

    Examples
    --------
    >>> import coworkingview as cwv
    >>> df = cwv.spaces(city="berlin", product="meeting_room", limit=10)  # doctest: +SKIP
    >>> df[["title", "zone_slug", "url"]]  # doctest: +SKIP
    """
    return _client().spaces(
        city=city,
        country=country,
        zone=zone,
        operator=operator,
        product=product,
        min_capacity=min_capacity,
        min_price=min_price,
        max_price=max_price,
        currency=currency,
        sort=sort,
        limit=limit,
        locale=locale,
    )


def space(slug: str, locale: str = "en") -> Space:
    """One space from the catalogue, with its pricing table.

    Parameters
    ----------
    slug : str
        The space's slug, as in the ``slug`` column of :func:`spaces`.
    locale : {"en", "es", "de"}, default "en"
        Language of titles and of the listing ``url``.

    Returns
    -------
    Space
        A frozen dataclass with the :func:`spaces` fields plus ``address``,
        ``capacity`` and ``amenities``; ``pricing`` is a DataFrame with one
        row per pricing option (``product``, ``title``, ``price``,
        ``currency``, ``billing_period``, ``price_on_request``,
        ``min_capacity``, ``max_capacity``); ``attribution`` and ``notice``
        carry the citation and catalogue notice.

    Raises
    ------
    ValueError
        ``slug`` does not match ``^[A-Za-z0-9][A-Za-z0-9._-]*$`` or ``locale``
        is not supported.
    APIError
        The API answered with an error (``code == "NOT_FOUND"`` for an
        unknown slug).
    CoworkingViewError
        The API could not be reached.

    Examples
    --------
    >>> import coworkingview as cwv
    >>> s = cwv.space("sankt-oberholz-rosenthaler-berlin")  # doctest: +SKIP
    >>> s.pricing[["product", "price", "billing_period"]]  # doctest: +SKIP
              product  price billing_period
    0       flex_desk  209.0          month
    1        fix_desk   <NA>          month
    """
    return _client().space(slug, locale=locale)
