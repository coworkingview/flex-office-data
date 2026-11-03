"""Stand-ins for ``urllib`` and for the plot client's ``market_rates``."""

from __future__ import annotations

import email.message
import io
import json
import urllib.error
from typing import Any

from mpl_coworkingview._parse import MarketRates, parse_market_rates


class Response:
    """The bits of ``http.client.HTTPResponse`` the client reads."""

    def __init__(
        self,
        body: bytes,
        status: int = 200,
        reason: str = "OK",
        headers: dict[str, str] | None = None,
    ) -> None:
        self._body = body
        self.status = status
        self.reason = reason
        self.headers = email.message.EmailMessage()
        for key, value in (headers or {}).items():
            self.headers[key] = value

    def read(self) -> bytes:
        return self._body

    def __enter__(self) -> Response:
        return self

    def __exit__(self, *args: object) -> bool:
        return False


class FakeOpener:
    """Returns queued responses, or raises the queued exception."""

    def __init__(self, responses: list[Any]) -> None:
        self.responses = list(responses)
        self.requests: list[tuple[Any, float | None]] = []

    def open(self, request: Any, timeout: float | None = None) -> Response:
        self.requests.append((request, timeout))
        item = self.responses.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def http_error(status: int, body: bytes | str = b"", headers: dict[str, str] | None = None):
    """``HTTPError`` whose ``read()`` returns ``body``."""
    hdrs = email.message.EmailMessage()
    for key, value in (headers or {}).items():
        hdrs[key] = value
    payload = body.encode("utf-8") if isinstance(body, str) else body
    return urllib.error.HTTPError(
        url="https://api.coworkingview.com/v1/market/rates",
        code=status,
        msg=f"HTTP {status}",
        hdrs=hdrs,
        fp=io.BytesIO(payload),
    )


def json_response(payload: dict[str, Any], **kwargs: Any) -> Response:
    return Response(json.dumps(payload).encode("utf-8"), **kwargs)


class RecordingClient:
    """Returns one parsed fixture and records the query the plot function sent."""

    def __init__(self, payload: dict[str, Any]) -> None:
        self.result: MarketRates = parse_market_rates(payload)
        self.calls: list[dict[str, str]] = []

    def market_rates(self, **kwargs: str) -> MarketRates:
        self.calls.append(kwargs)
        return self.result
