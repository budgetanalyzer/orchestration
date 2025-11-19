# Nginx API Gateway for Local Development

This setup provides an nginx-based API gateway running in Docker that acts as a single entry point for both your React app and microservices during development.

## Architecture

```
Browser (localhost:8081)
    ↓
Session Gateway (BFF, port 8081) - OAuth2 authentication, session management
    ↓
Nginx Gateway (Docker, port 8080) - JWT validation, routing
    ├─→ / → React App (Vite dev server on localhost:3000)
    ├─→ /api/transactions → Budget Analyzer API (localhost:8082)
    ├─→ /api/currencies → Currency Service (localhost:8084)
    └─→ /health → Health check
```

**Key Benefits:**
- Single origin (`localhost:8081` via Session Gateway) - no CORS issues
- JWT tokens stored server-side in Redis - never exposed to browser (XSS protection)
- Resource-based routing - frontend doesn't know about microservice architecture
- Defense in depth - Session Gateway → NGINX validation → Backend authorization
- Production parity - same routing logic in dev and prod
- Easy to add/move/refactor services without frontend changes

## Service Configuration

### Upstream Services (in nginx.conf)

```nginx
upstream transaction_service {
    server host.docker.internal:8082;
}

upstream currency_service {
    server host.docker.internal:8084;
}

upstream react_app {
    server host.docker.internal:3000;
}
```

### Resource-Based Routing

The frontend sees clean resource paths:
- `GET /api/transactions` → Budget Analyzer API
- `GET /api/currencies` → Currency Service

Nginx handles the routing and path transformation to backend services.

## Usage

### 1. Start Vite dev server

```bash
# In the React app directory
npm run dev
```

**Important:** Vite must bind to `0.0.0.0` (not just `localhost`) for Docker to access it.

Check `vite.config.ts`:
```typescript
server: {
  port: 3000,
  host: '0.0.0.0',  // Required for Docker access
}
```

### 2. Start your microservices

```bash
# In each microservice directory
./gradlew bootRun
```

Services should run on:
- Budget Analyzer API: `localhost:8082`
- Currency Service: `localhost:8084`

### 3. Start the nginx gateway

```bash
docker compose up -d
```

### 4. Access your app

Open your browser to **`http://localhost:8081`** (Session Gateway, not NGINX or Vite directly)

All requests (React app, API calls, hot reload) go through Session Gateway (8081) → NGINX (8080).

### 5. Verify it's working

```bash
# Session Gateway health check (browser entry point)
curl http://localhost:8081/health

# NGINX health check (internal)
curl http://localhost:8080/health

# React app loads (through Session Gateway)
curl http://localhost:8081/

# API request requires authentication (through Session Gateway)
# Browser will be redirected to Auth0 login
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

Nginx handles routing to the correct backend service.

## Commands

```bash
# Start gateway
docker compose up -d

# View logs
docker compose logs -f nginx-gateway

# Stop gateway
docker compose down

# Restart after config changes
docker compose restart nginx-gateway

