require "net/http"
require "uri"
require "json"

class ArtsdataClient
  ALLOWED_ENTITY_TYPES = %w[Organization Person Place].freeze

  def initialize(
    sparql_endpoint: ENV.fetch("ARTSDATA_SPARQL_ENDPOINT", "https://api.artsdata.ca/query"),
    reconciliation_endpoint: ENV.fetch("ARTSDATA_RECONCILIATION_ENDPOINT", "https://recon.artsdata.ca/match")
  )
    @sparql_endpoint = sparql_endpoint
    @reconciliation_endpoint = reconciliation_endpoint
  end

  def search_items(query:, lang:)
    entities = search_entities(query: query)
    format_search_results(entities)
  end

  def search_entities(query:, types: nil)
    payload = {
      queries: [
        {
          limit: 50,
          conditions: [
            {
              matchType: "name",
              propertyValue: query,
              required: true
            }
          ]
        }
      ]
    }

    supported_type = Array(types).find { |type| ALLOWED_ENTITY_TYPES.include?(type.to_s) }
    payload[:queries][0][:type] = "http://schema.org/#{supported_type}"  if supported_type

    body = execute_reconciliation_query(payload)
    format_entity_results(body.fetch("results", []))
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

  def execute_reconciliation_query(payload)
    uri = URI.parse(reconciliation_endpoint)
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload)

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    return {} unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError
    {}
  end

  def format_search_results(entities)
    entities.map do |entity|
      id = entity[:id].to_s
      name = entity[:name].to_s
      description = entity[:description].to_s
      next if id.empty? || name.empty?

      "#{id}: #{name} — #{description}".strip
    end.compact.join("\n")
  end

  def format_entity_results(rows)
    candidates = rows.flat_map { |row| row.fetch("candidates", []) }
    candidates.map do |candidate|
      id = candidate.fetch("id", "").to_s
      name = candidate.fetch("name", "").to_s
      description = candidate.fetch("description", "").to_s
      next if id.empty? || name.empty?

      uri = candidate.fetch("uri", "").to_s
      uri = "http://kg.artsdata.ca/resource/#{id}" if uri.empty?
      types = Array(candidate["types"]).map(&:to_s).reject(&:empty?)

      {
        id: id,
        uri: uri,
        name: name,
        types: types,
        description: description
      }
    end.compact
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
