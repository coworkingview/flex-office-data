# Changelog

All notable changes to the `coworkingview` crate and the `cwv` CLI are
documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-10-27

### Added

- `cwv rates`: the CoworkingView Price Index, one row per city × product
  (flex desk, fixed desk, private office per month; day pass per day; meeting
  room per hour), with `--city`, `--country`, `--currency`, `--product`.
- `cwv cities`: cities in the index with entry prices; unpublished cities listed.
- `cwv spaces`: catalogue search with city, zone, operator, product, capacity
  and price filters; at most 200 results; random order with seed reuse across pages.
- `cwv space <slug>`: one space with address, amenities and its pricing table.
- `--format table|csv|json`, `--locale en|es|de`, `--no-color`; attribution
  on stderr after tables and CSV, inside the JSON wrapper otherwise.
- `cwv completions <shell>` (bash, zsh, fish, PowerShell, elvish) and a man
  page (`cwv man`).
- Library: `Client` with `rates()`, `cities()`, `spaces()`, `space()`, typed
  rows, `parse` for offline JSON and `csv` writer in the kit's shared format.
- One retry on `429`/`5xx` honouring `Retry-After` (capped at 10 s);
  `COWORKINGVIEW_API_URL` override; rustls only, fully static builds.

[Unreleased]: https://github.com/coworkingview/flex-office-data/compare/rust-v0.1.0...HEAD
[0.1.0]: https://github.com/coworkingview/flex-office-data/releases/tag/rust-v0.1.0
