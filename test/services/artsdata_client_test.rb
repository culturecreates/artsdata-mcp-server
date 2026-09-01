require "test_helper"

class ArtsdataClientTest < ActiveSupport::TestCase
  test "get_entity_by_extend_service accepts a uri keyword" do
    uri = "http://kg.artsdata.ca/resource/K11-23"

    ArtsdataClient.new.get_entity_by_extend_service(uri: uri)
  rescue ArgumentError => e
    flunk "get_entity_by_extend_service does not accept `uri:` (it only accepts `ids:`): #{e.message}"
  end
end
