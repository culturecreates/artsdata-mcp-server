require "test_helper"
require "minitest/mock"

class McpSearchEntitiesFlowTest < ActionDispatch::IntegrationTest
  test "mcp initialize to search_entities and get_entity flow follows protocol" do

    # MCP Initialize
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
    assert_equal 1, initialize_response.fetch("id")
    # Stateless transport: no Mcp-Session-Id is issued or required on subsequent requests.
    assert_nil response.headers["Mcp-Session-Id"]

    # MCP notifications/initialized
    initialized_response = mcp_post(jsonrpc: "2.0", method: "notifications/initialized", params: {})

    assert_includes(200..299, response.status)
    assert_nil initialized_response

    # MCP list tools
    tools_list_response = mcp_post(
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list",
      params: {}
    )

    assert_response :success
    assert_equal "2.0", tools_list_response.fetch("jsonrpc")
    assert_equal 2, tools_list_response.fetch("id")

    tools = tools_list_response.dig("result", "tools")
    refute_nil tools

    search_entities_tool = tools.find { |tool| tool["name"] == "search_entities" }
    refute_nil search_entities_tool
    assert search_entities_tool.key?("inputSchema")
    assert search_entities_tool.key?("outputSchema")

    # MCP search_entities
    fixture_results = load_fixture("search_entities_results.json")
    searched_uri = fixture_results.first.fetch("uri")
    fixture_entity = {
      "id" => searched_uri.split("/").last,
      "uri" => searched_uri,
      "name" => [{ "value" => "Festival Example", "language" => "en" }],
      "sameAs" => ["https://example.org/festival"]
    }
    mock_client = Minitest::Mock.new

    mock_client.expect(
      :search_items,
      fixture_results,
      [],
      query: "festival", types: ["Organization"], lang: "en", limit: 2
    )
    mock_client.expect(
      :get_entity_by_extend_service,
      [fixture_entity],
      [],
      ids: [searched_uri.split("/").last]
    )

    ArtsdataClient.stub(:new, mock_client) do
      search_entities_response = mcp_post(
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: {
          name: "search_entities",
          arguments: {
            query: "festival",
            types: ["Organization"],
            language: "en",
            limit: 2
          }
        }
      )

      assert_response :success
      assert_equal 3, search_entities_response.fetch("id")

      structured_content = search_entities_response.dig("result", "structuredContent")
      assert_equal({ "results" => fixture_results }, structured_content)

      text_content = search_entities_response.dig("result", "content", 0, "text")
      assert_equal({ "results" => fixture_results }, JSON.parse(text_content))

      get_entity_response = mcp_post(
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: {
          name: "get_entity",
          arguments: {
            uri: searched_uri
          }
        }
      )

      assert_response :success
      assert_equal 4, get_entity_response.fetch("id")

      get_entity_structured_content = get_entity_response.dig("result", "structuredContent")
      assert_equal searched_uri, get_entity_structured_content.fetch("uri")
      assert_equal searched_uri.split("/").last, get_entity_structured_content.fetch("id")

      get_entity_text_content = get_entity_response.dig("result", "content", 0, "text")
      assert_equal(get_entity_structured_content, JSON.parse(get_entity_text_content))
    end

    mock_client.verify
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

  def load_fixture(file_name)
    JSON.parse(File.read(Rails.root.join("test", "fixtures", file_name)))
  end
end