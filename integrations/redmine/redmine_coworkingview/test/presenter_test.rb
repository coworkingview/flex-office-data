# frozen_string_literal: true

require "test_helper"

class PresenterTest < Minitest::Test
  include CoworkingviewTest

  def setup
    @dataset = RedmineCoworkingview::Dataset.from_api(fixture_payload)
    @presenter = RedmineCoworkingview::Presenter.new(@dataset)
  end

  def test_rate_defaults_to_flex_desk_and_shows_every_required_field
    row = @dataset.rows.find { |item| item.city_slug == "berlin" && item.product == "flex_desk" }
    html = @presenter.rate("berlin")

    assert_equal html, @presenter.rate("Berlin", "flex_desk")
    assert_includes html, %(<span class="coworkingview-city">#{row.city_name}</span>)
    assert_includes html, %(<span class="coworkingview-product">#{row.product}</span>)
    assert_includes html, %(<span class="coworkingview-median">#{row.median}</span>)
    assert_includes html, %(<span class="coworkingview-spread">#{row.p25}-#{row.p75}</span>)
    assert_includes html, %(<span class="coworkingview-currency">#{row.currency}</span>)
    assert_includes html, %(<span class="coworkingview-unit">#{row.unit}</span>)
    assert_includes html, %(<span class="coworkingview-sample">#{row.sample_size}</span>)
    assert_includes html, %(as of #{@dataset.as_of})
    assert_attribution html
    refute_includes html, "Bundled snapshot"
    refute_includes html, "creativecommons.org"
  end

  def test_rate_selects_the_optional_product
    row = @dataset.rows.find { |item| item.city_slug == "berlin" && item.product == "private_office" }
    html = @presenter.rate("berlin", "Private_Office")

    assert_includes html, %(<span class="coworkingview-product">#{row.product}</span>)
    assert_includes html, %(<span class="coworkingview-median">#{row.median}</span>)
  end

  def test_rates_lists_every_product_for_the_city
    rows = @dataset.rows.select { |item| item.city_slug == "berlin" }
    html = @presenter.rates(" berlin ")

    rows.each do |row|
      assert_includes html, %(<td class="coworkingview-product">#{row.product}</td>)
      assert_includes html, %(<td class="coworkingview-median">#{row.median}</td>)
      assert_includes html, %(<td class="coworkingview-currency">#{row.currency}</td>)
      assert_includes html, %(<td class="coworkingview-unit">#{row.unit}</td>)
      assert_includes html, %(<td class="coworkingview-sample">#{row.sample_size}</td>)
    end
    assert_equal rows.length, html.scan('class="coworkingview-product"').length
    refute_includes html, ">madrid<"
    assert_attribution html
  end

  def test_missing_percentiles_are_not_filled_in
    html = @presenter.rate("berlin", "day_pass")
    assert_includes html, %(<span class="coworkingview-spread">—</span>)
  end

  def test_output_escapes_city_product_and_error_text
    nasty = RedmineCoworkingview::Rate.new(
      city_slug: "x",
      city_name: "<b>Berlin</b> & 'O'",
      country_code: "DE",
      currency: "EUR&",
      product: "flex_desk\"<script>",
      unit: "month",
      median: 1,
      p25: 1,
      p75: 2,
      sample_size: 3,
      low_confidence: true,
      as_of: "2026-01-01T00:00:00Z"
    )
    dataset = RedmineCoworkingview::Dataset.new(rows: [nasty], source: "live", as_of: nasty.as_of)
    html = RedmineCoworkingview::Presenter.new(dataset).rate("x", nasty.product)

    assert_includes html, "&lt;b&gt;Berlin&lt;/b&gt; &amp; &#39;O&#39;"
    assert_includes html, "EUR&amp;"
    assert_includes html, "flex_desk&quot;&lt;script&gt;"
    refute_includes html, "<b>Berlin</b>"
    refute_includes html, "<script>"

    unknown_city = @presenter.rate("<script>alert(1)</script>")
    assert_includes unknown_city, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes unknown_city, "<script>"

    unknown_product = @presenter.rate("berlin", "<img src=x>")
    assert_includes unknown_product, "&lt;img src=x&gt;"
    refute_includes unknown_product, "<img"
  end

  def test_unknown_city_and_blank_city
    missing = @presenter.rates("not-a-city")
    assert_includes missing, "No Price Index rates for not-a-city."
    assert_includes @presenter.rate(""), "Pass a city slug"
  end

  def test_snapshot_source_is_labelled
    dataset = RedmineCoworkingview::Dataset.from_csv(RedmineCoworkingview::SNAPSHOT_PATH)
    html = RedmineCoworkingview::Presenter.new(dataset).rates("madrid")
    assert_includes html, "Bundled snapshot."
    assert_attribution html
  end

  private

  def assert_attribution(html)
    assert_includes html, %(href="#{RedmineCoworkingview::ATTRIBUTION_URL}")
    assert_includes html, RedmineCoworkingview::ATTRIBUTION_TEXT
  end
end
