# CoworkingView

CoworkingView publishes a public catalogue of coworking spaces and private offices, together with the CoworkingView Price Index of aggregated city prices. This connector reads that catalogue and that price snapshot: search listings, open a space, operator, or place profile, and read city medians. No sign-in is required. The service website is [https://coworkingview.com](https://coworkingview.com).

## Publisher: CoworkingView

CoworkingView owns the service at [https://coworkingview.com](https://coworkingview.com) and the host `api.coworkingview.com`. Support contact: info@coworkingview.com. Privacy policy: [https://coworkingview.com/en/privacy](https://coworkingview.com/en/privacy).

## Prerequisites

No account, subscription, or key is required. Every operation in this connector is a public read.

To import the connector yourself before it is listed, you need permission to create a custom connector in your environment.

## Supported Operations

### Get remote configuration

Returns remote configuration for official clients, including feature flags and the minimum supported build. Catalogue reads do not depend on this operation.

### Get filter options

Returns filter options with contextual counts for the current catalogue query. `locale` is required. Optional filters are `country`, `city`, `zone`, `operator`, `pricingOptionType`, and `currency`.

### Get places index

Returns the countries, cities, and zones index. `locale` is required. The payload is small and long-lived.

### Get service health

Returns a liveness probe that reports the deployed build identifier.

### List spaces

Returns one page of listing cards. `locale` is required. Optional filters include city, zone, operator, pricing option, amenities, capacity, price, currency, sort order, and a geographic window (`lat`, `lng`, `radiusMeters`, or `bbox`). `page` starts at 1. `pageSize` is at most 50.

### List map markers

Returns a lightweight projection of the matching listings for map markers. It accepts the same filters as List spaces.

### Get market rates

Returns aggregated pricing per city, including median, minimum, and maximum by option type. The payload is a snapshot, not a time series. `locale` is required. `city`, `country`, and `currency` are optional.

### Get operator profile

Returns an operator brand hub, including editorial copy, frequently asked questions, and computed stats. `slug` and `locale` are required.

### Get place profile

Returns a country, city, or zone hub, including editorial copy, frequently asked questions, and computed stats. `kind` (`country`, `city`, or `zone`), `slug`, and `locale` are required.

### Get space detail

Returns the full detail for one listing, including address, amenities, and pricing options. `slug` and `locale` are required.

### Suggest search matches

Returns city, zone, operator, and property suggestions for a short query. `locale` and `q` are required. `limit` defaults to 8 and is at most 20.

## Obtaining Credentials

There are no credentials. Choose **No authentication** when you create the connector. `apiProperties.json` sets `connectionParameters` to an empty object, `publisher` and `stackOwner` to CoworkingView, and `iconBrandColor` to `#FAF9F9`.

## Getting Started

1. Create a connection. Leave every field empty.
2. Run **Get market rates** with `locale` `en` and `city` `berlin`.
3. Run **List spaces** with `locale` `en`, `city` `berlin`, and `pageSize` 5.
4. Copy a `slug` from that page and run **Get space detail** with the same locale.
5. Keep the attribution that arrives with the price index, and the citation on catalogue responses, next to any figure you display.

A direct call for the same price snapshot is `https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin`.

## Known Issues and Limitations

- The connector is read-only. `POST /v1/leads/contact` and `POST /v1/leads/inquiry` are omitted on purpose. Each of those calls creates a real enquiry that is sent to CoworkingView and forwarded to space operators.
- The service allows 120 requests per 60 seconds per IP address. Responses include `RateLimit-*` headers. A `429` response uses the problem code `RATE_LIMITED`.
- `locale` is required on every operation except Get remote configuration and Get service health. Allowed values are `en`, `de`, and `es`.
- `pageSize` is at most 50. When `sortBy` is `random`, reuse `meta.seed` from the first page on every following page, or rows repeat and skip.
- Currency codes are `EUR`, `GBP`, `USD`, `CHF`, `VES`, and `AED`. `VES` is a valid code, and the service can answer `400` when it has no conversion rate for the requested city.
- `sortBy` `distance` needs `lat` and `lng`.
- The Price Index is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Responses carry an attribution string, a license URL, and an as-of timestamp. Catalogue content (descriptions, images, logos, names, and prices) belongs to the listed operators and rights holders. The service does not grant a licence to copy the catalogue database. Catalogue responses carry `meta.catalogueNotice` and `meta.citation`. Do not strip the attribution.
- The icon file is the official 192 by 192 pixel mark from `https://coworkingview.com/icon-192.png`: a serif black "CV" with a gold dot on an off-white ground (`#FAF9F9`). This repository did not previously contain the artwork. `https://coworkingview.com/icon.svg` is a different mask icon and is not the connector icon.
- Get service health currently also returns `meta.appVersion`, a string naming the deployed build. The public OpenAPI document does not declare that property, and it marks `meta` as closed, so the connector schema follows the document and does not list the field.

## Frequently Asked Questions

### Where is the service website?

[https://coworkingview.com](https://coworkingview.com). The connector metadata `Website` value is that same URL, without `www`.

### Do I need a key?

No. The operations are public and unauthenticated.

## Deployment Instructions

Import this folder as a custom connector:

1. In Power Automate, open **Custom connectors**, choose **New custom connector**, then **Import an OpenAPI file**.
2. Select `apiDefinition.swagger.json`.
3. Upload `icon.png` and set the icon background color to `#FAF9F9`.
4. On the security step, select **No authentication**.
5. Create the connector. Open **Test operation** and call each action at least once. Use `locale` `en` and, where a slug is required, a slug returned by List spaces, Get places index, or Suggest search matches.
