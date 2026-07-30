# Artsdata MCP Server (Rails)

## Prerequisites

- Ruby `4.0.6`
- Rails `8.1`
- Bundler

## Setup

```bash
bundle install
```

## Endpoints

- `GET /search-entities?query=<text>&lang=en|fr`
- `GET /entities?id=<uri_or_id>&lang=en|fr`

Both endpoints return JSON in MCP-style payloads with a `tool`, `result`, and `arguments`.

## Directory structure

```text
app/
  controllers/entities_controller.rb
  services/artsdata_client.rb
config/
  routes.rb
swagger/v1/
  swagger.yaml
test/
  controllers/entities_controller_test.rb
```

## Configuration

- `ARTSDATA_SPARQL_ENDPOINT` (optional): configurable SPARQL endpoint URL.
- `ARTSDATA_RECONCILIATION_ENDPOINT` (optional): configurable reconciliation
  endpoint URL for `/search-entities`.
- `ARTSDATA_CORS_ORIGINS` (optional): comma-separated CORS origins (default `*`).
- SPARQL query template for `/entities` is currently a placeholder in
  `app/services/artsdata_client.rb`.
- Docker instance profiles are provided in:
  - `env/production.env`
  - `env/staging.env`
- `ARTSDATA_INSTANCE_TYPE` (optional): `PRODUCTION` (default) or `STAGING`.
  The Docker entrypoint loads the matching file from `env/`.

## Run the application

```bash
bundle exec rails server
```

The API will be available at `http://localhost:3000`.

## Docker

Build the image:

```bash
docker build -t artsdata-mcp-server .
```

Run the server:

```bash
docker run --rm -p 3000:3000 artsdata-mcp-server
```

Run with staging profile:

```bash
docker run --rm -p 3000:3000 -e ARTSDATA_INSTANCE_TYPE=STAGING artsdata-mcp-server
```

Run tests in Docker:

```bash
docker run --rm artsdata-mcp-server bundle exec rails test test/controllers/entities_controller_test.rb
```

## Swagger

- Swagger UI: `GET /api-docs`
- OpenAPI file: `/api-docs/v1/swagger.yaml`

## Run tests

```bash
bundle exec rails test test/controllers/entities_controller_test.rb
```

Run all tests:

```bash
bundle exec rails test
```
