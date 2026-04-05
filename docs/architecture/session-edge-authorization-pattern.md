# Session Edge Authorization + API Gateway Pattern

**Pattern**: Hybrid architecture combining session-based edge authorization for browser security with API Gateway for routing, and Istio ext_authz for per-request session validation.

## Overview

Budget Analyzer uses a multi-layer gateway architecture that separates browser security concerns (Session Gateway) from session validation (ext_authz) and API routing (NGINX Gateway). This provides maximum security for financial data while maintaining clean separation of concerns.

## Request Flow

**Single entry point**: `app.budgetanalyzer.localhost`

```
Browser → Istio Ingress (:443) → ext_authz validates session → NGINX (:8080) → Services
Auth paths: Browser → Istio Ingress (:443) → Session Gateway (:8081)
```

**Key stages**:
1. **Istio Ingress**: SSL termination, ext_authz enforcement on `/api/*` paths, and auth-path throttling
2. **ext_authz**: Session lookup in Redis, header injection (X-User-Id, X-Roles, X-Permissions)
3. **NGINX**: Route to appropriate backend service
4. **Session Gateway**: Auth lifecycle plus the versioned browser JSON endpoints (`/auth/v1/session`, `/auth/v1/user`, `/oauth2/*`, `/login/oauth2/*`, `/logout`)

**Routing**:
- `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout` → Session Gateway (auth lifecycle; browser JSON endpoints live under `/auth/v1/*`)
- `/api/*` → NGINX (ext_authz enforced, routing to backends)
- local development only: `/_prod-smoke/*` → NGINX (same-origin static frontend verification path)
- `/login`, `/*` → NGINX (frontend, no auth required)

## Component Roles

### Istio Ingress Gateway (Port 443, HTTPS) - Ingress Layer

**Purpose**: SSL termination, ext_authz enforcement, and initial routing — inside the Istio service mesh with SPIFFE identity

**Responsibilities**:
- Handles SSL/TLS termination for all traffic
- Enforces ext_authz on `/api/*` paths via `AuthorizationPolicy` with `action: CUSTOM`
- Applies local rate limiting to auth-sensitive browser entry points (`/login`, `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`)
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

### ext_authz Service (Port 9002 HTTP, Port 8090 Health) - Authorization Layer

**Purpose**: Per-request session validation via Redis lookup

**Responsibilities**:
- Authenticates to Redis with the dedicated `ext-authz` ACL user
- Validates session tokens by looking up `session:{id}` in Redis
- Injects `X-User-Id`, `X-Roles`, `X-Permissions` headers on valid sessions
- Returns 401 for invalid/expired sessions (request rejected by Istio ingress)

**Key Benefit**: Centralized session validation, instant revocation via Redis key deletion

**Discovery**:
```bash
# Check ext_authz service status
kubectl get pods -l app=ext-authz

# View ext_authz logs
kubectl logs deployment/ext-authz

# Check ext_authz health
kubectl exec deployment/ext-authz -- wget -qO- http://localhost:8090/healthz
```

### NGINX (Port 8080, HTTP) - API Gateway Layer

**Purpose**: Routing and backend/API rate limiting for backend services

**Responsibilities**:
- Routes requests to appropriate microservices
- Resource-based routing with path transformation
- Rate limits backend-facing API paths after ingress validation
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

**Runtime proof**: [`./scripts/dev/verify-phase-6-edge-browser-hardening.sh`](/workspace/orchestration/scripts/dev/verify-phase-6-edge-browser-hardening.sh) is the Phase 6 completion gate for the edge/browser contract. It checks the dev/strict CSP split on the real app paths, the production route cutover, direct auth-edge throttling coverage for `/login`, `/auth/*`, `/logout`, and `/login/oauth2/*`, reruns the existing Session 3, Session 7, and Phase 5 verifiers, and keeps `/api-docs` probes visible as warnings instead of completion blockers. Manual browser-console validation on `/_prod-smoke/` is still required before Phase 6 can be called complete.

### Session Gateway (Port 8081, HTTP) - Auth Layer

**Purpose**: Browser authentication and session security

