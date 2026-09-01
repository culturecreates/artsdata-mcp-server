require "test_helper"

class ArtsdataClientTest < ActiveSupport::TestCase
  test "get_entity_by_extend_service accepts a uri keyword" do
    ids = ["K11-23"]
    result = ArtsdataClient.new.get_entity_by_extend_service(ids: ids)
    assert_equal ids.first, result.first.fetch("id", nil)

  rescue ArgumentError => e
    flunk "get_entity_by_extend_service does not accept `uri:` (it only accepts `ids:`): #{e.message}"
  end
end
