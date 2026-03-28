# API Documentation Aggregator

`/api-docs` is the human-friendly developer page for viewing the shared Budget
Analyzer API documentation. It is intentionally separate from the main app and
`/api/*` browser-hardening contract.

The machine-readable contract stays first-class on the same public route:

- `/api-docs/openapi.json` is the unified JSON contract
- `/api-docs/openapi.yaml` is the unified YAML contract

## Overview

The docs page serves a checked-in wrapper from this repository, stages stock
Swagger UI `5.11.0` assets from a pinned `swaggerapi/swagger-ui` init
container, and points the browser at the same-origin checked-in unified spec at
`/api-docs/openapi.json`.

The route is intentionally read-only:

- Swagger UI runs with `supportedSubmitMethods: []`
- the wrapper hides the authorize button
- raw JSON and YAML downloads remain first-class on the same route for tooling
  and direct download use

The generated unified downloads remain checked in here:

- `docs-aggregator/openapi.json`
- `docs-aggregator/openapi.yaml`

Those files are refreshed by `./scripts/generate-unified-api-docs.sh`.

## Public Outputs

- `/api-docs` is the human docs page backed by self-hosted Swagger UI.
- `/api-docs/openapi.json` is the machine-readable JSON contract.
- `/api-docs/openapi.yaml` is the machine-readable YAML contract.

## Runtime Shape

```
Browser
    ↓
https://app.budgetanalyzer.localhost/api-docs
    ↓
Receives self-hosted Swagger UI assets from nginx-gateway
    ↓
Fetches `/api-docs/openapi.json` from the same public origin
```

The direct downloads at `/api-docs/openapi.json` and `/api-docs/openapi.yaml`
remain available for browser download, local inspection, or tooling use.

`/api-docs` now carries its own docs-only relaxed CSP include. That profile is
limited to what the self-hosted Swagger UI bundle needs and does not change the
main app or `/api/*` posture.

## Files

- `index.html` contains the wrapper page and same-origin asset references.
- `swagger-initializer.js` holds the small Swagger UI bootstrap configuration.
- `swagger-ui-overrides.css` contains the wrapper styling and minor UI overrides.
- `openapi.json` and `openapi.yaml` are generated unified OpenAPI outputs.

## Adding a New Microservice

1. Update `./scripts/generate-unified-api-docs.sh` so it fetches and merges the new service spec into the unified output.
2. Rerun `./scripts/generate-unified-api-docs.sh` to refresh the checked-in `openapi.json` and `openapi.yaml` artifacts.
3. Only update NGINX docs routing if you intentionally want to expose that service's raw live `v3/api-docs` endpoint for some separate non-browser use case.

## Dependencies

- stock Swagger UI `5.11.0` assets, staged from pinned `swaggerapi/swagger-ui:v5.11.0`
- NGINX serving the checked-in wrapper files and generated OpenAPI downloads
- `kubectl` access to the running local cluster when regenerating the unified spec
