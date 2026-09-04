require "net/http"
require "uri"
require "json"

class DatabusClient
  API_ENDPOINT_ENV = "ARTSDATA_API_ENDPOINT".freeze
  DEFAULT_API_ENDPOINT = "https://api.artsdata.ca".freeze
  LATEST_ARTIFACT_PATH = "/databus/artifact/latest".freeze

  DEFAULT_TIMEOUT_SECONDS = 10

  class Error < StandardError; end

  attr_reader :api_endpoint

  def self.api_endpoint
    ENV.fetch(API_ENDPOINT_ENV, DEFAULT_API_ENDPOINT)
  end

  def initialize(api_endpoint: self.class.api_endpoint, timeout: DEFAULT_TIMEOUT_SECONDS)
    @api_endpoint = api_endpoint.chomp("/")
    @timeout = timeout
  end

  # URL queried for the latest version of `artifact_uri`.
  def latest_artifact_url(artifact_uri)
    "#{api_endpoint}#{LATEST_ARTIFACT_PATH}?#{URI.encode_www_form('artifact' => artifact_uri)}"
  end

def latest_artifact(artifact_uri)
    url = latest_artifact_url(artifact_uri)
    response = get(url)

    raise Error, "HTTP #{response.code} from #{url}" unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    artifacts = body.is_a?(Hash) ? Array(body["artifacts"]) : []
    entry = artifacts.find { |a| a.is_a?(Hash) && a["artifact"] == artifact_uri } || artifacts.first

    raise Error, "no artifact found for #{artifact_uri}" unless entry.is_a?(Hash)
    raise Error, "Databus entry for #{artifact_uri} has no file" if entry["file"].blank?

    entry
  rescue JSON::ParserError => e
    raise Error, "invalid JSON from #{url}: #{e.message}"
  rescue Error
    raise
  rescue StandardError => e
    raise Error, "#{e.class}: #{e.message}"
  end

  private

  def get(location)
    uri = URI.parse(location)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: @timeout, read_timeout: @timeout) do |http|
      http.request(request)
    end
  end
end
