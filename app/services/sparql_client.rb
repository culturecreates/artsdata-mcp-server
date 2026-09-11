require "net/http"
require "uri"
require "json"

# Thin client for the Artsdata SPARQL endpoint (GraphDB / RDF4J protocol).
#
# It sends a query exactly as written and hands back the endpoint's SPARQL 1.1 Query Results JSON.
# There is no query building or rewriting here. The only things it adds are guard rails so an agent
# cannot hurt the server or itself: read-only query forms, a timeout, and a row cap on the result.
class SparqlClient
  ENDPOINT_ENV = "ARTSDATA_SPARQL_ENDPOINT".freeze
  DEFAULT_ENDPOINT = "https://query.artsdata.ca/query".freeze

  # Kept under Heroku's 30 s router timeout, so a slow query fails with a useful message instead of
  # an H12 on the whole MCP request.
  TIMEOUT_ENV = "ARTSDATA_SPARQL_TIMEOUT_SECONDS".freeze
  DEFAULT_TIMEOUT_SECONDS = 25
  OPEN_TIMEOUT_SECONDS = 10

  MAX_ROWS_ENV = "ARTSDATA_SPARQL_MAX_ROWS".freeze
  DEFAULT_MAX_ROWS = 1000

  RESULTS_MEDIA_TYPE = "application/sparql-results+json".freeze

  # Query forms whose result is SPARQL Results JSON. CONSTRUCT/DESCRIBE return RDF instead, and
  # anything else (INSERT, DELETE, LOAD, CLEAR, ...) is an update.
  RESULT_FORMS = %i[select ask].freeze

  # The prologue (whitespace, comments, BASE and PREFIX declarations) that may precede the query form.
  # IRIs are matched as whole <...> tokens, so a '#' inside an IRI is not mistaken for a comment.
  PROLOGUE = /\A(?:\s+|#[^\n]*|BASE\s*<[^>]*>|PREFIX\s+[^\s:]*:\s*<[^>]*>)*/i
  QUERY_FORM = /\A(SELECT|ASK|CONSTRUCT|DESCRIBE)\b/i

  MAX_ERROR_MESSAGE_LENGTH = 2000

  class Error < StandardError; end

  # The endpoint rejected the query itself (HTTP 400: syntax error, unknown prefix, ...). The message
  # is the endpoint's own explanation, which is what an agent needs to fix the query.
  class QueryError < Error; end

  class << self
    def endpoint
      ENV.fetch(ENDPOINT_ENV, DEFAULT_ENDPOINT)
    end

    def timeout
      Integer(ENV.fetch(TIMEOUT_ENV, DEFAULT_TIMEOUT_SECONDS))
    end

    def max_rows
      Integer(ENV.fetch(MAX_ROWS_ENV, DEFAULT_MAX_ROWS))
    end

    # :select, :ask, :construct, :describe, or nil when the query starts with anything else.
    def query_form(query)
      rest = query.to_s.sub(PROLOGUE, "")
      rest[QUERY_FORM, 1]&.downcase&.to_sym
    end
  end

  attr_reader :endpoint, :timeout, :max_rows

  def initialize(endpoint: self.class.endpoint, timeout: self.class.timeout, max_rows: self.class.max_rows)
    @endpoint = endpoint
    @timeout = timeout
    @max_rows = max_rows
  end

  # Runs a SELECT or ASK query and returns the parsed SPARQL Results JSON. If a SELECT returns more
  # than max_rows bindings, only the first max_rows are kept and "truncated" => true is added.
  def query(query)
    form = self.class.query_form(query)
    unless RESULT_FORMS.include?(form)
      raise QueryError, "Only SELECT queries are supported" \
                        "#{form ? " (got #{form.to_s.upcase})" : ""}. " \
                        "Rewrite the query as a SELECT; use get_entity to get an entity's details."
    end

    cap_rows(parse(post(query)))
  end

  private

  def post(query)
    uri = URI.parse(endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Accept"] = RESULTS_MEDIA_TYPE
    request.set_form_data("query" => query)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: OPEN_TIMEOUT_SECONDS, read_timeout: timeout) do |http|
      http.request(request)
    end

    return response.body.to_s.force_encoding(Encoding::UTF_8) if response.is_a?(Net::HTTPSuccess)

    message = endpoint_message(response)
    if response.is_a?(Net::HTTPBadRequest)
      raise QueryError, "The SPARQL endpoint rejected the query: #{message}"
    end

    raise Error, "The SPARQL endpoint returned HTTP #{response.code}#{": #{message}" if message.present?}"
  rescue Net::OpenTimeout, Net::ReadTimeout
    raise Error, "The query did not finish within #{timeout} seconds. Narrow it (more specific " \
                 "patterns, filters on typed or linked values before text filters) and add a LIMIT."
  rescue Error
    raise
  rescue StandardError => e
    Rails.logger.error("SparqlClient: request to #{endpoint} failed: #{e.class}: #{e.message}")
    raise Error, "Could not reach the SPARQL endpoint."
  end

  def parse(body)
    result = JSON.parse(body)
    unless result.is_a?(Hash) && (result.key?("results") || result.key?("boolean"))
      raise Error, "The SPARQL endpoint returned an unexpected response."
    end

    result
  rescue JSON::ParserError
    raise Error, "The SPARQL endpoint returned a response that is not SPARQL Results JSON."
  end

  def cap_rows(result)
    bindings = result.dig("results", "bindings")
    return result unless bindings.is_a?(Array) && bindings.size > max_rows

    result.merge(
      "results" => result["results"].merge("bindings" => bindings.first(max_rows)),
      "truncated" => true
    )
  end

  def endpoint_message(response)
    response.body.to_s.force_encoding(Encoding::UTF_8).scrub.strip.truncate(MAX_ERROR_MESSAGE_LENGTH)
  end
end
