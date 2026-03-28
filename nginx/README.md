# NGINX API Gateway for Kubernetes

NGINX handles backend routing and API-path rate limiting for backend microservices. Authentication and auth-sensitive path throttling are handled at the Istio ingress gateway before requests reach NGINX.

## Request Flow

The checked-in `nginx/nginx.k8s.conf` route graph is the local-development
variant. It keeps Vite/HMR live on `/` and `/login` and exposes
`/_prod-smoke/` only as a same-origin verification seam while serving the docs
surface separately on `/api-docs`.

**Single browser entry point:** `https://app.budgetanalyzer.localhost`

```
Browser (https://app.budgetanalyzer.localhost)
    │
    ▼
Istio Ingress Gateway (:443) ─── SSL termination + ext_authz session validation
    │
    ├─→ /auth/*, /oauth2/*, /login/oauth2/*, /logout, /user → Session Gateway (:8081)
    │
    ├─→ /api/* → NGINX (:8080)
    │
    ├─→ /api-docs, /api-docs/* → NGINX (:8080)
    │
    ├─→ /login → NGINX (:8080) → React App (:3000)
    │
    ├─→ /_prod-smoke/* → NGINX (:8080) → Built React bundle (static files)
    │
    ▼ (K8s internal: nginx-gateway:8080)
NGINX (:8080) ─── API-path rate limiting, route to service
    │
    ├─→ /                 → React App (:3000)
    ├─→ /api-docs*        → Swagger UI page + unified contract downloads
    ├─→ /_prod-smoke/*    → Static smoke bundle
    ├─→ /api/v1/transactions → Transaction Service (:8082)
    ├─→ /api/v1/currencies   → Currency Service (:8084)
    └─→ /health     → Health check
```

**Why this works:**
- Single origin = no CORS
- Opaque session tokens = no JWTs exposed to browser (XSS protection)
- Resource-based routing = frontend decoupled from services
- ext_authz at Istio ingress layer validates sessions before reaching NGINX

## Rate-Limiting Split

- Istio ingress rate limits auth-sensitive browser entry points: `/login`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, and `/user`
- NGINX rate limits backend-facing API paths after ingress validation and routing
- NGINX now derives the API limiter identity from the rightmost ingress-appended `X-Forwarded-For` hop while trusting only the pod-local Envoy sidecar loopback source (`set_real_ip_from 127.0.0.0/8` with `real_ip_recursive on`)

Bare `/login` is still a frontend route. It is served through NGINX and initiates OAuth2 with `/oauth2/authorization/idp`; ingress now rate limits that entry point too, but it is not a direct Session Gateway route.

## Service Configuration

### Service Resolution (in nginx.k8s.conf)

NGINX uses variable-based `proxy_pass` with Kubernetes FQDN for dynamic DNS resolution. This allows NGINX to start before backend services are available:

```nginx
set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
proxy_pass $transaction_backend;

set $currency_backend "http://currency-service.default.svc.cluster.local:8084";
proxy_pass $currency_backend;

set $frontend_backend "http://budget-analyzer-web.default.svc.cluster.local:3000";
proxy_pass $frontend_backend;
```

### Resource-Based Routing

The frontend sees clean resource paths:
- `GET /api/v1/transactions` → Transaction Service
- `GET /api/v1/currencies` → Currency Service

NGINX handles the routing and path transformation to backend services.

## Usage with Tilt

### 1. Start all services

```bash
cd orchestration/
tilt up
```

This deploys NGINX as a Kubernetes deployment with ConfigMap-mounted configuration.

### 2. Access your app

Open your browser to **`https://app.budgetanalyzer.localhost`**

API requests go through Istio Ingress Gateway (443) → ext_authz → NGINX (8080).
OAuth2 and auth lifecycle requests go through Istio Ingress Gateway (443) → Session Gateway (8081).
The frontend login page at `/login` goes through Istio Ingress Gateway (443) → NGINX (8080).
The production-smoke verification path at `/_prod-smoke/` is served directly by NGINX from a built frontend bundle copied in by an init container; it does not proxy to the Vite dev server.
The shared docs route at `/api-docs` now serves a checked-in wrapper plus the generated OpenAPI downloads from the same NGINX pod. Stock Swagger UI assets are copied in by a pinned init container and served same-origin from that docs mount. Unlisted `/api-docs/*` paths intentionally return `404` instead of falling through to the frontend SPA.

