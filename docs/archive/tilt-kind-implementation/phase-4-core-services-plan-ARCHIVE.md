# Phase 4: Core Services Implementation Plan

This document provides a step-by-step guide for completing Phase 4 of the Tilt and Kind deployment. The goal is to deploy all core application services including nginx-gateway, token-validation-service, session-gateway, and the backend microservices (transaction, currency, permission).

---

## Prerequisites

- Phase 1 completed (Kind cluster running with cert-manager and Envoy Gateway)
- Phase 2 completed (Gateway API configuration with HTTPRoutes)
- Phase 3 completed (Infrastructure services: PostgreSQL, Redis, RabbitMQ)
- All service repositories cloned in `/workspace/`:
  - `/workspace/session-gateway`
  - `/workspace/token-validation-service`
  - `/workspace/transaction-service`
  - `/workspace/currency-service`
  - `/workspace/permission-service`
  - `/workspace/budget-analyzer-web`

---

## Overview

Phase 4 deploys the core services with these key architectural changes from Docker Compose:

1. **No SSL in NGINX**: Envoy Gateway handles TLS termination, so NGINX operates as HTTP-only (port 8080)
2. **K8s Service Discovery**: Services use Kubernetes DNS names instead of `host.docker.internal`
3. **Internal Communication**: Session Gateway proxies to `http://nginx-gateway:8080` (internal HTTP)
4. **ConfigMaps**: NGINX configuration stored in ConfigMaps for easy updates

---

## Step 1: Create Services Namespace Structure

**Objective:** To organize Kubernetes manifests for all core services in a consistent structure.

### 1.1. Create Directory Structure

**Action:** Create the directory structure for all service manifests.

```bash
mkdir -p kubernetes/services/nginx-gateway
mkdir -p kubernetes/services/session-gateway
mkdir -p kubernetes/services/token-validation-service
mkdir -p kubernetes/services/transaction-service
mkdir -p kubernetes/services/currency-service
mkdir -p kubernetes/services/permission-service
```

### 1.2. Verify Directory Structure

**Action:** Confirm the directories were created.

```bash
ls -la kubernetes/services/
```

**Expected Output:** Six directories, one for each service.

---

## Step 2: Create Unified NGINX Configuration

**Objective:** To create an environment-agnostic NGINX configuration that works in both Kind and GKE. This configuration removes all SSL handling (delegated to Envoy Gateway) and uses Kubernetes service names.

### 2.1. Create NGINX Configuration File

**Action:** Create the Kubernetes-compatible NGINX configuration file.

