require "test_helper"
require "minitest/mock"

class EventsDumpTest < ActiveSupport::TestCase
  DUMP_URL = "https://dumps.example.test/core-graph-minus-provenance/monthly/artsdata-2026-09-01-core-minus-provenance.ttl.gz".freeze

  DUMP_METADATA = {
    "url" => DUMP_URL,
    "available" => true,
    "content_type" => "application/gzip",
    "format" => "text/turtle",
    "size" => 987_654_321,
    "last_modified" => "2026-09-01T03:15:02Z",
    "checked_at" => "2026-09-04T08:00:00Z"
  }.freeze

  test "the resource descriptor advertised by resources/list is complete" do
    descriptor = ArtsdataDump.to_h

    assert_equal "artsdata://dump", descriptor[:uri]
    assert_equal "artsdata_dump", descriptor[:name]
    assert_equal "application/json", descriptor[:mimeType]
    assert_match(/not the dump itself/, descriptor[:description],
                 "the description should make clear that reading returns a manifest, not the data")
  end

  test "contents returns a JSON manifest carrying the dump URL and metadata." do
    contents = with_stubbed_dump_metadata(DUMP_METADATA) { ArtsdataDump.contents }

    assert_kind_of MCP::Resource::TextContents, contents
    assert_equal ArtsdataDump::RESOURCE_URI, contents.uri
    assert_equal "application/json", contents.mime_type

    manifest = JSON.parse(contents.text)
    assert_equal "artsdata://dump", manifest["resource"]
    assert_equal "artsdata_dump", manifest["name"]
    assert_equal "monthly", manifest["update_schedule"]
    assert_equal "Artsdata dump", manifest["title"]
    assert_equal DUMP_METADATA, manifest["dump"]
    assert_equal DUMP_URL, manifest.dig("dump", "url")

    assert_operator contents.text.bytesize, :<, 2_000,
                    "the manifest must stay tiny - it must never embed the dump contents"
  end

  private

  def with_stubbed_dump_metadata(metadata)
    mock_client = Minitest::Mock.new
    mock_client.expect(:metadata, metadata)

    result = DataDumpClient.stub(:new, mock_client) { yield }
    mock_client.verify
    result
  end
end
