# flex-office-data — shared specification

This file is the contract the Python, R, Rust and Java packages implement. When it
changes, all four change in the same pull request, and the golden files in
`spec/golden/` are regenerated with `python3 spec/tools/make_golden.py`.

## 1. Source

| | |
|---|---|
| Base URL | `https://api.coworkingview.com` (override: env `COWORKINGVIEW_API_URL`) |
| Auth | None. Public, read-only. |
| Rate limit | 120 requests / 60 s per IP (`RateLimit-*` headers). |
| Caching | Responses carry `Cache-Control: max-age=600` and an `ETag`. |
| Envelope | `{ "data": …, "meta": { "contractVersion", "citation"?, "pagination"?, "seed"? } }` |
| Errors | RFC 9457 problem JSON: `{ type, title, status, code, detail, errors? }` |

Endpoints used:

| Endpoint | Used by |
|---|---|
| `GET /v1/market/rates?locale=&city=&country=&currency=` | `rates()`, `cities()` |
| `GET /v1/properties?locale=&city=&country=&zone=&operator=&pricingOptionType=&minCapacity=&minPrice=&maxPrice=&currency=&sortBy=&page=&pageSize=&seed=` | `spaces()` |
| `GET /v1/properties/{slug}?locale=` | `space()` |

Accepted values:

- `locale`: `en` (default), `es`, `de`
- `currency`: `EUR`, `GBP`, `USD`, `CHF`, `AED` (`VES` exists in the API but has
  no conversion rate for most cities; pass it through and let the API answer 400)
- `product` (the API's `pricingOptionType`): `flex_desk`, `fix_desk`,
  `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`,
  `event_space`, `virtual_office`, `membership`
- `sort`: `random` (default), `price-asc`, `date-desc`, `date-asc`

## 2. HTTP behaviour (every package)

- `User-Agent: <package>/<version> (+https://github.com/coworkingview/flex-office-data)`
  e.g. `coworkingview-python/0.1.0 (+https://github.com/coworkingview/flex-office-data)`,
  `coworkingview-java/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.
- `Accept: application/json`. Timeout 20 s.
- On `429` or `5xx`: wait `Retry-After` seconds, else `RateLimit-Reset`, else
  2 s — capped at 10 s — then retry **once**. Never more.
- Any other non-2xx: raise the package's error type carrying `status`, `code`,
  `title`, `detail` from the problem body (fall back to the HTTP reason, and
  to `code = "HTTP_<status>"` when the body has no `code`). `status` always
  comes from the HTTP response.
- A non-JSON body is an error too (`code = "BAD_RESPONSE"`).
- Connection failures (DNS, refused, timeout) raise the package's error type.
  Exception: in R the exported functions print an informative message and
  return `invisible(NULL)`, as CRAN's policy on internet resources requires.
- Slugs are validated against `^[A-Za-z0-9][A-Za-z0-9._-]*$` before being put
  in a path.
- No network call at import/load time.

## 3. `rates()` — the Price Index, one row per city × product

`GET /v1/market/rates`. Columns, in this order:

| column | type | from |
|---|---|---|
| `city_slug` | str | `city.slug` |
| `city_name` | str | `city.name` |
| `country_code` | str / null | `countryCode` |
| `currency` | str | `currency` |
| `product` | str | see below |
| `unit` | str | `month` / `day` / `hour` (see below) |
| `median` | float | `.median.amount` |
| `p25` | float / null | `.p25.amount` |
| `p75` | float / null | `.p75.amount` |
| `sample_size` | int | `.sampleSize` |
| `property_count` | int / null | `.propertyCount` |
| `operator_count` | int / null | `.operatorCount` |
| `low_confidence` | bool | `sample_size < 10` |
| `as_of` | str (ISO 8601) | top-level `asOf` |

Rows per city:

1. For each item of `figures` (if `figures` is present and non-empty):
   `product = optionType`, `unit = "month"`.
2. Otherwise, for each item of `byType`: same, with `p25`/`p75`/`property_count`/
   `operator_count` null.
3. For each **top-level key of the city object whose value is an object with
   `median` and `sampleSize`** (today `dayPass`, `meetingRoom`): `product` is
   the key in snake_case (`dayPass` → `day_pass`, `meetingRoom` →
   `meeting_room`, a future `eventSpace` → `event_space`). `unit`: `day_pass` →
   `day`, `meeting_room` → `hour`, `event_space` → `hour`, `virtual_office` →
   `month`, anything else → null. `p25`/`p75` from the stat when present, else
   null. This makes new aggregates appear without a release.

Order: `city_slug` ascending, then product in this order — `flex_desk`,
`fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`,
`event_space`, `virtual_office`, `membership` — then any unknown product
alphabetically.

Cities in `unpublished` produce no rows.

## 4. `cities()` — one row per city

Same request. Columns:

| column | from |
|---|---|
| `city_slug`, `city_name`, `country_code`, `currency` | as above |
| `published` | `true` for `cities[]`, `false` for `unpublished[]` |
| `property_count`, `operator_count` | city-level, null when absent |
| `entry_median`, `entry_min`, `entry_max` | `.entryMedian/.entryMin/.entryMax.amount` (cheapest monthly option per space) |
| `p25`, `p75` | city-level `.p25/.p75.amount` |
| `sample_size` | city-level `sampleSize` (null for unpublished) |
| `as_of` | top-level `asOf` |

Order: `published` first (true before false), then `city_slug`.

## 5. `spaces()` — catalogue search, one row per space

`GET /v1/properties`, `pageSize = min(50, limit)`, following pages until `limit` rows or
`pagination.pageCount`. **`limit` defaults to 50 and is capped at 200** — the
catalogue may be searched and linked, not bulk-copied (see §8). With
`sort = "random"`, reuse `meta.seed` from page 1 on every following page.

Columns:

| column | from |
|---|---|
| `slug`, `title` | |
| `city_slug`, `zone_slug` | `city.slug`, `zone.slug` (null when absent) |
| `operator_slug`, `operator_name` | `operator.slug`, `operator.name` |
| `country_code` | `countryCode` |
| `lat`, `lng` | `coordinates.lat`, `coordinates.lng` |
| `featured` | bool |
| `market_verdict` | `marketPosition.verdict` (`below`/`around`/`above`), null when absent |
| `market_median`, `market_sample_size` | `marketPosition.median.amount`, `marketPosition.sampleSize` |
| `url` | `https://coworkingview.com/{locale}/{workspace\|oficina\|buero}/{slug}` (en/es/de) |
| `updated_at` | `updatedAt` |

No images, descriptions or logos are returned.

## 6. `space(slug)` — one space

`GET /v1/properties/{slug}`. Returns the space's fields (as in §5, plus
`address`, `capacity` (the detail's integer `capacity`, often absent),
`amenities` list and `url` = `webUrl`) and a **pricing
table**, one row per `pricingOptions[]` item:

| column | from |
|---|---|
| `product` | `optionType` |
| `title` | `title` |
| `price` | `price.amount`, null when on request |
| `currency` | `price.currency`, null when on request |
| `billing_period` | `billingPeriod` |
| `price_on_request` | `priceOnRequest` |
| `min_capacity`, `max_capacity` | null when absent |

## 7. Attribution travels with the data

The Price Index is **CC BY 4.0**. Every `rates()` / `cities()` result carries
the response's `attribution` string, its `licenseUrl` (under the name
`license`) and `asOf` (under `as_of`):

