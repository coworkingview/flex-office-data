# CoworkingView for Nextcloud

Search flexible workspaces from the public [CoworkingView](https://coworkingview.com) catalogue inside Nextcloud. Filter by city and workspace type on the Dashboard. Each result shows the workspace name, the city, the workspace type and a link to the listing. Unified Search can look up a workspace by name, or the workspaces in a city, after you turn on search of connected services.

The app reads `https://api.coworkingview.com`, the same public API as the other clients in this repository. No account and no API key are required. Prices, photos, logos and descriptions are not stored.

Supported Nextcloud versions are the current stable range: **33, 34 and 35** (PHP 8.2–8.5).

## Install

From the App Store, once the app is published: search for **CoworkingView** in **Apps**.

From this repository, build the release archive and install that. The archive has one top-level folder, `coworkingview/`.

```console
cd integrations/nextcloud/coworkingview
make
```

`make` writes `integrations/nextcloud/dist/coworkingview.tar.gz`. In Nextcloud, open **Apps → Your apps** (or the app installer) and use **Download and enable**, or extract the archive into the server's `apps/` directory and run:

```console
sudo -u www-data php occ app:enable coworkingview
```

The server must be able to reach `https://api.coworkingview.com`. Set `COWORKINGVIEW_API_URL` only when the base URL should not be the public API. Nothing is requested when the app is loaded. A search runs when someone uses the widget or unified search.

To develop against a checkout instead of the tarball, run `npm ci && npm run build` in this directory. The build writes `js/coworkingview-dashboard.mjs`, which Nextcloud 33 and newer loads for the widget. Then point Nextcloud's `apps` directory at this folder.

## Use

Enable the app, then open the Dashboard and choose **Customise**. Add **CoworkingView**.

1. Wait for the city list. It comes from `GET /v1/geo/bootstrap`. Cities with no listed spaces are left out. If that request fails, the app uses the published cities from `GET /v1/market/rates`.
2. Choose a city. A city is required. The app does not download the catalogue.
3. Choose a workspace type, or leave **All types**. The types are the product codes the API accepts: flex desk, dedicated desk, private office, exclusive area, day pass, meeting room, event space, virtual office and membership.
4. Choose **Search**.

The widget asks the API for one page of up to 8 listings (`sortBy=date-desc`) and then once per listing so the workspace type can be filled in from that listing's published options. The previous page is not kept. Results are cached on the Nextcloud server for 10 minutes, which is the API's `Cache-Control` max-age. The cache stores the name, city, type codes and listing URL, plus the citation and catalogue notice. It does not store prices, photos or descriptions.

A listing opens on `https://coworkingview.com`. The widget also shows the citation and catalogue notice returned with the search, and how many of the city's matches are on this page.

Search sends the city and workspace type you choose to the public API. That happens only after you press **Search**.

### Unified Search

The provider is an external provider. Nextcloud leaves it off until you enable **Search connected services** in the unified search window. A query is then sent to `GET /v1/search/suggest`.

- A workspace match shows the name, the city and, when the listing detail could be read, the workspace type. The row links to the listing.
- If the query is a city name or city slug and no workspace was suggested, the app shows one page of workspaces in that city.
- Operators and countries are not listed as workspaces.

An empty query is not sent.

## Data

Figures come from the public, keyless API documented in [spec/SPEC.md](../../../spec/SPEC.md). The same product codes and listing URLs are used by the Python, R and command-line clients. Locale follows the user's Nextcloud language when it is English, German or Spanish, and English otherwise. Listing paths are `/en/workspace/`, `/de/buero/` and `/es/oficina/`.

The CoworkingView Price Index is separate and is not shown. City names taken from the price index are only a fallback list for the city menu.

## Build and test

Requires PHP 8.2 or newer (with curl, json and mbstring), Composer, and Node.js 22.

```console
composer install
composer lint
composer test
npm ci
npm run lint
npm test
npm run build
make
```

`composer lint` runs the Nextcloud PHP coding standard and `php -l`. `npm run lint` runs ESLint. The PHPUnit tests use the shared fixtures in `spec/fixtures/` and do not call the network. The Vue tests mount the widget and check the name, city, type and link.

Publishing on apps.nextcloud.com is described in [../PUBLISHING.md](../PUBLISHING.md). The tarball from `make` is the archive you sign. It does not contain a signature. Signing needs the app certificate and `occ integrity:sign-app`, then a new tar of the signed folder.

## Licence

The app code is [AGPL-3.0-or-later](LICENSE), which apps.nextcloud.com requires. The rest of this repository is MIT. Catalogue listings are not licensed for reuse: you may link to them. The notice returned with each search is shown in the widget.

Issues: <https://github.com/coworkingview/flex-office-data/issues>