### 3. Verify it's working

```bash
# NGINX Gateway health check (via Istio ingress)
curl https://app.budgetanalyzer.localhost/health

# React app loads
curl https://app.budgetanalyzer.localhost/

# Production-smoke bundle loads from the same public origin
curl https://app.budgetanalyzer.localhost/_prod-smoke/

# Dev route keeps the relaxed Vite/HMR CSP
curl -kI https://app.budgetanalyzer.localhost/ | grep -i content-security-policy

# Public smoke route emits the strict CSP
curl -kI https://app.budgetanalyzer.localhost/_prod-smoke/ | grep -i content-security-policy

# Public docs route is outside /api/* auth. Verify its headers directly:
curl -kI https://app.budgetanalyzer.localhost/api-docs | grep -i content-security-policy

# Machine-readable unified contracts stay public and same-origin:
curl -kI https://app.budgetanalyzer.localhost/api-docs/openapi.json
curl -kI https://app.budgetanalyzer.localhost/api-docs/openapi.yaml

# Run the full Phase 6 completion gate
./scripts/dev/verify-phase-6-edge-browser-hardening.sh
```

## Frontend Configuration

NGINX serves two frontend modes on the same origin:
- `/` and `/login` keep the existing Vite/HMR development flow through the `budget-analyzer-web` pod.
- `/_prod-smoke/` serves the sibling repo's `npm run build:prod-smoke` output as static files for CSP and browser-policy verification.

The `budget-analyzer-web-prod-smoke-build` Tilt resource runs that smoke build
locally in the sibling repo, not inside the frontend container. Keep local npm
dependencies installed there (`cd ../budget-analyzer-web && npm install`) if
you expect `/_prod-smoke/` to build or refresh. The normal frontend pod remains
separate and still installs its own dependencies inside its image. Tilt also
watches the smoke build's `.env`, `.env.local`, `.env.production`, and
`.env.production.local` inputs so relevant env changes retrigger the static
bundle path.

The smoke path is a verification seam, not a second long-term application mode. API and auth endpoints stay root-relative (`/api`, `/oauth2/authorization/idp`, `/logout`) regardless of which frontend path is loaded.

The `/api-docs` route serves a checked-in wrapper, self-hosted Swagger UI assets, and the unified OpenAPI downloads from `nginx-gateway`.
Treat those surfaces differently:
- `/api-docs` is the human-readable docs page.
- `/api-docs/openapi.json` and `/api-docs/openapi.yaml` are the machine-readable unified contracts.
The download endpoints at `/api-docs/openapi.json` and `/api-docs/openapi.yaml` intentionally do not emit wildcard CORS headers; same-origin browser fetches and downloads work through the shared public origin instead.
Any other `/api-docs/*` path is intentionally outside that allowlist and returns `404`.

## CSP Split

NGINX now serves three intentional CSP profiles:

- Relaxed development CSP on the live Vite/HMR routes (`/`, `/login`, `/@vite/client`, `/src`, `/node_modules`, `/assets`)
- Docs-only relaxed CSP on `/api-docs` and its explicit asset/download allowlist
- Strict production-oriented CSP on `/_prod-smoke/` and on the checked-in production route variant

The main strict policy removes both `'unsafe-inline'` and `'unsafe-eval'`:

```text
default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self';
```

NGINX applies those policies with checked-in include files so any `location`
that adds route-specific headers can also re-include the full security-header
set instead of accidentally dropping the inherited headers.

The docs route now uses a dedicated include:

```text
default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self';
```

That docs-only CSP is explicit because the stock Swagger UI bundle is not
strict-CSP-compatible. The main app route graph and the `/api/*` route graph do
not inherit that relaxation.

Your React app should be configured with:

**`.env`:**
```bash
VITE_API_BASE_URL=/api
VITE_USE_MOCK_DATA=false
```

**API calls:**
```typescript
// Frontend sees resource paths (no service names!)
apiClient.get('/transactions')        // Not /transaction-service/transactions
apiClient.get('/currencies')          // Not /currency-service/currencies
```

