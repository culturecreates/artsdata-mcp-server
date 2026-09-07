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

  ORGANIZER_OR_PERFORMER_PROPERTY_ID = 'schema:organizer|schema:performer'.freeze

  MATCH_QUALIFIER_DATE_RANGE_URI = "http://kg.artsdata.ca/resource/reconciliation-qualifier-date-range"

  attr_reader :reconciliation_endpoint

  def initialize(
    reconciliation_endpoint: ENV.fetch("ARTSDATA_RECONCILIATION_ENDPOINT")
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
    parse_loc_str = ->(vals) { vals.map { |v| { "value" => v["str"] || "" }.tap { |h| h["language"] = v["lang"] if v["lang"] } } }
    extract_val   = ->(vals) { vals.filter_map { |v| v["str"] || v["id"] } }
    to_uris       = ->(ids) { ids.map { |id| "#{ARTSDATA_BASE_URL}#{id}" } }

    loc_str_fields = {
      "alternate_names"           => %w[alternateName],
      "description"               => %w[description disambiguatingDescription],
    }
    single_str_fields = {
      "main_entity_of_page" => %w[url mainEntityOfPage],
      "start_date"           => %w[startDate],
      "end_date"             => %w[endDate],
    }
    single_id_fields = {
      "event_status"         => %w[eventStatus],
      "event_attendance_mode" => %w[eventAttendanceMode],
    }
    value_list_fields = {
      "same_as"         => %w[sameAs],
      "additional_type" => %w[additionalType],
    }
    entity_ref_fields = %w[performer organizer location]

    known_keys = %w[name type] + loc_str_fields.values.flatten +
                 single_str_fields.values.flatten + single_id_fields.values.flatten +
                 value_list_fields.values.flatten + entity_ref_fields

    input_data.map do |entity|
      props = (entity["properties"] || []).group_by { |p| p["id"] }
      values_for = ->(ids) { ids.map { |id| props[id] }.compact.first&.first&.fetch("values", nil) }

      # Parse and construct the required `types` array
      type_vals = values_for.call(["type"])
      parsed_types = if type_vals
                       type_vals.filter_map do |v|
                         uri = v["id"] || v["str"]
                         next unless uri
                         label = uri.split("/").last || uri
                         { "uri" => uri, "label" => label }
                       end
                     else
                       []
                     end

      # Fallback to default Event type if list is empty
      if parsed_types.empty?
        parsed_types = [{ "uri" => "http://schema.org/Event", "label" => "Event" }]
      end

      result = {
        "id"    => entity["id"],
        "uri"   => "#{ARTSDATA_BASE_URL}#{entity["id"]}",
        "types" => parsed_types,
        "name"  => props["name"] ? parse_loc_str.call(props["name"].first["values"]) : []
      }

      loc_str_fields.each do |key, ids|
        vals = values_for.call(ids)
        result[key] = parse_loc_str.call(vals) if vals
      end

      single_str_fields.each do |key, ids|
        val = values_for.call(ids)&.dig(0, "str")
        result[key] = val if val
      end

      single_id_fields.each do |key, ids|
        val = values_for.call(ids)&.dig(0, "id")
        result[key] = val if val
      end

      value_list_fields.each do |key, ids|
        vals = values_for.call(ids)
        result[key] = extract_val.call(vals) if vals
      end

      entity_ref_fields.each do |key|
        vals = values_for.call([key])
        result[key] = to_uris.call(extract_val.call(vals)) if vals
      end

      extra_props = props.except(*known_keys).map do |prop_id, items|
        {
          "predicate" => { "uri" => "http://schema.org/#{prop_id}", "label" => prop_id },
          "values"    => items.flat_map { |item| extract_val.call(item["values"]) }
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
        { "id": "http://www.w3.org/1999/02/22-rdf-syntax-ns#type" },
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

    agents = Array(artists).compact.union(Array(organizations).compact)
    agent_uris, agent_labels = agents.partition { |agent| agent.to_s.start_with?("http") }

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

    if agent_labels.size > 0
      conditions.push(agent_condition(ORGANIZER_NAME_PROPERTY_ID, agent_labels))
      conditions.push(agent_condition(PERFORMER_NAME_PROPERTY_ID, agent_labels))
    end

    if agent_uris.size > 0
      conditions.push(agent_condition(ORGANIZER_OR_PERFORMER_PROPERTY_ID, agent_uris))
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

  # An agent (artist or organizer) condition. These are `required: false` so that a match on
  # any one of them - organizer or performer, by label or by URI - keeps the event.
  def agent_condition(property_id, property_value)
    {
      matchType: "property",
      propertyId: property_id,
      propertyValue: property_value,
      required: true,
      matchQuantifier: 'any'
    }
  end

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
