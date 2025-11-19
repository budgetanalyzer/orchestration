# Local HTTPS Development Setup

**Status**: Planned
**Created**: 2025-11-19
**Goal**: Enable production-like HTTPS for local development with clean subdomain URLs

## Problem Statement

Modern browsers require the `Secure` flag on cookies for session management in production scenarios. Our current HTTP-only local development environment prevents proper testing of secure cookie behavior. We need a local HTTPS setup that mirrors production architecture.

## Proposed Solution

Implement full HTTPS for local development using clean subdomain URLs with standard ports:

- **Session Gateway**: `https://app.budgetanalyzer.localhost` (port 443)
- **API Gateway**: `https://api.budgetanalyzer.localhost` (port 443)
- **Backend Services**: Internal HTTP (Docker network, no security concern)

## Architecture

### Current State (HTTP)
```
Browser → http://localhost:8081 (Session Gateway)
    ↓
Session Gateway → http://localhost:8080 (NGINX)
    ↓
NGINX → http://host.docker.internal:8082+ (Backend Services)
```

### Target State (HTTPS)
```
Browser → https://app.budgetanalyzer.localhost (Session Gateway on :443)
    ↓
Session Gateway → https://api.budgetanalyzer.localhost (NGINX on :443)
    ↓
NGINX → http://host.docker.internal:8082+ (Backend Services)
```

## Implementation Plan

### Phase 1: Certificate Generation with mkcert

**Why mkcert?**
- Industry standard for local development HTTPS
- Creates locally-trusted certificates with zero configuration
- Automatically installs CA in system trust store
- No browser security warnings
- Works across all modern browsers

**Steps:**

1. **Install mkcert**
   ```bash
   # macOS
   brew install mkcert nss  # nss for Firefox support

   # Linux
   sudo apt install libnss3-tools
   curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
   chmod +x mkcert-v*-linux-amd64
   sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

   # Windows (Chocolatey)
   choco install mkcert
   ```

2. **Create Local CA**
   ```bash
   mkcert -install
   ```
   This creates a local CA and installs it in your system's trust store (including browsers).

3. **Generate Wildcard Certificate**
   ```bash
   cd /workspace/orchestration
   mkdir -p nginx/certs
   cd nginx/certs
   mkcert "*.budgetanalyzer.localhost"
   ```

   This generates:
   - `_wildcard.budgetanalyzer.localhost.pem` (certificate)
   - `_wildcard.budgetanalyzer.localhost-key.pem` (private key)

   The wildcard covers:
   - `app.budgetanalyzer.localhost` (Session Gateway)
   - `api.budgetanalyzer.localhost` (NGINX)
   - Any future subdomains

4. **Update .gitignore**
   ```
   # SSL Certificates (never commit private keys!)
   nginx/certs/*.pem
   nginx/certs/*.p12
   session-gateway/src/main/resources/certs/*.p12
   ```

### Phase 2: NGINX HTTPS Configuration

**File**: `/workspace/orchestration/nginx/nginx.dev.conf`

**Changes Required:**

1. **Update server_name**
   ```nginx
   # Line 48 - Change from:
   server_name localhost;

   # To:
   server_name api.budgetanalyzer.localhost;
   ```

2. **Update listen directive**
   ```nginx
   # Line 49 - Change from:
   listen 80;

   # To:
   listen 443 ssl http2;
   listen 80;  # Keep for redirect
   ```

3. **Add SSL directives** (after server_name)
   ```nginx
   # SSL Configuration
   ssl_certificate /etc/nginx/certs/_wildcard.budgetanalyzer.localhost.pem;
   ssl_certificate_key /etc/nginx/certs/_wildcard.budgetanalyzer.localhost-key.pem;

   # Modern SSL protocols only
   ssl_protocols TLSv1.2 TLSv1.3;

   # Strong cipher suites
   ssl_ciphers HIGH:!aNULL:!MD5;
   ssl_prefer_server_ciphers on;

   # SSL session cache for performance
   ssl_session_cache shared:SSL:10m;
   ssl_session_timeout 10m;
   ```

4. **Enable HSTS headers** (currently commented at lines 84-86)
   ```nginx
   # Uncomment and update:
   add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
   add_header X-Frame-Options "SAMEORIGIN" always;
   add_header X-Content-Type-Options "nosniff" always;
   ```

