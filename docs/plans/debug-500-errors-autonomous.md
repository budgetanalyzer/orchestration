# Plan: Autonomous Debugging of 500 Errors in Tilt/Kind

## Problem
500 errors when accessing https://app.budgetanalyzer.localhost, but ingress-gateway shows green in Tilt.

## Prerequisites (User does before starting)
1. Shut down Tilt: `tilt down` - verify with ps -ef | grep "tilt"
2. Ensure `.env` file exists with Auth0 credentials
3. Ensure Kind cluster is running: `kind get clusters`

---

## Phase 1: Start Tilt and Wait for Services

1. Run `tilt up` in background mode
2. Wait for resources to become ready (check with `tilt get`)
3. Monitor until ingress-gateway and session-gateway are ready

**Commands:**
```bash
cd /workspace/orchestration
tilt up &
sleep 30
tilt get
```

---

## Phase 2: Check Infrastructure Health

1. Verify all pods are running
2. Check service endpoints exist
3. Verify secrets are populated

**Commands:**
```bash
# Check all pods
kubectl get pods -A

# Check session-gateway specifically
kubectl get pods -l app=session-gateway
kubectl describe pod -l app=session-gateway

# Check service endpoints
kubectl get endpoints session-gateway

# Verify auth0 credentials secret has values
kubectl get secret auth0-credentials -o jsonpath='{.data.AUTH0_CLIENT_ID}' | base64 -d | wc -c
```

---

## Phase 3: Simulate Browser Request

Test the actual endpoint that's failing:

```bash
curl -v -k \
  -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8" \
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" \
  https://app.budgetanalyzer.localhost/
```

**Expected outcomes:**
- 302 redirect to Auth0 login = SUCCESS (session-gateway working)
- 500 error = Continue debugging
- Connection refused = Gateway/routing issue

---

## Phase 4: Trace the Request Path

### 4a. Check Envoy Gateway Logs
```bash
kubectl logs -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=ingress-gateway --tail=100
```

Look for:
- Upstream connection failures
- 503/500 response codes
- Backend not found errors

### 4b. Check Session Gateway Logs
```bash
kubectl logs deployment/session-gateway --tail=200
```

Look for:
- Auth0 configuration errors
- Redis connection failures
- Spring Boot startup exceptions
- Health check failures

### 4c. Test Session Gateway Health Directly
```bash
# Port forward to session-gateway
kubectl port-forward svc/session-gateway 8081:8081 &
sleep 2

# Test health endpoint
curl -v http://localhost:8081/actuator/health

# Kill port-forward
pkill -f "port-forward.*session-gateway"
```

### 4d. Check Redis Connectivity
```bash
kubectl get pods -l app=redis
kubectl logs deployment/redis --tail=50
```

### 4e. Check HTTPRoute Status
```bash
kubectl get httproute app-route -o yaml | grep -A 20 "status:"
```

Look for conditions showing "Accepted" and "ResolvedRefs"

---

## Phase 5: Identify and Fix Root Cause

Based on findings from Phase 4, apply fixes:

### If Auth0 credentials empty:
- Check `.env` file has values
- Recreate the secret or restart Tilt

### If session-gateway pod crashing:
- Check logs for specific error
- Fix configuration in `kubernetes/services/session-gateway/`

### If Redis not available:
- Check infrastructure namespace
- Verify Redis deployment and service

### If HTTPRoute not resolving:
- Check service name matches in `kubernetes/gateway/app-httproute.yaml`
- Verify session-gateway service exists

### If Envoy can't reach backend:
- Check ClientTrafficPolicy settings
- Verify network policies

---

## Phase 6: Verify Fix

After applying fixes:

```bash
# Re-test the endpoint
curl -v -k \
  -H "Accept: text/html" \
  -H "User-Agent: Mozilla/5.0" \
  https://app.budgetanalyzer.localhost/

# Should get 302 redirect to Auth0, not 500
```

---

## Phase 7: Cleanup

```bash
tilt down
```

---

## Deliverables

Report back with:
1. **Root cause**: What was actually causing the 500 error
2. **Fix applied**: What configuration/code changes were made
3. **Verification**: Confirmation that curl now returns expected response (302 to Auth0)
4. **Files modified**: List of any files changed

---

## Known Potential Issues

| Issue | Severity | Symptoms |
|-------|----------|----------|
| Empty Auth0 credentials | HIGH | Session-gateway crashes on startup |
| Long readiness probe (60s) | MEDIUM | Pod shows Running but not Ready |
| Redis not available | MEDIUM | Session storage fails |
| Missing TLS certificate | HIGH | Envoy can't terminate TLS |
| Wrong service name in HTTPRoute | HIGH | 500 from Envoy |
