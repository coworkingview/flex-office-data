# cwv — flexible-office prices from the command line

[![crates.io](https://img.shields.io/crates/v/coworkingview.svg)](https://crates.io/crates/coworkingview)
[![docs.rs](https://img.shields.io/docsrs/coworkingview)](https://docs.rs/coworkingview)
[![License: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](LICENSE)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

`cwv` asks [CoworkingView](https://coworkingview.com) what flexible office
space costs, city by city, and searches its catalogue of coworking spaces,
private offices, meeting rooms, event spaces and virtual offices. It reads a
public API — no key, no sign-up — and prints aligned tables, CSV or JSON.

The figures come from the
[CoworkingView Price Index](https://coworkingview.com/en/tools/price-index):
median, 25th and 75th percentile prices for flex desks, fixed desks and private
offices per month, day passes per day and meeting rooms per hour, published
under CC BY 4.0.

This crate is also a Rust library (`coworkingview`) — see
[Library](#library).

## Install

| | |
|---|---|
| Cargo | `cargo install coworkingview` |
| Arch Linux (AUR) | `paru -S cwv` (or `yay -S cwv`) |
| Windows (Chocolatey) | `choco install cwv` |
| Linux (Snap) | `sudo snap install cwv` |
| Docker | `docker run --rm coworkingview/cwv rates --city berlin` |
| Binaries | [GitHub releases](https://github.com/coworkingview/flex-office-data/releases) (Linux static, macOS, Windows) |

The binary is self-contained: TLS is rustls with bundled Mozilla roots, so it
needs neither OpenSSL nor a system CA bundle. Building from source needs Rust
1.88 or newer.

## Quick start

```console
$ cwv rates --city berlin
╭────────┬────────────────┬───────┬─────────┬─────────┬─────────┬────────┬────────┬───────────╮
│ City   ┆ Product        ┆ Per   ┆  Median ┆     P25 ┆     P75 ┆ Prices ┆ Spaces ┆ Operators │
╞════════╪════════════════╪═══════╪═════════╪═════════╪═════════╪════════╪════════╪═══════════╡
│ Berlin ┆ Flex desk      ┆ month ┆ 214 EUR ┆ 199 EUR ┆ 292 EUR ┆    72  ┆     66 ┆        38 │
│        ┆ Fixed desk     ┆ month ┆ 310 EUR ┆ 290 EUR ┆ 421 EUR ┆    60  ┆     56 ┆        37 │
│        ┆ Private office ┆ month ┆ 480 EUR ┆ 399 EUR ┆ 550 EUR ┆    59  ┆     38 ┆        20 │
│        ┆ Day pass       ┆ day   ┆  35 EUR ┆       — ┆       — ┆    59  ┆     55 ┆        27 │
│        ┆ Meeting room   ┆ hour  ┆  32 EUR ┆       — ┆       — ┆    79  ┆     51 ┆        25 │
╰────────┴────────────────┴───────┴─────────┴─────────┴─────────┴────────┴────────┴───────────╯

Source: CoworkingView Price Index (https://www.coworkingview.com/en/tools/price-index), as of
October 2026. Licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/). …
License: https://creativecommons.org/licenses/by/4.0/ (as of 2026-10-27T21:06:48.313Z)
```

(Figures above are from October 2026; yours will be current.) The two lines
under the table go to **stderr**, so `cwv rates > rates.txt` and pipes get
only the data while you still see the attribution.

## Commands

### `cwv rates` — the Price Index

One row per city × product.

```sh
cwv rates                                    # every city
cwv rates --city berlin                      # one city (slug)
cwv rates --country ES --currency USD        # Spanish cities, in dollars
cwv rates -p flex_desk,private_office -f csv > rates.csv
```

Products: `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`,
`day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership`.
Currencies: `EUR`, `GBP`, `USD`, `CHF`, `AED` (conversions are approximate).
Figures based on fewer than 10 prices are marked `*` in the table and
`low_confidence = true` in CSV/JSON: read them as indicative.

### `cwv cities` — cities covered

```console
$ cwv cities
╭──────────────┬─────────┬───────────────────┬───────────┬──────────────┬───────────────────┬───────────┬───────────┬────────╮
│ City         ┆ Country ┆            Spaces ┆ Operators ┆ Entry median ┆       Entry range ┆       P25 ┆       P75 ┆ Prices │
╞══════════════╪═════════╪═══════════════════╪═══════════╪══════════════╪═══════════════════╪═══════════╪═══════════╪════════╡
│ Abu Dhabi    ┆ AE      ┆                 2 ┆         1 ┆    1,453 AED ┆ 1,069 – 7,535 AED ┆ 1,400 AED ┆ 2,200 AED ┆      2 │
│ Berlin       ┆ DE      ┆                85 ┆        48 ┆      265 EUR ┆    80 – 2,100 EUR ┆   219 EUR ┆   450 EUR ┆     85 │
│ Madrid       ┆ ES      ┆                10 ┆         6 ┆      325 EUR ┆    85 – 1,980 EUR ┆   195 EUR ┆   349 EUR ┆     10 │
╰──────────────┴─────────┴───────────────────┴───────────┴──────────────┴───────────────────┴───────────┴───────────┴────────╯
```

The *entry price* is each space's cheapest monthly option; the range is the
cheapest and most expensive of those.

### `cwv spaces` — search the catalogue

```sh
cwv spaces --city berlin --zone mitte
cwv spaces --city madrid --product private_office --min-capacity 4
cwv spaces --city berlin --product day_pass --max-price 30 --sort price-asc
cwv spaces --operator regus --limit 200 -f csv
```

| Option | |
|---|---|
| `--city`, `--country`, `--zone`, `--operator` | Filters (slugs; country is an ISO code) |
| `-p, --product` | Only spaces offering this product |
| `--min-capacity` | Room for at least this many people |
| `--min-price`, `--max-price`, `--currency` | Price range |
| `--sort` | `random` (default), `price-asc`, `date-desc`, `date-asc` |
| `--seed` | Repeat a random order exactly |
| `-n, --limit` | Results, 1–200 (default 50) |

At most 200 spaces per call: the catalogue is there to be searched and linked
to, not copied (see [Licence](#attribution-and-licence)).

### `cwv space <slug>` — one space

```console
$ cwv space sankt-oberholz-rosenthaler-berlin
 Space          St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße
 Operator       St. Oberholz
 Address        Rosenthaler Straße 72a, 10119 Berlin, Germany
 Price vs city  around the city median (214 EUR, 72 prices)
 Link           https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin

╭────────────────┬──────────────────────────────────┬────────────┬───────┬────────╮
│ Product        ┆ Offer                            ┆      Price ┆ Per   ┆ People │
╞════════════════╪══════════════════════════════════╪════════════╪═══════╪════════╡
│ Flex desk      ┆ Coworking Membership – Flex Desk ┆    209 EUR ┆ month ┆ —      │
│ Fixed desk     ┆ Fixed Desk                       ┆ on request ┆ month ┆ —      │
│ Virtual office ┆ Virtual Office with St.Dropscan  ┆     69 EUR ┆ month ┆ —      │
╰────────────────┴──────────────────────────────────┴────────────┴───────┴────────╯
```

With `-f csv` you get the pricing table; with `-f json` the space under
`space` and its prices under `rows`.

### Output formats and global options

| Option | |
|---|---|
| `-f, --format table\|csv\|json` | Table (default), CSV with a header row, or JSON |
| `-l, --locale en\|es\|de` | Language of names and of the coworkingview.com links |
| `--no-color` | No colours (`NO_COLOR` is honoured too; pipes are never coloured) |
| `--api-url <URL>` | Another API server (also `COWORKINGVIEW_API_URL`) |

CSV uses the kit's shared format — comma, `\n`, empty field for null,
`true`/`false`, numbers as the API wrote them — so it is identical to what the
Python and R packages produce. JSON is always one object:

```json
{ "attribution": "Source: CoworkingView Price Index (…)", "license": "https://creativecommons.org/licenses/by/4.0/",
  "as_of": "2026-10-27T21:06:48.313Z", "notice": null, "rows": [ … ] }
```

```sh
cwv cities -f json | jq -r '.rows[] | select(.published) | .city_slug'
```

**Exit codes:** `0` success, `1` API or network error (the problem `code`,
e.g. `VALIDATION_FAILED`, is in the message on stderr), `2` usage error.

### Shell completions and man page

```sh
cwv completions bash > ~/.local/share/bash-completion/completions/cwv
cwv completions zsh  > ~/.zfunc/_cwv
cwv completions fish > ~/.config/fish/completions/cwv.fish
cwv completions powershell >> $PROFILE
cwv man > cwv.1 && man ./cwv.1
```

Distribution packages (AUR, Snap) install both for you.

## Library

```toml
[dependencies]
coworkingview = { version = "0.1", default-features = false }  # library only, no clap
```

```rust
use coworkingview::{Client, Product, RatesQuery, SpacesQuery};

fn main() -> Result<(), coworkingview::Error> {
    let client = Client::new();

    let rates = client.rates_with(&RatesQuery::new().product(Product::FlexDesk))?;
    for r in rates.iter() {
        println!("{:<12} {:>6} {}", r.city_name, r.median, r.currency);
    }
    // CC BY 4.0: publish this with the figures.
    println!("{}", rates.attribution.as_deref().unwrap_or_default());

    let spaces = client.spaces(&SpacesQuery::new().city("berlin").limit(10))?;
    let first = client.space(&spaces[0].slug)?;
    println!("{} — {} offers", first.title, first.pricing.len());
    Ok(())
}
```

Every call returns a `Dataset<T>` that dereferences to the rows and carries
`attribution`, `license`, `as_of` and `notice`. Errors are a single
`coworkingview::Error` with a stable `.code()` (`VALIDATION_FAILED`,
`NOT_FOUND`, `BAD_RESPONSE`, `NETWORK_ERROR`, …). `coworkingview::parse`
turns saved API responses into the same rows without a network call, and
`coworkingview::csv::write` writes them in the shared CSV format. Full API
docs: [docs.rs/coworkingview](https://docs.rs/coworkingview).

**HTTP behaviour.** Blocking requests (ureq + rustls), 20 s timeout,
`User-Agent: coworkingview-rust/<version>`. On `429` or `5xx` the client waits
for `Retry-After` (else `RateLimit-Reset`, else 2 s; never more than 10 s) and
retries **once**. The API allows 120 requests per minute per IP and responses
are cacheable for 10 minutes — please cache rather than poll.

## Attribution and licence

- **Code:** MIT — see [LICENSE](LICENSE).
- **Price Index data** (`rates`, `cities`): [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
  Reuse it freely — in reports, articles, models — and credit it with the
  attribution line `cwv` prints (or the `attribution` field in JSON). The
  methodology and interactive charts are on the
  [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) page.
- **Catalogue content** (`spaces`, `space`): names, descriptions, photos and
  prices of individual spaces belong to their operators and are **not
  licensed** to you. You may search it and link to the listing pages;
  systematic extraction or re-publication of the catalogue is not permitted.
  `cwv` returns no photos, logos or descriptions and caps searches at 200
  results for this reason.

## Related

This crate is part of [flex-office-data](https://github.com/coworkingview/flex-office-data),
which also ships Python and R packages built from the same specification and
tested against the same fixtures.