```bash
cat <<'EOF' > nginx/nginx.k8s.conf
events {
    worker_connections 1024;
}

http {
    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log debug;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;

    # WebSocket upgrade handling
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # ========================================================================
    # RATE LIMITING
    # ========================================================================

    # Regular endpoints: 100 requests per minute per IP
    limit_req_zone $binary_remote_addr zone=per_ip:10m rate=100r/m;

    # Admin endpoints: 20 requests per minute per IP (more restrictive)
    limit_req_zone $binary_remote_addr zone=per_ip_admin:10m rate=20r/m;

    # ========================================================================
    # UPSTREAM SERVICES (Kubernetes DNS names)
    # ========================================================================

    upstream transaction_service {
        server transaction-service:8082;
    }

    upstream currency_service {
        server currency-service:8084;
    }

    upstream permission_service {
        server permission-service:8086;
    }

    # React dev server (in dev environment, in prod this serves static files)
    upstream react_app {
        server budget-analyzer-web:3000;
    }

    # Session Gateway (BFF for browser authentication)
    upstream session_gateway {
        server session-gateway:8081;
    }

    # Token Validation Service
    upstream token_validation_service {
        server token-validation-service:8088;
    }

    # ========================================================================
    # API GATEWAY SERVER BLOCK (HTTP only - TLS handled by Envoy Gateway)
    # ========================================================================
    server {
        listen 8080;
        server_name api.budgetanalyzer.localhost;

        # Prevent absolute redirects and port issues
        absolute_redirect off;
        port_in_redirect off;

        # Default proxy timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # ========================================================================
        # SECURITY HEADERS
        # ========================================================================

        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:; connect-src 'self' https://dev-gcz1r8453xzz0317.us.auth0.com https://app.budgetanalyzer.localhost; frame-ancestors 'self';" always;

        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }

        # Favicon - return 204 No Content
        location = /favicon.ico {
            access_log off;
            log_not_found off;
            return 204;
        }

        # ========================================================================
        # JWT VALIDATION
        # ========================================================================

        location = /auth/validate {
            internal;

            access_log /var/log/nginx/auth_validate.log combined;

            # Use K8s service name for Token Validation Service
            proxy_pass http://token_validation_service/auth/validate;

            proxy_pass_request_body off;
            proxy_set_header Content-Length "0";
            proxy_set_header Authorization $http_authorization;
            proxy_set_header X-Original-URI $request_uri;

            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }

        # ========================================================================
        # ERROR HANDLING
        # ========================================================================

        error_page 401 = @error_401;

        location @error_401 {
            default_type application/json;
            return 401 '{"error":"Unauthorized","message":"Authentication required. Please log in."}';
        }

        # ========================================================================
        # API ROUTES
        # ========================================================================

        # API Documentation
        location = /api/docs {
            alias /usr/share/nginx/html/docs/index.html;
            default_type text/html;
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
        }

        # OpenAPI spec files
        location ~ ^/api/docs/(openapi\.(json|yaml))$ {
            alias /usr/share/nginx/html/docs/$1;
            add_header Content-Disposition 'attachment; filename="$1"';
            add_header Access-Control-Allow-Origin "*";
            add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
        }

        # Transaction Service OpenAPI spec
        location /api/transaction-service/v3/api-docs {
            proxy_pass http://transaction_service/transaction-service/v3/api-docs;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Transaction import (larger uploads)
        location /api/v1/transactions/import {
            include includes/api-protection.conf;
            client_max_body_size 10M;
            rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
            proxy_pass http://transaction_service;
            include includes/backend-headers.conf;
            proxy_connect_timeout 60s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # General transactions
        location /api/v1/transactions {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
            proxy_pass http://transaction_service;
            include includes/backend-headers.conf;
        }

        # Admin transactions
        location /api/v1/admin/transactions {
            include includes/admin-api-protection.conf;
            rewrite ^/api/v1/(.*)$ /transaction-service/v1/$1 break;
            proxy_pass http://transaction_service;
            include includes/backend-headers.conf;
        }

        # Currency Service OpenAPI spec
        location /api/currency-service/v3/api-docs {
            proxy_pass http://currency_service/currency-service/v3/api-docs;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Currency endpoints
        location /api/v1/currencies {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
            proxy_pass http://currency_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/exchange-rates {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
            proxy_pass http://currency_service;
            include includes/backend-headers.conf;
        }

        # Admin currency endpoints
        location /api/v1/admin/currencies {
            include includes/admin-api-protection.conf;
            rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
            proxy_pass http://currency_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/admin/exchange-rates {
            include includes/admin-api-protection.conf;
            rewrite ^/api/v1/(.*)$ /currency-service/v1/$1 break;
            proxy_pass http://currency_service;
            include includes/backend-headers.conf;
        }

        # Permission Service OpenAPI spec
        location /api/permission-service/v3/api-docs {
            proxy_pass http://permission_service/permission-service/v3/api-docs;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # Permission Service routes
        location /api/v1/users {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
            proxy_pass http://permission_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/roles {
            include includes/admin-api-protection.conf;
            rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
            proxy_pass http://permission_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/delegations {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
            proxy_pass http://permission_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/resource-permissions {
            include includes/api-protection.conf;
            rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
            proxy_pass http://permission_service;
            include includes/backend-headers.conf;
        }

        location /api/v1/audit {
            include includes/admin-api-protection.conf;
            rewrite ^/api/v1/(.*)$ /permission-service/v1/$1 break;
            proxy_pass http://permission_service;
            include includes/backend-headers.conf;
        }

        # React app (frontend)
        location / {
            proxy_pass http://react_app;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host $host;
            proxy_cache_bypass $http_upgrade;
        }
    }
}
EOF
```

### 2.2. Key Differences from Development Configuration

**Explanation:** The Kubernetes configuration differs from `nginx.dev.conf` in these important ways:

