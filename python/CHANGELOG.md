# Changelog

All notable changes to this package are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-27

### Added

- `rates()`: the CoworkingView Price Index as one row per city and product
  (flex desk, fixed desk, private office per month; day pass per day; meeting
  room per hour), with `p25`/`p75`, sample sizes and a `low_confidence` flag.
  New aggregates published by the API appear without a release.
- `cities()`: one row per city, published and unpublished, with entry-level prices.
- `spaces()`: catalogue search by city, country, zone, operator, product,
  capacity and price, paginated with a stable random seed and capped at 200
  rows per call.
- `space()`: one space as a frozen `Space` dataclass with its pricing table; the
  slug is validated against `^[A-Za-z0-9][A-Za-z0-9._-]*$` before any request.
- `Client` for a custom base URL, timeout or User-Agent; the
  `COWORKINGVIEW_API_URL` environment variable.
- `CoworkingViewError` and `APIError` (status, code, title, detail, errors from
  the API's RFC 9457 problem document).
- Nullable pandas dtypes throughout and timezone-aware UTC timestamps.
- CC BY 4.0 attribution in `df.attrs` on every Price Index result; citation and
  catalogue notice on every catalogue result.
- One retry on `429`/`5xx`, honouring `Retry-After`/`RateLimit-Reset`, capped at 10 s.
- Type hints (`py.typed`), NumPy-style docstrings, examples, conda-forge recipe.

[Unreleased]: https://github.com/coworkingview/flex-office-data/compare/python-v0.1.0...HEAD
[0.1.0]: https://github.com/coworkingview/flex-office-data/releases/tag/python-v0.1.0
