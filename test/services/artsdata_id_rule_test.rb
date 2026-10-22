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

  test "sources guidance is in the server instructions, get_schema conventions and tool descriptions" do
    assert_includes File.read(Rails.root.join("config/initializers/mcp_server.rb")), "ArtsdataSourcesRule::INSTRUCTION"
    assert_includes ArtsdataSchema::CONVENTIONS, ArtsdataSourcesRule::CONVENTION
    assert_includes ArtsdataSourcesRule::CONVENTION, "prov:wasDerivedFrom|prov:hadPrimarySource"
    assert_includes SparqlQuery.description, ArtsdataSourcesRule::TOOL_NOTE
    assert_includes GetEntity.description, ArtsdataSourcesRule::GET_ENTITY_NOTE
  end
end
