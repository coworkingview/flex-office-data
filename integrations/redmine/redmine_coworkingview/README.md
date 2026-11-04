# CoworkingView Prices

Redmine plugin `redmine_coworkingview` for the public [CoworkingView](https://coworkingview.com) Price Index. Two wiki macros print the median, the p25–p75 spread, the currency, the unit and the sample size for a city.

No account and no API key. The plugin code is MIT. The Price Index figures are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Compatible with Redmine 5.0 through 7.x, on Ruby 3.0 or newer. No database migration and no core patches.

## Install

Copy this directory to the Redmine `plugins/` directory. The folder name must stay `redmine_coworkingview`.

```console
cp -a redmine_coworkingview /path/to/redmine/plugins/redmine_coworkingview
```

Restart Redmine. In Administration → Plugins the entry is **CoworkingView Prices**. Configure it from that page.

## Usage

On a wiki page, one product (the default product is `flex_desk`):

```
{{coworking_rate(berlin)}}
```

A named product:

```
{{coworking_rate(berlin, private_office)}}
```

Every product published for the city, as a table:

```
{{coworking_rates(berlin)}}
```

The city argument is the Price Index slug (`berlin`, `madrid`, `abu-dhabi`). Matching ignores case and surrounding space. The optional product argument is a product slug such as `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office` or `membership`.

Each figure shows the median, the p25–p75 spread, the currency, the unit and the sample size. A percentile the index does not publish for that product is left blank (shown as —). Under the figure the macro links the text `Data: CoworkingView Price Index (CC BY 4.0)` to [https://coworkingview.com/en/tools/price-index](https://coworkingview.com/en/tools/price-index).

An unknown city or product is a short message. The macro does not invent a price.

## Settings

Administration → Plugins → CoworkingView Prices → Configure.

| Setting | Default | Meaning |
|---|---|---|
| Network | On | Off reads `data/rates_snapshot.csv` and does not call the API. |
| Cache TTL (hours) | 24 | How long a successful response stays in `Rails.cache`. A failed request is not cached, so the next view tries again. |
| Locale | `en` | Sent as the `locale` query parameter. Allowed values are `en`, `es` and `de`. |

The request is one HTTPS GET, with open, read and write timeouts of 20 seconds:

`https://api.coworkingview.com/v1/market/rates?locale=en`

`locale` is required. Without it the API returns HTTP 400. On HTTP 429 or 5xx the plugin waits and tries once more, then uses the bundled snapshot. The snapshot is the file `spec/golden/rates.csv` from this repository, copied to `data/rates_snapshot.csv`. City names in that file are the English export.

Set `COWORKINGVIEW_API_URL` only to point the plugin at a different origin. The default is `https://api.coworkingview.com`.

## Data licence

The plugin is [MIT](LICENSE). Price Index figures are not covered by that licence. They are CC BY 4.0. Credit the CoworkingView Price Index and link to [https://coworkingview.com/en/tools/price-index](https://coworkingview.com/en/tools/price-index). The macro prints that attribution with every figure.

Homepage: [https://coworkingview.com](https://coworkingview.com).

## Tests

From this directory, with no Redmine and no network. Each file is a standalone Minitest file (`ruby` runs the first program file only, so pass one file per process):

```console
ruby -Itest test/run.rb
```

`test/run.rb` loads every `*_test.rb` file. To run one file: `ruby -Itest test/dataset_test.rb`.

The tests parse `test/fixtures/market_rates.json` and compare it with `data/rates_snapshot.csv`.
