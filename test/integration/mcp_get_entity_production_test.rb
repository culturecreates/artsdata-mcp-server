require "test_helper"
require "net/http"
require "json"

class McpGetEntityProductionTest < ActiveSupport::TestCase
  MCP_URL = URI("https://mcp.artsdata.ca/mcp")

  test "production mcp server retrieves entity from uri" do
    skip "Set RUN_PRODUCTION_MCP_TESTS=true to run production MCP tests" unless ENV["RUN_PRODUCTION_MCP_TESTS"] == "true"

    mcp_session_id = nil

    initialize_response, mcp_session_id = mcp_post(
      payload: {
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {
          protocolVersion: "2025-06-18",
          capabilities: {},
          clientInfo: { name: "production-test-client", version: "1.0.0" }
        }
      },
      mcp_session_id: mcp_session_id
    )

    assert_equal 1, initialize_response.fetch("id")
    assert_not_nil mcp_session_id

    _initialized_response, mcp_session_id = mcp_post(
      payload: { jsonrpc: "2.0", method: "notifications/initialized", params: {} },
      mcp_session_id: mcp_session_id
    )

    search_response, mcp_session_id = mcp_post(
      payload: {
        jsonrpc: "2.0",
        id: 2,
        method: "tools/call",
        params: {
          name: "search_entities",
          arguments: {
            query: "festival",
            types: ["Organization"],
            language: "en",
            limit: 1
          }
        }
      },
      mcp_session_id: mcp_session_id
    )

    uri = search_response.dig("result", "structuredContent", "results", 0, "uri")
    assert_not_nil uri

    get_entity_response, = mcp_post(
      payload: {
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "get_entity",
          arguments: { uri: uri }
        }
      },
      mcp_session_id: mcp_session_id
    )

    structured_content = get_entity_response.dig("result", "structuredContent")
    assert_equal uri, structured_content.fetch("uri")
    assert_equal uri.split("/").last, structured_content.fetch("id")

    text_content = get_entity_response.dig("result", "content", 0, "text")
    assert_equal structured_content, JSON.parse(text_content)
  end

  private

  def mcp_post(payload:, mcp_session_id:)
    request = Net::HTTP::Post.new(MCP_URL)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json, text/event-stream"
    request["Mcp-Session-Id"] = mcp_session_id if mcp_session_id
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(MCP_URL.host, MCP_URL.port, use_ssl: true) do |http|
      http.request(request)
    end

    body = response.body.to_s.strip
    parsed_body = body.empty? ? nil : JSON.parse(body.sub(/\Adata:\s*/, ""))

    [parsed_body, response["Mcp-Session-Id"] || mcp_session_id]
  end
end
