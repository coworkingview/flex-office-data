# CoworkingView Price Index for OpenRefine

A small [OpenRefine](https://openrefine.org/) extension that adds one GREL function, `coworkingviewPriceIndex(city[, product])`. It reads the public CoworkingView Price Index, the same `GET https://api.coworkingview.com/v1/market/rates` endpoint the other clients in this repository use. There is no API key.

The index itself is described at [coworkingview.com/en/tools/price-index](https://coworkingview.com/en/tools/price-index). This extension is published by [CoworkingView](https://coworkingview.com).

## Install

The function works on OpenRefine 3.8, 3.9 and 3.10. Download the zip from the [0.1.0 release](https://github.com/coworkingview/flex-office-data/releases/download/openrefine-v0.1.0/coworkingview-openrefine-0.1.0.zip) and unzip it into the OpenRefine extensions directory, so that this path exists:

```text
extensions/coworkingview-openrefine-0.1.0/module/MOD-INF/module.properties
```

Put that `extensions` folder either in the OpenRefine program directory (`webapp/extensions`) or in the workspace directory (the folder OpenRefine opens from **Open Project → Browse workspace directory**). On Linux the workspace is `~/.local/share/openrefine/`. Restart OpenRefine.

The official install notes are [Installing extensions](https://openrefine.org/docs/manual/installing#installing-extensions).

## Use

In a project's expression editor, GREL:

```text
coworkingviewPriceIndex("berlin").median
```

That is the published monthly median for a flex desk (hot desk) in Berlin, in the city's own currency. A column of city names works the same way, and `Berlin` or `Berlin ` is read as the slug `berlin`:

```text
coworkingviewPriceIndex(value, "private_office").median
```

Omit the product and the function uses `flex_desk`. Other codes the index publishes, when it has them for that city, include `fix_desk`, `private_office`, `day_pass` and `meeting_room`. `Flex Desk` is accepted as `flex_desk`.

The function returns an object, not a made-up number. Pick a field with `.median`, or keep the whole object in the cell. Fields that the response actually carried:

| Field | Meaning |
|---|---|
| `citySlug`, `cityName`, `countryCode`, `currency` | The published city. |
| `product`, `unit` | `month` for a desk or office, `day` for `day_pass`, `hour` for `meeting_room`. |
| `median` | The median amount. |
| `p25`, `p75` | Percentiles, when `figures` published them. |
| `min`, `max` | Ends of the range, when `byType` published them. |
| `sampleSize`, `propertyCount`, `operatorCount` | How much data is behind the figure. |
| `lowConfidence` | `true` when `sampleSize` is under 10. This is derived here, the same way the other clients do it. |
| `asOf` | When the index was computed. |
| `attribution`, `license` | The credit and the licence URL from the response. |

`day_pass` and `meeting_room` come from the `dayPass` and `meetingRoom` objects. A percentile the API did not send is absent, not zero. An unknown city, a city with no published index, or a product the city does not list is a GREL error.

A column of the same city is one HTTP request. The client keeps a successful response for the `Cache-Control` max-age (10 minutes when the header is missing). On HTTP 429 or a 5xx response it waits and retries once.

Set `COWORKINGVIEW_API_URL` only to point the extension at a private mirror of the same API. The default host is `https://api.coworkingview.com`.

## Data licence

The extension code is MIT. The Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Keep the `attribution` string with any figure you publish. The API description is [coworkingview.com/en/api](https://coworkingview.com/en/api).

## Build

Java 11 or newer and Maven:

```sh
cd openrefine-extension
mvn -B package
```

The zip is `target/coworkingview-openrefine-0.1.0.zip`. Tests use a saved rates response and a local HTTP server. They do not call the live API. The same tests are run against the OpenRefine 3.8.7, 3.9.5 and 3.10.1 jars.
