require "test_helper"
require "minitest/mock"

class ArtsdataDumpTest < ActiveSupport::TestCase
  RESOURCE_URI = "artsdata://dumps/core-minus-provenance/latest".freeze
  ARTIFACT_URI = "http://kg.artsdata.ca/databus/culture-creates/artsdata-dump/core-minus-provenance".freeze
  FILE_URL = "https://artsdata-graphdb-backups.s3.ca-central-1.amazonaws.com/core-graph-minus-provenance/monthly/artsdata-2026-09-01-core-minus-provenance.ttl.gz".freeze

  DATABUS_ENTRY = {
    "artifact" => ARTIFACT_URI,
    "file" => FILE_URL,
    "latestVersion" => "2026-09-01T05_18_57"
  }.freeze


  test "manifest describes the latest version reported by the Databus" do
    manifest = with_stubbed_databus(DATABUS_ENTRY) { ArtsdataCoreMinusProvenanceDump.manifest }

    assert_equal({
                   "uri" => RESOURCE_URI,
                   "type" => "ArtsdataDump",
                   "name" => "Artsdata core minus provenance",
                   "description" => "Latest public dump of the Artsdata core graph with provenance and RDF-star " \
                     "annotations removed. Intended for RDF 1.1 consumers, AI agents, " \
                     "reconciliation workflows, and systems that cannot parse RDF 1.2/Turtle-star.",
                   "artifact" => "core-minus-provenance",
                   "artifactUri" => ARTIFACT_URI,
                   "version" => "2026-09-01T05_18_57",
                   "content" => "Artsdata core graph without provenance, RDF 1.1 compatible",
                   "format" => "text/turtle",
                   "compression" => "gzip",
                   "downloadUrl" => FILE_URL
                 }, manifest)
  end

  test "manifest stays readable when the Databus is unavailable" do
    manifest = with_stubbed_databus(DatabusClient::Error.new("HTTP 503")) { ArtsdataCoreMinusProvenanceDump.manifest }

    assert_equal RESOURCE_URI, manifest["uri"]
    assert_equal "core-minus-provenance", manifest["artifact"]
    assert_equal "HTTP 503", manifest["error"]
    refute manifest.key?("downloadUrl"), "no download URL can be offered when the Databus is unreachable"
    refute manifest.key?("version")
  end


  private

  # Stubs DatabusClient#latest_artifact. `result` is either the entry to return or an exception
  # to raise; either way the artifact URI the resource asked for is asserted.
  def with_stubbed_databus(result)
    return with_raising_databus(result) { yield } if result.is_a?(Exception)

    mock_client = Minitest::Mock.new
    mock_client.expect(:latest_artifact, result, [ARTIFACT_URI])

    value = DatabusClient.stub(:new, mock_client) { yield }
    mock_client.verify
    value
  end

  # Minitest::Mock cannot be taught to raise, so the failure case uses a plain double.
  def with_raising_databus(error)
    requested = []
    failing_client = Object.new
    failing_client.define_singleton_method(:latest_artifact) do |uri|
      requested << uri
      raise error
    end

    value = DatabusClient.stub(:new, failing_client) { yield }
    assert_equal [ARTIFACT_URI], requested
    value
  end
end
