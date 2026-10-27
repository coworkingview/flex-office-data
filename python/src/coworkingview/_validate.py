"""Client-side argument checks, so mistakes fail fast with a useful message."""

from __future__ import annotations

import re
from collections.abc import Sequence
from typing import Union

from ._parse import PRODUCT_ORDER

LOCALES: tuple[str, ...] = ("en", "es", "de")
#: ``VES`` exists in the API but has no rate for most cities; it is passed
#: through and the API answers 400 where it cannot convert (SPEC section 1).
CURRENCIES: tuple[str, ...] = ("EUR", "GBP", "USD", "CHF", "AED", "VES")
PRODUCTS: tuple[str, ...] = PRODUCT_ORDER
SORTS: tuple[str, ...] = ("random", "price-asc", "date-desc", "date-asc")
#: Hard ceiling on rows per ``spaces()`` call (SPEC section 8).
MAX_LIMIT = 200

Number = Union[int, float]

#: Slugs allowed in a URL path (SPEC section 2).
SLUG_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def _choices(values: Sequence[str]) -> str:
    return ", ".join(repr(v) for v in values)


def _one_of(name: str, value: object, valid: Sequence[str]) -> str:
    if not isinstance(value, str) or value not in valid:
        raise ValueError(f"{name}={value!r} is not supported; use one of {_choices(valid)}.")
    return value


def locale(value: object) -> str:
    """Validate ``locale``."""
    return _one_of("locale", value, LOCALES)


def currency(value: object) -> str | None:
    """Validate ``currency`` (case-insensitive); ``None`` means the city's own currency."""
    if value is None:
        return None
    normalised = value.upper() if isinstance(value, str) else value
    return _one_of("currency", normalised, CURRENCIES)


def product(value: object) -> str | None:
    """Validate ``product``."""
    if value is None:
        return None
    return _one_of("product", value, PRODUCTS)


def sort(value: object) -> str:
    """Validate ``sort``."""
    return _one_of("sort", value, SORTS)


def text(name: str, value: object) -> str | None:
    """Validate an optional free-text filter such as a city or operator slug."""
    if value is None:
        return None
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string, got {value!r}.")
    return value.strip()


def limit(value: object) -> int:
    """Validate ``limit`` (1-200)."""
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ValueError(f"limit must be a positive integer, got {value!r}.")
    if value > MAX_LIMIT:
        raise ValueError(
            f"limit={value} exceeds the maximum of {MAX_LIMIT}. The catalogue may be "
            "searched and linked to, not bulk-copied: its content belongs to the operators "
            "and the API's catalogue notice forbids systematic extraction. Narrow the "
            "search (city, zone, operator, product, price) instead."
        )
    return value


def count(name: str, value: object) -> int | None:
    """Validate an optional non-negative integer such as ``min_capacity``."""
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise ValueError(f"{name} must be a non-negative integer, got {value!r}.")
    return value


def price(name: str, value: object) -> Number | None:
    """Validate an optional non-negative price bound."""
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        raise ValueError(f"{name} must be a non-negative number, got {value!r}.")
    return value


def price_range(min_price: Number | None, max_price: Number | None) -> None:
    """Reject an empty price range."""
    if min_price is not None and max_price is not None and min_price > max_price:
        raise ValueError(f"min_price ({min_price}) is greater than max_price ({max_price}).")


def slug(value: object) -> str:
    """Validate a space slug before it is put in a URL path."""
    if not isinstance(value, str) or not SLUG_PATTERN.fullmatch(value):
        raise ValueError(
            f"slug={value!r} is not a valid slug; slugs are letters, digits, '.', '_' "
            "and '-', starting with a letter or digit (e.g. 'sankt-oberholz-rosenthaler-berlin')."
        )
    return value
