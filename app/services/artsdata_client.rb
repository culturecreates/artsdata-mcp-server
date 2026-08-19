require "net/http"
require "uri"
require "json"

class ArtsdataClient

  SCHEMA_BASE_URL = 'http://schema.org/'.freeze
  ARTSDATA_BASE_URL = 'http://kg.artsdata.ca/resource/'.freeze

  RDF_TYPE_PROPERTY_ID = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'.freeze
  LOCATION_NAME_PROPERTY_ID = 'schema:location/schema:name'.freeze
  PERFORMER_NAME_PROPERTY_ID = 'schema:performer/schema:name'.freeze
  ORGANIZER_NAME_PROPERTY_ID = 'schema:organizer/schema:name'.freeze

  attr_reader :reconciliation_endpoint

  def initialize(
    reconciliation_endpoint: ENV.fetch("ARTSDATA_MATCH_RECONCILIATION_ENDPOINT", "https://recon.artsdata.ca/")
  )
    @reconciliation_endpoint = reconciliation_endpoint
  end

  def search_items(query:, types:, lang:, limit:)

    types_array = Array(types).compact
    type_uris = types_array.map { |t| t.start_with?("http") ? t : "#{SCHEMA_BASE_URL}#{t}" }

    conditions = [
      {
        matchType: "name",
        propertyValue: query,
        required: true
      }
    ]

    if type_uris.size > 1
      conditions << {
        matchType: 'property',
        propertyId: RDF_TYPE_PROPERTY_ID,
        propertyValue: type_uris,
        required: true,
        matchQuantifier: 'any'
      }

      query_type = nil
    else
      query_type = type_uris.first
    end

    payload = {
      queries: [
        {
          limit: limit,
          type: query_type,
          conditions: conditions
        }.compact
      ]
    }

    body = execute_reconciliation_query(payload, lang: lang, route: 'match')
    format_search_results(body.fetch("results", []))
  end

  def format_get_entity_results(rows)
    item = rows.first
    result = {
      "id" => item["id"],
      "uri" => "http://kg.artsdata.ca/resource/#{item['id']}"
    }

    item["properties"].each do |prop|
      key = prop["id"]

      result[key] = prop["values"].map do |val|
        if val.key?("str")
          obj = { "value" => val["str"] }
          obj["language"] = val["lang"] if val.key?("lang")
          obj
        elsif val.key?("id")
          val["id"]
        else
          val
        end
      end
    end
    result
  end

  def get_entity(uri:)

    id = uri.split('/').last

    payload = {
      "ids": [id],
      "properties": [
        { "id": "name" },
        { "id": "url" },
        { "id": "sameAs" },
        { "id": "disambiguatingDescription" }
      ]
    }

    body = execute_reconciliation_query(payload, route: 'extend')
    format_get_entity_results(body.fetch("rows", []))
  end

  def search_events(places:, artists:, organizations:, types:, language:, limit:)
    types_array = Array(types).compact
    type_uris = types_array.map { |t| t.start_with?("http") ? t : "#{SCHEMA_BASE_URL}#{t}" }

    # merge artists and organizations
    agents = artists.union(organizations)

    conditions = []
    if places.size > 0
      conditions.push({
                        matchType: "property",
                        propertyId: LOCATION_NAME_PROPERTY_ID,
                        propertyValue: places,
                        required: true,
                        matchQuantifier: 'any'
                      })
    end

    if agents.size > 0
      conditions.push({
                        matchType: "property",
                        propertyId: ORGANIZER_NAME_PROPERTY_ID,
                        propertyValue: agents,
                        required: false,
                        matchQuantifier: 'any'
                      })

      conditions.push({
                        matchType: "property",
                        propertyId: PERFORMER_NAME_PROPERTY_ID,
                        propertyValue: agents,
                        required: false,
                        matchQuantifier: 'any'
                      })
    end

    if type_uris.size == 0
      query_type = "#{SCHEMA_BASE_URL}Event"
    elsif type_uris.size > 1
      conditions.push({
                        matchType: 'property',
                        propertyId: RDF_TYPE_PROPERTY_ID,
                        propertyValue: type_uris,
                        required: true,
                        matchQuantifier: 'any'

                      })

      query_type = nil
    else
      query_type = type_uris.first
    end

    payload = {
      queries: [
        {
          limit: limit,
          type: query_type,
          conditions: conditions
        }.compact
      ]
    }

    data = execute_reconciliation_query(payload, lang: language, route: 'match')

    details = data["results"].flat_map do |result|
      result["candidates"].presence&.map do |c|
        get_entity(uri: "#{ARTSDATA_BASE_URL}#{c["id"]}")
      end
    end.compact

    details
  end

  private

  def execute_query(query, variables = {})
    uri = URI.parse(sparql_endpoint)
    request = Net::HTTP::Post.new(uri)
    request.set_form_data({ query: query, format: "application/sparql-results+json" }.merge(variables))

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    return [] unless response.is_a?(Net::HTTPSuccess)

    body = JSON.parse(response.body)
    body.fetch("results", {}).fetch("bindings", [])
  rescue StandardError
    []
  end

  def execute_reconciliation_query(payload, lang: "en", route:)
    uri = URI.join(reconciliation_endpoint, route)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["accept-language"] = lang
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    return {} unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError
    {}
  end

  def format_search_results(rows)
    candidates = rows.flat_map { |row| row.fetch("candidates", []) }

    candidates.map do |candidate|
      # Build the full URI using the candidate's id
      uri = "http://kg.artsdata.ca/resource/#{candidate['id']}"

      # Merge/override the computed URI and strip out unwanted keys
      candidate.merge("uri" => uri).except("score", "match", "features")
    end
  end

end
