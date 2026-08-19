require "mcp"
require "json"

class SearchEvents < MCP::Tool

  description "Tool to search for events in the Artsdata knowledge graph by place, artist, organization,type and language."

  request_schema_path = File.expand_path("../schema/search_events_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/search_events_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(places: [], artists: [], organizations: [], types: [], language: 'en', limit: 25)

      result = ArtsdataClient.new.search_events(places:, artists:, organizations:, types:, language:, limit:)
      structured_result = { results: result }
      MCP::Tool::Response.new(
        [{ type: "text", text: JSON.generate(structured_result) }],
        structured_content: structured_result)
    end
  end
end

