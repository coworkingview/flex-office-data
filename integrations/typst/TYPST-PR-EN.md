Add `coworkingview` version 0.1.0 under `packages/preview/coworkingview/0.1.0`.

`coworkingview` looks up median flexible-office prices from a bundled snapshot of the CoworkingView Price Index and can set them as a table. The public functions are `rate(city, product)`, `rates-table(...)`, `cities()` and `attribution()`. The minimum compiler version is 0.13.0. The manifest categories are `visualization` and `utility`.

The figures are the recorded snapshot already in the CoworkingView data repository: `spec/golden/rates.csv` and `spec/golden/cities.csv`, generated from `spec/fixtures/market_rates.json` (`GET /v1/market/rates`, captured 2026-10-27T21:06:48.313Z). The package file is `data/price-index.json`. Amounts are copied from those tables. The unpublished fixture city `example-town` is included and has no prices. The Price Index is CC BY 4.0. `attribution()` returns the attribution string from that response, unchanged. `scope` in the same JSON file is the scope text from that response. Package code is MIT. The data file is not MIT.

Homepage: https://coworkingview.com/en/tools/price-index

Repository: https://github.com/coworkingview/flex-office-data

The prepared tree in that repository is `integrations/typst/submission/packages/preview/coworkingview/0.1.0`. It is the same as `integrations/typst/coworkingview`.

CoworkingView (https://coworkingview.com) publishes the Price Index. The author of this package is affiliated with CoworkingView.

This pull request was prepared with AI assistance.
