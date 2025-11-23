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
```

### Port Mapping

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| **Application Access** |
| 443 (30443) | Envoy Gateway | HTTPS | Browser entry point |
| 80 (30080) | Envoy Gateway | HTTP | Redirects to HTTPS |
| **Internal Services** |
| 8080 | nginx-gateway | HTTP | API routing (behind Envoy) |
| 8081 | session-gateway | HTTP | Browser auth/session management |
| 8082 | transaction-service | HTTP | Transaction API |
| 8084 | currency-service | HTTP | Currency API |
| 8086 | permission-service | HTTP | Permission API |
| 8088 | token-validation-service | HTTP | JWT validation |
| 3000 | budget-analyzer-web | HTTP | React dev server |
| **Infrastructure** |
| 5432 | postgresql | TCP | Database |
| 6379 | redis | TCP | Session storage |
| 5672 | rabbitmq | AMQP | Message queue |
| 15672 | rabbitmq | HTTP | Management UI |
| **Debug Ports** |
| 5006 | transaction-service | JDWP | Remote debugging |
| 5007 | currency-service | JDWP | Remote debugging |
| 5008 | permission-service | JDWP | Remote debugging |
| 5009 | session-gateway | JDWP | Remote debugging |
| 5010 | token-validation-service | JDWP | Remote debugging |

### Service Health Endpoints

```bash
# All Spring Boot services
curl http://localhost:8081/actuator/health  # session-gateway
curl http://localhost:8082/actuator/health  # transaction-service
curl http://localhost:8084/actuator/health  # currency-service
curl http://localhost:8086/actuator/health  # permission-service
curl http://localhost:8088/actuator/health  # token-validation-service

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

# Test with a JWT (if you have one)
curl -H "Authorization: Bearer <jwt>" http://localhost:8082/api/transactions
```

### 4. Remote Debugging (IDE)

Each service has JDWP enabled. Configure your IDE:

| Service | Debug Port | IDE Configuration |
|---------|------------|-------------------|
| transaction-service | 5006 | Remote JVM Debug → localhost:5006 |
| currency-service | 5007 | Remote JVM Debug → localhost:5007 |
| permission-service | 5008 | Remote JVM Debug → localhost:5008 |
| session-gateway | 5009 | Remote JVM Debug → localhost:5009 |
| token-validation-service | 5010 | Remote JVM Debug → localhost:5010 |

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
│   ├── app.budgetanalyzer.localhost
│   │   └── Check session-gateway: kubectl logs -f deployment/session-gateway
│   └── api.budgetanalyzer.localhost
│       └── Check nginx-gateway: kubectl logs -f deployment/nginx-gateway
├── Is upstream service running?
│   └── kubectl get pods | grep <service-name>
└── Check NGINX upstream config
    └── kubectl logs deployment/nginx-gateway | grep upstream
```

### Issue: Authentication Failures (401/403)

```
Auth failures after login?
├── Check browser DevTools → Network tab
│   ├── Request missing Authorization header?
│   │   └── Session Gateway not injecting JWT
│   │       └── kubectl logs -f deployment/session-gateway
│   └── Request has Authorization but still 401/403?
│       └── JWT validation failing
│           └── kubectl logs -f deployment/token-validation-service
├── Check token-validation-service health
│   └── curl http://localhost:8088/actuator/health
├── Check Redis for session data
│   └── kubectl exec -it deploy/redis -n infrastructure -- redis-cli keys "*"
└── Check Auth0 credentials secret
    └── kubectl get secret auth0-credentials -o yaml
```

### Issue: Database Connection Errors

```
Database connection errors?
├── Is PostgreSQL running?
│   └── kubectl get pods -n infrastructure | grep postgres
├── Can you connect directly?
│   └── psql -h localhost -p 5432 -U budget_analyzer -d budget_analyzer
├── Check credentials secret
│   └── kubectl get secret db-credentials -o yaml
└── Check service logs for connection errors
    └── kubectl logs deployment/<service> | grep -i postgres
```

---

## Service-Specific Debugging

### Session Gateway

**Role**: Browser authentication, session management, JWT storage in Redis

**Common Issues**:
- OAuth2 redirect failures
- Session not persisting
- JWT not being injected into proxied requests

**Debug Commands**:
```bash
# Check logs
kubectl logs -f deployment/session-gateway

# Health check
curl http://localhost:8081/actuator/health

# Check Redis sessions
kubectl exec -it deploy/redis -n infrastructure -- redis-cli
> keys *session*
> keys *token*

# Flush all Redis data (clears all sessions)
kubectl exec -it deploy/redis -n infrastructure -- redis-cli FLUSHALL
```

**Log Patterns to Watch**:
- `OAuth2AuthorizationRequestRedirectFilter` - OAuth flow starting
- `OAuth2LoginAuthenticationFilter` - Login completing
- `TokenRelayGatewayFilterFactory` - JWT injection

### Token Validation Service

**Role**: JWT signature verification for NGINX auth_request

