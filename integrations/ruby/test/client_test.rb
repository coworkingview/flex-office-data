# frozen_string_literal: true

require "open3"
require "test_helper"

class ClientTest < Minitest::Test
  RATE_COLUMNS = CoworkingView::Client::RATE_COLUMNS
  CITY_COLUMNS = CoworkingView::Client::CITY_COLUMNS
  SPACE_COLUMNS = %i[
    slug title city_slug zone_slug operator_slug operator_name country_code
    lat lng featured market_verdict market_median market_sample_size url updated_at
  ].freeze
  PRICING_COLUMNS = %i[
    product title price currency billing_period price_on_request min_capacity max_capacity
  ].freeze

  def test_require_does_not_touch_the_network
    lib = File.expand_path("../lib", __dir__)
    _stdout, stderr, status = Open3.capture3(
      { "COWORKINGVIEW_API_URL" => nil },
      RbConfig.ruby,
      "-I",
      lib,
      "-e",
      <<~RUBY
        require "webmock"
        WebMock.disable_net_connect!
        require "coworkingview"
        client = CoworkingView::Client.new
        raise client.base_url unless client.base_url == "https://api.coworkingview.com"
        raise CoworkingView::VERSION unless CoworkingView::VERSION == "0.1.0"
      RUBY
    )
    assert status.success?, stderr
  end

  def test_user_agent_accept_and_rates_query
    stub_api("/v1/market/rates", fixture("market_rates.json"))
    result = client.rates(city: " berlin ", currency: "eur")

    assert_requested :get, "https://api.coworkingview.com/v1/market/rates",
                     query: { "locale" => "en", "city" => "berlin", "currency" => "EUR" },
                     headers: {
                       "Accept" => "application/json",
                       "User-Agent" => "coworkingview-ruby/0.1.0 (+https://github.com/coworkingview/flex-office-data)"
                     }
    assert_equal "https://creativecommons.org/licenses/by/4.0/", result.license
    assert_equal "2026-10-27T21:06:48.313Z", result.as_of
    assert_match(/CoworkingView Price Index/, result.attribution)
  end

  def test_custom_user_agent_and_base_url
    stub_request(:get, "http://127.0.0.1:4010/v1/market/rates?locale=en")
      .to_return(status: 200, body: empty_rates, headers: json_headers)
    built = client(base_url: "http://127.0.0.1:4010/", user_agent: "research/1.0", timeout: 5)
    built.rates

    assert_equal "http://127.0.0.1:4010", built.base_url
    assert_equal 5.0, built.timeout
    assert_requested :get, "http://127.0.0.1:4010/v1/market/rates",
                     query: { "locale" => "en" },
                     headers: { "User-Agent" => "research/1.0" }
  end

  def test_environment_base_url
    ENV["COWORKINGVIEW_API_URL"] = "https://mirror.example/"
    assert_equal "https://mirror.example", client.base_url
  end

  def test_rejects_unsafe_base_url_without_a_request
    assert_raises(ArgumentError) { client(base_url: "ftp://api.coworkingview.com") }
    assert_raises(ArgumentError) { client(base_url: "https://user:secret@api.coworkingview.com") }
    assert_raises(ArgumentError) { client(base_url: "https://api.coworkingview.com/v1") }
    assert_no_requests
  end

  def test_rates_match_the_golden_file
    stub_api("/v1/market/rates", fixture("market_rates.json"))
    result = client.rates

    assert_golden result.data, "rates.csv", RATE_COLUMNS
    assert_equal RATE_COLUMNS, result.data.first.keys
  end

  def test_cities_match_the_golden_file
    stub_api("/v1/market/rates", fixture("market_rates.json"))
    result = client.cities(locale: "de")

    assert_golden result.data, "cities.csv", CITY_COLUMNS
    assert_equal false, result.data.last[:published]
    assert_requested :get, "https://api.coworkingview.com/v1/market/rates",
                     query: { "locale" => "de" }
  end

  def test_unknown_price_aggregate_is_kept
    body = {
      "data" => {
        "cities" => [
          {
            "city" => { "slug" => "berlin", "name" => "Berlin" },
            "countryCode" => "DE",
            "currency" => "EUR",
            "figures" => [],
            "eventSpace" => {
              "median" => { "amount" => 12, "currency" => "EUR" },
              "sampleSize" => 4
            }
          }
        ],
        "asOf" => "2026-01-01T00:00:00Z",
        "attribution" => "Attr",
        "licenseUrl" => "https://creativecommons.org/licenses/by/4.0/"
      }
    }.to_json
    stub_api("/v1/market/rates", body)
    row = client.rates.data.fetch(0)

    assert_equal "event_space", row[:product]
    assert_equal "hour", row[:unit]
    assert_equal 12, row[:median]
    assert_equal true, row[:low_confidence]
  end

  def test_spaces_match_the_golden_file_and_omit_operator_content
    stub_api("/v1/properties", fixture("properties_berlin.json"))
    result = client.spaces(city: "berlin", product: "private_office", limit: 3)

    assert_golden result.data, "spaces.csv", SPACE_COLUMNS
    assert_equal SPACE_COLUMNS, result.data.first.keys
    assert_match(/Catalogue content/, result.notice)
    assert_match(/Coworking spaces in Berlin/, result.attribution)
    assert_equal 110, result.total
    assert_equal "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin", result.data.first[:url]
    assert_requested :get, "https://api.coworkingview.com/v1/properties",
                     query: hash_including(
                       "locale" => "en",
                       "city" => "berlin",
                       "pricingOptionType" => "private_office",
                       "sortBy" => "random",
                       "page" => "1",
                       "pageSize" => "3"
                     ),
                     times: 1
  end

  def test_spaces_follow_pages_and_forward_the_random_seed
    seen = []
    stub_request(:get, %r{\Ahttps://api\.coworkingview\.com/v1/properties\?}).to_return do |request|
      query = URI.decode_www_form(URI(request.uri).query).to_h
      seen << query
      page = query.fetch("page")
      card = { "slug" => "space-#{page}", "title" => "Space #{page}", "countryCode" => "DE" }
      body = {
        "data" => [card],
        "meta" => {
          "pagination" => { "page" => page.to_i, "pageSize" => 2, "total" => 2, "pageCount" => 2 },
          "seed" => 99,
          "citation" => { "text" => "cite" },
          "catalogueNotice" => "notice"
        }
      }
      { status: 200, body: body.to_json, headers: json_headers }
    end

    result = client.spaces(city: "berlin", limit: 2)

    assert_equal %w[space-1 space-2], result.data.map { |row| row[:slug] }
    assert_equal "cite", result.attribution
    assert_equal "notice", result.notice
    assert_nil seen[0]["seed"]
    assert_equal "99", seen[1]["seed"]
    assert_equal "2", seen[1]["page"]
  end

  def test_spaces_trim_to_limit_without_another_page
    body = {
      "data" => [
        { "slug" => "a", "title" => "A" },
        { "slug" => "b", "title" => "B" },
        { "slug" => "c", "title" => "C" }
      ],
      "meta" => { "pagination" => { "page" => 1, "pageSize" => 2, "total" => 3, "pageCount" => 1 } }
    }.to_json
    stub_api("/v1/properties", body)
    result = client.spaces(limit: 2, locale: "es")

    assert_equal %w[a b], result.data.map { |row| row[:slug] }
    assert_equal "https://coworkingview.com/es/oficina/a", result.data.first[:url]
    assert_requested :get, /\/v1\/properties/, times: 1
  end

  def test_space_matches_the_golden_pricing_table
    payload = JSON.parse(fixture("property_detail.json"))
    stub_api("/v1/properties/sankt-oberholz-rosenthaler-berlin", fixture("property_detail.json"))
    space = client.space("sankt-oberholz-rosenthaler-berlin")

    assert_golden space.pricing, "space_pricing.csv", PRICING_COLUMNS
    assert_equal payload.dig("data", "address"), space.address
    assert_nil space.capacity
    assert_includes space.amenities, "wifi"
    assert_equal payload.dig("data", "webUrl"), space.url
    assert_equal payload.dig("meta", "citation", "text"), space.attribution
    assert_equal payload.dig("meta", "catalogueNotice"), space.notice
    refute_includes space.to_h.keys, :description
    assert_requested :get,
                     "https://api.coworkingview.com/v1/properties/sankt-oberholz-rosenthaler-berlin",
                     query: { "locale" => "en" }
  end

  def test_invalid_arguments_do_not_send_a_request
    assert_raises(ArgumentError) { client.space("../etc/passwd") }
    assert_raises(ArgumentError) { client.space("") }
    assert_raises(ArgumentError) { client.rates(locale: "fr") }
    assert_raises(ArgumentError) { client.spaces(limit: 201) }
    assert_raises(ArgumentError) { client.spaces(limit: 0) }
    assert_raises(ArgumentError) { client.spaces(min_price: 40, max_price: 10) }
    assert_raises(ArgumentError) { client.spaces(product: "desk") }
    assert_raises(ArgumentError) { client.spaces(sort: "distance") }
    assert_no_requests
  end

  def test_problem_json_is_not_retried
    stub_api("/v1/market/rates", fixture("error_validation.json"), status: 400)
    error = assert_raises(CoworkingView::APIError) { client.rates(city: "berlin", currency: "VES") }

    assert_equal 400, error.status
    assert_equal "VALIDATION_FAILED", error.code
    assert_equal "Validation failed", error.title
    assert_match(/VES/, error.detail)
    assert_equal "currency", error.errors.first["path"]
    assert_requested :get, /\/v1\/market\/rates/,
                     query: hash_including("currency" => "VES"),
                     times: 1
  end

  def test_non_json_success_and_error_bodies
    stub_api("/v1/market/rates", "not-json")
    success = assert_raises(CoworkingView::APIError) { client.rates }
    assert_equal 200, success.status
    assert_equal "BAD_RESPONSE", success.code

    WebMock.reset!
    stub_api("/v1/market/rates", "missing", status: 404)
    missing = assert_raises(CoworkingView::APIError) { client.rates }
    assert_equal 404, missing.status
    assert_equal "HTTP_404", missing.code
    assert_equal "HTTP 404", missing.title
  end

  def test_retries_once_using_retry_after_then_succeeds
    sleeps = []
    stub_request(:get, %r{/v1/market/rates}).to_return(
      { status: 429, body: "{}", headers: json_headers("Retry-After" => "3") },
      { status: 200, body: empty_rates, headers: json_headers }
    )
    result = client(sleeper: ->(seconds) { sleeps << seconds }).rates

    assert_equal [], result.data
    assert_equal [3.0], sleeps
    assert_requested :get, /\/v1\/market\/rates/, times: 2
  end

  def test_retries_only_once
    sleeps = []
    stub_request(:get, %r{/v1/market/rates}).to_return(
      { status: 503, body: { "title" => "Down", "code" => "UNAVAILABLE" }.to_json, headers: json_headers },
      { status: 503, body: { "title" => "Still down", "code" => "UNAVAILABLE" }.to_json, headers: json_headers },
      { status: 200, body: empty_rates, headers: json_headers }
    )
    error = assert_raises(CoworkingView::APIError) do
      client(sleeper: ->(seconds) { sleeps << seconds }).rates
    end

    assert_equal 503, error.status
    assert_equal "Still down", error.title
    assert_equal [2.0], sleeps
    assert_requested :get, /\/v1\/market\/rates/, times: 2
  end

  def test_retry_wait_caps_and_reads_rate_limit_reset
    assert_equal 10.0, CoworkingView::Client.retry_wait({ "Retry-After" => "120", "RateLimit-Reset" => "5" })
    assert_equal 4.0, CoworkingView::Client.retry_wait({ "RateLimit-Reset" => "4" })
    assert_equal 4.0, CoworkingView::Client.retry_wait({ "Retry-After" => "soon", "RateLimit-Reset" => "4" })
    assert_equal 2.0, CoworkingView::Client.retry_wait({})

    now = Time.utc(2026, 11, 3, 12, 0, 0)
    header = (now + 6).httpdate
    assert_in_delta 6.0, CoworkingView::Client.retry_wait({ "Retry-After" => header }, now: now), 0.01
  end

  def test_connection_and_timeout_errors
    stub_request(:get, %r{/v1/market/rates}).to_raise(SocketError.new("name lookup failed"))
    connection = assert_raises(CoworkingView::Error) { client.rates }
    assert_equal 0, connection.status
    assert_equal "CONNECTION", connection.code
    refute_kind_of CoworkingView::APIError, connection

    WebMock.reset!
    stub_request(:get, %r{/v1/market/rates}).to_timeout
    timeout = assert_raises(CoworkingView::Error) { client.rates }
    assert_equal "TIMEOUT", timeout.code
    assert_equal 0, timeout.status
  end

  def test_german_listing_path
    body = {
      "data" => [{ "slug" => "example-space", "title" => "Beispiel" }],
      "meta" => { "pagination" => { "page" => 1, "pageSize" => 1, "total" => 1, "pageCount" => 1 } }
    }.to_json
    stub_api("/v1/properties", body)
    row = client.spaces(limit: 1, locale: "de").data.fetch(0)

    assert_equal "https://coworkingview.com/de/buero/example-space", row[:url]
  end

  def empty_rates
    {
      "data" => {
        "cities" => [],
        "unpublished" => [],
        "asOf" => "2026-10-27T21:06:48.313Z",
        "attribution" => "Attr",
        "licenseUrl" => "https://creativecommons.org/licenses/by/4.0/"
      },
      "meta" => {}
    }.to_json
  end
end
