# Debug Plan: Fix Local HTTPS Inside Container

## Overview
Debug and fix local HTTPS setup entirely within the devcontainer environment using curl to simulate browser requests. **Critical**: Must test from inside Docker containers to validate actual network paths, and use browser-like curl options (cookies, redirects) to verify OAuth2 flow works.

## Known Issues from Previous Debugging

1. **Session Gateway binds to localhost only** - Must add `server.address: 0.0.0.0` to `/workspace/session-gateway/src/main/resources/application.yml`
2. **React frontend must be running** - Session Gateway routes `/` to `api.budgetanalyzer.localhost` which proxies to port 3000
3. **service-common must be built first** - Run `publishToMavenLocal` before starting Session Gateway

---

## Phase 1: Environment Setup

### 1. Build shared dependencies
```bash
cd /workspace/service-common && ./gradlew publishToMavenLocal
```

### 2. Start Session Gateway service
**IMPORTANT**: Must listen on all interfaces for Docker to reach it.
```bash
cd /workspace/session-gateway && ./gradlew bootRun --args='--server.address=0.0.0.0'
```
Run in background. Or permanently fix by adding to application.yml:
```yaml
server:
  port: 8081
  address: 0.0.0.0
```

### 3. Start React frontend
```bash
cd /workspace/budget-analyzer-web && npm run dev
```
Run in background. Must be accessible on port 3000.

### 4. Verify services are running locally
```bash
curl -s http://localhost:8081/actuator/health | jq .status
curl -s http://localhost:3000/ | head -20
```

---

## Phase 2: SSL Trust Configuration

### 5. Add mkcert CA to system trust store
```bash
sudo cp /home/vscode/.local/share/mkcert/rootCA.pem /usr/local/share/ca-certificates/mkcert-ca.crt
sudo update-ca-certificates
```

### 6. Verify DNS resolution
```bash
getent hosts app.budgetanalyzer.localhost
getent hosts api.budgetanalyzer.localhost
```
Both should resolve to `::1` or `127.0.0.1`.

---

## Phase 3: Test from INSIDE Docker Containers

**This is critical** - NGINX runs in Docker and connects via `host.docker.internal`, not localhost.

### 7. Test NGINX can reach Session Gateway
```bash
docker exec api-gateway wget -qO- --timeout=5 http://host.docker.internal:8081/actuator/health
```
**Expected**: Health JSON with `"status":"UP"`

### 8. Test NGINX can reach React app
```bash
docker exec api-gateway wget -qO- --timeout=5 http://host.docker.internal:3000/ | head -20
```
**Expected**: React HTML content

### 9. Check what host.docker.internal resolves to
```bash
docker exec api-gateway getent hosts host.docker.internal
```
Note the IP - Session Gateway must be listening on this interface.

---

## Phase 4: Test HTTPS with Browser-Like Behavior

### 10. Test NGINX SSL termination directly
```bash
curl -v https://api.budgetanalyzer.localhost/health
```
**Expected**: `healthy` with HTTP 200, SSL certificate verified OK

### 11. Test Session Gateway health through NGINX (with cookies)
```bash
curl -v -L \
  -c /tmp/cookies.txt \
  -b /tmp/cookies.txt \
  https://app.budgetanalyzer.localhost/actuator/health
```
**Expected**: Health JSON with HTTP 200, SESSION cookie set

### 12. Verify SESSION cookie properties
```bash
cat /tmp/cookies.txt | grep SESSION
```
**Expected**: Cookie with `Secure`, `HttpOnly`, `SameSite=Lax`

### 13. Test frontend loads through full chain
```bash
curl -v -L \
  -c /tmp/cookies.txt \
  -b /tmp/cookies.txt \
  https://app.budgetanalyzer.localhost/
```
**Expected**: HTTP 200 with React HTML content (or 302 redirect to Auth0 if auth required)

---

## Phase 5: Test OAuth2 Flow

