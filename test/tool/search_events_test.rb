require "test_helper"
require "minitest/mock"
require "json_schemer"

class SearchEventsTest < ActiveSupport::TestCase
  SCHEMA_PATH = Rails.root.join("app", "schema", "search_events_request_schema.json")
  RESPONSE_SCHEMA_PATH = Rails.root.join("app", "schema", "search_events_response_schema.json")

  FULL_PARAMS = {
    startDateFrom: "2026-01-01",
    startDateTo: "2026-01-31",
    places: ["Toronto"],
    artists: ["Jane Doe"],
    organizations: ["Some Org"],
    types: ["MusicEvent"],
    language: "fr",
    limit: 10
  }.freeze

  DEFAULT_PARAMS = {
    startDateFrom: nil,
    startDateTo: nil,
    places: [],
    artists: [],
    organizations: [],
    types: [],
    language: "en",
    limit: 25
  }.freeze

  # A "match" reconciliation response with one candidate, and one with none - the two shapes
  # ArtsdataClient#search_events branches on.
  MATCH_RESPONSE_WITH_ONE_CANDIDATE = {
    "results" => [
      { "candidates" => [{ "id" => "K1-1" }] }
    ]
  }.freeze

  MATCH_RESPONSE_WITH_NO_CANDIDATES = { "results" => [] }.freeze

  # A raw "extend" reconciliation response row, using the exact property ids
  # get_entity_by_extend_service (app/services/artsdata_client.rb) requests, each given at
  # least one value. Driving format_get_entity_results from data shaped like this - rather than
  # from an already-formatted result hash - means a change to the recon query's requested
  # properties, or to how format_get_entity_results reads them, shows up here.
  EXTEND_RESPONSE = {
    "rows" => [
      {
        "id" => "K1-1",
        "properties" => [
          { "id" => "name", "values" => [{ "str" => "Test Event", "lang" => "en" }] },
          { "id" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            "values" => [{ "id" => "http://schema.org/MusicEvent", "str" => "MusicEvent" }] },
          { "id" => "startDate", "values" => [{ "str" => "2026-01-01" }] },
          { "id" => "endDate", "values" => [{ "str" => "2026-01-02" }] },
          { "id" => "disambiguatingDescription", "values" => [{ "str" => "A test event description", "lang" => "en" }] },
          { "id" => "additionalType", "values" => [{ "id" => "http://schema.org/Festival" }] },
          { "id" => "url", "values" => [{ "str" => "http://example.com/event" }] },
          { "id" => "sameAs", "values" => [{ "id" => "http://wikidata.org/Q1" }] },
          { "id" => "eventStatus", "values" => [{ "id" => "http://schema.org/EventScheduled" }] },
          { "id" => "eventAttendanceMode", "values" => [{ "id" => "http://schema.org/OfflineEventAttendanceMode" }] },
          { "id" => "location",
            "values" => [{ "id" => "Place1",
                           "properties" => [{ "id" => "name",
                                              "values" => [{ "str" => "Test Place" },
                                                           { "str" => "Test Place", "lang" => "en" }] }] }] },
          { "id" => "performer",
            "values" => [{ "id" => "Person1",
                           "properties" => [{ "id" => "name",
                                              "values" => [{ "str" => "Test Performer" }] }] }] },
          { "id" => "organizer",
            "values" => [{ "id" => "Organization1",
                           "properties" => [{ "id" => "name",
                                              "values" => [{ "str" => "Test Organization" }] }] }] }
        ]
      }
    ]
  }.freeze

  # Exercises the request schema itself, independent of the Ruby method: a fully populated,
  # in-range payload should validate; out-of-range or unknown values should not.
  test "request schema validates supported payloads and rejects invalid ones" do
    schema = JSONSchemer.schema(SCHEMA_PATH)

    valid_payload = {
      "startDateFrom" => "2026-01-01",
      "startDateTo" => "2026-01-31",
      "places" => ["Toronto"],
      "artists" => ["Jane Doe"],
      "organizations" => ["Some Org"],
      "types" => ["MusicEvent"],
      "language" => "fr",
      "limit" => 10
    }

    assert_empty schema.validate(valid_payload).to_a,
                 "a fully populated, in-range payload should satisfy the schema"
    assert_empty schema.validate({}).to_a,
                 "an empty payload should satisfy the schema, since every property is optional"
    assert_empty schema.validate(
      valid_payload.merge("artists" => ["Jane Doe", "http://kg.artsdata.ca/resource/K1-1"])
    ).to_a, "the artists list may mix labels and URIs"

    refute_empty schema.validate(valid_payload.merge("limit" => 0)).to_a,
                 "limit below the schema minimum (1) should fail validation"
    refute_empty schema.validate(valid_payload.merge("limit" => 51)).to_a,
                 "limit above the schema maximum (50) should fail validation"
    refute_empty schema.validate(valid_payload.merge("places" => "Toronto")).to_a,
                 "places must be an array, not a bare string"
    refute_empty schema.validate(valid_payload.merge("unknownField" => "x")).to_a,
                 "additionalProperties: false should reject unrecognized fields"
  end

  test "call forwards every supported parameter to ArtsdataClient#search_events" do
    fixture_result = [{ "id" => "K1-1", "uri" => "http://kg.artsdata.ca/resource/K1-1" }]
    mock_client = Minitest::Mock.new
    mock_client.expect(:search_events, fixture_result, [], **FULL_PARAMS)

    response = ArtsdataClient.stub :new, mock_client do
      SearchEvents.call(**FULL_PARAMS)
    end
    mock_client.verify

    assert_equal({ results: fixture_result }, response.structured_content)
  end

  test "call falls back to the schema defaults when optional params are omitted" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:search_events, [], [], **DEFAULT_PARAMS)

    response = ArtsdataClient.stub :new, mock_client do
      SearchEvents.call
    end
    mock_client.verify

    assert_equal({ results: [] }, response.structured_content)
  end

  test "call defaults every unspecified parameter when only one filter is given" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:search_events, [], [], **DEFAULT_PARAMS.merge(places: ["Montreal"]))

    response = ArtsdataClient.stub :new, mock_client do
      SearchEvents.call(places: ["Montreal"])
    end
    mock_client.verify

    assert_equal({ results: [] }, response.structured_content)
  end

  # The tests below stub only execute_reconciliation_query - the method that actually talks to
  # the reconciliation service - so SearchEvents.call runs its real
  # search_events -> get_entity_by_extend_service -> format_get_entity_results pipeline against
  # recon-service-shaped responses. That's what lets these catch a regression in the SPARQL/
  # reconciliation query shape or in the formatting logic, not just in SearchEvents.call itself.

  test "call's response satisfies the response schema for a realistic match+extend result" do
    response = call_search_events_with_stubbed_reconciliation(
      match_response: MATCH_RESPONSE_WITH_ONE_CANDIDATE,
      extend_response: EXTEND_RESPONSE,
      **FULL_PARAMS
    )

    wire_response = JSON.parse(response.content.first[:text])
    errors = JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
    assert_empty errors, "response schema validation errors: #{errors.map { |e| e["error"] }.join("; ")}"
  end

 test "call resolves performer, organizer and location to id, uri and name" do
    captured = {}
    response = call_search_events_with_stubbed_reconciliation(
      match_response: MATCH_RESPONSE_WITH_ONE_CANDIDATE,
      extend_response: EXTEND_RESPONSE,
      captured: captured,
      **FULL_PARAMS
    )

    expanded = captured[:extend_payload][:properties]
      .select { |property| property[:expand] }
      .map { |property| property[:id] }
    assert_equal %w[location performer organizer].sort, expanded.sort,
                 "performer, organizer and location must be requested with expand: true"

    event = JSON.parse(response.content.first[:text]).fetch("results").first

    assert_equal [{ "id" => "Person1", "uri" => "http://kg.artsdata.ca/resource/Person1",
                    "name" => "Test Performer" }], event.fetch("performer")
    assert_equal [{ "id" => "Organization1", "uri" => "http://kg.artsdata.ca/resource/Organization1",
                    "name" => "Test Organization" }], event.fetch("organizer")
    assert_equal [{ "id" => "Place1", "uri" => "http://kg.artsdata.ca/resource/Place1",
                    "name" => "Test Place" }], event.fetch("location")
  end

  test "call's response satisfies the response schema, and never queries extend, when match has no candidates" do
    response = call_search_events_with_stubbed_reconciliation(
      match_response: MATCH_RESPONSE_WITH_NO_CANDIDATES,
      **DEFAULT_PARAMS
    )

    wire_response = JSON.parse(response.content.first[:text])
    assert_equal({ "results" => [] }, wire_response)

    errors = JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
    assert_empty errors, "response schema validation errors: #{errors.map { |e| e["error"] }.join("; ")}"
  end

  private

  # Stubs execute_reconciliation_query on a real ArtsdataClient instance (and makes
  # ArtsdataClient.new return that instance), so SearchEvents.call exercises its real
  # implementation end to end, with only the network call itself replaced by canned data.
  def call_search_events_with_stubbed_reconciliation(match_response:, extend_response: nil, captured: {}, **params)
    real_client = ArtsdataClient.new

    respond_to_route = lambda do |payload, **options|
      next match_response if options[:route] == "match"

      captured[:extend_payload] = payload
      extend_response || flunk("execute_reconciliation_query was called with route: 'extend', but no extend_response was given")
    end

    real_client.stub(:execute_reconciliation_query, respond_to_route) do
      ArtsdataClient.stub(:new, real_client) do
        SearchEvents.call(**params)
      end
    end
  end
end
