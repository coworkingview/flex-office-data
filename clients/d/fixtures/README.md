# Fixtures

Real responses from `api.coworkingview.com` (captured 2026-10-27), used by
every package's tests. Operator-owned content — descriptions, photos and logos
— is replaced with placeholders (`https://example.com/...`, "Example
description used as a test fixture."); prices, names and statistics are as the
API returned them. `market_rates.json` is trimmed to three cities plus one
synthetic unpublished city.

| File | Request |
|---|---|
| `market_rates.json` | `GET /v1/market/rates?locale=en` (trimmed) |
| `market_rates_berlin_usd.json` | `GET /v1/market/rates?locale=en&city=berlin&currency=USD` |
| `properties_berlin.json` | `GET /v1/properties?locale=en&city=berlin&pricingOptionType=private_office&pageSize=3` |
| `properties_empty.json` | `GET /v1/properties?locale=en&city=nowhere-xyz` |
| `property_detail.json` | `GET /v1/properties/sankt-oberholz-rosenthaler-berlin?locale=en` |
| `error_validation.json` | `GET /v1/market/rates?locale=en&currency=VES` (HTTP 400) |
