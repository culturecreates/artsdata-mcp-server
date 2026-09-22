
module McpAnalytics

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
    # @return [Hash] GA4 event params, normalized and with blanks dropped
    def params_for(call:, outcome:, http_status:, duration_ms:,
                   user_agent: nil, client_name: nil, client_version: nil,
                   **_unused)
      {
        mcp_method: call&.method_name,
        tool_name: call&.tool_name,
        resource_uri: call&.resource_uri,
        prompt_name: call&.prompt_name,
        sparql_form: call&.sparql_form,
        sparql_where: call&.sparql_where,
        user_agent: user_agent,
        client_name: client_name,
        client_version: client_version,

        status: outcome,
        http_status: http_status,
        duration_ms: duration_ms
      }.filter_map { |key, value| [key, normalize(value)] unless blank?(value) }.to_h
    end

    def blank?(value)
      return false if value.is_a?(Numeric)

      value.nil? || value.to_s.strip.empty?
    end

    def normalize(value)
      return value if value.is_a?(Numeric)

      string = value.to_s.strip
      string.length > MAX_PARAM_VALUE_LENGTH ? string[0, MAX_PARAM_VALUE_LENGTH] : string
    end
  end
end