| Aspect | Docker Compose (`nginx.dev.conf`) | Kubernetes (`nginx.k8s.conf`) |
|--------|-----------------------------------|-------------------------------|
| TLS | Handles SSL (port 443) | No SSL (port 8080) - Envoy Gateway handles TLS |
| Service Discovery | `host.docker.internal:PORT` | K8s DNS: `service-name:PORT` |
| Server Name | `*.budgetanalyzer.localhosthost` | `*.budgetanalyzer.localhost` |
| Token Validation | `http://host.docker.internal:8088` | `http://token_validation_service/...` |
| HTTP Redirect | Port 80 redirects to 443 | No redirect (Envoy handles) |

---

## Step 3: Deploy NGINX Gateway

**Objective:** To deploy the NGINX gateway as a Kubernetes Deployment with ConfigMaps for configuration and includes files.

### 3.1. Create NGINX ConfigMap

**Action:** Create a ConfigMap containing the main NGINX configuration.

```bash
cat <<'EOF' > kubernetes/services/nginx-gateway/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-gateway-config
  namespace: default
  labels:
    app: nginx-gateway
data:
  nginx.conf: |
    # Content will be mounted from nginx/nginx.k8s.conf
    # This is a placeholder - actual config will be added via kustomize or helm
EOF

# Create ConfigMap directly from the nginx.k8s.conf file
kubectl create configmap nginx-gateway-config \
  --from-file=nginx.conf=nginx/nginx.k8s.conf \
  --dry-run=client -o yaml > kubernetes/services/nginx-gateway/configmap.yaml
```

### 3.2. Create NGINX Includes ConfigMap

**Action:** Create a ConfigMap for the NGINX include files.

```bash
kubectl create configmap nginx-gateway-includes \
  --from-file=nginx/includes/ \
  --dry-run=client -o yaml > kubernetes/services/nginx-gateway/includes-configmap.yaml
```

### 3.3. Create NGINX Deployment

**Action:** Create the Deployment manifest for nginx-gateway.

```bash
cat <<'EOF' > kubernetes/services/nginx-gateway/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-gateway
  namespace: default
  labels:
    app: nginx-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-gateway
  template:
    metadata:
      labels:
        app: nginx-gateway
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 8080
          name: http
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
          readOnly: true
        - name: nginx-includes
          mountPath: /etc/nginx/includes
          readOnly: true
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-gateway-config
      - name: nginx-includes
        configMap:
          name: nginx-gateway-includes
EOF
```

### 3.4. Create NGINX Service

**Action:** Create the Service manifest for nginx-gateway.

```bash
cat <<'EOF' > kubernetes/services/nginx-gateway/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-gateway
  namespace: default
  labels:
    app: nginx-gateway
spec:
  type: ClusterIP
  selector:
    app: nginx-gateway
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
EOF
```

### 3.5. Apply NGINX Gateway Manifests

**Action:** Apply all NGINX gateway manifests to the cluster.

```bash
# Create ConfigMaps from actual files
kubectl create configmap nginx-gateway-config \
  --from-file=nginx.conf=nginx/nginx.k8s.conf \
  -n default --save-config

kubectl create configmap nginx-gateway-includes \
  --from-file=nginx/includes/ \
  -n default --save-config

# Apply Deployment and Service
kubectl apply -f kubernetes/services/nginx-gateway/deployment.yaml
kubectl apply -f kubernetes/services/nginx-gateway/service.yaml
```

### 3.6. Verify NGINX Gateway Deployment

**Action:** Confirm the nginx-gateway is running.

```bash
# Check pod status
kubectl get pods -l app=nginx-gateway

# Wait for pod to be ready
kubectl wait --for=condition=ready pod \
  -l app=nginx-gateway \
  --timeout=120s

# Check service
kubectl get svc nginx-gateway
```

**Expected Output:** One pod in `Running` state and service with ClusterIP.

---

## Step 4: Deploy Token Validation Service

**Objective:** To deploy the token-validation-service, which validates JWTs for NGINX auth_request.

### 4.1. Create Token Validation Service Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/token-validation-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: token-validation-service
  namespace: default
  labels:
    app: token-validation-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: token-validation-service
  template:
    metadata:
      labels:
        app: token-validation-service
    spec:
      containers:
      - name: token-validation-service
        image: token-validation-service:latest
        imagePullPolicy: Never  # Use local Kind image
        ports:
        - containerPort: 8088
          name: http
        env:
        # Auth0 Configuration
        - name: AUTH0_ISSUER
          value: "https://dev-gcz1r8453xzz0317.us.auth0.com/"
        - name: AUTH0_AUDIENCE
          value: "https://api.budgetanalyzer.com"
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8088
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8088
          initialDelaySeconds: 60
          periodSeconds: 20
