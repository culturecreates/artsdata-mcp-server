require "test_helper"
require "minitest/mock"
require "json_schemer"

class SparqlQueryTest < ActiveSupport::TestCase
  REQUEST_SCHEMA_PATH = Rails.root.join("app", "schema", "sparql_query_request_schema.json")
  RESPONSE_SCHEMA_PATH = Rails.root.join("app", "schema", "sparql_query_response_schema.json")

  QUERY = "PREFIX schema: <http://schema.org/>\nSELECT ?event ?name WHERE { ?event a schema:Event ; schema:name ?name } LIMIT 1".freeze

  SELECT_RESULT = {
    "head" => { "vars" => %w[event name] },
    "results" => {
      "bindings" => [
        { "event" => { "type" => "uri", "value" => "http://kg.artsdata.ca/resource/K11-1" },
          "name" => { "type" => "literal", "value" => "Concert", "xml:lang" => "en" } }
      ]
    }
  }.freeze

  test "is listed by the MCP server as sparql_query, taking a query and declaring an output schema" do
    body = ArtsdataMCPServer.handle_json({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json)
    tool = JSON.parse(body).dig("result", "tools").find { |t| t["name"] == "sparql_query" }

    refute_nil tool, "sparql_query should be registered in config/initializers/mcp_server.rb"
    assert_equal ["query"], tool.dig("inputSchema", "required")
    assert_equal "object", tool.dig("outputSchema", "type")
    assert_match(/get_schema/, tool["description"])
  end

  test "request schema requires a non-empty query string and nothing else" do
    schema = JSONSchemer.schema(REQUEST_SCHEMA_PATH)

    assert_empty schema.validate({ "query" => QUERY }).to_a
    refute_empty schema.validate({}).to_a
    refute_empty schema.validate({ "query" => "" }).to_a
    refute_empty schema.validate({ "query" => 1 }).to_a
    refute_empty schema.validate({ "query" => QUERY, "limit" => 10 }).to_a
  end

  test "response schema accepts SELECT, ASK, truncated and RDF-star results" do
    schema = JSONSchemer.schema(RESPONSE_SCHEMA_PATH)
    quoted_triple = {
      "type" => "triple",
      "value" => {
        "subject" => { "type" => "uri", "value" => "http://kg.artsdata.ca/resource/K11-1" },
        "predicate" => { "type" => "uri", "value" => "http://schema.org/name" },
        "object" => { "type" => "literal", "value" => "Concert" }
      }
    }

    assert_empty schema.validate(SELECT_RESULT).to_a
    assert_empty schema.validate({ "head" => {}, "boolean" => false }).to_a
    assert_empty schema.validate(SELECT_RESULT.merge("truncated" => true)).to_a
    assert_empty schema.validate({ "head" => { "vars" => ["t"] },
                                   "results" => { "bindings" => [{ "t" => quoted_triple }] } }).to_a
    refute_empty schema.validate({ "results" => { "bindings" => [] } }).to_a
  end

  test "call passes the query through unchanged and returns the result as structured content and JSON text" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:query, SELECT_RESULT, [QUERY])

    response = SparqlClient.stub(:new, mock_client) { SparqlQuery.call(query: QUERY) }
    mock_client.verify

    refute response.error?
    assert_equal SELECT_RESULT, response.structured_content
    assert_equal SELECT_RESULT, JSON.parse(response.content.first[:text])
  end

  test "call returns endpoint and validation errors as a tool error the agent can read" do
    failing_client = Object.new
    failing_client.define_singleton_method(:query) do |_query|
      raise SparqlClient::QueryError, "The SPARQL endpoint rejected the query: MALFORMED QUERY"
    end

    response = SparqlClient.stub(:new, failing_client) { SparqlQuery.call(query: "SELECT * { ?s ?p }") }

    assert response.error?
    assert_nil response.structured_content
    assert_equal "The SPARQL endpoint rejected the query: MALFORMED QUERY", response.content.first[:text]
  end

  test "tools/call sparql_query over MCP returns the results, and an update as isError" do
    request = ->(query) { { jsonrpc: "2.0", id: 1, method: "tools/call",
                            params: { name: "sparql_query", arguments: { query: query } } }.to_json }

    stub_client = SparqlClient.new(endpoint: "https://sparql.example.test/query")
    body = stub_client.stub(:query, SELECT_RESULT) do
      SparqlClient.stub(:new, stub_client) { ArtsdataMCPServer.handle_json(request.call(QUERY)) }
    end
    result = JSON.parse(body).fetch("result")

    refute result["isError"], result.inspect
    assert_equal SELECT_RESULT, result["structuredContent"]

    # The real client refuses an update before any HTTP request is made.
    body = Net::HTTP.stub(:start, ->(*) { flunk "no request should be sent for an update" }) do
      ArtsdataMCPServer.handle_json(request.call("INSERT DATA { <urn:a> <urn:b> <urn:c> }"))
    end
    result = JSON.parse(body).fetch("result")

    assert result["isError"]
    assert_match(/Only SELECT and ASK queries are supported. Rewrite the query as a SELECT; use get_entity to get an entity's details./, result.dig("content", 0, "text"))
  end
end
