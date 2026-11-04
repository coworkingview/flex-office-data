# Changelog

## 0.1.0

First release of the Redmine plugin CoworkingView Prices.

- Wiki macros `coworking_rate` and `coworking_rates` for one product, or every product in a city.
- Median, p25–p75, currency, unit and sample size, with the CC BY 4.0 attribution link.
- Successful responses are stored in `Rails.cache` (default 24 hours). Plugin settings: network on/off, cache TTL hours, locale.
- Bundled `data/rates_snapshot.csv` when the network is off or the rates request fails. A failure is not cached.
- No database migration and no core patches. Redmine 5.0 through 7.x. Ruby 3.0 or newer.
