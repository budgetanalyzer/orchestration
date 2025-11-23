# Autonomous Debug Plan: POST Timeout on Transaction Import

## Problem Statement
- `POST /api/v1/transactions/import` hangs indefinitely
- `GET` requests work fine
- Confirmed backend issue (not frontend)

## Test Data
```bash
# Use smallest test file
FILE=/workspace/transaction-service/src/test/resources/csv/truist-2022-01-01-to-2025-10-31.csv
```

---

## Phase 1: Setup Monitoring (One-time)

### 1.1 Open 4 terminal panes for log streaming
```bash
# Pane 1: Envoy Gateway
kubectl logs -f deployment/envoy-gateway -n envoy-gateway-system

# Pane 2: Session Gateway
kubectl logs -f deployment/session-gateway

# Pane 3: NGINX Gateway
kubectl logs -f deployment/nginx-gateway

# Pane 4: Transaction Service
kubectl logs -f deployment/transaction-service
```

### 1.2 Get valid session cookie
```bash
# Check Redis for active sessions
kubectl exec -it deploy/redis -n infrastructure -- redis-cli keys '*session*'

# If no sessions, get new one:
# 1. Open https://app.budgetanalyzer.localhost in browser
# 2. Login via Auth0
# 3. Copy SESSION cookie from browser DevTools
```

---

## Phase 2: Isolate the Failure Point (Bottom-up)

### 2.1 Test Transaction Service Directly (bypass all gateways)
```bash
# Get JWT from Redis session
kubectl exec -it deploy/redis -n infrastructure -- redis-cli
> HGETALL "spring:session:sessions:<session-id>"
# Look for OAuth2AuthorizedClient containing access_token

# Test direct to service
kubectl port-forward svc/transaction-service 8082:8082 &
curl -v -X POST http://localhost:8082/transaction-service/v1/transactions/import \
  -H "Authorization: Bearer <JWT>" \
  -H "X-User-Id: <user-id>" \
  -F "format=truist" \
  -F "files=@$FILE"
```
**Expected**: Should work. If fails here, problem is in transaction-service.

### 2.2 Test Through NGINX (bypass session-gateway + envoy)
```bash
kubectl port-forward svc/nginx-gateway 8080:8080 &
curl -v -X POST http://localhost:8080/api/v1/transactions/import \
  -H "Authorization: Bearer <JWT>" \
  -F "format=truist" \
  -F "files=@$FILE"
```
**Expected**: Should work. If fails here, problem is NGINX config or auth_request.

### 2.3 Test Through Session Gateway (bypass envoy only)
```bash
kubectl port-forward svc/session-gateway 8081:8081 &
curl -v -X POST http://localhost:8081/api/v1/transactions/import \
  -H "Cookie: SESSION=<session-id>" \
  -F "format=truist" \
  -F "files=@$FILE"
```
**Expected**: Should work. If fails here, problem is session-gateway proxy config.

### 2.4 Test Full Stack (through Envoy)
```bash
curl -v -k -X POST 'https://app.budgetanalyzer.localhost/api/v1/transactions/import?format=truist' \
  -H "Cookie: SESSION=<session-id>" \
  -F "files=@$FILE"
```
**Expected**: This is what's failing. If 2.3 works but 2.4 fails, problem is Envoy.

---

## Phase 3: Targeted Fixes Based on Isolation

### If 2.1 fails (Transaction Service)
- Check Spring multipart config in `application.yml`
- Look for `spring.servlet.multipart.max-file-size`
- Check for blocking operations in import code

### If 2.2 fails (NGINX)
- Check `nginx.k8s.conf` auth_request timeout
- Verify `client_body_buffer_size` is adequate
- Check `proxy_request_buffering on` is set
- Test auth_request endpoint independently:
  ```bash
  curl -v http://localhost:8088/validate -H "Authorization: Bearer <JWT>"
  ```

### If 2.3 fails (Session Gateway)
- Check `application-kubernetes.yml` for:
  - `spring.codec.max-in-memory-size` (must be >= file size)
  - `spring.cloud.gateway.httpclient.response-timeout`
- Look for WebFlux buffer size limits
- Check if OAuth2TokenRelayGlobalFilter is working

### If 2.4 fails (Envoy Gateway)
- Check `app-httproute.yaml` timeout: `timeouts.request: "60s"`
- Check for Envoy request body size limits
- Look at `client-traffic-policy.yaml` for any restrictions
- Check Envoy Gateway logs for specific errors

---

## Phase 4: Debug/Fix Cycle

For each iteration:

### 4.1 Make Configuration Change
Edit the suspected config file based on Phase 3 findings.

### 4.2 Redeploy
```bash
# For Kubernetes manifests
kubectl apply -f kubernetes/gateway/<file>.yaml

# For service configs (triggers Tilt rebuild)
tilt trigger <service-name>

# Verify pod restarted
kubectl get pods -w
```

### 4.3 Verify Configuration Applied
```bash
# For NGINX
kubectl exec deploy/nginx-gateway -- nginx -T | grep -A5 "location /api/v1/transactions/import"

# For session-gateway
kubectl exec deploy/session-gateway -- env | grep -i timeout
```

### 4.4 Test
```bash
curl -v -k -X POST 'https://app.budgetanalyzer.localhost/api/v1/transactions/import?format=truist' \
  -H "Cookie: SESSION=<session-id>" \
  -F "files=@$FILE"
```

### 4.5 Analyze Logs
- Check which service received the request
- Check which service timed out
- Note any error messages

### 4.6 Repeat or Proceed
- If still failing, go back to 4.1 with new hypothesis
- If fixed, proceed to Phase 5

---

## Phase 5: Verification

### 5.1 Test with original curl command
```bash
curl -k 'https://app.budgetanalyzer.localhost/api/v1/transactions/import?format=capital-one' \
  -H 'Cookie: SESSION=<session-id>' \
  -F 'files=@/workspace/transaction-service/src/test/resources/csv/capital-one-2000-01-01-to-2025-11-05.csv'
```

### 5.2 Test with larger file
Use the 1.6MB file to ensure timeouts are adequate:
```bash
curl -k 'https://app.budgetanalyzer.localhost/api/v1/transactions/import?format=bkk-bank' \
  -H 'Cookie: SESSION=<session-id>' \
  -F 'files=@/workspace/transaction-service/src/test/resources/csv/bkk-bank-1970-01-01-to-2025-10-31.csv'
```

### 5.3 Test from browser
Perform actual import from frontend UI to confirm end-to-end works.

---

## Likely Culprits (Priority Order)

1. **Session Gateway WebFlux buffer size** - multipart uploads may exceed default buffer
2. **Envoy Gateway request body handling** - may need explicit body size config
3. **NGINX auth_request + request buffering conflict** - auth_request may not work with unbuffered bodies
4. **Missing content-length handling** - chunked transfer encoding issues

---

## Success Criteria
- POST import completes within 10 seconds for small files
- Response contains imported transaction count
- All log streams show successful request flow
- No timeout errors in any service logs
