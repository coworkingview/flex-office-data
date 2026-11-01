# CoworkingView

Flexible office price medians for one city. Loads api.coworkingview.com; no visitor data is sent.

## Description

**Flexible office prices (CoworkingView)** is a dashboard widget. It shows median flexible office prices for one city, the 25th and 75th percentiles, the sample size, and how many workspaces are listed there.

The widget loads external data from `https://api.coworkingview.com`. The Matomo server calls that public API when someone views a dashboard that contains the widget. No API key is required. The only value taken from Matomo settings is the city a superuser or the current user chose. Each request also sends a fixed `locale=en`, because the API rejects a call that omits the locale, and `pageSize=1` on the workspace request, so the widget can read the catalogue total. No visitor data is sent: no visitor id, no user id, no page URL, and no analytics payload. The browser does not call the API. The plugin loads no external script and no external image.

A successful response is cached on the Matomo server for about 12 hours. A failed request is not cached, so the next view tries again.

### Features

- One dashboard widget, **Flexible office prices (CoworkingView)**
- A system default city and a personal override. The default is `berlin`
- Median, 25th percentile, 75th percentile, sample size, and a workspace count
- Server-side cache of about 12 hours, and an error state when the API cannot be reached
- English translations. No tracking code

### How it works

Activate the plugin, then add the widget from **Dashboard > Add a widget > CoworkingView**. A superuser sets the default city in **Administration > System > General settings**. Each user can set another city in **Personal > Settings**. Leave the personal value empty to keep the system city.

### What is sent

| Request | Query |
|---|---|
| `GET https://api.coworkingview.com/v1/market/rates` | `city` (the chosen slug) and `locale=en` |
| `GET https://api.coworkingview.com/v1/properties` | `city`, `locale=en`, and `pageSize=1` |

Nothing else is sent. **Data by CoworkingView** links to [https://coworkingview.com](https://coworkingview.com).

## Requirements

- Matomo `>=5.0.0-b1` and `<6.0.0-b1`
- PHP `>=8.1`

## Installation

The Matomo server must be able to reach `https://api.coworkingview.com` over HTTPS.

### From the Matomo Marketplace

When the plugin is listed, install **CoworkingView** from **Administration > Marketplace**. Activate it if Matomo did not do that automatically.

### Manual installation

Copy this directory to `plugins/CoworkingView` inside Matomo. The directory name must stay `CoworkingView`, matching `plugin.json`.

From a checkout of the flex-office-data repository:

```console
cp -a integrations/matomo/CoworkingView /path/to/matomo/plugins/CoworkingView
```

Activate it under **Administration > Plugins**, or from the Matomo console:

```console
./console plugin:activate CoworkingView
```

This folder is self-contained. The Marketplace reads `plugin.json` from the root of the plugin repository, so publish a copy of this folder as its own repository rather than the flex-office-data monorepo.

## FAQ

### Does this plugin send data to external services?

Yes, and only the city you chose. The Matomo server calls `https://api.coworkingview.com`. See [What is sent](#what-is-sent). No visitor data is sent.

### Where do I set the city?

**Administration > System > General settings**, section CoworkingView, for the default. **Personal > Settings** for your own dashboards. The default is `berlin`.

### What happens if the API is down?

The widget stays on the dashboard and says the data could not be loaded. Failures are not cached. The next time the widget renders, it tries again.

### Which Matomo versions are supported?

Matomo 5.x, from `5.0.0-b1` up to but not including `6.0.0-b1`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

GPL-3.0 or later. See [LICENSE](LICENSE).

Price Index figures are CC BY 4.0. The widget keeps the `attribution` string returned by the API and links to [CoworkingView](https://coworkingview.com).
