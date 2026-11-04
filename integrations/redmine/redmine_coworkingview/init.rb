# frozen_string_literal: true

require "redmine"
require_relative "lib/redmine_coworkingview"
require_relative "lib/redmine_coworkingview/macros"

Redmine::Plugin.register :redmine_coworkingview do
  name 'CoworkingView Prices'
  author 'CoworkingView'
  description 'Wiki macros for the CoworkingView Price Index: median, p25-p75 spread, currency, unit and sample size for a city.'
  version '0.1.0'
  url 'https://coworkingview.com'
  author_url 'https://coworkingview.com'
  requires_redmine version_or_higher: '5.0.0'

  settings default: {
    'network' => '1',
    'cache_ttl_hours' => '24',
    'locale' => 'en'
  }, partial: 'settings/coworkingview'
end

RedmineCoworkingview::Macros.register!

if defined?(Rails) && Rails.application.respond_to?(:reloader) && Rails.application.reloader
  Rails.application.reloader.to_prepare do
    RedmineCoworkingview::Macros.register!
  end
end
