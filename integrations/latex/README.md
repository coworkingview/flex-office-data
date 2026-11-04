# coworkingview

Median flexible-office prices by city, from a bundled snapshot of the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index).

The package does not access the network. `coworkingview-rates.csv` is that snapshot, captured `2026-10-27T21:06:48.313Z`. The rows are copied from the open rates table: Abu Dhabi, Berlin and Madrid. The unpublished fixture city `example-town` has no prices and is not included. Every amount is copied from that table.

This material is subject to the LaTeX Project Public License 1.3c. The code and the documentation may be distributed and modified under LPPL 1.3c or any later version. See [LICENSE](LICENSE).

`coworkingview-rates.csv` is not covered by the LPPL. It is CoworkingView Price Index data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). `\cwvattribution` prints the credit line. Keep it with any figure you republish.

Version 0.1.0. Requires LaTeX2e 2022-06-01 or newer.

- Homepage: https://coworkingview.com/en/tools/price-index
- Repository: https://github.com/coworkingview/flex-office-data
- Bug tracker: https://github.com/coworkingview/flex-office-data/issues
- Maintainer: CoworkingView <info@coworkingview.com>

## Installation

Put `coworkingview.sty` and `coworkingview-rates.csv` in the same directory as the document, or install both on the TeX input path. The `.sty` file reads the `.csv` file by name. Neither file is fetched at run time.

## Commands

```latex
\usepackage{coworkingview}
% \usepackage{hyperref} % optional

Flex desk in Berlin: \cwvrate{berlin}.
\cwvrate[product=day_pass]{Berlin}
\cwvratestable{madrid}
\cwvcities
\cwvsnapshotdate
\cwvattribution
```

`\cwvrate{<city>}` prints the median and the currency code, then the unit recorded for that row, for example `214 EUR/month`. The default product is `flex_desk`. `\cwvrate[product=<product>]{<city>}` selects another product: `flex_desk`, `fix_desk`, `private_office`, `day_pass` or `meeting_room`. `flex desk` and `private-office` match the same rows. The median is printed as recorded. It is not rounded.

`<city>` is a slug (`berlin`, `abu-dhabi`) or a display name (`Berlin`, `Abu Dhabi`). Comparison ignores case and treats spaces, hyphens and underscores as the same separator.

`\cwvratestable{<city>}` prints a `tabular` with one row per product in that city: product, median, the 25th and 75th percentiles, and the sample size `n`. An em dash means that percentile was not in the snapshot. The currency of the percentiles is the currency in the median column.

`\cwvcities` prints the display names of the cities in the snapshot, in the recorded order. `\cwvsnapshotdate` prints the snapshot timestamp from the `as_of` column.

`\cwvattribution` prints `Data: CoworkingView Price Index, CC BY 4.0`. If `hyperref` is loaded, the name is an `\href` to `https://coworkingview.com/en/tools/price-index`. The package does not load `hyperref`. If `\href` is not defined, the same words are printed and the URL is added with `\url`.

An unknown city or product is a package error. The message names the cities or products in the snapshot.

## Snapshot

The generator is `tools/build_snapshot.py` in the repository. It copies `spec/golden/rates.csv` and checks the date and licence against `spec/fixtures/market_rates.json`. It does not recompute a price.

```sh
python3 integrations/latex/tools/build_snapshot.py
python3 integrations/latex/tools/build_snapshot.py --check
```

## Building

From this directory, with TeX Live:

```sh
l3build check
l3build ctan
```

`l3build ctan` writes `coworkingview.zip`. The archive contains one top-level directory, `coworkingview/`.
