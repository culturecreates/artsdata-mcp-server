require "test_helper"
require "minitest/mock"
require "json_schemer"

class GetEntityTest < ActiveSupport::TestCase
  REQUEST_SCHEMA_PATH = Rails.root.join("app", "schema", "get_entity_request_schema.json")
  RESPONSE_SCHEMA_PATH = Rails.root.join("app", "schema", "get_entity_response_schema.json")

  ENTITY_URI = "http://kg.artsdata.ca/resource/K11-23".freeze
  ENTITY_ID = "K11-23".freeze

  # What ArtsdataClient#get_entity_by_extend_service hands back: an already-formatted entity.
  FORMATTED_ENTITY = {
    "id" => ENTITY_ID,
    "uri" => ENTITY_URI,
    "types" => [{ "uri" => "http://schema.org/Organization", "label" => "Organization" }],
    "name" => [{ "value" => "Test Organization", "language" => "en" }]
  }.freeze

  # A raw "extend" reconciliation response, using the property ids get_entity_by_extend_service
  # asks the reconciliation service for. Driving the tool from data in this shape - rather than
  # from an already-formatted hash - keeps the real
  # get_entity_by_extend_service -> format_get_entity_results pipeline under test, with only the
  # network call itself replaced.
  EXTEND_RESPONSE = {
    "rows" => [
      {
        "id" => ENTITY_ID,
        "properties" => [
          { "id" => "name", "values" => [{ "str" => "Test Organization", "lang" => "en" }] },
          { "id" => "type", "values" => [{ "id" => "http://schema.org/Organization" }] },
          { "id" => "disambiguatingDescription",
            "values" => [{ "str" => "A test organization", "lang" => "en" }] },
          { "id" => "startDate", "values" => [{ "str" => "2026-01-01" }] },
          { "id" => "endDate", "values" => [{ "str" => "2026-01-02" }] },
          { "id" => "url", "values" => [{ "str" => "http://example.com/organization" }] },
          { "id" => "sameAs", "values" => [{ "id" => "http://www.wikidata.org/entity/Q1" }] },
          { "id" => "eventStatus", "values" => [{ "id" => "http://schema.org/EventScheduled" }] },
          { "id" => "eventAttendanceMode",
            "values" => [{ "id" => "http://schema.org/OfflineEventAttendanceMode" }] },
          { "id" => "location",
            "values" => [{ "id" => "K11-99",
                           "properties" => [{ "id" => "name",
                                              "values" => [{ "str" => "Test Place" },
                                                           { "str" => "Test Place", "lang" => "en" }] }] }] },
          { "id" => "performer",
            "values" => [{ "id" => "K11-98",
                           "properties" => [{ "id" => "name",
                                              "values" => [{ "str" => "Test Performer" }] }] }] },
          { "id" => "organizer", "values" => [{ "id" => "K11-97" }] },
          { "id" => "offers", "values" => [{ "id" => "http://example.com/tickets" }] }
        ]
      }
    ]
  }.freeze

  test "call returns entity details for a valid uri instead of raising" do
    uri = "http://kg.artsdata.ca/resource/K11-23"
    id = uri.split('/').last
    response = GetEntity.call(uri: uri)

    assert_equal id, response.structured_content&.fetch("id", nil)
  rescue ArgumentError => e
    flunk "GetEntity.call raised #{e.class}: #{e.message} " \
          "(app/tool/get_entity.rb calls ArtsdataClient#get_entity_by_extend_service with `uri:`, " \
          "but that method only accepts `ids:`)"
  end

  # Exercises the request schema itself, independent of the Ruby method.
  test "request schema requires a uri and rejects anything else" do
    schema = JSONSchemer.schema(REQUEST_SCHEMA_PATH)

    assert_empty schema.validate({ "uri" => ENTITY_URI }).to_a,
                 "an Artsdata entity uri should satisfy the schema"
    refute_empty schema.validate({}).to_a,
                 "uri is required, so an empty payload should fail validation"
    refute_empty schema.validate({ "uri" => 123 }).to_a,
                 "uri must be a string"
    refute_empty schema.validate({ "uri" => ENTITY_URI, "unknownField" => "x" }).to_a,
                 "additionalProperties: false should reject unrecognized fields"
  end

  test "call returns the entity as structured content and as matching JSON text content" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:get_entity_by_extend_service, [FORMATTED_ENTITY], [], ids: [ENTITY_ID])

    response = ArtsdataClient.stub(:new, mock_client) do
      GetEntity.call(uri: ENTITY_URI)
    end
    mock_client.verify

    assert_equal FORMATTED_ENTITY, response.structured_content
    assert_equal FORMATTED_ENTITY, JSON.parse(response.content.first[:text]),
                 "the text content should be the JSON serialization of the structured content"
  end


  # The tests below stub only execute_reconciliation_query - the method that actually talks to
  # the reconciliation service - so GetEntity.call runs its real
  # get_entity_by_extend_service -> format_get_entity_results pipeline against a
  # recon-service-shaped response. That is what lets them catch a regression in the
  # reconciliation query shape or in the formatting logic, not just in GetEntity.call itself.

  test "call queries the extend route with the bare id and satisfies the response schema" do
    captured = {}
    response = call_get_entity_with_stubbed_reconciliation(
      extend_response: EXTEND_RESPONSE, captured: captured
    )

    assert_equal "extend", captured[:route]
    assert_equal [ENTITY_ID], captured[:payload][:ids]

    wire_response = JSON.parse(response.content.first[:text])
    assert_equal ENTITY_ID, wire_response.fetch("id")
    assert_equal ENTITY_URI, wire_response.fetch("uri")

    errors = JSONSchemer.schema(RESPONSE_SCHEMA_PATH).validate(wire_response).to_a
    assert_empty errors,
                 "response schema validation errors: #{errors.map { |e| e['error'] }.join('; ')}"
  end

 test "call resolves performer and location to id, uri and name, and tolerates a missing name" do
    captured = {}
    response = call_get_entity_with_stubbed_reconciliation(
      extend_response: EXTEND_RESPONSE, captured: captured
    )

    expanded = captured[:payload][:properties]
      .select { |property| property[:expand] }
      .map { |property| property[:id] }
    assert_equal %w[location performer organizer].sort, expanded.sort,
                 "performer, organizer and location must be requested with expand: true"

    wire_response = JSON.parse(response.content.first[:text])

    assert_equal [{ "id" => "K11-98", "uri" => "http://kg.artsdata.ca/resource/K11-98",
                    "name" => "Test Performer" }], wire_response.fetch("performer")
    assert_equal [{ "id" => "K11-99", "uri" => "http://kg.artsdata.ca/resource/K11-99",
                    "name" => "Test Place" }], wire_response.fetch("location")
    assert_equal [{ "id" => "K11-97", "uri" => "http://kg.artsdata.ca/resource/K11-97" }],
                 wire_response.fetch("organizer"),
                 "a reference without a nested name should still carry its id and uri"
  end


  private

  # Stubs execute_reconciliation_query on a real ArtsdataClient instance (and makes
  # ArtsdataClient.new return that instance), so GetEntity.call exercises the real client
  # implementation end to end, with only the network call replaced by canned data. Anything
  # passed to the reconciliation service is recorded in `captured`.
  def call_get_entity_with_stubbed_reconciliation(extend_response:, captured: {})
    real_client = ArtsdataClient.new

    record_and_respond = lambda do |payload, **options|
      captured[:payload] = payload
      captured[:route] = options[:route]
      extend_response
    end

    real_client.stub(:execute_reconciliation_query, record_and_respond) do
      ArtsdataClient.stub(:new, real_client) do
        GetEntity.call(uri: ENTITY_URI)
      end
    end
  end
end
