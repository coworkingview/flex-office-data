# coworkingview

D client for the public API of [CoworkingView](https://coworkingview.com).

It reads the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) and searches the coworking catalogue. No API key. The only dependency is Phobos (`std.net.curl` and `std.json`). Nothing is downloaded when the module is imported.

API reference: <https://coworkingview.com/en/api>.

This library was built with AI assistance.

Price Index figures are open data from CoworkingView under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The code is MIT.

| | |
|---|---|
| API | `https://api.coworkingview.com` |
| Package | `coworkingview` 0.1.0 |
| Compilers | DMD and LDC, frontend 2.097 or newer |

## Install

On [code.dlang.org](https://code.dlang.org), once this package is registered:

```
dub add coworkingview
```

```json
"dependencies": {
    "coworkingview": "~>0.1.0"
}
```

The release tag on the standalone repository is `v0.1.0`. Until that tag is on the registry, point a path dependency at a checkout of this package (the repository root after the copy; `clients/d` in the flex-office-data monorepo).

Linking needs libcurl, which Phobos uses for `std.net.curl`. On Debian or Ubuntu that is `libcurl4-openssl-dev`.

## Usage

```d
import std.stdio : writefln, writeln;

import coworkingview;

void main()
{
    auto client = new Client();

    auto berlin = client.rates(city: "berlin");
    foreach (rate; berlin.data)
        writefln("%s %s %s %s n=%s", rate.product, rate.unit, rate.medianText,
            rate.currency, rate.sampleSize);
    // Print this next to any figure you republish. The index is CC BY 4.0.
    writeln(berlin.attribution);

    auto rooms = client.spaces(city: "madrid", product: "meeting_room", limit: 20);
    foreach (room; rooms.data)
        writeln(room.title, " ", room.url);

    auto space = client.space("sankt-oberholz-rosenthaler-berlin");
    foreach (offer; space.data.pricing)
    {
        // price is null when the operator quotes on request. It is not zero.
        auto price = offer.price.isNull ? "on request" : offer.priceText;
        writefln("%s %s %s", offer.product, price, offer.currency);
    }
}
```

`new Client()` talks to `https://api.coworkingview.com`, or to whatever `COWORKINGVIEW_API_URL` is set to. The constructor changes the base URL, the timeout (default 20 seconds), the `User-Agent` and the default locale (`en`, `es` or `de`).

```d
auto client = new Client(null, 5, "my-research-project/1.0 (me@example.org)", "de");
```

On HTTP 429 or 5xx the client waits `Retry-After` seconds (else `RateLimit-Reset`, else 2 seconds, never more than 10) and retries once. The API allows 120 requests per minute per IP. Responses are cacheable for 10 minutes.

`dub run :example` prints the Berlin medians. That command calls the live API.

### What you can ask for

| Parameter | Values |
|---|---|
| locale | `en` (default), `es`, `de` |
| currency | `EUR`, `GBP`, `USD`, `CHF`, `AED`, `VES` (any case). `VES` is sent through; the API answers 400 where it cannot convert |
| product | `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership` |
| sort | `random` (default), `price-asc`, `date-desc`, `date-asc` |

`rates` and `cities` call `GET /v1/market/rates`. `spaces` calls `GET /v1/properties` and follows pages until `limit` rows (default 50, maximum 200). `space` calls `GET /v1/properties/{slug}`.

Optional numeric filters on `spaces` are `Nullable` values (`import std.typecons : nullable`), for example `minPrice: nullable(200.0)`. `operatorSlug` is sent as the query parameter `operator`.

A new Price Index aggregate shows up in `rates` without a library update. Products this version does not name a unit for come back with `unit` null.

`spaces` does not return descriptions, photos or logos. Those belong to the operators. Link to `url` instead of copying the catalogue. The catalogue notice is `Dataset.notice`.

## Data

Figures come from operator-published prices of the spaces listed on [CoworkingView](https://coworkingview.com). `asOf` on a Price Index result says when the index was computed. Keep `attribution` with anything you publish. The licence URL is `license` (`licenseUrl` on the response).

`medianText` (and the other `*Text` fields) is the number as the API wrote it.

## Tests

```
dub build
dub test
```

`dub test` replays `fixtures/` and compares Price Index and catalogue rows with `golden/`. It does not open a socket. Pass your own `Transport` to `Client` when you want the same in a test of your own.

## Licence and attribution

- **Code:** MIT, see [LICENSE](LICENSE).
- **Price Index data:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit *CoworkingView Price Index* with a link to <https://coworkingview.com/en/tools/price-index>. Use the `attribution` field on the result.
- **Catalogue:** names, prices and links are for search and reference. Descriptions, photos and logos belong to the operators and are not included. A search that follows pages stops at 200 listings.

Changes are in [CHANGES.md](CHANGES.md). Publishing notes are in [docs/DUB-CHECKLIST.md](docs/DUB-CHECKLIST.md). Issues: <https://github.com/coworkingview/flex-office-data/issues>.

Maintained by [CoworkingView](https://coworkingview.com).
