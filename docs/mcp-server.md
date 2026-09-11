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

The server implements the MCP **Streamable HTTP** transport in **stateless**
mode. Requests are JSON-RPC 2.0 messages sent via `POST`. The protocol still
requires the client to send `initialize` before any other request, but the
server does not persist a session afterward — no `Mcp-Session-Id` is issued,
and none is expected on later requests. Each request (including `initialize`
itself) is handled independently, since none of the tools depend on
per-connection state.

| | |
|---|---|
| Transport | Streamable HTTP (JSON-RPC 2.0 over `POST`) |
| Protocol version | Negotiated per client via the `initialize` handshake. Any of `2024-11-05`, `2025-03-26`, `2025-06-18`, `2025-11-25` is accepted and echoed back as-is; an unrecognized version (including the modern `2026-07-28`, which is only reachable via per-request `_meta`, not the handshake) falls back to the latest handshake version, `2025-11-25`. |
| Auth | None (public) |

## Connecting a client

Most MCP-aware tools (Claude Code, Claude Desktop, etc.) can connect directly
by pointing an MCP client configuration at the endpoint above — no manual
handshake required. For a custom/manual client, the flow is:

### 1. Send the `initialize` handshake

```bash
curl -i -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-06-18",
      "capabilities": {},
      "clientInfo": { "name": "my-client", "version": "1.0" }
    }
  }'
```

The response does **not** include an `Mcp-Session-Id` header — the server is
stateless, so there is no session to track and none to send back on later
requests.

### 2. Send the `initialized` notification

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

### 3. List available tools

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

### 4. Call a tool

```bash
curl -X POST https://mcp.artsdata.ca/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
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
| `startDateFrom` | string (ISO 8601) | No | Lower bound filter; includes events starting on or after this date/time. |
| `startDateTo` | string (ISO 8601) | No | Upper bound filter; includes events starting on or before this date/time. |
| `places` | array of strings | No | Place labels to filter by. |
| `artists` | array of strings | No | Artist labels to filter by. |
| `organizations` | array of strings | No | Organization labels to filter by. |
| `types` | array of strings | No | Event type labels to filter by. |
| `languages` | string | No (default `en`) | Language for matching/labels. |
| `limit` | integer (1–50) | No (default 25) | Max number of results. |

**Output**

Each matching event is returned in the same detailed shape as `get_entity`
(the tool internally resolves matches to full entity records):

```json
{
  "results": [
    {
      "id": "string",
      "uri": "uri",
      "types": [ { "uri": "uri", "label": "string" } ],
      "name": [ { "value": "string", "language": "en|fr" } ],
      "description": [ { "value": "string", "language": "en|fr" } ],
      "main_entity_of_page": "uri",
      "additional_properties": [
        {
          "predicate": { "uri": "uri", "label": "string" },
          "values": ["string"]
        }
      ]
    }
  ]
}
```

**Example call**

```json
{
  "name": "search_events",
  "arguments": {
    "organizations": ["Cirque du Soleil"],
    "limit": 10
  }
}
```

### `get_schema`

Returns the Artsdata data model so an agent can write SPARQL against
`https://query.artsdata.ca/query` without prior knowledge of Artsdata's
ontology. It is compiled from
[`artsdata-schema.ttl`](https://docs.artsdata.ca/artsdata-schema.ttl) (the
Artsdata Ontology plus the CORE graph SHACL shapes) into a class-centric
digest. All shapes that apply to a class (core, ontology-extension,
equivalent-class, superclass and value shapes) are merged into one property
list. IRIs are written as CURIEs over the returned `prefixes`, and paths as
SPARQL property paths. Validation-only details (`sh:message`, `sh:sparql`)
are dropped.

The file is fetched at runtime and cached in process (24h by default). If a
refresh can't fetch or parse it, the last good digest is kept; if nothing has
been loaded yet, the tool call fails.

**Input:** none (`{}`).

**Output (abridged)**

