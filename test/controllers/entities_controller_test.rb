require "test_helper"

class EntitiesEndpointsTest < ActionDispatch::IntegrationTest
  test "search-entities returns formatted payload" do
    with_env("ARTSDATA_SPARQL_ENDPOINT", "http://127.0.0.1:9/sparql") do
      get "/search-entities", params: { query: "example", lang: "en" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "search-entities", body["tool"]
    assert_kind_of String, body["result"]
    assert_equal({ "query" => "example", "lang" => "en" }, body["arguments"])
  end

  test "entities returns formatted payload" do
    with_env("ARTSDATA_SPARQL_ENDPOINT", "http://127.0.0.1:9/sparql") do
      get "/entities", params: { id: "Q42", lang: "en" }
    end

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "get_statements", body["tool"]
    assert_kind_of String, body["result"]
    assert_equal(
      { "entity_id" => "Q42", "include_external_ids" => false, "lang" => "en" },
      body["arguments"]
    )
  end

  test "invalid lang returns 422" do
    get "/search-entities", params: { query: "example", lang: "es" }

    assert_response :unprocessable_content
  end

  test "search-entities includes cors headers" do
    with_env("ARTSDATA_SPARQL_ENDPOINT", "http://127.0.0.1:9/sparql") do
      get "/search-entities", params: { query: "example", lang: "en" }, headers: { "Origin" => "https://client.example" }
    end

    assert_response :success
    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
  end

  test "mcp tools/list returns tools metadata" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 1, body["id"]
    assert_equal %w[search_entities get_entity], body.dig("result", "tools").map { |tool| tool["name"] }
  end

  test "mcp unknown method returns method not found error" do
    post "/mcp", params: { jsonrpc: "2.0", id: 2, method: "unknown/method", params: {} }, as: :json

    assert_response :not_found
    body = JSON.parse(response.body)
    assert_equal "2.0", body["jsonrpc"]
    assert_equal 2, body["id"]
    assert_equal(-32601, body.dig("error", "code"))
    assert_equal "Method not found", body.dig("error", "message")
  end

  private

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end
end
