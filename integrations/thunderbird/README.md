# CoworkingView – Workspace Prices

Thunderbird MailExtension that shows flexible workspace prices for one city. The button is labelled **CoworkingView prices** and sits on the message display toolbar and the compose toolbar. It is for someone arranging a meeting or a trip by email. It does not read the message.

Thunderbird 128 or newer. No account and no API key. The package is plain JavaScript: `build.sh` only zips it.

## Install

Build `dist/coworkingview-workspace-prices-0.1.0.xpi`, or take that file from a CI artifact.

In Thunderbird: **Tools → Add-ons and Themes → Extensions → Install Add-on From File**. The entry is **CoworkingView – Workspace Prices**. The homepage link is [https://coworkingview.com](https://coworkingview.com).

While developing, **Tools → Developer Tools → Debug Add-ons → Load Temporary Add-on** and choose `addon/manifest.json`.

Open a message, or a compose window, and click **CoworkingView prices**. The default city is `berlin`. Change it in the popup, or set the default under **Add-ons Manager → CoworkingView – Workspace Prices → Preferences**.

## What it shows

Prices are the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index). One row per product the city publishes: median, 25th and 75th percentile when that percentile exists, and the sample size. A sample under 10 is marked as low confidence. A missing percentile is shown as an em dash, not as zero.

| Request | What is read |
|---|---|
| `GET /v1/market/rates?locale=&city=` | `figures[]` when present, otherwise `byType[]`. `dayPass`, `meetingRoom`, and any later city field that has `median` and `sampleSize`. `data.attribution`, `data.license`, `data.licenseUrl`, `data.asOf`. |
| `GET /v1/market/rates?locale=` | `data.cities[].city.slug` and `name`, for the city list. `unpublished` is not listed. |
| `GET /v1/properties?locale=&city=&page=1&pageSize=1` | `meta.pagination.total` and `meta.citation`. The listing in `data` is discarded. |

`locale` is `en`, `de`, or `es`, from the Thunderbird language. Anything else is sent as `en`. The API rejects a call that omits `locale`.

The catalogue total is not the price-index `propertyCount`. On the recorded Berlin fixture the catalogue total is 110 and the index `propertyCount` is a different number. The popup shows the catalogue total.

Monthly products are per month. A day pass is per day. A meeting room is per hour. The same units are in `spec/SPEC.md` and in `clients/swift` and `clients/ocaml`.

The attribution string is `data.attribution`, copied unchanged, including whatever host the API wrote. The CC BY 4.0 link is `data.licenseUrl`.

A HTTP 429 or 5xx is retried once. The wait is `Retry-After`, otherwise `RateLimit-Reset`, otherwise 2 seconds, and never more than 10. The browser sets `User-Agent`. An extension page cannot replace that header.

## Privacy

The only stored value is the city slug, in `storage.local` on this computer. It is not synced.

Opening the button sends that slug and the language to `https://api.coworkingview.com`. Nothing from the message, the address book, or the account is read or sent. The add-on sets no cookie. Details are on the options page.

The website privacy policy at [https://coworkingview.com/en/privacy](https://coworkingview.com/en/privacy) describes the website. It returned HTTP 200 on 1 November 2026. It is linked from the options page. It is not a description of this add-on. The add-on policy for addons.thunderbird.net is in [docs/THUNDERBIRD-LISTING.md](docs/THUNDERBIRD-LISTING.md).

## Build, test, lint

```console
npm ci
npm test
npm run lint
./build.sh
```

`npm test` uses node:test and jsdom. Fixtures are the recorded responses in `spec/fixtures/`. Tests do not call the network.

`npm run lint` runs `addons-linter` and fails if it reports an error, a warning, or a file it classifies as minified. The Firefox data-collection manifest key is not set: current addons-linter rejects it when `strict_min_version` is `128.0`, and warns if a newer Firefox check is left on. The reason is in [docs/THUNDERBIRD-CHECKLIST.md](docs/THUNDERBIRD-CHECKLIST.md).

`./build.sh` writes `dist/coworkingview-workspace-prices-0.1.0.xpi`. `manifest.json` is at the root of the zip. Tests, docs, and `node_modules` are not in the zip. The script does not transform JavaScript, so the xpi is the source a reviewer reads. No separate source archive is required.

Icons are drawn by `tools/render_icons.py` (serif “CV”, gold dot, off-white). Regenerate them with Pillow if you change the script. There was no logo file under `/cursor/stores/bot`.

Screenshots in `docs/screenshots/` were rendered in headless Chrome from the add-on's popup renderer and the Berlin fixture:

```console
node tools/capture.mjs
```

## Licence

MIT. See [LICENSE](LICENSE). The Price Index data is not covered by that licence. It is CC BY 4.0, and the popup keeps the attribution the API returns. The catalogue is not licensed for reuse. The extension asks for one properties row so it can read `pagination.total`, and it does not keep the listing.
