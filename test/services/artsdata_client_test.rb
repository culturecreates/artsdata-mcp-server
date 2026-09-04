require "test_helper"
require "minitest/mock"

class ArtsdataClientTest < ActiveSupport::TestCase

  RECON_MATCH_FIXTURE_PATH = Rails.root.join("test", "fixtures", "search_entities_recon_match_results.json")

  test "get_entity_by_extend_service accepts an ids keyword and returns one formatted entity per row" do
    ids = ["K11-23"]
    client = ArtsdataClient.new
    extend_response = {
      "rows" => [
        {
          "id" => "K11-23",
          "properties" => [
            { "id" => "name", "values" => [{ "str" => "Test Organization", "lang" => "en" }] },
            { "id" => "type", "values" => [{ "id" => "http://schema.org/Organization" }] }
          ]
        }
      ]
    }

    result = client.stub(:execute_reconciliation_query, ->(_payload, **_options) { extend_response }) do
      client.get_entity_by_extend_service(ids: ids)
    end

    assert_equal ids.first, result.first.fetch("id", nil)
    assert_equal "http://kg.artsdata.ca/resource/K11-23", result.first.fetch("uri", nil)

  rescue ArgumentError => e
    flunk "get_entity_by_extend_service does not accept `ids:`: #{e.message}"
  end

  test "search_events combines the match and extend reconciliation responses into formatted results" do
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

  test "format_get_entity_results returns an empty array when given no rows" do
    assert_equal [], ArtsdataClient.new.format_get_entity_results([])
  end

  test "search_items formats match candidates into search results" do

    SEARCH_MATCH_RESPONSE = JSON.parse(File.read(RECON_MATCH_FIXTURE_PATH))

    result = search_items_with_stubbed_reconciliation(
      match_response: SEARCH_MATCH_RESPONSE, query: "festival", types: [], lang: "en", limit: 25
    )

    expected = [
      {
        "id" => "K11-23",
        "name" => "Festival Example",
        "description" => "Sample festival organization",
        "type" => [{ "id" => "http://schema.org/Organization", "name" => "Organization" }],
        "uri" => "http://kg.artsdata.ca/resource/K11-23"
      },
      {
        "id" => "K11-24",
        "name" => "Festival Hall",
        "type" => [{ "id" => "http://schema.org/Place", "name" => "Place" }],
        "uri" => "http://kg.artsdata.ca/resource/K11-24"
      }
    ]

    assert_equal expected, result
  end

  test "search_items returns an empty array when the match response has no candidates" do
    assert_equal [], search_items_with_stubbed_reconciliation(
      match_response: { "results" => [{ "candidates" => [] }] },
      query: "nothing", types: [], lang: "en", limit: 25
    )
    assert_equal [], search_items_with_stubbed_reconciliation(
      match_response: { "results" => [] },
      query: "nothing", types: [], lang: "en", limit: 25
    )
  end

  test "search_items returns an empty array when the reconciliation service is unavailable" do

    assert_equal [], search_items_with_stubbed_reconciliation(
      match_response: {}, query: "festival", types: [], lang: "en", limit: 25
    )
  end

  private

  def search_items_with_stubbed_reconciliation(match_response:, captured: {}, **params)
    client = ArtsdataClient.new

    record_and_respond = lambda do |payload, **options|
      captured[:payload] = payload
      captured[:route] = options[:route]
      captured[:lang] = options[:lang]
      match_response
    end

    client.stub(:execute_reconciliation_query, record_and_respond) do
      client.search_items(**params)
    end
  end
end
