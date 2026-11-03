"""Errors raised while reading the CoworkingView API."""

from __future__ import annotations


class CoworkingViewError(Exception):
    """The Price Index could not be read.

    Network failures are raised as this class. HTTP error responses are
    raised as :class:`CoworkingViewApiError`.
    """


class CoworkingViewApiError(CoworkingViewError):
    """The API answered with an error, or with a body that is not usable JSON.

    ``status``, ``code``, ``title`` and ``detail`` follow the RFC 9457 problem
    document the API returns. When the body has no ``code``, ``code`` is
    ``HTTP_<status>``.
    """

    def __init__(
        self,
        status: int,
        code: str,
        title: str,
        detail: str | None = None,
    ) -> None:
        self.status = status
        self.code = code
        self.title = title
        self.detail = detail
        message = f"{status} {code}: {title}"
        if detail:
            message += f" ({detail})"
        super().__init__(message)
