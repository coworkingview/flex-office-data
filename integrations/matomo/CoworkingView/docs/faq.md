# FAQ

## Does the widget track visitors?

No. It does not register a tracker and it does not send visitor data anywhere.

## What is sent to CoworkingView?

Only the chosen city. The Matomo server calls `GET /v1/market/rates?city=<city>&locale=en` and `GET /v1/properties?city=<city>&locale=en&pageSize=1` on `https://api.coworkingview.com`. `locale=en` is fixed because the API requires it. `pageSize=1` is sent so the widget can read `meta.pagination.total` without a page of listings. No API key is sent. No visitor data is sent.

## Where do I set the city?

A superuser sets the default under **Administration → System → General settings**. The default is `berlin`. Each user can set another city under **Personal → Settings**. Leave the personal value empty to use the system city.

## What do the numbers mean?

Market-rate rows come from `figures` on the city (or `byType` when `figures` is empty): median, 25th percentile, 75th percentile and sample size, when those fields are present. `dayPass` and `meetingRoom` are separate objects on the same city and are shown too.

The workspace count is `meta.pagination.total`. It is a different number from `propertyCount` on the rates payload.

Monthly rows come from `figures` and `byType`. Day pass is per day. Meeting room is per hour. The API does not send a unit field; this is the same rule as the other CoworkingView clients.

## What if loading fails?

The widget stays on the dashboard and says the data could not be loaded. A failed request is not cached. The next time the widget renders, it tries again.

## Where does the link go?

**Data by CoworkingView** links to [https://coworkingview.com](https://coworkingview.com).
