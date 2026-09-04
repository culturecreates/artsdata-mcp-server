require "test_helper"
require "minitest/mock"
require "json_schemer"

class SearchEntitiesTest < ActiveSupport::TestCase
  REQUEST_SCHEMA_PATH = Rails.root.join("app", "schema", "search_entities_request_schema.json")
  RESPONSE_SCHEMA_PATH = Rails.root.join("app", "schema", "search_entities_response_schema.json")
  SEARCH_RESULT_FIXTURE_PATH = Rails.root.join("test", "fixtures", "search_entities_results.json")
  RECON_MATCH_FIXTURE_PATH = Rails.root.join("test", "fixtures", "search_entities_recon_match_results.json")

  FULL_PARAMS = {
    query: "festival",
    types: ["Organization", "Place"],
    language: "fr",
    limit: 10
  }.freeze

  # What SearchEntities.call passes to ArtsdataClient#search_items when only `query` is given.
  # Note the tool's `language:` keyword is forwarded as the client's `lang:` keyword.
  CLIENT_DEFAULT_ARGS = {
    # Query is requiredQuery is required
    query: "festival",
    types: [],
    lang: "en",
    limit: 50
  }.freeze

  # A raw "match" reconciliation response, shaped like what the Artsdata reconciliation
  # service returns for the `match` route. Each candidate carries the `score`, `match` and
  # `features` keys that ArtsdataClient#format_search_results is expected to strip, so driving
  # the tool from data in this shape - rather than from an already-formatted result - keeps the
  # real search_items -> format_search_results pipeline under test, with only the network call
  # itself replaced.
  MATCH_RESPONSE = JSON.parse(File.read(RECON_MATCH_FIXTURE_PATH))

  MATCH_RESPONSE_WITH_NO_CANDIDATES = { "results" => [{ "candidates" => [] }] }.freeze

  # ---------------------------------------------------------------------------------------
  # Request schema
  # ---------------------------------------------------------------------------------------

  # Exercises the request schema itself, independent of the Ruby method: a fully populated,
  # in-range payload should validate; missing, out-of-range or unknown values should not.
  test "request schema validates supported payloads" do
    schema = JSONSchemer.schema(REQUEST_SCHEMA_PATH)

    valid_payload = {
      "query" => "festival",
      "types" => ["Organization", "Place"],
      "language" => "fr",
      "limit" => 10
    }

    assert_empty schema.validate(valid_payload).to_a,
                 "a fully populated, in-range payload should satisfy the schema"
    assert_empty schema.validate({ "query" => "festival" }).to_a,
                 "query alone should satisfy the schema, since every other property is optional"
    assert_empty schema.validate(valid_payload.merge("types" => [])).to_a,
                 "an empty types array is explicitly allowed"
    assert_empty schema.validate(valid_payload.merge("limit" => 1)).to_a,
                 "limit at the schema minimum (1) should validate"
    assert_empty schema.validate(valid_payload.merge("limit" => 50)).to_a,
                 "limit at the schema maximum (50) should validate"
  end

  test "request schema rejects invalid payloads" do
    schema = JSONSchemer.schema(REQUEST_SCHEMA_PATH)
    valid_payload = { "query" => "festival", "types" => ["Person"], "language" => "en", "limit" => 5 }

    refute_empty schema.validate({}).to_a,
                 "query is required, so an empty payload should fail validation"
    refute_empty schema.validate(valid_payload.merge("query" => "")).to_a,
                 "query has minLength 1, so an empty string should fail validation"
    refute_empty schema.validate(valid_payload.merge("query" => 123)).to_a,
                 "query must be a string"
    refute_empty schema.validate(valid_payload.merge("types" => ["Event"])).to_a,
                 "types is restricted to the Place/Person/Organization enum"
    refute_empty schema.validate(valid_payload.merge("types" => ["Person", "Person"])).to_a,
                 "types has uniqueItems: true, so duplicates should fail validation"
    refute_empty schema.validate(valid_payload.merge("types" => "Person")).to_a,
                 "types must be an array, not a bare string"
    refute_empty schema.validate(valid_payload.merge("language" => "de")).to_a,
                 "language is restricted to en/fr"
    refute_empty schema.validate(valid_payload.merge("limit" => 0)).to_a,
                 "limit below the schema minimum (1) should fail validation"
    refute_empty schema.validate(valid_payload.merge("limit" => 51)).to_a,
                 "limit above the schema maximum (50) should fail validation"
    refute_empty schema.validate(valid_payload.merge("limit" => 2.5)).to_a,
                 "limit must be an integer"
    refute_empty schema.validate(valid_payload.merge("unknownField" => "x")).to_a,
                 "additionalProperties: false should reject unrecognized fields"
  end

  test "the tool exposes the request and response JSON schema files as its MCP schemas" do
    assert_equal JSON.parse(File.read(REQUEST_SCHEMA_PATH), symbolize_names: true),
                 SearchEntities::REQUEST_SCHEMA
    assert_equal JSON.parse(File.read(RESPONSE_SCHEMA_PATH), symbolize_names: true),
                 SearchEntities::RESPONSE_SCHEMA
    assert_equal "search_entities", SearchEntities.tool_name
  end

  # ---------------------------------------------------------------------------------------
  # Response schema
  # ---------------------------------------------------------------------------------------

  test "response schema accepts the search_entities fixture and rejects malformed results" do
    schema = JSONSchemer.schema(RESPONSE_SCHEMA_PATH)
    fixture_results = JSON.parse(File.read(SEARCH_RESULT_FIXTURE_PATH))

    assert_empty schema.validate({ "results" => fixture_results }).to_a,
                 "the checked-in fixture should satisfy the response schema"
    assert_empty schema.validate({ "results" => [] }).to_a,
                 "an empty results array is a valid response"

    refute_empty schema.validate({}).to_a,
                 "results is required"
    refute_empty schema.validate({ "results" => fixture_results, "extra" => 1 }).to_a,
                 "additionalProperties: false at the top level should reject unrecognized fields"

    %w[id name type uri].each do |required_key|
      without_key = fixture_results.first.except(required_key)
      refute_empty schema.validate({ "results" => [without_key] }).to_a,
                   "a result without `#{required_key}` should fail validation"
    end

    with_unknown_key = fixture_results.first.merge("score" => 90)
    refute_empty schema.validate({ "results" => [with_unknown_key] }).to_a,
                 "a result carrying an unrecognized key should fail validation"

    with_bad_type = fixture_results.first.merge("type" => [{ "id" => "http://schema.org/Organization" }])
    refute_empty schema.validate({ "results" => [with_bad_type] }).to_a,
                 "each type entry requires both id and name"
  end

  # ---------------------------------------------------------------------------------------
  # SearchEntities.call -> ArtsdataClient#search_items (client mocked)
  # ---------------------------------------------------------------------------------------

  test "call forwards every supported parameter to ArtsdataClient#search_items" do
    fixture_results = JSON.parse(File.read(SEARCH_RESULT_FIXTURE_PATH))
    mock_client = Minitest::Mock.new
    mock_client.expect(:search_items, fixture_results, [],
                       query: "festival", types: ["Organization", "Place"], lang: "fr", limit: 10)

    response = ArtsdataClient.stub(:new, mock_client) do
      SearchEntities.call(**FULL_PARAMS)
    end
    mock_client.verify

    assert_equal({ results: fixture_results }, response.structured_content)
    assert_equal({ "results" => fixture_results }, JSON.parse(response.content.first[:text]),
                 "the text content should be the JSON serialization of the structured content")
    assert_equal "text", response.content.first[:type]
  end

  test "call falls back to the Ruby defaults when optional params are omitted" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:search_items, [], [], **CLIENT_DEFAULT_ARGS)

    response = ArtsdataClient.stub(:new, mock_client) do
      SearchEntities.call(query: "festival")
    end
    mock_client.verify

    assert_equal({ results: [] }, response.structured_content)
  end

  test "call requires a query" do
    assert_raises(ArgumentError) { SearchEntities.call }
  end

  # ---------------------------------------------------------------------------------------
  # SearchEntities.call end to end, with only the reconciliation HTTP call stubbed
  # ---------------------------------------------------------------------------------------

  # The tests below stub only execute_reconciliation_query - the method that actually talks to
  # the reconciliation service - so SearchEntities.call runs its real
  # search_items -> format_search_results pipeline against recon-service-shaped responses.
  # That's what lets them catch a regression in the reconciliation query shape or in the
  # formatting logic, not just in SearchEntities.call itself.

  test "call queries the match route and its response satisfies the response schema" do
    captured = {}
    response = call_search_entities_with_stubbed_reconciliation(
      match_response: MATCH_RESPONSE, captured: captured, **FULL_PARAMS
    )

    assert_equal "match", captured[:route]
    assert_equal "fr", captured[:lang]

    query = captured[:payload][:queries].first
    assert_equal 10, query[:limit]
    assert_equal "festival", query[:conditions].first[:propertyValue]

    wire_response = JSON.parse(response.content.first[:text])
    assert_equal wire_response, deep_stringify(response.structured_content)

    errors = JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
    assert_empty errors, "response schema validation errors: #{errors.map { |e| e['error'] }.join('; ')}"

    results = wire_response.fetch("results")
    assert_equal %w[K11-23 K11-24], results.map { |r| r["id"] }
    assert_equal "http://kg.artsdata.ca/resource/K11-23", results.first["uri"]
    results.each do |result|
      %w[score match features].each do |stripped|
        refute result.key?(stripped), "`#{stripped}` should be stripped from candidate `#{result['id']}`"
      end
    end
  end

  test "call returns an empty, schema-valid result when the match route has no candidates" do
    response = call_search_entities_with_stubbed_reconciliation(
      match_response: MATCH_RESPONSE_WITH_NO_CANDIDATES, query: "nothing-matches"
    )

    wire_response = JSON.parse(response.content.first[:text])
    assert_equal({ "results" => [] }, wire_response)

    errors = JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
    assert_empty errors, "response schema validation errors: #{errors.map { |e| e['error'] }.join('; ')}"
  end

  test "call returns an empty, schema-valid result when the reconciliation service is unavailable" do
    # execute_reconciliation_query swallows network/HTTP errors and returns {}.
    response = call_search_entities_with_stubbed_reconciliation(match_response: {}, query: "festival")

    wire_response = JSON.parse(response.content.first[:text])
    assert_equal({ "results" => [] }, wire_response)
    assert_empty JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
  end

  private

  # Stubs execute_reconciliation_query on a real ArtsdataClient instance (and makes
  # ArtsdataClient.new return that instance), so SearchEntities.call exercises the real client
  # implementation end to end, with only the network call replaced by canned data. Anything
  # passed to the reconciliation service is recorded in `captured`.
  def call_search_entities_with_stubbed_reconciliation(match_response:, captured: {}, **params)
    real_client = ArtsdataClient.new

    record_and_respond = lambda do |payload, **options|
      captured[:payload] = payload
      captured[:route] = options[:route]
      captured[:lang] = options[:lang]
      match_response
    end

    real_client.stub(:execute_reconciliation_query, record_and_respond) do
      ArtsdataClient.stub(:new, real_client) do
        SearchEntities.call(**params)
      end
    end
  end

  def deep_stringify(value)
    JSON.parse(JSON.generate(value))
  end
end
