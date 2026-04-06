# Tilt Debugging Runbook

Operational guide for debugging the Budget Analyzer Tilt/Kind local development environment.

## Quick Reference

### Essential Commands

```bash
# Start everything
tilt up

# View Tilt UI (primary debugging tool)
open http://localhost:10350

# Check all pod status
kubectl get pods -A

# View logs for a service
kubectl logs -f deployment/<service-name>

# Restart a single service
tilt trigger <service-name>

# Check Kind cluster
kind get clusters
kubectl cluster-info --context kind-kind
docker inspect kind-control-plane --format '{{.Config.Image}}'

# Validate Phase 0 security prerequisites
./scripts/dev/verify-security-prereqs.sh

# Validate Phase 1 credential isolation
./scripts/dev/verify-phase-1-credentials.sh

# Validate the Session Architecture Rethink Phase 5 contract
./scripts/dev/verify-session-architecture-phase-5.sh --static-only

# Validate Phase 2 network policy enforcement
./scripts/dev/verify-phase-2-network-policies.sh

# Validate Phase 3 ingress/egress hardening
./scripts/dev/verify-phase-3-istio-ingress.sh
```

`./scripts/dev/verify-security-prereqs.sh` proves the Phase 0 platform
baseline. `./scripts/dev/verify-session-architecture-phase-5.sh` proves the
unified Redis session namespace, the shared `session:` key prefix and
`BA_SESSION` cookie-name defaults across Session Gateway and ext-authz, the
explicit `SESSION_COOKIE_NAME=BA_SESSION` wiring in the `ext-authz`
deployment, and the full Session Gateway auth-route ownership contract for
`/auth/*`, `/oauth2/*`, `/login/oauth2/*`, and `/logout`, with no standalone
`/user` match.
`./scripts/dev/verify-phase-3-istio-ingress.sh` is the Phase 3 completion
gate. The browser login page is `/login`; the actual OAuth2 redirect starts at
`/oauth2/authorization/idp`, returns to `/login/oauth2/code/idp`, and active
browser sessions are extended by `GET /auth/v1/session`. The browser only
carries an opaque `BA_SESSION` cookie; Session Gateway keeps the session data
in Redis under `session:{id}` and the temporary OAuth2 request state under
`oauth2:state:{state}`.

### Port Mapping

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| **Application Access** |
| 443 (30443) | Istio Ingress Gateway | HTTPS | Browser entry point |
| 80 | Kind host mapping | TCP | Reserved host mapping in the Kind config |
| **Internal Services** |
| 8080 | nginx-gateway | HTTP | API routing (behind Istio ingress) |
| 8081 | session-gateway | HTTP | Browser auth/session management |
| 8082 | transaction-service | HTTP | Transaction API |
| 8084 | currency-service | HTTP | Currency API |
| 8086 | permission-service | HTTP | Roles/permissions API |
| 9002 | ext-authz | HTTP | Session validation |
| 8090 | ext-authz | HTTP | Health check |
| 3000 | budget-analyzer-web | HTTP | React dev server |
| **Infrastructure** |
| 5432 | postgresql | TCP | Database |
| 6379 | redis | TCP | Session storage |
| 5671 | rabbitmq | AMQPS | Message queue |
| 15672 | rabbitmq | HTTP | Management UI |
| **Debug Ports** |
| 5006 | transaction-service | JDWP | Remote debugging |
| 5007 | currency-service | JDWP | Remote debugging |
| 5009 | session-gateway | JDWP | Remote debugging |

### Service Health Endpoints

```bash
# All Spring Boot services
curl http://localhost:8081/actuator/health  # session-gateway
curl http://localhost:8082/actuator/health  # transaction-service
curl http://localhost:8084/actuator/health  # currency-service
curl http://localhost:8086/actuator/health  # permission-service

# NGINX Gateway
curl http://localhost:8080/health
```

---

## Debugging Tools & Access Points

### 1. Tilt UI (Primary Tool)

**URL**: http://localhost:10350

The Tilt UI shows:
- Real-time build/deploy status for all resources
- Color-coded health (green=healthy, yellow=building, red=failed)
- Live log streaming
- Resource dependency graph
- Trigger buttons for manual rebuilds

