# Port Reference

**Purpose**: Canonical reference for all service ports in the Budget Analyzer system.

## Port Summary

| Port | Service | Protocol | Purpose | Access Level |
|------|---------|----------|---------|--------------|
| 443 | Envoy Gateway | HTTPS | SSL termination, ext_authz enforcement, ingress | Public (browsers) |
| 9002 | ext_authz | HTTP | Per-request session validation | Internal (Envoy only) |
| 8090 | ext_authz | HTTP | Health endpoint | Internal (probes only) |
| 8080 | NGINX Gateway | HTTP | Routing, rate limiting | Internal (Envoy only) |
| 8081 | Session Gateway | HTTP | Browser authentication, session management | Internal (Envoy only) |
| 8086 | Permission Service | HTTP | Internal roles/permissions resolution | Internal (Session Gateway only) |
| 8082 | Transaction Service | HTTP | Transaction management API | Internal (NGINX only) |
| 8084 | Currency Service | HTTP | Currency and exchange rate API | Internal (NGINX only) |
| 3000 | React Dev Server | HTTP | Frontend development (dev only) | Internal (NGINX only) |
| 5432 | PostgreSQL | TCP | Relational database | Internal (services only) |
| 6379 | Redis | TCP | Session storage (Spring Session + ext_authz schema), caching | Internal (services only) |
| 5672 | RabbitMQ | AMQP | Message broker | Internal (services only) |
| 15672 | RabbitMQ Management | HTTP | RabbitMQ admin UI | Internal (dev access) |

## Port Ranges by Layer

### Public Layer (Browser Accessible)
- **443** - Envoy Gateway (HTTPS)
  - `app.budgetanalyzer.localhost` → routes to Session Gateway (auth paths) or NGINX (API/frontend paths)
  - ext_authz enforced on `/api/*` paths

### Gateway Layer (Internal)
- **9002** - ext_authz HTTP (session validation, header injection)
- **8090** - ext_authz health (HTTP health probes)
- **8080** - NGINX Gateway (API routing, rate limiting)
- **8081** - Session Gateway (BFF, session management)

### Business Services Layer (Internal)
- **8082** - Transaction Service
- **8084** - Currency Service

### Frontend Layer (Development)
- **3000** - React Dev Server (Tilt live reload)

### Infrastructure Layer (Internal)
- **5432** - PostgreSQL (database)
- **6379** - Redis (session storage + ext_authz schema)
- **5672** - RabbitMQ (messaging)
- **15672** - RabbitMQ Management UI

## Service Discovery Commands

**List all Kubernetes services and ports**:
```bash
kubectl get svc
```

**Check specific service port mapping**:
```bash
kubectl describe svc nginx-gateway
kubectl describe svc session-gateway
```

**List all infrastructure services**:
```bash
kubectl get svc -n infrastructure
```

**View pod port bindings**:
```bash
kubectl get pods -o wide
```

**Test service connectivity**:
```bash
# From inside a pod
kubectl exec deployment/nginx-gateway -- curl http://transaction-service:8082/actuator/health
```

## Port Assignment Convention

**Pattern**: Ports are assigned based on service layer and creation order.

**Gateway Layer (8080-8090, 9002)**:
- 8080: NGINX Gateway (API routing)
- 8081: Session Gateway (BFF)
- 9002: ext_authz HTTP (session validation)
- 8090: ext_authz health

**Business Services (8082+, even numbers)**:
- 8082: Transaction Service
- 8084: Currency Service
- 8086: Permission Service

**Frontend Development (3000-3999)**:
- 3000: React Dev Server (standard React port)

**Infrastructure (Standard ports)**:
- 5432: PostgreSQL (standard)
- 6379: Redis (standard)
- 5672: RabbitMQ AMQP (standard)
- 15672: RabbitMQ Management (standard)

## Adding a New Service

**When adding a new microservice**, assign the next available port in the appropriate range:

1. **Determine layer**:
   - Gateway service? Use 8080-8089 range
   - Business service? Use next even number starting from 8082
   - Frontend? Use 3000+ range

2. **Check for conflicts**:
```bash
# List all currently used ports
kubectl get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[*].port}{"\n"}{end}'
```

3. **Update this document** with the new port assignment

4. **Update Kubernetes manifests** with the chosen port

5. **Add to Tiltfile** if using Tilt for development

## Port Conflicts and Debugging

**Check if port is already in use locally**:
```bash
# macOS/Linux
lsof -i :<port>

# Linux alternative
netstat -tulpn | grep <port>
```

**Check Kubernetes service conflicts**:
```bash
kubectl get svc --all-namespaces | grep <port>
```

**Common conflicts**:
- Port 3000: Often used by other React apps (stop other dev servers)
- Port 8080: Common default for many services (ensure NGINX has exclusive use)
- Port 5432: If running local PostgreSQL (use Kubernetes version instead)

## Security Considerations

**Network Policies**:
- Public ports (443) are accessible from outside the cluster
- Internal ports (8080+) are cluster-internal only by service type
- Phase 0 provides a `NetworkPolicy`-capable CNI and runtime verifier, but the actual application/infrastructure allowlist policies land in a later hardening phase

**Check network policies**:
```bash
kubectl get networkpolicies
kubectl get networkpolicies -n infrastructure
```

**Verify service is not exposed publicly**:
```bash
# Should only show Envoy Gateway on 443
kubectl get svc --field-selector spec.type=LoadBalancer
```

## Related Documentation

- **BFF + API Gateway Pattern**: [bff-api-gateway-pattern.md](bff-api-gateway-pattern.md)
- **NGINX Configuration**: [../../nginx/README.md](../../nginx/README.md)
- **Security Architecture**: [security-architecture.md](security-architecture.md)
