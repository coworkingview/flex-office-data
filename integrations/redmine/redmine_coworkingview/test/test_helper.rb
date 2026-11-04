# frozen_string_literal: true

ENV.delete("COWORKINGVIEW_API_URL")

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "json"
require "redmine_coworkingview"

module CoworkingviewTest
  FIXTURE = File.expand_path("fixtures/market_rates.json", __dir__)

  def fixture_payload
    JSON.parse(File.read(FIXTURE))
  end

  def fixture_body
    File.read(FIXTURE)
  end
end

# Cache stand-in with a movable clock. +expires_in+ is seconds.
class MemoryCache
  def initialize
    @now = Time.utc(2026, 1, 1)
    @store = {}
  end

  attr_accessor :now

  def read(key)
    entry = @store[key]
    return nil unless entry
    return nil if @now >= entry[:expires_at]

    entry[:value]
  end

  def write(key, value, expires_in:)
    @store[key] = { value: value, expires_at: @now + expires_in }
    value
  end
end