- Python: `df.attrs["attribution"]`, `df.attrs["license"]`, `df.attrs["as_of"]`
- R: `attr(x, "attribution")`, `attr(x, "license")`, `attr(x, "as_of")`
- Rust CLI: printed to **stderr** after a table (never into CSV/JSON on stdout);
  the JSON output wraps rows as `{ "attribution", "license", "as_of", "rows" }`.
- Java: `dataset.getAttribution()`, `dataset.getLicense()`, `dataset.getAsOf()`;
  catalogue results also expose `dataset.getNotice()` and, for a search,
  `dataset.getTotal()` (`pagination.total` of the first page).

`spaces()` / `space()` carry `meta.citation.text` the same way, under
`attribution`, plus `meta.catalogueNotice` under `notice`.

## 8. What the packages must not do

- Fetch more than 200 spaces per call, or loop over cities to rebuild the
  catalogue. The API's `catalogueNotice` forbids systematic extraction.
- Strip or hide the attribution.
- Return photos, logos or descriptions (operators' content, not licensed).

## 9. Tests

Each package tests its parsing against the fixtures in `spec/fixtures/` (real
API responses, operator prose and images replaced with placeholders) and
compares to `spec/golden/*.csv`. Network tests are opt-in only
(`COWORKINGVIEW_LIVE_TESTS=1`) and make at most 3 requests.

Golden files: `rates.csv` (from `market_rates.json`), `cities.csv` (same),
`spaces.csv` (from `properties_berlin.json`, locale `en`), `space_pricing.csv`
(from `property_detail.json`). CSV: comma, `\n`, header row, empty field for
null, booleans `true`/`false`, numbers as the API wrote them (no rounding).
