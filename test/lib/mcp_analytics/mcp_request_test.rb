require "test_helper"

class McpAnalytics::McpRequestTest < ActiveSupport::TestCase
  test "extracts the tool name from a tools/call" do
    request = McpAnalytics::McpRequest.new(
      { jsonrpc: "2.0", id: 2, method: "tools/call",
        params: { name: "get_entity",
                  arguments: { uri: "http://kg.artsdata.ca/resource/K23-934" } } }.to_json
    )

    call = request.calls.sole
    assert_equal "tools/call", call.method_name
    assert_equal "get_entity", call.tool_name
    assert_nil call.resource_uri
  end

  test "extracts the uri from a resources/read" do
    request = McpAnalytics::McpRequest.new(
      { jsonrpc: "2.0", id: 5, method: "resources/read",
        params: { uri: "artsdata://dumps/core-minus-provenance/latest" } }.to_json
    )

    call = request.calls.sole
    assert_equal "resources/read", call.method_name
    assert_equal "artsdata://dumps/core-minus-provenance/latest", call.resource_uri
  end

  test "extracts client info from initialize" do
    request = McpAnalytics::McpRequest.new(
      { jsonrpc: "2.0", id: 1, method: "initialize",
        params: { protocolVersion: "2025-06-18",
                  clientInfo: { name: "claude-ai", version: "1.0.0" } } }.to_json
    )

    assert_equal "claude-ai", request.client_name
    assert_equal "1.0.0", request.client_version
    assert_equal "2025-06-18", request.protocol_version
  end

  test "handles notifications, which have no id" do
    request = McpAnalytics::McpRequest.new(
      { jsonrpc: "2.0", method: "notifications/initialized", params: {} }.to_json
    )

    assert_equal "notifications/initialized", request.calls.sole.method_name
  end

  test "tolerates a batch" do
    request = McpAnalytics::McpRequest.new(
      [{ jsonrpc: "2.0", id: 1, method: "tools/list" },
       { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_schema" } }].to_json
    )

    assert_equal %w[tools/list tools/call], request.calls.map(&:method_name)
    assert_equal "get_schema", request.calls.last.tool_name
  end

  test "never raises on junk" do
    ["", nil, "not json", "{", "[]", '{"params": "not a hash"}', "\xff\xfe"].each do |body|
      assert_nothing_raised { McpAnalytics::McpRequest.new(body) }
    end
  end
end
