"""Tap entry point."""

from __future__ import annotations

from singer_sdk import Stream, Tap
from singer_sdk.typing import PropertiesList, Property, StringType

from tap_coworkingview.client import DEFAULT_API_URL, DEFAULT_CITY
from tap_coworkingview.streams import MarketRatesStream, WorkspacesStream


class TapCoworkingView(Tap):
    """Extract CoworkingView listings and the Price Index for one city. The API is public and needs no key."""

    name = "tap-coworkingview"
    config_jsonschema = PropertiesList(
        Property(
            "city",
            StringType,
            default=DEFAULT_CITY,
            title="City",
            description=(
                "City slug to extract, for example berlin, madrid or abu-dhabi. "
                "Listings and Price Index figures are limited to this city. "
                "Defaults to berlin."
            ),
        ),
        Property(
            "api_url",
            StringType,
            default=DEFAULT_API_URL,
            title="API URL",
            description=(
                "CoworkingView API root. Defaults to https://api.coworkingview.com. "
                "The API is public and needs no key."
            ),
        ),
    ).to_dict()

    def discover_streams(self) -> list[Stream]:
        """Listings for the configured city, and that city's Price Index."""
        return [
            WorkspacesStream(self),
            MarketRatesStream(self),
        ]


if __name__ == "__main__":
    TapCoworkingView.cli()
