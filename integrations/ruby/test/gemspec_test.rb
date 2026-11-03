# frozen_string_literal: true

require "test_helper"

class GemspecTest < Minitest::Test
  def test_metadata_matches_the_repository
    spec = Gem::Specification.load(File.expand_path("../coworkingview.gemspec", __dir__))

    assert_equal "coworkingview", spec.name
    assert_equal "0.1.0", spec.version.to_s
    assert_equal ["CoworkingView"], spec.authors
    assert_equal ["info@coworkingview.com"], spec.email
    assert_equal "MIT", spec.license
    assert_equal "https://coworkingview.com", spec.homepage
    assert_equal "https://coworkingview.com", spec.metadata["homepage_uri"]
    assert_equal "https://github.com/coworkingview/flex-office-data/tree/main/integrations/ruby",
                 spec.metadata["source_code_uri"]
    assert_equal "https://github.com/coworkingview/flex-office-data/blob/main/integrations/ruby/CHANGELOG.md",
                 spec.metadata["changelog_uri"]
    assert_equal "true", spec.metadata["rubygems_mfa_required"]
    assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.0.0"))
    refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("2.7.8"))
    assert_empty spec.dependencies.reject { |dependency| dependency.type == :development }
    %w[lib/coworkingview.rb lib/coworkingview/version.rb lib/coworkingview/client.rb LICENSE README.md CHANGELOG.md].each do |path|
      assert_includes spec.files, path
    end
  end
end