**Common Issues**:
- JWKS fetch failures (can't reach Auth0)
- Invalid issuer/audience claims
- Expired tokens

**Debug Commands**:
```bash
# Check logs
kubectl logs -f deployment/token-validation-service

# Health check
curl http://localhost:8088/actuator/health

# Test validation endpoint directly (if exposed)
curl -H "Authorization: Bearer <jwt>" http://localhost:8088/auth/validate
```

**Log Patterns to Watch**:
- `JwtDecoder` - Token decoding
- `JwkSetUri` - JWKS fetching
- `InvalidClaimException` - Claim validation failures

### NGINX Gateway

**Role**: HTTP routing, JWT validation via auth_request, load balancing

**Common Issues**:
- Upstream connection refused
- auth_request failures
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
- `auth_request` - JWT validation calls
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
Browser (https://app.budgetanalyzer.localhost/api/transactions)
    ↓
Envoy Gateway (30443) - TLS termination
    ↓
Session Gateway (8081) - Session → JWT lookup in Redis
    ↓
NGINX Gateway (8080) - auth_request to token-validation-service
    ↓
Token Validation Service (8088) - JWT signature verification
    ↓ (if valid)
NGINX Gateway (8080) - Route to backend
    ↓
Transaction Service (8082) - Business logic
```

### Tracing a Request

**Step 1: Browser DevTools**
```
Open DevTools → Network tab → Find failing request
Note: Status code, response body, request headers
```

**Step 2: Check Envoy Gateway**
```bash
kubectl logs -f deployment/envoy-gateway -n envoy-gateway-system | grep <path>
```

**Step 3: Check Session Gateway**
```bash
kubectl logs -f deployment/session-gateway | grep -E "(proxy|forward|token)"
```

**Step 4: Check NGINX Gateway**
```bash
kubectl logs -f deployment/nginx-gateway | grep <path>
```

**Step 5: Check Token Validation**
```bash
kubectl logs -f deployment/token-validation-service
```

**Step 6: Check Backend Service**
```bash
kubectl logs -f deployment/transaction-service
```

### Testing Each Hop with curl

```bash
# 1. Test backend service directly (no auth)
curl http://localhost:8082/actuator/health

# 2. Test NGINX routing (no auth)
curl http://localhost:8080/health

# 3. Test through Envoy (HTTPS, no auth)
curl -k https://api.budgetanalyzer.localhost/health

# 4. Test full flow (requires valid session cookie)
# Use browser DevTools to copy the Cookie header, then:
curl -k -H "Cookie: SESSION=<value>" https://app.budgetanalyzer.localhost/api/transactions
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

**4. Check token-validation-service**
```bash
# Health
curl http://localhost:8088/actuator/health

# Logs - look for validation failures
kubectl logs -f deployment/token-validation-service
```

**5. Check session-gateway JWT injection**
```bash
# Logs - look for token relay
kubectl logs -f deployment/session-gateway | grep -i token
```

**6. Check NGINX auth_request flow**
```bash
# Logs - look for auth_request calls and upstream errors
kubectl logs -f deployment/nginx-gateway | grep -E "(auth|upstream|error)"
```

**7. Verify secrets are configured**
```bash
# Auth0 credentials
kubectl get secret auth0-credentials -o jsonpath='{.data}' | base64 -d

# Database credentials
kubectl get secret db-credentials -o jsonpath='{.data}' | base64 -d
```

**8. Check Redis for session data**
```bash
kubectl exec -it deploy/redis -n infrastructure -- redis-cli keys "*"
# Should see session keys after login
```

### Common Causes

| Error | Likely Cause | Fix |
|-------|--------------|-----|
| 401 Unauthorized | JWT not present or invalid | Check session-gateway logs for token injection |
| 403 Forbidden | JWT valid but claims rejected | Check token-validation-service logs, verify audience/issuer |
| 502 Bad Gateway | Backend service not running | Check pod status, restart service |
| 504 Gateway Timeout | Backend service slow or hung | Check service logs, database connections |
| Network Error | Envoy/NGINX misconfiguration | Check gateway logs, verify routes |

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
alias logs-token='kubectl logs -f deployment/token-validation-service'
alias logs-nginx='kubectl logs -f deployment/nginx-gateway'
alias logs-tx='kubectl logs -f deployment/transaction-service'
alias logs-currency='kubectl logs -f deployment/currency-service'

# Health checks
alias health-all='for p in 8081 8082 8084 8086 8088; do echo "Port $p:"; curl -s http://localhost:$p/actuator/health | jq -r .status; done'

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

# Start fresh
tilt up
```

### Reset Single Service

```bash
# Delete and recreate pod
kubectl delete pod -l app=transaction-service

# Or use Tilt trigger
tilt trigger transaction-service
```

### Reset Database

```bash
# Run database reset script
./scripts/dev/reset-databases.sh

# Or manually
kubectl delete pvc -l app=postgresql -n infrastructure
kubectl delete pod -l app=postgresql -n infrastructure
```

### Clear Redis Sessions

```bash
kubectl exec -it deploy/redis -n infrastructure -- redis-cli FLUSHALL
```
