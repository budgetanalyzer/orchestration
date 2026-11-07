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
- Validates session tokens by looking up `session:{sha256(token)}` in Redis
- Injects `X-User-Id`, `X-Roles`, `X-Permissions` headers on valid sessions
- Returns 401 for invalid/expired sessions (request rejected by Istio ingress)

**Key Benefit**: Centralized session validation with no session cache, so deleting a Redis session key rejects that session's later requests at once

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
- Applies the backend header contract in `nginx/includes/backend-headers.conf` on every API route: it forwards `X-User-Id`, `X-Roles` and `X-Permissions` from `ext_authz`, removes the `Cookie` and `Authorization` request headers because `ext_authz` already consumed the session cookie at the ingress, and sends `X-Forwarded-Proto: https` because NGINX listens on plain HTTP behind the TLS-terminating ingress. Business services never receive the reusable session cookie. The direct Session Gateway lane does not pass through NGINX and still receives the cookie
- Serves the production-smoke frontend bundle statically at `/_prod-smoke/` while the live dev route continues to proxy to Vite
- Uses the checked-in `nginx/nginx.production.k8s.conf` variant for the production cutover, where `/` and `/login` serve the built frontend bundle directly, `/_prod-smoke/` is absent, and Vite-only public routes return `404`
- Load balancing across service instances

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
- Writes session data (userId, roles, permissions, idp_sub, email, display_name) as Redis hashes (`session:{sha256(token)}`) using the dedicated `session-gateway` ACL user, which is limited to the session keyspaces and the commands Session Gateway issues (see [Redis local access](../development/local-environment.md#backend-services-spring-boot)) — no Auth0 tokens are stored
- Issues the host-only `__Host-BA_SESSION` session cookie (`Secure`, `HttpOnly`, `SameSite=Strict`, `Path=/`, no `Domain`) to browsers
- Provides browser session inspection at `GET /auth/v1/user`, state-extending
  heartbeat at `POST /auth/v1/session`, and logout through a top-level form
  `POST /logout`
- Calls permission-service during login with `POST` user sync to establish the account and initial grants, then by internal user ID on every heartbeat to refresh account status, roles, and permissions

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

Orchestration sets the callback URL sent to the IdP explicitly through
`IDP_REDIRECT_URI` in `ConfigMap/session-gateway-idp-config`; locally it is
`https://app.budgetanalyzer.localhost/login/oauth2/code/idp`. The value must
equal the IdP's registered callback URL. When it is set, Session Gateway does
not derive the callback from forwarded request headers.

Session Gateway stores a login `returnUrl` only when it is a relative path of at
most 2048 characters with no scheme, authority, backslash, whitespace or control
character; otherwise the callback redirects to `/`. The SPA's `/login` page
follows a `returnUrl` only when its own check confirms a same-origin relative
path, and otherwise lands on the role's default page.

OAuth initiation binds the saved authorization request to the browser through
the reusable `__Host-BA_OAUTH_BINDING` cookie (`Secure`, `HttpOnly`,
`SameSite=Lax`, `Path=/`, no `Domain`). Redis stores its SHA-256 hash with the
short-lived `oauth2:state:*` record, not the raw binding value. The callback
requires a valid binding and compares its hash in constant time before
consuming state. Only a callback whose Redis `DEL` removes exactly one record
may proceed. Missing, malformed, duplicate or mismatched bindings reject login
without consuming the legitimate browser's state or issuing a session.

The cookie survives callback completion so existing parallel login attempts
share a binding. Simultaneous first initiations before the browser has a cookie
can race; a rejected tab must restart login. In-flight authorization requests
created before binding was introduced also require a fresh login; no legacy
state format is accepted. This control is separate from authenticated-request
CSRF protection.

The live [OAuth binding verifier](../../scripts/smoketest/verify-oauth-browser-binding.py)
pauses an unused hosted-login callback before delivery, proves rejection from
an empty cookie jar, then resumes the same cross-site browser navigation. Its
successful login proves both browser cookie delivery and preservation of the
authorization request after the unbound attempt. See the
[script catalog](../../scripts/README.md) for prerequisites and invocation.

After the IdP callback succeeds, Session Gateway calls
`POST /permission-service/internal/v1/users/sync` with a JSON body carrying
the IdP subject, email and display name. permission-service creates or updates
the user and returns the internal `userId`, roles and permissions that seed the
new session. Identity fields travel only in the body. The whole call is bounded
by Session Gateway's `PERMISSION_SERVICE_LOGIN_TIMEOUT` (default `5s`). A
timeout, transport failure, non-2xx response such as `422` for a deactivated
account, or undecodable body fails the callback: the browser is redirected to
`/oops` and no session hash, user-session index entry or session cookie is
written. Session Gateway's
[Login User Sync](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#login-user-sync)
section owns the client contract.

Active browser sessions call `POST /auth/v1/session` under the `/auth/*` route
family. Each heartbeat first reads the current Redis session, then performs one
bounded permission-service lookup by internal `userId`. For an active account,
Session Gateway atomically replaces the roles and permissions snapshot and
extends `expires_at`, the session TTL, and its user-session index TTL only if
the session still exists, never past the
[absolute session lifetime](#absolute-session-lifetime). The response retains
its existing shape and reports the expiration actually stored. This keeps permission-service off the
`/api/*` hot path: `ext_authz` continues to authorize every API request from
Redis alone. The heartbeat does not call Auth0. Browser session inspection
lives alongside it at `GET /auth/v1/user` and reflects the refreshed Redis
snapshot on its next fetch.

Logout accepts only a same-origin top-level form `POST /logout`. Session
Gateway deletes the session, clears the public cookie, and returns `303 See
Other` to its server-constructed identity-provider logout URL. `GET` and
`HEAD` cannot heartbeat or log out and return `405` without changing the
session. The exact-Origin ingress control is a separate layer.

The internal lookup is
`GET /permission-service/internal/v1/users/{userId}/authorization` from
Session Gateway to permission-service. Istio identity and NetworkPolicy permit
that east-west call in both supported deployments, and the mesh admits Session
Gateway only with `GET` on this lookup and `POST` on the login user sync
(see [Mesh Public/Internal Boundary](security-architecture.md#mesh-publicinternal-boundary)).
It is not an NGINX route or a public browser API.

| Heartbeat result | Session behavior | Browser result |
| --- | --- | --- |
| Active account and successful lookup | Replace roles and permissions and extend the existing session atomically, up to its absolute lifetime | `200` with refreshed roles and stored expiration |
| Session at its absolute lifetime | Delete this session and clear its cookie | `401` after invalidation |
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

**Sliding TTL in ADR 007**: [ADR 007](../decisions/007-browser-only-session-gateway.md)
says a user revoked at Auth0 but not deactivated in permission-service keeps
their session "until Redis TTL expiry". That is the sliding session TTL, not a
fixed deadline from the Auth0 revocation. The heartbeat does not call Auth0,
so each successful heartbeat for an account permission-service still reports
active moves `expires_at` and the key TTL forward again, up to the absolute
session lifetime. Such a session ends one TTL after its last successful
heartbeat, at its absolute lifetime, at logout, or through permission-service
deactivation and bulk revocation.

### Absolute Session Lifetime

Heartbeats cannot renew a session past
`created_at + SESSION_MAX_LIFETIME_SECONDS`. Orchestration sets it to `28800`
(8 hours) in the checked-in `session-gateway-config` ConfigMap and in the
Tiltfile's `session-gateway-config`, which overrides that ConfigMap in local
Tilt. Session Gateway uses the same default when the setting is absent and
refuses to start if it is below `SESSION_TTL_SECONDS`. Session Gateway's
[Absolute Session Lifetime](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#absolute-session-lifetime)
section owns the exact behavior.

- Each successful heartbeat sets `expires_at` and the Redis key TTL to the
  earlier of `now + SESSION_TTL_SECONDS` and the lifetime deadline. Near the
  deadline the reported expiration stops advancing, and the key expires at the
  deadline.
- Once no lifetime remains, the heartbeat deletes the session, clears its
  cookie, and returns `401`. A missing session also returns `401`.
- `ext_authz` does not read `created_at` or the lifetime setting. It enforces
  the cap transitively by rejecting a passed `expires_at` and a missing session.
- The frontend detects a capped expiration and replaces its inactivity warning
  with a sign-in-again prompt; see `budget-analyzer-web`'s
  [Absolute session lifetime](https://github.com/budgetanalyzer/budget-analyzer-web/blob/main/docs/authentication.md#absolute-session-lifetime).
- The value matches the Auth0 tenant's 8-hour Maximum Session Lifetime. The
  Auth0 idle lifetime is 15 minutes and nothing after login reaches Auth0, so a
  user at the cap gets a real hosted-login prompt without `max_age` or
  `prompt=login`. See Session Gateway's
  [Recommended Auth0 Settings](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/auth0-settings.md).
- The cap is not account-wide revocation and does not require MFA step-up.
  Changing the value applies to existing sessions at their next heartbeat.

## Shared Session Contract

The browser session interface shared between Session Gateway and `ext_authz` is intentionally small:

- `SESSION_KEY_PREFIX` defaults to `session:` in both repos. Session Gateway writes browser sessions under `session:{sha256(token)}`, and `ext_authz` reads the same Redis namespace.
- The Redis key suffix is the lowercase hex SHA-256 of the UTF-8 `__Host-BA_SESSION` cookie value, and the `user_sessions:{userId}` index members are the same bare digests. The raw cookie token never appears in Redis key names, index members, the append-only file or logs, and neither service falls back to raw-token keys. Session Gateway owns the derivation and golden vector in its [Hashed Session Keys](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#hashed-session-keys) section.
- Orchestration seeders, load-test fixtures and verifiers derive keys with `session_key_for` and index members with `session_digest_for` from `scripts/lib/redis-cli.sh`. `./scripts/smoketest/verify-session-architecture.sh` statically checks that Session Gateway, `ext_authz` and that helper agree on the shared golden vector, and its live checks fail on any `session:*` key that is not a digest key.
- Hashing hides the reusable token, not the session count: key names remain visible metadata to Redis operators. A local cluster that holds sessions written before the hashed-key cutover must run `./scripts/ops/flush-redis.sh`; those raw-key sessions are unreachable and users sign in again.
- The browser session cookie name defaults to `__Host-BA_SESSION` in both repos. Session Gateway writes that cookie, and `ext_authz` reads it on `/api/*` requests. `./scripts/smoketest/verify-session-architecture.sh` statically checks that both defaults are that name.
- Orchestration also sets `SESSION_COOKIE_NAME=__Host-BA_SESSION` explicitly on the checked-in `ext-authz` deployment so the live cluster does not depend on the compiled default.
- The `__Host-` prefix requires `Secure`, `Path=/` and no `Domain` attribute, so the cookie is always host-only and Session Gateway has no domain override. A client must reach the ingress over HTTPS to store it; verifiers that seed a Redis session build the `Cookie` header with this name directly. Session Gateway owns the attribute details in its [Cookie Behavior](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/session-configuration.md#cookie-behavior) section.
- A local cluster upgraded from the earlier `BA_SESSION` name needs no migration: browsers still holding the old cookie get `401` and sign in again. Run `./scripts/ops/flush-redis.sh` to discard the orphaned sessions at once instead of waiting for their TTL.
- Session Gateway owns the session hash contents and expiry behavior, including
  atomic role/permission replacement on a successful heartbeat. `ext_authz`
  only assumes the hash exists, that it contains a parseable `expires_at`
  field, and that the current time is still before that timestamp; it never
  calls permission-service.

`./scripts/smoketest/verify-session-architecture.sh --static-only` is the repo-level proof for that shared contract. It compares the checked-in defaults in sibling `../ext-authz` and `../session-gateway` before any live-cluster checks run.

## Versioned Machine Error Contract

Application-produced errors on versioned machine endpoints use the shared
`ApiErrorResponse` wire shape, including Session Gateway errors and ordinary
`ext-authz` denials. Ingress-generated authorizer-failure responses are an
exception: they have an empty body, as described below. The required JSON
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
| Session-store or unexpected lookup failure on `/api/*`, or `ext-authz` unavailable, unreachable or slower than the provider timeout | Istio ingress (`ext_authz` `statusOnError`) | Fail-closed `503` with an empty body and no `content-type`; never report infrastructure failure as invalid credentials. See [Authorizer failures](#authorizer-failures) |
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
reach the downstream client. For a `401` denial the body comes from
`ext-authz`; Istio does not rewrite it. `./scripts/smoketest/verify-istio-ingress.sh` checks the rendered
Envoy filter and proves the generic JSON denial through the real local ingress
for `/api/*`, `/auth/v1/user`, and `/auth/v1/session` with normal TLS
verification.

### Authorizer failures

The `ext-authz-http` provider in `kubernetes/istio/istiod-values.yaml` sets
`failOpen: false`, `statusOnError: "503"` and a `timeout`. Without the last two,
Istio defaults to `403` and `600s`, so an authorizer outage looked like a
permission denial and a hung authorizer held each request for ten minutes.

Envoy's HTTP `ext_authz` client treats an authorizer `5xx` as an error, not as a
denial, and discards its body. The `SERVICE_UNAVAILABLE` JSON that `ext-authz`
writes for a session-store failure therefore never reaches a client. Every
authorizer failure, whether `ext-authz` answers `5xx`, has no ready endpoint,
does not answer within the timeout or drops the connection, becomes the same
ingress-generated `503` with an empty body and no `content-type`. The request
never reaches NGINX. A missing or unknown session is still a normal denial and
keeps the JSON `401` above, as long as `ext-authz` can answer. Clients must
handle a `503` without a body; the frontend reads only the status.

The timeout is about two orders of magnitude above the measured check latency;
the measurement and the failure-path results are recorded in
[security-consensus-hardening-evidence.md](../research/security-consensus-hardening-evidence.md).
Changing it requires repeating that measurement.
`./scripts/smoketest/verify-edge-contract.sh` (section "Authorization Failure")
reads the live values from the ingress Envoy config dump and proves the `401`
through the real ingress. With `--inject-failures` it also proves the empty
`503` with `ext-authz` scaled to zero, blocked by a temporary network policy so
the check hangs, and with Redis stopped; the default run changes no Kubernetes
object and skips those cases. `./scripts/guardrails/verify-static-security-manifests.sh` fails when
the provider loses `statusOnError`, the `timeout` or `failOpen: false`.

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

**Server-side session revocation**:
- Delete Redis session key → later requests for that session fail at ext_authz, which reads Redis without a cache
- No bearer-token expiry window to wait out (unlike JWTs)
- Deletion cannot undo requests already authorized or stop a concurrent login or heartbeat that fetched authorization earlier; see the heartbeat race above and [Emergency Admin Containment](security-architecture.md#emergency-admin-containment)

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

# Verify session exists in Redis; the key is the SHA-256 of the __Host-BA_SESSION cookie value
SESSION_TOKEN='<__Host-BA_SESSION cookie value>'
SESSION_KEY="session:$(printf '%s' "$SESSION_TOKEN" | sha256sum | cut -d' ' -f1)"
kubectl exec -n infrastructure redis-0 -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning HGETALL "$SESSION_KEY"

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
