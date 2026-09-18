class SearchEvents < MCP::Tool

  description "Tool to search for events in the Artsdata knowledge graph by place, artist, organization, " \
              "has_event_type_concept and language. Places, artists and organizations are Artsdata entity URIs; " \
              "the has_event_type_concept filter takes concept URIs from the Artsdata Event Types vocabulary " \
              "(adr:ArtsdataEventTypes), not schema.org classes. Resolve any name or label to its URI with " \
              "search_entities first."

  request_schema_path = File.expand_path("../schema/search_events_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/search_events_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(startDateFrom: nil, startDateTo: nil, places: [], artists: [], organizations: [],
             has_event_type_concept: [], language: 'en', limit: 25)

      result = ArtsdataClient.new.search_events(
        startDateFrom: startDateFrom,
        startDateTo: startDateTo,
        places: places,
        artists: artists,
        organizations: organizations,
        has_event_type_concept: has_event_type_concept,
        language: language,
        limit: limit
      )

      structured_result = { results: result }
      MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate(structured_result) }],
        structured_content: structured_result)
    end
  end
end