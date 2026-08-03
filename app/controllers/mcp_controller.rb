class McpController < ApplicationController
  TOOLS = [
    {
      name: "search_entities",
      description: "Search Artsdata for entities (events, organizations, people, places) by free-text name. Use this before get_entity when you don't already have an Artsdata ID — returns ranked candidates with confidence scores. Chain the returned 'id' into get_entity to fetch the full record.",
      inputSchema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Free text to search for, e.g. an organization or person name." },
          types: {
            type: "array",
            items: { type: "string", enum: %w[Event Organization Person Place] },
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
          id: { type: "string", description: "An Artsdata ID (e.g. 'K10-122') or full resource URI (e.g. 'http://kg.artsdata.ca/resource/K10-122')." },
          format: { type: "string", enum: %w[simplified json-ld], default: "simplified" }
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
          name: { type: "string" },
          sameAs: { type: "array", items: { type: "string" } },
          url: { type: "string" }
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
    else
      render json: {
        jsonrpc: "2.0",
        id: params[:id],
        error: { code: -32_601, message: "Method not found" }
      }, status: :not_found
    end
  end
end
