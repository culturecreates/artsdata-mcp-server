require "net/http"
require "uri"
require "json"

class ArtsdataClient

  SCHEMA_BASE_URL = 'http://schema.org/'.freeze
  RDF_TYPE_PROPERTY_ID = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type'.freeze

  def initialize(
    sparql_endpoint: ENV.fetch("ARTSDATA_SPARQL_ENDPOINT", "https://api.artsdata.ca/query"),
    reconciliation_endpoint: ENV.fetch("ARTSDATA_RECONCILIATION_ENDPOINT", "https://recon.artsdata.ca/match")
  )
    @sparql_endpoint = sparql_endpoint
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

    body = execute_reconciliation_query(payload, lang: lang)
    format_search_results(body.fetch("results", []))
  end

  def get_statements(entity_id:, lang:)
    sparql = <<~SPARQL
      # Placeholder SPARQL query for entity statements.
      # Replace with final Artsdata statement query once schema is confirmed.
      SELECT ?entityLabel ?pid ?propertyLabel ?valueLabel ?valueQid ?literalValue WHERE {
        # TODO: fetch all triples related to #{entity_id}.
      }
      LIMIT 200
    SPARQL

    rows = execute_query(sparql, entity_id: entity_id, lang: lang)
    format_statement_results(rows, entity_id: entity_id)
  end

  private

  attr_reader :sparql_endpoint, :reconciliation_endpoint

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

  def execute_reconciliation_query(payload, lang: "en")
    uri = URI.parse(reconciliation_endpoint)
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

  def format_statement_results(rows, entity_id:)
    rows.map do |row|
      entity_label = value_for(row, "entityLabel")
      property_label = value_for(row, "propertyLabel")
      pid = value_for(row, "pid")
      value_label = value_for(row, "valueLabel")
      value_qid = value_for(row, "valueQid")
      literal_value = value_for(row, "literalValue")

      value = if value_label.empty?
                literal_value
              elsif value_qid.empty?
                value_label
              else
                "#{value_label} (#{value_qid})"
              end

      "#{entity_label} (#{entity_id}): #{property_label} (#{pid}): #{value}".strip
    end.compact.join("\n")
  end

  def value_for(row, key)
    row.fetch(key, {}).fetch("value", "").to_s
  end
end
