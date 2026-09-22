require "test_helper"
require "minitest/mock"

# Runs real MCP requests through the full Rails stack with reporting switched
# on. The unit tests cover the middleware in isolation; this exists to prove
# that buffering the request body does not break the MCP transport, which is
# the one way this integration could take the server down.
class McpAnalyticsReportingTest < ActionDispatch::IntegrationTest
  class RecordingClient
    attr_reader :payloads

    def initialize
      @payloads = []
    end

    def send_events(client_id:, session_id:, events:, occurred_at: Time.now)
      @payloads << {
        client_id: client_id,
        session_id: session_id,
        events: events,
        occurred_at: occurred_at
      }
      :sent
    end
  end

  setup do
    @original_config = McpAnalytics.config
    McpAnalytics.config = McpAnalytics::Configuration.new(
      "GA4_MEASUREMENT_ID" => "G-TESTTEST",
      "GA4_API_SECRET" => "test-secret"
    )

    McpAnalytics.config.request_log = false
    @client = RecordingClient.new
    McpAnalytics.client = @client
  end

  teardown do
    McpAnalytics.config = @original_config
    McpAnalytics.client = nil
  end

  test "an initialize request still succeeds and is reported" do
    body = mcp_post(
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2025-06-18",
        capabilities: {},
        clientInfo: { name: "Claude Code", version: "1.0.0" }
      }
    )

    assert_response :success
    assert_equal 1, body.fetch("id")

    params = reported_params
    assert_equal "mcp_request", reported_event[:name]
    assert_equal "initialize", params[:mcp_method]
    assert_equal "Claude Code", params[:client_name]
    assert_equal "1.0.0", params[:client_version]

  end

  test "tools/list still succeeds and is reported" do
    body = mcp_post(jsonrpc: "2.0", id: 2, method: "tools/list", params: {})

    assert_response :success
    refute_nil body.dig("result", "tools")
    assert_equal "tools/list", reported_params[:mcp_method]
  end

  test "a tools/call still reaches the tool with its arguments intact" do
    uri = "http://kg.artsdata.ca/resource/K23-934"
    entity = { "id" => "K23-934", "uri" => uri, "name" => [{ "value" => "Example", "language" => "en" }] }

    mock_client = Minitest::Mock.new
    mock_client.expect(:get_entity_by_extend_service, [entity], [], ids: ["K23-934"])

    ArtsdataClient.stub(:new, mock_client) do
      body = mcp_post(
        jsonrpc: "2.0",
        id: 3,
        method: "tools/call",
        params: { name: "get_entity", arguments: { uri: uri } }
      )

      assert_response :success
      assert_equal uri, body.dig("result", "structuredContent").fetch("uri")
    end

    mock_client.verify

    assert_equal "mcp_tool_call", reported_event[:name]
    assert_equal "get_entity", reported_params[:tool_name]
    assert_kind_of Integer, reported_params[:duration_ms]

    # Outcome detection is covered exhaustively in the unit tests, where the
    # response body is under our control. Here we only require that a
    # successful call is not reported as a failure -- the transport is free to
    # hand back a body we cannot cheaply inspect, which is reported as
    # "unknown" by design rather than guessed at.
    assert_includes %w[success unknown], reported_params[:status]
  end

  test "the user agent is recorded verbatim on a plain tool call" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:get_entity_by_extend_service, [{ "id" => "K23-934" }], [], ids: ["K23-934"])

    ArtsdataClient.stub(:new, mock_client) do
      mcp_post(
        { jsonrpc: "2.0", id: 4, method: "tools/call",
          params: { name: "get_entity", arguments: { uri: "http://kg.artsdata.ca/resource/K23-934" } } },
        "HTTP_USER_AGENT" => "Cursor/0.42.3"
      )
    end

    assert_equal "Cursor/0.42.3", reported_params[:user_agent]
  end

  test "an unknown method is reported as an error, not a success" do
    mcp_post(jsonrpc: "2.0", id: 9, method: "tools/nope", params: {})

    assert_equal "tools/nope", reported_params[:mcp_method]
    refute_equal "success", reported_params[:status]
  end

  private

  def reported_event
    @client.payloads.last.fetch(:events).first
  end

  def reported_params
    reported_event.fetch(:params)
  end

  def mcp_post(payload, extra_headers = {})
    headers = {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => "127.0.0.1"
    }.merge(extra_headers)

    post "/mcp", params: payload.to_json, headers: headers

    body = response.body.to_s.strip
    return nil if body.empty?

    JSON.parse(body.sub(/\Adata:\s*/, ""))
  rescue JSON::ParserError
    nil
  end
end
