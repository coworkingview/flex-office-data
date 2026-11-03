# leaflet-coworkingview

A Leaflet 1.9 layer for the [CoworkingView Price Index](https://coworkingview.com). It calls `GET https://api.coworkingview.com/v1/market/rates` and adds one marker per published city. The marker title and popup show that city's median (`entryMedian` when the API sends it, otherwise the `flex_desk` median, otherwise the first figure median). The popup also lists each `figures` median (or `byType` when `figures` is empty).

The Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Adding the layer registers that credit, with a link to [https://coworkingview.com](https://coworkingview.com), on the map attribution control. The popup includes the `attribution` string from the response.

## Requirements

- Leaflet `^1.9.0` (tested with 1.9.4). Leaflet 2 is not supported.
- A browser with `fetch`, `URL`, and `AbortSignal`.
- No other runtime dependencies. Leaflet is a `peerDependency`.

## Demo

[https://coworkingview.github.io/flex-office-data/leaflet/](https://coworkingview.github.io/flex-office-data/leaflet/)

The page is [`index.html`](index.html). It loads Leaflet from the CDN and `dist/leaflet-coworkingview.js` from the same directory. It requests the live rates API, then, if that request fails (the API allows browser calls from `https://coworkingview.com`), loads `market_rates.json` beside the page. The published copy of that file is `spec/fixtures/market_rates.json`. GitHub Pages publishes this directory from the same artifact as the Eclipse update site, under `leaflet/`, so `eclipse/updates/` stays on the site.

## Install

This package is not published to npm. Use the files in this directory.

Script tag, after Leaflet:

```html
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script src="dist/leaflet-coworkingview.js"></script>
<script>
  var map = L.map('map').setView([50, 10], 4);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    attribution: '&copy; OpenStreetMap contributors'
  }).addTo(map);
  L.coworkingView.layer({ fitBounds: true }).addTo(map);
</script>
```

ES module, from this directory:

```js
import { map as createMap, tileLayer } from 'leaflet';
import { layer } from './src/index.js';

const map = createMap(document.getElementById('map')).setView([50, 10], 4);
tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
  maxZoom: 19,
  attribution: '&copy; OpenStreetMap contributors',
}).addTo(map);
layer({ fitBounds: true }).addTo(map);
```

`package.json` names the package `leaflet-coworkingview`. Its `import` entry is `src/index.js` and its `require` entry is the UMD build, which also sets `L.coworkingView`. Leaflet stays a peer dependency so the app and the plugin share one copy.

## API

### `L.coworkingView.layer(options)` / `layer(options)`

Returns a `LayerGroup`. The request starts when the layer is added to a map. Nothing is fetched when the module loads.

| Option | Default | |
|---|---|---|
| `url` | `https://api.coworkingview.com/v1/market/rates` | Request URL. Query keys below are set on it. |
| `locale` | `'en'` | `locale` query. `en`, `es`, and `de` are the values the API documents. |
| `city` | | `city` query (a city slug). Omit to load every published city. |
| `country` | | `country` query. |
| `currency` | | `currency` query (`EUR`, `GBP`, `USD`, `CHF`, `AED`). |
| `coordinates` | | Extra or replacement centroids, keyed by city slug. A value is `{ lat, lng }` or `[lat, lng]`. Both numbers have to be finite. |
| `fitBounds` | `false` | After markers are added, fit the map to them. |
| `attribution` | CoworkingView and GeoNames credit | Passed through to Leaflet's attribution control. |

`reload()` fetches again and returns a promise of the `load` summary. It rejects with `CoworkingViewError` (`status`, `code`, `title`, `detail`) when the request fails.

### Events

| Event | |
|---|---|
| `loading` | A request started. |
| `load` | Markers are on the layer. Fields: `cities` (marker count), `unlocated` (slugs with no centroid), `attribution`, `license`, `licenseUrl`, `asOf`. |
| `error` | `{ error }` is a `CoworkingViewError`. |

The client sends `Accept: application/json` and, where the environment allows it, `User-Agent: leaflet-coworkingview/0.1.0 (+https://github.com/coworkingview/flex-office-data)`. Browsers forbid setting `User-Agent`. The timeout is 20 seconds. On HTTP 429 or 5xx it waits `Retry-After`, else `RateLimit-Reset`, else 2 seconds, capped at 10 seconds, and retries once.

Unpublished cities (`data.unpublished`) are left off the map. A published city with no centroid is listed in `unlocated` and gets no marker.

### `fetchRates(options)`

The same request, returning the parsed JSON document. Useful when you want the payload without a map. Accepts `url`, `locale`, `city`, `country`, `currency`, `fetch`, and `sleep`.

## Coordinates

`GET /v1/market/rates` has no latitude or longitude. `src/city-coordinates.json` holds a centroid only for city slugs in the response fetched on 2026-11-03.

Source: [GeoNames](https://www.geonames.org/) country dumps from [download.geonames.org/export/dump/](https://download.geonames.org/export/dump/), retrieved 2026-11-03, licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Each row copies `latitude`, `longitude`, `geonameid`, `name`, and `feature code` from the populated-place record whose name, ASCII name, or alternate name matched the API city in that country. `tools/build_city_coordinates.py` rebuilds the file.

These slugs were ambiguous in that dump and are omitted: `ashford`, `casalecchio`, `coleshill`. Pass `coordinates` for them. `molesey` uses West Molesey (GeoNames 2634340): East Molesey and West Molesey both list the alternate name Molesey and lie within 5 km, and the lower GeoNames id is kept. Override any slug the same way.

## Development

```sh
npm test
npm run build
```

`npm test` rebuilds `dist/leaflet-coworkingview.js` and runs vitest in jsdom. Tests parse `spec/fixtures/market_rates.json` and do not call the network. `prepublishOnly` exits with an error so this package is not published to npm.

## Licence

Plugin code: MIT, see [LICENSE](LICENSE).

Price Index data: CC BY 4.0. Keep the attribution control credit and the response `attribution` string with any figure you show.

City centroids: © GeoNames, CC BY 4.0.
