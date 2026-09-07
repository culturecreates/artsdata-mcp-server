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


  test "search_events matches artist labels on the organizer and performer name properties" do
    payload = search_events_with_captured_match_payload(artists: ["Jane Doe", "John Roe"])

    assert_equal [
                   agent_condition(ORGANIZER_NAME_PROPERTY_ID, ["Jane Doe", "John Roe"]),
                   agent_condition(PERFORMER_NAME_PROPERTY_ID, ["Jane Doe", "John Roe"])
                 ],
                 agent_conditions(payload),
                 "artist labels should be matched on the organizer and performer name properties"
  end

  test "search_events matches artist URIs on the organizer and performer properties" do
    uris = ["http://kg.artsdata.ca/resource/K1-1", "http://kg.artsdata.ca/resource/K1-2"]
    payload = search_events_with_captured_match_payload(artists: uris)

    assert_equal [
                   agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, uris)
                 ],
                 agent_conditions(payload),
                 "artist URIs should be matched on the organizer and performer properties, not the name ones"
  end

  test "search_events matches a mix of artist labels and URIs on both sets of properties" do
    uri = "http://kg.artsdata.ca/resource/K1-1"
    payload = search_events_with_captured_match_payload(artists: ["Jane Doe", uri])

    assert_equal [
                   agent_condition(ORGANIZER_NAME_PROPERTY_ID, ["Jane Doe"]),
                   agent_condition(PERFORMER_NAME_PROPERTY_ID, ["Jane Doe"]),
                   agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, [uri])
                 ],
                 agent_conditions(payload),
                 "a mixed artists list should produce label conditions and URI conditions side by side"
  end

  test "search_events merges organizations with artists, splitting labels from URIs" do
    artist_uri = "http://kg.artsdata.ca/resource/K1-1"
    org_uri = "http://kg.artsdata.ca/resource/K2-2"
    payload = search_events_with_captured_match_payload(
      artists: ["Jane Doe", artist_uri],
      organizations: ["Some Org", org_uri]
    )

    assert_equal [
                   agent_condition(ORGANIZER_NAME_PROPERTY_ID, ["Jane Doe", "Some Org"]),
                   agent_condition(PERFORMER_NAME_PROPERTY_ID, ["Jane Doe", "Some Org"]),
                   agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, [artist_uri, org_uri])
                 ],
                 agent_conditions(payload)
  end

  test "search_events adds no agent conditions when artists and organizations are empty" do
    payload = search_events_with_captured_match_payload(artists: [], organizations: [])

    assert_empty agent_conditions(payload),
                 "an empty artists/organizations list should not add any agent condition"
  end

  test "search_events leaves the other filter conditions untouched when filtering by artist URI" do
    payload = search_events_with_captured_match_payload(
      startDateFrom: "2026-01-01",
      startDateTo: "2026-01-31",
      places: ["Toronto"],
      artists: ["http://kg.artsdata.ca/resource/K1-1"]
    )

    conditions = payload[:queries].first[:conditions]

    assert_includes conditions,
                    {
                      matchType: "property",
                      propertyId: ArtsdataClient::START_DATE_PROPERTY_ID,
                      propertyValue: "2026-01-01/2026-01-31",
                      required: true,
                      matchQualifier: ArtsdataClient::MATCH_QUALIFIER_DATE_RANGE_URI
                    }
    assert_includes conditions,
                    {
                      matchType: "property",
                      propertyId: ArtsdataClient::LOCATION_NAME_PROPERTY_ID,
                      propertyValue: ["Toronto"],
                      required: true,
                      matchQuantifier: "any"
                    }
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

  ORGANIZER_NAME_PROPERTY_ID = ArtsdataClient::ORGANIZER_NAME_PROPERTY_ID
  PERFORMER_NAME_PROPERTY_ID = ArtsdataClient::PERFORMER_NAME_PROPERTY_ID

  ORGANIZER_OR_PERFORMER_PROPERTY_ID  = ArtsdataClient::ORGANIZER_OR_PERFORMER_PROPERTY_ID

  AGENT_PROPERTY_IDS = [
    ORGANIZER_NAME_PROPERTY_ID, PERFORMER_NAME_PROPERTY_ID,
    ORGANIZER_OR_PERFORMER_PROPERTY_ID
  ].freeze

  SEARCH_EVENTS_DEFAULT_PARAMS = {
    startDateFrom: nil, startDateTo: nil, places: [], artists: [],
    organizations: [], types: [], language: "en", limit: 25
  }.freeze

  def search_events_with_captured_match_payload(**params)
    client = ArtsdataClient.new
    captured = {}

    record_and_respond = lambda do |payload, **options|
      captured[options[:route]] = payload
      { "results" => [] }
    end

    client.stub(:execute_reconciliation_query, record_and_respond) do
      client.search_events(**SEARCH_EVENTS_DEFAULT_PARAMS.merge(params))
    end

    captured.fetch("match")
  end

  # The agent (artist/organization) conditions of a match payload, in the order they were added.
  def agent_conditions(payload)
    payload[:queries].first[:conditions].select { |condition| AGENT_PROPERTY_IDS.include?(condition[:propertyId]) }
  end

  def agent_condition(property_id, property_value)
    {
      matchType: "property",
      propertyId: property_id,
      propertyValue: property_value,
      required: true,
      matchQuantifier: "any"
    }
  end

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
