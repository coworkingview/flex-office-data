# frozen_string_literal: true

require_relative "lib/coworkingview/version"

Gem::Specification.new do |spec|
  spec.name = "coworkingview"
  spec.version = CoworkingView::VERSION
  spec.authors = ["CoworkingView"]
  spec.email = ["info@coworkingview.com"]
  spec.summary = "Ruby client for the CoworkingView Price Index and catalogue."
  spec.description = <<~TEXT
    Ruby client for the public CoworkingView API (https://api.coworkingview.com).
    It reads the CoworkingView Price Index — median, 25th and 75th percentile
    prices by city and product, with the sample size beside every figure — and
    searches the coworking catalogue. No API key. The Price Index is CC BY 4.0
    and the attribution string is returned with every index result. The only
    runtime dependencies are net/http and json from the Ruby standard library.
  TEXT
  spec.homepage = "https://coworkingview.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["homepage_uri"] = "https://coworkingview.com"
  spec.metadata["source_code_uri"] = "https://github.com/coworkingview/flex-office-data/tree/main/integrations/ruby"
  spec.metadata["changelog_uri"] = "https://github.com/coworkingview/flex-office-data/blob/main/integrations/ruby/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) { Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"] }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.24"
end
