require "test_helper"
require "net/http"

class ArtsdataClientTest < ActiveSupport::TestCase
  test "search_items uses reconciliation api and formats candidates" do
    response_body = {
      "results" => [
        {
          "candidates" => [
            {
              "id" => "K2-5280",
              "name" => "Centre Expo-Festival Center",
              "description" => "performing arts presenting organization in Wellington"
            },
            {
              "id" => "K5-1221",
              "name" => "Centre Christ-Roy, FCL Center",
              "description" => "street_address at 1452 Rue Gigaire"
            }
          ]
        }
      ]
    }

    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.instance_variable_set(:@read, true)
    response.instance_variable_set(:@body, JSON.generate(response_body))
    captured_request = nil

    original_start = Net::HTTP.method(:start)
    Net::HTTP.singleton_class.define_method(:start) do |_host, _port, use_ssl:, &block|
      fake_http = Object.new
      fake_http.define_singleton_method(:request) do |request|
        captured_request = request
        response
      end
      block.call(fake_http)
    end

    begin
      client = ArtsdataClient.new(reconciliation_endpoint: "https://recon.artsdata.ca/match")
      result = client.search_items(query: "Benny Jones", lang: "en")

      assert_equal(
        "K2-5280: Centre Expo-Festival Center — performing arts presenting organization in Wellington\n" \
        "K5-1221: Centre Christ-Roy, FCL Center — street_address at 1452 Rue Gigaire",
        result
      )
    ensure
      Net::HTTP.singleton_class.define_method(:start, original_start)
    end

    assert_equal "application/json", captured_request["Content-Type"]
    assert_equal(
      {
        "queries" => [
          {
            "limit" => 50,
            "conditions" => [
              {
                "matchType" => "name",
                "propertyValue" => "Benny Jones",
                "required" => true
              }
            ]
          }
        ]
      },
      JSON.parse(captured_request.body)
    )
  end
end
