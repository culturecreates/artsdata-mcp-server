require "test_helper"

class ArtsdataIdRuleTest < ActiveSupport::TestCase
  test "server instructions include the id rule" do
    assert_includes File.read(Rails.root.join("config/initializers/mcp_server.rb")), "ArtsdataIdRule::INSTRUCTION"
  end

  test "every tool description carries the id note" do
    [GetEntity, SearchEvents, SparqlQuery].each do |tool|
      assert_includes tool.description, ArtsdataIdRule::TOOL_NOTE, "#{tool} is missing the note"
    end
  end

  test "search_entities description carries the label note" do
    assert_includes SearchEntities.description, ArtsdataIdRule::SEARCH_NOTE
  end
end
