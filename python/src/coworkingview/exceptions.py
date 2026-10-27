"""Exceptions raised by :mod:`coworkingview`."""

from __future__ import annotations

from typing import Any

__all__ = ["APIError", "CoworkingViewError"]


class CoworkingViewError(Exception):
    """Base class for every error raised by this package.

    Network failures (DNS, refused connection, timeout) are raised as this
    class directly; answers from the API that are not a success are raised as
    the subclass :class:`APIError`.
    """


class APIError(CoworkingViewError):
    """The API answered with an error, or with a body that is not valid JSON.

    The fields mirror the RFC 9457 problem document the API returns. When the
    body is not a problem document they fall back to the HTTP status line.

    Parameters
    ----------
    status : int
        HTTP status code (e.g. ``400``, ``404``, ``429``).
    code : str
        Machine-readable error code, e.g. ``"VALIDATION_FAILED"``,
        ``"NOT_FOUND"``, or ``"BAD_RESPONSE"`` when the body was not JSON.
    title : str
        Short human-readable summary.
    detail : str or None
        Longer explanation, when the API gave one.
    errors : list of dict
        Per-field validation errors (``{"path": ..., "message": ...}``);
        empty when the API gave none.

    Examples
    --------
    >>> import coworkingview as cwv
    >>> try:  # doctest: +SKIP
    ...     cwv.rates(city="berlin", currency="VES")
    ... except cwv.APIError as err:
    ...     print(err.status, err.code)
    400 VALIDATION_FAILED
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

    def __repr__(self) -> str:
        return (
            f"APIError(status={self.status!r}, code={self.code!r}, "
            f"title={self.title!r}, detail={self.detail!r}, errors={self.errors!r})"
        )
