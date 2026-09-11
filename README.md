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

## MCP resources

- `artsdata://dumps/core-minus-provenance/latest` (`artsdata_dump`): manifest for the
  latest Artsdata core-minus-provenance dump — the core graph with provenance and
  RDF-star annotations removed, published monthly as a gzipped Turtle file.

  `resources/read` asks the Artsdata Databus for the newest version of the artifact
  (`GET /databus/artifact/latest?artifact=<ARTIFACT_URI>`) and returns a small JSON
  document with the download URL, version, format and compression — never the dump
  contents. Going through the Databus means MCP clients need to know nothing about
  where the file is actually stored. Clients download the file from `downloadUrl` and
  compare `version` across reads to detect when a new dump lands.


## Directory structure

```text
.github/
  workflows/
    deploy-to-heroku.yml  # Workflow deploying to Heroku
    run-unit-tests.yml    # Reusable workflow running Minitest
    unit-test-on-pull-request.yml # Workflow running unit tests on pull requests
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

- `ARTSDATA_RECONCILIATION_ENDPOINT`: configurable reconciliation
  endpoint URL for `/search-entities`.
- `ARTSDATA_SCHEMA_URL` (optional): Turtle file compiled by the `get_schema` tool
  (default `https://docs.artsdata.ca/artsdata-schema.ttl`).
- `ARTSDATA_SCHEMA_CACHE_TTL_SECONDS` (optional): how long the compiled schema is cached
  in process (default `86400`).
- `ARTSDATA_CORS_ORIGINS` (optional): comma-separated CORS origins (default `*`).
- `ARTSDATA_API_ENDPOINT` (optional): base URL of the Artsdata API, used to query the
  Databus for the latest data dump (default `https://api.artsdata.ca`).
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

## Deployment & CI/CD Details:

This project uses GitHub Actions for continuous integration and automated deployment to Heroku.
Every push to the `main` branch triggers a workflow that builds and deploys the application to Heroku.
The workflow is defined in `.github/workflows/deploy-to-heroku.yml`.

Every pull request triggers a workflow that unit tests. The workflow is defined in `.github/workflows/run-unit-tests.yml`.

## Server Access & API Documentation
The Artsdata MCP Server is actively deployed and hosted in a live production environment.

Live Production Endpoints
API Documentation (Swagger UI): https://artsdata-mcp-server-8cb4262e2362.herokuapp.com/api-docs/index.html