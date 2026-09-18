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
        organizations: [], has_event_type_concept: [], language: "en", limit: 25
      )
    end

    assert_equal expected_result, result
  end


  test "search_events matches artist URIs on the organizer and performer properties" do
    uris = ["http://kg.artsdata.ca/resource/K1-1", "http://kg.artsdata.ca/resource/K1-2"]
    payload = search_events_with_captured_match_payload(artists: uris)

    assert_equal [
                   agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, uris)
                 ],
                 add_conditions(payload),
                 "every artist URI belongs in one condition on schema:organizer|schema:performer, matched with 'any'"
  end

  test "search_events merges organizations with artists from URIs" do
    artist_uri = "http://kg.artsdata.ca/resource/K1-1"
    org_uri = "http://kg.artsdata.ca/resource/K2-2"
    payload = search_events_with_captured_match_payload(
      artists: [artist_uri],
      organizations: [org_uri]
    )

    assert_equal [agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, [artist_uri, org_uri])],
                 add_conditions(payload)
  end

  test "search_events adds no agent conditions when artists and organizations are empty" do
    payload = search_events_with_captured_match_payload(artists: [], organizations: [])

    assert_empty add_conditions(payload),
                 "an empty artists/organizations list should not add any agent condition"
  end

  test "search_events leaves the other filter conditions untouched when filtering by artist URI" do
    payload = search_events_with_captured_match_payload(
      startDateFrom: "2026-01-01",
      startDateTo: "2026-01-31",
      places: ["http://kg.artsdata.ca/resource/KP-1"],
      artists: ["http://kg.artsdata.ca/resource/KA-1"]
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
                      propertyId: ArtsdataClient::LOCATION_PROPERTY_ID,
                      propertyValue: ["http://kg.artsdata.ca/resource/KP-1"],
                      required: true,
                      matchQuantifier: "any"
                    }
  end

  test "search_events puts several place URIs in one condition, matched with 'any'" do
    uris = ["http://kg.artsdata.ca/resource/K5-69", "http://kg.artsdata.ca/resource/K5-72"]
    payload = search_events_with_captured_match_payload(places: uris)

    location_conditions = payload[:queries].first[:conditions]
                                           .select { |c| c[:propertyId] == ArtsdataClient::LOCATION_PROPERTY_ID }

    assert_equal [
                   {
                     matchType: "property",
                     propertyId: ArtsdataClient::LOCATION_PROPERTY_ID,
                     propertyValue: uris,
                     required: true,
                     matchQuantifier: "any"
                   }
                 ], location_conditions
  end

  test "search_events adds no place condition when places is empty" do
    payload = search_events_with_captured_match_payload(places: [])

    assert_empty payload[:queries].first[:conditions]
                                  .select { |c| c[:propertyId] == ArtsdataClient::LOCATION_PROPERTY_ID },
                 "an empty places list should not add a location condition"
  end

  test "search_events matches event type concept URIs on ado:hasEventTypeConcept" do
    uri = "http://kg.artsdata.ca/resource/ClassicalMusicPerformance"
    payload = search_events_with_captured_match_payload(has_event_type_concept: [uri])

    assert_equal [
                   {
                     matchType: "property",
                     propertyId: ArtsdataClient::HAS_EVENT_TYPE_CONCEPT_PROPERTY_ID,
                     propertyValue: [uri],
                     required: true
                   }
                 ], event_type_conditions(payload),
                 "the condition carries no matchQuantifier or matchQualifier"
  end

  test "search_events puts several event type concept URIs in one condition" do
    uris = ["http://kg.artsdata.ca/resource/ClassicalMusicPerformance",
            "http://kg.artsdata.ca/resource/CircusPerformance"]
    payload = search_events_with_captured_match_payload(has_event_type_concept: uris)

    assert_equal [uris], event_type_conditions(payload).map { |c| c[:propertyValue] }
  end

  test "search_events adds no event type condition when has_event_type_concept is empty" do
    assert_empty event_type_conditions(search_events_with_captured_match_payload(has_event_type_concept: [])),
                 "an empty has_event_type_concept list should not add a condition"
  end

  test "search_events always queries type schema:Event, whatever the event type concepts are" do
    payload = search_events_with_captured_match_payload(
      has_event_type_concept: ["http://kg.artsdata.ca/resource/ClassicalMusicPerformance"]
    )
    query = payload[:queries].first

    assert_equal "http://schema.org/Event", query[:type]
    assert_empty query[:conditions].select { |c| c[:propertyId] == ArtsdataClient::RDF_TYPE_PROPERTY_ID },
                 "event types are not matched on rdf:type"
  end

  test "search_events builds one condition per filter, in a stable order" do
    payload = search_events_with_captured_match_payload(
      startDateFrom: "2026-01-01",
      startDateTo: "2026-01-31",
      places: ["http://kg.artsdata.ca/resource/K5-69"],
      artists: ["http://kg.artsdata.ca/resource/K2-6574"],
      organizations: ["http://kg.artsdata.ca/resource/K5-72"],
      has_event_type_concept: ["http://kg.artsdata.ca/resource/ClassicalMusicPerformance"]
    )

    assert_equal [
                   ArtsdataClient::START_DATE_PROPERTY_ID,
                   ArtsdataClient::LOCATION_PROPERTY_ID,
                   ORGANIZER_OR_PERFORMER_PROPERTY_ID,
                   ArtsdataClient::HAS_EVENT_TYPE_CONCEPT_PROPERTY_ID
                 ], payload[:queries].first[:conditions].map { |c| c[:propertyId] }
  end

  test "search_events sends no conditions at all when no filter is given" do
    assert_empty search_events_with_captured_match_payload[:queries].first[:conditions],
                 "an unfiltered search should send an empty condition list, not a nil entry"
  end

  test "format_get_entity_results returns an empty array when given no rows" do
    assert_equal [], ArtsdataClient.new.format_get_entity_results([])
  end

  test "format_get_entity_results prefixes only has_event_type_concept values, not other properties" do
    rows = [
      {
        "id" => "K1-1",
        "properties" => [
          { "id" => "hasEventTypeConcept",
            "values" => [{ "id" => "MusicPerformance" },
                         { "str" => "Event" },
                         { "id" => "http://kg.artsdata.ca/resource/TheatrePerformance" }] },
          { "id" => "sameAs", "values" => [{ "id" => "Q123" }] },
          { "id" => "eventStatus", "values" => [{ "id" => "EventScheduled" }] },
          { "id" => "offers", "values" => [{ "id" => "offer-1" }] }
        ]
      }
    ]

    result = ArtsdataClient.new.format_get_entity_results(rows).first

    assert_equal [
      "http://kg.artsdata.ca/resource/MusicPerformance",
      "http://kg.artsdata.ca/resource/Event",
      "http://kg.artsdata.ca/resource/TheatrePerformance"
    ], result["has_event_type_concept"]

    assert_equal ["Q123"], result["same_as"]
    assert_equal "EventScheduled", result["event_status"]
    assert_equal ["offer-1"], result.dig("additional_properties", 0, "values")
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

 test "search_items sends a single type as the query type, verbatim" do
    captured = {}
    search_items_with_stubbed_reconciliation(
      match_response: { "results" => [] }, captured: captured,
      query: "festival", types: ["http://dbpedia.org/ontology/Agent"], lang: "en", limit: 25
    )

    query = captured[:payload][:queries].first
    assert_equal "http://dbpedia.org/ontology/Agent", query[:type]
    assert_equal ["name"], query[:conditions].map { |c| c[:matchType] },
                 "a single type needs no rdf:type condition"
  end

  test "search_items matches several types with an rdf:type condition and no query type" do
    captured = {}
    types = ["http://schema.org/Person", "http://www.w3.org/2004/02/skos/core#Concept"]
    search_items_with_stubbed_reconciliation(
      match_response: { "results" => [] }, captured: captured,
      query: "festival", types: types, lang: "en", limit: 25
    )

    query = captured[:payload][:queries].first
    assert_nil query[:type]
    assert_includes query[:conditions],
                    {
                      matchType: "property",
                      propertyId: ArtsdataClient::RDF_TYPE_PROPERTY_ID,
                      propertyValue: types,
                      required: true,
                      matchQuantifier: "any"
                    }
  end

  test "search_items narrows the search to a concept scheme with a skos:inScheme condition" do
    captured = {}
    scheme = "http://kg.artsdata.ca/resource/ArtsdataEventTypes"
    search_items_with_stubbed_reconciliation(
      match_response: { "results" => [] }, captured: captured,
      query: "exhibition", types: ["http://www.w3.org/2004/02/skos/core#Concept"],
      in_scheme: [scheme], lang: "en", limit: 25
    )

    conditions = captured[:payload][:queries].first[:conditions]

    assert_includes conditions,
                    {
                      matchType: "property",
                      propertyId: ArtsdataClient::IN_SCHEME_PROPERTY_ID,
                      propertyValue: [scheme],
                      required: true
                    }
    assert_equal "http://www.w3.org/2004/02/skos/core#inScheme", ArtsdataClient::IN_SCHEME_PROPERTY_ID
  end

  test "search_items adds no scheme condition when in_scheme is empty" do
    captured = {}
    search_items_with_stubbed_reconciliation(
      match_response: { "results" => [] }, captured: captured,
      query: "festival", types: [], in_scheme: [], lang: "en", limit: 25
    )

    assert_equal ["name"], captured[:payload][:queries].first[:conditions].map { |c| c[:matchType] },
                 "an empty in_scheme list should not add a condition"
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

  ORGANIZER_OR_PERFORMER_PROPERTY_ID  = ArtsdataClient::ORGANIZER_OR_PERFORMER_PROPERTY_ID

  SEARCH_EVENTS_DEFAULT_PARAMS = {
    startDateFrom: nil, startDateTo: nil, places: [], artists: [],
    organizations: [], has_event_type_concept: [], language: "en", limit: 25
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

  # The conditions of a match payload, in the order they were added.
  def add_conditions(payload)
    payload[:queries].first[:conditions].select { |condition| ORGANIZER_OR_PERFORMER_PROPERTY_ID.include?(condition[:propertyId]) }
  end

  def event_type_conditions(payload)
    payload[:queries].first[:conditions]
                     .select { |c| c[:propertyId] == ArtsdataClient::HAS_EVENT_TYPE_CONCEPT_PROPERTY_ID }
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
      client.search_items(**{ in_scheme: [] }.merge(params))
    end
  end
end
