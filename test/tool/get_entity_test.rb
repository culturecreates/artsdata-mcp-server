require "test_helper"

class GetEntityTest < ActiveSupport::TestCase
  test "call returns entity details for a valid uri instead of raising" do
    uri = "http://kg.artsdata.ca/resource/K11-23"
    id = uri.split('/').last
    response = GetEntity.call(uri: uri)

    assert_equal id, response.structured_content&.fetch("id", nil)
  rescue ArgumentError => e
    flunk "GetEntity.call raised #{e.class}: #{e.message} " \
          "(app/tool/get_entity.rb calls ArtsdataClient#get_entity_by_extend_service with `uri:`, " \
          "but that method only accepts `ids:`)"
  end
end
