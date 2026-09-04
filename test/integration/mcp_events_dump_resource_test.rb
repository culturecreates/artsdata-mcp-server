require "test_helper"
require "minitest/mock"

class McpEventsDumpResourceTest < ActionDispatch::IntegrationTest
  DUMP_URL = "https://dumps.example.test/core-graph-minus-provenance/monthly/artsdata-2026-09-01-core-minus-provenance.ttl.gz".freeze

  DUMP_METADATA = {
    "url" => DUMP_URL,
    "available" => true,
    "content_type" => "application/gzip",
    "format" => "text/turtle",
    "size" => 987_654_321,
    "last_modified" => "2026-09-01T03:15:02Z",
    "checked_at" => "2026-09-04T08:00:00Z"
  }.freeze

  test "the events dump is listed as a resource and reads back as a manifest" do
    initialize_response = mcp_post(
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0.0" }
      }
    )
    assert_response :success
    refute_nil initialize_response.dig("result", "capabilities", "resources"),
               "the server should advertise the resources capability"

    mcp_post(jsonrpc: "2.0", method: "notifications/initialized", params: {})

    # resources/list
    list_response = mcp_post(jsonrpc: "2.0", id: 2, method: "resources/list", params: {})
    assert_response :success

    resources = list_response.dig("result", "resources")
    refute_nil resources
    events_dump = resources.find { |r| r["uri"] == "artsdata://dump" }
    refute_nil events_dump, "artsdata://dump should be listed"
    assert_equal "artsdata_dump", events_dump["name"]
    assert_equal "application/json", events_dump["mimeType"]

    # resources/read -> manifest, not the dump itself
    mock_client = Minitest::Mock.new
    mock_client.expect(:metadata, DUMP_METADATA)

    read_response = DataDumpClient.stub(:new, mock_client) do
      mcp_post(jsonrpc: "2.0", id: 3, method: "resources/read", params: { uri: "artsdata://dump" })
    end
    mock_client.verify

    assert_response :success
    assert_equal 3, read_response.fetch("id")

    contents = read_response.dig("result", "contents")
    assert_equal 1, contents.size
    assert_equal "artsdata://dump", contents.first["uri"]
    assert_equal "application/json", contents.first["mimeType"]
    refute contents.first.key?("blob")

    manifest = JSON.parse(contents.first["text"])
    assert_equal DUMP_URL, manifest.dig("dump", "url")
    assert_equal 987_654_321, manifest.dig("dump", "size")
    assert_equal "2026-09-01T03:15:02Z", manifest.dig("dump", "last_modified")
  end

  test "reading an unknown resource uri returns a JSON-RPC error" do
    error_response = mcp_post(jsonrpc: "2.0", id: 4, method: "resources/read", params: { uri: "artsdata://dumps/nope" })

    refute_nil error_response["error"], "an unknown resource should produce a JSON-RPC error"
    assert_nil error_response["result"]
  end

  private

  def mcp_post(payload)
    headers = {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => "127.0.0.1"
    }

    post "/mcp", params: payload.to_json, headers: headers

    body = response.body.to_s.strip
    return nil if body.empty?

    JSON.parse(body.sub(/\Adata:\s*/, ""))
  rescue JSON::ParserError
    nil
  end
end
