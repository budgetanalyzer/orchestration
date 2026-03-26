# API Documentation Aggregator

`/api/docs` is a lightweight developer convenience page for viewing the shared
Budget Analyzer API documentation. It is intentionally best-effort and is not a
browser-hardening contract or production support surface.

## Overview

The docs page serves a simple checked-in HTML shell from this repository and
loads Swagger UI from the public CDN at runtime. The page points Swagger UI at
the gateway-backed service OpenAPI endpoints and keeps the shared UI in
read-only mode.

The generated unified downloads remain checked in here:

- `docs-aggregator/openapi.json`
- `docs-aggregator/openapi.yaml`

Those files are refreshed by `./scripts/generate-unified-api-docs.sh`.

## Runtime Shape

```
Browser
    ↓
https://app.budgetanalyzer.localhost/api/docs
    ↓
Loads Swagger UI from unpkg CDN
    ↓
Fetches service specs from the public gateway origin
```

The direct downloads at `/api/docs/openapi.json` and `/api/docs/openapi.yaml`
remain available for browser download or tooling use.

## Files

- `index.html` contains the full page shell, inline styling, and Swagger UI bootstrap.
- `openapi.json` and `openapi.yaml` are generated unified OpenAPI outputs.

## Adding a New Microservice

1. Update `docs-aggregator/index.html` and add the new docs endpoint to the `urls` array.
2. Update the NGINX gateway routes so the service's `v3/api-docs` endpoint is reachable.
3. Rerun `./scripts/generate-unified-api-docs.sh` if the unified download artifacts should include that service.

## Dependencies

- Swagger UI `5.11.0`, loaded from `https://unpkg.com/swagger-ui-dist@5.11.0/`
- NGINX serving the checked-in docs files and generated OpenAPI downloads