### 14. Test OAuth2 authorization initiation
```bash
curl -v -L \
  -c /tmp/cookies.txt \
  -b /tmp/cookies.txt \
  --max-redirs 3 \
  https://app.budgetanalyzer.localhost/oauth2/authorization/auth0
```
**Expected**: 302 redirect chain ending at Auth0's `/authorize` endpoint

### 15. Test API endpoint returns 401 (not 502)
```bash
curl -v -L \
  -c /tmp/cookies.txt \
  -b /tmp/cookies.txt \
  https://app.budgetanalyzer.localhost/api/v1/transactions
```
**Expected**: HTTP 401 Unauthorized (proves the request reached the backend, not a gateway error)

---

## Phase 6: Diagnose Issues

### 16. Check NGINX logs for errors
```bash
docker logs api-gateway --tail 100 2>&1 | grep -E "(error|502|refused)"
```

### 17. Check Session Gateway logs
Look at the background process output for:
- SSL handshake errors when connecting to `api.budgetanalyzer.localhost`
- Route matching issues
- Upstream connection failures

### 18. Test Session Gateway can reach NGINX (api subdomain)
The Session Gateway proxies to `https://api.budgetanalyzer.localhost`. Verify this works:
```bash
# From devcontainer
curl -v https://api.budgetanalyzer.localhost/health
```

---

## Phase 7: Common Fixes

### If docker exec tests fail (Connection refused to host.docker.internal)
- Session Gateway not listening on 0.0.0.0
- Fix: Add `server.address: 0.0.0.0` to application.yml

### If 502 Bad Gateway errors
- Upstream service not running (Session Gateway or React)
- Wrong IP resolution for host.docker.internal
- Fix: Start the missing service, verify with docker exec tests

### If SSL certificate errors in Session Gateway logs
- Session Gateway can't verify NGINX's certificate
- Fix: Configure Session Gateway to trust the mkcert CA or disable SSL verification for local dev

### If OAuth2 redirect fails
- Incorrect redirect URI configuration
- Session Gateway not preserving cookies properly
- Fix: Check Auth0 application settings match the redirect URI

---

## Success Criteria

**ALL of these must pass before declaring the setup fixed:**

| Test Command | Expected Result |
|-------------|----------------|
| `docker exec api-gateway wget -qO- http://host.docker.internal:8081/actuator/health` | HTTP 200, `"status":"UP"` |
| `docker exec api-gateway wget -qO- http://host.docker.internal:3000/` | HTTP 200, React HTML |
| `curl https://api.budgetanalyzer.localhost/health` | HTTP 200, `healthy` |
| `curl -L -c /tmp/c.txt https://app.budgetanalyzer.localhost/actuator/health` | HTTP 200, health JSON |
| `curl -L -c /tmp/c.txt https://app.budgetanalyzer.localhost/` | HTTP 200 (React) or 302 (Auth0) |
| `curl -L -c /tmp/c.txt https://app.budgetanalyzer.localhost/api/v1/transactions` | HTTP 401 (not 502) |
| `grep SESSION /tmp/c.txt` | Cookie exists with Secure flag |

---

## Architecture Reference

```
Browser Request Flow:

  curl/Browser
       │
       ▼
  NGINX (443)  ─────────────────┐
  app.budgetanalyzer.localhost  │
       │                        │
       ▼                        │
  Session Gateway (8081)        │
  - OAuth2 session mgmt         │
  - Cookie ↔ JWT translation    │
       │                        │
       ▼                        │
  NGINX (443)  ◄────────────────┘
  api.budgetanalyzer.localhost
       │
       ├──► React App (3000)     [for / frontend routes]
       ├──► Transaction Svc (8082) [for /api/v1/transactions]
       └──► Currency Svc (8084)  [for /api/v1/currencies]
```

**Key insight**: NGINX container uses `host.docker.internal` to reach services running on the devcontainer host. All services must bind to `0.0.0.0` (not `127.0.0.1`) to be reachable.
