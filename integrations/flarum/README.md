# CoworkingView Coworking Prices

Flarum 1.8 extension that shows [CoworkingView](https://coworkingview.com) Price Index figures for one city. A sidebar card on the discussion list and on discussions, and a `[coworking]` BBCode in posts.

No account and no API key. The extension is MIT. The Price Index figures are [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

This extension was built with AI assistance. CoworkingView maintains it.

## Install

```bash
composer require coworkingview/flarum-coworkingview
php flarum cache:clear
```

Enable **CoworkingView Coworking Prices** in the admin. The formatter cache is cleared when the extension is enabled. After an update, run `php flarum cache:clear` again.

Requires Flarum `^1.8` and PHP 8.1 or newer.

## Posts

```
[coworking city=berlin]
[coworking city=berlin product=flex_desk]
[coworking city=madrid locale=es]
```

`city` is the Price Index slug (`berlin`, `abu-dhabi`). `product` is optional: `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, or `membership`. Leave it out to show every product the city publishes. `locale` is optional: `en`, `de`, or `es`. When it is omitted, the admin setting is used.

Each product shows the median, the currency, the unit, the p25–p75 spread when both percentiles were published, and the sample size. A percentile the index does not publish is left blank. A sample under 10 is marked low confidence. The card does not invent a price.

The card prints the `attribution` string from the API and links [CoworkingView](https://coworkingview.com) and the [CC BY 4.0 licence](https://creativecommons.org/licenses/by/4.0/). The city name links to the [Price Index](https://coworkingview.com/en/tools/price-index).

Figures are read when the post is displayed, not when it is saved. The composer preview asks the forum API for the same reading.

## Sidebar

The card also sits in the discussion-list sidebar and the discussion sidebar. Admins choose the city, the language, one product or all products, and whether the card is shown. Defaults are `berlin`, `en`, all products, and shown.

## What is sent

Each uncached reading is one HTTPS GET:

`https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin`

`locale` is required. Without it the API returns HTTP 400. The query sends the city slug and the locale only. No API key, no post text, and no account data.

The user agent is `flarum-coworkingview/0.1.0 (+https://github.com/coworkingview/flarum-coworkingview)`. Timeout is 20 seconds. A 429 or 5xx response is retried once. A successful reading, an unknown city, and an unpublished city are cached for 10 minutes. A failed request is not cached.

Set `COWORKINGVIEW_API_URL` only to point the extension at a different origin (scheme, host, and port). The path stays `/v1/market/rates`. The default origin is `https://api.coworkingview.com`.

## Data licence

The extension is [MIT](LICENSE). Price Index figures are not covered by that licence. They are CC BY 4.0. The card keeps the attribution string the API returns.

Homepage: [https://coworkingview.com](https://coworkingview.com).

## Checks

From this directory, with no Flarum install and no network:

```bash
composer validate --strict --no-check-publish
find . -name '*.php' -not -path './vendor/*' -print0 | xargs -0 -n1 php -l
php tests/run.php
cd js && npm ci && npm run build
```

The tests use a synthetic payload. They do not call the live API.
