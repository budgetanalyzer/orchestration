# BFF + API Gateway Hybrid Pattern

**Pattern**: Hybrid architecture combining Backend-for-Frontend (BFF) for browser security with API Gateway for routing and validation.

## Overview

Budget Analyzer uses a dual-gateway architecture that separates browser security concerns (Session Gateway) from API routing and validation (NGINX Gateway). This provides maximum security for financial data while maintaining clean separation of concerns.

## Request Flow

**All browser traffic goes through Session Gateway.** Think of it as a maxiservice.

```
Browser → Envoy (:443) → Session Gateway (:8081) → Envoy → NGINX (:8080) → Services
```

**Key stages**:
1. **Envoy**: SSL termination for all traffic
2. **Session Gateway**: JWT lookup from Redis, inject into header
3. **NGINX**: JWT validation, route to service

**Two entry points**:
- `app.budgetanalyzer.localhost` → Envoy → Session Gateway (browser auth)
- `api.budgetanalyzer.localhost` → Envoy → NGINX (API gateway)

## Component Roles

### Envoy Gateway (Port 443, HTTPS) - Ingress Layer

**Purpose**: SSL termination and initial routing

**Responsibilities**:
- Handles SSL/TLS termination for both app. and api. subdomains
- Routes app.budgetanalyzer.localhost to Session Gateway
- Routes api.budgetanalyzer.localhost to NGINX
- Provides Gateway API-compliant ingress

**Key Benefit**: Modern, Kubernetes-native ingress with SSL termination

**Discovery**:
```bash
# Check Envoy Gateway status
kubectl get gateway -n budget-analyzer

# View Envoy Gateway logs
kubectl logs -n envoy-gateway-system deployment/envoy-gateway

# Inspect Gateway configuration
kubectl get gateway budget-analyzer-gateway -n budget-analyzer -o yaml
```

### NGINX (Port 8080, HTTP) - API Gateway Layer

**Purpose**: JWT validation, routing, and request processing

**Responsibilities**:
- Validates JWTs via Token Validation Service (auth_request directive)
- Routes requests to appropriate microservices
- Resource-based routing with path transformation
- Rate limiting per user/IP
- Load balancing and circuit breaking

**Key Benefit**: Centralized JWT validation and routing logic

**Discovery**:
```bash
# View NGINX configuration
cat nginx/nginx.k8s.conf

# Check NGINX status
kubectl get pods -n budget-analyzer -l app=nginx-gateway

# Test NGINX configuration validity
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -t

# View NGINX logs
kubectl logs -n budget-analyzer deployment/nginx-gateway
```

**Configuration**: See [nginx/README.md](../../nginx/README.md) for detailed routing configuration and how to add new routes.

### Session Gateway (Port 8081, HTTP) - BFF Layer

**Purpose**: Browser authentication and session security

**Responsibilities**:
- Manages OAuth2 flows with Auth0
- Stores JWTs in Redis (server-side, never exposed to browser)
- Issues HttpOnly, Secure session cookies to browsers
- Proactive token refresh before expiration
- Proxies authenticated requests to NGINX with JWT injection

**Key Benefit**: Maximum security for browser-based financial application (JWTs never exposed to XSS)

**Discovery**:
```bash
# Check Session Gateway status
kubectl get pods -n budget-analyzer -l app=session-gateway

# View Session Gateway logs
kubectl logs -n budget-analyzer deployment/session-gateway

# Test Session Gateway health
curl -v https://app.budgetanalyzer.localhost/actuator/health

# Check Redis connection (session storage)
kubectl exec -n infrastructure deployment/redis -- redis-cli PING
```

**Repository**: https://github.com/budgetanalyzer/session-gateway

### Token Validation Service (Port 8088)

**Purpose**: JWT signature verification for NGINX

**Responsibilities**:
- Verifies JWT signatures using Auth0 JWKS
- Validates issuer, audience, and expiration claims
- Called by NGINX via auth_request for every protected endpoint

**Key Benefit**: Centralized JWT validation logic, defense in depth

**Discovery**:
```bash
# Check Token Validation Service status
kubectl get pods -n budget-analyzer -l app=token-validation-service

# View Token Validation Service logs
kubectl logs -n budget-analyzer deployment/token-validation-service

# Test validation endpoint (requires valid JWT)
curl -H "Authorization: Bearer <JWT>" http://localhost:8088/validate
```

**Repository**: https://github.com/budgetanalyzer/token-validation-service

## Why This Pattern?

### No CORS Needed

**Same-Origin Architecture**: All browser requests go through Session Gateway (app.budgetanalyzer.localhost), which proxies to NGINX, which routes to backends. Browser sees single origin = no CORS issues!

