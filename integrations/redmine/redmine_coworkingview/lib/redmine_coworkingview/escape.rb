# frozen_string_literal: true

module RedmineCoworkingview
  # HTML escape used for every value interpolated into macro output.
  # Same characters as Rails' +h+ / +ERB::Util.html_escape+, including apostrophes.
  module Escape
    module_function

    def h(value)
      CGI.escapeHTML(value.to_s).gsub("'", "&#39;")
    end
  end
end
