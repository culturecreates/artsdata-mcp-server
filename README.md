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

## Deployment & CI/CD Details:

This project uses GitHub Actions for continuous integration and automated deployment to Heroku.
Every push to the `main` branch triggers a workflow that builds and deploys the application to Heroku.
The workflow is defined in `.github/workflows/deploy-to-heroku.yml`.

The Heroku app is configured to use the `production` environment variables from the Heroku CLI.
Every pull request triggers a workflow that runs unit tests.
The workflow is defined in `.github/workflows/run-unit-tests.yml`.

## Server Access & API Documentation
The Artsdata MCP Server is actively deployed and hosted in a live production environment.

Live Production Endpoints
API Documentation (Swagger UI): https://artsdata-mcp-server-8cb4262e2362.herokuapp.com/api-docs/index.html