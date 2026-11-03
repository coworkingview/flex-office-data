"""Hook for the public CoworkingView Price Index."""

from __future__ import annotations

import os
from typing import Any

from airflow.exceptions import AirflowNotFoundException

from coworkingview_provider._compat import BaseHook
from coworkingview_provider.client import (
    DEFAULT_BASE_URL,
    DEFAULT_TIMEOUT,
    ENV_BASE_URL,
    CoworkingViewClient,
)
from coworkingview_provider.exceptions import CoworkingViewError


class CoworkingViewHook(BaseHook):
    """Read flexible-office prices from the CoworkingView Price Index.

    The API is public. A connection is optional. When ``coworkingview_default``
    is missing, the hook uses ``https://api.coworkingview.com``. Set the
    connection's host, or the ``COWORKINGVIEW_API_URL`` environment variable,
    to point at another API root. The host wins when both are set.

    :param coworkingview_conn_id: Airflow connection id. The host, when set,
        is the API root (``https://api.coworkingview.com``). Login, password,
        port, schema and extra are unused: there is no API key.
    :param timeout: Per-request timeout in seconds. The default is 20, the
        same timeout as the other CoworkingView clients.
    """

    conn_name_attr = "coworkingview_conn_id"
    default_conn_name = "coworkingview_default"
    conn_type = "coworkingview"
    hook_name = "CoworkingView"

    def __init__(
        self,
        coworkingview_conn_id: str = default_conn_name,
        timeout: float = DEFAULT_TIMEOUT,
    ) -> None:
        super().__init__()
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0:
            raise ValueError(f"timeout must be a positive number of seconds, got {timeout!r}.")
        self.coworkingview_conn_id = coworkingview_conn_id
        self.timeout = float(timeout)
        self._base_url: str | None = None
        self._client: CoworkingViewClient | None = None

    @staticmethod
    def get_ui_field_behaviour() -> dict[str, Any]:
        """Show only the API root. The public API has no credentials."""
        return {
            "hidden_fields": ["schema", "login", "password", "port", "extra"],
            "relabeling": {"host": "API base URL (optional)"},
            "placeholders": {"host": DEFAULT_BASE_URL},
        }

    def _resolve_base_url(self) -> str:
        """Connection host, else ``COWORKINGVIEW_API_URL``, else the public API."""
        if self._base_url is not None:
            return self._base_url
        host: str | None = None
        try:
            connection = self.get_connection(self.coworkingview_conn_id)
        except AirflowNotFoundException:
            self.log.info(
                "No Airflow connection %r; using the public CoworkingView API.",
                self.coworkingview_conn_id,
            )
        else:
            raw_host = getattr(connection, "host", None)
            host = raw_host.strip() if isinstance(raw_host, str) and raw_host.strip() else None
        chosen = host or os.environ.get(ENV_BASE_URL) or DEFAULT_BASE_URL
        # normalize_base_url runs inside the client. Keep the raw value here
        # so an invalid host fails in get_conn with CoworkingViewError.
        self._base_url = chosen.strip() if isinstance(chosen, str) else chosen
        return self._base_url

    def get_conn(self) -> CoworkingViewClient:
        """Return the HTTP client for this connection.

        :raises CoworkingViewError: when the API root is not an http(s) URL.
        """
        if self._client is None:
            self._client = CoworkingViewClient(
                base_url=self._resolve_base_url(),
                timeout=self.timeout,
                logger=self.log,
            )
        return self._client

    def get_city_rates(
        self,
        *,
        city: str,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
        product: str | None = None,
    ) -> dict[str, Any]:
        """Fetch the Price Index for ``city``.

        The return value is a JSON object: city, currency, ``as_of``,
        ``attribution``, ``license``, and ``rates`` (one object per product).
        ``attribution`` is the CC BY 4.0 credit from the API. Keep it with
        anything you publish.

        :param city: City slug, for example ``berlin``.
        :param country: Optional ISO country code sent as ``country``.
        :param currency: Optional presentation currency (``EUR``, ``GBP``,
            ``USD``, ``CHF``, ``AED``, ``VES``).
        :param locale: ``en`` (default), ``es`` or ``de``.
        :param product: When set, ``rates`` contains only that product.
        """
        return self.get_conn().city_rates(
            city=city,
            country=country,
            currency=currency,
            locale=locale,
            product=product,
        )

    def test_connection(self) -> tuple[bool, str]:
        """Check the connection from the Airflow UI.

        Calls ``GET /v1/market/rates?locale=en&city=berlin``, the same Price
        Index request a task makes. Berlin is a published city in the public
        index.
        """
        try:
            payload = self.get_city_rates(city="berlin")
        except (CoworkingViewError, ValueError, OSError) as err:
            return False, str(err)
        return (
            True,
            f"CoworkingView Price Index reachable for berlin "
            f"({len(payload['rates'])} products, as of {payload['as_of']}).",
        )
