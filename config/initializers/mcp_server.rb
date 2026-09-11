Rails.application.config.to_prepare do

  ArtsdataMCPServer = MCP::Server.new(
    name: "artsdata_mcp_server",
    title: "Artsdata MCP Server",
    version: "0.0.1",
    instructions: "Access Artsdata's public APIs through a secure, lightweight, LLM-optimized layer designed for efficient querying by autonomous agents and users alike. SPARQL endpoint: https://query.artsdata.ca/query. " \
                  "To answer a question with SPARQL, call get_schema to learn the data model, write the query and run it " \
                  "with sparql_query, then use get_entity (details of a URI) or search_entities (URI from a name) as needed.",
    tools: [
      SearchEntities, # search for entities
      GetEntity, # get entity details by uri
      SearchEvents, # search for events by place, artist, organization, type and language
      GetSchema, # data model to get Artsdata schema (ontology + SHACL)
      SparqlQuery, # run a read-only SPARQL query written from the get_schema data model
    ],
    resources: [
      ArtsdataCoreMinusProvenanceDump
    ],
    prompts: []
  )

  MyTransport = MCP::Server::Transports::StreamableHTTPTransport.new(
    ArtsdataMCPServer,
    stateless: true,
    allowed_hosts: ["mcp.artsdata.ca"]
  )
end