"""The :class:`Client` and the endpoint logic behind the module-level functions."""

from __future__ import annotations

import os
from typing import Any, Union

import pandas as pd

from . import _parse
from . import _validate as check
from ._frames import (
    CITIES_SCHEMA,
    PRICING_SCHEMA,
    RATES_SCHEMA,
    SPACES_SCHEMA,
    frame,
    to_timestamp,
)
from ._http import DEFAULT_BASE_URL, DEFAULT_TIMEOUT, DEFAULT_USER_AGENT, QueryValue, Transport
from .exceptions import APIError
from .models import Space

__all__ = ["Client"]

#: Environment variable that overrides the API base URL.
ENV_BASE_URL = "COWORKINGVIEW_API_URL"
#: Page size used by :meth:`Client.spaces` (the last page is trimmed to ``limit``).
PAGE_SIZE = 50

Number = Union[int, float]


def _data(payload: dict[str, Any], path: str) -> Any:
    if "data" not in payload:
        raise APIError(200, "BAD_RESPONSE", "The API response has no 'data' member", f"GET {path}")
    return payload["data"]


def _meta(payload: dict[str, Any]) -> dict[str, Any]:
    meta = payload.get("meta")
    return meta if isinstance(meta, dict) else {}


def _citation_text(meta: dict[str, Any]) -> str | None:
    citation = meta.get("citation")
    if isinstance(citation, dict):
        text = citation.get("text")
        return text if isinstance(text, str) else None
    return None


