require "test_helper"

class McpAnalytics::MiddlewareTest < ActiveSupport::TestCase
  # Records what would have been sent instead of calling Google.
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

  class ExplodingClient
    def send_events(**_kwargs)
      raise "GA4 is on fire"
    end
  end

  ENABLED_ENV = {
    "GA4_MEASUREMENT_ID" => "G-TESTTEST",
    "GA4_API_SECRET" => "secret"
  }.freeze

 def config(overrides = {})
    built = McpAnalytics::Configuration.new(ENABLED_ENV.merge(overrides))
    built.request_log = false
    built
  end

  def silent_config(env)
    built = McpAnalytics::Configuration.new(env)
    built.request_log = false
    built
  end

  def env_for(body, overrides = {})
    {
      "PATH_INFO" => "/mcp",
      "REQUEST_METHOD" => "POST",
      "CONTENT_TYPE" => "application/json",
      "CONTENT_LENGTH" => body.bytesize.to_s,
      "REMOTE_ADDR" => "203.0.113.5",
      "HTTP_USER_AGENT" => "claude-code/1.2.3",
      "rack.input" => StringIO.new(body.dup.force_encoding(Encoding::BINARY))
    }.merge(overrides)
  end

  def json_app(response_body, status: 200, content_type: "application/json")
    ->(_env) { [status, { "content-type" => content_type }, [response_body]] }
  end

  def tool_call_body(name = "get_entity")
    { jsonrpc: "2.0", id: 2, method: "tools/call",
      params: { name: name, arguments: { uri: "http://kg.artsdata.ca/resource/K23-934" } } }.to_json
  end

  def params_from(client)
    client.payloads.sole[:events].sole[:params]
  end

  # --- the invariant that matters most -------------------------------------

  test "leaves the request body readable by the application" do
    body = tool_call_body
    seen = nil
    app = lambda do |env|
      seen = env["rack.input"].read
      [200, { "content-type" => "application/json" }, ['{"jsonrpc":"2.0","id":2,"result":{}}']]
    end

    McpAnalytics::Middleware.new(app, config: config, client: RecordingClient.new).call(env_for(body))

    assert_equal body, seen
  end

  test "returns the application's response unchanged" do
    app = json_app('{"jsonrpc":"2.0","id":2,"result":{}}')
    expected = app.call({})

    actual = McpAnalytics::Middleware.new(app, config: config, client: RecordingClient.new)
                                     .call(env_for(tool_call_body))

    assert_equal expected, actual
  end

  test "a failing analytics client never breaks the request" do
    app = json_app('{"jsonrpc":"2.0","id":2,"result":{}}')

    status, _headers, body = McpAnalytics::Middleware
                             .new(app, config: config, client: ExplodingClient.new)
                             .call(env_for(tool_call_body))

    assert_equal 200, status
    assert_equal ['{"jsonrpc":"2.0","id":2,"result":{}}'], body
  end

  test "does not read the body at all when reporting is off" do
    client = RecordingClient.new
    body = tool_call_body
    seen = nil
    app = lambda do |env|
      seen = env["rack.input"].read
      [200, { "content-type" => "application/json" }, ["{}"]]
    end

    McpAnalytics::Middleware
      .new(app, config: silent_config({}), client: client)
      .call(env_for(body))

    assert_equal body, seen
    assert_empty client.payloads
  end

  test "hands on an oversized body intact without parsing it" do
    client = RecordingClient.new
    oversized = "x" * (McpAnalytics::Configuration::MAX_BODY_BYTES + 1000)
    body = { jsonrpc: "2.0", id: 1, method: "tools/call",
             params: { name: "sparql_query", arguments: { query: oversized } } }.to_json
    seen = nil
    app = lambda do |env|
      seen = env["rack.input"].read
      [200, { "content-type" => "application/json" }, ["{}"]]
    end

    McpAnalytics::Middleware.new(app, config: config, client: client).call(env_for(body))

    assert_equal body, seen
    # Still reported, but we never parsed it, so there is no tool name.
    assert_nil params_from(client)[:tool_name]
  end

  test "ignores paths outside the mcp mount" do
    client = RecordingClient.new
    app = json_app("ok")

    McpAnalytics::Middleware.new(app, config: config, client: client)
                            .call(env_for("", "PATH_INFO" => "/up"))
    McpAnalytics::Middleware.new(app, config: config, client: client)
                            .call(env_for("", "PATH_INFO" => "/mcp-something-else"))

    assert_empty client.payloads
  end

  # --- what actually gets reported -----------------------------------------

  test "reports a tool call with the tool name as a parameter" do
    client = RecordingClient.new

    McpAnalytics::Middleware
      .new(json_app('{"jsonrpc":"2.0","id":2,"result":{}}'), config: config, client: client)
      .call(env_for(tool_call_body))

    event = client.payloads.sole[:events].sole
    assert_equal "mcp_tool_call", event[:name]
    assert_equal "get_entity", event[:params][:tool_name]
    assert_equal "tools/call", event[:params][:mcp_method]
    assert_equal "success", event[:params][:status]
  end

  test "reports a resource read with the uri as a parameter" do
    client = RecordingClient.new
    body = { jsonrpc: "2.0", id: 5, method: "resources/read",
             params: { uri: "artsdata://dumps/core-minus-provenance/latest" } }.to_json

    McpAnalytics::Middleware
      .new(json_app('{"jsonrpc":"2.0","id":5,"result":{}}'), config: config, client: client)
      .call(env_for(body))

    event = client.payloads.sole[:events].sole
    assert_equal "mcp_resource_read", event[:name]
    assert_equal "artsdata://dumps/core-minus-provenance/latest", event[:params][:resource_uri]
  end

  test "records the user agent verbatim" do
    client = RecordingClient.new

    McpAnalytics::Middleware
      .new(json_app("{}"), config: config, client: client)
      .call(env_for(tool_call_body, "HTTP_USER_AGENT" => "Cursor/0.42.3"))

    assert_equal "Cursor/0.42.3", params_from(client)[:user_agent]
  end

  test "omits the user agent rather than inventing one when the header is absent" do
    client = RecordingClient.new
    env = env_for(tool_call_body)
    env.delete("HTTP_USER_AGENT")

    McpAnalytics::Middleware.new(json_app("{}"), config: config, client: client).call(env)

    refute params_from(client).key?(:user_agent)
  end

  test "records what the client calls itself during initialize" do
    client = RecordingClient.new
    body = { jsonrpc: "2.0", id: 1, method: "initialize",
             params: { protocolVersion: "2025-06-18",
                       clientInfo: { name: "Claude Code", version: "1.0.0" } } }.to_json

    McpAnalytics::Middleware.new(json_app("{}"), config: config, client: client).call(env_for(body))

    assert_equal "Claude Code", params_from(client)[:client_name]
    assert_equal "1.0.0", params_from(client)[:client_version]
  end

  test "records how long the request took" do
    client = RecordingClient.new
    slow_app = lambda do |_env|
      sleep 0.02
      [200, { "content-type" => "application/json" }, ["{}"]]
    end

    McpAnalytics::Middleware.new(slow_app, config: config, client: client)
                            .call(env_for(tool_call_body))

    assert_operator params_from(client)[:duration_ms], :>=, 20
  end

  test "reports non-tool methods as mcp_request" do
    client = RecordingClient.new
    body = { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }.to_json

    McpAnalytics::Middleware.new(json_app("{}"), config: config, client: client).call(env_for(body))

    event = client.payloads.sole[:events].sole
    assert_equal "mcp_request", event[:name]
    assert_equal "tools/list", event[:params][:mcp_method]
  end

  test "reports a body-less transport call" do
    client = RecordingClient.new

    McpAnalytics::Middleware
      .new(json_app("", content_type: "text/event-stream"), config: config, client: client)
      .call(env_for("", "REQUEST_METHOD" => "GET"))

    event = client.payloads.sole[:events].sole
    assert_equal "mcp_request", event[:name]
    assert_equal "transport/get", event[:params][:mcp_method]
    refute event[:params].key?(:transport)
  end

  # --- outcome detection ----------------------------------------------------

  test "detects a json-rpc error behind a 200" do
    client = RecordingClient.new
    error = '{"jsonrpc":"2.0","id":2,"error":{"code":-32601,"message":"Method not found"}}'

    McpAnalytics::Middleware.new(json_app(error), config: config, client: client)
                            .call(env_for(tool_call_body))

    assert_equal "error", params_from(client)[:status]
  end

  test "detects a tool-level error" do
    client = RecordingClient.new
    result = '{"jsonrpc":"2.0","id":2,"result":{"isError":true,"content":[]}}'

    McpAnalytics::Middleware.new(json_app(result), config: config, client: client)
                            .call(env_for(tool_call_body))

    assert_equal "tool_error", params_from(client)[:status]
  end

  test "reads a response framed as a server-sent event" do
    client = RecordingClient.new
    sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{}}\n\n"

    McpAnalytics::Middleware
      .new(json_app(sse, content_type: "text/event-stream"), config: config, client: client)
      .call(env_for(tool_call_body))

    assert_equal "success", params_from(client)[:status]
  end

  test "records an http error" do
    client = RecordingClient.new

    McpAnalytics::Middleware
      .new(json_app("{}", status: 400), config: config, client: client)
      .call(env_for(tool_call_body))

    assert_equal "http_error", params_from(client)[:status]
    assert_equal 400, params_from(client)[:http_status]
  end

  test "records an exception raised by the application and re-raises it" do
    client = RecordingClient.new
    app = ->(_env) { raise "boom" }

    assert_raises(RuntimeError) do
      McpAnalytics::Middleware.new(app, config: config, client: client).call(env_for(tool_call_body))
    end

    assert_equal "exception", params_from(client)[:status]
  end

  # --- payload hygiene ------------------------------------------------------

  test "truncates parameters to the length GA4 accepts" do
    client = RecordingClient.new
    body = { jsonrpc: "2.0", id: 5, method: "resources/read",
             params: { uri: "artsdata://#{'x' * 500}" } }.to_json

    McpAnalytics::Middleware.new(json_app("{}"), config: config, client: client).call(env_for(body))

    assert_equal 100, params_from(client)[:resource_uri].length
  end

  test "gives the same caller a stable client id" do
    client = RecordingClient.new
    2.times do
      McpAnalytics::Middleware.new(json_app("{}"), config: config, client: client)
                              .call(env_for(tool_call_body))
    end

    assert_equal 1, client.payloads.map { |payload| payload[:client_id] }.uniq.size
  end
end
