# frozen_string_literal: true

require "cgi"
require "csv"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

# Wiki macros for the CoworkingView Price Index.
#
# The library is plain Ruby so the unit tests can run without Redmine.
# +init.rb+ is what registers the plugin and the macros.
module RedmineCoworkingview
  VERSION = "0.1.0"
  ROOT = File.expand_path("..", __dir__)
  SNAPSHOT_PATH = File.join(ROOT, "data", "rates_snapshot.csv").freeze

  # Same product order as spec/SPEC.md and the Ruby client.
  PRODUCTS = %w[
    flex_desk fix_desk private_office exclusive_bereich day_pass
    meeting_room event_space virtual_office membership
  ].freeze

  # Units for the city-level stat objects (dayPass, meetingRoom, ...).
  # Rows taken from figures or byType are monthly.
  STAT_UNITS = {
    "day_pass" => "day",
    "meeting_room" => "hour",
    "event_space" => "hour",
    "virtual_office" => "month"
  }.freeze

  LOCALES = %w[en es de].freeze
  DEFAULT_LOCALE = "en"
  DEFAULT_TTL_HOURS = 24
  LOW_CONFIDENCE_BELOW = 10
  DEFAULT_PRODUCT = "flex_desk"

  ATTRIBUTION_TEXT = "Data: CoworkingView Price Index (CC BY 4.0)"
  ATTRIBUTION_URL = "https://coworkingview.com/en/tools/price-index"
end

require_relative "redmine_coworkingview/escape"
require_relative "redmine_coworkingview/error"
require_relative "redmine_coworkingview/dataset"
require_relative "redmine_coworkingview/settings"
require_relative "redmine_coworkingview/client"
require_relative "redmine_coworkingview/catalog"
require_relative "redmine_coworkingview/presenter"
