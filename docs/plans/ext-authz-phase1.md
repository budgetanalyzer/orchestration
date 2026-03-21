# Phase 1: ext_authz Service + Redis Session Schema

> Status: Historical plan, superseded by the current ext_authz HTTP implementation and the active [Security Hardening Plan v2](./security-hardening-v2.md). This document is retained for context and does not describe the current Phase 0 baseline.

## Context

This was Phase 1 of an earlier session hardening migration concept for replacing JWTs with opaque Redis-backed tokens and Envoy ext_authz for per-request validation.

Phase 1 builds the ext_authz gRPC service and defines the Redis session schema. It deploys to the Kind cluster via Tilt alongside existing services. **No changes to session-gateway or other service repos** — everything lives in the orchestration repo.

Since session-gateway won't write `extauthz:session:` keys until Phase 3, the service deploys in **observe mode**: it receives every request via Envoy, looks up the session in Redis, logs the result, but returns OK regardless. This validates the full pipeline (Envoy → ext_authz → Redis) without breaking existing flows.

---

## 1. New Files

```
orchestration/
  ext-authz/
    main.go              # Entry point: gRPC server + health HTTP server
    server.go            # ext_authz CheckRequest handler
    session.go           # Redis session lookup
    config.go            # Env var configuration
    Dockerfile           # Multi-stage Go build
  kubernetes/
    gateway/
      ext-authz-security-policy.yaml   # SecurityPolicy targeting api-route
    services/
      ext-authz/
        deployment.yaml
        service.yaml
  scripts/
    dev/
      seed-ext-authz-session.sh        # Dev helper to populate test sessions
```

## 2. Modified Files

- `Tiltfile` — Add ext-authz build, K8s manifests, resource deps, SecurityPolicy apply
- `tilt/common.star` — Add ext-authz to SERVICE_PORTS

---

## 3. Redis Session Schema

```
Key:     extauthz:session:{session-id}
Type:    Hash
TTL:     1800 seconds (30 min, matching Spring Session)

Fields:
  user_id       string    Internal user ID (from permission-service)
  roles         string    Comma-separated (e.g., "ROLE_USER,ROLE_ADMIN")
  permissions   string    Comma-separated (e.g., "transactions:read,transactions:write")
  created_at    string    Unix timestamp (seconds)
  expires_at    string    Unix timestamp (seconds)
```

Separate from Spring Session's `spring:session:sessions:{id}` keys. Session Gateway will dual-write to both in Phase 3. For Phase 1, the seed script populates test data.

---

## 4. ext-authz Go Service

### 4.1 `config.go` — Environment variables

| Var | Default | Description |
|-----|---------|-------------|
| `REDIS_ADDR` | `redis.infrastructure:6379` | Redis address |
| `GRPC_PORT` | `9001` | gRPC listen port |
| `HEALTH_PORT` | `8090` | HTTP health check port |
| `SESSION_KEY_PREFIX` | `extauthz:session:` | Redis key prefix |
| `SESSION_COOKIE_NAME` | `SESSION` | Cookie name to extract |
| `ENFORCE_MODE` | `false` | When false: observe-only (always allow, log decisions). When true: deny on invalid/missing session |
| `REDIS_PASSWORD` | _(empty)_ | Redis AUTH password (from `redis-credentials` secret). Empty = no auth |
| `REDIS_TLS` | `false` | Enable TLS for Redis connection. Local Kind cluster uses plaintext; production should enable |
| `LOG_LEVEL` | `info` | Log level |
| `LOG_FORMAT` | `json` | Log output format: `json` (default, for aggregators) or `text` (human-readable local dev) |

### 4.2 `session.go` — Redis lookup

- Connect via `github.com/redis/go-redis/v9` with pool size 10, read timeout 100ms
- Configure Redis AUTH password when `REDIS_PASSWORD` is set
- Configure TLS when `REDIS_TLS=true` (uses system CA pool)
- `LookupSession(ctx, sessionID)` → `HGETALL extauthz:session:{sessionID}`
- Parse into `SessionData{UserID, Roles, Permissions, ExpiresAt}`
- Check `ExpiresAt` against current time
- Return typed errors: `ErrSessionNotFound`, `ErrSessionExpired`

### 4.3 `server.go` — gRPC ext_authz handler

