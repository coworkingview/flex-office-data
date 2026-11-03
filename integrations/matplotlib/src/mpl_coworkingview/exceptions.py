"""Errors raised by :mod:`mpl_coworkingview`."""

from __future__ import annotations

from typing import Any

__all__ = ["APIError", "CoworkingViewError"]


class CoworkingViewError(Exception):
    """Base class for errors raised while reading the Price Index.

    Connection failures are this class. An HTTP error response is
    :class:`APIError`.
    """


class APIError(CoworkingViewError):
    """The API answered with an error, or with a body that is not JSON.

    ``status``, ``code``, ``title``, ``detail`` and ``errors`` follow the
    RFC 9457 problem document. ``status`` is the HTTP status. When the body
    has no ``code``, ``code`` is ``HTTP_<status>``. A non-JSON success body
    uses ``code`` ``BAD_RESPONSE``.
    """

    def __init__(
        self,
        status: int,
        code: str,
        title: str,
        detail: str | None = None,
        errors: list[dict[str, Any]] | None = None,
    ) -> None:
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        self.errors: list[dict[str, Any]] = list(errors or [])
        message = f"{status} {code}: {title}"
        if detail:
            message += f" ({detail})"
        super().__init__(message)
