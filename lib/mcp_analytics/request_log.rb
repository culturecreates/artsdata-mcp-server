require "json"
require "time"

module McpAnalytics

  class RequestLog
    EVENT = "mcp_request"


    MAX_ARGUMENTS_BYTES = 8_000

    def initialize(io: $stdout, logger: nil)
      @io = io
      @logger = logger
    end

    def write(call:, request_id: nil, occurred_at: Time.now, **context)
      line = {
        event: EVENT,
        at: occurred_at.utc.iso8601(3),
        request_id: request_id,
        mcp_method: call&.method_name,
        tool: call&.tool_name,
        resource_uri: call&.resource_uri,
        prompt_name: call&.prompt_name,
        arguments: arguments_for(call),
        sparql_hash: call&.sparql_hash,
        status: context[:outcome],
        http_status: context[:http_status],
        duration_ms: context[:duration_ms],
        user_agent: context[:user_agent],
        client_name: context[:client_name],
        client_version: context[:client_version],
        protocol_version: context[:protocol_version]
      }

      @io.puts(JSON.generate(prune(line)))
      @io.flush if @io.respond_to?(:flush)
      :written
    rescue StandardError => e
      @logger&.warn("[mcp_analytics] request log failed: #{e.class}: #{e.message}")
      :failed
    end

    private

    def prune(line)
      line.reject do |_key, value|
        next false if value.is_a?(Numeric)

        value.nil? || (value.respond_to?(:empty?) && value.empty?) ||
          (value.is_a?(String) && value.strip.empty?)
      end
    end

    def arguments_for(call)
      arguments = call&.arguments
      return nil if arguments.nil? || arguments.empty?

      encoded = JSON.generate(arguments)
      return arguments if encoded.bytesize <= MAX_ARGUMENTS_BYTES

      { truncated: true, bytes: encoded.bytesize, preview: encoded[0, MAX_ARGUMENTS_BYTES] }
    end
  end
end
