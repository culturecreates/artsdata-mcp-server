class McpController < ActionController::API
  def create

    transport = MCP::Server::Transports::StreamableHTTPTransport.new(ArtsdataMCPServer, stateless: true)
    status, headers, body = transport.handle_request(request)

    render(json: body.first, status: status, headers: headers)
  end
end