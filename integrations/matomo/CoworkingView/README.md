# CoworkingView

Dashboard widget for Matomo 5 that shows flexible office price medians for one city from the [CoworkingView](https://coworkingview.com) Price Index.

## Description

**Flexible office prices (CoworkingView)** is a dashboard widget. It shows a small table of market rates for the chosen city and how many workspaces are listed there.

The widget loads external data from `https://api.coworkingview.com`. The Matomo server calls that public API. No API key is required. The only value taken from Matomo settings is the chosen city. Each request also sends a fixed `locale=en`, because the API rejects a call that omits the locale, and the workspace request sends `pageSize=1` so the widget can read the catalogue total. No visitor data is sent: no visitor id, no user id, no page URL, and no analytics payload. The browser does not call the API.

A successful response is cached on the Matomo server for about 12 hours. A failed request is not cached, so the next view tries again.

## Installation

The Matomo server must be able to reach `https://api.coworkingview.com` over HTTPS.

### Marketplace

When the plugin is listed on the Matomo Marketplace, install **CoworkingView** from **Administration → Platform → Marketplace**. Activate it if Matomo did not do that automatically.

### Manual

Copy this directory to `plugins/CoworkingView` inside a Matomo 5 installation. The directory name must stay `CoworkingView`, matching `plugin.json`.

From a checkout of the flex-office-data repository:

```console
cp -a integrations/matomo/CoworkingView /path/to/matomo/plugins/CoworkingView
```

Activate it under **Administration → Plugins**, or from the Matomo console:

```console
./console plugin:activate CoworkingView
```

Open a dashboard and choose **Add a widget**. Add **Flexible office prices (CoworkingView)** from the **CoworkingView** category.

This folder is self-contained. Published on its own, `plugin.json` sits at the repository root, which is what the Marketplace expects.

### City

A superuser sets the default city under **Administration → System → General settings**. The default is `berlin`. Each user can override it under **Personal → Settings**. Leave the personal value empty to keep the system city. Enter the city slug, for example `berlin` or `madrid`.

## FAQ

### Does the widget track visitors?

No. It does not register a tracker and it does not send visitor data anywhere.

### What is sent to CoworkingView?

Only the chosen city. The Matomo server calls:

- `GET /v1/market/rates?city=<city>&locale=en`
- `GET /v1/properties?city=<city>&locale=en&pageSize=1`

`locale=en` is fixed. The API returns validation error 400 when locale is omitted. `pageSize=1` limits the workspace response to the count in `meta.pagination.total`. No API key is sent.

### Which fields are shown?

The rates table uses `data.cities[]` for the requested city:

- One row for each item in `figures`. When `figures` is missing or empty, the rows come from `byType` instead. Columns are `optionType`, `median.amount` with `median.currency`, `p25` and `p75` when those objects exist, and `sampleSize`.
- One extra row for every other city field whose value is an object with both `median` and `sampleSize`. On the current API those fields are `dayPass` and `meetingRoom`.

The workspace line is `meta.pagination.total` from the properties response. It is not the length of `data` (that is one page) and it is not `propertyCount` on the rates payload (that is how many spaces are in the price index).

The API does not send a unit. Rows from `figures` and `byType` are monthly. `dayPass` is per day, `meetingRoom` and `eventSpace` are per hour, and `virtualOffice` is per month. That is the same rule the other CoworkingView clients use. A statistic with no documented unit is left blank.

`asOf` and `attribution` are shown when the rates response includes them. **Data by CoworkingView** always links to [https://coworkingview.com](https://coworkingview.com).

Names, photos, descriptions and prices of individual workspaces are not shown and are not stored.

### What if the city has no published prices?

The widget says that no price index is published for that city. If the catalogue total is present it is still shown, including zero.

### Why do I see an error instead of the table?

The API could not be reached, or it returned an error or a response the widget did not recognise. The widget stays on the dashboard and says the data could not be loaded. When the API sent a problem title or detail, that text is included. Failures are not cached.

### Which Matomo versions are supported?

Matomo 5.x, from `5.0.0-b1` up to but not including `6.0.0-b1`.

## Licence

Code is GPL-3.0 or later. See [LICENSE](LICENSE).

Price Index figures are CC BY 4.0. The widget keeps the `attribution` string from the API and links to [CoworkingView](https://coworkingview.com).
