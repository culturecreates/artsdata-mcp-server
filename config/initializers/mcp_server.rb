Rails.application.config.to_prepare do

  ArtsdataMCPServer = MCP::Server.new(
    name: "artsdata_mcp_server",
    title: "Artsdata MCP Server",
    version: "0.0.1",
    instructions: "Use the tools of this server, that acts as a thin, safe, LLM-friendly layer over Artsdata's existing
public APIs, so agents or users can search",
    tools: [SearchEntities, GetEntity],
  # prompts: [MyPrompt],
  )

  MyTransport = MCP::Server::Transports::StreamableHTTPTransport.new(
    ArtsdataMCPServer,
    allowed_hosts: ["mcp.artsdata.ca", "artsdata-mcp-server-8cb4262e2362.herokuapp.com"]
  )
end