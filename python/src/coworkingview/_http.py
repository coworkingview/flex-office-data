"""HTTP transport: one GET, JSON in, at most one retry (SPEC section 2)."""

from __future__ import annotations

import json
import socket
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Mapping
from datetime import datetime, timezone
from email.message import Message
from email.utils import parsedate_to_datetime
from typing import Any, Callable, Optional, Union

from ._version import __version__
from .exceptions import APIError, CoworkingViewError

DEFAULT_BASE_URL = "https://api.coworkingview.com"
DEFAULT_USER_AGENT = (
    f"coworkingview-python/{__version__} (+https://github.com/coworkingview/flex-office-data)"
)
DEFAULT_TIMEOUT = 20.0

#: Wait used when a 429/5xx carries neither ``Retry-After`` nor ``RateLimit-Reset``.
FALLBACK_WAIT = 2.0
#: Upper bound on any wait before the single retry.
MAX_WAIT = 10.0

QueryValue = Optional[Union[str, int, float]]


def _is_retryable(status: int) -> bool:
    return status == 429 or 500 <= status <= 599


def _seconds(value: str | None, *, now: datetime | None = None) -> float | None:
    """Parse a delay header: delta-seconds, or (``Retry-After`` only) an HTTP date."""
    if value is None:
        return None
    value = value.strip()
    try:
        return max(0.0, float(value))
    except ValueError:
        pass
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError, IndexError):
        return None
    if when.tzinfo is None:
        when = when.replace(tzinfo=timezone.utc)
    current = now or datetime.now(timezone.utc)
    return max(0.0, (when - current).total_seconds())


def retry_wait(headers: Message | Mapping[str, str]) -> float:
    """Seconds to wait before the retry: ``Retry-After``, else ``RateLimit-Reset``, else 2 s.

    The result is capped at :data:`MAX_WAIT`.
    """
    wait = _seconds(headers.get("Retry-After"))
    if wait is None:
        wait = _seconds(headers.get("RateLimit-Reset"))
    if wait is None:
        wait = FALLBACK_WAIT
    return min(wait, MAX_WAIT)


def _decode(raw: bytes, status: int, reason: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise APIError(
            status,
            "BAD_RESPONSE",
            "The API returned a body that is not valid JSON",
            f"HTTP {status} {reason}".strip(),
        ) from None


def _problem(status: int, reason: str, raw: bytes) -> APIError:
    """Build an :class:`APIError` from an error response, problem JSON or not."""
    body: Any = None
    try:
        body = json.loads(raw.decode("utf-8")) if raw else None
    except (UnicodeDecodeError, ValueError):
        body = None
    if not isinstance(body, dict):
        body = {}
    title = body.get("title")
    detail = body.get("detail")
    code = body.get("code")
    errors = body.get("errors")
    return APIError(
        status=status,
        code=code if isinstance(code, str) and code else f"HTTP_{status}",
        title=title if isinstance(title, str) and title else (reason or f"HTTP {status}"),
        detail=detail if isinstance(detail, str) else None,
        errors=[e for e in errors if isinstance(e, dict)] if isinstance(errors, list) else None,
    )


class Transport:
    """Minimal JSON-over-HTTPS client built on :mod:`urllib.request`."""

    def __init__(self, base_url: str, timeout: float, user_agent: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.user_agent = user_agent
        self._opener = urllib.request.build_opener()
        self._sleep: Callable[[float], None] = time.sleep

    def url(self, path: str, params: Mapping[str, QueryValue] | None = None) -> str:
        """Absolute URL for ``path`` with ``None`` parameters dropped."""
        query = {k: v for k, v in (params or {}).items() if v is not None}
        url = f"{self.base_url}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        return url

    def get(self, path: str, params: Mapping[str, QueryValue] | None = None) -> dict[str, Any]:
        """GET ``path`` and return the decoded JSON envelope.

        Raises
        ------
        APIError
            Non-2xx answer (after the single retry for 429/5xx), or a body
            that is not a JSON object.
        CoworkingViewError
            The request never got an HTTP answer (DNS, connection, timeout).
        """
        url = self.url(path, params)
        for attempt in (1, 2):
            status, reason, headers, raw = self._fetch(url)
            if 200 <= status <= 299:
                payload = _decode(raw, status, reason)
                if not isinstance(payload, dict):
                    raise APIError(
                        status,
                        "BAD_RESPONSE",
                        "The API returned JSON that is not an object",
                        f"GET {path}",
                    )
                return payload
            if attempt == 1 and _is_retryable(status):
                self._sleep(retry_wait(headers))
                continue
            raise _problem(status, reason, raw)
        raise AssertionError("unreachable")  # pragma: no cover

    def _fetch(self, url: str) -> tuple[int, str, Message, bytes]:
        request = urllib.request.Request(
            url,
            headers={"Accept": "application/json", "User-Agent": self.user_agent},
            method="GET",
        )
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                return response.status, response.reason or "", response.headers, response.read()
        except urllib.error.HTTPError as err:
            try:
                raw = err.read()
            finally:
                err.close()
            return err.code, str(err.reason or ""), err.headers, raw
        except (urllib.error.URLError, socket.timeout, TimeoutError, ConnectionError) as err:
            reason = getattr(err, "reason", err)
            raise CoworkingViewError(f"Could not reach {self.base_url}: {reason}") from err
