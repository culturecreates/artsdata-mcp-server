# frozen_string_literal: true

require "json"

require_relative "sparql"

module McpAnalytics

  class McpRequest
    Call = Struct.new(:method_name, :tool_name, :resource_uri, :prompt_name,
                      :arguments, :sparql_form, :sparql_where, keyword_init: true)

    attr_reader :calls, :client_name, :client_version, :protocol_version

    def initialize(raw_body)
      @calls = []
      @client_name = nil
      @client_version = nil
      @protocol_version = nil

      parse(raw_body)
    end

    private

    def parse(raw_body)
      return if raw_body.nil? || raw_body.empty?

      payload = JSON.parse(raw_body.dup.force_encoding(Encoding::UTF_8))
      entries = payload.is_a?(Array) ? payload : [payload]

      entries.each do |entry|
        next unless entry.is_a?(Hash)

        call = build_call(entry)
        @calls << call if call
        extract_client_info(entry) if entry["method"] == "initialize"
      end
    rescue JSON::ParserError, ArgumentError, EncodingError
      # Not JSON, or not valid UTF-8. Nothing to extract.
      nil
    end

    def build_call(entry)
      method_name = entry["method"].to_s
      return nil if method_name.empty?

      params = entry["params"].is_a?(Hash) ? entry["params"] : {}
      tool_name = (presence(params["name"]) if method_name == "tools/call")
      arguments = (params["arguments"] if method_name == "tools/call" &&
                                          params["arguments"].is_a?(Hash))
      query = (presence(arguments["query"]) if tool_name == "sparql_query" && arguments)

      Call.new(
        method_name: method_name,
        tool_name: tool_name,
        resource_uri: (presence(params["uri"]) if method_name.start_with?("resources/")),
        prompt_name: (presence(params["name"]) if method_name == "prompts/get"),
        arguments: arguments,
        sparql_form: (Sparql.form(query) if query),
        sparql_where: (Sparql.where_clause(query) if query)
      )
    end

    def extract_client_info(entry)
      params = entry["params"].is_a?(Hash) ? entry["params"] : {}
      info = params["clientInfo"].is_a?(Hash) ? params["clientInfo"] : {}

      @client_name = presence(info["name"])
      @client_version = presence(info["version"])
      @protocol_version = presence(params["protocolVersion"])
    end

    def presence(value)
      value.nil? || value.to_s.strip.empty? ? nil : value.to_s.strip
    end
  end
end
