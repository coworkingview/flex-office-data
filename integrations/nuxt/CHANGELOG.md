# Changelog

## 0.1.0

First release of `@coworkingview/nuxt`.

- Nuxt module `configKey` `coworkingview`, built with `@nuxt/module-builder`.
- Auto-imported `useCoworkingProperties` (`GET /v1/properties`) and `useCoworkingRates` (`GET /v1/market/rates`).
- No API key. Default origin `https://api.coworkingview.com`.
- Price Index responses keep the API's `attribution`, `license` and `licenseUrl` (CC BY 4.0).
- Listing responses omit photos, logos and description text.
