# FAQ

## Does this plugin send data to external services?

Yes. The Matomo server calls `https://api.coworkingview.com` when a dashboard containing the widget is viewed.

The requests are:

- `GET /v1/market/rates?city=<city>&locale=en`
- `GET /v1/properties?city=<city>&locale=en&pageSize=1`

`city` is the slug from the system setting or, when a user has set one, from the personal setting. `locale=en` is fixed because the API returns HTTP 400 without it. `pageSize=1` is sent so the workspace response is only the count in `meta.pagination.total`.

No API key is sent. No visitor id, user id, page URL, or analytics payload is sent. The browser does not call the API. The plugin does not load an external script or image.

## Where do I set the city?

A superuser sets the default under **Administration > System > General settings**, section CoworkingView. The default is `berlin`.

Each user can set another city under **Personal > Settings**. Leave that value empty to use the system city.

## How often is the data refreshed?

A successful response is cached for about 12 hours. The next dashboard view after that fetches again. A failed request is not cached.

## What happens if the API is down?

The widget stays on the dashboard and says the prices or the workspace count could not be loaded. If the API returned a problem title or detail, that text is included. The next view tries again.

## What do the columns mean?

The product name is `optionType` (or `dayPass` / `meetingRoom`). Median, 25th percentile, and 75th percentile are the `amount` and `currency` on those objects. Sample size is `sampleSize`. A dash means that field was not in the response.

The workspace line is `meta.pagination.total`. It is a different number from `propertyCount` on the rates payload.

## Which Matomo versions are supported?

Matomo 5.x, from `5.0.0-b1` up to but not including `6.0.0-b1`, on PHP 8.1 or newer.

## Where does the link go?

**Data by CoworkingView** links to [https://coworkingview.com](https://coworkingview.com).
