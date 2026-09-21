# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module McpAnalytics
  class Ga4Client
    # Measurement Protocol caps a single payload at 25 events.
    MAX_EVENTS_PER_PAYLOAD = 25

    def initialize(config = McpAnalytics.config)
      @config = config
    end

    # @param events [Array<Hash>] each { name:, params: }
    # @return [Symbol] :sent, :failed, :disabled or :empty
    def send_events(client_id:, session_id:, events:, occurred_at: Time.now)
      return :disabled unless @config.enabled?
      return :empty if events.nil? || events.empty?

      body = JSON.generate(
        payload_for(client_id, session_id, events, occurred_at)
      )

      report_validation(body) if @config.debug?
      post(@config.collect_url, body)
    end

    private

    def payload_for(client_id, session_id, events, occurred_at = Time.now)
      {
        client_id: client_id,
        timestamp_micros: (occurred_at.to_f * 1_000_000).round,
        non_personalized_ads: true,
        events: events.first(MAX_EVENTS_PER_PAYLOAD).map do |event|
          { name: event[:name], params: event_params(event, session_id) }
        end
      }
    end

    def event_params(event, session_id)
      params = event[:params].merge(
        session_id: session_id,
        # GA4 discards events with no engagement time; 1ms is the
        # conventional placeholder for server-side hits.
        engagement_time_msec: 1
      )
      params[:debug_mode] = 1 if @config.debug?
      params
    end

    def post(url, body)
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout
      http.write_timeout = @config.read_timeout if http.respond_to?(:write_timeout=)

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = body

      response = http.request(request)
      logger&.info("[mcp_analytics] GA4 responded #{response.code} to #{body}") if @config.debug?
      :sent
    rescue StandardError => e
      # Analytics must never take the server down with it.
      logger&.warn("[mcp_analytics] GA4 delivery failed: #{e.class}: #{e.message}")
      :failed
    end

    # Asks GA4 what is wrong with the payload and logs the answer. Never raises
    # and never affects whether the real hit is sent.
    def report_validation(body)
      uri = URI.parse(@config.validation_url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @config.open_timeout
      http.read_timeout = @config.read_timeout

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = body

      messages = JSON.parse(http.request(request).body.to_s)["validationMessages"]
      if messages.nil? || messages.empty?
        logger&.info("[mcp_analytics] payload valid")
      else
        logger&.warn("[mcp_analytics] GA4 rejected this payload: #{messages.inspect}")
      end
    rescue StandardError => e
      logger&.warn("[mcp_analytics] could not validate payload: #{e.class}: #{e.message}")
    end

    def logger
      @config.logger
    end
  end
end
