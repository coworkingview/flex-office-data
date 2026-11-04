# frozen_string_literal: true

module RedmineCoworkingview
  # A failed rates request, or a payload this plugin cannot read.
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      @status = status
      super(message)
    end
  end
end
