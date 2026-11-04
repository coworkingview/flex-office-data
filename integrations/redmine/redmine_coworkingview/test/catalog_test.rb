# frozen_string_literal: true

require "test_helper"

class CatalogTest < Minitest::Test
  include CoworkingviewTest

  def test_network_off_does_not_call_the_api
    calls = 0
    catalog = build_catalog(network: "0", http: lambda { |_uri|
      calls += 1
      [200, fixture_body, {}]
    })
    dataset = catalog.dataset

    assert_equal 0, calls
    assert_equal "snapshot", dataset.source
    refute_empty dataset.rows
  end

  def test_successful_response_is_cached_until_the_ttl
    calls = 0
    cache = MemoryCache.new
    catalog = build_catalog(cache: cache, ttl: "24", http: lambda { |uri|
      calls += 1
      assert_includes uri.to_s, "locale=es"
      [200, fixture_body, {}]
    }, locale: "es")

    first = catalog.dataset
    second = catalog.dataset
    assert_equal 1, calls
    assert_same first, second
    assert_equal "live", first.source

    cache.now += (24 * 3600) - 1
    catalog.dataset
    assert_equal 1, calls

    cache.now += 1
    catalog.dataset
    assert_equal 2, calls
  end

  def test_failure_falls_back_to_the_snapshot_and_is_not_cached
    calls = 0
    catalog = build_catalog(http: lambda { |_uri|
      calls += 1
      [400, '{"title":"Validation failed"}', {}]
    })

    first = catalog.dataset
    second = catalog.dataset
    assert_equal "snapshot", first.source
    assert_equal "snapshot", second.source
    assert_equal 2, calls
    refute_empty first.rows
  end

  def test_one_retry_then_the_live_dataset
    calls = 0
    responses = [
      [500, "nope", {}],
      [200, fixture_body, {}]
    ]
    catalog = build_catalog(http: lambda { |_uri|
      calls += 1
      responses.shift
    })

    assert_equal "live", catalog.dataset.source
    assert_equal 2, calls
    catalog.dataset
    assert_equal 2, calls
  end

  private

  def build_catalog(http:, network: "1", locale: "en", ttl: "24", cache: MemoryCache.new)
    settings = RedmineCoworkingview::Settings.new(
      "network" => network,
      "locale" => locale,
      "cache_ttl_hours" => ttl
    )
    client = RedmineCoworkingview::Client.new(http: http, sleeper: ->(_seconds) {})
    RedmineCoworkingview::Catalog.new(client: client, settings: settings, cache: cache)
  end
end
