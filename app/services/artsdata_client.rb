require "net/http"
require "uri"
require "json"

class ArtsdataClient

  SCHEMA_BASE_URL = 'http://schema.org/'.freeze
  ARTSDATA_BASE_URL = 'http://kg.artsdata.ca/resource/'.freeze

  RDF_TYPE_PROPERTY_ID = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'.freeze
  START_DATE_PROPERTY_ID = 'http://schema.org/startDate'.freeze
  LOCATION_NAME_PROPERTY_ID = 'schema:location/schema:name'.freeze
  PERFORMER_NAME_PROPERTY_ID = 'schema:performer/schema:name'.freeze
  ORGANIZER_NAME_PROPERTY_ID = 'schema:organizer/schema:name'.freeze

  MATCH_QUALIFIER_DATE_RANGE_URI = "http://kg.artsdata.ca/resource/reconciliation-qualifier-date-range"

  attr_reader :reconciliation_endpoint

  def initialize(
    reconciliation_endpoint: ENV.fetch("ARTSDATA_MATCH_RECONCILIATION_ENDPOINT", "https://staging-recon.artsdata.ca/")
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

  def format_get_entity_results(input_data)
    # Helpers to format recurring schema structures
    parse_loc_str = ->(vals) { vals.map { |v| { "value" => v["str"] || "" }.tap { |h| h["language"] = v["lang"] if v["lang"] } } }
    extract_val = ->(vals) { vals.filter_map { |v| v["str"] || v["id"] } }

    input_data.map do |entity|
      props = (entity["properties"] || []).group_by { |p| p["id"] }

      result = {
        "id" => entity["id"],
        "uri" => "#{ARTSDATA_BASE_URL}#{entity["id"]}",
        "types" => (props["type"] || props["@type"])&.flat_map do |p|
          p["values"].map { |v| { "uri" => v["id"] || "http://schema.org/#{v['str']}", "label" => v["str"] || v["id"]&.split('/')&.last } }
        end || [{ "uri" => "http://schema.org/Thing", "label" => "Thing" }],
        "name" => props["name"] ? parse_loc_str.call(props["name"].first["values"]) : []
      }

      # Optional schema attributes
      if (alts = props["alternateName"] || props["alternate_names"])
        result["alternate_names"] = parse_loc_str.call(alts.first["values"])
      end
      if (descs = props["description"] || props["disambiguatingDescription"])
        result["description"] = parse_loc_str.call(descs.first["values"])
      end
      if (url = (props["url"] || props["mainEntityOfPage"])&.first&.dig("values", 0, "str"))
        result["main_entity_of_page"] = url
      end
      if (same = props["sameAs"])
        result["same_as"] = extract_val.call(same.first["values"])
      end

      # Unmapped properties -> additional_properties
      known_keys = %w[name alternateName alternate_names description disambiguatingDescription url mainEntityOfPage sameAs type @type ]
      extra_props = props.except(*known_keys).map do |prop_id, items|
        {
          "predicate" => { "uri" => "http://schema.org/#{prop_id}", "label" => prop_id },
          "values" => items.flat_map { |item| extract_val.call(item["values"]) }
        }
      end
      result["additional_properties"] = extra_props unless extra_props.empty?

      result
    end
  end

  def get_entity_by_extend_service(ids:)

    payload = {
      "ids": ids,
      "properties": [
        { "id": "name" },
        { "id": "startDate" },
        { "id": "endDate" },
        { "id": "disambiguatingDescription" },
        { "id": "additionalType" },
        { "id": "url" },
        { "id": "sameAs" },
        { "id": "eventStatus" },
        { "id": "eventAttendanceMode" },
        { "id": "location" },
        { "id": "offers" },
        { "id": "performer" },
        { "id": "organizer" }
      ]
    }

    body = execute_reconciliation_query(payload, route: 'extend')
    format_get_entity_results(body.fetch("rows", []))
  end
  def search_events(startDateFrom:, startDateTo:, places:, artists:, organizations:, types:, language:, limit:)
    types_array = Array(types).compact
    type_uris = types_array.map { |t| t.start_with?("http") ? t : "#{SCHEMA_BASE_URL}#{t}" }

    # merge artists and organizations
    agents = artists.union(organizations)

    conditions = []

    if startDateFrom.present? || startDateTo.present?

      property_value = "#{startDateFrom}/#{startDateTo}" if startDateFrom.present? || startDateTo.present?

      conditions.push({
                        matchType: "property",
                        propertyId: START_DATE_PROPERTY_ID,
                        propertyValue: property_value,
                        required: true,
                        matchQualifier: MATCH_QUALIFIER_DATE_RANGE_URI
                      })
    end

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

    ids = data["results"].flat_map do |result|
      result["candidates"].presence&.map { |c| c["id"] }
    end.compact

    ids.empty? ? [] : get_entity_by_extend_service(ids:)
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
  rescue StandardError => e
    Rails.logger.error("ArtsdataClient#execute_query failed: #{e.class}: #{e.message}")
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
  rescue StandardError => e
    Rails.logger.error("ArtsdataClient#execute_reconciliation_query failed (route: #{route}): #{e.class}: #{e.message}")
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
