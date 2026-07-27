# Artsdata MCP Server (Rails)

## Endpoints

- `GET /search-entities?query=<text>&lang=en|fr`
- `GET /entities?id=<uri_or_id>&lang=en|fr`

Both endpoints return JSON in MCP-style payloads with a `tool`, `result`, and `arguments`.

## Configuration

- `ARTSDATA_SPARQL_ENDPOINT` (optional): configurable SPARQL endpoint URL.
- SPARQL query templates are currently placeholders in
  `/home/runner/work/artsdata-mcp-server/artsdata-mcp-server/app/services/artsdata_client.rb`.

## Swagger

- Swagger UI: `GET /api-docs`
- OpenAPI file: `/api-docs/v1/swagger.yaml`

## Run tests

```bash
bundle exec rails test test/integration/entities_endpoints_test.rb
```