NGINX handles routing to the correct backend service.

## Checked-In Production Route Variant

`nginx/nginx.production.k8s.conf` is the explicit production cutover
configuration for `nginx-gateway`.

It changes the frontend route shape intentionally:
- `/` and `/login` serve the built frontend bundle directly from NGINX with the strict CSP.
- `/_prod-smoke/` returns `404` instead of remaining user-facing.
- `/@vite/client`, `/src`, and `/node_modules` return `404` instead of exposing the dev route graph.
- `/assets/` serves built frontend assets as static files instead of proxying to the Vite pod.

That file expects a normal root-mounted frontend production build under
`/usr/share/nginx/html`. It is not a header-only toggle layered on top of the
dev route graph.

The Phase 6 verifier does not rely on text inspection alone for that cutover
file. It stages `nginx/nginx.production.k8s.conf` inside the running
`nginx-gateway` pod, mirrors the pod's mounted include files into a temporary
prefix, and runs `nginx -p <tmpdir> -t -c nginx.production.k8s.conf` there. If
the file stops parsing or the expected runtime includes are missing, the
verifier fails explicitly.

## Commands

```bash
# View NGINX logs
kubectl logs deployment/nginx-gateway

# Check NGINX config syntax
kubectl exec deployment/nginx-gateway -- nginx -t

# Reload NGINX config (Tilt does this automatically)
kubectl exec deployment/nginx-gateway -- nginx -s reload

# Trigger config reload via Tilt
tilt trigger nginx-gateway-config
```

The Kubernetes access log now includes the derived `remote_addr`, the trusted proxy hop as `proxy_addr`, `X-Forwarded-For`, and `X-Real-IP` so the Phase 3 and Phase 6 verifiers can prove forwarded-header preservation and the API rate-limit trust model through Istio ingress.

Phase 6 Session 7 adds a dedicated runtime proof:

```bash
./scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh
```

That verifier creates two temporary no-sidecar probe pods, sends authenticated API traffic through the live ingress gateway, confirms NGINX derives distinct client identities from the ingress-appended downstream hop, proves a forged external `X-Forwarded-For` value cannot pick a new bucket, and checks that separate real clients do not share one API limiter bucket.

The full Phase 6 completion gate is:

```bash
./scripts/dev/verify-phase-6-edge-browser-hardening.sh
```

It verifies the dev/strict CSP split on the real app paths, warning-only docs visibility,
the checked-in production route cutover, a real `nginx -t` syntax check of
`nginx/nginx.production.k8s.conf` inside the running `nginx-gateway` pod, the
fail-closed docs-path behavior,
the remaining auth-edge throttling
coverage, reruns the Session 3 frontend CSP audit, reruns the Session 7 API
identity verifier, and then reruns the Phase 5 runtime-hardening cascade.
Manual browser-console validation on `/_prod-smoke/` is still required before
Phase 6 is actually complete; `/api-docs` warnings remain visible but do not
block completion.

## Customization

### Adding a New Resource Route

**Scenario:** You want to add `/api/accounts` served by Transaction Service.

