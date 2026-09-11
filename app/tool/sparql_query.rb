require "mcp"
require "json"

class SparqlQuery < MCP::Tool

  description "Runs a read-only SPARQL 1.1 SELECT or ASK query against the Artsdata Knowledge Graph " \
              "(#{SparqlClient.endpoint}) and returns the result as SPARQL 1.1 Query Results JSON, " \
              "exactly as the endpoint returns it: head.vars and results.bindings for SELECT, boolean for ASK. " \
              "Call get_schema first and build the query from the classes, properties, prefixes and " \
              "conventions it returns, since Artsdata's model is not general knowledge. Declare every PREFIX " \
              "you use and always add a LIMIT: at most #{SparqlClient.max_rows} rows are returned " \
              "(the rest is cut and truncated is true; page with OFFSET), and a query gets " \
              "#{SparqlClient.timeout} seconds. If the endpoint rejects the query, its error " \
              "message is returned so you can fix the query and retry. For the details of an entity URI in " \
              "the results use get_entity; to find an entity's URI from its name use search_entities."

  request_schema_path = File.expand_path("../schema/sparql_query_request_schema.json", __dir__)
  REQUEST_SCHEMA = JSON.parse(File.read(request_schema_path), symbolize_names: true)

  response_schema_path = File.expand_path("../schema/sparql_query_response_schema.json", __dir__)
  RESPONSE_SCHEMA = JSON.parse(File.read(response_schema_path), symbolize_names: true)

  input_schema(REQUEST_SCHEMA)
  output_schema(RESPONSE_SCHEMA)

  class << self
    def call(query:)
      result = SparqlClient.new.query(query)
      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }], structured_content: result)
    rescue SparqlClient::Error => e
      # Returned as a tool error (isError: true) rather than raised, so the agent sees why the query
      # failed - raised errors reach the client only as a generic "Internal error".
      MCP::Tool::Response.new([{ type: "text", text: e.message }], error: true)
    end
  end
end
