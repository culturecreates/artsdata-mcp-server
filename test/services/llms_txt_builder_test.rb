require "test_helper"

class LlmsTxtBuilderTest < ActiveSupport::TestCase
  test "public llms txt stays in sync with generated content" do
    generated = LlmsTxtBuilder.new.render
    checked_in = File.read(Rails.root.join("public", "llms.txt"))

    assert_equal generated, checked_in, "public/llms.txt is stale. Run: bundle exec rake docs:generate_llms"
  end
end