EOF
```

### 4.2. Create Token Validation Service Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/token-validation-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: token-validation-service
  namespace: default
  labels:
    app: token-validation-service
spec:
  type: ClusterIP
  selector:
    app: token-validation-service
  ports:
  - name: http
    port: 8088
    targetPort: 8088
    protocol: TCP
EOF
```

### 4.3. Build and Load Token Validation Service Image

**Action:** Build the Docker image and load it into Kind.

```bash
# Build the image (from service repository)
cd /workspace/token-validation-service
./gradlew bootBuildImage --imageName=token-validation-service:latest

# Load into Kind cluster
kind load docker-image token-validation-service:latest

# Return to orchestration directory
cd /workspace/orchestration
```

### 4.4. Apply Token Validation Service Manifests

**Action:** Apply the manifests to the cluster.

```bash
kubectl apply -f kubernetes/services/token-validation-service/deployment.yaml
kubectl apply -f kubernetes/services/token-validation-service/service.yaml
```

### 4.5. Verify Token Validation Service

**Action:** Confirm the service is running.

```bash
# Check pod status
kubectl get pods -l app=token-validation-service

# Wait for pod to be ready (may take longer due to JVM startup)
kubectl wait --for=condition=ready pod \
  -l app=token-validation-service \
  --timeout=180s

# Check logs for startup completion
kubectl logs -l app=token-validation-service --tail=20
```

**Expected Output:** Pod in `Running` state with health checks passing.

---

## Step 5: Deploy Session Gateway

**Objective:** To deploy the session-gateway (BFF), configured to proxy API requests to `http://nginx-gateway:8080` instead of the HTTPS endpoint.

### 5.1. Create Session Gateway ConfigMap

**Action:** Create a ConfigMap for Kubernetes-specific configuration.

```bash
cat <<'EOF' > kubernetes/services/session-gateway/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: session-gateway-config
  namespace: default
  labels:
    app: session-gateway
data:
  # Kubernetes-specific routing configuration
  BACKEND_URI: "http://nginx-gateway:8080"
  FRONTEND_URI: "http://nginx-gateway:8080"
EOF
```

### 5.2. Create Session Gateway Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/session-gateway/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: session-gateway
  namespace: default
  labels:
    app: session-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: session-gateway
  template:
    metadata:
      labels:
        app: session-gateway
    spec:
      containers:
      - name: session-gateway
        image: session-gateway:latest
        imagePullPolicy: Never  # Use local Kind image
        ports:
        - containerPort: 8081
          name: http
        env:
        # Spring profile
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        # Backend routing (key change from dev)
        - name: BACKEND_URI
          valueFrom:
            configMapKeyRef:
              name: session-gateway-config
              key: BACKEND_URI
        # Redis connection
        - name: SPRING_DATA_REDIS_HOST
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: host
        - name: SPRING_DATA_REDIS_PORT
          valueFrom:
            secretKeyRef:
              name: redis-credentials
              key: port
        # Auth0 Configuration (should be externalized to secrets in production)
        - name: SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_AUTH0_CLIENT_ID
          value: "your-client-id"  # Replace with actual value
        - name: SPRING_SECURITY_OAUTH2_CLIENT_REGISTRATION_AUTH0_CLIENT_SECRET
          value: "your-client-secret"  # Replace with actual value or use secret
        - name: SPRING_SECURITY_OAUTH2_CLIENT_PROVIDER_AUTH0_ISSUER_URI
          value: "https://dev-gcz1r8453xzz0317.us.auth0.com/"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8081
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8081
          initialDelaySeconds: 60
          periodSeconds: 20
EOF
```

### 5.3. Create Session Gateway Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/session-gateway/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: session-gateway
  namespace: default
  labels:
    app: session-gateway
spec:
  type: ClusterIP
  selector:
    app: session-gateway
  ports:
  - name: http
    port: 8081
    targetPort: 8081
    protocol: TCP
EOF
```

### 5.4. Build and Load Session Gateway Image

**Action:** Build the Docker image and load it into Kind.

