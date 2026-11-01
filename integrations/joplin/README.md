# CoworkingView

Insert flexible-workspace listings and city price figures from [CoworkingView](https://coworkingview.com) into a Joplin note. The English pages are at [coworkingview.com/en](https://coworkingview.com/en).

The plugin reads the public API at `https://api.coworkingview.com` (the same `GET /v1/properties` and `GET /v1/market/rates` endpoints as the other clients in this repository). No account and no API key are required. Photos, logos and descriptions are not inserted.

Maintained by [CoworkingView](https://coworkingview.com). This plugin was built with AI assistance.

## Usage

Open a note in the markdown editor, then run either command from the command palette or from the Tools menu.

**CoworkingView: Insert workspace search results**

The dialog asks for a city slug, for example `berlin`. A slug with spaces, such as `Abu Dhabi`, is turned into `abu-dhabi`. The command inserts one page of up to 20 listings, most recently updated first:

| Workspace | City | Operator | Listing |
| --- | --- | --- | --- |
| [St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße](https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin) | Berlin | St. Oberholz | https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin |

Each name links to that listing on coworkingview.com. The API's citation and catalogue notice are placed under the table. If the city has no listings, nothing is inserted.

**CoworkingView: Insert market rates**

The dialog asks for a city. Leave it empty to insert every published city. When the API returns price figures, the command inserts a Markdown table of the median, the 25th and 75th percentiles, the sample size and a low-confidence mark (sample size under 10). Day passes are per day and meeting rooms are per hour; monthly products are per month. These figures are the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index). The attribution and CC BY 4.0 licence text returned by the API are kept under the table. If the response has no published figures, nothing is inserted.

## Settings

In Joplin, open **Configuration → CoworkingView**.

- **Default city** — pre-fills both dialogs. Example: `berlin`. Leave it empty to type a city each time.
- **API URL** — optional API root. Leave it empty to use `https://api.coworkingview.com`.

## Build

From this directory:

```bash
npm install
npm test
npm run dist
```

`npm run dist` writes `publish/com.coworkingview.joplin.jpl` and `publish/com.coworkingview.joplin.json`. In Joplin, install that `.jpl` from **Configuration → Plugins**, or add this directory under development plugins.

## Publish

From `integrations/joplin`, after the package is logged in to npm:

```bash
npm publish
```

`npm publish` runs `prepare`, which runs `npm run dist`, and uploads the `publish/` directory. The package name is `joplin-plugin-coworkingview` and the keywords include `joplin-plugin`, which is what the Joplin plugin index requires. Do not publish from CI.
