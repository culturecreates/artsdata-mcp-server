require "test_helper"
require "minitest/mock"

class ArtsdataClientTest < ActiveSupport::TestCase
  test "get_entity_by_extend_service accepts a uri keyword" do
    ids = ["K11-23"]
    result = ArtsdataClient.new.get_entity_by_extend_service(ids: ids)
    assert_equal ids.first, result.first.fetch("id", nil)

  rescue ArgumentError => e
    flunk "get_entity_by_extend_service does not accept `uri:` (it only accepts `ids:`): #{e.message}"
  end

  test "search_events combines the match and extend reconciliation responses into formatted results" do
    # The "match" reconciliation query finds candidate entity ids; the "extend" query then
    # fetches full details for those ids. Stub execute_reconciliation_query (the method that
    # actually talks to the reconciliation service) to return canned responses for each route,
    # so this test exercises the real search_events -> get_entity_by_extend_service ->
    # format_get_entity_results pipeline without making a network call.
    match_response = {
      "results" => [
        { "candidates" => [{ "id" => "K1-1" }] }
      ]
    }

    extend_response = {
      "rows" => [
        {
          "id" => "K1-1",
          "properties" => [
            { "id" => "name", "values" => [{ "str" => "Test Event", "lang" => "en" }] },
            { "id" => "type", "values" => [{ "id" => "http://schema.org/Event" }] },
            { "id" => "startDate", "values" => [{ "str" => "2026-01-01" }] }
          ]
        }
      ]
    }

    expected_result = [
      {
        "id" => "K1-1",
        "uri" => "http://kg.artsdata.ca/resource/K1-1",
        "types" => [{ "uri" => "http://schema.org/Event", "label" => "Event" }],
        "name" => [{ "value" => "Test Event", "language" => "en" }],
        "start_date" => "2026-01-01"
      }
    ]

    stubbed_recon_query = lambda do |_payload, **options|
      options[:route] == "match" ? match_response : extend_response
    end

    client = ArtsdataClient.new
    result = client.stub(:execute_reconciliation_query, stubbed_recon_query) do
      client.search_events(
        startDateFrom: "2026-01-01", startDateTo: "", places: [], artists: [],
        organizations: [], types: [], language: "en", limit: 25
      )
    end

    assert_equal expected_result, result
  end
end
