# CoworkingView Workspace Prices

Site module for Joomla 4 and Joomla 5. The element name is `mod_coworkingview`. The name in the install manifest is **CoworkingView Workspace Prices**, which is also the name to use on the Joomla Extensions Directory.

It shows indicative flexible-workspace prices for one city: median, spread (25th to 75th percentile), and sample size. The figures come from the public [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) (`GET /v1/market/rates` on `https://api.coworkingview.com`). There is no API key and nothing to pay.

This module was built with AI assistance.

CoworkingView is not affiliated with or endorsed by Open Source Matters or the Joomla project. The name Joomla is used here only to name the software this module installs into.

## Licence

GNU General Public License version 2 or later. The full text is [LICENSE.txt](mod_coworkingview/LICENSE.txt) inside the package. You may use, study, share, and change this module under that licence. There are no extra restrictions and no commercial key.

The Price Index figures are not covered by the GPL. They are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The module shows the attribution string the API returns and a link labelled `Data: CoworkingView` to `https://coworkingview.com`.

## Install

1. Download `mod_coworkingview-1.0.0.zip` from the GitHub release tagged `joomla-v1.0.0` (that release is created after this branch is merged to `main`).
2. In the Joomla administrator, open System → Install → Extensions and upload the zip.
3. Open Content → Site Modules → New, choose **CoworkingView Workspace Prices**, set the parameters below, publish the module, and assign a position and pages.

The zip has `mod_coworkingview.xml` at its root. Install with method `upgrade`, so a later version replaces this one.

## Configuration

| Parameter | Default | What it does |
|---|---|---|
| City | `berlin` | City slug sent to the API. Letters, digits, `.`, `_`, and `-`. Example: `abu-dhabi`. |
| Product type | All products | One Price Index product, or every product the city publishes. |
| Language | English | Locale sent to the API: `en`, `de`, or `es`. |
| Items | 6 | How many product rows to show, from 1 to 12. |
| Cache time | 60 | Minutes to keep a successful response, from 10 to 1440. |

A failed request is not cached. Changing the product or the item count uses the cached city response. Changing the city or the language fetches again.

The module sets its own cache group (`mod_coworkingview`) and turns caching on for that request even when Joomla's global cache is off. Joomla's separate module-caching option (Advanced → Caching) should stay on **No caching**. If that option caches the whole module, a later change of product or item count can keep showing the previous HTML until that cache expires.

## What is sent

Each refresh sends one HTTPS GET to `https://api.coworkingview.com/v1/market/rates` with `locale` and `city`. The user agent is `mod_coworkingview/1.0.0 (+https://github.com/coworkingview/flex-office-data)`. No API key, no visitor address, and no Joomla account data is added by the module. A 429 or 5xx response is retried once.

## Updates

The manifest points at the update stream:

`https://raw.githubusercontent.com/coworkingview/flex-office-data/main/integrations/joomla/updates/mod_coworkingview.xml`

The changelog is:

`https://raw.githubusercontent.com/coworkingview/flex-office-data/main/integrations/joomla/updates/changelog.xml`

After merge, tag `joomla-v1.0.0` and attach `mod_coworkingview-1.0.0.zip` to that GitHub release. The update stream downloads that asset. Do not create the release before the file is on `main`, because the raw update XML is read from `main`.

## Build and check

From this directory:

```bash
composer install --no-interaction --prefer-dist
./check.sh
./vendor/bin/phpcs --standard=phpcs.xml.dist -n
./build.sh
```

`check.sh` runs `php -l`, the parser fixture tests, and `tools/jed-check.php`. That script applies the JED Checker rules that can run without a Joomla site: the GPL phrase, the `_JEXEC` pattern used by PH2, the manifest (`<licence>`, update server, name, version), language files, and the zip layout. The JED Checker component itself needs a Joomla installation and a database, so CI does not boot that component. `phpcs` uses the Joomla standard from `joomla/coding-standards` 3.0.0-alpha. CI repeats the syntax checks on PHP 8.1, 8.2, and 8.3 and uploads `mod_coworkingview-1.0.0.zip` as an artifact.

Screenshots in [screenshots/](screenshots/) are rendered from `tmpl/default.php` with a live API response. See [docs/JED-LISTING.md](docs/JED-LISTING.md) for the directory listing text.
