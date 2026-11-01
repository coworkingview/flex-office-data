# CoworkingView

This directory contains the manifest-only connector for `source-coworkingview`.

CoworkingView publishes a public catalogue of flexible workspaces and the CoworkingView Price Index. This source syncs both for one city from `https://api.coworkingview.com`. No API key.

Streams:

- `properties` — listings for the configured city (`GET /v1/properties`). Full refresh. Pages follow `page` and `pageSize` (the API allows at most 50). Sorted with `sortBy=date-desc` so a later page does not reshuffle. Primary key: `slug`. Photos, logos and listing descriptions are left out. Each record keeps the response `citation` and `catalogueNotice`.
- `market_rates` — Price Index rows for that city (`GET /v1/market/rates`). Full refresh, one response, no pagination. Primary key: `city_slug` (the API's `city.slug`, copied to the top level because this CDK rejects a nested primary key). The index is CC BY 4.0. Each record keeps `attribution`, `license`, `licenseUrl`, `asOf`, `scope` and `copyright` from the same response.

The connection check reads `market_rates`.

## Usage

There are multiple ways to use this connector:

- You can use this connector as any other connector in Airbyte Marketplace.
- You can load this connector in `pyairbyte` using `get_source`!
- You can open this connector in Connector Builder, edit it, and publish to your workspaces.

Please refer to the manifest-only connector documentation for more details.

## Local Development

We recommend you use the Connector Builder to edit this connector.

But, if you want to develop this connector locally, you can use the following steps.

### Environment Setup

You will need `airbyte-ci` installed. You can find the documentation [here](airbyte-ci).

### Build

This will create a dev image (`source-coworkingview:dev`) that you can use to test the connector locally.

```bash
airbyte-ci connectors --name=source-coworkingview build
```

### Test

This will run the acceptance tests for the connector.

```bash
airbyte-ci connectors --name=source-coworkingview test
```
