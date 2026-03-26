# API Documentation Aggregator

This service provides a unified Swagger UI interface for all Budget Analyzer microservices.

## Overview

The docs aggregator consolidates OpenAPI documentation from all microservices into a single, interactive interface. It uses the same Swagger UI that each individual microservice uses, but configured to load specs from multiple sources.

## Features

- **Unified View**: All API documentation in one place
- **Service Selector**: Dropdown to switch between different microservices
- **Gateway-Backed Specs**: OpenAPI specs are loaded through the same public origin and gateway stack as the rest of the app
- **Same-Origin Downloads**: The OpenAPI download endpoints stay on the shared origin and do not expose wildcard CORS
- **Current UI Mode**: "Try it out" is intentionally disabled in the shared docs page
- **Strict-CSP Ready Delivery**: Swagger UI CSS/JS is pinned in-repo and served from the same `/api/docs` origin path
- **Strict-CSP Enforcement**: `nginx-gateway` serves `/api/docs` with a strict CSP that removes both `'unsafe-inline'` and `'unsafe-eval'`

## Architecture

```
User Browser
    ↓
https://app.budgetanalyzer.localhost/api/docs (Swagger UI HTML)
    ↓
Loads pinned same-origin assets from:
    - https://app.budgetanalyzer.localhost/api/docs/swagger-ui.css
    - https://app.budgetanalyzer.localhost/api/docs/swagger-ui-bundle.js
    - https://app.budgetanalyzer.localhost/api/docs/swagger-ui-standalone-preset.js
    - https://app.budgetanalyzer.localhost/api/docs/docs-aggregator.css
    - https://app.budgetanalyzer.localhost/api/docs/docs-aggregator.js
    ↓
Loads OpenAPI specs from:
    - https://app.budgetanalyzer.localhost/api/transaction-service/v3/api-docs
    - https://app.budgetanalyzer.localhost/api/currency-service/v3/api-docs
    ↓
Displayed through the same public origin and gateway stack as the rest of the app
```

The optional direct downloads at `/api/docs/openapi.json` and `/api/docs/openapi.yaml` are served from that same origin path as attachments. They are intended for same-origin browser use or non-browser tooling and do not rely on `Access-Control-Allow-Origin: *`.

## Configuration

The page shell lives in `index.html`. The Swagger bootstrap is in `docs-aggregator.js`, and the custom styling is in `docs-aggregator.css`.

### API Spec URLs

```javascript
const urls = [
    {
        name: "Transaction Service",
        url: `${window.location.origin}/api/transaction-service/v3/api-docs`
    },
    {
        name: "Currency Service",
        url: `${window.location.origin}/api/currency-service/v3/api-docs`
    }
];
```

### Swagger UI Behavior

`docs-aggregator.js` pins the shared docs UI to read-only mode:

```javascript
tryItOutEnabled: false,
supportedSubmitMethods: [],
```

### Adding a New Microservice

To add documentation for a new microservice:

1. Update `docs-aggregator/docs-aggregator.js` and add the new URL to the `urls` array
2. Update `nginx/nginx.k8s.conf` to proxy the new service's api-docs endpoint
3. Let Tilt rebuild the `budget-analyzer-docs-assets` image and redeploy `nginx-gateway`, or trigger `tilt trigger nginx-gateway` if you need to force reconciliation

## Pinned Assets

- **Swagger UI**: v5.11.0, vendored from the npm tarball
- **Integrity**: `sha512-j0PIATqQSEFGOLmiJOJZj1X1Jt6bFIur3JpY7+ghliUnfZs0fpWDdHEkn9q7QUlBtKbkn6TepvSxTqnE8l3s0A==`
- **Refresh command**: `./scripts/refresh-swagger-ui-assets.sh`

The refresh script downloads the exact tarball from the npm registry, verifies its SHA-512 integrity string, and updates the pinned files in `docs-aggregator/`.
