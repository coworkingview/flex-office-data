# coworkingview

[![Maven Central](https://img.shields.io/maven-central/v/io.github.coworkingview/coworkingview.svg)](https://central.sonatype.com/artifact/io.github.coworkingview/coworkingview)
[![Java](https://img.shields.io/badge/java-11%2B-blue.svg)](https://github.com/coworkingview/flex-office-data/tree/main/integrations/java)
[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](https://github.com/coworkingview/flex-office-data/blob/main/integrations/java/LICENSE)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

Java client for the public API of [CoworkingView](https://coworkingview.com).

It gives you:

- **The CoworkingView Price Index**: median, 25th and 75th percentile by city for flex desks, fixed desks and private offices (per month), day passes (per day) and meeting rooms (per hour), with the sample size next to every figure. Open data under **CC BY 4.0**.
- **Catalogue search**: coworking spaces, business centres, meeting rooms, event spaces and virtual offices, filtered by city, neighbourhood, operator, product, capacity and price, each with a link to its listing on [coworkingview.com](https://coworkingview.com).

No API key. The only runtime dependency is the JDK (Java 11 or newer): HTTP is `java.net.http.HttpClient`, and JSON is parsed in the library. Nothing is downloaded at class-load time.

The same endpoints, columns and ordering are implemented by the [Python](../../python/), [R](../../r/) and [Rust](../../rust/) packages in this repository. They are checked against the same fixtures.

Maintained by [CoworkingView](https://coworkingview.com). This library was built with AI assistance.

## Install

Maven:

```xml
<dependency>
  <groupId>io.github.coworkingview</groupId>
  <artifactId>coworkingview</artifactId>
  <version>0.1.0</version>
</dependency>
```

Gradle (Groovy):

```groovy
implementation "io.github.coworkingview:coworkingview:0.1.0"
```

Gradle (Kotlin):

```kotlin
implementation("io.github.coworkingview:coworkingview:0.1.0")
```

Those coordinates are the Maven Central coordinates (`io.github.coworkingview:coworkingview:0.1.0`). Until the first publish, build it from this directory:

```bash
mvn -B install
```

Publishing steps are in [PUBLISHING.md](PUBLISHING.md). Requires JDK 11 or newer.

## Usage

```java
import io.github.coworkingview.Client;
import io.github.coworkingview.Dataset;
import io.github.coworkingview.Listing;
import io.github.coworkingview.Locale;
import io.github.coworkingview.PricingOption;
import io.github.coworkingview.Product;
import io.github.coworkingview.Rate;
import io.github.coworkingview.RatesQuery;
import io.github.coworkingview.Space;
import io.github.coworkingview.SpacesQuery;

import java.util.List;

Client client = Client.create();

Dataset<List<Rate>> berlin = client.rates(new RatesQuery().city("berlin"));
for (Rate rate : berlin.getData()) {
    System.out.printf(
            "%s %s %s %s (n=%d)%n",
            rate.getProduct().getApiName(),
            rate.getUnit() == null ? "" : rate.getUnit().getApiName(),
            rate.getMedianText(),
            rate.getCurrency(),
            rate.getSampleSize());
}
// Print this next to any figure you republish. The index is CC BY 4.0.
System.out.println(berlin.getAttribution());

// City names in German. "en", "es" and "de" are the locales the API accepts.
client.cities(new RatesQuery().country("DE").locale(Locale.DE));

Dataset<List<Listing>> rooms = client.spaces(
        new SpacesQuery().city("berlin").product(Product.MEETING_ROOM).limit(20));
for (Listing room : rooms.getData()) {
    System.out.println(room.getTitle() + " " + room.getUrl());
}

Dataset<Space> space = client.space("sankt-oberholz-rosenthaler-berlin");
for (PricingOption offer : space.getData().getPricing()) {
    // getPrice() is null when the operator quotes on request. It is not zero.
    System.out.println(offer.getProduct() + " " + offer.getPriceText() + " " + offer.getCurrency());
}
```

`Client.create()` talks to `https://api.coworkingview.com`, or to whatever `COWORKINGVIEW_API_URL` is set to. `Client.builder()` changes the base URL, the timeout (default 20 seconds), the `User-Agent` and the default locale.

```java
Client client = Client.builder()
        .timeout(java.time.Duration.ofSeconds(5))
        .userAgent("my-research-project/1.0 (me@example.org)")
        .locale(Locale.DE)
        .build();
```

A client is safe to share between threads. Do not change a query object while a call is using it.

Figures move as the index is recomputed. `getAsOf()` on the dataset, and on each Price Index row, says when.

### What you can ask for

| parameter | values |
|---|---|
| locale | `en` (default), `es`, `de` |
| currency | `EUR`, `GBP`, `USD`, `CHF`, `AED`, `VES` (any case; the API converts at an approximate rate and answers 400 where it has none) |
| product | `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership` |
| sort | `random` (default), `price-asc`, `date-desc`, `date-asc` |

A typo throws `IllegalArgumentException` before a request is sent. The message lists the accepted spellings.

### `rates`

`GET /v1/market/rates`. One row per published city and product.

| field | meaning |
|---|---|
| `citySlug`, `cityName` | city identifier and the name in the requested locale |
| `countryCode` | ISO 3166-1 alpha-2, or `null` when omitted |
| `currency` | currency of the amounts, as the API wrote it |
| `product` | `flex_desk`, `fix_desk`, `private_office`, `day_pass`, `meeting_room`, … |
| `unit` | `month`, `day` (day pass) or `hour` (meeting and event rooms); `null` for an aggregate this version has no unit for |
| `median`, `p25`, `p75` | price statistics. `p25` and `p75` are `null` when the API did not publish them |
| `sampleSize` | number of prices behind the figure |
| `propertyCount`, `operatorCount` | spaces and operators behind the figure, or `null` when omitted |
| `lowConfidence` | `true` when `sampleSize` is below 10 |
| `asOf` | when the index was computed, ISO 8601 |

`getMedianText()` (and the same for the percentiles) is the exact token from the JSON, so `214` stays `214`. `getMedian()` is that number as a `double`.

Rows are ordered by city slug, then by product. An aggregate the API adds later (the way `dayPass` became `day_pass`) appears as a new row without a library release. Cities in `unpublished` produce no rate rows.

`RatesQuery.product(...)` filters the rows locally. It is not sent to the API. `cities` ignores it.

### `cities`

The same request. One row per city. Published cities come first, then by slug.

| field | meaning |
|---|---|
| `published` | `false` when the city does not have enough prices for an index yet |
| `propertyCount`, `operatorCount` | spaces and operators with prices; `null` for an unpublished city |
| `entryMedian`, `entryMin`, `entryMax` | cheapest monthly option per space: median, minimum, maximum |
| `p25`, `p75` | quartiles of those entry prices |
| `sampleSize` | number of spaces with a monthly price; `null` when unpublished |

An unpublished city has no price figures. The counts and entry prices are `null`.

### `spaces`

`GET /v1/properties`. One row per space. `limit` defaults to 50 and must be from 1 to 200. The page size is `min(50, limit)`. Further pages are followed until `limit` rows or `pagination.pageCount`. With `sort = random` (the default), the seed of the first page is reused so the pages of one call do not overlap. Pass `seed(long)` to ask for an order again.

| field | meaning |
|---|---|
| `slug`, `title` | identifier and name. Pass the slug to `space` |
| `citySlug`, `zoneSlug` | city and neighbourhood |
| `operatorSlug`, `operatorName` | operator |
| `countryCode` | ISO 3166-1 alpha-2 |
| `lat`, `lng` | WGS 84. `null` when the card has no coordinates |
| `featured` | `Boolean`. `null` means the API omitted the flag, which is not the same as `false` |
| `marketVerdict` | `below`, `around` or `above` the city median, or `null` |
| `marketMedian`, `marketSampleSize` | the median that verdict compares against |
| `url` | listing page, `https://coworkingview.com/{locale}/{workspace\|oficina\|buero}/{slug}` |
| `updatedAt` | last update, ISO 8601 |

`getTotal()` on the dataset is `pagination.total` from the first page (how many spaces matched, which can be more than `limit`), or `null` when the API omitted it. `getAttribution()` is the citation. `getNotice()` is the catalogue notice.

### `space`

`GET /v1/properties/{slug}`. The search fields, plus:

| field | meaning |
|---|---|
| `address` | street address, or `null` |
| `capacity` | integer capacity in people, or `null` when it is absent or not an integer |
| `amenities` | codes such as `wifi` and `meeting_rooms`. Empty when omitted |
| `pricing` | one `PricingOption` per `pricingOptions` item, in the API's order |
| `url` | the response's `webUrl` when that is a non-empty string, otherwise the locale link |

| pricing field | meaning |
|---|---|
| `product`, `title` | product and the operator's name for the offer |
| `price`, `currency` | `null` when the price is on request or the API omitted `price` |
| `billingPeriod` | as the API states it: `month`, `day`, `hour`, `once`, … |
| `priceOnRequest` | no public price |
| `minCapacity`, `maxCapacity` | people, or `null` when omitted |

A slug that is not letters, digits, `.`, `_` and `-`, starting with a letter or digit, throws `IllegalArgumentException` and no request is made.

## Errors

| exception | when |
|---|---|
| `IllegalArgumentException` | an argument is invalid, before any request |
| `ApiException` | the API answered with an error, or a success body was not the expected JSON (`code` is `BAD_RESPONSE`) |
| `CoworkingViewException` | the base class, thrown directly when the host cannot be reached |

`ApiException` carries `status`, `code`, `title`, `detail`, `type` and `errors`. `status` is the HTTP status.

```java
import io.github.coworkingview.ApiException;

try {
    client.rates(new RatesQuery().city("berlin").currency("VES"));
} catch (ApiException err) {
    System.out.println(err.getStatus() + " " + err.getCode() + " " + err.getDetail());
}
```

On `429` or a `5xx`, the client waits for `Retry-After` seconds, else `RateLimit-Reset`, else 2 seconds, and never more than 10 seconds, then retries **once**.

## Limits

The catalogue may be searched and linked to, not bulk-copied. Descriptions, photos and logos belong to the operators and are not returned. A search stops at 200 rows. Please don't loop over cities to reconstruct the catalogue. The API allows 120 requests per minute per IP; responses are cacheable for 10 minutes.

## Build

```bash
cd integrations/java
mvn -B verify
```

`mvn verify` runs the unit tests against the shared fixtures in `spec/fixtures/` and a local HTTP server. It does not call the live API, and it does not need a GPG key. The `release` profile signs artifacts; see [PUBLISHING.md](PUBLISHING.md).

## Licence and attribution

- **Code:** MIT. See [LICENSE](LICENSE).
- **Price Index** (`rates`, `cities`): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit the CoworkingView Price Index and keep `dataset.getAttribution()` with anything you publish. The licence URL is `dataset.getLicense()`.
- **Catalogue** (`spaces`, `space`): names, prices and links are for search and reference. Keep `dataset.getNotice()` in mind: systematic extraction is not permitted.

The data returned by the API is not covered by the MIT licence on this code.

- [CoworkingView](https://coworkingview.com)
- [Price Index](https://coworkingview.com/en/tools/price-index)
- [Offices in Berlin](https://coworkingview.com/en/office-space/berlin)
- [Source](https://github.com/coworkingview/flex-office-data)
