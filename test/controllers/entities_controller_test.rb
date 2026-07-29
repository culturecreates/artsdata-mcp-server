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

  private

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end
end
