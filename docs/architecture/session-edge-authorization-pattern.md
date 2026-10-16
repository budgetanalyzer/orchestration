# Session Edge Authorization + API Gateway Pattern

**Pattern**: Hybrid architecture combining session-based edge authorization for browser security with API Gateway for routing, and Istio ext_authz for per-request session validation.

## Overview

Budget Analyzer uses a multi-layer gateway architecture that separates browser security concerns (Session Gateway) from session validation (ext_authz) and API routing (NGINX Gateway). This provides maximum security for financial data while maintaining clean separation of concerns.

This document owns the browser request flow, route ownership, and shared
browser session contract. Exact service ports and exposure rules live in
[port-reference.md](port-reference.md). Exact `/api-docs` behavior lives in
[../../docs-aggregator/README.md](../../docs-aggregator/README.md).

## Request Flow

**Single entry point**: `app.budgetanalyzer.localhost`

```
Browser → Istio Ingress → ext_authz validates session → NGINX → Services
Auth paths: Browser → Istio Ingress → Session Gateway
```

**Key stages**:
1. **Istio Ingress**: SSL termination, per-client auth/API throttling, and ext_authz enforcement on `/api/*` paths
2. **ext_authz**: Session lookup in Redis, header injection (X-User-Id, X-Roles, X-Permissions)
3. **NGINX**: Route to appropriate backend service
4. **Session Gateway**: Auth lifecycle plus the versioned browser JSON endpoints (`/auth/v1/session`, `/auth/v1/user`, `/oauth2/*`, `/login/oauth2/*`, `/logout`)

