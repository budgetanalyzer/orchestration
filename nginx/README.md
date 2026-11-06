# NGINX API Gateway for Kubernetes

NGINX handles resource-based routing and load balancing for backend microservices. Istio ingress is the sole owner of general per-client auth/API rate limiting.

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
    ├─→ /auth/*, /oauth2/*, /login/oauth2/*, /logout → Session Gateway (:8081)
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
NGINX (:8080) ─── route and load balance to service
    │
    ├─→ /                 → React App (:3000)
    ├─→ /api-docs*        → Swagger UI page + unified contract downloads
    ├─→ /_prod-smoke/*    → Static smoke bundle
    ├─→ /api/v1/transactions → Transaction Service (:8082)
    ├─→ /api/v1/currencies   → Currency Service (:8084)
    ├─→ /api/v1/users        → Permission Service (:8086)
    └─→ /health     → Health check
```

**Why this works:**
- Single origin = no CORS
- Opaque session tokens = no JWTs exposed to browser (XSS protection)
- Resource-based routing = frontend decoupled from services
- ext_authz at Istio ingress layer validates sessions before reaching NGINX

## Rate-Limiting Ownership

- Istio ingress has four per-client policies for login initiation, login completion, session operations, and API requests; exact boundaries and capacities are owned by [the security architecture](../docs/architecture/security-architecture.md#ingress-per-client-rate-limiting)
- NGINX has no blanket `limit_req` zone or API directives; add no backend-specific replacement without a demonstrated requirement
- NGINX still derives the downstream client identity from the rightmost ingress-appended `X-Forwarded-For` hop while trusting only the pod-local Envoy sidecar loopback source (`set_real_ip_from 127.0.0.0/8` with `real_ip_recursive on`) so logs and forwarded backend headers remain trustworthy

Bare `/login` is still a frontend route outside the OAuth-initiation budget. It is served through NGINX and starts the separately limited OAuth flow at `/oauth2/authorization/idp`; it is not a direct Session Gateway route.

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
- `POST /api/v1/users/{id}/deactivate` → Permission Service

NGINX handles the routing and path transformation to backend services.
The browser edge intentionally does not route any `/internal/**` path. Internal
service endpoints stay east-west only unless a specific public `/api/...` route
is added here.

The `/api` namespace fails closed. After all owned resource routes, each NGINX
variant defines an exact `/api` location and an `/api/` prefix fallback that
return an explicit `404 text/plain` response. This keeps unknown API paths out
of the frontend SPA while allowing longer, owned resource locations to
continue routing to their services. Keep the explicit response body: a bare
`return 404;` makes NGINX generate an HTML error page.

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
OAuth2 and auth lifecycle requests go through Istio Ingress Gateway (443) → Session Gateway (8081). The browser JSON endpoints now live at `/auth/v1/session` and `/auth/v1/user`.
The frontend login page at `/login` goes through Istio Ingress Gateway (443) → NGINX (8080).
The production-smoke verification path at `/_prod-smoke/` is served directly by NGINX from a built frontend bundle copied in by an init container; it does not proxy to the Vite dev server.
NGINX also mounts the shared docs surface at `/api-docs`. Exact docs-route
behavior, generated outputs, and docs-only CSP details live in
[../docs-aggregator/README.md](../docs-aggregator/README.md).

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

# Run the edge and browser hardening verifier
./scripts/smoketest/verify-edge-browser-hardening.sh
```

The surrounding script layout is purpose-split: gateway day-two helpers such as
Redis/session maintenance live under `scripts/ops/`, while route and browser
contract proofs live under `scripts/smoketest/`.

## Frontend Configuration

NGINX serves two frontend modes on the same origin:
- `/` and `/login` keep the existing Vite/HMR development flow through the `budget-analyzer-web` pod.
- `/_prod-smoke/` serves the sibling repo's `npm run build:prod-smoke` output as static files for CSP and browser-policy verification.

The `budget-analyzer-web-prod-smoke` Tilt image target runs that smoke build
locally in the sibling repo, not inside the frontend container, then builds the
tiny static-asset image directly from the completed `dist/` directory as the
same atomic operation. Keep local npm dependencies installed there
(`cd ../budget-analyzer-web && npm install`) if you expect `/_prod-smoke/` to
build or refresh. The normal frontend pod remains separate and still installs
its own dependencies inside its image. Tilt watches the smoke build inputs,
including `.env`, `.env.local`, `.env.production`, and
`.env.production.local`, plus the asset Dockerfile. A changed image reference
updates the NGINX Deployment, replaces its pod, and reruns the init container
that copies the current bundle into the pod-local volume. Exact mechanics live
in [../docs/development/local-environment.md](../docs/development/local-environment.md#frontend-reactvite).

The smoke path is a verification seam, not a second long-term application mode. API and auth endpoints stay root-relative (`/api`, `/oauth2/authorization/idp`, `/logout`) regardless of which frontend path is loaded.

NGINX also serves the repo-owned docs surface at `/api-docs`. Keep the route
mounted here, but treat [../docs-aggregator/README.md](../docs-aggregator/README.md)
as the canonical owner for exact docs outputs, allowlist behavior, and
browser-facing contract details.

## CSP Split

NGINX now serves three intentional CSP profiles:

- Relaxed development CSP on the live Vite/HMR routes (`/`, `/login`, `/@vite/client`, `/src`, `/node_modules`, `/assets`)
- Separate docs-route CSP for the repo-owned `/api-docs` surface; see
  [../docs-aggregator/README.md](../docs-aggregator/README.md) for the exact
  docs contract
- Strict production-oriented CSP on `/_prod-smoke/` and on the checked-in production route variant

The main strict policy removes both `'unsafe-inline'` and `'unsafe-eval'`:

```text
default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'; form-action 'self' <configured-IdP-origin>;
```

Every profile permits form submissions only to `'self'` and the configured
IdP's exact HTTPS origin, supporting the upcoming native form logout redirect.
`deploy/scripts/render/render-csp.py` replaces `__IDP_LOGOUT_ORIGIN__` in the
shared templates. Tilt uses `AUTH0_ISSUER_URI`, matching Session Gateway and
egress; the offline production renderer uses its own reference issuer. Empty,
non-HTTPS, wildcard or malformed values fail rendering. Do not copy a template
verbatim into a running ConfigMap or add a second tenant allowance.

The includes omit `X-XSS-Protection`. HSTS belongs to the ingress: every route
rule sets exactly `max-age=31536000`, including the direct Session Gateway
lane. The same rules strip caller-supplied forwarding authority fields; see
[the security architecture](../docs/architecture/security-architecture.md#ingress-header-ownership).
`verify-edge-contract.sh` checks all four response paths and forged login
forwarding fields; `verify-edge-browser-hardening.sh` checks each live CSP
profile's exact form sources and headers with normal TLS verification.

NGINX applies those policies with checked-in include files so any `location`
that adds route-specific headers can also re-include the full security-header
set instead of accidentally dropping the inherited headers.

The docs route keeps its own dedicated include because the stock Swagger UI
bundle is not strict-CSP-compatible. The main app route graph and the `/api/*`
route graph do not inherit that relaxation.

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
configuration for `nginx-gateway`. The production app Kustomization generates
its ConfigMaps directly from this file and the top-level `nginx/includes/`
files; there is no second production-reference copy to keep synchronized.

It changes the frontend route shape intentionally:
- `/` and `/login` serve the built frontend bundle directly from NGINX with the strict CSP.
- `/_prod-smoke/` returns `404` instead of remaining user-facing.
- `/@vite/client`, `/src`, and `/node_modules` return `404` instead of exposing the dev route graph.
- `/assets/` serves built frontend assets as static files instead of proxying to the Vite pod.

That file expects a normal root-mounted frontend production build under
`/usr/share/nginx/html`. It is not a header-only toggle layered on top of the
dev route graph.

The production route verifier does not rely on text inspection alone for that cutover
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

# Reload NGINX after an include change. Tilt updates the ConfigMap and the
# kubelet refreshes /etc/nginx/includes, but the running NGINX keeps the old
# config until reloaded. nginx.conf is a subPath mount, so a main-config change
# needs a pod restart instead.
kubectl exec deployment/nginx-gateway -- nginx -s reload

# Trigger config reload via Tilt
tilt trigger nginx-gateway-config
```

The Kubernetes access log includes the derived `remote_addr`, the trusted proxy hop as `proxy_addr`, `X-Forwarded-For`, and `X-Real-IP` so the ingress and browser hardening verifiers can prove forwarded-header preservation through Istio ingress.

The focused ingress rate-limit and downstream identity proof is:

```bash
./scripts/smoketest/verify-ingress-rate-limits.sh
```

That verifier creates two temporary no-sidecar clients, proves ingress client and policy isolation, and retains the independent check that NGINX derives distinct client identities from the ingress-appended downstream hop rather than a forged external `X-Forwarded-For` value.

The edge and browser hardening verifier is:

```bash
./scripts/smoketest/verify-edge-browser-hardening.sh
```

It verifies the dev/strict CSP split on the real app paths, warning-only docs visibility,
the checked-in production route cutover, a real `nginx -t` syntax check of
`nginx/nginx.production.k8s.conf` inside the running `nginx-gateway` pod, the
fail-closed API namespace and docs-path behavior,
the focused ingress per-client rate-limit proof, reruns the frontend CSP audit, and
then reruns the runtime-hardening cascade.
Manual browser-console validation on `/_prod-smoke/` is still required before
the browser proof is complete; `/api-docs` warnings remain visible but do not
block the verifier.

## Customization

### Adding a New Resource Route

**Scenario:** You want to add `/api/accounts` served by Transaction Service.

1. Add the location block once, in the shared `nginx/includes/api-routes.conf`,
   above the unknown-route rejections. Both `nginx/nginx.k8s.conf` and
   `nginx/nginx.production.k8s.conf` include that file, so do not add `/api`
   locations to either server config:
```nginx
location /api/v1/accounts {
    set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include includes/backend-headers.conf;
}
```

2. Allow the rewritten upstream path for the NGINX identity in the backend's
   rule in `kubernetes/istio/authorization-policies.yaml`, with both an exact
   entry and a `/*` entry:
```yaml
              - "/transaction-service/v1/accounts"
              - "/transaction-service/v1/accounts/*"
```
   The mesh lists exact public prefixes only, so a new resource without its
   mesh path fails closed with `403` and the body `RBAC: access denied`. Never
   widen the rule to `/<service>/v1/*`; the static guardrail rejects
   service- and version-wide wildcards. See
   [Mesh Public/Internal Boundary](../docs/architecture/security-architecture.md#mesh-publicinternal-boundary).

3. Verify checked-in route ownership and the shared-route contract:
```bash
rg -n "/api/v1/accounts" nginx/includes/api-routes.conf
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
rg -n "/transaction-service/v1/accounts" kubernetes/istio/authorization-policies.yaml
```

4. Validate the active NGINX pod still parses the live config:
```bash
kubectl exec deployment/nginx-gateway -- nginx -t
```

5. Probe the public route and make sure it does not leak the frontend SPA or
   stop at the mesh `403`:
```bash
curl -isS https://app.budgetanalyzer.localhost/api/v1/accounts
```

6. Frontend code (no changes needed if using consistent API client):
```typescript
apiClient.get('/accounts')
```

Public `/api/...` work is incomplete if only one NGINX variant changes or if
verification stops at status codes. Keep new resource locations above the
fail-closed API fallback and verify that unknown API paths still return the
explicit non-HTML `404` rather than frontend HTML.

### Adding a New Microservice

**Scenario:** You're adding a new "Reports Service" on port 8086.

1. Add location blocks for its resources in the shared `includes/api-routes.conf`:
```nginx
location /api/reports {
    set $reports_backend "http://reports-service.default.svc.cluster.local:8086";
    rewrite ^/api/v1/(.*)$ /reports-service/v1/$1 break;
    proxy_pass $reports_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

2. Add an `AuthorizationPolicy` for the service in
   `kubernetes/istio/authorization-policies.yaml` whose NGINX rule lists the
   exact rewritten resource paths, as in
   [Adding a New Resource Route](#adding-a-new-resource-route). `default-deny-all`
   leaves a workload with no ALLOW rule unreachable.

3. Tilt will reload automatically.

### Moving a Resource Between Services

**Scenario:** You want to move `/transactions` from one service to another.

**Frontend code:** No changes needed! 🎉

**NGINX config:** Just update the location block in `nginx/includes/api-routes.conf`:

```nginx
location /api/v1/transactions {
    set $transaction_backend "http://new-transaction-service.default.svc.cluster.local:8082";
    rewrite ^/api/v1/(.*)$ /new-transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

Move the resource's mesh paths to the new service's policy in
`kubernetes/istio/authorization-policies.yaml` in the same change.

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
1. Check the owning Tilt resource: `tilt get uiresources nginx-gateway`
2. Ensure the sibling repo has local npm dependencies: `cd ../budget-analyzer-web && npm install`
3. Inspect the image map: `tilt get imagemaps budget-analyzer-web-prod-smoke`
4. Inspect the NGINX image-build logs: `tilt logs nginx-gateway`
5. Inspect the init container: `kubectl logs deployment/nginx-gateway -c web-prod-smoke-assets`
6. Verify the copied files exist: `kubectl exec deployment/nginx-gateway -c nginx -- ls -R /usr/share/nginx/html/_prod-smoke`

### API requests fail (404 or 502)

**Cause:** Backend service not running or NGINX can't reach it.

**Fix:**
1. Verify service is running: `kubectl get pods | grep transaction-service`
2. Check NGINX logs: `kubectl logs deployment/nginx-gateway`
3. Verify service DNS resolution: `kubectl exec deployment/nginx-gateway -- nslookup transaction-service`

### API route returns 403 `RBAC: access denied`

**Cause:** The Istio sidecar on the backend denied the NGINX identity because
the rewritten upstream path is not in the backend's NGINX rule in
`kubernetes/istio/authorization-policies.yaml`. An application `403` has a JSON
body instead.

**Fix:** Add the exact and `/*` mesh paths for the resource as described in
[Adding a New Resource Route](#adding-a-new-resource-route). Do not widen the
rule to `/<service>/v1/*`.

### Path with `;` returns 403 or 400

**Cause:** Matrix-parameter syntax is rejected on purpose. The ingress
`ingress-path-hardening` filter answers `403` with the body
`RBAC: access denied` for a literal `;` or a `%3b`/`%3B` at any
percent-encoding depth (`%253b`, `%25253b` and so on) in the path on every
lane, before `ext_authz`, NGINX or Session Gateway. The shared
`api-routes.conf` answers `400` for a decoded `;` that reaches NGINX by another
route. A `;` in the query string is unaffected. See
[Ingress Path Hardening](../docs/architecture/security-architecture.md#ingress-path-hardening).

**Fix:** Send the value as a query parameter or a path segment without `;`.

### Getting 401 Unauthorized

**Cause:** ext_authz session validation failed.

**Fix:**
1. Check ext-authz is running: `kubectl get pods | grep ext-authz`
2. Check ext-authz logs: `kubectl logs deployment/ext-authz`
3. Verify session cookie is being sent and Redis has session data

### CORS issues

**You shouldn't have CORS issues!** Everything is same-origin (`app.budgetanalyzer.localhost` via Istio ingress gateway).

The session-based edge authorization pattern eliminates CORS:
- Browser sees single origin: `app.budgetanalyzer.localhost`
- Istio ingress gateway routes to NGINX or Session Gateway
- NGINX routes to backend services
- No cross-origin requests = no CORS

If you see CORS errors:
1. Verify you're accessing via `https://app.budgetanalyzer.localhost` (not direct service ports)
2. Check that `VITE_API_BASE_URL=/api` in `.env` (relative URL, not full URL)
3. Check Session Gateway is running and configured correctly
4. Use [../docs-aggregator/README.md](../docs-aggregator/README.md) for the
   exact `/api-docs` browser contract instead of debugging against stale copied
   expectations here

### ConfigMap not updating

**Cause:** Tilt didn't detect the config change.

**Fix:**
1. Manually trigger reload: `tilt trigger nginx-gateway-config`
2. Check ConfigMap content: `kubectl get configmap nginx-gateway-config -o yaml`

## Configuration Files

### nginx.k8s.conf

Main NGINX configuration for Kubernetes deployment. Uses Kubernetes DNS names for service discovery.
It also trusts only the pod-local loopback proxy hop for `real_ip_*` handling so logs and backend forwarding use the ingress-appended client address instead of the sidecar hop.

### includes/

Shared configuration snippets. Each file ships through the
`nginx-gateway-includes` ConfigMap. Tilt renders all `nginx/includes/*.conf`
through the shared CSP renderer; `kubernetes/production/apps/kustomization.yaml`
lists the production subset (omitting `security-headers-dev-csp.conf`). Add
new production includes to that list and render through `production-routes.sh`.

- `api-routes.conf` - The one copy of every `/api` location, including the
  `= /api` and `/api/` unknown-route `404` rejections, included once at server
  level by both configs. It also carries the server-level
  `if ($uri ~ ";") { return 400; }`, which rejects a decoded `;` anywhere in
  the path as the second layer behind the ingress path-hardening filter.
  Sharing the blocks stops them drifting, but each including server still
  supplies the server-level settings, security headers and location
  precedence.
- `api-docs-routes.conf` - The one copy of the five `/api-docs` locations. NGINX
  checks regex locations in file order, so keep its two regex locations in
  their current relative order. The static guardrail requires both configs to
  include each shared file exactly once and to declare no `/api` or
  `/api-docs` location of their own, and
  `../scripts/guardrails/verify-nginx-shared-routes.sh` runs `nginx -t` and
  the `;`, unknown-route, query and docs-header probes against both complete
  configs in disposable containers.
- `backend-headers.conf` - Standard proxy headers and identity header forwarding
  for every API route. It forwards `X-User-Id`, `X-Roles` and `X-Permissions`,
  removes `Cookie` and `Authorization` (`ext_authz` already consumed the session
  cookie at the ingress), and sends `X-Forwarded-Proto: https`, because
  `$scheme` is always `http` behind the ingress. Every `/api` location with a
  `proxy_pass` in both configs must include it; the static guardrail enforces
  this and the three directives, and
  `../scripts/guardrails/verify-nginx-backend-headers.sh` proves the stripping
  against an echo upstream in a disposable container. A backend that needs a
  browser cookie is a contract change, not a per-route override.

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
