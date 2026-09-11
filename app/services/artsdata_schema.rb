require "net/http"
require "uri"

# The Artsdata data model (Artsdata Ontology + CORE graph SHACL shapes) as a query-ready digest.
#
# The source of truth is https://docs.artsdata.ca/artsdata-schema.ttl, generated in
# culturecreates/artsdata-data-model. It is fetched at runtime so the digest follows the ontology,
# compiled once, and cached in-process for CACHE_TTL_SECONDS. If a refresh cannot fetch or parse
# the file, the last good digest is kept; if there is none yet, the error is raised.
class ArtsdataSchema
  SOURCE_URL_ENV = "ARTSDATA_SCHEMA_URL".freeze
  DEFAULT_SOURCE_URL = "https://docs.artsdata.ca/artsdata-schema.ttl".freeze
  SPARQL_ENDPOINT = "https://query.artsdata.ca/query".freeze

  CACHE_TTL_ENV = "ARTSDATA_SCHEMA_CACHE_TTL_SECONDS".freeze
  DEFAULT_CACHE_TTL_SECONDS = 24 * 60 * 60
  DEFAULT_TIMEOUT_SECONDS = 10

  # How to read the digest and write SPARQL against it. Kept short and limited to what the schema
  # itself states; edit freely as sparql_query usage shows where agents stumble.
  CONVENTIONS = [
    "Use the `prefixes` verbatim in SPARQL. schema: is http://schema.org/ (http, not https).",
    "`classes` lists the entity types of the Artsdata CORE graph (the reconciled graph of Artsdata-minted " \
      "entities, adr: = http://kg.artsdata.ca/resource/) and the properties each is validated against. " \
      "`required: true` means every entity of that class is expected to have the property; wrap all other " \
      "properties in OPTIONAL { }.",
    "A property whose `pattern` is ^http://kg\\.artsdata\\.ca/resource/ links to another Artsdata entity " \
      "(an adr: URI), not to text. To filter or display it by name, join to that entity's schema:name - " \
      "unless it is a skos:Concept (see `vocabularies`), which uses skos:prefLabel instead; concepts do " \
      "not have schema:name.",
    "Text such as schema:name is usually language-tagged (rdf:langString), at most one value per language. " \
      "A plain string never equals a tagged one: compare with STR(?x), e.g. " \
      "FILTER(CONTAINS(LCASE(STR(?name)), \"jazz\")), and pick a language with FILTER(LANG(?name) = \"en\"). " \
      "This STR() rule is only for text - it does not apply to typed literals such as dates or numbers.",
    "A property whose `datatypes` includes xsd:date or xsd:dateTime (e.g. schema:startDate, " \
      "schema:endDate) is a typed literal, not text: compare or filter it directly against a typed " \
      "literal, e.g. FILTER(?startDate >= \"2026-01-01T00:00:00\"^^xsd:dateTime), never with STR().",
    "`in` lists the only allowed values. `value_shape` describes the node a property points to " \
      "(e.g. an image or a postal address).",
    "Properties listed under `vocabularies` point to skos:Concept URIs in an Artsdata controlled vocabulary; " \
      "list a vocabulary's concepts with ?concept skos:inScheme <scheme>. Concepts can be owl:deprecated.",
    "`equivalent_classes`, `subclass_of`, `sub_property_of` and `equivalent_properties` come from the " \
      "Artsdata Ontology (OWL-Horst profile). Query with the `class` and `path` names listed here.",
    "This describes what the CORE graph is validated against, not every triple in it: entities can carry " \
      "properties that are not listed."
  ].freeze

  MUTEX = Mutex.new

  class << self
    # The cached digest, reloaded after the cache TTL.
    def digest
      MUTEX.synchronize do
        if @digest.nil? || monotonic_now - @loaded_at > cache_ttl
          @digest = new.load(previous: @digest)
          @loaded_at = monotonic_now
        end
        @digest
      end
    end

    def reset_cache!
      MUTEX.synchronize { @digest = nil }
    end

    def cache_ttl
      Integer(ENV.fetch(CACHE_TTL_ENV, DEFAULT_CACHE_TTL_SECONDS))
    end

    private

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  attr_reader :source_url

  def initialize(source_url: ENV.fetch(SOURCE_URL_ENV, DEFAULT_SOURCE_URL),
                 timeout: DEFAULT_TIMEOUT_SECONDS)
    @source_url = source_url
    @timeout = timeout
  end

  # Fetches and compiles the live file. On failure, returns the previous digest if there is one,
  # otherwise raises.
  def load(previous: nil)
    compile(fetch_remote)
  rescue StandardError => e
    raise unless previous

    Rails.logger.warn("ArtsdataSchema: could not load #{source_url} (#{e.class}: #{e.message}); " \
                      "keeping the previously loaded schema")
    previous
  end

  def compile(turtle)
    digest = ShaclSchemaCompiler.compile_turtle(turtle)
    about = digest.fetch("about", {}).merge(
      "source" => source_url,
      "sparql_endpoint" => SPARQL_ENDPOINT
    )
    { "about" => about, "conventions" => CONVENTIONS }.merge(digest.except("about"))
  end

  def fetch_remote
    uri = URI.parse(source_url)
    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "text/turtle"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: @timeout, read_timeout: @timeout) do |http|
      http.request(request)
    end
    raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    response.body.force_encoding(Encoding::UTF_8)
  end
end
