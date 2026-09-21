require "cgi"

module McpAnalytics
  # Configuration for the Google Analytics 4 integration.
  #
  # Only the two credentials and a debug switch come from the environment, so
  # they can be changed with a Heroku config var instead of a deploy. Everything
  # else is a constant: these are implementation details, not deployment
  # choices, and a knob nobody turns is just another thing to get wrong.
  #
  # The measurement id is not a secret and may live in env/*.env.
  # GA4_API_SECRET must only ever be set as a config var.
  class Configuration
    COLLECT_ENDPOINT = "https://www.google-analytics.com/mp/collect"
    DEBUG_ENDPOINT   = "https://www.google-analytics.com/debug/mp/collect"

    # The path the middleware watches. Matches the mount point in config/routes.rb.
    PATH_PREFIX = "/mcp"

    # Delivery is synchronous, so these are the worst case we are willing to add
    # to an MCP response when Google is slow or unreachable.
    OPEN_TIMEOUT = 1.0
    READ_TIMEOUT = 2.0

    # Request bodies above this size are passed through untouched but not parsed.
    MAX_BODY_BYTES = 256 * 1024

    attr_reader :measurement_id, :api_secret
    attr_accessor :logger

    def initialize(env = ENV)
      @measurement_id = presence(env["GA4_MEASUREMENT_ID"])
      @api_secret     = presence(env["GA4_API_SECRET"])
      @debug          = truthy?(env["GA4_DEBUG"])
      @logger         = nil
    end

    # Reporting is on as soon as both credentials are present, and off
    # otherwise. Unset either one to switch it off.
    def enabled?
      !measurement_id.nil? && !api_secret.nil?
    end

    # Debug mode does two things, neither of which stops an event being
    # recorded: it tags each event with debug_mode so it shows up in GA4's
    # DebugView within seconds, and it additionally posts the payload to the
    # validation endpoint so a malformed event is reported in the log.
    #
    # The validation step matters because /mp/collect answers 204 for valid and
    # invalid payloads alike -- it is the only way to be told an event name or
    # parameter was rejected.
    def debug?
      @debug
    end

    # Where real, recorded hits go. Always the collect endpoint.
    def collect_url
      with_credentials(COLLECT_ENDPOINT)
    end

    # Checks a payload and reports what is wrong with it. Records nothing.
    def validation_url
      with_credentials(DEBUG_ENDPOINT)
    end

    def path_prefix
      PATH_PREFIX
    end

    def open_timeout
      OPEN_TIMEOUT
    end

    def read_timeout
      READ_TIMEOUT
    end

    def max_body_bytes
      MAX_BODY_BYTES
    end

    private

    def with_credentials(base)
      "#{base}?measurement_id=#{CGI.escape(measurement_id.to_s)}" \
        "&api_secret=#{CGI.escape(api_secret.to_s)}"
    end

    def presence(value)
      value.nil? || value.to_s.strip.empty? ? nil : value.to_s.strip
    end

    def truthy?(value)
      %w[1 true t yes y on].include?(value.to_s.strip.downcase)
    end
  end

  class << self
    def config
      @config ||= Configuration.new
    end

    attr_writer :config

    def configure
      yield config
      config
    end

    # The delivery client. Overridable so tests can run the middleware end to
    # end without talking to Google.
    def client
      @client ||= Ga4Client.new(config)
    end

    attr_writer :client
  end
end
