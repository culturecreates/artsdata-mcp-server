require "mcp"
require "json"

class GetEntity < MCP::Tool

  description "Tool to get entities details from Artsdata Knowledge Graph by entity URI."

  request_schema_path = File.expand_path("../schema/get_entity_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/get_entity_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(uri:)

      result = ArtsdataClient.new.get_entity_by_extend_service(uri:)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }], structured_content: result)
    end
  end
end

