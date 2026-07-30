require "test_helper"

class VersionUpgradeTest < ActiveSupport::TestCase
  test "ruby is at least 4.0.6" do
    assert_operator Gem::Version.new(RUBY_VERSION), :>=, Gem::Version.new("4.0.6")
  end

  test "rails stays on 8.1.x" do
    assert_operator Rails.gem_version, :>=, Gem::Version.new("8.1.0")
    assert_operator Rails.gem_version, :<, Gem::Version.new("8.2.0")
  end
end