# Reload nginx config without downtime
docker exec api-gateway nginx -s reload
```

## Customization

### Adding a New Resource Route

**Scenario:** You want to add `/api/accounts` served by Budget Analyzer API.

1. Add location block in `nginx.conf`:
```nginx
location /api/accounts {
    rewrite ^/api/(.*)$ /transaction-service/$1 break;
    proxy_pass http://transaction_service;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

2. Restart nginx:
```bash
docker compose restart nginx-gateway
```

3. Frontend code (no changes needed if using consistent API client):
```typescript
apiClient.get('/accounts')
```

### Adding a New Microservice

**Scenario:** You're adding a new "Reports Service" on port 8086.

1. Add upstream in `nginx.conf`:
```nginx
upstream reports_service {
    server host.docker.internal:8086;
}
```

2. Add location blocks for its resources:
```nginx
location /api/reports {
    rewrite ^/api/(.*)$ /reports-service/$1 break;
    proxy_pass http://reports_service;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
```

3. Restart nginx:
```bash
docker compose restart nginx-gateway
```

### Moving a Resource Between Services

**Scenario:** You want to move `/transactions` from Budget Analyzer to a new Transaction Service.

**Frontend code:** No changes needed! 🎉

**Nginx config:** Just update the location block:

```nginx
location /api/transactions {
    rewrite ^/api/(.*)$ /transaction-service/$1 break;
    proxy_pass http://transaction_service;  # Changed upstream
    # ... headers stay the same
}
```

This is the power of resource-based routing!

### Changing the Gateway Port

Edit `docker compose.yml` and change `"8080:80"` to your desired port (e.g., `"9000:80"`).

Then access at `http://localhost:9000`.

### Linux Users

If you're on Linux, `host.docker.internal` doesn't work by default. Add it to `docker compose.yml`:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

(This is already configured in the provided docker compose.yml)

## Hot Module Replacement (HMR)

Nginx automatically proxies WebSocket connections for Vite's HMR. When you edit a React component, changes should appear instantly in your browser.

The `Upgrade` headers in the main location block handle this:
```nginx
location / {
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    # ...
}
```

## Troubleshooting

### React app not loading (502 Bad Gateway)

**Cause:** Nginx can't reach Vite dev server.

**Fix:**
1. Verify Vite is running: `curl http://localhost:3000`
2. Check Vite binds to `0.0.0.0` in `vite.config.ts`
3. Restart Vite dev server

### API requests fail (404 or 502)

**Cause:** Backend service not running or nginx can't reach it.

**Fix:**
1. Verify service is running: `curl http://localhost:8082/transaction-service/transactions`
2. Check nginx logs: `docker compose logs nginx-gateway`
3. Verify Docker can reach host: `docker exec api-gateway ping host.docker.internal`

### Getting 302 redirects on API calls

**Cause:** Incorrect nginx configuration (usually from using variables in `proxy_pass`).

**Fix:** Use explicit location blocks with static upstream names (as shown in this README).

### Hot reload not working

**Cause:** WebSocket connection failing.

**Fix:**
1. Check browser console for WebSocket errors
2. Verify nginx is proxying WebSocket upgrade headers
3. Make sure you're accessing via `http://localhost:8081` (Session Gateway) not `:8080` or `:3000`
4. Verify Session Gateway is proxying WebSocket connections correctly

### CORS issues

**You shouldn't have CORS issues!** Everything is same-origin (`localhost:8081` via Session Gateway).

The BFF (Backend for Frontend) pattern eliminates CORS:
- Browser sees single origin: `localhost:8081`
- Session Gateway proxies to NGINX (8080)
- NGINX proxies to backend services
- No cross-origin requests = no CORS

If you see CORS errors:
1. Verify you're accessing via `http://localhost:8081` (Session Gateway, not `:8080` or `:3000`)
2. Check that `VITE_API_BASE_URL=/api` in `.env` (relative URL, not full URL)
3. Check Session Gateway is running and configured correctly

### Services not accessible from Docker

**Cause:** Services binding to `127.0.0.1` only (not accessible from Docker).

**Fix:**
- For Spring Boot: Add `server.address=0.0.0.0` to `application.properties`
- For Vite: Set `host: '0.0.0.0'` in `vite.config.ts`
- Check firewall settings aren't blocking Docker

### Connection refused on host.docker.internal

**Linux users:** Make sure you have the `extra_hosts` configuration in `docker compose.yml`:
```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

**Mac/Windows:** Should work out of the box. If not, check Docker Desktop is running.

## Production Considerations

In production, this setup changes slightly:

1. **React app**: Serve static files (from `npm run build`) directly via nginx
   - Remove `proxy_pass http://react_app`
   - Use `root /usr/share/nginx/html` with built files
   - Add `try_files $uri /index.html` for client-side routing

2. **Microservices**: Point to actual service hosts (not `host.docker.internal`)
   - Use service discovery (Kubernetes, Consul, etc.)
   - Or configure actual service IPs/hostnames

3. **Port**: Use port 80 (HTTP) or 443 (HTTPS) instead of 8080

The routing logic stays the same - only the upstream targets change!
