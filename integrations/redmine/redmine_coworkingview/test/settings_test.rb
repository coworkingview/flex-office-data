# frozen_string_literal: true

require "test_helper"

class SettingsTest < Minitest::Test
  def test_defaults
    settings = RedmineCoworkingview::Settings.new(nil)
    assert settings.network?
    assert_equal "en", settings.locale
    assert_equal 24, settings.cache_ttl_hours
  end

  def test_network_flag
    refute RedmineCoworkingview::Settings.new("network" => "0").network?
    refute RedmineCoworkingview::Settings.new("network" => "off").network?
    refute RedmineCoworkingview::Settings.new("network" => false).network?
    assert RedmineCoworkingview::Settings.new("network" => "on").network?
    assert RedmineCoworkingview::Settings.new("network" => true).network?
  end

  def test_locale_and_ttl
    assert_equal "de", RedmineCoworkingview::Settings.new("locale" => "DE").locale
    assert_equal "en", RedmineCoworkingview::Settings.new("locale" => "fr").locale
    assert_equal 6, RedmineCoworkingview::Settings.new("cache_ttl_hours" => "6").cache_ttl_hours
    assert_equal 24, RedmineCoworkingview::Settings.new("cache_ttl_hours" => "0").cache_ttl_hours
    assert_equal 24, RedmineCoworkingview::Settings.new("cache_ttl_hours" => "nope").cache_ttl_hours
  end
end
