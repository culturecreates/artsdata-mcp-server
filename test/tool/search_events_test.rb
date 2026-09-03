require "test_helper"
require "minitest/mock"
require "json_schemer"

class SearchEventsTest < ActiveSupport::TestCase
  SCHEMA_PATH = Rails.root.join("app", "schema", "search_events_request_schema.json")

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
end