**Best Practices**:
- Keep Tilt UI open in a browser tab while developing
- Click on a resource to see its detailed logs
- Use the "Trigger Update" button to force a rebuild

### 2. kubectl Commands

```bash
# Pod status across all namespaces
kubectl get pods -A

# Detailed pod information (shows events, conditions)
kubectl describe pod <pod-name> -n <namespace>

# Follow logs for a deployment
kubectl logs -f deployment/transaction-service

# Get recent events (useful for crash loops)
kubectl get events -n default --sort-by='.lastTimestamp' | tail -20

# Check resource usage
kubectl top pods -n default
```

### 3. Direct Service Testing

Use port-forwards to bypass the gateway and test services directly:

```bash
# Test transaction-service directly
curl http://localhost:8082/actuator/health
curl http://localhost:8082/actuator/info
```

Authenticated API behavior must be tested through the ingress path, not a
direct service port-forward. The backend services trust identity headers that
`ext_authz` injects at the edge; port-forwarding to a service bypasses that
path and does not reproduce real authenticated requests.

### 4. Remote Debugging (IDE)

Each service has JDWP enabled. Configure your IDE:

| Service | Debug Port | IDE Configuration |
|---------|------------|-------------------|
| transaction-service | 5006 | Remote JVM Debug → localhost:5006 |
| currency-service | 5007 | Remote JVM Debug → localhost:5007 |
| session-gateway | 5009 | Remote JVM Debug → localhost:5009 |

---

## Common Issues Decision Tree

### Issue: Service Pod Not Starting

```
Pod not starting?
├── Check Tilt UI for build errors
│   └── Red resource = build failed → Check build logs
├── kubectl describe pod <name>
│   ├── ImagePullBackOff → Image not loaded to Kind
│   │   └── Run: tilt trigger load-images-to-kind
│   ├── CrashLoopBackOff → App crashing on startup
│   │   └── Check: kubectl logs <pod-name>
│   └── Pending → Resource constraints or missing dependencies
│       └── Check: kubectl get events
└── Check dependencies in Tilt UI
    └── Dependent service not ready → Fix upstream service first
```

### Issue: 502 Bad Gateway

```
502 Bad Gateway?
├── Which endpoint?
│   ├── app.budgetanalyzer.localhost (frontend)
│   │   └── Check nginx-gateway: kubectl logs -f deployment/nginx-gateway
│   └── app.budgetanalyzer.localhost/api/*
│       └── Check ext-authz + nginx-gateway logs
├── Is upstream service running?
│   └── kubectl get pods | grep <service-name>
└── Check NGINX upstream config
    └── kubectl logs deployment/nginx-gateway | grep upstream
```

### Issue: Authentication Failures (401/403)

```
Auth failures after login?
├── Check browser DevTools → Network tab
│   ├── Request missing BA_SESSION cookie?
│   │   └── Session Gateway not setting cookie after login
│   │       └── kubectl logs -f deployment/session-gateway
│   └── Request has BA_SESSION cookie but still 401/403?
│       ├── Probe the heartbeat directly with that cookie
│       │   └── curl -k -H "Cookie: BA_SESSION=<value>" https://app.budgetanalyzer.localhost/auth/v1/session
│       ├── /auth/v1/session returns 401?
│       │   └── Session missing/expired or IDP grant revoked
│       │       └── kubectl logs -f deployment/session-gateway
│       └── /auth/v1/session returns 200 but /api/* still fails?
│           └── ext_authz session validation or permission injection failing
│               └── kubectl logs -f deployment/ext-authz
├── Check ext-authz health
│   └── curl http://localhost:8090/healthz
├── Check Redis for session data
│   └── REDIS_OPS_USERNAME=redis-ops
│       REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
│       kubectl exec -it deploy/redis -n infrastructure -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "*"
└── Check Session Gateway Auth0 config and secret
    ├── kubectl get configmap session-gateway-idp-config -o yaml
    └── kubectl get secret auth0-credentials -o yaml
```

### Issue: Database Connection Errors

