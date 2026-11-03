# coworkingview

Ruby client for the public API of [CoworkingView](https://coworkingview.com).

It reads:

- **The CoworkingView Price Index** (`GET /v1/market/rates`): median, 25th and 75th percentile by city and product, with the sample size next to every figure. Open data under **CC BY 4.0**. The attribution string comes back on every result and has to travel with the figures.
- **Catalogue search** (`GET /v1/properties`) and **one space** (`GET /v1/properties/{slug}`): coworking spaces and other flexible offices, filtered by city, neighbourhood, operator, product, capacity and price.

No API key. Nothing is downloaded when the library is loaded. The client uses `net/http` and `json` from the standard library and has no runtime dependencies.

The same three endpoints, columns and HTTP behaviour are implemented by the Python, R, Java and Rust packages in this repository. Numbers are checked against the shared fixtures in `spec/`.

Maintained by [CoworkingView](https://coworkingview.com).

## Install

Ruby 3.0 or newer. This gem is not published to rubygems.org. Build it from this directory:

```bash
cd integrations/ruby
gem build coworkingview.gemspec
gem install ./coworkingview-0.1.0.gem
```

Or point Bundler at a checkout:

```ruby
gem "coworkingview", git: "https://github.com/coworkingview/flex-office-data", glob: "integrations/ruby/*.gemspec"
```

## Usage

```ruby
require "coworkingview"

client = CoworkingView::Client.new

berlin = client.rates(city: "berlin")
berlin.data.each do |row|
  puts "#{row[:product]} #{row[:unit]} median #{row[:median]} #{row[:currency]} n=#{row[:sample_size]}"
end
# Print this next to any figure you republish. The index is CC BY 4.0.
puts berlin.attribution

rooms = client.spaces(city: "madrid", product: "meeting_room", limit: 20)
rooms.data.each { |row| puts "#{row[:title]} #{row[:url]}" }

space = client.space("sankt-oberholz-rosenthaler-berlin")
space.pricing.each do |offer|
  # price is nil when the operator quotes on request. It is not zero.
  price = offer[:price_on_request] ? "on request" : "#{offer[:price]} #{offer[:currency]}"
  puts "#{offer[:product]} #{price}"
end
```

`CoworkingView::Client.new` talks to `https://api.coworkingview.com`. Pass `base_url:` to point at another origin, or set `COWORKINGVIEW_API_URL`. A trailing slash is removed. The default user agent is `coworkingview-ruby/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.

```ruby
client = CoworkingView::Client.new(
  timeout: 5,
  user_agent: "my-research-project/1.0 (me@example.org)"
)
```

`locale` defaults to `"en"` and is always sent. The API requires one of `en`, `de` or `es`.

### Price Index

```ruby
client.rates(city: "berlin", currency: "EUR")
client.cities(country: "germany")
```

`rates` returns one row per published city and product. `cities` is the same request, one row per city, published cities first. Both carry `attribution`, `license` (the response's `licenseUrl`) and `as_of`.

| Argument | Values |
|---|---|
| `locale` | `en` (default), `es`, `de` |
| `currency` | `EUR`, `GBP`, `USD`, `CHF`, `AED`, `VES` (any case). `VES` is sent through; the API answers 400 where it cannot convert |
| `city` | City slug, for example `berlin` |
| `country` | Country slug, for example `germany` |

A product the API adds later shows up in `rates` without a library update. Products this version does not name a unit for come back with `unit: nil`. `low_confidence` is true when `sample_size` is below 10.

### Catalogue

```ruby
client.spaces(
  city: "berlin",
  zone: "mitte",
  operator: "regus",
  product: "flex_desk",
  min_capacity: 1,
  min_price: 0,
  max_price: 400,
  currency: "EUR",
  sort: "price-asc",
  limit: 50
)
```

`spaces` calls `GET /v1/properties` and follows pages until `limit` rows (default 50, maximum 200). Each request asks for at most 50 rows. `product` is sent as `pricingOptionType`. `sort` is sent as `sortBy`: `random` (default), `price-asc`, `date-desc` or `date-asc`. When the first page of a random sort returns `meta.seed`, later pages send it back. Pass `seed:` to supply one yourself.

`space` calls `GET /v1/properties/{slug}`. The slug is checked against `^[A-Za-z0-9][A-Za-z0-9._-]*$` before it is placed in the path.

`Dataset#attribution` on a search is `meta.citation.text`. `Dataset#notice` is `meta.catalogueNotice`. `Dataset#total` is `pagination.total` from the first page. A space uses `webUrl` when the API sends one, otherwise `https://coworkingview.com/{locale}/{workspace|oficina|buero}/{slug}`.

Descriptions, photos and logos are not returned. Link to `url` instead of copying the catalogue.

### Errors

`CoworkingView::APIError` is raised for a non-2xx response and for a body that is not a JSON object. `status` is the HTTP status. `code`, `title`, `detail` and `errors` come from the problem document. When the body has no `code`, `code` is `HTTP_<status>`. A non-JSON success body uses `BAD_RESPONSE`.

On HTTP 429 or 5xx the client waits `Retry-After` seconds (else `RateLimit-Reset`, else 2 seconds, never more than 10) and retries once. The per-request timeout is 20 seconds. DNS failures, refused connections and timeouts raise `CoworkingView::Error` with `status` 0 and `code` `CONNECTION` or `TIMEOUT`.

Wrong arguments raise `ArgumentError` and do not send a request.

## Tests

```bash
bundle install
bundle exec rake test
gem build coworkingview.gemspec
```

HTTP is stubbed with webmock. The tests replay `spec/fixtures/` and compare rows with `spec/golden/`.

## Licence and attribution

- **Code:** MIT, see [LICENSE](LICENSE).
- **Price Index data:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit *CoworkingView Price Index* with a link to <https://coworkingview.com/en/tools/price-index>. Use the `attribution` field on the result.
- **Catalogue:** names, prices and links are for search and reference. Descriptions, photos and logos belong to the operators and are not included. A search that follows pages stops at 200 listings.

Changes are in [CHANGELOG.md](CHANGELOG.md). Issues: <https://github.com/coworkingview/flex-office-data/issues>.