class Client:
    """Configurable client for the CoworkingView public API.

    The module-level functions (:func:`coworkingview.rates`, ...) use a shared
    default ``Client()``; create your own to change the base URL, timeout or
    User-Agent. The API is public and needs no key. A client holds no
    connection and is safe to share between threads.

    Parameters
    ----------
    base_url : str, optional
        API root. Defaults to the ``COWORKINGVIEW_API_URL`` environment
        variable, else ``"https://api.coworkingview.com"``.
    timeout : float, default 20
        Seconds to wait for each HTTP response.
    user_agent : str, optional
        ``User-Agent`` header. Defaults to
        ``"coworkingview-python/<version> (+https://github.com/coworkingview/flex-office-data)"``.
        If you build something on top of this package, consider appending
        your own product token so the operators of the API can reach you.

    Notes
    -----
    On ``429`` or ``5xx`` answers the client waits ``Retry-After`` seconds
    (else ``RateLimit-Reset``, else 2 s; never more than 10 s) and retries
    exactly once. Any other error is raised as :class:`~coworkingview.APIError`.
    The API allows 120 requests per minute per IP and its responses are
    cacheable for 10 minutes, so cache results you reuse.

    Examples
    --------
    >>> from coworkingview import Client
    >>> client = Client(timeout=5)
    >>> df = client.rates(city="berlin")  # doctest: +SKIP
    """

    def __init__(
        self,
        base_url: str | None = None,
        timeout: float = DEFAULT_TIMEOUT,
        user_agent: str | None = None,
    ) -> None:
        resolved = base_url or os.environ.get(ENV_BASE_URL) or DEFAULT_BASE_URL
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError(f"timeout must be a positive number of seconds, got {timeout!r}.")
        self._transport = Transport(resolved, float(timeout), user_agent or DEFAULT_USER_AGENT)

    @property
    def base_url(self) -> str:
        """API root this client talks to."""
        return self._transport.base_url

    @property
    def timeout(self) -> float:
        """Per-request timeout in seconds."""
        return self._transport.timeout

    @property
    def user_agent(self) -> str:
        """``User-Agent`` header sent with every request."""
        return self._transport.user_agent

    def __repr__(self) -> str:
        return f"Client(base_url={self.base_url!r}, timeout={self.timeout!r})"

    # -- Price Index ---------------------------------------------------------

    def _market(
        self,
        city: str | None,
        country: str | None,
        currency: str | None,
        locale: str,
    ) -> dict[str, Any]:
        params: dict[str, QueryValue] = {
            "locale": check.locale(locale),
            "city": check.text("city", city),
            "country": check.text("country", country),
            "currency": check.currency(currency),
        }
        path = "/v1/market/rates"
        data = _data(self._transport.get(path, params), path)
        if not isinstance(data, dict):
            raise APIError(200, "BAD_RESPONSE", "Unexpected shape for market rates", f"GET {path}")
        return data

    @staticmethod
    def _index_attrs(df: pd.DataFrame, data: dict[str, Any]) -> pd.DataFrame:
        df.attrs["attribution"] = data.get("attribution")
        df.attrs["license"] = data.get("licenseUrl")
        df.attrs["as_of"] = data.get("asOf")
        return df

    def rates(
        self,
        city: str | None = None,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
    ) -> pd.DataFrame:
        """Price Index figures, one row per city x product. See :func:`coworkingview.rates`."""
        data = self._market(city, country, currency, locale)
        return self._index_attrs(frame(_parse.rate_rows(data), RATES_SCHEMA), data)

    def cities(
        self,
        city: str | None = None,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
    ) -> pd.DataFrame:
        """Cities covered by the Price Index, one row per city. See :func:`coworkingview.cities`."""
        data = self._market(city, country, currency, locale)
        return self._index_attrs(frame(_parse.city_rows(data), CITIES_SCHEMA), data)

    # -- Catalogue -----------------------------------------------------------

    def spaces(
        self,
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
        """Search the catalogue, one row per space. See :func:`coworkingview.spaces`."""
        locale = check.locale(locale)
        sort = check.sort(sort)
        limit = check.limit(limit)
        low = check.price("min_price", min_price)
        high = check.price("max_price", max_price)
        check.price_range(low, high)
        page_size = min(PAGE_SIZE, limit)
        params: dict[str, QueryValue] = {
            "locale": locale,
            "city": check.text("city", city),
            "country": check.text("country", country),
            "zone": check.text("zone", zone),
            "operator": check.text("operator", operator),
            "pricingOptionType": check.product(product),
            "minCapacity": check.count("min_capacity", min_capacity),
            "minPrice": low,
            "maxPrice": high,
            "currency": check.currency(currency),
            "sortBy": sort,
            "pageSize": page_size,
        }
        path = "/v1/properties"
        cards: list[dict[str, Any]] = []
        first_meta: dict[str, Any] = {}
        total: int | None = None
        page = 1
        while True:
            payload = self._transport.get(path, {**params, "page": page})
            data = _data(payload, path)
            if not isinstance(data, list):
                raise APIError(
                    200, "BAD_RESPONSE", "Unexpected shape for properties", f"GET {path}"
                )
            meta = _meta(payload)
            pagination = meta.get("pagination")
            pagination = pagination if isinstance(pagination, dict) else {}
            if page == 1:
                first_meta = meta
                total = pagination.get("total")
                if sort == "random" and meta.get("seed") is not None:
                    params["seed"] = meta["seed"]
            cards.extend(c for c in data if isinstance(c, dict))
            page_count = pagination.get("pageCount")
            if (
                len(cards) >= limit
                or not data
                or not isinstance(page_count, int)
                or page >= page_count
            ):
                break
            page += 1
        df = frame((_parse.space_row(c, locale) for c in cards[:limit]), SPACES_SCHEMA)
        df.attrs["attribution"] = _citation_text(first_meta)
        df.attrs["notice"] = first_meta.get("catalogueNotice")
        df.attrs["total"] = total
        return df

    def space(self, slug: str, locale: str = "en") -> Space:
        """One space with its pricing table. See :func:`coworkingview.space`."""
        locale = check.locale(locale)
        path = "/v1/properties/" + check.slug(slug)
        payload = self._transport.get(path, {"locale": locale})
        detail = _data(payload, path)
        if not isinstance(detail, dict):
            raise APIError(200, "BAD_RESPONSE", "Unexpected shape for a property", f"GET {path}")
        meta = _meta(payload)
        attribution = _citation_text(meta)
        notice = meta.get("catalogueNotice")
        pricing = frame(_parse.pricing_rows(detail), PRICING_SCHEMA)
        pricing.attrs["attribution"] = attribution
        pricing.attrs["notice"] = notice
        fields = _parse.space_fields(detail, locale)
        lat, lng, median = fields["lat"], fields["lng"], fields["market_median"]
        return Space(
            slug=fields["slug"],
            title=fields["title"],
            city_slug=fields["city_slug"],
            zone_slug=fields["zone_slug"],
            operator_slug=fields["operator_slug"],
            operator_name=fields["operator_name"],
            country_code=fields["country_code"],
            lat=None if lat is None else float(lat),
            lng=None if lng is None else float(lng),
            featured=fields["featured"],
            market_verdict=fields["market_verdict"],
            market_median=None if median is None else float(median),
            market_sample_size=fields["market_sample_size"],
            url=fields["url"],
            updated_at=to_timestamp(fields["updated_at"]),
            address=fields["address"],
            capacity=fields["capacity"],
            amenities=fields["amenities"],
            pricing=pricing,
            attribution=attribution,
            notice=notice if isinstance(notice, str) else None,
        )
