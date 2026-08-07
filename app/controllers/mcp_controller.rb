class McpController < ActionController::API
  def create

    transport = MCP::Server::Transports::StreamableHTTPTransport.new(
      ArtsdataMCPServer,
      stateless: true,
      allowed_hosts: ["mcp.artsdata.ca", "artsdata-mcp-server-8cb4262e2362.herokuapp.com"]
    )
    status, headers, body = transport.handle_request(request)

    render(json: body.first, status: status, headers: headers)
  end
end