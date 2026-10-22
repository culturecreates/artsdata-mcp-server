# Single source of truth for how to find and cite the sources of an Artsdata entity or of one of its
# property values, reused in the server instructions, the get_schema conventions and tool descriptions.
module ArtsdataSourcesRule
  INSTRUCTION = "Sources: a property's asserted value is the answer; other sources may only claim a different " \
                "value (see get_schema about.description). When asked who says or which sources claim a value " \
                "(e.g. 'who says the name is...'), follow the sources convention of get_schema with sparql_query. " \
                "Answer with the asserted value and its sources first, then differing claimed values with theirs; " \
                "name each source by its dataset's schema:name and link its schema:maintainer (add https:// if it " \
                "has no scheme).".freeze

  TOOL_NOTE = "To find who claims a property value, see the sources guidance in the get_schema conventions.".freeze

  GET_ENTITY_NOTE = "The result's `sources` lists the datasets the entity was built from: name them when you " \
                    "answer about the entity, linking `url` when present, else by `name`.".freeze

  CONVENTION = "Sources of an entity: `<entity_uri> ^schema:sameAs/void:inDataset ?dataset`. Sources of one property " \
               "value, asserted or only claimed: replace ENTITY_URI and the property in SELECT ?value ?asserted " \
               "?source ?datasetName ?maintainer WHERE { <<<ENTITY_URI> schema:name ?value>> prov:wasDerivedFrom|prov:hadPrimarySource " \
               "?source . BIND(EXISTS { <ENTITY_URI> schema:name ?value } AS ?asserted) OPTIONAL { ?source " \
               "void:inDataset ?dataset } BIND(COALESCE(?dataset, ?source) AS ?ds) OPTIONAL { ?ds schema:name " \
               "?datasetName } OPTIONAL { ?ds schema:maintainer ?maintainer } } LIMIT 100".freeze
end
