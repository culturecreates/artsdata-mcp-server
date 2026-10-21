# Single source of truth for the "cite the Artsdata ID" rule, reused in the server instructions
# and the tool descriptions so the wording cannot drift.
module ArtsdataIdRule
  INSTRUCTION = "When you mention an event, place, person or organization that has an Artsdata URI " \
                "(http://kg.artsdata.ca/resource/K12-345), cite its Artsdata ID (the ID matching K\\d+-\\d+ at " \
                "the end of the URI) on first mention, formatted as 'Name (K12-345)'. search_entities results " \
                "include a ready-made markdown-link `label` showing that format; use it. Take IDs only from tool " \
                "results, never invent them; entities with other URIs (e.g. Wikidata) have no Artsdata ID. " \
                "To find the ID of an entity you only know by name, use search_entities.".freeze

  TOOL_NOTE = "Entity URIs end in the Artsdata ID (K\\d+-\\d+, e.g. K12-345); cite it with the entity name.".freeze

  SEARCH_NOTE = "Each result has a markdown-link `label` like '[Name (K12-345)](https://kg.artsdata.ca/resource/K12-345)': " \
                "use it verbatim when mentioning the entity.".freeze
end
