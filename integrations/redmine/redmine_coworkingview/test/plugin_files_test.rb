# frozen_string_literal: true

require "test_helper"

class PluginFilesTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_init_registers_the_plugin
    source = File.read(File.join(ROOT, "init.rb"))
    assert_includes source, "Redmine::Plugin.register :redmine_coworkingview"
    assert_includes source, "name 'CoworkingView Prices'"
    assert_includes source, "author 'CoworkingView'"
    assert_includes source, "version '0.1.0'"
    assert_includes source, "url 'https://coworkingview.com'"
    assert_includes source, "author_url 'https://coworkingview.com'"
    assert_includes source, "requires_redmine version_or_higher: '5.0.0'"
    assert_includes source, "'network' => '1'"
    assert_includes source, "'cache_ttl_hours' => '24'"
    assert_includes source, "'locale' => 'en'"
    refute_includes source, "ActiveRecord::Migration"
  end

  def test_both_macros_are_registered
    source = File.read(File.join(ROOT, "lib/redmine_coworkingview/macros.rb"))
    assert_includes source, "macro :coworking_rate"
    assert_includes source, "macro :coworking_rates"
    assert_includes source, "html_safe"
  end

  def test_settings_partial_has_the_three_settings
    source = File.read(File.join(ROOT, "app/views/settings/_coworkingview.html.erb"))
    assert_includes source, "settings[network]"
    assert_includes source, "settings[cache_ttl_hours]"
    assert_includes source, "settings[locale]"
  end

  def test_macro_output_is_marked_html_safe_when_the_string_supports_it
    require "redmine_coworkingview/macros"
    fragment = String.new("<p>a &amp; b</p>")
    def fragment.html_safe
      @marked = true
      self
    end

    result = RedmineCoworkingview::Macros.safe(fragment)
    assert_equal true, result.instance_variable_get(:@marked)
    assert_includes result, "&amp;"
  end

  def test_readme_has_no_price_figures
    readme = File.read(File.join(ROOT, "README.md"))
    assert_includes readme, "{{coworking_rate(berlin)}}"
    assert_includes readme, "{{coworking_rate(berlin, private_office)}}"
    assert_includes readme, "{{coworking_rates(berlin)}}"
    assert_includes readme, "https://coworkingview.com"
    assert_includes readme, "CC BY 4.0"
    assert_includes readme, "plugins/"
    refute_match(/\b\d{2,}\s*(EUR|AED|GBP|USD)\b/, readme)
  end
end
