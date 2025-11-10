# API Documentation Aggregator

This service provides a unified Swagger UI interface for all Budget Analyzer microservices.

## Overview

The docs aggregator consolidates OpenAPI documentation from all microservices into a single, interactive interface. It uses the same Swagger UI that each individual microservice uses, but configured to load specs from multiple sources.

## Features

- **Unified View**: All API documentation in one place
- **Service Selector**: Dropdown to switch between different microservices
- **Try It Out**: Full interactive API testing functionality
- **Real Requests**: All requests go through the NGINX gateway with proper routing

## Architecture

```
User Browser
    ↓
http://localhost:8080/api/docs (Swagger UI HTML)
    ↓
Loads OpenAPI specs from:
    - http://localhost:8080/api/transaction-service/v3/api-docs
    - http://localhost:8080/api/currency-service/v3/api-docs
    ↓
"Try it out" requests → NGINX Gateway → Appropriate Microservice
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
2. Update `nginx/nginx.dev.conf` to proxy the new service's api-docs endpoint
3. Restart services: `docker-compose restart nginx-gateway`

## Dependencies

- **Swagger UI**: v5.10.3 (loaded from unpkg.com CDN)
- **NGINX**: Alpine-based image for serving static content
