# CoworkingView

The **Flexible office prices (CoworkingView)** widget shows Price Index medians for one city on a Matomo dashboard, plus the number of workspaces listed for that city.

## Installation

1. Copy the `CoworkingView` folder to your Matomo `plugins/` directory.
2. Activate the plugin in **Administration > Plugins**.
3. Add the widget from **Dashboard > Add a widget > CoworkingView > Flexible office prices (CoworkingView)**.

The Matomo server must reach `https://api.coworkingview.com` over HTTPS.

## Configuration

Settings are the city slug, for example `berlin` or `madrid`.

| Setting | Who edits it | Default |
|---|---|---|
| City | Superuser, **Administration > System > General settings**, section CoworkingView | `berlin` |
| City | Each user, **Personal > Settings**, section CoworkingView | Empty, which means "use the system city" |

The setting text states that this city is sent to `api.coworkingview.com`. No other Matomo value is sent.

## What the widget shows

Rows come from `GET /v1/market/rates?city=<city>&locale=en`:

- Each item in `figures` (or `byType` when `figures` is empty): product, median, 25th percentile, 75th percentile, and sample size, when those fields exist.
- `dayPass` and `meetingRoom` when the city object includes them.

The workspace count is `meta.pagination.total` from `GET /v1/properties?city=<city>&locale=en&pageSize=1`. It is not the length of `data`, and it is not `propertyCount` on the rates payload.

The API does not send a unit. Rows from `figures` and `byType` are monthly. Day pass is per day. Meeting room is per hour. A statistic with no documented unit is left blank.

`asOf` and `attribution` are shown when the rates response includes them. **Data by CoworkingView** links to [https://coworkingview.com](https://coworkingview.com).

## Caching

A successful response is stored in Matomo's lazy cache for about 12 hours (43200 seconds). The cache key includes the plugin version and the city. Failures are not cached.

## Data source

Figures are the public CoworkingView Price Index. The plugin does not store workspace names, photos, descriptions, or individual prices.