Implements `envoy.service.auth.v3.Authorization/Check`:

```
Check(ctx, CheckRequest):
  1. Read headers from req.Attributes.Request.Http.Headers
  2. Parse "cookie" header → extract SESSION={value}
  3. If no session cookie:
     - enforce mode: return DENIED 401
     - observe mode: log "no session cookie", return OK
  4. LookupSession(ctx, sessionID)
     - Redis error/timeout:
       - enforce: return DENIED 503 (fail-closed)
       - observe: log error, return OK
     - Not found / expired:
       - enforce: return DENIED 401
       - observe: log "session not found/expired", return OK
     - Found:
       - Return OK with response headers:
         X-User-Id: session.UserID
         X-Roles: session.Roles (comma-joined)
         X-Permissions: session.Permissions (comma-joined)
       - Include headers_to_remove: [X-User-Id, X-Roles, X-Permissions]
         (strip incoming spoofed headers before injecting real ones)

All decision points emit structured log entries via `log/slog`:
  - Level INFO: session found, headers injected (with user_id, path, method)
  - Level WARN: session not found, session expired, no cookie (with path, method, mode)
  - Level ERROR: Redis timeout/error (with error detail, path)
  - All entries include: request path, method, decision (allow/deny), mode (observe/enforce)
```

### 4.4 `main.go`

1. Load config
2. Initialize structured logger (`log/slog`) — JSON handler by default (`LOG_FORMAT=json`), text handler for local dev (`LOG_FORMAT=text`). Set as default logger so all log output is structured
3. Create Redis client, verify connection (fail fast if Redis unreachable)
4. Register `AuthorizationServer` on gRPC port
5. Start health HTTP server (goroutine): `GET /healthz` → Redis ping → 200/503
6. Start gRPC server (blocking)
7. Graceful shutdown on SIGTERM/SIGINT

### 4.5 `Dockerfile`

```dockerfile
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o ext-authz .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/ext-authz /ext-authz
USER nonroot:nonroot
EXPOSE 9001 8090
ENTRYPOINT ["/ext-authz"]
```

### 4.6 Go dependencies

- `google.golang.org/grpc`
- `github.com/envoyproxy/go-control-plane` (v0.13.1 — matches Envoy proxy version in EG v1.2.1)
- `github.com/redis/go-redis/v9`

---

## 5. Kubernetes Manifests

### 5.1 `kubernetes/services/ext-authz/deployment.yaml`

- Namespace: `default` (same as all services)
- Image: `ext-authz:latest`, imagePullPolicy: Never (Kind)
- Ports: 9001 (grpc), 8090 (health)
- Env: `REDIS_ADDR` and `REDIS_PASSWORD` from `redis-credentials` secret, `ENFORCE_MODE=false`, `REDIS_TLS=false` (Kind cluster), `LOG_FORMAT=json`
- Resources: requests 32Mi/50m, limits 64Mi/200m
- startupProbe: HTTP /healthz :8090, periodSeconds 2, failureThreshold 5
- readinessProbe: HTTP /healthz :8090, periodSeconds 5
- livenessProbe: HTTP /healthz :8090, periodSeconds 10

### 5.2 `kubernetes/services/ext-authz/service.yaml`

- ClusterIP with ports: grpc (9001), health (8090)

### 5.3 `kubernetes/gateway/ext-authz-security-policy.yaml`

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: ext-authz-policy
  namespace: default
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: api-route
  extAuth:
    failOpen: false
    grpc:
      backendRefs:
        - name: ext-authz
          port: 9001
```

Targets `api-route` only (not `app-route` — Session Gateway handles its own auth for browser traffic). `failOpen: false` — if the ext-authz pod is unreachable, Envoy denies the request. In observe mode the service always returns OK, so this only triggers on pod crash/network failure. This makes ext-authz a hard dependency from day one, which ensures operational issues surface immediately rather than being masked by NGINX's JWT fallback.

---

## 6. Tiltfile Changes

### 6.1 Add ext-authz build and deploy

Between the "GATEWAY SERVICES" and "NGINX GATEWAY" sections:

```python
# ext-authz service (Go, gRPC external authorization)
docker_build(
    'ext-authz',
    context='ext-authz',
    dockerfile='ext-authz/Dockerfile',
)

