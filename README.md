# flex-office-data

**Open data on flexible office prices** — flex desks, fixed desks, private
offices, day passes and meeting rooms — city by city, from the
[CoworkingView Price Index](https://coworkingview.com/en/tools/price-index).
One call returns a tidy table you can analyse, chart or join with your own data.

| Language | Package | Install |
|---|---|---|
| Python | [`coworkingview`](python/) | `pip install coworkingview` · `conda install -c conda-forge coworkingview` |
| R | [`coworkingview`](r/) | `install.packages("coworkingview")` |
| Java | [`coworkingview`](integrations/java/) | Maven Central `io.github.coworkingview:coworkingview` |
| OCaml | [`coworkingview`](clients/ocaml/) | `opam install coworkingview` |
| Swift | [`CoworkingView`](clients/swift/) | Swift Package Manager · CocoaPods `pod 'CoworkingView'` |
| D | [`coworkingview`](clients/d/) | `dub add coworkingview` |
| Command line | [`cwv`](rust/) (Rust) | `cargo install coworkingview` · `docker run --rm coworkingview/cwv` · AUR · Chocolatey · Snap |

[LibreOffice Calc](integrations/libreoffice/) uses the same public API as spreadsheet functions (`CWV_SPACES`, `CWV_PRICE`, and the others in that README).

[Backstage](integrations/backstage/) (`@coworkingview/backstage-plugin-coworkingview`) shows the same prices and spaces on a portal page.

[Nuxt](integrations/nuxt/) (`@coworkingview/nuxt`) auto-imports `useCoworkingProperties` and `useCoworkingRates` for the same two endpoints.

[Thunderbird](integrations/thunderbird/) adds a “CoworkingView prices” button to the message and compose windows and looks up the same Price Index.

[Joomla](integrations/joomla/) (`mod_coworkingview`, CoworkingView Workspace Prices) shows the same Price Index on a site page. That module is GPL-2.0-or-later.

[LM Studio](integrations/lmstudio/) (`coworkingview/coworkingview-workspace-prices`) gives a local model tools for the same prices and a short catalogue search. That plugin is published with `lms push`.

The Python, R, Java and command-line packages read the same public API, follow
the same [specification](spec/SPEC.md) and are tested against the same
[fixtures and expected outputs](spec/), so a number is the same whichever of
those tools you use. The OCaml, Swift and D packages are typed clients for the Price Index
and catalogue search on that API, tested against the recorded API fixtures.

## Why

Flexible workspace is priced in thousands of operator pages, in different
currencies, units and formats. Analysts, proptech teams, journalists and
companies choosing where to open an office end up copying prices by hand.
This kit gives you the medians and spreads behind the Price Index directly —
with the sample size next to every figure, so you know how much to trust it.

## Quickstart

**Python**

```python
import coworkingview as cwv

rates = cwv.rates(city="berlin")
rates[["product", "unit", "median", "p25", "p75", "sample_size"]]
#           product   unit  median    p25    p75  sample_size
# 0       flex_desk  month   214.0  199.0  292.0           72
# 1        fix_desk  month   310.0  290.0  421.0           60
# 2  private_office  month   480.0  399.0  550.0           59
# 3        day_pass    day    35.0   <NA>   <NA>           59
# 4    meeting_room   hour    32.0   <NA>   <NA>           79
```

**R**

```r
library(coworkingview)
rates <- cwv_rates(country = "germany")
subset(rates, product == "private_office", c(city_name, median, sample_size))
```

**Java**

```java
import io.github.coworkingview.Client;
import io.github.coworkingview.RatesQuery;

Client client = Client.create();
client.rates(new RatesQuery().city("berlin"));
```

**OCaml**

```ocaml
let client = Coworkingview.make () in
Coworkingview.market_rates client ~city:"berlin" ()
```

**Swift**

```swift
import CoworkingView

let client = try Client()
let berlin = try await client.rates(city: "berlin")
print(berlin.attribution ?? "")
```

**D**

```d
import coworkingview;

auto client = new Client();
auto berlin = client.rates(city: "berlin");
// Print berlin.attribution next to any figure you republish.
```

**Command line**

```console
$ cwv rates --city berlin
$ cwv spaces --city madrid --product meeting_room --format csv > meeting-rooms.csv
```

## What's in the data

| Function | One row per | Highlights |
|---|---|---|
| `rates()` | city × product | median, 25th/75th percentile, sample size, `low_confidence` flag |
| `cities()` | city | entry price (cheapest monthly option per space), coverage |
| `spaces()` | space | search the catalogue by city, product (incl. event spaces, virtual offices, meeting rooms), capacity, price — with a link to each listing |
| `space(slug)` | space | every published price option of one space |

Products: `flex_desk`, `fix_desk` (dedicated desk), `private_office`,
`exclusive_bereich` (exclusive area), `day_pass`, `meeting_room`,
`event_space`, `virtual_office`, `membership`. New aggregates published by the
Price Index appear in `rates()` without a package update.

## Licence and attribution

- **Code:** MIT (each package's `LICENSE`). The Joomla module in `integrations/joomla/` is GPL-2.0-or-later, the licence the Joomla Extensions Directory requires for a listing.
- **Price Index data** (`rates()`, `cities()`): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  Credit *CoworkingView Price Index* with a link to
  <https://coworkingview.com/en/tools/price-index>. Every result carries the
  exact attribution text (`df.attrs["attribution"]` in Python,
  `attr(x, "attribution")` in R, stderr in the CLI).
- **Catalogue** (`spaces()`, `space()`): names, prices and links are for search
  and reference. Descriptions, photos and logos belong to the operators and
  are not included. The packages cap a search at 200 results; please don't use
  them to copy the catalogue.

## Data source and freshness

Figures come from the operator-published prices of the spaces listed on
[CoworkingView](https://coworkingview.com), normalised to a monthly price per
desk (monthly products), per day (day pass) or per hour (meeting rooms). The
API recomputes them as listings change; `as_of` on every row says when. Cities
below the publication threshold are listed by `cities()` with
`published = false` and no figures.

## Browse offices

- [Offices in Berlin](https://coworkingview.com/en/office-space/berlin)
- [Coworking spaces in Berlin](https://coworkingview.com/en/coworking/berlin)

## Repository layout

```
spec/               SPEC.md, API fixtures, golden outputs (the contract all packages share)
python/             coworkingview on PyPI / conda-forge
r/                  coworkingview on CRAN
rust/               cwv CLI and the coworkingview crate (crates.io, Docker)
integrations/java/  coworkingview on Maven Central
clients/ocaml/      coworkingview OCaml client (opam)
clients/swift/      CoworkingView Swift package (Swift Package Index, CocoaPods)
clients/d/          coworkingview D client (code.dlang.org)
integrations/matomo/CoworkingView/  Matomo 5 dashboard widget
integrations/libreoffice/  Calc add-in (CWV_SPACES, CWV_PRICE)
integrations/backstage/  Backstage frontend plugin
integrations/nuxt/  `@coworkingview/nuxt` module (`useCoworkingProperties`, `useCoworkingRates`)
integrations/thunderbird/  Thunderbird MailExtension (CoworkingView prices)
integrations/joomla/   Joomla 4/5 site module (CoworkingView Workspace Prices)
integrations/lmstudio/  LM Studio tools-provider plugin (coworkingview-workspace-prices)
packaging/          AUR, Chocolatey and Snap manifests for cwv
```

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
Found a wrong price? Report it on the space's page at
[coworkingview.com](https://coworkingview.com) so it is fixed at the source.

Maintained by [CoworkingView](https://coworkingview.com), the coworking and
flexible office comparison platform for Europe and the UAE.
