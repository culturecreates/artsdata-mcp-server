class McpController < ApplicationController
  TOOLS = [
    {
      name: "search_entities",
      description: "Search Artsdata for entities (organizations, people, places) by name. Use this before get_entity when you don't already have an Artsdata ID — returns entities. Chain the returned 'id' into get_entity to fetch the full record.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Text search for, e.g. an organization or person name." },
          types: {
            type: "array",
            items: { type: "string", enum: %w[Organization Person Place] },
            description: "Optional. Restrict results to one or more entity types. Omit to search all types."
          },
          language: { type: "string", description: "Optional ISO language code (e.g. 'en', 'fr') if the query text's language is known. Leave unset otherwise." },
          limit: { type: "integer", minimum: 1, maximum: 50, default: 25 }
        },
        required: ["query"]
      },
      outputSchema: {
        type: "object",
        properties: {
          results: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: { type: "string" },
                uri: { type: "string" },
                name: { type: "string" },
                types: { type: "array", items: { type: "string" } },
                description: { type: "string" }
              },
              required: %w[id uri name]
            }
          }
        },
        required: ["results"]
      }
    },
    {
      name: "get_entity",
      description: "Fetch the full Artsdata record for a known entity, given its ID or resource URI. Use search_entities first if you don't already have an ID.",
      inputSchema: {
        type: "object",
        properties: {
          id: { type: "string", description: "An Artsdata ID (e.g. 'K10-122') or full resource URI (e.g. 'http://kg.artsdata.ca/resource/K10-122')." }
        },
        required: ["id"],
        additionalProperties: false
      },
      outputSchema: {
        type: "object",
        properties: {
          id: { type: "string" },
          uri: { type: "string" },
          type: { type: "string" },
          additionalType: { type: "string" },
          name: { type: "string" },
          alternateName: { type: "string" },
          description: { type: "string" },
          sameAs: { type: "array", items: { type: "string" } },
          url: { type: "string" },
          image: { type: "string" },
          disambiguatingDescription: { type: "string" },
          mainEntityOfPage: { type: "string" }
        },
        required: %w[id uri type name]
      }
    }
  ].freeze

  def handle
    case params[:method]
    when "tools/list", "tool/list"
      render json: {
        jsonrpc: "2.0",
        id: params[:id],
        result: { tools: TOOLS }
      }
    when "tools/call", "tool/call"
      return render_tool_not_found unless params.dig(:params, :name) == "search_entities"

      arguments = params.dig(:params, :arguments) || {}
      results = ArtsdataClient.new.search_entities(
        query: arguments[:query].to_s,
        types: arguments[:types]
      )
      structured_content = { results: results }

      render json: {
        jsonrpc: "2.0",
        id: params[:id],
        result: {
          content: [
            {
              type: "text",
              text: JSON.generate(structured_content)
            }
          ],
          structuredContent: structured_content,
          isError: false
        }
      }
    else
      render_method_not_found
    end
  end

  private

  def render_method_not_found
    render json: {
      jsonrpc: "2.0",
      id: params[:id],
      error: { code: -32_601, message: "Method not found" }
    }, status: :not_found
  end

  def render_tool_not_found
    render json: {
      jsonrpc: "2.0",
      id: params[:id],
      error: { code: -32_601, message: "Tool not found" }
    }, status: :not_found
  end
end
