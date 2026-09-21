
module McpAnalytics
  # Turns one MCP call into one GA4 event.
  #
  # GA4 constrains event names hard: at most 40 characters, letters/numbers/
  # underscore only, and a property is capped at 500 distinct names. Anything
  # unbounded (a resource URI, a SPARQL query) therefore has to travel as a
  # parameter, not as part of the name. Parameters have their own limits, which
  # `truncate` enforces -- a value over 100 characters is dropped by GA4
  # silently, so we shorten rather than let it disappear.
  module Event
    NAME_BY_METHOD = {
      "tools/call"     => "mcp_tool_call",
      "resources/read" => "mcp_resource_read",
      "prompts/get"    => "mcp_prompt_get"
    }.freeze
    DEFAULT_NAME = "mcp_request"

    MAX_PARAM_VALUE_LENGTH = 100

    module_function

    # The single place event naming is decided. Swapping to a name-per-tool
    # scheme (mcp_tools_call_get_entity) means changing this method alone --
    # but note that resource URIs can never be encoded this way.
    def name_for(method_name)
      NAME_BY_METHOD.fetch(method_name.to_s, DEFAULT_NAME)
    end

    # @return [Hash] GA4 event params, already truncated and compacted
    def params_for(call:, outcome:, http_status:, duration_ms:, transport:,
                   user_agent: nil, client_name: nil, client_version: nil,
                   protocol_version: nil, server_version: nil, environment: nil)
      {
        mcp_method: call&.method_name,
        tool_name: presence(call&.tool_name),
        resource_uri: presence(call&.resource_uri),
        prompt_name: presence(call&.prompt_name),
        user_agent: presence(user_agent),
        client_name: presence(client_name),
        client_version: presence(client_version),

        status: outcome,
        http_status: http_status,
        duration_ms: duration_ms,

        transport: transport,
        protocol_version: presence(protocol_version),
        server_version: presence(server_version),
        environment: presence(environment)
      }.filter_map { |key, value| [key, truncate(value)] unless value.nil? }.to_h
    end

    def truncate(value)
      return value if value.is_a?(Numeric)

      string = value.to_s
      string.length > MAX_PARAM_VALUE_LENGTH ? string[0, MAX_PARAM_VALUE_LENGTH] : string
    end

    def presence(value)
      value.nil? || value.to_s.strip.empty? ? nil : value.to_s.strip
    end
  end
end
