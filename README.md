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

- `artsdata://dump` (`artsdata_dump`): manifest for the latest complete data dump.
  Dumps are gzipped Turtle files (`artsdata-YYYY-MM-DD-core-minus-provenance.ttl.gz`)
  published to a public S3 bucket on the first day of each month. `resources/read` lists
  the bucket prefix anonymously (S3 `ListObjectsV2`, no credentials), picks the object with
  the newest `LastModified`, and returns a small JSON document with its download URL, size,
  ETag, last-modified and a `version` token — never the dump contents. Clients download
  the file from `dump.url` and compare `dump.version` across reads to detect a new dump.

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
- `ARTSDATA_CORS_ORIGINS` (optional): comma-separated CORS origins (default `*`).
- `ARTSDATA_DUMPS_BUCKET_URL` : base URL of the public S3 bucket holding the
  data dumps.
- `ARTSDATA_DUMP_FOLDER` : folder name that contains latest dump inside the
  bucket.
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