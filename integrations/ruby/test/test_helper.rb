# frozen_string_literal: true

require "csv"
require "json"
require "minitest/autorun"
require "webmock/minitest"

require "coworkingview"

WebMock.disable_net_connect!

module FixtureHelpers
  ROOT = File.expand_path("../../..", __dir__)

  def fixture(name)
    File.read(File.join(ROOT, "spec", "fixtures", name))
  end

  def golden_path(name)
    File.join(ROOT, "spec", "golden", name)
  end

  def client(**kwargs)
    kwargs[:sleeper] ||= ->(_seconds) {}
    CoworkingView::Client.new(**kwargs)
  end

  def json_headers(extra = {})
    { "Content-Type" => "application/json" }.merge(extra)
  end

  def stub_api(path, body, status: 200, headers: {})
    stub_request(:get, %r{\Ahttps://api\.coworkingview\.com#{Regexp.escape(path)}(?:\?|\z)})
      .to_return(status: status, body: body, headers: json_headers(headers))
  end

  def cell(value)
    case value
    when nil, "" then nil
    when true then "true"
    when false then "false"
    else value.to_s
    end
  end

  def assert_golden(rows, filename, columns)
    expected = CSV.read(golden_path(filename), headers: true).map do |row|
      row.to_h.transform_values { |value| value == "" ? nil : value }
    end
    actual = rows.map do |row|
      columns.to_h { |column| [column.to_s, cell(row[column])] }
    end
    assert_equal expected, actual
  end

  def assert_no_requests
    assert_empty WebMock::RequestRegistry.instance.requested_signatures.hash
  end
end

class Minitest::Test
  include FixtureHelpers

  def setup
    super
    WebMock.reset!
    @previous_api_url = ENV.delete("COWORKINGVIEW_API_URL")
  end

  def teardown
    if @previous_api_url.nil?
      ENV.delete("COWORKINGVIEW_API_URL")
    else
      ENV["COWORKINGVIEW_API_URL"] = @previous_api_url
    end
    super
  end
end