**Routing**:
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout` → Session Gateway (auth lifecycle; browser JSON endpoints live under `/auth/v1/*`)
- `/api/*` → NGINX (ext_authz enforced, routing to backends)
- local development only: `/_prod-smoke/*` → NGINX (same-origin static frontend verification path)
- `/login`, `/*` → NGINX (frontend, no auth required)

## Component Roles

### Istio Ingress Gateway - Ingress Layer

**Purpose**: SSL termination, ext_authz enforcement, and initial routing — inside the Istio service mesh with SPIFFE identity

**Responsibilities**:
- Handles SSL/TLS termination for all traffic
- Enforces ext_authz on `/api/*` paths via `AuthorizationPolicy` with `action: CUSTOM`
- Applies four per-client local rate-limit policies to login initiation, login completion, session operations, and `/api/*` before `ext_authz`; the canonical boundaries and capacity model live in [Ingress Per-Client Rate Limiting](security-architecture.md#ingress-per-client-rate-limiting)
- Routes auth paths to Session Gateway
- Routes API and frontend paths to NGINX
- Provides Gateway API-compliant ingress
- Participates in mesh mTLS (has SPIFFE identity for AuthorizationPolicy enforcement)

**Key Benefit**: Per-request session validation at the edge, with full mesh identity for mTLS and policy enforcement

**Discovery**:
```bash
# Check Istio ingress gateway status
kubectl get gateway -n istio-ingress istio-ingress-gateway

# View Istio ingress gateway logs
kubectl logs -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway

# Verify ext_authz extension provider
kubectl get cm istio -n istio-system -o yaml | grep ext-authz-http
```

### ext_authz Service - Authorization Layer

**Purpose**: Per-request session validation via Redis lookup

**Responsibilities**:
- Authenticates to Redis with the dedicated `ext-authz` ACL user
- Validates session tokens by looking up `session:{id}` in Redis
- Injects `X-User-Id`, `X-Roles`, `X-Permissions` headers on valid sessions
- Returns 401 for invalid/expired sessions (request rejected by Istio ingress)

**Key Benefit**: Centralized session validation, instant revocation via Redis key deletion

**Repository**: https://github.com/budgetanalyzer/ext-authz owns the Go source,
Dockerfile, tests, and service-local release workflow. Orchestration owns the
Kubernetes deployment, Istio `ext_authz` provider wiring, Redis ACL wiring, and
shared session-edge contract documented here.

**Discovery**:
```bash
# Check ext_authz service status
kubectl get pods -l app=ext-authz

# View ext_authz logs
kubectl logs deployment/ext-authz

# Check ext_authz health
kubectl exec deployment/ext-authz -- wget -qO- http://localhost:8090/healthz
```

### NGINX - API Gateway Layer

**Purpose**: Resource routing and load balancing for backend services

**Responsibilities**:
- Routes requests to appropriate microservices
- Resource-based routing with path transformation
- Serves the production-smoke frontend bundle statically at `/_prod-smoke/` while the live dev route continues to proxy to Vite
- Uses the checked-in `nginx/nginx.production.k8s.conf` variant for the production cutover, where `/` and `/login` serve the built frontend bundle directly, `/_prod-smoke/` is absent, and Vite-only public routes return `404`
- Load balancing and circuit breaking

**Key Benefit**: Clean routing logic, decoupled from authentication concerns

**Discovery**:
```bash
# View NGINX configuration
cat nginx/nginx.k8s.conf

# Check NGINX status
kubectl get pods -l app=nginx-gateway

# Test NGINX configuration validity
kubectl exec deployment/nginx-gateway -- nginx -t

# View NGINX logs
kubectl logs deployment/nginx-gateway
```

**Configuration**: See [nginx/README.md](../../nginx/README.md) for detailed routing configuration and how to add new routes.

**Runtime proof**: [`./scripts/smoketest/verify-edge-browser-hardening.sh`](../../scripts/smoketest/verify-edge-browser-hardening.sh) verifies the edge and browser security contract. It checks the dev/strict CSP split on the real app paths, the production route cutover, the focused ingress per-client rate-limit contract, the frontend CSP audit, and the runtime-hardening verifier, and keeps `/api-docs` probes visible as warnings. The exact rate-limit contract and the non-secret cutover verification record stay in the canonical security section linked above. Manual browser-console validation on `/_prod-smoke/` is still required before relying on the edge and browser security proof.

### Session Gateway - Auth Layer

**Purpose**: Browser authentication and session security

**Responsibilities**:
- Manages OAuth2 flows with Auth0
- Writes session data (userId, roles, permissions, idp_sub, email, display_name) as Redis hashes (`session:{id}`) using the dedicated `session-gateway` ACL user — no Auth0 tokens are stored
- Issues HttpOnly, Secure session cookies to browsers
- Provides browser session endpoints `GET /auth/v1/session` and `GET /auth/v1/user`
- Calls permission-service during login to establish the account and initial grants, then by internal user ID on every heartbeat to refresh account status, roles, and permissions

**Key Benefit**: Maximum security for browser-based financial application (tokens never exposed to XSS)

**Discovery**:
```bash
# Check Session Gateway status
kubectl get pods -l app=session-gateway

# View Session Gateway logs
kubectl logs deployment/session-gateway

# Test Session Gateway health
kubectl exec deployment/session-gateway -- wget -qO- http://localhost:8081/actuator/health

# Check Redis connection (session storage) with the redis-ops ACL user
REDIS_OPS_USERNAME=redis-ops
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
kubectl exec -n infrastructure redis-0 -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning PING
```

`redis-ops` is a maintenance identity only. Application paths use the
service-specific Redis ACL users, not a shared password.

**Repository**: https://github.com/budgetanalyzer/session-gateway

Bare `/login` remains a frontend route. The SPA owns that page and initiates the real OAuth2 login request through `/oauth2/authorization/idp`, while the callback returns through `/login/oauth2/code/*`.

Active browser sessions call `GET /auth/v1/session` under the `/auth/*` route
family. Each heartbeat first reads the current Redis session, then performs one
bounded permission-service lookup by internal `userId`. For an active account,
Session Gateway atomically replaces the roles and permissions snapshot and
extends `expires_at`, the session TTL, and its user-session index TTL only if
the session still exists. The response retains its existing shape and reports
the expiration actually stored. This keeps permission-service off the
`/api/*` hot path: `ext_authz` continues to authorize every API request from
Redis alone. The heartbeat does not call Auth0. Browser session inspection
lives alongside it at `GET /auth/v1/user` and reflects the refreshed Redis
snapshot on its next fetch.

The internal lookup is
`GET /permission-service/internal/v1/users/{userId}/authorization` from
Session Gateway to permission-service. Istio identity and NetworkPolicy permit
that east-west call in both supported deployments. It is not an NGINX route or
a public browser API.

| Heartbeat result | Session behavior | Browser result |
| --- | --- | --- |
| Active account and successful lookup | Replace roles and permissions and extend the existing session atomically | `200` with refreshed roles and stored expiration |
| Deactivated, deleted, or missing account | Delete this session and clear its cookie | `401` after invalidation |
| Lookup unavailable, timed out, or invalid | Preserve the existing snapshot and expiration; do not extend from cached grants | `503`; keep the cookie so a later heartbeat can retry |
| Session missing or expired before the final write | Do not recreate or resurrect it; clear the cookie | `401` |
| Redis mutation failure | Do not report success; finite existing expiry remains the fallback | Temporary service failure |

**Heartbeat responsibility split**: Session Gateway has no concept of browser
activity or idle state. The frontend tracks activity (mouse, keyboard, tab
focus) and only calls the heartbeat while the user is active. Its current
default cadence is every two minutes
(`VITE_HEARTBEAT_INTERVAL_MS=120000` in `budget-analyzer-web`), so an active
browser normally observes account deactivation or changed grants at its next
heartbeat. Idle sessions receive no heartbeat and the configured session TTL
(currently 15 minutes by default) lapses naturally. Failed refreshes also
leave the existing finite expiration unchanged, so they cannot keep a session
alive.

This is a bounded ordinary-deactivation fallback, not an immediate containment
guarantee. A login or heartbeat that obtained authorization just before a
concurrent account or grant change may finish with that earlier result. The
next successful heartbeat refreshes it, or the session expires at its remaining
TTL if refresh never succeeds. Do not describe this as a strict deadline
measured from the deactivation commit. Use the separate
[emergency admin containment](security-architecture.md#emergency-admin-containment)
procedure when that race is unacceptable.

## Shared Session Contract

The browser session interface shared between Session Gateway and `ext_authz` is intentionally small:

- `SESSION_KEY_PREFIX` defaults to `session:` in both repos. Session Gateway writes browser sessions under `session:{id}`, and `ext_authz` reads the same Redis namespace.
- The browser session cookie name defaults to `BA_SESSION` in both repos. Session Gateway writes that cookie, and `ext_authz` reads it on `/api/*` requests.
- Orchestration also sets `SESSION_COOKIE_NAME=BA_SESSION` explicitly on the checked-in `ext-authz` deployment so the live cluster does not depend on the compiled default.
- Session Gateway owns the session hash contents and expiry behavior, including
  atomic role/permission replacement on a successful heartbeat. `ext_authz`
  only assumes the hash exists, that it contains a parseable `expires_at`
  field, and that the current time is still before that timestamp; it never
  calls permission-service.

`./scripts/smoketest/verify-session-architecture.sh --static-only` is the repo-level proof for that shared contract. It compares the checked-in defaults in sibling `../ext-authz` and `../session-gateway` before any live-cluster checks run.

## Versioned Machine Error Contract

Every versioned machine endpoint uses the shared `ApiErrorResponse` wire shape
regardless of which edge or application layer rejects the request. The required
fields are `type` and `message`; `code` and `fieldErrors` are optional. This is
a wire-level contract rather than a shared runtime implementation: Java
producers use `service-common`, while the Go `ext-authz` service keeps the
minimal representation locally. Changes to `ApiErrorResponse` must be
coordinated with both edge producers as described in
[service-common error handling](../../../service-common/docs/error-handling.md).

Producer ownership remains split by route:

| Request outcome | Producer | Public response |
| --- | --- | --- |
| Missing, blank, unknown, or expired session on `/api/*` | `ext-authz`, forwarded by Istio ingress | `401 application/json` with `{"type":"UNAUTHORIZED","message":"Authentication required"}` |
| Session-store or unexpected lookup failure on `/api/*` | `ext-authz`, forwarded by Istio ingress | Fail-closed `503 application/json` with `type` `SERVICE_UNAVAILABLE`; never report infrastructure failure as invalid credentials |
| Missing, invalid, expired, or invalidated session on `/auth/v1/*` | Session Gateway | `401 application/json` with `type` `UNAUTHORIZED` and message `Authentication required`; clear the cookie when required by session lifecycle rules |
| Authorization refresh, Redis, or other temporary dependency failure on `/auth/v1/*` | Session Gateway | Existing temporary-failure status with schema-valid `ApiErrorResponse` JSON |
| Missing or malformed trusted claims after edge admission | Backend service | Existing service-common JSON `401` defense-in-depth response |
| Insufficient authenticated grants | Backend service | Existing service-common JSON `403` response |

Security failures use generic messages and do not reveal whether a cookie was
unknown, expired, malformed, or associated with a particular account. Browser
navigation endpoints are outside this JSON rule: `/login`, `/oauth2/*`,
`/login/oauth2/*`, and `/logout` retain their browser-oriented redirect and
navigation behavior.

Orchestration allows only `content-type` from an `ext_authz` denial response to
reach the downstream client. The body comes from `ext-authz`; Istio does not
rewrite it. `./scripts/smoketest/verify-istio-ingress.sh` checks the rendered
Envoy filter and proves the generic JSON denial through the real local ingress
for `/api/*`, `/auth/v1/user`, and `/auth/v1/session` with normal TLS
verification.

## Why This Pattern?

### No CORS Needed

**Same-Origin Architecture**: All browser requests go through a single entry point (app.budgetanalyzer.localhost). The Istio ingress gateway routes to Session Gateway or NGINX internally. Browser sees single origin = no CORS issues!

**Traditional architecture (CORS required)**:
```
Browser → Frontend (3000) → Backend Services (8082+)  ❌ Different origins
```

**Current architecture (No CORS)**:
```
Browser → Istio Ingress (app.budgetanalyzer.localhost) → ext_authz → NGINX → Backend Services  ✅ Same origin
```

### Security Benefits - Defense in Depth

**Multiple security layers**:
1. **Istio Ingress Gateway**: SSL termination for all traffic
2. **Session Gateway**: Prevents token exposure to browser (XSS protection)
3. **ext_authz**: Validates every API request via Redis session lookup
4. **Backend Services**: Data-level authorization (user owns resource)

**Tokens never reach browser**:
- Traditional approach: Store JWT in localStorage/sessionStorage → Vulnerable to XSS attacks
- Session-based approach: Store session data in Redis, issue secure session cookie → XSS cannot steal tokens
- Financial application: Protecting access tokens is critical for user financial data

**Instant session revocation**:
- Delete Redis session key → next request immediately fails at ext_authz
- No token expiry window to wait out (unlike JWTs)

**For comprehensive security architecture**: See [security-architecture.md](security-architecture.md)

## Port And Exposure Reference

Exact service ports, exposure levels, and caller allowlists live in
[port-reference.md](port-reference.md).

## When to Use This Pattern

**Best for**:
- Browser-based applications requiring maximum security (financial, healthcare, etc.)
- Applications where token exposure to XSS is unacceptable
- Microservices architectures needing centralized authentication
- Systems requiring same-origin policy (no CORS complexity)

**Not ideal for**:
- Mobile apps (native apps can securely store tokens in keychain)
- Public APIs (no browser session to manage)
- Simple single-service applications (overkill)

## Adding New Services to the Gateway

**When adding a new microservice**:

1. **Add Kubernetes manifests**: `kubernetes/services/{service-name}/`
2. **Register with Tilt**: Add to `Tiltfile` using `spring_boot_service()` pattern. If the service needs non-secret runtime config, place it at `kubernetes/services/{service-name}/configmap.yaml`; the helper loads that manifest automatically when present.
3. **Add NGINX routes**: Update `nginx/nginx.k8s.conf` with new location blocks using variable-based `proxy_pass` (e.g., `set $backend "http://service.default.svc.cluster.local:port"; proxy_pass $backend;`)

**See [nginx/README.md](../../nginx/README.md) for detailed instructions.**

## Troubleshooting

**Common Issues**:

**502 Bad Gateway**:
```bash
# Check if service is running
kubectl get pods

# Check NGINX can reach service
kubectl exec deployment/nginx-gateway -- curl http://{service-name}:8082/actuator/health

# Check NGINX configuration
kubectl exec deployment/nginx-gateway -- nginx -t
```

**401 Unauthorized**:
```bash
# Check ext_authz service
kubectl logs deployment/ext-authz

REDIS_OPS_USERNAME=redis-ops
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)

# Verify session exists in Redis
kubectl exec -n infrastructure redis-0 -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning HGETALL "session:{session-id}"

# Check session storage
kubectl exec -n infrastructure redis-0 -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "session:*"
```

**Session not persisting**:
```bash
# Check Redis is running
kubectl get pods -n infrastructure -l app=redis

# Check Session Gateway Redis connection
kubectl logs deployment/session-gateway | grep -i redis

# Verify session cookie is set
curl -v https://app.budgetanalyzer.localhost (check Set-Cookie header)
```

**For comprehensive troubleshooting**: See [nginx/README.md](../../nginx/README.md) troubleshooting section.

## References

- **NGINX Configuration**: [nginx/README.md](../../nginx/README.md)
- **Security Architecture**: [security-architecture.md](security-architecture.md)
- **Session Gateway Repository**: https://github.com/budgetanalyzer/session-gateway
