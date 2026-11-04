# frozen_string_literal: true

module RedmineCoworkingview
  # Registers {{coworking_rate}} and {{coworking_rates}}.
  #
  # Redmine wraps macro output in +h()+. The string returned here is already
  # escaped and marked html_safe, so that outer +h()+ leaves the tags in place
  # and does not escape them a second time.
  module Macros
    module_function

    def register!
      Redmine::WikiFormatting::Macros.register do
        desc "One Price Index product for a city. " \
             "{{coworking_rate(berlin)}} uses flex_desk. " \
             "{{coworking_rate(berlin, private_office)}} selects the product."
        macro :coworking_rate do |_obj, args|
          RedmineCoworkingview::Macros.render_rate(args)
        end

        desc "Price Index table for every product in a city. {{coworking_rates(berlin)}}"
        macro :coworking_rates do |_obj, args|
          RedmineCoworkingview::Macros.render_rates(args)
        end
      end
    end

    def render_rate(args)
      list = Array(args)
      safe(Presenter.new(catalog.dataset).rate(list[0], list[1]))
    rescue Error => e
      safe(%(<p class="coworkingview-error">#{Escape.h(e.message)}</p>))
    end

    def render_rates(args)
      list = Array(args)
      safe(Presenter.new(catalog.dataset).rates(list[0]))
    rescue Error => e
      safe(%(<p class="coworkingview-error">#{Escape.h(e.message)}</p>))
    end

    def catalog
      logger = nil
      logger = Rails.logger if defined?(Rails) && Rails.respond_to?(:logger)
      Catalog.new(client: Client.new, settings: Settings.from_plugin, cache: rails_cache, logger: logger)
    end

    def rails_cache
      return nil unless defined?(Rails) && Rails.respond_to?(:cache)

      Rails.cache
    rescue StandardError
      nil
    end

    def safe(html)
      text = html.to_s
      text.respond_to?(:html_safe) ? text.html_safe : text
    end
  end
end