5. **Add HTTP → HTTPS redirect** (before main server block)
   ```nginx
   # HTTP redirect to HTTPS
   server {
       listen 80;
       server_name api.budgetanalyzer.localhost;

       location / {
           return 301 https://$server_name$request_uri;
       }
   }
   ```

**File**: `/workspace/orchestration/docker-compose.yml`

**Changes for nginx-gateway service:**

```yaml
nginx-gateway:
  image: nginx:alpine
  container_name: api-gateway
  ports:
    - "443:443"    # HTTPS
    - "80:80"      # HTTP (for redirects)
  volumes:
    - ./nginx/nginx.dev.conf:/etc/nginx/nginx.conf:ro
    - ./nginx/includes:/etc/nginx/includes:ro
    - ./nginx/certs:/etc/nginx/certs:ro  # Add cert mount
  extra_hosts:
    - "host.docker.internal:host-gateway"
  networks:
    - budget-analyzer
```

### Phase 3: Session Gateway HTTPS Configuration

**Step 1: Convert Certificate to PKCS12 Format**

Spring Boot requires PKCS12 keystore format (not PEM).

```bash
cd /workspace/session-gateway/src/main/resources
mkdir -p certs
cd /workspace/orchestration/nginx/certs

# Convert to PKCS12
openssl pkcs12 -export \
  -in _wildcard.budgetanalyzer.localhost.pem \
  -inkey _wildcard.budgetanalyzer.localhost-key.pem \
  -out /workspace/session-gateway/src/main/resources/certs/budgetanalyzer.p12 \
  -name budgetanalyzer \
  -passout pass:changeit
```

**Step 2: Update application.yml**

**File**: `/workspace/session-gateway/src/main/resources/application.yml`

Add SSL configuration:

```yaml
server:
  port: 443  # Change from 8081
  ssl:
    enabled: true
    key-store: classpath:certs/budgetanalyzer.p12
    key-store-password: changeit
    key-store-type: PKCS12
    key-alias: budgetanalyzer
```