```bash
# Build the image
cd /workspace/session-gateway
./gradlew bootBuildImage --imageName=session-gateway:latest

# Load into Kind cluster
kind load docker-image session-gateway:latest

# Return to orchestration directory
cd /workspace/orchestration
```

### 5.5. Apply Session Gateway Manifests

**Action:** Apply the manifests to the cluster.

```bash
kubectl apply -f kubernetes/services/session-gateway/configmap.yaml
kubectl apply -f kubernetes/services/session-gateway/deployment.yaml
kubectl apply -f kubernetes/services/session-gateway/service.yaml
```

### 5.6. Verify Session Gateway

**Action:** Confirm the service is running.

```bash
# Check pod status
kubectl get pods -l app=session-gateway

# Wait for pod to be ready
kubectl wait --for=condition=ready pod \
  -l app=session-gateway \
  --timeout=180s

# Check logs
kubectl logs -l app=session-gateway --tail=20
```

**Expected Output:** Pod in `Running` state with health checks passing.

---

## Step 6: Deploy Transaction Service

**Objective:** To deploy the transaction-service backend microservice.

### 6.1. Create Transaction Service Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/transaction-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: transaction-service
  namespace: default
  labels:
    app: transaction-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: transaction-service
  template:
    metadata:
      labels:
        app: transaction-service
    spec:
      containers:
      - name: transaction-service
        image: transaction-service:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8082
          name: http
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        # Database connection
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: budget-analyzer-url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: password
        # RabbitMQ connection
        - name: SPRING_RABBITMQ_HOST
          valueFrom:
            secretKeyRef:
              name: rabbitmq-credentials
              key: host
        - name: SPRING_RABBITMQ_PORT
          valueFrom:
            secretKeyRef:
              name: rabbitmq-credentials
              key: amqp-port
        - name: SPRING_RABBITMQ_USERNAME
          valueFrom:
            secretKeyRef:
              name: rabbitmq-credentials
              key: username
        - name: SPRING_RABBITMQ_PASSWORD
          valueFrom:
            secretKeyRef:
              name: rabbitmq-credentials
              key: password
        # Auth0 Configuration
        - name: AUTH0_ISSUER
          value: "https://dev-gcz1r8453xzz0317.us.auth0.com/"
        - name: AUTH0_AUDIENCE
          value: "https://api.budgetanalyzer.com"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8082
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8082
          initialDelaySeconds: 60
          periodSeconds: 20
EOF
```

### 6.2. Create Transaction Service Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/transaction-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: transaction-service
  namespace: default
  labels:
    app: transaction-service
spec:
  type: ClusterIP
  selector:
    app: transaction-service
  ports:
  - name: http
    port: 8082
    targetPort: 8082
    protocol: TCP
EOF
```

### 6.3. Build and Load Transaction Service Image

**Action:** Build the Docker image and load it into Kind.

```bash
cd /workspace/transaction-service
./gradlew bootBuildImage --imageName=transaction-service:latest
kind load docker-image transaction-service:latest
cd /workspace/orchestration
```

### 6.4. Apply Transaction Service Manifests

**Action:** Apply the manifests to the cluster.

```bash
kubectl apply -f kubernetes/services/transaction-service/deployment.yaml
kubectl apply -f kubernetes/services/transaction-service/service.yaml
```

---

## Step 7: Deploy Currency Service

**Objective:** To deploy the currency-service backend microservice.

### 7.1. Create Currency Service Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/currency-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: currency-service
  namespace: default
  labels:
    app: currency-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: currency-service
  template:
    metadata:
      labels:
        app: currency-service
    spec:
      containers:
      - name: currency-service
        image: currency-service:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8084
          name: http
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        # Database connection
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: currency-url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: password
        # Auth0 Configuration
        - name: AUTH0_ISSUER
          value: "https://dev-gcz1r8453xzz0317.us.auth0.com/"
        - name: AUTH0_AUDIENCE
          value: "https://api.budgetanalyzer.com"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8084
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8084
          initialDelaySeconds: 60
          periodSeconds: 20
EOF
```

### 7.2. Create Currency Service Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/currency-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: currency-service
  namespace: default
  labels:
    app: currency-service
spec:
  type: ClusterIP
  selector:
    app: currency-service
  ports:
  - name: http
    port: 8084
    targetPort: 8084
    protocol: TCP
EOF
```

