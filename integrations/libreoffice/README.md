# CoworkingView for Calc

Spreadsheet functions for the public [CoworkingView](https://coworkingview.com) catalogue and price index. The extension is a LibreOffice `.oxt` (Python, no extra packages) and is meant to be published on [extensions.libreoffice.org](https://extensions.libreoffice.org).

No account and no API key. LibreOffice 7.0 or newer, including 24.x, on Linux, Windows and macOS.

## Install

Build the package, or take `dist/coworkingview-calc-0.1.0.oxt` from a release.

**Extension Manager.** In LibreOffice choose **Tools → Extension Manager → Add**, select the `.oxt`, and accept the MIT license. Restart LibreOffice, including a quickstarter if one is running. The entry is **CoworkingView for Calc**. The publisher link is [https://coworkingview.com](https://coworkingview.com).

**Command line.**

```console
unopkg add --suppress-license dist/coworkingview-calc-0.1.0.oxt
```

Restart LibreOffice after `unopkg` returns.

In Calc the functions are in the Function Wizard under **Add-In**. A locale that uses `,` as the decimal separator (most of Europe) separates arguments with `;`:

```
=CWV_PRICE("berlin";"flex_desk")
```

A locale that uses `.` as the decimal separator (for example English (USA)) uses `,`:

```
=CWV_PRICE("berlin","flex_desk")
```

On LibreOffice 24.2.7 with English (USA), that formula returned 214, `=CWV_SPACES("berlin")` returned 143, and `=CWV_RATE("berlin","flex_desk","p25")` returned 199 (1 November 2026).

An empty city is Berlin. The city is the catalogue slug (`berlin`, `bad-homburg`), not a translated name.

## Functions

| Function | Returns |
|---|---|
| `CWV_SPACES(city)` | Number of workspace listings in the city. |
| `CWV_PRICE(city, product)` | Median market rate for that product. |
| `CWV_RATE(city, product, stat)` | `median`, `min`, `max`, `p25` or `p75`, when that statistic is published. |
| `CWV_CURRENCY(city)` | ISO currency of the price index, for example `EUR`. |
| `CWV_SAMPLE(city, product)` | Observations behind that product. |
| `CWV_ASOF(city)` | Price-index timestamp (`asOf`). |
| `CWV_SOURCE()` | `Data: CoworkingView https://coworkingview.com` |
| `CWV_ATTRIBUTION(city)` | Attribution string shipped with the price index. Keep it with any figure you republish. |

`CWV_SOURCE()` does not call the network. The others do, the first time each URL is needed.

Product codes are the API's: `flex_desk`, `fix_desk`, `private_office`, `day_pass`, `meeting_room`, plus any later aggregate the city object publishes in the same shape. `Flex Desk` and `day-pass` are accepted and sent as `flex_desk` and `day_pass`. A code the city does not publish returns `CWV: unknown product '…'. Available: …` rather than a zero.

A failure is text in the cell, starting with `CWV:`. Examples: `CWV: unknown city 'nope'`, `CWV: 'p25' is not published for 'day_pass'. Available: median`, `CWV: network error: …`.

## How the fields are mapped

Checked against live responses from `https://api.coworkingview.com` on 2026-11-01. `locale=en` is required; without it the API returns HTTP 400. Only fields present on those responses are read. Missing statistics are an error, not a made-up number.

| Function | Request | Field |
|---|---|---|
| `CWV_SPACES` | `GET /v1/properties?locale=en&city=<slug>&page=1&pageSize=1` | `meta.pagination.total` |
| `CWV_PRICE` | `GET /v1/market/rates?locale=en&city=<slug>` | `median.amount` |
| `CWV_RATE` | same rates request | `median`, `min`, `max`, `p25` or `p75` `.amount` |
| `CWV_CURRENCY` | same | `data.cities[].currency` |
| `CWV_SAMPLE` | same | `sampleSize` |
| `CWV_ASOF` | same | `data.asOf` |
| `CWV_ATTRIBUTION` | same | `data.attribution`, unchanged |
| `CWV_SOURCE` | none | the fixed credit line above |

`CWV_SPACES` also requests the rates endpoint and returns an error when the slug is not in `data.cities[].city.slug`. A typo on the catalogue endpoint alone comes back as total `0`, which would look like a real empty city.

For `flex_desk`, `fix_desk` and `private_office`, the median, p25, p75 and sample size are taken from `figures[]` where `optionType` matches. `min` and `max` are taken from `byType[]`, because `figures[]` does not carry them. `day_pass` is `dayPass.median.amount` (and `dayPass.sampleSize`). `meeting_room` is `meetingRoom`. Any other city field that is an object with both `median` and `sampleSize` is exposed the same way, under the camelCase name turned into snake_case. That is how a new aggregate shows up without a new release.

On 2026-11-01, Berlin's catalogue total (`pagination.total`) was 143 and the price-index `propertyCount` was 85. `CWV_SPACES` is the catalogue total. `propertyCount` is a different count and is not returned.

These fields are on the response and are not returned, because they are not a product rate or because the extension does not copy the catalogue: city-level `p25`, `p75`, `min`, `max`, `entryMedian`, `entryMin`, `entryMax`; `buildings`; and, from `/v1/properties`, the listing itself (`title`, `excerpt`, `images`, `amenities`, `fromPrice`, operator names). `pageSize=1` is only there so `pagination.total` is present. The listing body is discarded before the cache.

The price index is CC BY 4.0. `CWV_ATTRIBUTION` returns the API's own attribution string, including whatever host it names. The extension credit line (`CWV_SOURCE`) does not replace it.

## Privacy

Only the city you type is sent to `https://api.coworkingview.com`. The request also sends a fixed `locale=en` (the API rejects a call that omits it) and, for `CWV_SPACES`, `page=1` and `pageSize=1`. No API key, no other cells, and no spreadsheet contents are sent.

Responses are kept in memory for the `Cache-Control: max-age` the API sends (600 seconds on rates and 300 seconds on properties when this was checked), or 600 seconds when that header is missing. The cache is the LibreOffice process. It is not written to disk. A HTTP 429 or 5xx is retried once.

Set `COWORKINGVIEW_API_URL` only to point the extension at a different base URL. The default is `https://api.coworkingview.com`.

## Build

The `.oxt` is a zip. `types.rdb` is produced with LibreOffice's `unoidl-write`, so the SDK has to be installed on the build machine. The installed extension does not need the SDK.

```console
sudo apt install libreoffice-calc python3-uno libreoffice-dev
./build.sh
```

The script writes `dist/coworkingview-calc-0.1.0.oxt`. `make` runs the same script.

`UNOIDL_WRITE`, `UNO_TYPES` and `UNO_OFFAPI` override the tool and the two type registries when they are not in the Debian paths.

Checks that do not need LibreOffice:

```console
python3 -m pip install ruff
ruff check .
python3 -m py_compile coworkingview_calc.py pythonpath/coworkingview_api.py
python3 -m unittest discover -s tests -v
```

`tests/smoke.sh` installs the `.oxt` with `unopkg` and evaluates `CWV_SOURCE()`, `CWV_SPACES("berlin")`, `CWV_PRICE` and `CWV_ATTRIBUTION` in headless Calc. It needs a built package, `soffice`, and network access to the public API.

Icons are rendered from `icons/coworkingview-mark.png` (the CoworkingView wordmark) by `tools/render_icons.py`. Regenerate them with Pillow if that file changes. The script does not draw a new mark.

Publishing text for extensions.libreoffice.org is in [docs/LISTING.md](docs/LISTING.md). The rule-by-rule check is [docs/PUBLISHING-CHECKLIST.md](docs/PUBLISHING-CHECKLIST.md).

## Licence

MIT. See [LICENSE](LICENSE). The Price Index data is not covered by that licence; it is CC BY 4.0, and the catalogue is not licensed for reuse. The same text is shown by the Extension Manager before install.
