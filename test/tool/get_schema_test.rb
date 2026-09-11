require "test_helper"
require "minitest/mock"
require "json_schemer"

class GetSchemaTest < ActiveSupport::TestCase
  REQUEST_SCHEMA_PATH = Rails.root.join("app", "schema", "get_schema_request_schema.json")
  DIGEST = ArtsdataSchema.new.compile(Rails.root.join("test/fixtures/files/artsdata-schema.ttl").read(encoding: "UTF-8")).freeze

  test "is listed by the MCP server as get_schema, with an empty input schema and an output schema" do
    body = ArtsdataMCPServer.handle_json({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json)
    tool = JSON.parse(body).dig("result", "tools").find { |t| t["name"] == "get_schema" }

    refute_nil tool, "get_schema should be registered in config/initializers/mcp_server.rb"
    assert_empty tool.dig("inputSchema", "properties").to_h
    assert_equal "object", tool.dig("outputSchema", "type")
  end

  test "takes no arguments" do
    schema = JSONSchemer.schema(REQUEST_SCHEMA_PATH)

    assert_empty schema.validate({}).to_a
    refute_empty schema.validate({ "class" => "Event" }).to_a
  end

  test "call returns the schema digest as structured content and as matching JSON text" do
    response = ArtsdataSchema.stub(:digest, DIGEST) { GetSchema.call }

    assert_equal DIGEST, response.structured_content
    assert_equal DIGEST, JSON.parse(response.content.first[:text])
  end

  test "tools/call get_schema over MCP returns the digest" do
    request = { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_schema", arguments: {} } }
    body = ArtsdataSchema.stub(:digest, DIGEST) { ArtsdataMCPServer.handle_json(request.to_json) }
    result = JSON.parse(body).fetch("result")

    refute result["isError"], result.inspect
    assert_equal JSON.parse(JSON.generate(DIGEST)), result["structuredContent"]
  end
end
