# Artsdata MCP Server

The Artsdata MCP Server exposes the [Artsdata](https://artsdata.ca) knowledge
graph to AI agents and LLM-based tools via the
[Model Context Protocol](https://modelcontextprotocol.io) (MCP). It lets an
agent search for entities (organizations, people, places), fetch full entity
details, and search for events — all backed by Artsdata's linked-data
knowledge graph.

## Endpoint

```text
https://mcp.artsdata.ca/mcp
```

The server implements the MCP **Streamable HTTP** transport. Requests are
JSON-RPC 2.0 messages sent via `POST`, and require an initialization
handshake before any tool can be called.

| | |
|---|---|
| Transport | Streamable HTTP (JSON-RPC 2.0 over `POST`) |
| Protocol version | `2024-11-05` |
| Auth | None (public) |

## Connecting a client

Most MCP-aware tools (Claude Code, Claude Desktop, etc.) can connect directly
by pointing an MCP client configuration at the endpoint above — no manual
handshake required. For a custom/manual client, the flow is:

### 1. Initialize a session

```bash
curl -i -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2024-11-05",
      "capabilities": {},
      "clientInfo": { "name": "my-client", "version": "1.0" }
    }
  }'
```

The response includes an `mcp-session-id` header. Save it — every
subsequent request must include it.

### 2. Send the `initialized` notification

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

### 3. List available tools

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: <SESSION_ID>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

### 4. Call a tool

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: <SESSION_ID>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "get_entity",
      "arguments": { "uri": "http://kg.artsdata.ca/resource/K11-70" }
    }
  }'
```

## Tools

### `search_entities`

Search for entities in the Artsdata knowledge graph by name and, optionally,
type.

**Input**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `query` | string | Yes | Non-empty search query. |
| `types` | array of `Place \| Person \| Organization` | No | Filter results by entity type. |
| `language` | `en` \| `fr` | No (default `en`) | Language for matching/labels. |
| `limit` | integer (1–50) | No (default 25) | Max number of results. |

**Output**

```json
{
  "results": [
    {
      "id": "string",
      "name": "string",
      "description": "string",
      "type": [ { "id": "uri", "name": "string" } ],
      "uri": "uri"
    }
  ]
}
```

**Example call**

```json
{
  "name": "search_entities",
  "arguments": {
    "query": "Cirque du Soleil",
    "types": ["Organization"],
    "limit": 5
  }
}
```

### `get_entity`

Retrieve full details for a single entity, given its Artsdata URI.

**Input**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `uri` | string (URI) | Yes | The Artsdata entity URI. |

**Output**

```json
{
  "id": "string",
  "uri": "uri",
  "types": [ { "uri": "uri", "label": "string" } ],
  "name": [ { "value": "string", "language": "en|fr" } ],
  "alternate_names": [ { "value": "string", "language": "en|fr" } ],
  "description": [ { "value": "string", "language": "en|fr" } ],
  "main_entity_of_page": "uri",
  "same_as": ["string"],
  "additional_properties": [
    {
      "predicate": { "uri": "uri", "label": "string" },
      "values": ["string"]
    }
  ]
}
```

**Example call**

```json
{
  "name": "get_entity",
  "arguments": {
    "uri": "https://kg.artsdata.ca/resource/K11-70"
  }
}
```

**Example response**

```json
{
  "id": "K11-70",
  "uri": "http://kg.artsdata.ca/resource/K11-70",
  "name": [
    { "value": "Klondike Institute of Art & Culture", "language": "en" },
    { "value": "Klondike Institute of Art & Culture" },
    { "value": "Klondike Institute of Art & Culture", "language": "fr" }
  ]
}
```

### `search_events`

Search for events in the Artsdata knowledge graph by place, artist,
organization, type, and language.

**Input**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `places` | array of strings | No | Place labels to filter by. |
| `artists` | array of strings | No | Artist labels to filter by. |
| `organizations` | array of strings | No | Organization labels to filter by. |
| `types` | array of strings | No | Event type labels to filter by. |
| `languages` | string | No (default `en`) | Language for matching/labels. |
| `limit` | integer (1–50) | No (default 25) | Max number of results. |

**Output**

```json
{
  "results": [
    {
      "id": "string",
      "name": "string",
      "description": "string",
      "type": [ { "id": "uri", "name": "string" } ],
      "uri": "uri"
    }
  ]
}
```

**Example call**

```json
{
  "name": "search_events",
  "arguments": {
    "places": ["Montreal"],
    "types": ["Theatre"],
    "limit": 10
  }
}
```

## REST-style equivalent

A legacy REST/JSON endpoint mirroring `search_entities` is also available on
the same host, for clients that don't speak MCP:

```text
GET /search-entities?query=<text>&lang=en|fr
```

Full OpenAPI documentation is available at:

- Swagger UI: `/api-docs/index.html`
- OpenAPI spec: `/api-docs/v1/swagger.yaml`

## See also

- [Model Context Protocol specification](https://modelcontextprotocol.io)
- [Artsdata](https://artsdata.ca)
