require "test_helper"
require "minitest/mock"

class DatabusClientTest < ActiveSupport::TestCase
  API_ENDPOINT = "https://api.example.test".freeze
  ARTIFACT_URI = "http://kg.artsdata.ca/databus/culture-creates/artsdata-dump/core-minus-provenance".freeze
  FILE_URL = "https://artsdata-graphdb-backups.s3.ca-central-1.amazonaws.com/core-graph-minus-provenance/monthly/artsdata-2026-09-01-core-minus-provenance.ttl.gz".freeze


  test "latest_artifact_url percent-encodes the artifact uri and drops a trailing slash" do
    client = DatabusClient.new(api_endpoint: "#{API_ENDPOINT}/")

    assert_equal "#{API_ENDPOINT}/databus/artifact/latest?artifact=http%3A%2F%2Fkg.artsdata.ca%2F" \
                 "databus%2Fculture-creates%2Fartsdata-dump%2Fcore-minus-provenance",
                 client.latest_artifact_url(ARTIFACT_URI)
  end

  test "latest_artifact returns the Databus entry for the requested artifact" do
    captured = {}
    entry = with_stubbed_http([ok(fixture)], captured) { client.latest_artifact(ARTIFACT_URI) }

    assert_equal ["api.example.test"], captured[:hosts]
    assert_kind_of Net::HTTP::Get, captured[:requests].first
    assert_equal "application/json", captured[:requests].first["accept"]
    assert_equal client.latest_artifact_url(ARTIFACT_URI),
                 "#{API_ENDPOINT}#{captured[:requests].first.path}"

    assert_equal ARTIFACT_URI, entry["artifact"]
    assert_equal FILE_URL, entry["file"]
    assert_equal "2026-09-01T05_18_57", entry["latestVersion"]
  end

  private

  def client
    @client ||= DatabusClient.new(api_endpoint: API_ENDPOINT)
  end

  def fixture
    File.read(Rails.root.join("test", "fixtures", "databus_artifact_latest.json"))
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
    captured[:requests] = []

    fake_start = lambda do |host, _port, **_opts, &block|
      captured[:hosts] << host
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