### 7.3. Build and Load Currency Service Image

**Action:** Build the Docker image and load it into Kind.

```bash
cd /workspace/currency-service
./gradlew bootBuildImage --imageName=currency-service:latest
kind load docker-image currency-service:latest
cd /workspace/orchestration
```

### 7.4. Apply Currency Service Manifests

**Action:** Apply the manifests to the cluster.

```bash
kubectl apply -f kubernetes/services/currency-service/deployment.yaml
kubectl apply -f kubernetes/services/currency-service/service.yaml
```

---

## Step 8: Deploy Permission Service

**Objective:** To deploy the permission-service backend microservice.

### 8.1. Create Permission Service Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/permission-service/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: permission-service
  namespace: default
  labels:
    app: permission-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: permission-service
  template:
    metadata:
      labels:
        app: permission-service
    spec:
      containers:
      - name: permission-service
        image: permission-service:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 8086
          name: http
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "kubernetes"
        # Database connection
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: permission-url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-credentials
              key: password
        # Auth0 Configuration
        - name: AUTH0_ISSUER
          value: "https://dev-gcz1r8453xzz0317.us.auth0.com/"
        - name: AUTH0_AUDIENCE
          value: "https://api.budgetanalyzer.com"
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8086
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8086
          initialDelaySeconds: 60
          periodSeconds: 20
EOF
```

### 8.2. Create Permission Service Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/permission-service/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: permission-service
  namespace: default
  labels:
    app: permission-service
spec:
  type: ClusterIP
  selector:
    app: permission-service
  ports:
  - name: http
    port: 8086
    targetPort: 8086
    protocol: TCP
EOF
```

### 8.3. Build and Load Permission Service Image

**Action:** Build the Docker image and load it into Kind.

```bash
cd /workspace/permission-service
./gradlew bootBuildImage --imageName=permission-service:latest
kind load docker-image permission-service:latest
cd /workspace/orchestration
```

### 8.4. Apply Permission Service Manifests

**Action:** Apply the manifests to the cluster.

```bash
kubectl apply -f kubernetes/services/permission-service/deployment.yaml
kubectl apply -f kubernetes/services/permission-service/service.yaml
```

---

## Step 9: Deploy React Frontend (Budget Analyzer Web)

**Objective:** To deploy the React frontend application for local development.

### 9.1. Create Frontend Deployment

**Action:** Create the Deployment manifest.

```bash
cat <<'EOF' > kubernetes/services/budget-analyzer-web/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: budget-analyzer-web
  namespace: default
  labels:
    app: budget-analyzer-web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: budget-analyzer-web
  template:
    metadata:
      labels:
        app: budget-analyzer-web
    spec:
      containers:
      - name: budget-analyzer-web
        image: budget-analyzer-web:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 3000
          name: http
        env:
        - name: NODE_ENV
          value: "development"
        # Vite configuration for Kubernetes
        - name: VITE_API_BASE_URL
          value: ""  # Empty for same-origin requests via session gateway
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "300m"
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 20
EOF
```

### 9.2. Create Frontend Service

**Action:** Create the Service manifest.

```bash
cat <<'EOF' > kubernetes/services/budget-analyzer-web/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: budget-analyzer-web
  namespace: default
  labels:
    app: budget-analyzer-web
spec:
  type: ClusterIP
  selector:
    app: budget-analyzer-web
  ports:
  - name: http
    port: 3000
    targetPort: 3000
    protocol: TCP
EOF
```

### 9.3. Build and Load Frontend Image

**Action:** Build and load the frontend image.

```bash
cd /workspace/budget-analyzer-web
docker build -t budget-analyzer-web:latest .
kind load docker-image budget-analyzer-web:latest
cd /workspace/orchestration
```

### 9.4. Apply Frontend Manifests

**Action:** Apply the manifests to the cluster.

```bash
mkdir -p kubernetes/services/budget-analyzer-web
kubectl apply -f kubernetes/services/budget-analyzer-web/deployment.yaml
kubectl apply -f kubernetes/services/budget-analyzer-web/service.yaml
```

---

## Step 10: Final Verification

**Objective:** To perform a comprehensive check that all core services are running and can communicate with each other.

### 10.1. Check All Pods