k8s_yaml([
    'kubernetes/services/ext-authz/deployment.yaml',
    'kubernetes/services/ext-authz/service.yaml',
])

k8s_resource(
    'ext-authz',
    port_forwards=[
        port_forward(9001, 9001, name='gRPC'),
        port_forward(8090, 8090, name='Health'),
    ],
    labels=['gateway'],
    resource_deps=['redis'],
)
```

### 6.2 Add SecurityPolicy to ingress-gateway resource

Add `kubernetes/gateway/ext-authz-security-policy.yaml` to the `ingress-gateway` local_resource `cmd` and `deps`.

### 6.3 Update `tilt/common.star`

Add to SERVICE_PORTS: `'ext-authz': 9001`

---

## 7. Dev Seed Script

`scripts/dev/seed-ext-authz-session.sh` — Creates test sessions in Redis:

```bash
#!/bin/bash
# Usage: ./scripts/dev/seed-ext-authz-session.sh [session-id]
REDIS_POD=$(kubectl get pods -n infrastructure -l app=redis -o jsonpath='{.items[0].metadata.name}')
SESSION_ID="${1:-test-session-001}"
EXPIRES_AT=$(date -d '+30 minutes' +%s 2>/dev/null || date -v+30M +%s)
kubectl exec -n infrastructure "$REDIS_POD" -- redis-cli HSET \
  "extauthz:session:${SESSION_ID}" \
  user_id "test-user-001" \
  roles "ROLE_USER,ROLE_ADMIN" \
  permissions "transactions:read,transactions:write,currencies:read" \
  created_at "$(date +%s)" \
  expires_at "${EXPIRES_AT}"
kubectl exec -n infrastructure "$REDIS_POD" -- redis-cli EXPIRE \
  "extauthz:session:${SESSION_ID}" 1800
echo "Seeded session: extauthz:session:${SESSION_ID}"
```

---

## 8. Coexistence with Existing JWT Flow

During Phase 1, both auth systems run simultaneously:

```
Browser → Envoy (:443)
  → ext_authz (observe mode: log + allow all)
  → NGINX (:8080)
    → auth_request /auth/validate (TVS JWT validation — still enforcing)
    → Backend service
```

The ext-authz service adds headers (`X-User-Id`, `X-Roles`, `X-Permissions`) when a valid session is found, but NGINX's `backend-headers.conf` overwrites `X-User-Id` with the JWT-extracted value. No conflict — JWT validation remains the enforcement layer until Phase 6 removes it.

---

## 9. Implementation Order

1. **Go service skeleton** — `go mod init`, dependencies, `config.go`
2. **Redis session lookup** — `session.go`
3. **gRPC handler** — `server.go` with observe/enforce modes
4. **Entry point + health** — `main.go` with health HTTP server
5. **Dockerfile** — multi-stage build
6. **K8s manifests** — deployment, service
7. **SecurityPolicy** — wire to Envoy via SecurityPolicy CRD
8. **Tiltfile** — build, deploy, wire
9. **Seed script** — dev testing helper
10. **Verify** — end-to-end test

---

## 10. Verification

### Deploy and check health
```bash
tilt up
# Wait for ext-authz pod to be ready
kubectl get pods -l app=ext-authz
curl http://localhost:8090/healthz  # Should return 200
```

### Seed a test session
```bash
./scripts/dev/seed-ext-authz-session.sh test-session-001
```

### Verify Envoy is calling ext-authz (observe mode logs)
```bash
# Make a request to the API route
curl -v https://api.budgetanalyzer.localhost/health

# Check ext-authz logs — should show "no session cookie" observation
kubectl logs deployment/ext-authz

# Make a request with a fake session cookie
curl -v --cookie "SESSION=test-session-001" https://api.budgetanalyzer.localhost/health

# Check logs — should show "session found, injecting headers"
kubectl logs deployment/ext-authz
```

### Verify existing JWT flow still works
```bash
# Login through the browser at https://app.budgetanalyzer.localhost
# Make API calls — they should work exactly as before (NGINX JWT validation)
```

### Verify header injection (when session exists)
```bash
# Add a temporary log to a backend service to print received headers
# Or check NGINX access logs for X-User-Id header presence
```