**Traditional architecture (CORS required)**:
```
Browser → Frontend (3000) → Backend Services (8082+)  ❌ Different origins
```

**Current architecture (No CORS)**:
```
Browser → Session Gateway (app.budgetanalyzer.localhost) → NGINX (api.budgetanalyzer.localhost) → Backend Services  ✅ Same origin
```

### Security Benefits - Defense in Depth

**Multiple security layers**:
1. **Envoy Gateway**: SSL termination for all traffic
2. **Session Gateway**: Prevents JWT exposure to browser (XSS protection)
3. **NGINX auth_request**: Validates every API request before routing
4. **Token Validation Service**: Cryptographic JWT verification
5. **Backend Services**: Data-level authorization (user owns resource)

**JWT never reaches browser**:
- Traditional approach: Store JWT in localStorage/sessionStorage → Vulnerable to XSS attacks
- BFF approach: Store JWT in Redis, issue secure session cookie → XSS cannot steal JWT
- Financial application: Protecting access tokens is critical for user financial data

**For comprehensive security architecture**: See [security-architecture.md](security-architecture.md)

## Port Summary

| Port | Service | Purpose | Access |
|------|---------|---------|--------|
| 443 | Envoy Gateway | SSL termination, ingress (HTTPS) | Public (browsers via app. and api.budgetanalyzer.localhost) |
| 8080 | NGINX Gateway | JWT validation, routing | Internal (Envoy only) |
| 8081 | Session Gateway | Browser authentication, session management | Internal (Envoy only) |
| 8088 | Token Validation | JWT signature verification | Internal (NGINX only) |
| 8082 | Transaction Service | Business logic | Internal (NGINX only) |
| 8084 | Currency Service | Business logic | Internal (NGINX only) |
| 3000 | React Dev Server | Frontend (dev only) | Internal (NGINX only) |

**Discovery**:
```bash
# List all services and ports
kubectl get svc -n budget-analyzer

# Check specific service port mappings
kubectl describe svc nginx-gateway -n budget-analyzer
```

## When to Use This Pattern

**Best for**:
- Browser-based applications requiring maximum security (financial, healthcare, etc.)
- Applications where JWT exposure to XSS is unacceptable
- Microservices architectures needing centralized authentication
- Systems requiring same-origin policy (no CORS complexity)

**Not ideal for**:
- Mobile apps (native apps can securely store tokens in keychain)
- Public APIs (no browser session to manage)
- Simple single-service applications (overkill)

## Adding New Services to the Gateway

**When adding a new microservice**:

1. **Add Kubernetes manifests**: `kubernetes/services/{service-name}/`
2. **Register with Tilt**: Add to `Tiltfile` using `spring_boot_service()` pattern
3. **Add NGINX routes**: Update `nginx/nginx.k8s.conf` with new location blocks
4. **Add upstream**: Define service endpoint in NGINX upstreams section

**See [nginx/README.md](../../nginx/README.md) for detailed instructions.**

## Troubleshooting

**Common Issues**:

**502 Bad Gateway**:
```bash
# Check if service is running
kubectl get pods -n budget-analyzer

# Check NGINX can reach service
kubectl exec -n budget-analyzer deployment/nginx-gateway -- curl http://{service-name}:8082/actuator/health

# Check NGINX configuration
kubectl exec -n budget-analyzer deployment/nginx-gateway -- nginx -t
```

**401 Unauthorized**:
```bash
# Check Token Validation Service
kubectl logs -n budget-analyzer deployment/token-validation-service

# Verify JWT is being passed
kubectl logs -n budget-analyzer deployment/nginx-gateway | grep Authorization

# Check Session Gateway session storage
kubectl exec -n infrastructure deployment/redis -- redis-cli KEYS "spring:session:*"
```

**Session not persisting**:
```bash
# Check Redis is running
kubectl get pods -n infrastructure -l app=redis

# Check Session Gateway Redis connection
kubectl logs -n budget-analyzer deployment/session-gateway | grep -i redis

# Verify session cookie is set
curl -v https://app.budgetanalyzer.localhost (check Set-Cookie header)
```

**For comprehensive troubleshooting**: See [nginx/README.md](../../nginx/README.md) troubleshooting section.

## References

- **NGINX Configuration**: [nginx/README.md](../../nginx/README.md)
- **Security Architecture**: [security-architecture.md](security-architecture.md)
- **Session Gateway Repository**: https://github.com/budgetanalyzer/session-gateway
- **Token Validation Repository**: https://github.com/budgetanalyzer/token-validation-service
