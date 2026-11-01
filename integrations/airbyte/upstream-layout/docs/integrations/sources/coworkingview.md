# CoworkingView

<HideInUI>

This page contains the setup guide and reference information for the [CoworkingView](https://coworkingview.com) source connector.

</HideInUI>

## Overview

The CoworkingView source reads the public [CoworkingView](https://coworkingview.com) API at `https://api.coworkingview.com`. It syncs coworking listings and the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) for one city. The API does not require an account or an API key.

A source is limited to the city you configure. `berlin` is the default.

## Prerequisites

None. CoworkingView is public and doesn't require authentication.

## Setup guide

1. Add a new CoworkingView source.
2. For **City**, enter the city slug you want to sync. Leave the default `berlin` to sync Berlin.
3. For **Locale**, choose `en`, `de` or `es`. The API rejects any other value. The default is `en`.
4. Test and save the source.

## Supported sync modes

The CoworkingView source connector supports the following [sync modes](https://docs.airbyte.com/cloud/core-concepts/#connection-sync-modes):

| Feature | Supported? |
| :--- | :--- |
| Full refresh | Yes |
| Incremental | No |

Both streams are a snapshot of the current API response. Schedule another sync when you want a newer snapshot.

## Supported streams

| Stream | Primary key | Description |
| :--- | :--- | :--- |
| `properties` | `slug` | One listing from `GET /v1/properties` for the configured city. Pages use `page` and `pageSize`. The API allows at most 50 rows on a page, and the connector requests 50. `sortBy` is `date-desc`, because the API's default sort reshuffles each page. |
| `market_rates` | `city_slug` | One Price Index row from `GET /v1/market/rates` for the configured city. The endpoint does not paginate. `city_slug` is the API's `city.slug`, copied to the top level because the connector runtime does not accept a nested primary key. |

`properties` does not sync photos, logos or listing descriptions. Those fields are removed before a record is emitted. Each listing keeps the `citation` and `catalogueNotice` returned with the search.

`market_rates` keeps `attribution`, `license`, `licenseUrl`, `asOf`, `scope` and `copyright` from the same response. The Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Keep that attribution with anything you publish.

## Limitations

- A source configuration syncs one city. Create a separate source for each additional city.
- An unknown city slug returns an empty result. The connection check reads `market_rates` and fails when that city has no index row.
- Catalogue content belongs to the listed operators and rights holders. The API returns this notice with every listing search: "Catalogue content (descriptions, images, logos, names and prices) belongs to the respective operators and rights holders. No licence to reuse it is granted. You may link to listing pages. Systematic extraction or re-use of the catalogue database is not permitted."
- The Price Index licence does not cover photos, logos or reviews. This connector does not emit them.

## Rate limits

CoworkingView allows 120 requests per 60 seconds per IP address. Responses include `RateLimit-Limit`, `RateLimit-Remaining` and `RateLimit-Reset`. The connector retries HTTP 429, 500, 502, 503 and 504, waiting for `Retry-After` when that header is present.

A sync of one city is a handful of requests: one for the Price Index, and one page of listings per 50 rows.

## Changelog

<details>
  <summary>Expand to review</summary>

| Version | Date       | Pull Request | Subject                                         |
| :------ | :--------- | :----------- | :---------------------------------------------- |
| 0.0.1   | 2026-11-01 |              | Initial release of the CoworkingView source.   |

</details>
