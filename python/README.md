# coworkingview

[![PyPI](https://img.shields.io/pypi/v/coworkingview.svg)](https://pypi.org/project/coworkingview/)
[![Python](https://img.shields.io/pypi/pyversions/coworkingview.svg)](https://pypi.org/project/coworkingview/)
[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](https://github.com/coworkingview/flex-office-data/blob/main/python/LICENSE)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

Flexible-office prices and coworking-space search as tidy **pandas** DataFrames.

`coworkingview` is the Python client for the public API of
[CoworkingView](https://coworkingview.com). It gives you:

- **The CoworkingView Price Index**: median, p25 and p75 prices by city for flex
  desks, fixed desks and private offices (per month), day passes (per day) and
  meeting rooms (per hour), with sample sizes. Open data under **CC BY 4.0**.
- **Catalogue search**: coworking spaces, business centres, meeting rooms, event
  spaces and virtual offices, filtered by city, neighbourhood, operator, product,
  capacity and price, each with a link to its listing.

One call, one DataFrame. No API key, no account, one runtime dependency (pandas).

## Install

```bash
pip install coworkingview
```

or with conda (once the conda-forge recipe is merged):

```bash
conda install -c conda-forge coworkingview
```

Requires Python 3.9 or newer.

## 60-second quickstart

```python
>>> import coworkingview as cwv

>>> berlin = cwv.rates(city="berlin")
>>> berlin[["product", "unit", "median", "p25", "p75", "sample_size", "low_confidence"]]
          product   unit  median    p25    p75  sample_size  low_confidence
0       flex_desk  month   214.0  199.0  292.0           72           False
1        fix_desk  month   310.0  290.0  421.0           60           False
2  private_office  month   480.0  399.0  550.0           59           False
3        day_pass    day    35.0   <NA>   <NA>           59           False
4    meeting_room   hour    32.0   <NA>   <NA>           79           False

>>> print(berlin.attrs["attribution"])
Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), as of October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). Aggregated figures only; no endorsement by CoworkingView or any operator is implied.

>>> cwv.cities()[["city_slug", "currency", "published", "property_count", "entry_median"]]
      city_slug currency  published  property_count  entry_median
0     abu-dhabi      AED       True               2        1453.0
1        berlin      EUR       True              85         265.0
2        madrid      EUR       True              10         325.0
...

>>> rooms = cwv.spaces(city="berlin", product="meeting_room", limit=20)
>>> rooms[["title", "zone_slug", "operator_name", "market_verdict"]].head(3)
                                                      title                   zone_slug operator_name market_verdict
0  St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße                       mitte  St. Oberholz         around
1                      smartspaces Coworking Berlin-Spandau                     spandau   smartspaces         around
2                                      Regus Charlottenburg  charlottenburg-wilmersdorf         Regus           <NA>

>>> s = cwv.space("sankt-oberholz-rosenthaler-berlin")
>>> s.pricing[["product", "title", "price", "currency", "billing_period", "price_on_request"]]
          product                             title  price currency billing_period  price_on_request
0       flex_desk  Coworking Membership – Flex Desk  209.0      EUR          month             False
1        fix_desk                        Fixed Desk   <NA>     <NA>          month              True
2  private_office                 Private Team Room   <NA>     <NA>          month              True
3    meeting_room           Meeting & Workshop Room   <NA>     <NA>           once              True
4  virtual_office   Virtual Office with St.Dropscan   69.0      EUR          month             False
```

(Figures are illustrative and change as the index is recomputed; `as_of` tells you when.)

Every column has a nullable pandas dtype (`string`, `Float64`, `Int64`, `boolean`) and
timestamps are timezone-aware UTC, so missing values are `<NA>`, never a silent `NaN`
in an integer column.

## Reference

Accepted values, validated before any request is sent (a typo raises `ValueError`
listing the valid values):

| parameter | values |
|---|---|
| `locale` | `"en"` (default), `"es"`, `"de"` |
| `currency` | `"EUR"`, `"GBP"`, `"USD"`, `"CHF"`, `"AED"`, `"VES"` (case-insensitive; the API converts at an approximate rate and answers 400 where it has none) |
| `product` | `"flex_desk"`, `"fix_desk"`, `"private_office"`, `"exclusive_bereich"`, `"day_pass"`, `"meeting_room"`, `"event_space"`, `"virtual_office"`, `"membership"` |
| `sort` | `"random"` (default), `"price-asc"`, `"date-desc"`, `"date-asc"` |

### `rates(city=None, country=None, currency=None, locale="en")`

The Price Index: one row per published city and product.

| parameter | type | description |
|---|---|---|
| `city` | `str` | City slug, e.g. `"berlin"`, `"madrid"`, `"abu-dhabi"` |
| `country` | `str` | ISO 3166-1 alpha-2 code, e.g. `"DE"` |
| `currency` | `str` | Present prices in this currency (default: each city's own) |
| `locale` | `str` | Language of city names |

| column | dtype | description |
|---|---|---|
| `city_slug`, `city_name` | string | City identifier and display name |
| `country_code` | string | ISO 3166-1 alpha-2 |
| `currency` | string | Currency of the figures |
| `product` | string | `flex_desk`, `fix_desk`, `private_office`, `day_pass`, `meeting_room`, ... |
| `unit` | string | `month`, `day` (day pass) or `hour` (meeting and event rooms) |
| `median`, `p25`, `p75` | Float64 | Price statistics (`p25`/`p75` are `<NA>` when not published) |
| `sample_size` | Int64 | Number of prices behind the figure |
| `property_count`, `operator_count` | Int64 | Spaces and operators behind the figure |
| `low_confidence` | boolean | `True` when `sample_size < 10`; treat as indicative |
| `as_of` | datetime64[ns, UTC] | When the index was computed |

Rows are sorted by city, then product (flex desk, fixed desk, private office, ...).
Aggregates the API adds later (say, event spaces) appear as new rows without a
package release. `df.attrs` holds `attribution`, `license` (licence URL) and `as_of`.

### `cities(city=None, country=None, currency=None, locale="en")`

One row per city, same parameters as `rates()`.

| column | dtype | description |
|---|---|---|
| `city_slug`, `city_name`, `country_code`, `currency` | string | As in `rates()` |
| `published` | boolean | `False` for cities with too few prices for an index yet |
| `property_count`, `operator_count` | Int64 | Spaces and operators in the city |
| `entry_median`, `entry_min`, `entry_max` | Float64 | Cheapest monthly option per space: median, min, max |
| `p25`, `p75` | Float64 | Quartiles of those entry prices |
| `sample_size` | Int64 | Number of spaces with a monthly price (`<NA>` if unpublished) |
| `as_of` | datetime64[ns, UTC] | When the index was computed |

Published cities come first, then by slug. Same `df.attrs` as `rates()`.

### `spaces(city=None, country=None, zone=None, operator=None, product=None, min_capacity=None, min_price=None, max_price=None, currency=None, sort="random", limit=50, locale="en")`

Search the catalogue, one row per space.

| parameter | type | description |
|---|---|---|
| `city`, `country` | `str` | City slug, ISO country code |
| `zone` | `str` | Neighbourhood slug, e.g. `"mitte"` |
| `operator` | `str` | Operator slug, e.g. `"regus"` |
| `product` | `str` | Only spaces offering this product (see accepted values) |
| `min_capacity` | `int` | Options for at least this many people |
| `min_price`, `max_price` | `float` | Price bounds (in `currency` when given) |
| `currency` | `str` | Currency of the price bounds |
| `sort` | `str` | `"random"` is stable across the pages of one call |
| `limit` | `int` | 1 to 200 (default 50); see [limits](#limits-and-good-citizenship) |
| `locale` | `str` | Language of titles and of `url` |

| column | dtype | description |
|---|---|---|
| `slug`, `title` | string | Identifier and name of the space |
| `city_slug`, `zone_slug` | string | City and neighbourhood |
| `operator_slug`, `operator_name` | string | Operator |
| `country_code` | string | ISO 3166-1 alpha-2 |
| `lat`, `lng` | Float64 | WGS 84 coordinates |
| `featured` | boolean | Featured listing |
| `market_verdict` | string | `below`, `around` or `above` the city median |
| `market_median`, `market_sample_size` | Float64, Int64 | The city median it compares against |
| `url` | string | Listing page on coworkingview.com |
| `updated_at` | datetime64[ns, UTC] | Last update of the listing |

`df.attrs` holds `attribution` (the citation), `notice` (the catalogue notice) and
`total` (how many spaces matched, which can be more than `limit`).

### `space(slug, locale="en")`

One space, by its `slug` (letters, digits, `.`, `_`, `-`; anything else raises
`ValueError` before a request is made), returned as a frozen dataclass `Space` with the `spaces()` fields plus
`address`, `capacity` and `amenities` (a tuple of codes such as `"wifi"`), and:

| attribute | type | description |
|---|---|---|
| `pricing` | DataFrame | One row per pricing option (below) |
| `attribution` | str | Citation to show next to the data |
| `notice` | str | The catalogue notice |

| `pricing` column | dtype | description |
|---|---|---|
| `product` | string | Product type |
| `title` | string | The operator's name for the option |
| `price`, `currency` | Float64, string | `<NA>` when the price is on request |
| `billing_period` | string | `month`, `day`, `hour`, `once`, ... |
| `price_on_request` | boolean | No public price |
| `min_capacity`, `max_capacity` | Int64 | People, when published |

### `Client(base_url=None, timeout=20, user_agent=None)`

The functions above use a shared default client. Create your own to change the
configuration; it has the same four methods.

```python
from coworkingview import Client

client = Client(timeout=5, user_agent="my-research-project/1.0 (me@example.org)")
client.rates(country="ES", currency="EUR")
```

`base_url` defaults to the `COWORKINGVIEW_API_URL` environment variable, else
`https://api.coworkingview.com`. Nothing touches the network at import time.

### Errors

| exception | raised when |
|---|---|
| `ValueError` | An argument is invalid (before any request) |
| `coworkingview.APIError` | The API answered with an error, or with a body that is not JSON (`code == "BAD_RESPONSE"`) |
| `coworkingview.CoworkingViewError` | Base class; raised directly when the API cannot be reached |

`APIError` carries the API's problem document: `status`, `code`, `title`, `detail`
and `errors` (per-field messages).

```python
try:
    cwv.rates(city="berlin", currency="VES")
except cwv.APIError as err:
    print(err.status, err.code, err.detail)
# 400 VALIDATION_FAILED currency "VES" has no approximate rate from "EUR" ...
```

On `429 Too Many Requests` or a `5xx`, the client waits (`Retry-After`, else
`RateLimit-Reset`, else 2 s; never more than 10 s) and retries **once**.

## Limits and good citizenship

- The API allows 120 requests per minute per IP and answers are cacheable for
  10 minutes. Cache what you reuse.
- `spaces()` returns at most **200** spaces per call, and asking for more raises a
  `ValueError`. That is deliberate: the catalogue may be searched and linked to,
  but not bulk-copied. Please do not loop over cities or operators to rebuild it.
- No descriptions, photos or logos are returned. They belong to the operators.

## Attribution and licence

- **Code**: MIT, see [LICENSE](https://github.com/coworkingview/flex-office-data/blob/main/python/LICENSE).
- **Price Index data** (`rates()`, `cities()`): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  You may share and adapt it, including commercially, if you credit the source. Every
  result carries the credit line in `df.attrs["attribution"]`; publish it next to
  any chart, table or article that uses the figures. Methodology and the interactive
  index: [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index).
- **Catalogue content** (`spaces()`, `space()`): names, descriptions, images, logos
  and prices of individual spaces belong to their operators and are **not licensed**
  for reuse. You may search it and link to the listing `url`; `df.attrs["notice"]`
  carries the exact terms.

## Development

```bash
uv sync                                   # create .venv with dev tools
uv run ruff format --check . && uv run ruff check .
uv run mypy                               # --strict
uv run pytest --cov                       # offline; fails under 90 % coverage
COWORKINGVIEW_LIVE_TESTS=1 uv run pytest -m live   # 3 real requests, opt-in
```

The parsing is tested row for row against the shared contract in
[`spec/`](https://github.com/coworkingview/flex-office-data/tree/main/spec),
which the R and Rust packages implement too.
