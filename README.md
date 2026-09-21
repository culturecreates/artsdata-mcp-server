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

- `POST /mcp`: MCP Streamable HTTP endpoint (tools and resources are documented in
  [docs/mcp-server.md](docs/mcp-server.md))
- `GET /up`: health check
- `GET /llms.txt`: machine-readable guide for agents

Calls to `/mcp` are reported to Google Analytics 4.

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
  resource/     # MCP resources
  schema/       # JSON schemas of the tools' input and output
  services/     # Clients for the reconciliation service, SPARQL endpoint and Databus
  tool/         # MCP tools
config/
  initializers/mcp_server.rb  # MCP server: registered tools, resources and transport
  initializers/mcp_analytics.rb # Google Analytics 4 reporting configuration
  routes.rb
lib/
  mcp_analytics/  # Rack middleware reporting MCP usage to Google Analytics 4
test/
```

## Configuration

- `ARTSDATA_RECONCILIATION_ENDPOINT`: reconciliation service URL used by the
  `search_entities`, `get_entity` and `search_events` tools.
- `ARTSDATA_SCHEMA_URL` (optional): Turtle file compiled by the `get_schema` tool
  (default `https://docs.artsdata.ca/artsdata-schema.ttl`).
- `ARTSDATA_SCHEMA_CACHE_TTL_SECONDS` (optional): how long the compiled schema is cached
  in process (default `86400`).
- `ARTSDATA_CORS_ORIGINS` (optional): comma-separated CORS origins (default `*`).
- `ARTSDATA_API_ENDPOINT` (optional): base URL of the Artsdata API, used to query the
  Databus for the latest data dump (default `https://api.artsdata.ca`).
- `ARTSDATA_SPARQL_ENDPOINT` (optional): SPARQL endpoint queried by the `sparql_query`
  tool (default `https://query.artsdata.ca/query`).
- `ARTSDATA_SPARQL_TIMEOUT_SECONDS` (optional): read timeout for a `sparql_query` call
  (default `25`).
- `ARTSDATA_SPARQL_MAX_ROWS` (optional): maximum rows `sparql_query` returns; extra rows
  are cut and the result is flagged `truncated` (default `1000`).
- Docker instance profiles are provided in:
  - `env/production.env`
  - `env/staging.env`
- `ARTSDATA_INSTANCE_TYPE` (optional): `PRODUCTION` (default) or `STAGING`.
  The Docker entrypoint loads the matching file from `env/`.

### Usage analytics

Calls to `/mcp` are reported to Google Analytics 4, including the tool used,
how long the call took, and the caller's `User-Agent`. Reporting stays off until
both variables below are set, so development and CI need no configuration.

- `GA4_MEASUREMENT_ID`: the GA4 property's `G-XXXXXXXXXX` id. Not a secret;
  defaulted for production in `config/environments/production.rb`.
- `GA4_API_SECRET`: Measurement Protocol secret. **Secret — set it as a Heroku.
  config var, never in `env/*.env`, which is committed.**
- `GA4_DEBUG` (optional): tag events so they appear in GA4's DebugView within
  seconds, and log whether GA4 considers each payload valid. Events are still
  recorded. Useful because the normal endpoint answers `204` whether or not the
  payload is valid.

Reporting is on when both credentials are present and off otherwise.

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
docker run --rm artsdata-mcp-server bundle exec rails test
```

## Run tests

Run a single test file:

```bash
bundle exec rails test test/tool/search_events_test.rb
```

Run all tests:

```bash
bundle exec rails test
```

## llms.txt maintenance

The public/llms.txt file is generated from MCP server metadata (tools, resources,
descriptions, and schemas).

CI behavior:
- Pull request CI runs bundle exec rake docs:check_llms.
- If public/llms.txt is stale, the workflow fails.

Developer workflow:
- Most of the time, no manual action is needed.
- If you change MCP tools, resources, or schemas, regenerate the file with:

```bash
bundle exec rake docs:generate_llms
```

- Confirm it is in sync with:

```bash
bundle exec rake docs:check_llms
```

- Commit the updated public/llms.txt.

## Deployment & CI/CD Details:

This project uses GitHub Actions for continuous integration and automated deployment to Heroku.
Every push to the `main` branch triggers a workflow that builds and deploys the application to Heroku.
The workflow is defined in `.github/workflows/deploy-to-heroku.yml`.

Every pull request triggers a workflow that unit tests. The workflow is defined in `.github/workflows/run-unit-tests.yml`.

## Server Access & API Documentation
The Artsdata MCP Server is actively deployed and hosted in a live production environment.

Live Production Endpoints
- MCP endpoint: https://mcp.artsdata.ca/mcp
- Agent guide: https://mcp.artsdata.ca/llms.txt