# API Documentation Aggregator

This service provides a unified Swagger UI interface for all Budget Analyzer microservices.

## Overview

The docs aggregator consolidates OpenAPI documentation from all microservices into a single, interactive interface. It uses the same Swagger UI that each individual microservice uses, but configured to load specs from multiple sources.

## Features

- **Unified View**: All API documentation in one place
- **Service Selector**: Dropdown to switch between different microservices
- **Gateway-Backed Specs**: OpenAPI specs are loaded through the same public origin and gateway stack as the rest of the app
- **Current UI Mode**: "Try it out" is intentionally disabled in the shared docs page

## Architecture

```
User Browser
    ↓
https://app.budgetanalyzer.localhost/api/docs (Swagger UI HTML)
    ↓
Loads OpenAPI specs from:
    - https://app.budgetanalyzer.localhost/api/transaction-service/v3/api-docs
    - https://app.budgetanalyzer.localhost/api/currency-service/v3/api-docs
    ↓
Displayed through the same public origin and gateway stack as the rest of the app
```

## Configuration

The aggregator is configured in `index.html` with the following key settings:

### API Spec URLs

```javascript
urls: [
    {
        name: "Budget Analyzer API",
        url: baseUrl + "/api/transaction-service/v3/api-docs"
    },
    {
        name: "Currency Service",
        url: baseUrl + "/api/currency-service/v3/api-docs"
    }
]
```

### Adding a New Microservice

To add documentation for a new microservice:

1. Update `docs-aggregator/index.html` - add new URL to the array
2. Update `nginx/nginx.k8s.conf` to proxy the new service's api-docs endpoint
3. Let Tilt apply the config change or run `tilt trigger nginx-gateway-config`

## Dependencies

- **Swagger UI**: v5.10.3 (loaded from unpkg.com CDN)
- **NGINX**: Alpine-based image for serving static content
