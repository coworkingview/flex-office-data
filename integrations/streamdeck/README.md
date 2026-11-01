# Coworking Prices for Stream Deck

Stream Deck plugin that shows live CoworkingView figures on a key. Workspace Count is how many coworking spaces a city lists. Market Rate is one Price Index median. Pressing a key opens https://coworkingview.com.

The plugin talks to the public API at `https://api.coworkingview.com`. It does not use an API key.

## Requirements

Development uses Node.js 24, matching [Getting Started](https://docs.elgato.com/streamdeck/sdk/introduction/getting-started). The plugin itself requires Stream Deck 7.1 or later, because that is the first release that runs Node.js 24. macOS 12 and Windows 10 are the declared minimums.

## Actions

| Action          | What the key shows                                           | Source                                                                                      |
| --------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| Workspace Count | Catalogue size and city name, for example `143` and `Berlin` | `GET /v1/properties?locale=en&city=<city>&page=1&pageSize=1`, field `meta.pagination.total` |
| Market Rate     | Median amount, currency, figure, and city                    | `GET /v1/market/rates?locale=en&city=<city>`                                                |

`locale` is required by the API (`en`, `de`, or `es`). The plugin always sends `en`. The default city is `berlin`.

Market Rate can show these fields, and only these fields:

- `figures[]` where `optionType` is `flex_desk`, `fix_desk`, or `private_office` (`median.amount`, `median.currency`, monthly)
- `dayPass.median` (daily)
- `meetingRoom.median` (hourly)

The catalogue total is not `data.propertyCount` on the rates response. Those two numbers differ. A city with no published figure shows an em dash and the Stream Deck alert. A city with an empty catalogue shows `0`.

Visible keys refresh every 30 minutes. Responses are cached in memory for the same interval, and one in-flight request is shared by every key that needs it. The plugin asks for one property page (`pageSize=1`) so it can read the total without copying the catalogue. It does not display listing titles, excerpts, photos, or logos.

Each fresh rates response includes `data.attribution`. The plugin writes that string to the Stream Deck log unchanged. Price Index medians are CC BY 4.0.

## Property inspector

Each action has its own inspector. City is a select filled from the published cities on `GET /v1/market/rates?locale=en`. Market Rate also has a figure select. Settings save as they change. If the city list cannot be loaded, the select falls back to Berlin.

## Build

```sh
npm ci
npm test
npm run lint
npm run build
npm run validate
npm run pack
```

`npm run pack` writes `com.coworkingview.prices.streamDeckPlugin` in this directory. The bundle `bin/plugin.js` is produced by the build and is not committed. `bin/package.json` marks that bundle as an ES module, which is how Stream Deck loads it. Rolldown lowers the `@action` decorators so Node.js 24 can parse the bundle.

Icons are generated from `integrations/nextcloud/coworkingview/img/app.png` (black serif CV, gold dot) with `npm run icons`.

`COWORKINGVIEW_API_URL` overrides the API origin for local tests. Leave it unset for production.
