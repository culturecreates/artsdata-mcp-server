require "stringio"

require_relative "configuration"
require_relative "identity"
require_relative "mcp_request"
require_relative "event"
require_relative "ga4_client"
require_relative "request_log"

module McpAnalytics


  class Middleware
    JSON_CONTENT_TYPE = %r{application/json}i
    SSE_CONTENT_TYPE = %r{text/event-stream}i
    MAX_PEEK_BYTES = 64 * 1024

    # @param config [Configuration, nil] defaults to the global configuration
    # @param client [#send_events, nil] injectable for tests
    def initialize(app, config: nil, client: nil)
      @app = app
      @config = config
      @client = client
    end

    def call(env)
      log_status_once
      return @app.call(env) unless tracked_path?(env) && config.active?

      raw_body = buffer_request_body(env)
      started_at = monotonic_now
      begin
        status, headers, body = @app.call(env)
      rescue StandardError => e
        track(env, raw_body, elapsed_ms(started_at), status: 500, outcome: "exception")
        raise e
      end

      track(env, raw_body, elapsed_ms(started_at),
            status: status, outcome: outcome_for(status, headers, body))

      [status, headers, body]
    end

    private

    def log_status_once
      return if @status_logged

      @status_logged = true

      if config.enabled?
        mode = config.debug? ? " (debug_mode on, events also validated)" : ""
        config.logger&.info(
          "[mcp_analytics] reporting MCP calls to #{config.measurement_id}#{mode}"
        )
      elsif config.reporting_disabled?
        config.logger&.info("[mcp_analytics] reporting OFF -- disabled for this environment")
      else
        missing = []
        missing << "GA4_MEASUREMENT_ID" if config.measurement_id.nil?
        missing << "GA4_API_SECRET" if config.api_secret.nil?
        config.logger&.info("[mcp_analytics] reporting OFF -- no #{missing.join(' and no ')}")
      end

      config.logger&.info(
        "[mcp_analytics] request log #{config.request_log? ? 'ON (stdout)' : 'OFF'}"
      )
    rescue StandardError
      @status_logged = true
    end

    def config
      @config || McpAnalytics.config
    end

    def tracked_path?(env)
      path = env["PATH_INFO"].to_s
      prefix = config.path_prefix
      path == prefix || path.start_with?("#{prefix}/")
    end

    def buffer_request_body(env)
      raw = nil
      input = env["rack.input"]
      return nil if input.nil?

      declared = env["CONTENT_LENGTH"].to_s
      return nil unless declared.match?(/\A\d+\z/)

      length = declared.to_i
      return nil if length.zero?

      raw = input.read(length)
      return nil if raw.nil?

      raw = raw.dup.force_encoding(Encoding::BINARY)
      env["rack.input"] = StringIO.new(raw)

      # Oversized bodies are put back intact but not parsed.
      raw.bytesize > config.max_body_bytes ? nil : raw
    rescue StandardError => e
      warn_failure("could not buffer request body", e)
      # Only restore what we actually read. Replacing an unread stream with an
      # empty one would silently strip the body from the request.
      env["rack.input"] = StringIO.new(raw) if raw
      nil
    end

    def track(env, raw_body, duration_ms, status:, outcome:)
      return unless config.active?

      mcp_request = McpRequest.new(raw_body)
      context = shared_context(env, mcp_request, outcome, status, duration_ms)
      calls = calls_for(mcp_request, env["REQUEST_METHOD"].to_s.upcase)

      write_request_log(env, calls, context) if config.request_log?
      report_to_ga4(env, calls, context) if config.enabled?
    rescue StandardError => e
      warn_failure("failed to record request", e)
      nil
    end

    def write_request_log(env, calls, context)
      calls.each do |call|
        request_log.write(call: call, request_id: env["action_dispatch.request_id"], **context)
      end
    end

    def report_to_ga4(env, calls, context)
      events = calls.map { |call| event_for(call, context) }
      return if events.empty?

      seed = Identity.seed(
        session_id: env["HTTP_MCP_SESSION_ID"],
        user_agent: env["HTTP_USER_AGENT"],
        ip: client_ip(env)
      )

      client.send_events(
        client_id: Identity.client_id(seed),
        session_id: Identity.session_id(seed),
        events: events
      )
    end

    def request_log
      @request_log ||= RequestLog.new(io: config.request_log_io, logger: config.logger)
    end

    def shared_context(env, mcp_request, outcome, status, duration_ms)
      {
        outcome: outcome,
        http_status: status.to_i,
        duration_ms: duration_ms,
        user_agent: env["HTTP_USER_AGENT"],
        client_name: mcp_request.client_name,
        client_version: mcp_request.client_version,
        protocol_version: mcp_request.protocol_version || env["HTTP_MCP_PROTOCOL_VERSION"]
      }
    end

    def calls_for(mcp_request, transport)
      calls = mcp_request.calls
      return calls unless calls.empty?

      [McpRequest::Call.new(method_name: "transport/#{transport.downcase}")]
    end

    def event_for(call, context)
      {
        name: Event.name_for(call.method_name),
        params: Event.params_for(call: call, **context)
      }
    end


    def outcome_for(status, headers, body)
      return "http_error" if status.to_i >= 400

      payload = peek_json(headers, body)
      return "unknown" if payload.nil?

      entries = payload.is_a?(Array) ? payload : [payload]
      return "error" if entries.any? { |entry| entry.is_a?(Hash) && entry["error"] }
      return "tool_error" if entries.any? { |entry| entry.is_a?(Hash) && entry.dig("result", "isError") }

      "success"
    end

    def peek_json(headers, body)
      content_type = headers.to_h.find { |key, _| key.to_s.casecmp("content-type").zero? }&.last.to_s
      sse = content_type.match?(SSE_CONTENT_TYPE)
      return nil unless sse || content_type.match?(JSON_CONTENT_TYPE)
      return nil unless body.is_a?(Array) && body.all?(String)

      joined = body.join
      return nil if joined.empty? || joined.bytesize > MAX_PEEK_BYTES

      JSON.parse(sse ? unwrap_sse(joined) : joined)
    rescue StandardError
      nil
    end

    # The transport may answer a single JSON-RPC response as one SSE frame.
    # Pull the payload out of the first `data:` line.
    def unwrap_sse(text)
      line = text.each_line.find { |candidate| candidate.start_with?("data:") }
      line.to_s.sub(/\Adata:\s*/, "")
    end

    def client_ip(env)
      forwarded = env["HTTP_X_FORWARDED_FOR"].to_s.split(",").first
      (forwarded || env["REMOTE_ADDR"]).to_s.strip
    end

    def client
      @client || McpAnalytics.client
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def elapsed_ms(started_at)
      ((monotonic_now - started_at) * 1000).round
    end

    # Step-by-step trace, debug mode only. Silence in the middle of this
    # sequence is how you find where a request stopped.
    def trace(message)
      config.logger&.info("[mcp_analytics] #{message}") if config.debug?
    rescue StandardError
      nil
    end

    def warn_failure(message, error)
      config.logger&.warn("[mcp_analytics] #{message}: #{error.class}: #{error.message}")
    end
  end
end