1. Add location block in `nginx.k8s.conf`:
```nginx
location /api/accounts {
    set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
    limit_req zone=per_ip burst=50 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

2. Tilt will automatically reload the ConfigMap and NGINX.

3. Frontend code (no changes needed if using consistent API client):
```typescript
apiClient.get('/accounts')
```

### Adding a New Microservice

**Scenario:** You're adding a new "Reports Service" on port 8086.

1. Add location blocks for its resources in `nginx.k8s.conf`:
```nginx
location /api/reports {
    set $reports_backend "http://reports-service.default.svc.cluster.local:8086";
    limit_req zone=per_ip burst=50 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /reports-service/v1/$1 break;
    proxy_pass $reports_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

3. Tilt will reload automatically.

### Moving a Resource Between Services

**Scenario:** You want to move `/transactions` from one service to another.

**Frontend code:** No changes needed! 🎉

**NGINX config:** Just update the location block:

```nginx
location /api/v1/transactions {
    set $transaction_backend "http://new-transaction-service.default.svc.cluster.local:8082";
    limit_req zone=per_ip burst=50 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /new-transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

This is the power of resource-based routing!

## Troubleshooting

### React app not loading (502 Bad Gateway)

**Cause:** NGINX can't reach the frontend service.

**Fix:**
1. Check if frontend pod is running: `kubectl get pods | grep budget-analyzer-web`
2. Check frontend service exists: `kubectl get svc budget-analyzer-web`
3. View NGINX logs for errors: `kubectl logs deployment/nginx-gateway`

### Production-smoke path not loading

**Cause:** The smoke bundle did not build, the static asset image is stale, or the init container failed to copy files into the NGINX volume.

**Fix:**
1. Check the Tilt resource: `tilt get uiresources | grep budget-analyzer-web-prod-smoke-build`
2. Ensure the sibling repo has local npm dependencies: `cd ../budget-analyzer-web && npm install`
3. Re-run the build directly if needed: `cd ../budget-analyzer-web && npm run build:prod-smoke`
4. Inspect the init container: `kubectl logs deployment/nginx-gateway -c web-prod-smoke-assets --previous`
5. Verify the copied files exist: `kubectl exec deployment/nginx-gateway -- ls -R /usr/share/nginx/html/_prod-smoke`

### API requests fail (404 or 502)

**Cause:** Backend service not running or NGINX can't reach it.

**Fix:**
1. Verify service is running: `kubectl get pods | grep transaction-service`
2. Check NGINX logs: `kubectl logs deployment/nginx-gateway`
3. Verify service DNS resolution: `kubectl exec deployment/nginx-gateway -- nslookup transaction-service`

### Getting 401 Unauthorized

**Cause:** ext_authz session validation failed.

**Fix:**
1. Check ext-authz is running: `kubectl get pods | grep ext-authz`
2. Check ext-authz logs: `kubectl logs deployment/ext-authz`
3. Verify session cookie is being sent and Redis has session data

### CORS issues

**You shouldn't have CORS issues!** Everything is same-origin (`app.budgetanalyzer.localhost` via Istio ingress gateway).

The BFF (Backend for Frontend) pattern eliminates CORS:
- Browser sees single origin: `app.budgetanalyzer.localhost`
- Istio ingress gateway routes to NGINX or Session Gateway
- NGINX routes to backend services
- No cross-origin requests = no CORS

If you see CORS errors:
1. Verify you're accessing via `https://app.budgetanalyzer.localhost` (not direct service ports)
2. Check that `VITE_API_BASE_URL=/api` in `.env` (relative URL, not full URL)
3. Check Session Gateway is running and configured correctly
4. Do not expect `/api-docs/openapi.{json,yaml}` to return `Access-Control-Allow-Origin: *`; those downloads are intentionally same-origin
5. Do not expect other unlisted `/api-docs/*` paths to work; the docs subtree is allowlisted and those requests intentionally return `404`

### ConfigMap not updating

**Cause:** Tilt didn't detect the config change.

**Fix:**
1. Manually trigger reload: `tilt trigger nginx-gateway-config`
2. Check ConfigMap content: `kubectl get configmap nginx-gateway-config -o yaml`

## Configuration Files

### nginx.k8s.conf

Main NGINX configuration for Kubernetes deployment. Uses Kubernetes DNS names for service discovery.
It also trusts only the pod-local loopback proxy hop for `real_ip_*` handling so API `limit_req` keys on the derived client address instead of the sidecar hop.

### includes/

Shared configuration snippets:
- `backend-headers.conf` - Standard proxy headers and identity header forwarding

## Production Considerations

Production should not mirror the local verification seam exactly:

1. **React app**: Serve the built frontend on `/` and `/login` with the strict CSP by using `nginx/nginx.production.k8s.conf`.
2. **`/_prod-smoke/`**: Treat it as local-only verification plumbing. The checked-in production route variant returns `404` for it.
3. **Dev-only public paths**: `/@vite/client`, `/src`, and `/node_modules` must stay unavailable in production.
4. **Microservices**: Same - Kubernetes DNS names work identically.
5. **SSL/TLS**: Handled by Istio ingress gateway (or cloud load balancer).

The production route shape should stay user-facing and simple: normal app
routes at `/` and `/login`, docs at `/api-docs`, APIs at `/api/*`, and no
dev-server-only paths exposed publicly.
