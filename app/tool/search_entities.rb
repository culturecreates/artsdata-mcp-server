require "mcp"
require "json"

class SearchEntities < MCP::Tool
  description "Tool to search for entities in the Artsdata knowledge graph by name and type(optional)."

  schema_path = File.expand_path("../schema/search_entities_schema.json", __dir__)
  SCHEMA = JSON.parse(File.read(schema_path), symbolize_names: true)

  input_schema(properties: SCHEMA[:properties],
               required: SCHEMA[:required],
               additionalProperties: SCHEMA[:additionalProperties]
  )

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

