# Single source of truth for how to find and cite the sources of an Artsdata entity or of one of its
# property values, reused in the server instructions, the get_schema conventions and tool descriptions.
module ArtsdataSourcesRule
  INSTRUCTION = "Sources: the asserted value of a property is the answer; other sources may only claim a " \
                "different value (an RDF-star annotation that is not asserted). When asked who says or which " \
                "sources claim a property value (e.g. 'who says the name is...', 'what sources claim the date'), " \
                "use sparql_query with <<<entity_uri> <property> ?value>> prov:wasDerivedFrom ?source, tell asserted " \
                "from claimed with BIND(EXISTS { <entity_uri> <property> ?value } AS ?asserted), and name each " \
                "source by its dataset (?source void:inDataset ?dataset; if ?source has no dataset, it is the " \
                "dataset): schema:name, and schema:maintainer (its website; add https:// if it has no scheme). " \
                "Answer with the asserted value and its sources first, then any differing claimed values with " \
                "theirs. Declare PREFIX prov: <http://www.w3.org/ns/prov#> and PREFIX void: <http://rdfs.org/ns/void#>.".freeze

  TOOL_NOTE = "To find who claims a property value, see the sources guidance in the get_schema conventions.".freeze

  GET_ENTITY_NOTE = "The result's `sources` lists the datasets the entity was built from: name them when you " \
                    "answer about the entity, linking `url` when present, else by `name`.".freeze

  CONVENTION = "Sources of an Artsdata entity: its datasets are `<entity_uri> ^schema:sameAs/void:inDataset ?dataset`. " \
               "Sources of one property value are RDF-star annotations `<<<entity_uri> <property> ?value>> " \
               "prov:wasDerivedFrom ?source`: the triple is asserted only for the retained value, other sources may " \
               "claim a different value that is not asserted. Declare PREFIX prov: <http://www.w3.org/ns/prov#> and " \
               "PREFIX void: <http://rdfs.org/ns/void#>. Template (replace ENTITY_URI and the property): " \
               "SELECT ?value ?asserted ?source ?datasetName ?maintainer WHERE { " \
               "<<<ENTITY_URI> schema:name ?value>> prov:wasDerivedFrom ?source . " \
               "BIND(EXISTS { <ENTITY_URI> schema:name ?value } AS ?asserted) " \
               "OPTIONAL { ?source void:inDataset ?dataset } BIND(COALESCE(?dataset, ?source) AS ?ds) " \
               "OPTIONAL { ?ds schema:name ?datasetName } OPTIONAL { ?ds schema:maintainer ?maintainer } } LIMIT 100".freeze
end
