# coworkingview

PostgreSQL extension for the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index): median flexible-office prices by city and product. Pure SQL. No C compiler, and no call to the network when you install or query it.

The rows are a snapshot of the open dataset already in this repository. `spec/fixtures/market_rates.json` is a recorded `GET /v1/market/rates` response. `spec/golden/rates.csv` and `spec/golden/cities.csv` are the tidy tables the other packages test against. The Ruby client and the Airflow provider read that same endpoint and lock their parsers to those files. This extension loads those tables. It does not invent a price.

Snapshot timestamp: `2026-10-27T21:06:48.313Z`.

## Install

PostgreSQL 14 or newer.

```console
make
make install
make installcheck
```

`make installcheck` runs the pg_regress suite.

From PGXN, once the release is published:

```console
pgxn install coworkingview
```

In a database:

```sql
CREATE EXTENSION coworkingview;
```

The extension is relocatable and trusted.

## Query

`coworkingview_rate(city)` is the flex-desk median. Pass a product for the other rows. City and product are matched case-insensitively after trimming. An unknown city or product returns NULL.

```sql
SELECT coworkingview_rate('berlin');
SELECT coworkingview_rate('madrid', 'private_office');

SELECT product, unit, median, p25, p75, sample_size, low_confidence
FROM coworkingview_rates
WHERE city_slug = 'berlin'
ORDER BY product;

SELECT city_name, published, entry_median, currency
FROM coworkingview_cities
ORDER BY published DESC, city_slug;

SELECT coworkingview_attribution();
```

| Object | What it is |
|---|---|
| `coworkingview_price_index` | Snapshot table, one row per city and product (`rates.csv`). |
| `coworkingview_cities` | Snapshot table, one row per city, including unpublished cities (`cities.csv`). |
| `coworkingview_rates` | View of the price index. Every row carries `attribution`, `license` and `license_url`. |
| `coworkingview_rate(city text)` | Flex-desk median for that city slug. |
| `coworkingview_rate(city text, product_code text)` | Median for `flex_desk`, `fix_desk`, `private_office`, `day_pass` or `meeting_room`. |
| `coworkingview_attribution()` | The CC BY 4.0 credit from the snapshot. Keep it with any figure you republish. |
| `coworkingview_about` | One row: `as_of`, attribution, licence and the dataset's scope text. |

`low_confidence` is true when `sample_size` is under 10. Day passes are per day. Meeting rooms are per hour. The monthly products are per month.

## Attribution

The Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit CoworkingView Price Index and keep `coworkingview_attribution()` with anything you publish. The extension code does not replace that credit.

Figures move as the live index is recomputed. This extension does not follow those updates. Shipping a newer snapshot is a new release.

## Build the PGXN zip

From a checkout of this repository:

```console
make -C integrations/postgres bundle
```

`pgxn-bundle` archives whatever git root it finds. Running it directly in `integrations/postgres` would pack the whole monorepo and leave `META.json` off the distribution root, which PGXN rejects. `make bundle` copies this directory outside the work tree and runs `pgxn-bundle` there. The zip is `coworkingview-0.1.0.zip`.

Publishing is the `pgxn-release.yml` workflow, on an annotated tag `pgxn-v*`. It uploads that zip to PGXN with the `PGXN_USERNAME` and `PGXN_PASSWORD` secrets and attaches the same zip to the GitHub release. Do not create those secrets from this tree.

## Licence

Code: MIT. See [LICENSE](LICENSE).

Price Index data: CC BY 4.0. See `coworkingview_about.scope` for what that licence covers.
