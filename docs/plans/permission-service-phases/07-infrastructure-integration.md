# Permission Service - Phase 8: Infrastructure Integration

> **Full Archive**: [permission-service-implementation-plan-ARCHIVE.md](../permission-service-implementation-plan-ARCHIVE.md)

## Phase 8: Infrastructure Integration

### 8.1 Database Initialization

Add to `/workspace/orchestration/postgres-init/01-init-databases.sql`:

```sql
-- Permission Service database
CREATE DATABASE permission;
GRANT ALL PRIVILEGES ON DATABASE permission TO budget_analyzer;
```

### 8.2 Docker Compose

Add to `/workspace/orchestration/docker-compose.yml`:

```yaml
  permission-service:
    build:
      context: ../permission-service
      dockerfile: Dockerfile
    container_name: permission-service
    ports:
      - "8086:8086"
    environment:
      - SPRING_DATASOURCE_URL=jdbc:postgresql://shared-postgres:5432/permission
      - SPRING_DATASOURCE_USERNAME=budget_analyzer
      - SPRING_DATASOURCE_PASSWORD=budget_analyzer
      - SPRING_REDIS_HOST=redis
      - AUTH0_ISSUER_URI=${AUTH0_ISSUER_URI}
      - AUTH0_AUDIENCE=${AUTH0_AUDIENCE}
    depends_on:
      shared-postgres:
        condition: service_healthy
      redis:
        condition: service_started
    networks:
      - gateway-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8086/permission-service/actuator/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 8.3 NGINX Configuration

Add to `/workspace/orchestration/nginx/nginx.dev.conf`:

**Upstream definition** (add with other upstreams):

```nginx
upstream permission_service {
    server host.docker.internal:8086;
}
```

**Route definitions** (add in server block):

```nginx
# Permission Service Routes

# User permissions (including /me/permissions)
location /api/v1/users {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Role management (admin only - stricter rate limiting)
location /api/v1/roles {
    include includes/admin-api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Delegations
location /api/v1/delegations {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Resource permissions
location /api/v1/resource-permissions {
    include includes/api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}

# Audit logs (admin/auditor only - stricter rate limiting)
location /api/v1/audit {
    include includes/admin-api-protection.conf;
    rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
    proxy_pass http://permission_service;
    include includes/backend-headers.conf;
}
```