```
Database connection errors?
├── Is PostgreSQL running?
│   └── kubectl get pods -n infrastructure | grep postgres
├── Can you connect directly with TLS verification?
│   └── PGPASSWORD="$POSTGRES_BOOTSTRAP_PASSWORD" psql "host=localhost port=5432 user=postgres_admin dbname=postgres sslmode=verify-full sslrootcert=./nginx/certs/infra/infra-ca.pem"
├── Check credentials secret
│   └── kubectl get secret <service>-postgresql-credentials -o yaml
└── Check service logs for connection errors
    └── kubectl logs deployment/<service> | grep -i postgres
```

---

## Service-Specific Debugging

### Session Gateway

**Role**: Browser authentication and session management

**Common Issues**:
- OAuth2 redirect failures
- Session not persisting

**Debug Commands**:
```bash
# Check logs
kubectl logs -f deployment/session-gateway

# Health check
curl http://localhost:8081/actuator/health

# Check Redis sessions with the redis-ops ACL user
REDIS_OPS_USERNAME=redis-ops
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
kubectl exec -it deploy/redis -n infrastructure -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "session:*"
kubectl exec -it deploy/redis -n infrastructure -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "oauth2:state:*"

# Test the heartbeat with a copied browser session cookie
curl -k -H "Cookie: BA_SESSION=<value>" https://app.budgetanalyzer.localhost/auth/v1/session

# Inspect one specific session hash if you have the cookie value
kubectl exec -it deploy/redis -n infrastructure -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning HGETALL "session:<session-id-from-cookie>"

# Verify the full Session Architecture Rethink Phase 5 contract
./scripts/dev/verify-session-architecture-phase-5.sh

# Flush all Redis data (clears all sessions)
./scripts/dev/flush-redis.sh
```

**Log Patterns to Watch**:
- `OAuth2AuthorizationRequestRedirectFilter` - OAuth flow starting
- `OAuth2LoginAuthenticationFilter` - Login completing
- `Session heartbeat for sessionId=` - frontend keep-alive requests are reaching Session Gateway; the heartbeat is local Redis only and never calls Auth0
- `Session revocation requested for userId=` / `Session revocation completed for userId=, deletedSessions=` / `Session revocation failed for userId=` - bulk revocation through `DELETE /internal/v1/sessions/users/{userId}` is being driven east-west by permission-service

### RabbitMQ

**Role**: Messaging broker for `currency-service`

**Common Issues**:
- `currency-service` cannot authenticate to AMQP
- Management UI login fails
- Boot-time user or permission changes do not appear

**Debug Commands**:
```bash
# List broker users and permissions
kubectl exec -it statefulset/rabbitmq -n infrastructure -- rabbitmqctl list_users
kubectl exec -it statefulset/rabbitmq -n infrastructure -- rabbitmqctl list_permissions -p /

# Confirm the broker only exposes AMQPS on 5671 for the data plane
kubectl exec -it statefulset/rabbitmq -n infrastructure -- rabbitmqctl listeners

# Authenticate the break-glass admin user from the bootstrap secret
RABBITMQ_ADMIN_PASSWORD=$(kubectl get secret rabbitmq-bootstrap-credentials -n infrastructure -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -it statefulset/rabbitmq -n infrastructure -- rabbitmqctl authenticate_user rabbitmq-admin "$RABBITMQ_ADMIN_PASSWORD"

# Inspect the boot-time definitions secret
kubectl get secret rabbitmq-bootstrap-credentials -n infrastructure -o jsonpath='{.data.username}' | base64 -d && echo
kubectl get secret rabbitmq-bootstrap-credentials -n infrastructure -o jsonpath='{.data.definitions\.json}' | base64 -d

# Inspect the currency-service connection secret
kubectl get secret currency-service-rabbitmq-credentials -o yaml
```

RabbitMQ data-plane traffic is TLS-only on `5671`. Port `15672` stays on HTTP for
the internal management UI.

If the definitions file changed but the broker still shows the old users or
permissions, recreate the RabbitMQ PVC and restart the resource:

```bash
kubectl delete pvc rabbitmq-data-rabbitmq-0 -n infrastructure
tilt trigger rabbitmq
```

### NGINX Gateway

**Role**: HTTP routing, API-path rate limiting, load balancing

**Common Issues**:
- Upstream connection refused
- Routing misconfigurations

