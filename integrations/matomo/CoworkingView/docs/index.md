# CoworkingView

The **Flexible office prices (CoworkingView)** widget shows Price Index medians for one city on a Matomo dashboard, plus the number of workspaces listed for that city.

Data is loaded by the Matomo server from [https://api.coworkingview.com](https://api.coworkingview.com). The only chosen value is the city. No visitor data is sent. See the [README](../README.md) for installation, the request URLs, and how each column is mapped.

The default city is `berlin`. Change it under **Administration → System → General settings**, or override it for yourself under **Personal → Settings**.

Successful responses are cached for about 12 hours. Errors are not cached.
