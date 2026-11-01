# Changelog

## 0.1.0 — 2026-11-01

Initial release of the Swift client for the public CoworkingView API.

- `GET /v1/market/rates` for Price Index figures (`rates`) and cities (`cities`).
- `GET /v1/properties` for catalogue search (`spaces`), at most 200 rows.
- `GET /v1/properties/{slug}` for one space and its pricing table (`space`).
- async/await over `URLSession`, including on Linux via `FoundationNetworking`.
- No API key. Attribution from CoworkingView travels with every result.
