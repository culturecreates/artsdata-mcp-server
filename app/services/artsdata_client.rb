require "net/http"
require "uri"
require "json"

class ArtsdataClient
  def initialize(endpoint: ENV.fetch("ARTSDATA_SPARQL_ENDPOINT", "https://api.artsdata.ca/query"))
    @endpoint = endpoint
  end

  def search_items(query:, lang:)
    sparql = <<~SPARQL
      # Placeholder SPARQL query using lucene index.
      # Replace with final Artsdata query once schema is confirmed.
      SELECT ?qid ?label ?description WHERE {
        # TODO: Lucene-powered text search against Artsdata.
      }
      LIMIT 10
    SPARQL

    rows = execute_query(sparql, query: query, lang: lang)
    format_search_results(rows)
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

  attr_reader :endpoint

  def execute_query(query, variables = {})
    uri = URI.parse(endpoint)
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

  def format_search_results(rows)
    rows.map do |row|
      qid = value_for(row, "qid")
      label = value_for(row, "label")
      description = value_for(row, "description")
      next if qid.empty?

      "#{qid}: #{label} — #{description}".strip
    end.compact.join("\n").then { |text| text.empty? ? text : "#{text}\n" }
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