```json
{
  "about": { "title": "Artsdata Ontology", "version": "1.4.0", "source": "https://docs.artsdata.ca/artsdata-schema.ttl", "sparql_endpoint": "https://query.artsdata.ca/query" },
  "conventions": ["Use the `prefixes` verbatim in SPARQL. schema: is http://schema.org/ (http, not https).", "..."],
  "prefixes": { "ado": "http://kg.artsdata.ca/ontology/", "adr": "http://kg.artsdata.ca/resource/", "schema": "http://schema.org/", "...": "..." },
  "classes": [
    {
      "class": "schema:Event",
      "label": "Event",
      "equivalent_classes": ["ado:Event"],
      "shapes": ["ads:AdoEventShape", "ads:CoreEventShape"],
      "properties": [
        { "path": "schema:location", "label": "location", "required": true, "node_kind": "IRI", "classes": ["schema:Place"], "pattern": "^http://kg\\.artsdata\\.ca/resource/" },
        { "path": "schema:name", "label": "name", "required": true, "datatypes": ["rdf:langString", "xsd:string"], "unique_lang": true },
        { "path": "schema:eventStatus", "label": "event status", "required": false, "max_count": 1, "in": ["schema:EventPostponed", "schema:EventScheduled", "..."] },
        {
          "path": "ado:hasEventTypeConcept", "label": "has event type", "required": false, "node_kind": "IRI", "classes": ["skos:Concept"],
          "sub_property_of": ["schema:additionalType"],
          "value_shape": { "label": "Artsdata Event Type Concept", "properties": [ { "path": "skos:inScheme", "required": false, "has_value": ["adr:ArtsdataEventTypes"] } ] }
        }
      ]
    }
  ],
  "vocabularies": [
    { "property": "ado:hasEventTypeConcept", "scheme": "adr:ArtsdataEventTypes", "label": "Artsdata Event Type Concept", "classes": ["skos:Concept"] }
  ]
}
```

### `sparql_query`

Runs a read-only SPARQL 1.1 query against `https://query.artsdata.ca/query`
and returns the endpoint's
[SPARQL 1.1 Query Results JSON](https://www.w3.org/TR/sparql11-results-json/)
as is. It is a thin pass-through: the agent writes the query from what
`get_schema` returns, and the server neither builds nor rewrites it.

The intended flow is `get_schema` (learn the model) → `sparql_query` (run the
query) → `get_entity` / `search_entities` for details about the entities in
the results.

Guard rails:

- Only `SELECT` and `ASK` are accepted (the forms whose result is SPARQL
  Results JSON). Updates, `CONSTRUCT` and `DESCRIBE` are refused before
  anything is sent to the endpoint.
- At most 1000 rows are returned. When the endpoint returns more, the rest is
  cut and `truncated: true` is added; agents should use `LIMIT` / `OFFSET`.
- When the endpoint rejects a query (HTTP 400, e.g. a syntax error), the tool
  returns `isError: true` with the endpoint's message so the agent can fix the
  query and retry. Timeouts and endpoint failures are returned the same way.

**Input**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `query` | string | Yes | A complete SPARQL `SELECT` or `ASK` query, with a `PREFIX` for every prefix it uses. |

**Example call**

```json
{
  "name": "sparql_query",
  "arguments": {
    "query": "PREFIX schema: <http://schema.org/>\nSELECT ?event ?name WHERE { ?event a schema:Event ; schema:name ?name . FILTER(LANG(?name) = \"en\") } LIMIT 2"
  }
}
```

**Example response**

```json
{
  "head": { "vars": ["event", "name"] },
  "results": {
    "bindings": [
      {
        "event": { "type": "uri", "value": "http://kg.artsdata.ca/resource/K11-1" },
        "name": { "type": "literal", "value": "Concert", "xml:lang": "en" }
      }
    ]
  }
}
```

An `ASK` query returns `{ "head": {}, "boolean": true }`.

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
