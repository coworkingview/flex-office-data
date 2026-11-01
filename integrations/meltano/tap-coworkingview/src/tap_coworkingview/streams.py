"""Workspaces (catalogue search) and market rates (Price Index)."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Any

import requests
from singer_sdk.exceptions import FatalAPIError
from singer_sdk.pagination import PageNumberPaginator
from singer_sdk.typing import (
    BooleanType,
    DateTimeType,
    IntegerType,
    NumberType,
    PropertiesList,
    Property,
    StringType,
)

from tap_coworkingview.client import (
    DEFAULT_LOCALE,
    MAX_SPACES,
    PAGE_SIZE,
    CoworkingViewStream,
    city_slug,
)
from tap_coworkingview.parse import rate_rows, workspace_row

# Newest listings first. ``random`` (the API default) reshuffles each page,
# so a multi-page sync would skip and repeat rows. ``date-desc`` is one of
# the sort values the API accepts.
LISTING_SORT = "date-desc"


class _WorkspacePaginator(PageNumberPaginator):
    """Follow ``meta.pagination`` and stop at 200 listings."""

    def __init__(self, stream: WorkspacesStream) -> None:
        super().__init__(1)
        self._stream = stream

    def has_more(self, response: requests.Response) -> bool:
        """True when another page exists and the 200-listing ceiling is open."""
        if self._stream.emitted >= MAX_SPACES:
            return False
        try:
            body = response.json()
        except ValueError:
            return False
        meta = body.get("meta") if isinstance(body, dict) else None
        pagination = meta.get("pagination") if isinstance(meta, dict) else None
        if not isinstance(pagination, dict):
            return False
        page_count = pagination.get("pageCount")
        if not isinstance(page_count, int):
            return False
        return self.current_value < page_count


class WorkspacesStream(CoworkingViewStream):
    """Coworking listings for one city.

    ``GET /v1/properties``. At most 200 rows, the same ceiling as the other
    clients. Each row links to its page on coworkingview.com. Operator
    photos, descriptions and logos are not extracted.
    """

    name = "workspaces"
    path = "/v1/properties"
    primary_keys = ("slug",)
    replication_method = "FULL_TABLE"

    @property
    def emitted(self) -> int:
        """Listings already produced in this sync."""
        return self._emitted

    def get_new_paginator(self) -> _WorkspacePaginator:
        """Start a fresh page count for this sync."""
        self._emitted = 0
        return _WorkspacePaginator(self)

    def get_url_params(
        self,
        context: dict | None,
        next_page_token: int | None,
    ) -> dict[str, Any]:
        """Query string for one catalogue page."""
        page = 1 if next_page_token is None else next_page_token
        return {
            "locale": DEFAULT_LOCALE,
            "city": city_slug(self.config),
            "sortBy": LISTING_SORT,
            "pageSize": PAGE_SIZE,
            "page": page,
        }

    def parse_response(self, response: requests.Response) -> Iterable[dict[str, Any]]:
        """Flatten listing cards and keep the citation next to each row."""
        payload = self._payload(response)
        data = payload["data"]
        if not isinstance(data, list):
            raise FatalAPIError(f"Unexpected shape for properties for path: {self.path}")
        meta = payload.get("meta") if isinstance(payload.get("meta"), dict) else {}
        citation = meta.get("citation") if isinstance(meta.get("citation"), dict) else {}
        attribution = citation.get("text") if isinstance(citation.get("text"), str) else None
        notice = meta.get("catalogueNotice")
        notice = notice if isinstance(notice, str) else None
        for card in data:
            if self._emitted >= MAX_SPACES:
                break
            if not isinstance(card, dict) or "slug" not in card:
                continue
            record = workspace_row(card, DEFAULT_LOCALE)
            record["attribution"] = attribution
            record["notice"] = notice
            self._emitted += 1
            yield record

    @property
    def schema(self) -> dict:
        """Catalogue-search columns, plus the citation that travels with them."""
        return PropertiesList(
            Property("slug", StringType, required=True, description="Listing slug."),
            Property("title", StringType, required=True, description="Listing title."),
            Property(
                "city_slug",
                StringType,
                nullable=True,
                description="City slug, for example berlin.",
            ),
            Property(
                "zone_slug",
                StringType,
                nullable=True,
                description="Neighbourhood slug, when the listing has one.",
            ),
            Property("operator_slug", StringType, nullable=True, description="Operator slug."),
            Property("operator_name", StringType, nullable=True, description="Operator name."),
            Property(
                "country_code",
                StringType,
                nullable=True,
                description="ISO 3166-1 alpha-2 country code.",
            ),
            Property("lat", NumberType, nullable=True, description="Latitude."),
            Property("lng", NumberType, nullable=True, description="Longitude."),
            Property("featured", BooleanType, nullable=True, description="Featured listing."),
            Property(
                "market_verdict",
                StringType,
                nullable=True,
                description="below, around, or above the city median, when published.",
            ),
            Property(
                "market_median",
                NumberType,
                nullable=True,
                description="City median the verdict was compared with.",
            ),
            Property(
                "market_sample_size",
                IntegerType,
                nullable=True,
                description="Sample size behind market_median.",
            ),
            Property(
                "url",
                StringType,
                required=True,
                description="Listing page on coworkingview.com.",
            ),
            Property(
                "updated_at",
                DateTimeType,
                nullable=True,
                description="When the listing was last updated.",
            ),
            Property(
                "attribution",
                StringType,
                nullable=True,
                description="Citation for this search. Keep it with the rows.",
            ),
            Property(
                "notice",
                StringType,
                nullable=True,
                description="Catalogue notice returned with the search.",
            ),
        ).to_dict()


class MarketRatesStream(CoworkingViewStream):
    """CoworkingView Price Index for one city.

    ``GET /v1/market/rates``. One row per product. The index is CC BY 4.0:
    ``attribution`` and ``license`` are on every row.
    """

    name = "market_rates"
    path = "/v1/market/rates"
    primary_keys = ("city_slug", "product")
    replication_method = "FULL_TABLE"

    def get_new_paginator(self) -> None:
        """The rates endpoint returns every product in one response."""
        return None

    def get_url_params(
        self,
        context: dict | None,
        next_page_token: Any | None,
    ) -> dict[str, Any]:
        """Query string for the Price Index."""
        return {
            "locale": DEFAULT_LOCALE,
            "city": city_slug(self.config),
        }

    def parse_response(self, response: requests.Response) -> Iterable[dict[str, Any]]:
        """Flatten the index and keep the CC BY attribution on every row."""
        payload = self._payload(response)
        data = payload["data"]
        if not isinstance(data, dict):
            raise FatalAPIError(f"Unexpected shape for market rates for path: {self.path}")
        attribution = data.get("attribution")
        license_url = data.get("licenseUrl")
        attribution = attribution if isinstance(attribution, str) else None
        license_url = license_url if isinstance(license_url, str) else None
        for row in rate_rows(data):
            row["attribution"] = attribution
            row["license"] = license_url
            yield row

    @property
    def schema(self) -> dict:
        """Price Index columns, plus attribution and the licence URL."""
        return PropertiesList(
            Property(
                "city_slug",
                StringType,
                required=True,
                description="City slug, for example berlin.",
            ),
            Property("city_name", StringType, required=True, description="City display name."),
            Property(
                "country_code",
                StringType,
                nullable=True,
                description="ISO 3166-1 alpha-2 country code.",
            ),
            Property("currency", StringType, required=True, description="Currency of the figures."),
            Property(
                "product",
                StringType,
                required=True,
                description="flex_desk, fix_desk, private_office, day_pass, meeting_room, and so on.",
            ),
            Property(
                "unit",
                StringType,
                nullable=True,
                description="month, day (day pass), or hour (meeting and event rooms).",
            ),
            Property("median", NumberType, required=True, description="Median price."),
            Property("p25", NumberType, nullable=True, description="25th percentile."),
            Property("p75", NumberType, nullable=True, description="75th percentile."),
            Property(
                "sample_size",
                IntegerType,
                required=True,
                description="Number of prices behind the figure.",
            ),
            Property(
                "property_count",
                IntegerType,
                nullable=True,
                description="Spaces behind the figure.",
            ),
            Property(
                "operator_count",
                IntegerType,
                nullable=True,
                description="Operators behind the figure.",
            ),
            Property(
                "low_confidence",
                BooleanType,
                required=True,
                description="True when sample_size is below 10.",
            ),
            Property(
                "as_of",
                DateTimeType,
                nullable=True,
                description="When the index was computed.",
            ),
            Property(
                "attribution",
                StringType,
                nullable=True,
                description="CC BY 4.0 attribution. Keep it with anything you publish.",
            ),
            Property(
                "license",
                StringType,
                nullable=True,
                description="Licence URL for the Price Index.",
            ),
        ).to_dict()