**Responsibilities**:
- Manages OAuth2 flows with Auth0
- Stores Auth0 tokens in Redis session hashes using the dedicated `session-gateway` ACL user
- Writes session data (userId, roles, permissions) as Redis hashes (`session:{id}`)
- Issues HttpOnly, Secure session cookies to browsers
- Provides browser session endpoints `GET /auth/v1/session` and `GET /auth/v1/user`
- Proactive token refresh when the IDP token is within the 10-minute refresh threshold (includes permission re-fetch and session hash update)
- Calls permission-service to enrich session with roles/permissions (email and displayName passed as query params)
- Provides token exchange endpoint for native/M2M clients (`POST /auth/token/exchange`)

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
kubectl exec -n infrastructure deployment/redis -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning PING
```

`redis-ops` is a maintenance identity only. Application paths use the
service-specific Redis ACL users, not a shared password.

**Repository**: https://github.com/budgetanalyzer/session-gateway

Bare `/login` remains a frontend route. The SPA owns that page and initiates the real OAuth2 login request through `/oauth2/authorization/idp`, while the callback returns through `/login/oauth2/code/*`.

Active browser sessions also call `GET /auth/v1/session` under the `/auth/*` route family. That heartbeat keeps the sliding session window alive and gives Session Gateway a place to validate or refresh the upstream IDP grant without putting Session Gateway on the API hot path. Browser session inspection lives alongside it at `GET /auth/v1/user`.

**Heartbeat responsibility split**: Session Gateway extends the session unconditionally on every heartbeat call — it has no concept of user activity or idle state. The frontend is responsible for tracking user activity (mouse, keyboard, tab focus) and only calling the heartbeat while the user is active. The current frontend default cadence is every 3 minutes. When the user is idle, the frontend stops calling, and the session TTL (default 15 min) lapses naturally via Redis key expiration.

## Shared Session Contract

The browser session interface shared between Session Gateway and `ext_authz` is intentionally small:

- `SESSION_KEY_PREFIX` defaults to `session:` in both repos. Session Gateway writes browser sessions under `session:{id}`, and `ext_authz` reads the same Redis namespace.
- The browser session cookie name defaults to `BA_SESSION` in both repos. Session Gateway writes that cookie, and `ext_authz` reads it on `/api/*` requests.
- Orchestration also sets `SESSION_COOKIE_NAME=BA_SESSION` explicitly on the checked-in `ext-authz` deployment so the live cluster does not depend on the compiled default.
- Session Gateway owns the session hash contents and expiry behavior. `ext_authz` only assumes the hash exists, that it contains a parseable `expires_at` field, and that the current time is still before that timestamp.

`./scripts/dev/verify-session-architecture-phase-5.sh --static-only` is the repo-level proof for that shared contract. It compares the checked-in defaults in `orchestration/ext-authz` and the sibling `session-gateway` repo before any live-cluster checks run.

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

## Port Summary

| Port | Service | Purpose | Access |
|------|---------|---------|--------|
| 443 | Istio Ingress Gateway | SSL termination, ext_authz enforcement, auth-path throttling (HTTPS) | Public (browsers via app.budgetanalyzer.localhost) |
| 9002 | ext_authz | Session validation (HTTP) | Internal (Istio ingress only) |
| 8090 | ext_authz | Health endpoint (HTTP) | Internal (probes only) |
| 8080 | NGINX Gateway | Routing, backend/API rate limiting | Internal (Istio ingress only) |
| 8081 | Session Gateway | Browser authentication, session management | Internal (Istio ingress only) |
| 8086 | Permission Service | Internal roles/permissions (network isolation) | Internal (Session Gateway only) |
| 8082 | Transaction Service | Business logic | Internal (NGINX only) |
| 8084 | Currency Service | Business logic | Internal (NGINX only) |
| 3000 | React Dev Server | Frontend (dev only) | Internal (NGINX only) |

**Discovery**:
```bash
# List all services and ports
kubectl get svc

# Check specific service port mappings
kubectl describe svc nginx-gateway
```

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
kubectl exec -n infrastructure deployment/redis -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning HGETALL "session:{session-id}"

# Check session storage
kubectl exec -n infrastructure deployment/redis -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "session:*"
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
