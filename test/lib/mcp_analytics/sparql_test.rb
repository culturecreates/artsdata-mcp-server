require "test_helper"

class McpAnalytics::SparqlTest < ActiveSupport::TestCase
  S = McpAnalytics::Sparql

  BASE = <<~SPARQL
    PREFIX schema: <http://schema.org/>
    SELECT ?event ?name WHERE {
      ?event a schema:Event ; schema:name ?name .
      FILTER(CONTAINS(LCASE(STR(?name)), "festival"))
    } LIMIT 20
  SPARQL

  def assert_same_shape(query, message)
    assert_equal S.fingerprint(BASE), S.fingerprint(query), message
  end

  def refute_same_shape(query, message)
    refute_equal S.fingerprint(BASE), S.fingerprint(query), message
  end

  # --- what must group ------------------------------------------------------

  test "renamed variables and different literals are the same shape" do
    assert_same_shape <<~SPARQL, "agents name variables differently every time"
      PREFIX schema: <http://schema.org/>
      SELECT ?e ?n WHERE {
        ?e a schema:Event ; schema:name ?n .
        FILTER(CONTAINS(LCASE(STR(?n)), "opera"))
      } LIMIT 50
    SPARQL
  end

  test "a different prefix label is the same shape" do
    assert_same_shape <<~SPARQL, "prefix labels are arbitrary"
      PREFIX s: <http://schema.org/>
      SELECT ?event ?name WHERE { ?event a s:Event ; s:name ?name .
        FILTER(CONTAINS(LCASE(STR(?name)), "festival")) } LIMIT 20
    SPARQL
  end

  test "formatting, comments and keyword case do not change the shape" do
    assert_same_shape <<~SPARQL, "only the shape should matter"
      # find festivals
      prefix schema: <http://schema.org/>
      SELECT ?event ?name WHERE { ?event a schema:Event ; schema:name ?name .
        FILTER(CONTAINS(LCASE(STR(?name)), "jazz")) } LIMIT 20
    SPARQL
  end

  test "IRIs are kept whole, so different entities are different shapes" do
    concert = <<~SPARQL
      PREFIX ado: <http://kg.artsdata.ca/ontology/>
      SELECT ?e WHERE { ?e ado:hasEventTypeConcept <http://kg.artsdata.ca/resource/Concert> } LIMIT 5
    SPARQL
    exhibition = concert.sub("Concert", "Exhibition")

    refute_equal S.fingerprint(concert), S.fingerprint(exhibition),
                 "which entity or concept was asked about is part of the shape"
    assert_includes S.normalize(concert), "<http://kg.artsdata.ca/resource/Concert>"
  end

  # --- what must stay apart -------------------------------------------------

  test "a different class is a different shape" do
    refute_same_shape <<~SPARQL, "Person is not Event"
      PREFIX schema: <http://schema.org/>
      SELECT ?p ?n WHERE { ?p a schema:Person ; schema:name ?n .
        FILTER(CONTAINS(LCASE(STR(?n)), "festival")) } LIMIT 20
    SPARQL
  end

  test "dropping a FILTER is a different shape" do
    refute_same_shape <<~SPARQL, "the filter is part of the question"
      PREFIX schema: <http://schema.org/>
      SELECT ?e ?n WHERE { ?e a schema:Event ; schema:name ?n . } LIMIT 20
    SPARQL
  end

  test "variables are renumbered positionally, so join structure survives" do
    three_vars = "SELECT ?a WHERE { ?a ?b ?c }"
    one_var    = "SELECT ?a WHERE { ?a ?a ?a }"

    refute_equal S.fingerprint(three_vars), S.fingerprint(one_var),
                 "renaming every variable to one token would merge these"
  end

  test "a join cycle differs from no cycle" do
    cycle    = "SELECT ?x ?y WHERE { ?x <urn:p> ?y . ?y <urn:q> ?x }"
    no_cycle = "SELECT ?x ?y WHERE { ?x <urn:p> ?y . ?x <urn:q> ?y }"

    refute_equal S.fingerprint(cycle), S.fingerprint(no_cycle)
  end

  # --- IRIs containing # (rdf, rdfs, owl, xsd, skos) ------------------------
  #
  # A plain /#[^\n]*/ comment strip destroys every one of these namespaces,
  # and every earlier test used schema:, which has no #, so it went unnoticed.

  test "a namespace ending in # survives intact" do
    query = <<~SPARQL
      PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
      SELECT ?c ?l WHERE { ?c skos:prefLabel ?l } LIMIT 10
    SPARQL

    assert_includes S.normalize(query), "<http://www.w3.org/2004/02/skos/core#prefLabel>"
  end

  test "numbers inside an IRI are not neutralised" do
    query = <<~SPARQL
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX schema: <http://schema.org/>
      SELECT ?e WHERE { ?e rdf:type schema:Event } LIMIT 20
    SPARQL

    assert_includes S.normalize(query), "1999/02/22", "a year in a namespace is not a literal"
  end

  test "keywords inside an IRI path are not upcased" do
    query = "SELECT ?e WHERE { ?e <http://example.org/as/in/thing> ?v } LIMIT 5"

    assert_includes S.normalize(query), "<http://example.org/as/in/thing>"
  end

  test "a real comment is still stripped" do
    commented = <<~SPARQL
      # find events
      PREFIX schema: <http://schema.org/>
      SELECT ?event ?name WHERE { ?event a schema:Event ; schema:name ?name .
        FILTER(CONTAINS(LCASE(STR(?name)), "festival")) } # trailing note
      LIMIT 20
    SPARQL

    assert_same_shape commented, "comments carry no meaning"
  end

  test "a hash inside a literal does not truncate the query" do
    query = 'PREFIX schema: <http://schema.org/> SELECT ?e WHERE { ?e schema:name "rock # roll" } LIMIT 20'

    assert_includes S.normalize(query), "LIMIT 0", "the line after the # must survive"
  end

  # --- shape and robustness -------------------------------------------------

  test "the canonical shape reads as a template" do
    assert_equal "SELECT ?v1 ?v2 WHERE { ?v1 a <http://schema.org/Event> ; " \
                 "<http://schema.org/name> ?v2 . " \
                 "FILTER(CONTAINS(LCASE(STR(?v2)), \"?\")) } LIMIT 0",
                 S.normalize(BASE)
  end

  test "the fingerprint is stable and 12 characters" do
    assert_equal S.fingerprint(BASE), S.fingerprint(BASE)
    assert_equal McpAnalytics::Sparql::FINGERPRINT_LENGTH, S.fingerprint(BASE).length
    assert_match(/\A[0-9a-f]+\z/, S.fingerprint(BASE))
  end

  test "no query yields no fingerprint" do
    assert_nil S.fingerprint(nil)
    assert_nil S.fingerprint("")
    assert_nil S.fingerprint("   ")
  end

  test "never raises on malformed input" do
    ["{{{", '"unterminated', "SELECT" * 3000, "\xff\xfe", "not a query"].each do |query|
      assert_nothing_raised do
        S.fingerprint(query)
        S.normalize(query)
      end
    end
  end
end
