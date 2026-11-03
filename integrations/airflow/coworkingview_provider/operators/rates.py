"""Operator that fetches CoworkingView price-index rates for one city."""

from __future__ import annotations

import json
from collections.abc import Sequence
from pathlib import Path
from typing import Any

from coworkingview_provider._compat import BaseOperator
from coworkingview_provider.client import DEFAULT_TIMEOUT
from coworkingview_provider.hooks.coworkingview import CoworkingViewHook


def write_rates_file(path: str, payload: dict[str, Any]) -> None:
    """Write ``payload`` as UTF-8 JSON, replacing ``path`` only after the write.

    ``path`` is a local filesystem path. A URL is rejected.
    """
    if not isinstance(path, str) or not path.strip():
        raise ValueError("output_path must be a non-empty filesystem path.")
    if "://" in path:
        raise ValueError("output_path must be a local filesystem path, not a URL.")
    target = Path(path)
    if target.exists() and target.is_dir():
        raise ValueError(f"output_path {path!r} is a directory.")
    target.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(target)


class CoworkingViewRatesOperator(BaseOperator):
    """Fetch the CoworkingView Price Index for one city.

    The task return value is pushed to XCom by Airflow. It is a JSON object
    with ``city``, ``currency``, ``as_of``, ``attribution``, ``license`` and
    ``rates`` (one object per product: flex desk, fixed desk, private office,
    day pass, meeting room, and any later aggregate the API adds). Set
    ``output_path`` to also write that same object to a file.

    The request is ``GET /v1/market/rates`` on the public API. No API key is
    read or sent. The Price Index is CC BY 4.0: ``attribution`` is logged and
    stored on the result and on every row. Keep it with anything you publish.

    :param city: City slug, for example ``berlin`` or ``abu-dhabi``.
    :param country: Optional ISO country code sent as the ``country`` query
        parameter.
    :param currency: Optional presentation currency. Omit it to keep the
        city's own currency.
    :param locale: Language of city names. ``en`` (default), ``es`` or ``de``.
        The API rejects a request that omits ``locale``.
    :param product: When set, ``rates`` contains only this product
        (``flex_desk``, ``fix_desk``, ``private_office``, ``day_pass``,
        ``meeting_room``, ...).
    :param output_path: Local file path for the JSON document. Directories
        are created. Leave unset to push XCom only.
    :param coworkingview_conn_id: Connection id. Optional; the public API is
        used when the connection does not exist.
    :param timeout: Per-request timeout in seconds.
    """

    template_fields: Sequence[str] = (
        "city",
        "country",
        "currency",
        "locale",
        "product",
        "output_path",
    )

    def __init__(
        self,
        *,
        city: str,
        country: str | None = None,
        currency: str | None = None,
        locale: str = "en",
        product: str | None = None,
        output_path: str | None = None,
        coworkingview_conn_id: str = CoworkingViewHook.default_conn_name,
        timeout: float = DEFAULT_TIMEOUT,
        **kwargs: Any,
    ) -> None:
        super().__init__(**kwargs)
        if not isinstance(city, str) or not city.strip():
            raise ValueError(f"city must be a non-empty string, got {city!r}.")
        self.city = city
        self.country = country
        self.currency = currency
        self.locale = locale
        self.product = product
        self.output_path = output_path
        self.coworkingview_conn_id = coworkingview_conn_id
        self.timeout = timeout

    def execute(self, context: Any) -> dict[str, Any]:
        """Fetch the rates and return them for XCom.

        Airflow stores the returned dict as this task's XCom. ``context`` is
        unused: the city and the other arguments are operator parameters.
        """
        _ = context
        hook = CoworkingViewHook(
            coworkingview_conn_id=self.coworkingview_conn_id,
            timeout=self.timeout,
        )
        payload = hook.get_city_rates(
            city=self.city,
            country=self.country,
            currency=self.currency,
            locale=self.locale,
            product=self.product,
        )
        attribution = payload.get("attribution")
        if attribution:
            self.log.info("%s", attribution)
        self.log.info(
            "CoworkingView Price Index for %s: %s product(s), as of %s.",
            payload["city"],
            len(payload["rates"]),
            payload["as_of"],
        )
        if self.output_path:
            write_rates_file(self.output_path, payload)
            self.log.info("Wrote CoworkingView rates to %s.", self.output_path)
        return payload
