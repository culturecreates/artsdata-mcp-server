require "test_helper"
require "minitest/mock"

class SparqlClientTest < ActiveSupport::TestCase
  ENDPOINT = "https://sparql.example.test/query".freeze

  SELECT_QUERY = <<~SPARQL.freeze
    # Events and their names
    PREFIX schema: <http://schema.org/>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    SELECT ?event ?name WHERE {
      ?event a schema:Event ; schema:name ?name .
    } LIMIT 2
  SPARQL

  SELECT_RESULT = {
    "head" => { "vars" => %w[event name] },
    "results" => {
      "bindings" => [
        { "event" => { "type" => "uri", "value" => "http://kg.artsdata.ca/resource/K11-1" },
          "name" => { "type" => "literal", "value" => "Concert", "xml:lang" => "en" } },
        { "event" => { "type" => "uri", "value" => "http://kg.artsdata.ca/resource/K11-2" },
          "name" => { "type" => "literal", "value" => "Spectacle", "xml:lang" => "fr" } }
      ]
    }
  }.freeze

  test "query_form skips comments, BASE and PREFIX declarations, including '#' inside IRIs" do
    assert_equal :select, SparqlClient.query_form(SELECT_QUERY)
    assert_equal :ask, SparqlClient.query_form("ask { ?s ?p ?o }")
    assert_equal :select, SparqlClient.query_form("BASE <http://example.org/#>\nPREFIX : <http://example.org/#>\nselect * { ?s ?p ?o }")
    assert_equal :construct, SparqlClient.query_form("CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }")
    assert_equal :describe, SparqlClient.query_form("DESCRIBE <http://kg.artsdata.ca/resource/K11-1>")
    assert_nil SparqlClient.query_form("PREFIX schema: <http://schema.org/>\nINSERT DATA { <urn:a> schema:name \"x\" }")
    assert_nil SparqlClient.query_form("WITH <urn:g> DELETE { ?s ?p ?o } WHERE { ?s ?p ?o }")
    assert_nil SparqlClient.query_form("# SELECT only in a comment\nDROP ALL")
    assert_nil SparqlClient.query_form("SELECTED")
  end

  test "query POSTs the query unchanged as a form parameter and returns the SPARQL results JSON" do
    captured = {}
    result = with_stubbed_http([ok(SELECT_RESULT.to_json)], captured) { client.query(SELECT_QUERY) }

    assert_equal SELECT_RESULT, result
    assert_equal ["sparql.example.test"], captured[:hosts]
    assert_equal({ use_ssl: true, open_timeout: SparqlClient::OPEN_TIMEOUT_SECONDS, read_timeout: 25 },
                 captured[:options].first)

    request = captured[:requests].first
    assert_kind_of Net::HTTP::Post, request
    assert_equal "/query", request.path
    assert_equal "application/sparql-results+json", request["accept"]
    assert_equal [["query", SELECT_QUERY]], URI.decode_www_form(request.body)
  end

  test "query returns an ASK result" do
    body = { "head" => {}, "boolean" => true }
    result = with_stubbed_http([ok(body.to_json)]) { client.query("ASK { ?s ?p ?o }") }

    assert_equal body, result
  end

  test "query keeps the first max_rows bindings and flags the result as truncated" do
    result = with_stubbed_http([ok(SELECT_RESULT.to_json)]) do
      SparqlClient.new(endpoint: ENDPOINT, max_rows: 1).query(SELECT_QUERY)
    end

    assert_equal true, result["truncated"]
    assert_equal SELECT_RESULT["head"], result["head"]
    assert_equal SELECT_RESULT.dig("results", "bindings").first(1), result.dig("results", "bindings")
  end

  test "query does not flag a result within max_rows as truncated" do
    result = with_stubbed_http([ok(SELECT_RESULT.to_json)]) do
      SparqlClient.new(endpoint: ENDPOINT, max_rows: 2).query(SELECT_QUERY)
    end

    refute result.key?("truncated")
  end

  test "query refuses updates and non-results query forms without calling the endpoint" do
    captured = {}
    ["INSERT DATA { <urn:a> <urn:b> <urn:c> }", "CONSTRUCT { ?s ?p ?o } WHERE { ?s ?p ?o }", "not sparql"].each do |query|
      error = assert_raises(SparqlClient::QueryError) do
        with_stubbed_http([], captured) { client.query(query) }
      end
      assert_match(/Only SELECT and ASK queries are supported/, error.message)
    end

    assert_empty captured[:requests]
  end

  test "query raises a QueryError carrying the endpoint's message when it rejects the query" do
    message = "MALFORMED QUERY: Encountered \" \"}\" at line 1, column 20."
    error = assert_raises(SparqlClient::QueryError) do
      with_stubbed_http([http_response(Net::HTTPBadRequest, "400", message)]) { client.query("SELECT * { ?s ?p }") }
    end

    assert_equal "The SPARQL endpoint rejected the query: #{message}", error.message
  end

  test "query raises an Error on other HTTP failures, timeouts, unreachable hosts and non-JSON bodies" do
    failures = {
      http_response(Net::HTTPServiceUnavailable, "503", "down") => /HTTP 503: down/,
      Net::ReadTimeout.new => /did not finish within 25 seconds/,
      SocketError.new("getaddrinfo") => /Could not reach the SPARQL endpoint/,
      ok("<html>proxy</html>") => /not SPARQL Results JSON/,
      ok({ "@context" => {} }.to_json) => /unexpected response/
    }

    failures.each do |response, message|
      error = assert_raises(SparqlClient::Error) { with_stubbed_http([response]) { client.query(SELECT_QUERY) } }
      refute_kind_of SparqlClient::QueryError, error
      assert_match message, error.message
    end
  end

  test "endpoint defaults to query.artsdata.ca and follows ARTSDATA_SPARQL_ENDPOINT" do
    original = ENV.delete(SparqlClient::ENDPOINT_ENV)
    assert_equal "https://query.artsdata.ca/query", SparqlClient.new.endpoint

    ENV[SparqlClient::ENDPOINT_ENV] = ENDPOINT
    assert_equal ENDPOINT, SparqlClient.new.endpoint
  ensure
    if original
      ENV[SparqlClient::ENDPOINT_ENV] = original
    else
      ENV.delete(SparqlClient::ENDPOINT_ENV)
    end
  end

  private

  def client
    @client ||= SparqlClient.new(endpoint: ENDPOINT, timeout: 25)
  end

  def ok(body)
    http_response(Net::HTTPOK, "200", body)
  end

  def http_response(klass, code, body = "")
    response = klass.new("1.1", code, klass.name.demodulize)
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def with_stubbed_http(responses, captured = {})
    queue = responses.dup
    captured[:hosts] = []
    captured[:options] = []
    captured[:requests] = []

    fake_start = lambda do |host, _port, **options, &block|
      captured[:hosts] << host
      captured[:options] << options
      http = Object.new
      http.define_singleton_method(:request) do |request|
        captured[:requests] << request
        next_response = queue.shift || raise("no more stubbed responses")
        raise next_response if next_response.is_a?(Exception)

        next_response
      end
      block.call(http)
    end

    Net::HTTP.stub(:start, fake_start) { yield }
  end
end
