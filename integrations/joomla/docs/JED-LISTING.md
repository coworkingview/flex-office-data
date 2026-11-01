# Joomla Extensions Directory listing

Paste these fields when submitting **CoworkingView Workspace Prices**. The install manifest `<name>` is the same string. Do not add promotional words, and do not imply that Open Source Matters or the Joomla project endorses this extension.

The download link is the GitHub release tagged `joomla-v1.0.0`. Create that release after this branch is merged, and attach `mod_coworkingview-1.0.0.zip`. The release does not exist until then.

## Name

CoworkingView Workspace Prices

## Short description

Indicative flexible-workspace prices for one city from the public CoworkingView Price Index. GPL. No API key.

109 characters.

## Long description

CoworkingView Workspace Prices is a site module for Joomla 4 and Joomla 5. It shows indicative prices for flexible workspace in one city: a flex desk, fixed desk, private office, day pass, meeting room, and any other product the CoworkingView Price Index publishes for that city. Each row is the median, the 25th to 75th percentile when the index provides both, and the sample size. A sample under 10 is marked as low confidence.

The figures are the public Price Index, CC BY 4.0. The module shows the attribution text the API returns and links to https://coworkingview.com with the label "Data: CoworkingView". It does not show operator listings, photos, or logos.

On each refresh the site sends the chosen city slug and the language (English, German, or Spanish) to https://api.coworkingview.com as GET /v1/market/rates. There is no API key. No visitor account is sent. A successful response is cached on the server for the number of minutes set in the module (10 to 1440, default 60). Failed requests are not cached.

Parameters: city (default berlin), product type (all products, or one product), language, items (1 to 12, default 6), and cache time. Set Joomla's own module cache to No caching so a change of product or item count is visible immediately. The module keeps its own cache of the API response.

The extension is free software under the GNU General Public License version 2 or later. There is no commercial key and no extra restriction. The Price Index data remains CC BY 4.0.

CoworkingView is not affiliated with or endorsed by Open Source Matters or the Joomla project.

Homepage: https://coworkingview.com
Documentation: https://github.com/coworkingview/flex-office-data/blob/main/integrations/joomla/README.md
Support: https://github.com/coworkingview/flex-office-data/issues

## Tags

coworking, workspace, prices, flexible-office, city, price-index

## Category

**Directory & Documentation → Directory.**

The module is a small directory of published price-index rows for one city. That is the closest current JED category.

Maps & Weather is a weaker fit. That category is for map, geotag, and weather widgets. This module has no map and no weather. Use it only if Directory is unavailable for a new listing.

## Links

| Field | Value |
|---|---|
| Project / homepage | https://coworkingview.com |
| Documentation | https://github.com/coworkingview/flex-office-data/blob/main/integrations/joomla/README.md |
| Download | https://github.com/coworkingview/flex-office-data/releases/download/joomla-v1.0.0/mod_coworkingview-1.0.0.zip |
| Support | https://github.com/coworkingview/flex-office-data/issues |
| Licence | GNU General Public License version 2 or later (GPLv2+) |

The download file is the asset on the `joomla-v1.0.0` release. The update server in the manifest is the raw file `integrations/joomla/updates/mod_coworkingview.xml` on `main`, and it points at the same download URL.

## Screenshots

Both files are 1280 pixels wide. They were produced by rendering `tmpl/default.php` through PHP's built-in server (`tools/preview.php`) with a live response from `GET /v1/market/rates`, then capturing the page in headless Chrome at 1280×800. They are not a photograph of a Joomla administrator screen, and the page chrome is an example article so the listing does not use the Joomla logo. Say that in the caption if the form has a caption field.

| File | Size target | What it shows |
|---|---|---|
| `screenshots/module-en-berlin.png` | 1280×800 | English module, Berlin, all products, up to six rows, attribution link visible. |
| `screenshots/module-de-berlin.png` | 1280×800 | German module, Berlin, private office only, attribution link visible. |

Regenerate with `./tools/capture.sh` from `integrations/joomla`. The script exits if the page is the error state or if the attribution link is missing.

## Licence field

GPLv2+. The package contains `LICENSE.txt` (GNU General Public License version 2). The manifest carries both `<license>` and `<licence>` with the version 2 or later notice. There is no paid edition.
