# frozen_string_literal: true

require "test_helper"

class DatasetTest < Minitest::Test
  include CoworkingviewTest

  COLUMNS = %i[
    city_slug city_name country_code currency product unit median p25 p75
    sample_size property_count operator_count low_confidence as_of
  ].freeze

  def test_fixture_json_matches_the_bundled_snapshot
    from_api = RedmineCoworkingview::Dataset.from_api(fixture_payload)
    from_csv = RedmineCoworkingview::Dataset.from_csv(RedmineCoworkingview::SNAPSHOT_PATH)

    assert_equal "live", from_api.source
    assert_equal "snapshot", from_csv.source
    assert_equal dump(from_csv.rows), dump(from_api.rows)
    assert_equal from_csv.as_of, from_api.as_of
    refute_empty from_api.rows
  end

  def test_snapshot_file_matches_the_repo_golden_csv_when_present
    golden = File.expand_path("../../../../spec/golden/rates.csv", __dir__)
    skip "golden csv is not beside the plugin" unless File.file?(golden)

    assert_equal File.binread(golden), File.binread(RedmineCoworkingview::SNAPSHOT_PATH)
  end

  def test_figures_win_over_by_type_and_unpublished_cities_are_skipped
    payload = {
      "data" => {
        "asOf" => "2026-01-01T00:00:00Z",
        "licenseUrl" => "https://creativecommons.org/licenses/by/4.0/",
        "attribution" => "Source: CoworkingView Price Index",
        "cities" => [
          {
            "city" => { "slug" => "example", "name" => "Example" },
            "countryCode" => "DE",
            "currency" => "EUR",
            "figures" => [
              {
                "optionType" => "fix_desk",
                "median" => { "amount" => 5 },
                "p25" => { "amount" => 4 },
                "p75" => { "amount" => 6 },
                "sampleSize" => 12,
                "propertyCount" => 3,
                "operatorCount" => 2
              }
            ],
            "byType" => [
              { "optionType" => "flex_desk", "median" => { "amount" => 1 }, "sampleSize" => 12 }
            ]
          }
        ],
        "unpublished" => [
          { "city" => { "slug" => "hidden", "name" => "Hidden" }, "countryCode" => "DE" }
        ]
      }
    }

    dataset = RedmineCoworkingview::Dataset.from_api(payload)
    assert_equal ["fix_desk"], dataset.rows.map(&:product)
    row = dataset.rows.first
    assert_equal "month", row.unit
    assert_equal 5, row.median
    assert_equal 4, row.p25
    assert_equal 6, row.p75
    assert_equal false, row.low_confidence
    assert_equal "https://creativecommons.org/licenses/by/4.0/", dataset.license
    refute_includes dataset.rows.map(&:city_slug), "hidden"
  end

  def test_empty_figures_fall_back_to_by_type_and_stat_objects
    payload = {
      "data" => {
        "asOf" => "2026-01-01T00:00:00Z",
        "cities" => [
          {
            "city" => { "slug" => "example", "name" => "Example" },
            "countryCode" => "DE",
            "currency" => "EUR",
            "figures" => [],
            "byType" => [
              { "optionType" => "flex_desk", "median" => { "amount" => 10 }, "sampleSize" => 4 }
            ],
            "dayPass" => { "median" => { "amount" => 2 }, "sampleSize" => 11 },
            "eventSpace" => {
              "median" => { "amount" => 8 },
              "p25" => { "amount" => 7 },
              "sampleSize" => 3
            }
          }
        ]
      }
    }

    rows = RedmineCoworkingview::Dataset.from_api(payload).rows
    assert_equal %w[flex_desk day_pass event_space], rows.map(&:product)

    flex, day, event = rows
    assert_equal "month", flex.unit
    assert_nil flex.p25
    assert_equal true, flex.low_confidence
    assert_equal "day", day.unit
    assert_equal 2, day.median
    assert_equal false, day.low_confidence
    assert_equal "hour", event.unit
    assert_equal 7, event.p25
    assert_nil event.p75
    assert_equal "—", RedmineCoworkingview::Presenter.new(
      RedmineCoworkingview::Dataset.from_api(payload)
    ).rate("example", "day_pass").then { |html| html[/<span class="coworkingview-spread">(.*?)<\/span>/, 1] }
  end

  def test_a_payload_without_data_raises
    assert_raises(RedmineCoworkingview::Error) do
      RedmineCoworkingview::Dataset.from_api("nope" => true)
    end
  end

  private

  def dump(rows)
    rows.map { |row| COLUMNS.map { |column| row.public_send(column) } }
  end
end
