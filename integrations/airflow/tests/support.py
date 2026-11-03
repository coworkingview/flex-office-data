"""HTTP stand-ins for the CoworkingView client tests."""

from __future__ import annotations

import email.message
import io
import json
import urllib.error
from pathlib import Path
from typing import Any

FIXTURE = Path(__file__).resolve().parents[3] / "spec" / "fixtures" / "market_rates_berlin_usd.json"


def berlin_rates() -> dict[str, Any]:
    """Recorded ``GET /v1/market/rates?locale=en&city=berlin&currency=USD`` body."""
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


class Response:
    """Context manager with the bits of ``http.client.HTTPResponse`` the client reads."""

    def __init__(self, body: bytes, status: int = 200, reason: str = "OK") -> None:
        self._body = body
        self.status = status
        self.reason = reason
        self.headers = email.message.EmailMessage()

    def read(self) -> bytes:
        return self._body

    def getcode(self) -> int:
        return self.status

    def __enter__(self) -> Response:
        return self

    def __exit__(self, *args: object) -> bool:
        return False


def http_error(status: int, body: bytes | str = b"", headers: dict[str, str] | None = None):
    """``HTTPError`` whose ``read()`` returns ``body`` and whose headers are set."""
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


def json_response(payload: dict[str, Any]) -> Response:
    return Response(json.dumps(payload).encode("utf-8"))
