# NGINX API Gateway for Kubernetes

NGINX handles JWT validation and routes requests to backend microservices.

## Request Flow

**All browser traffic goes through Session Gateway first.**

```
Browser (https://app.budgetanalyzer.localhost)
    │
    ▼
Envoy (:443) ─── SSL termination
    │
    ▼
Session Gateway (:8081) ─── JWT from Redis → inject header
    │
    ▼ (K8s internal: nginx-gateway:8080)
NGINX (:8080) ─── JWT validation, route to service
    │
    ├─→ /           → React App (:3000)
    ├─→ /api/transactions → Transaction Service (:8082)
    ├─→ /api/currencies   → Currency Service (:8084)
    └─→ /health     → Health check
```

**Why this works:**
- Single origin = no CORS
- JWT never in browser = XSS protection
- Resource-based routing = frontend decoupled from services
- Defense in depth = Session Gateway → NGINX → Backend

## Service Configuration

### Upstream Services (in nginx.k8s.conf)

```nginx
upstream transaction_service {
    server transaction-service:8082;
}

upstream currency_service {
    server currency-service:8084;
}

upstream react_app {
    server budget-analyzer-web:3000;
}
```

### Resource-Based Routing

The frontend sees clean resource paths:
- `GET /api/transactions` → Transaction Service
- `GET /api/currencies` → Currency Service

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

All requests go through Envoy Gateway (443) → Session Gateway (8081) → NGINX (8080).

### 3. Verify it's working

```bash
# NGINX Gateway health check
curl https://api.budgetanalyzer.localhost/health

# Session Gateway health check
curl https://app.budgetanalyzer.localhost/actuator/health

# React app loads (through Session Gateway)
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
kubectl logs -n budget-analyzer deployment/nginx-gateway

# Check NGINX config syntax
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -t

# Reload NGINX config (Tilt does this automatically)
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -s reload

# Trigger config reload via Tilt
tilt trigger nginx-gateway-config
```

## Customization

### Adding a New Resource Route

**Scenario:** You want to add `/api/accounts` served by Transaction Service.

1. Add location block in `nginx.k8s.conf`:
```nginx
location /api/accounts {
    include /etc/nginx/includes/api-protection.conf;

    rewrite ^/api/(.*)$ /v1/$1 break;
    proxy_pass http://transaction_service;
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

1. Add upstream in `nginx.k8s.conf`:
```nginx
upstream reports_service {
    server reports-service:8086;
}
```

2. Add location blocks for its resources:
```nginx
location /api/reports {
    include /etc/nginx/includes/api-protection.conf;

    rewrite ^/api/(.*)$ /v1/$1 break;
    proxy_pass http://reports_service;
    include /etc/nginx/includes/backend-headers.conf;
}
```

3. Tilt will reload automatically.

### Moving a Resource Between Services

**Scenario:** You want to move `/transactions` from one service to another.

**Frontend code:** No changes needed! 🎉

**NGINX config:** Just update the location block:

```nginx
location /api/transactions {
    include /etc/nginx/includes/api-protection.conf;

    rewrite ^/api/(.*)$ /v1/$1 break;
    proxy_pass http://new_transaction_service;  # Changed upstream
    include /etc/nginx/includes/backend-headers.conf;
}
```

This is the power of resource-based routing!

## Troubleshooting

### React app not loading (502 Bad Gateway)

**Cause:** NGINX can't reach the frontend service.

**Fix:**
1. Check if frontend pod is running: `kubectl get pods -n budget-analyzer | grep budget-analyzer-web`
2. Check frontend service exists: `kubectl get svc -n budget-analyzer budget-analyzer-web`
3. View NGINX logs for errors: `kubectl logs -n budget-analyzer deployment/nginx-gateway`

### API requests fail (404 or 502)

**Cause:** Backend service not running or NGINX can't reach it.

**Fix:**
1. Verify service is running: `kubectl get pods -n budget-analyzer | grep transaction-service`
2. Check NGINX logs: `kubectl logs -n budget-analyzer deployment/nginx-gateway`
3. Verify service DNS resolution: `kubectl exec -n budget-analyzer deployment/nginx-gateway -- nslookup transaction-service`

### Getting 401 Unauthorized

**Cause:** JWT validation failed.

**Fix:**
1. Check Token Validation Service is running: `kubectl get pods -n budget-analyzer | grep token-validation`
2. Check Token Validation logs: `kubectl logs -n budget-analyzer deployment/token-validation-service`
3. Verify JWT is being passed correctly from Session Gateway

### CORS issues

**You shouldn't have CORS issues!** Everything is same-origin (`app.budgetanalyzer.localhost` via Session Gateway).

The BFF (Backend for Frontend) pattern eliminates CORS:
- Browser sees single origin: `app.budgetanalyzer.localhost`
- Envoy routes to Session Gateway
- Session Gateway proxies to NGINX
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
2. Check ConfigMap content: `kubectl get configmap -n budget-analyzer nginx-gateway-config -o yaml`

## Configuration Files

### nginx.k8s.conf

Main NGINX configuration for Kubernetes deployment. Uses Kubernetes DNS names for service discovery.

### includes/

Shared configuration snippets:
- `api-protection.conf` - JWT validation via auth_request
- `backend-headers.conf` - Standard proxy headers

## Production Considerations

In production, this setup stays largely the same:

1. **React app**: Same - served from built static files in the container
2. **Microservices**: Same - Kubernetes DNS names work identically
3. **SSL/TLS**: Handled by Envoy Gateway (or cloud load balancer)

The routing logic stays the same - the power of Kubernetes-native architecture!
