require "mcp"
require "json"

class GetSchema < MCP::Tool

  description "Returns the data model of the Artsdata Knowledge Graph: its entity classes (Event, Place, " \
              "Organization, Person, LivePerformanceWork...), the properties of each with required/optional, " \
              "cardinality, value types, linked classes and allowed values, the controlled vocabularies, the " \
              "SPARQL prefixes, and conventions for querying. Derived from the Artsdata Ontology and the " \
              "Artsdata CORE graph SHACL shapes. Call this before writing a SPARQL query against " \
              "https://query.artsdata.ca/query, since Artsdata's model is not general knowledge. Takes no input."

  request_schema_path = File.expand_path("../schema/get_schema_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/get_schema_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(server_context: nil)
      result = ArtsdataSchema.digest
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }], structured_content: result)
    end
  end
end