Update Spring Cloud Gateway routes to use HTTPS for NGINX:

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: api-route
          uri: https://api.budgetanalyzer.localhost  # Change from http://localhost:8080
          predicates:
            - Path=/api/**
          filters:
            - name: TokenRelay
```

Update Auth0 logout configuration (line 94):

```yaml
auth0:
  logout:
    return-to: https://app.budgetanalyzer.localhost/  # Change from http://localhost:8081
```

**Step 3: Update Cookie Configuration**

**File**: `/workspace/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/SessionConfig.java`

Line 57 - Enable secure cookies:

```java
// Change from:
builder.secure(false);  // Set to true in production (HTTPS only)

// To:
builder.secure(true);   // HTTPS required for local dev now
```

**Step 4: Update Docker Compose**

**File**: `/workspace/orchestration/docker-compose.yml`

Update session-gateway service (if running in Docker):

```yaml
session-gateway:
  build:
    context: ../session-gateway
  container_name: session-gateway
  ports:
    - "443:443"  # Change from 8081:8081
  environment:
    - SPRING_PROFILES_ACTIVE=dev
    - SERVER_PORT=443
  networks:
    - budget-analyzer
```

**Note**: The PKCS12 keystore will be bundled into the JAR during build, so no additional volume mounts needed if using `classpath:` reference.

### Phase 4: Auth0 Configuration Updates

**Location**: Auth0 Dashboard → Applications → [Your Application] → Settings

**Current URLs to Update:**

1. **Allowed Callback URLs**
   ```
   Add: https://app.budgetanalyzer.localhost/login/oauth2/code/auth0
   Keep: http://localhost:8081/login/oauth2/code/auth0 (during migration)
   ```

2. **Allowed Logout URLs**
   ```
   Add: https://app.budgetanalyzer.localhost/
   Keep: http://localhost:8081/ (during migration)
   ```

3. **Allowed Web Origins**
   ```
   Add: https://app.budgetanalyzer.localhost
   Keep: http://localhost:8081 (during migration)
   ```

4. **Allowed Origins (CORS)**
   ```
   Add: https://app.budgetanalyzer.localhost
   Keep: http://localhost:8081 (during migration)
   ```

**Migration Strategy**: Keep both HTTP and HTTPS URLs during transition period. Remove HTTP URLs once HTTPS is verified working.

### Phase 5: Documentation Updates

**Files to Update:**

1. **`/workspace/orchestration/CLAUDE.md`**
   - Find/Replace: `http://localhost:8081` → `https://app.budgetanalyzer.localhost`
   - Find/Replace: `http://localhost:8080` → `https://api.budgetanalyzer.localhost`
   - Update port summary table
   - Update discovery commands
   - Add section on HTTPS setup

2. **`/workspace/orchestration/README.md`**
   - Update Quick Start URLs
   - Add Prerequisites section mentioning mkcert
   - Add "First Time Setup" for certificate generation

3. **`/workspace/orchestration/nginx/README.md`**
   - Update all curl examples to use https://api.budgetanalyzer.localhost
   - Update troubleshooting commands
   - Add SSL/certificate troubleshooting section

4. **Service READMEs** (if they reference URLs)
   - `/workspace/session-gateway/README.md`
   - `/workspace/budget-analyzer-web/README.md`

### Phase 6: Developer Onboarding Automation

**Create**: `/workspace/orchestration/scripts/setup-local-https.sh`

```bash
#!/bin/bash
set -e

echo "=== Budget Analyzer - Local HTTPS Setup ==="
echo

# Check if mkcert is installed
if ! command -v mkcert &> /dev/null; then
    echo "❌ mkcert is not installed"
    echo
    echo "Install mkcert:"
    echo "  macOS:   brew install mkcert nss"
    echo "  Linux:   See https://github.com/FiloSottile/mkcert#installation"
    echo "  Windows: choco install mkcert"
    echo
    exit 1
fi

echo "✅ mkcert is installed"

# Check if local CA is installed
if ! mkcert -CAROOT &> /dev/null; then
    echo "Installing local CA..."
    mkcert -install
    echo "✅ Local CA installed"
else
    echo "✅ Local CA already installed"
fi

# Generate certificates
echo
echo "Generating wildcard certificate for *.budgetanalyzer.localhost..."

cd "$(dirname "$0")/../nginx/certs" || exit 1
mkcert "*.budgetanalyzer.localhost"

echo "✅ Certificate generated:"
ls -lh _wildcard.budgetanalyzer.localhost*.pem

# Convert to PKCS12 for Session Gateway
echo
echo "Converting certificate to PKCS12 format for Spring Boot..."

PKCS12_PATH="../../session-gateway/src/main/resources/certs"
mkdir -p "$PKCS12_PATH"

openssl pkcs12 -export \
  -in _wildcard.budgetanalyzer.localhost.pem \
  -inkey _wildcard.budgetanalyzer.localhost-key.pem \
  -out "$PKCS12_PATH/budgetanalyzer.p12" \
  -name budgetanalyzer \
  -passout pass:changeit

echo "✅ PKCS12 keystore created"
echo

echo "=== Setup Complete! ==="
echo
echo "Next steps:"
echo "1. Restart Docker services: docker compose restart"
echo "2. Access application: https://app.budgetanalyzer.localhost"
echo "3. API Gateway: https://api.budgetanalyzer.localhost"
echo
echo "Note: Your browser will trust these certificates automatically!"
```

Make executable:
```bash
chmod +x scripts/setup-local-https.sh
```

### Phase 7: Testing & Validation

**Test Checklist:**

1. **Certificate Trust**
   - [ ] Access `https://app.budgetanalyzer.localhost`
   - [ ] Verify green padlock in browser (no warnings)
   - [ ] Check certificate details show mkcert CA

2. **Authentication Flow**
   - [ ] Click login button
   - [ ] Redirects to Auth0 correctly
   - [ ] Successfully authenticate
   - [ ] Redirects back to `https://app.budgetanalyzer.localhost`
   - [ ] Check browser DevTools → Application → Cookies
   - [ ] Verify SESSION cookie has `Secure` flag ✅

3. **API Communication**
   - [ ] Browse application pages
   - [ ] Check Network tab: all API calls use `https://app.budgetanalyzer.localhost/api/*`
   - [ ] Verify responses return successfully (200 status)
   - [ ] No CORS errors in console

4. **React Development Experience**
   - [ ] Make a code change in React app
   - [ ] Verify Hot Module Reload (HMR) works
   - [ ] Check WebSocket connection is secure (wss://)

5. **NGINX Routing**
   - [ ] Test transaction endpoints
   - [ ] Test currency endpoints
   - [ ] Verify NGINX logs show HTTPS requests

6. **HTTP → HTTPS Redirect**
   - [ ] Access `http://api.budgetanalyzer.localhost`
   - [ ] Verify it redirects to `https://api.budgetanalyzer.localhost`

**Manual Testing Commands:**

```bash
# Test API Gateway directly
curl -v https://api.budgetanalyzer.localhost/health

# Should redirect to HTTPS
curl -v http://api.budgetanalyzer.localhost/health

# Test Session Gateway
curl -v https://app.budgetanalyzer.localhost/actuator/health

# Check NGINX config is valid
docker exec api-gateway nginx -t

# View NGINX logs
docker logs api-gateway -f

# View Session Gateway logs
docker logs session-gateway -f

# Check certificate expiration
openssl x509 -in nginx/certs/_wildcard.budgetanalyzer.localhost.pem -noout -dates
```

## Benefits

### Security Benefits
✅ **Secure Cookies**: Proper testing of production cookie behavior
✅ **HTTPS-Only Features**: Test features that require secure context (Service Workers, Web Crypto API, etc.)
✅ **Defense in Depth**: Encrypted communication between gateway layers
✅ **No Browser Warnings**: Trusted certificates eliminate security warnings

### Developer Experience Benefits
✅ **Production Parity**: Local environment mirrors production architecture
✅ **Clean URLs**: Professional subdomain structure, no port numbers
✅ **No CORS Issues**: Same-origin policy maintained with HTTPS
✅ **Modern Browser Compliance**: Works with latest browser security requirements
✅ **Easy Onboarding**: Automated script for new developers

### Architectural Benefits
✅ **Subdomain Routing**: Scalable pattern for adding new services
✅ **Standard Ports**: Using 443 for HTTPS (no custom ports)
✅ **Wildcard Certificate**: Single cert covers all subdomains
✅ **Service Independence**: Backend services remain decoupled

## Rollback Plan

If issues arise, rollback is simple:

1. **Quick Rollback** (keep HTTPS config, just access via HTTP):
   - Access `http://app.budgetanalyzer.localhost:8081`
   - NGINX will handle on port 80

2. **Full Rollback**:
   ```bash
   git checkout nginx/nginx.dev.conf
   git checkout docker-compose.yml
   git checkout ../session-gateway/src/main/resources/application.yml
   docker compose restart
   ```

3. **Certificate Removal** (if needed):
   ```bash
   rm -rf nginx/certs/*.pem
   rm -rf ../session-gateway/src/main/resources/certs/*.p12
   mkcert -uninstall  # Remove CA from trust store
   ```

## Timeline Estimate

| Phase | Task | Estimated Time |
|-------|------|----------------|
| 1 | Certificate generation with mkcert | 15 min |
| 2 | NGINX HTTPS configuration | 30 min |
| 3 | Session Gateway HTTPS configuration | 45 min |
| 4 | Auth0 updates | 15 min |
| 5 | Documentation updates | 30 min |
| 6 | Create setup script | 20 min |
| 7 | Testing & validation | 30 min |
| **Total** | | **~3 hours** |

## Dependencies

- mkcert installed on local machine
- Docker and Docker Compose running
- Access to Auth0 application settings
- OpenSSL (for PKCS12 conversion)

## Success Criteria

- ✅ Browser shows green padlock for `https://app.budgetanalyzer.localhost`
- ✅ SESSION cookie has `Secure` flag enabled
- ✅ OAuth2 login flow completes successfully
- ✅ All API calls work through HTTPS
- ✅ React HMR (hot reload) continues to function
- ✅ No browser security warnings
- ✅ Setup script allows new developers to get HTTPS working in < 5 minutes

## Future Enhancements

1. **Production Deployment**: This plan sets foundation for production HTTPS with real certificates
2. **Additional Subdomains**: Easy to add `admin.budgetanalyzer.localhost`, `reports.budgetanalyzer.localhost`, etc.
3. **Certificate Rotation**: Document process for renewing certificates (mkcert certs don't expire, but good practice)
4. **CI/CD Integration**: Add certificate generation to CI pipeline for preview environments

## References

- [mkcert GitHub](https://github.com/FiloSottile/mkcert)
- [NGINX SSL Module](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [Spring Boot SSL Configuration](https://docs.spring.io/spring-boot/docs/current/reference/html/howto.html#howto.webserver.configure-ssl)
- [MDN: Secure Cookies](https://developer.mozilla.org/en-US/docs/Web/HTTP/Cookies#restrict_access_to_cookies)
- [Web.dev: When to Use Local HTTPS](https://web.dev/when-to-use-local-https/)
