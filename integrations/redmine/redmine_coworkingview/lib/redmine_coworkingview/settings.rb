# frozen_string_literal: true

module RedmineCoworkingview
  # Plugin settings stored by Redmine under +plugin_redmine_coworkingview+.
  class Settings
    DEFAULTS = {
      "network" => "1",
      "cache_ttl_hours" => DEFAULT_TTL_HOURS.to_s,
      "locale" => DEFAULT_LOCALE
    }.freeze

    def self.from_plugin
      raw = nil
      if defined?(Setting) && Setting.respond_to?(:plugin_redmine_coworkingview)
        raw = Setting.plugin_redmine_coworkingview
      end
      new(raw)
    rescue StandardError
      new(nil)
    end

    def initialize(values = nil)
      @values = DEFAULTS.merge(stringify(values))
    end

    def network?
      flag = @values["network"]
      return true if flag.nil?

      case flag
      when true then true
      when false then false
      else
        text = flag.to_s.strip.downcase
        return false if %w[0 false off no].include?(text)
        return true if text.empty? || %w[1 true on yes].include?(text)

        true
      end
    end

    def locale
      text = @values["locale"].to_s.strip.downcase
      LOCALES.include?(text) ? text : DEFAULT_LOCALE
    end

    def cache_ttl_hours
      text = @values["cache_ttl_hours"].to_s.strip
      return DEFAULT_TTL_HOURS unless /\A[1-9]\d*\z/.match?(text)

      hours = text.to_i
      hours.positive? ? hours : DEFAULT_TTL_HOURS
    end

    private

    def stringify(values)
      return {} if values.nil?
      hash = if values.respond_to?(:to_unsafe_h)
               values.to_unsafe_h
             elsif values.is_a?(Hash)
               values
             elsif values.respond_to?(:to_h)
               values.to_h
             else
               {}
             end
      return {} unless hash.respond_to?(:each_pair)

      hash.each_pair.with_object({}) do |(key, value), out|
        out[key.to_s] = value
      end
    end
  end
end
