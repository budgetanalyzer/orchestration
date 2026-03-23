# NGINX API Gateway for Kubernetes

NGINX handles backend routing and API-path rate limiting for backend microservices. Authentication and auth-sensitive path throttling are handled at the Istio ingress gateway before requests reach NGINX.

## Request Flow

**Single browser entry point:** `https://app.budgetanalyzer.localhost`

```
Browser (https://app.budgetanalyzer.localhost)
    │
    ▼
Istio Ingress Gateway (:443) ─── SSL termination + ext_authz session validation
    │
    ├─→ /auth/*, /oauth2/*, /login/oauth2/*, /logout, /user → Session Gateway (:8081)
    │
    ├─→ /api/* → NGINX (:8080)
    │
    ├─→ /login → NGINX (:8080) → React App (:3000)
    │
    ▼ (K8s internal: nginx-gateway:8080)
NGINX (:8080) ─── API-path rate limiting, route to service
    │
    ├─→ /           → React App (:3000)
    ├─→ /api/v1/transactions → Transaction Service (:8082)
    ├─→ /api/v1/currencies   → Currency Service (:8084)
    └─→ /health     → Health check
```

**Why this works:**
- Single origin = no CORS
- Opaque session tokens = no JWTs exposed to browser (XSS protection)
- Resource-based routing = frontend decoupled from services
- ext_authz at Istio ingress layer validates sessions before reaching NGINX

## Rate-Limiting Split

- Istio ingress rate limits auth-sensitive paths: `/auth/*`, `/oauth2/*`, `/login/oauth2/*`, `/logout`, and `/user`
- NGINX rate limits backend-facing API paths after ingress validation and routing

Bare `/login` is a frontend route. It is served through NGINX and initiates OAuth2 with `/oauth2/authorization/idp`; it is not a direct Session Gateway route.

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

NGINX handles the routing and path transformation to backend services.

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
OAuth2 and auth lifecycle requests go through Istio Ingress Gateway (443) → Session Gateway (8081).
The frontend login page at `/login` goes through Istio Ingress Gateway (443) → NGINX (8080).

### 3. Verify it's working

```bash
# NGINX Gateway health check (via Istio ingress)
curl https://app.budgetanalyzer.localhost/health

# React app loads
curl https://app.budgetanalyzer.localhost/
```

## Frontend Configuration

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

## Commands

```bash
# View NGINX logs
kubectl logs deployment/nginx-gateway

# Check NGINX config syntax
kubectl exec deployment/nginx-gateway -- nginx -t

# Reload NGINX config (Tilt does this automatically)
kubectl exec deployment/nginx-gateway -- nginx -s reload

# Trigger config reload via Tilt
tilt trigger nginx-gateway-config
```

The Kubernetes access log includes `remote_addr`, `X-Forwarded-For`, and `X-Real-IP` so the Phase 3 verifier can prove forwarded-header preservation through Istio ingress for both frontend and API requests.

## Customization

### Adding a New Resource Route

**Scenario:** You want to add `/api/accounts` served by Transaction Service.

1. Add location block in `nginx.k8s.conf`:
```nginx
location /api/accounts {
    set $transaction_backend "http://transaction-service.default.svc.cluster.local:8082";
    limit_req zone=per_ip burst=20 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

2. Tilt will automatically reload the ConfigMap and NGINX.

3. Frontend code (no changes needed if using consistent API client):
```typescript
apiClient.get('/accounts')
```

### Adding a New Microservice

**Scenario:** You're adding a new "Reports Service" on port 8086.

1. Add location blocks for its resources in `nginx.k8s.conf`:
```nginx
location /api/reports {
    set $reports_backend "http://reports-service.default.svc.cluster.local:8086";
    limit_req zone=per_ip burst=20 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /reports-service/v1/$1 break;
    proxy_pass $reports_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

3. Tilt will reload automatically.

### Moving a Resource Between Services

**Scenario:** You want to move `/transactions` from one service to another.

**Frontend code:** No changes needed! 🎉

**NGINX config:** Just update the location block:

```nginx
location /api/v1/transactions {
    set $transaction_backend "http://new-transaction-service.default.svc.cluster.local:8082";
    limit_req zone=per_ip burst=20 nodelay;
    limit_req_status 429;
    rewrite ^/api/v1/(.*)$ /new-transaction-service/v1/$1 break;
    proxy_pass $transaction_backend;
    include /etc/nginx/includes/backend-headers.conf;
}
```

This is the power of resource-based routing!

## Troubleshooting

### React app not loading (502 Bad Gateway)

**Cause:** NGINX can't reach the frontend service.

**Fix:**
1. Check if frontend pod is running: `kubectl get pods | grep budget-analyzer-web`
2. Check frontend service exists: `kubectl get svc budget-analyzer-web`
3. View NGINX logs for errors: `kubectl logs deployment/nginx-gateway`

### API requests fail (404 or 502)

**Cause:** Backend service not running or NGINX can't reach it.

**Fix:**
1. Verify service is running: `kubectl get pods | grep transaction-service`
2. Check NGINX logs: `kubectl logs deployment/nginx-gateway`
3. Verify service DNS resolution: `kubectl exec deployment/nginx-gateway -- nslookup transaction-service`

### Getting 401 Unauthorized

**Cause:** ext_authz session validation failed.

**Fix:**
1. Check ext-authz is running: `kubectl get pods | grep ext-authz`
2. Check ext-authz logs: `kubectl logs deployment/ext-authz`
3. Verify session cookie is being sent and Redis has session data

### CORS issues

**You shouldn't have CORS issues!** Everything is same-origin (`app.budgetanalyzer.localhost` via Istio ingress gateway).

The BFF (Backend for Frontend) pattern eliminates CORS:
- Browser sees single origin: `app.budgetanalyzer.localhost`
- Istio ingress gateway routes to NGINX or Session Gateway
- NGINX routes to backend services
- No cross-origin requests = no CORS

If you see CORS errors:
1. Verify you're accessing via `https://app.budgetanalyzer.localhost` (not direct service ports)
2. Check that `VITE_API_BASE_URL=/api` in `.env` (relative URL, not full URL)
3. Check Session Gateway is running and configured correctly

### ConfigMap not updating

**Cause:** Tilt didn't detect the config change.

**Fix:**
1. Manually trigger reload: `tilt trigger nginx-gateway-config`
2. Check ConfigMap content: `kubectl get configmap nginx-gateway-config -o yaml`

## Configuration Files

### nginx.k8s.conf

Main NGINX configuration for Kubernetes deployment. Uses Kubernetes DNS names for service discovery.

### includes/

Shared configuration snippets:
- `backend-headers.conf` - Standard proxy headers and identity header forwarding

## Production Considerations

In production, this setup stays largely the same:

1. **React app**: Same - served from built static files in the container
2. **Microservices**: Same - Kubernetes DNS names work identically
3. **SSL/TLS**: Handled by Istio ingress gateway (or cloud load balancer)

The routing logic stays the same - the power of Kubernetes-native architecture!
