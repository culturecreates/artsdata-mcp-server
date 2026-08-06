require "test_helper"

class McpSearchEntitiesFlowTest < ActionDispatch::IntegrationTest
  test "mcp initialize to search_entities flow follows protocol" do
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
    assert_equal "2.0", initialize_response.fetch("jsonrpc")
    assert_equal 1, initialize_response.fetch("id")
    assert initialize_response.fetch("result").key?("capabilities")

    initialized_response = mcp_post(
      jsonrpc: "2.0",
      method: "notifications/initialized",
      params: {}
    )

    assert_includes(200..299, response.status)
    assert_nil initialized_response

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

    fixture_results = load_fixture("search_entities_results.json")
    mock_client = Minitest::Mock.new
    mock_client.expect(
      :search_items,
      fixture_results,
      [{ query: "festival", types: ["Organization"], lang: "en", limit: 2 }]
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
      assert_equal "2.0", search_entities_response.fetch("jsonrpc")
      assert_equal 3, search_entities_response.fetch("id")

      structured_content = search_entities_response.dig("result", "structuredContent")
      assert_equal fixture_results, structured_content

      text_content = search_entities_response.dig("result", "content", 0, "text")
      assert_equal fixture_results, JSON.parse(text_content)
    end

    mock_client.verify
  end

  private

  def mcp_post(payload)
    post "/mcp", params: payload.to_json, headers: {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json"
    }

    body = response.body.to_s.strip
    return nil if body.empty?

    JSON.parse(body)
  rescue JSON::ParserError
    nil
  end

  def load_fixture(file_name)
    JSON.parse(File.read(Rails.root.join("test", "fixtures", file_name)))
  end
end