**Debug Commands**:
```bash
# Check logs
kubectl logs -f deployment/nginx-gateway

# Test config validity
kubectl exec deployment/nginx-gateway -- nginx -t

# Health check
curl http://localhost:8080/health
```

**Log Patterns to Watch**:
- `upstream` - Connection to backend services
- `[error]` - Any error-level messages

### Transaction/Currency Services

**Role**: Business logic APIs

**Common Issues**:
- Database connection failures
- RabbitMQ connection failures
- Authorization errors (user doesn't own resource)

**Debug Commands**:
```bash
# Check logs
kubectl logs -f deployment/transaction-service
kubectl logs -f deployment/currency-service

# Health checks
curl http://localhost:8082/actuator/health
curl http://localhost:8084/actuator/health
```

---

## Network Flow Debugging

### Complete Request Flow

```
Browser (https://app.budgetanalyzer.localhost/api/v1/transactions)
    ↓
Istio Ingress Gateway (30443) - TLS termination, auth-path rate limiting
    ↓
ext-authz (9002) - Session validation via Redis, injects X-User-Id/X-Roles/X-Permissions
    ↓ (if valid)
NGINX Gateway (8080) - API-path rate limiting, route to backend
    ↓
Transaction Service (8082) - Business logic
```

### Tracing a Request

**Step 1: Browser DevTools**
```
Open DevTools → Network tab → Find failing request
Note: Status code, response body, request headers
```

**Step 2: Check Istio Ingress Gateway**
```bash
kubectl logs -n istio-ingress -l gateway.networking.k8s.io/gateway-name=istio-ingress-gateway | grep <path>
```

**Step 3: Check ext-authz**
```bash
kubectl logs -f deployment/ext-authz
```

**Step 4: Check NGINX Gateway**
```bash
kubectl logs -f deployment/nginx-gateway | grep <path>
```

**Step 5: Check Backend Service**
```bash
kubectl logs -f deployment/transaction-service
```

### Testing Each Hop with curl

```bash
# 1. Test backend service directly (no auth)
curl http://localhost:8082/actuator/health

# 2. Test NGINX routing (no auth)
curl http://localhost:8080/health

# 3. Test full flow (requires valid session cookie)
# Use browser DevTools to copy the Cookie header, then:
curl -k -H "Cookie: BA_SESSION=<value>" https://app.budgetanalyzer.localhost/api/v1/transactions

# 4. Probe the heartbeat path with the same cookie
curl -k -H "Cookie: BA_SESSION=<value>" https://app.budgetanalyzer.localhost/auth/v1/session
```

---

## Specific Debugging: API Calls Blocked After Auth

**Symptom**: App loads, Auth0 login succeeds, React renders, but API calls to transaction-service/currency-service fail.

### Step-by-Step Diagnosis

**1. Identify the exact error**
```
Browser DevTools → Network tab → Find failing /api/* request
Check: Status code (401? 403? 502? 504?)
Check: Response body for error message
```

**2. Check if all services are healthy in Tilt UI**
```
http://localhost:10350
All resources should be green
```

**3. Verify backend services are reachable**
```bash
curl http://localhost:8082/actuator/health  # Should return UP
curl http://localhost:8084/actuator/health  # Should return UP
```

**4. Check ext-authz**
```bash
# Health
curl http://localhost:8090/healthz

# Logs - look for session validation failures
kubectl logs -f deployment/ext-authz
```

**5. Check NGINX routing**
```bash
# Logs - look for upstream errors
kubectl logs -f deployment/nginx-gateway | grep -E "(upstream|error)"
```

**7. Verify secrets are configured**
```bash
# Auth0 config + secret
kubectl get configmap session-gateway-idp-config -o yaml
kubectl get secret auth0-credentials -o jsonpath='{.data.AUTH0_CLIENT_SECRET}' | base64 -d

# PostgreSQL bootstrap admin credentials
kubectl get secret postgresql-bootstrap-credentials -n infrastructure -o jsonpath='{.data}' | base64 -d

# Service PostgreSQL credentials
kubectl get secret transaction-service-postgresql-credentials -o jsonpath='{.data}' | base64 -d
```

**8. Check Redis for session data**
```bash
REDIS_OPS_USERNAME=redis-ops
REDIS_OPS_PASSWORD=$(kubectl get secret redis-bootstrap-credentials -n infrastructure -o jsonpath='{.data.ops-password}' | base64 -d)
kubectl exec -it deploy/redis -n infrastructure -- redis-cli --tls --cacert /tls-ca/ca.crt --user "$REDIS_OPS_USERNAME" --pass "$REDIS_OPS_PASSWORD" --no-auth-warning KEYS "*"
# Should see session:* keys after login; oauth2:state:* only exists during the OAuth2 round-trip
```

### Common Causes

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| 401 Unauthorized | Session cookie missing or invalid | Check ext-authz logs, verify Redis session data |
| 403 Forbidden | Session valid but insufficient permissions | Check ext-authz logs, verify session roles/permissions |
| 502 Bad Gateway | Backend service not running | Check pod status, restart service |
| 504 Gateway Timeout | Backend service slow or hung | Check service logs, database connections |
| Network Error | Envoy/NGINX misconfiguration | Check gateway logs, verify routes |

---

## NetworkPolicy Troubleshooting (Phase 2)

Phase 2 enforces deny-by-default ingress and egress in `default` and `infrastructure` namespaces for pod-to-pod traffic. Kubelet probes and Tilt port-forwards are host-to-pod traffic, so under Calico's default `defaultEndpointToHostAction=Accept` they do not rely on these allowlists. When services break after policy changes, these are the most common causes.

### Missing DNS Egress

**Symptom**: Random service outages; services fail to resolve internal Kubernetes DNS names.

```bash
# Check if a pod can resolve DNS
kubectl exec -n default deployment/transaction-service -- nslookup postgresql.infrastructure.svc.cluster.local

# Verify the DNS egress policy exists
kubectl get networkpolicy allow-default-dns-egress -n default -o yaml
```

**Cause**: The shared DNS egress policy (`allow-default-dns-egress` in `default-allow.yaml`) is missing or was not applied. Without it, pods in `default` cannot reach `kube-dns` in `kube-system`.

**Fix**: Re-apply the network policies through Tilt (`tilt trigger network-policies`) or verify the `default-allow.yaml` manifest includes the DNS egress rule targeting `kube-system` pods with label `k8s-app=kube-dns` on TCP/UDP port 53.

### Missing Istio Ingress Selector Match

**Symptom**: All ingress returns 503; Istio ingress gateway pods cannot reach `nginx-gateway`, `ext-authz`, or `session-gateway`.

```bash
# Check the actual ingress gateway pod labels
kubectl get pods -n istio-ingress --show-labels

# Compare against what the nginx ingress allowlist expects
kubectl get networkpolicy allow-nginx-gateway-ingress-from-istio-ingress -n default -o yaml
```

**Cause**: The Istio ingress gateway pod labels no longer match the selectors used in the ingress policies. The current Gateway API controller renders `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway`; older manifests using `istio.io/gateway-name=istio-ingress-gateway` will not attach.

**Fix**: Update the ingress gateway selectors in `kubernetes/network-policies/default-allow.yaml`, `kubernetes/network-policies/istio-ingress-allow.yaml`, and `kubernetes/istio/ext-authz-policy.yaml` to match the current rendered label, then re-apply.

### Missing Istio Ingress Principal Match

**Symptom**: Login or API requests fail at ingress even though the gateway pod is healthy and the selector-based policies attach. Protected services return `403`, or ingress traffic never reaches `nginx-gateway`, `ext-authz`, or `session-gateway`.

```bash
# Check the rendered ingress gateway ServiceAccount
kubectl get deploy,sa -n istio-ingress -o yaml | rg 'istio-ingress-gateway-istio|serviceAccountName'

# Compare against ingress-facing AuthorizationPolicies
kubectl get authorizationpolicy -n default -o yaml | rg 'cluster.local/ns/istio-ingress/sa/'
```

**Cause**: The ingress-facing `AuthorizationPolicy` principals no longer match the rendered ingress gateway ServiceAccount. The current auto-provisioned identity is `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`; older manifests that allow `.../sa/istio-ingress-gateway` deny the real ingress workload.

**Fix**: Update the principals in `kubernetes/istio/authorization-policies.yaml` to `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`, then re-apply and rerun `./scripts/dev/verify-phase-3-istio-ingress.sh`.

### Missing Istiod Egress

**Symptom**: Services work initially after pod creation, but mTLS certificate rotation fails after ~24 hours. Sidecar proxies lose connectivity to istiod.

```bash
# Check sidecar-to-istiod connectivity
kubectl exec -n default deployment/ext-authz -c istio-proxy -- pilot-agent request GET /clusters | head -5

# Check istiod egress policy
kubectl get networkpolicy allow-default-istiod-egress -n default -o yaml
```

**Cause**: The istiod egress policy (`allow-default-istiod-egress`) is missing or not applied. Istio sidecars bootstrap successfully at pod creation (using cached certs), but certificates expire with default settings after ~24 hours. Without egress to `istiod.istio-system:15012`, sidecars cannot rotate certificates and mesh communication breaks.

**Fix**: Verify `default-allow.yaml` includes the istiod egress rule targeting `istio-system` pods with label `app=istiod` on TCP port 15012, then re-apply.

### Calico defaultEndpointToHostAction Changed

**Symptom**: All Kubernetes probes (startup, readiness, liveness) fail. All Tilt port-forwards break. Every pod shows as unhealthy.

```bash
# Check Calico configuration
kubectl get felixconfiguration default -o jsonpath='{.spec.defaultEndpointToHostAction}{"\n"}'
```

If that command prints nothing, the field is unset and Calico is using its default value (`Accept`).

**Cause**: Calico's `defaultEndpointToHostAction` was changed from its default value (`Accept`) to `Drop`. Kubernetes probes and Tilt port-forwards are host-to-pod traffic originating from the node IP, not from another pod. NetworkPolicy cannot allow this traffic — it depends on Calico's host endpoint handling.

**Fix**: This is a platform-level invariant, not something the policy manifests can control. Restore the Calico default:
```bash
kubectl patch felixconfiguration default --type=merge -p '{"spec":{"defaultEndpointToHostAction":"Accept"}}'
```

### Runtime Verification

Run the Phase 2 verifier to confirm policies are enforced (not just present):
```bash
./scripts/dev/verify-phase-2-network-policies.sh
```

This script uses disposable probe pods to test both positive (allowed) and negative (blocked) connectivity paths. Allowed paths pass within a bounded retry window; blocked paths must fail consistently across repeated attempts.

---

## Useful Aliases

Add to your shell profile for faster debugging:

```bash
# Tilt shortcuts
alias tup='tilt up'
alias tdown='tilt down'
alias tui='open http://localhost:10350'

# Quick log access
alias logs-session='kubectl logs -f deployment/session-gateway'
alias logs-authz='kubectl logs -f deployment/ext-authz'
alias logs-nginx='kubectl logs -f deployment/nginx-gateway'
alias logs-tx='kubectl logs -f deployment/transaction-service'
alias logs-currency='kubectl logs -f deployment/currency-service'

# Health checks
alias health-all='for p in 8081 8082 8084; do echo "Port $p:"; curl -s http://localhost:$p/actuator/health | jq -r .status; done && echo "ext-authz:"; curl -s http://localhost:8090/healthz'

# Pod status
alias pods='kubectl get pods -A'
alias pods-default='kubectl get pods -n default'
```

---

## Recovery Procedures

### Full Reset

If things are badly broken, do a full reset:

```bash
# Stop Tilt
tilt down

# Delete Kind cluster
kind delete cluster

# Recreate cluster
kind create cluster --config kind-cluster-config.yaml

# Install Calico (required for NetworkPolicy enforcement)
./scripts/dev/install-calico.sh

# Confirm the recreated cluster matches kind-cluster-config.yaml
docker inspect kind-control-plane --format '{{.Config.Image}}'

# Start fresh
tilt up

# Verify the Phase 0 platform baseline once platform resources are healthy
./scripts/dev/verify-security-prereqs.sh

# Verify the Phase 3 completion gate after ingress resources are ready
./scripts/dev/verify-phase-3-istio-ingress.sh
```

### Reset Single Service

```bash
# Delete and recreate pod
kubectl delete pod -l app=transaction-service

# Or use Tilt trigger
tilt trigger transaction-service
```

### Clear Redis Sessions

```bash
./scripts/dev/flush-redis.sh
```