**Action:** List all pods in the default namespace.

```bash
kubectl get pods
```

**Expected Output:** Seven pods (nginx-gateway, token-validation-service, session-gateway, transaction-service, currency-service, permission-service, budget-analyzer-web) should all be in `Running` state.

### 10.2. Check All Services

**Action:** List all services.

```bash
kubectl get svc
```

**Expected Output:** All services should be listed with ClusterIP addresses.

### 10.3. Test NGINX Health Endpoint

**Action:** Port-forward and test the NGINX health endpoint.

```bash
kubectl port-forward svc/nginx-gateway 8080:8080 &
sleep 3
curl http://localhost:8080/health
kill %1
```

**Expected Output:** Should return `healthy`.

### 10.4. Test Service Connectivity (from within cluster)

**Action:** Create a test pod to verify internal service discovery.

```bash
# Create a test pod
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "curl -s http://nginx-gateway:8080/health && echo ' - nginx OK' && \
         curl -s http://session-gateway:8081/actuator/health && echo ' - session-gateway OK'"
```

**Expected Output:** Both services should respond with health status.

### 10.5. Summary Check

**Action:** Run a complete status check.

```bash
echo "=== Core Services Status ==="
echo ""
echo "Pods:"
kubectl get pods -o wide
echo ""
echo "Services:"
kubectl get svc
echo ""
echo "Endpoints:"
kubectl get endpoints nginx-gateway session-gateway token-validation-service
```

---

## Troubleshooting

### Pod Stuck in ImagePullBackOff

**Symptom:** Pod cannot pull image.

**Solution:** Ensure images are loaded into Kind:
```bash
# List images in Kind
docker exec -it kind-control-plane crictl images | grep <service-name>

# Reload image if missing
kind load docker-image <service-name>:latest
```

### Service Not Resolving

**Symptom:** NGINX cannot reach backend services.

**Solution:** Check service endpoints and DNS:
```bash
# Check endpoints
kubectl get endpoints <service-name>

# Test DNS from NGINX pod
kubectl exec -it $(kubectl get pod -l app=nginx-gateway -o jsonpath='{.items[0].metadata.name}') -- \
  nslookup transaction-service
```

### JWT Validation Failing

**Symptom:** All API requests return 401.

**Solution:** Check token-validation-service logs:
```bash
kubectl logs -l app=token-validation-service --tail=50
```

Common causes:
- Incorrect Auth0 issuer/audience configuration
- Network connectivity issues to Auth0 JWKS endpoint

### Session Gateway Cannot Connect to Redis

**Symptom:** Session Gateway fails to start.

**Solution:** Verify Redis connectivity:
```bash
# Check Redis secret
kubectl get secret redis-credentials -o yaml

# Test connection
kubectl run redis-test --image=redis --rm -it --restart=Never -- \
  redis-cli -h redis-master.infrastructure.svc.cluster.local ping
```

### Database Connection Errors

**Symptom:** Backend service cannot connect to PostgreSQL.

**Solution:** Verify database secret and connectivity:
```bash
# Check secret
kubectl get secret postgresql-credentials -o jsonpath='{.data.budget-analyzer-url}' | base64 -d

# Test connection
kubectl run pg-test --image=postgres --rm -it --restart=Never -- \
  psql "postgresql://budget_analyzer:budget_analyzer@postgresql.infrastructure.svc.cluster.local:5432/budget_analyzer" -c "\l"
```

---

## Next Steps

After completing Phase 4, you have all core services running in Kubernetes. Proceed to:

- **Phase 5: Tiltfile Configuration** - Set up Tilt for live reload and development workflow
- Configure port-forwards for debugging
- Set up React dev server with HMR through Tilt

---

## Cleanup

To remove all core services (for fresh start or troubleshooting):

```bash
# Delete all deployments
kubectl delete deployment nginx-gateway session-gateway token-validation-service \
  transaction-service currency-service permission-service budget-analyzer-web

# Delete all services
kubectl delete svc nginx-gateway session-gateway token-validation-service \
  transaction-service currency-service permission-service budget-analyzer-web

# Delete ConfigMaps
kubectl delete configmap nginx-gateway-config nginx-gateway-includes session-gateway-config
```

**Note:** This does not delete infrastructure services (PostgreSQL, Redis, RabbitMQ) or secrets.
