require "net/http"
require "uri"
require "time"
require "nokogiri"

# Finds the most recent Artsdata data dump in the public S3 bucket where dumps are published.
#
class DataDumpClient
  BUCKET_URL_ENV = "ARTSDATA_DUMPS_BUCKET_URL".freeze
  DEFAULT_BUCKET_URL = "https://artsdata-graphdb-backups.s3.ca-central-1.amazonaws.com".freeze

  EVENTS_PREFIX_ENV = "ARTSDATA_DUMP_FOLDER".freeze
  DEFAULT_EVENTS_PREFIX = "core-graph-minus-provenance/monthly/".freeze

  DUMP_EXTENSION = ".ttl.gz".freeze
  DUMP_CONTENT_TYPE = "application/gzip".freeze
  DUMP_FORMAT = "text/turtle".freeze

  MAX_PAGES = 20
  DEFAULT_TIMEOUT_SECONDS = 10

  attr_reader :bucket_url, :prefix

  def self.bucket_url
    ENV.fetch(BUCKET_URL_ENV, DEFAULT_BUCKET_URL)
  end

  def self.events_prefix
    ENV.fetch(EVENTS_PREFIX_ENV, DEFAULT_EVENTS_PREFIX)
  end

  def initialize(bucket_url: self.class.bucket_url, prefix: self.class.events_prefix,
                 extension: DUMP_EXTENSION, timeout: DEFAULT_TIMEOUT_SECONDS)
    @bucket_url = bucket_url.chomp("/")
    @prefix = prefix
    @extension = extension
    @timeout = timeout
  end

  # URL of the anonymous S3 listing this client reads. Handy for debugging and for the manifest.
  def listing_url(continuation_token: nil)
    params = { "list-type" => "2", "prefix" => prefix }
    params["continuation-token"] = continuation_token if continuation_token
    "#{bucket_url}/?#{URI.encode_www_form(params)}"
  end

  # Returns a plain Hash describing the latest dump. Never raises: when the bucket cannot be
  # listed the Hash still carries the listing URL, with "available" => false and an "error"
  # explaining why, so the MCP resource stays readable even while S3 is unreachable.
  def metadata
    checked_at = Time.now.utc.iso8601
    objects = list_objects
    dumps = objects.select { |o| o["key"].end_with?(@extension) }
    latest = dumps.max_by { |o| o["last_modified"] }

    return unavailable(checked_at, "no #{@extension} objects found under #{prefix}") if latest.nil?

    {
      "url" => object_url(latest["key"]),
      "available" => true,
      "content_type" => DUMP_CONTENT_TYPE,
      "format" => DUMP_FORMAT,
      "size" => latest["size"],
      "last_modified" => latest["last_modified"],
      "checked_at" => checked_at
    }.compact
  rescue StandardError => e
    Rails.logger.error("DataDumpClient#metadata failed for #{listing_url}: #{e.class}: #{e.message}")
    unavailable(Time.now.utc.iso8601, "#{e.class}: #{e.message}")
  end

 def list_objects
    objects = []
    token = nil

    MAX_PAGES.times do
      page = fetch_listing_page(continuation_token: token)
      objects.concat(page[:objects])
      token = page[:next_token]
      break if token.nil?
    end

    objects.sort_by { |o| o["last_modified"] }
  end

  def object_url(key)
    "#{bucket_url}/#{key.split('/').map { |segment| URI.encode_www_form_component(segment) }.join('/')}"
  end

  private

  def unavailable(checked_at, error)
    { "available" => false, "listing_url" => listing_url, "error" => error, "checked_at" => checked_at }
  end

  def fetch_listing_page(continuation_token: nil)
    response = get(listing_url(continuation_token: continuation_token))
    raise "HTTP #{response.code} from #{bucket_url}" unless response.is_a?(Net::HTTPSuccess)

    parse_listing(response.body)
  end

  def parse_listing(xml)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!

    error = doc.at_xpath("/Error")
    raise "S3 error #{error.at_xpath('Code')&.text}: #{error.at_xpath('Message')&.text}" if error

    objects = doc.xpath("//Contents").map do |node|
      {
        "key" => node.at_xpath("Key")&.text,
        "size" => node.at_xpath("Size")&.text&.to_i,
        "last_modified" => parse_time(node.at_xpath("LastModified")&.text)
      }
    end

    truncated = doc.at_xpath("//IsTruncated")&.text == "true"
    next_token = truncated ? doc.at_xpath("//NextContinuationToken")&.text : nil

    { objects: objects, next_token: next_token.presence }
  end

  def get(location)
    uri = URI.parse(location)
    request = Net::HTTP::Get.new(uri)

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: @timeout, read_timeout: @timeout) do |http|
      http.request(request)
    end
  end

  def parse_time(value)
    return nil if value.blank?

    Time.iso8601(value).utc.iso8601
  rescue ArgumentError
    value
  end
end
