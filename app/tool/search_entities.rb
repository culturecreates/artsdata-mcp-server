require "mcp"
require "json"

class SearchEntities < MCP::Tool
  description "Tool to search for entities in the Artsdata knowledge graph by name and type(optional)."

  request_schema_path = File.expand_path("../schema/search_entities_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/search_entities_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(query:, language:, limit:)

      result = ArtsdataClient.new.search_items(query:, lang: language, limit:)
      MCP::Tool::Response.new({
                                type: "text",
                                text: JSON.generate(result),
                              }, structured_content: result)
    end
  end
end

