# Resource-Based Routing Pattern

**Pattern Category:** API Gateway
**Status:** Active
**Related ADR:** [002-resource-based-routing.md](../decisions/002-resource-based-routing.md)

## Overview

Budget Analyzer uses resource-based routing at the NGINX gateway. The frontend calls stable resource paths, while NGINX owns the mapping to service-specific upstream paths.

This keeps the frontend decoupled from backend topology. A route can move between services without forcing a frontend URL change.

## Core Principle

> **Frontend calls resources, not services.**

Examples:
- `GET /api/v1/transactions`
- `GET /api/v1/currencies`
- `GET /api/v1/exchange-rates`

The frontend should never call service-specific paths such as `/transaction-service/...`.

## Current Request Shape

```text
Browser
  -> https://app.budgetanalyzer.localhost/api/v1/transactions
  -> Istio Ingress Gateway
  -> ext_authz
  -> NGINX
  -> transaction-service /transaction-service/v1/transactions
```

## Current Configuration

**Source of truth:** [nginx.k8s.conf](../../nginx/nginx.k8s.conf)

Example route:

```nginx
location /api/v1/transactions {
    set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include includes/backend-headers.conf;
}
```

## Discovery

```bash
# List current resource routes
grep "location /api" nginx/nginx.k8s.conf | grep -v "#"

# Test a route through the public entry point
curl -v https://app.budgetanalyzer.localhost/api/v1/transactions
```

## Adding a Route

1. Choose a resource path.
2. Add a location block to `nginx/nginx.k8s.conf`.
3. Point it at the correct in-cluster service.
4. Keep the frontend path resource-based.

Example:

```nginx
location /api/v1/accounts {
    set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
    limit_req zone=per_ip burst=50 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include includes/backend-headers.conf;
}
```

Frontend call:

```ts
apiClient.get("/accounts")
```

## Refactoring Benefit

If a resource moves between services, the frontend can keep calling the same external path. Only the NGINX route needs to change.

## Best Practices

- Use resource names, not service names, in browser-facing URLs.
- Keep API versioning in the path.
- Use in-cluster service DNS names in NGINX upstreams.
- Treat `nginx/nginx.k8s.conf` as the current routing source of truth.
