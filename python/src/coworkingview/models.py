"""Result types that are not DataFrames."""

from __future__ import annotations

from dataclasses import dataclass, field

import pandas as pd

__all__ = ["Space"]


@dataclass(frozen=True)
class Space:
    """One coworking space, as returned by :func:`coworkingview.space`.

    Scalar fields match the columns of :func:`coworkingview.spaces`, plus the
    address, capacity and amenities of the space. Prices are in ``pricing``.
    Descriptions, photos and logos are deliberately not included: they are
    the operators' content and are not licensed for reuse.

    Attributes
    ----------
    slug : str
        Stable identifier of the space, e.g. ``"sankt-oberholz-rosenthaler-berlin"``.
    title : str
        Name of the space.
    city_slug, zone_slug : str or None
        City and neighbourhood identifiers.
    operator_slug, operator_name : str or None
        Operator identifier and display name.
    country_code : str or None
        ISO 3166-1 alpha-2 country code.
    lat, lng : float or None
        WGS 84 coordinates.
    featured : bool or None
        Whether CoworkingView features the space.
    market_verdict : str or None
        ``"below"``, ``"around"`` or ``"above"`` the city median for its
        cheapest monthly option.
    market_median : float or None
        The city median that verdict compares against.
    market_sample_size : int or None
        Number of prices behind ``market_median``.
    url : str
        Listing page on coworkingview.com.
    updated_at : pandas.Timestamp or None
        Last update of the listing (UTC).
    address : str or None
        Street address.
    capacity : int or None
        Total capacity in people, when the operator published it.
    amenities : tuple of str
        Amenity codes, e.g. ``("wifi", "meeting_rooms")``.
    pricing : pandas.DataFrame
        One row per pricing option, columns ``product``, ``title``, ``price``,
        ``currency``, ``billing_period``, ``price_on_request``,
        ``min_capacity``, ``max_capacity``.
    attribution : str or None
        Citation to show next to the data (``meta.citation.text``).
    notice : str or None
        The API's catalogue notice on reuse of operator content.
    """

    slug: str
    title: str
    city_slug: str | None
    zone_slug: str | None
    operator_slug: str | None
    operator_name: str | None
    country_code: str | None
    lat: float | None
    lng: float | None
    featured: bool | None
    market_verdict: str | None
    market_median: float | None
    market_sample_size: int | None
    url: str
    updated_at: pd.Timestamp | None
    address: str | None
    capacity: int | None
    amenities: tuple[str, ...]
    pricing: pd.DataFrame = field(repr=False, compare=False, hash=False)
    attribution: str | None = None
    notice: str | None = field(default=None, repr=False)
