# frozen_string_literal: true

require "test_helper"

class ClientTest < Minitest::Test
  include CoworkingviewTest

  def test_new_does_not_touch_the_transport
    calls = 0
    RedmineCoworkingview::Client.new(http: lambda { |_uri|
      calls += 1
      [200, fixture_body, {}]
    })
    assert_equal 0, calls
  end

  def test_rates_sends_locale_and_parses_the_body
    uris = []
    client = RedmineCoworkingview::Client.new(http: lambda { |uri|
      uris << uri.to_s
      [200, fixture_body, {}]
    })
    dataset = client.rates(locale: "en")

    assert_equal 1, uris.length
    assert_includes uris.first, "https://api.coworkingview.com/v1/market/rates?"
    assert_includes uris.first, "locale=en"
    assert_equal "live", dataset.source
    refute_empty dataset.rows
  end

  def test_locale_is_required
    calls = 0
    client = RedmineCoworkingview::Client.new(http: lambda { |_uri|
      calls += 1
      [200, fixture_body, {}]
    })
    assert_raises(ArgumentError) { client.rates(locale: nil) }
    assert_raises(ArgumentError) { client.rates(locale: "fr") }
    assert_equal 0, calls
  end

  def test_timeouts_user_agent_and_accept
    client = RedmineCoworkingview::Client.new(timeout: 3, base_url: "https://api.coworkingview.com")
    uri = URI("https://api.coworkingview.com/v1/market/rates?locale=en")
    http = client.build_http(uri)
    request = client.build_request(uri)

    assert_equal 3, http.open_timeout
    assert_equal 3, http.read_timeout
    assert_in_delta 3, http.write_timeout, 0
    assert_equal true, http.use_ssl?
    assert_equal 0, http.max_retries
    assert_equal "application/json", request["Accept"]
    assert_equal RedmineCoworkingview::Client::USER_AGENT, request["User-Agent"]
    assert_includes request["User-Agent"], "redmine_coworkingview/0.1.0"
  end

  def test_server_error_is_retried_once
    calls = 0
    waits = []
    responses = [
      [503, "busy", { "Retry-After" => "1" }],
      [200, fixture_body, {}]
    ]
    client = RedmineCoworkingview::Client.new(
      sleeper: ->(seconds) { waits << seconds },
      http: lambda { |_uri|
        calls += 1
        responses.shift
      }
    )
    dataset = client.rates(locale: "de")

    assert_equal 2, calls
    assert_equal [1.0], waits
    assert_equal "live", dataset.source
  end

  def test_client_error_is_not_retried
    calls = 0
    client = RedmineCoworkingview::Client.new(http: lambda { |_uri|
      calls += 1
      [400, '{"title":"Validation failed"}', {}]
    })

    error = assert_raises(RedmineCoworkingview::Error) { client.rates(locale: "en") }
    assert_equal 400, error.status
    assert_equal "Validation failed", error.message
    assert_equal 1, calls
  end

  def test_transport_errors_become_plugin_errors
    client = RedmineCoworkingview::Client.new(http: ->(_uri) { raise SocketError, "down" })
    error = assert_raises(RedmineCoworkingview::Error) { client.rates(locale: "en") }
    assert_match(/down/, error.message)
  end

  def test_base_url_must_be_an_origin
    assert_raises(ArgumentError) { RedmineCoworkingview::Client.new(base_url: "ftp://example.com") }
    assert_raises(ArgumentError) { RedmineCoworkingview::Client.new(base_url: "https://user:pass@example.com") }
    assert_raises(ArgumentError) { RedmineCoworkingview::Client.new(base_url: "https://example.com/v1") }
    built = RedmineCoworkingview::Client.new(base_url: "https://example.com/")
    assert_equal "https://example.com", built.base_url
  end
end
