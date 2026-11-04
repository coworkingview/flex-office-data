# coworkingview

Look up median flexible-office prices from a bundled snapshot of the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index).

`resources/coworkingview/price-index.edn` is that snapshot, captured `2026-10-27T21:06:48.313Z`. The rows are the open tables behind the index: three published cities (Abu Dhabi, Berlin, Madrid) and the unpublished fixture city `example-town`, which has no prices. Every amount is copied from `spec/golden/rates.csv` and `spec/golden/cities.csv`. Nothing in this library computes a price.

The code in this directory is MIT. The Price Index figures are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `attribution` returns the credit string from the capture. Keep it with any figure you republish. The snapshot has no photos, logos, or workspace descriptions.

Requires Clojure 1.12.

## Coordinates

Clojars group `net.clojars.coworkingview` (the auto-verified group for the `coworkingview` account), artifact `coworkingview`, version `0.1.0`. Pushing a tag `clojure-v*` publishes this version. The coordinates below are that release.

```clojure
net.clojars.coworkingview/coworkingview {:mvn/version "0.1.0"}
```

```clojure
[net.clojars.coworkingview/coworkingview "0.1.0"]
```

```xml
<dependency>
  <groupId>net.clojars.coworkingview</groupId>
  <artifactId>coworkingview</artifactId>
  <version>0.1.0</version>
</dependency>
```

The jar's homepage, the URL Clojars shows, is <https://coworkingview.com/en/tools/price-index>.

## Usage

```clojure
(require '[coworkingview.core :as cwv])

(def berlin (cwv/rate "berlin" "flex_desk"))
;; Berlin flex desk in this snapshot: median 214 EUR/month, sample 72.

(str (:median berlin) " " (:currency berlin) "/" (:unit berlin))
(cwv/attribution)
```

`rate` returns `nil` when the snapshot has no such row. `cities` includes `example-town` with `nil` prices. `attribution` returns the credit string unchanged:

> Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.

## Functions

`rate` takes a city and a product and returns one rates row, or `nil`. The city is a slug (`berlin`) or a display name (`Abu Dhabi`). Comparison ignores case and treats spaces, hyphens and underscores as the same separator. The product is `flex_desk`, `fix_desk`, `private_office`, `day_pass` or `meeting_room`. `flex desk` matches `flex_desk`.

The row fields are `:city_slug`, `:city_name`, `:country_code`, `:currency`, `:product`, `:unit`, `:median`, `:p25`, `:p75`, `:sample_size`, `:property_count`, `:operator_count`, `:low_confidence` and `:as_of`. `:median` is the published median. `:p25` and `:p75` are `nil` when the index did not publish them. `:low_confidence` is the flag from the capture (`sample_size` below 10).

`cities` returns the city rows in recorded order. Fields are `:city_slug`, `:city_name`, `:country_code`, `:currency`, `:published`, `:property_count`, `:operator_count`, `:entry_median`, `:entry_min`, `:entry_max`, `:p25`, `:p75`, `:sample_size` and `:as_of`. Empty fields are `nil`.

`attribution` returns the credit string above.

`snapshot` returns the whole capture, including `:license` (`CC-BY-4.0`), `:license_url` and `:scope`. The scope text from the capture is:

> This licence covers the CoworkingView Price Index and catalogue data in this dataset: prices and price statistics, space and operator names, and descriptions written by CoworkingView. It does not cover, and this dataset does not contain: photos, logos, reviews or ratings, data obtained from Google, or any other content of coworkingview.com, its API or MCP server, which remain subject to their own terms. Names are included for identification only; no trademark rights in CoworkingView or operator names and marks are licensed.

Loading `coworkingview.core` does not call the network.

## Optional API client

`coworkingview.client` calls the public read-only endpoint documented in `spec/SPEC.md`:

`GET https://api.coworkingview.com/v1/market/rates`

No API key. Set `COWORKINGVIEW_API_URL` to point at another origin. The user agent is `coworkingview-clojure/0.1.0 (+https://github.com/coworkingview/flex-office-data)`. A 429 or 5xx is retried once. The wait is `Retry-After`, otherwise `RateLimit-Reset`, otherwise 2 seconds, and never more than 10.

```clojure
(require '[coworkingview.client :as client])

(client/rate "berlin" "flex_desk")
(client/cities)
(client/attribution)
```

If the request fails, these return the bundled snapshot (`:origin :snapshot`) and `:error` says why. `:attribution` is still the CC BY 4.0 credit. Pass `:offline true` to skip the request. `:currency` is `EUR`, `GBP`, `USD`, `CHF`, `AED` or `VES` and is sent to the API, which does the conversion. The snapshot fallback does not convert: a request for USD does not turn a EUR median into a USD figure, and `rate` returns `nil` for that row.

## Build

From this directory:

```bash
clojure -M:test
clojure -T:build jar
```

`clojure -T:build deploy` publishes the jar. It reads `CLOJARS_USERNAME` and `CLOJARS_PASSWORD` (a Clojars deploy token). Pushing a tag `clojure-v*` runs `.github/workflows/clojars-release.yml`, which is the deploy. This repository does not create that tag.

## Licence

Code: MIT, see [LICENSE](LICENSE).

`resources/coworkingview/price-index.edn`: CC BY 4.0, credited by `attribution`.
