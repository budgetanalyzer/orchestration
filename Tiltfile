# ============================================================================
# Budget Analyzer - Tiltfile
# Phase 5: Complete Local Development Environment with Live Reload
# ============================================================================

# Load extensions
load('ext://restart_process', 'docker_build_with_restart')
load('ext://uibutton', 'cmd_button', 'location')
load('ext://configmap', 'configmap_create')
load('ext://dotenv', 'dotenv')

# Load environment variables from .env file
# Copy .env.example to .env and fill in your values
dotenv()

# Load common configuration
load('./tilt/common.star',
     'WORKSPACE',
     'DEFAULT_NAMESPACE',
     'INFRA_NAMESPACE',
     'SERVICE_PORTS',
     'DEBUG_PORTS',
     'get_repo_path')

# ============================================================================
# GLOBAL SETTINGS
# ============================================================================

# Restrict to our Kind cluster for safety
allow_k8s_contexts('kind-kind')

# Performance tuning
update_settings(
    max_parallel_updates=5,
    k8s_upsert_timeout_secs=120,
)

# Docker image pruning
docker_prune_settings(
    max_age_mins=360,
    num_builds=10,
    keep_recent=3,
)

# ============================================================================
# INFRASTRUCTURE SERVICES (Raw Kubernetes Manifests)
# ============================================================================

# Infrastructure namespace
k8s_yaml('kubernetes/infrastructure/namespace.yaml')

# PostgreSQL
k8s_yaml([
    'kubernetes/infrastructure/postgresql/configmap.yaml',
    'kubernetes/infrastructure/postgresql/service.yaml',
    'kubernetes/infrastructure/postgresql/statefulset.yaml',
])

k8s_resource(
    'postgresql',
    port_forwards=[
        port_forward(5432, 5432, name='PostgreSQL'),
    ],
    labels=['infrastructure', 'database'],
)

# Redis
configmap_create(
    'redis-acl-bootstrap',
    namespace=INFRA_NAMESPACE,
    from_file=['start-redis.sh=kubernetes/infrastructure/redis/start-redis.sh'],
    watch=True
)

k8s_yaml([
    'kubernetes/infrastructure/redis/deployment.yaml',
    'kubernetes/infrastructure/redis/service.yaml',
])

k8s_resource(
    'redis',
    port_forwards=[
        port_forward(6379, 6379, name='Redis'),
    ],
    labels=['infrastructure', 'cache'],
)

# RabbitMQ
k8s_yaml([
    'kubernetes/infrastructure/rabbitmq/configmap.yaml',
    'kubernetes/infrastructure/rabbitmq/statefulset.yaml',
    'kubernetes/infrastructure/rabbitmq/service.yaml',
])

k8s_resource(
    'rabbitmq',
    port_forwards=[
        port_forward(5671, 5671, name='AMQPS'),
        port_forward(15672, 15672, name='Management UI'),
    ],
    labels=['infrastructure'],
)

# ============================================================================
# SECRETS
# ============================================================================

# Helper function to encode values to base64
def shell_single_quote(value):
    """Quote a string for safe single-quoted shell usage."""
    return "'" + value.replace("'", "'\"'\"'") + "'"

def encode_secret_data(data):
    """Encode dictionary values to base64 for Kubernetes secrets."""
    encoded = {}
    for k, v in data.items():
        encoded[k] = str(local("printf %s " + shell_single_quote(v) + " | base64 | tr -d '\\n'", quiet=True)).strip()
    return encoded

def json_escape(value):
    """Escape a string for safe JSON interpolation."""
    escaped = value.replace('\\', '\\\\')
    escaped = escaped.replace('"', '\\"')
    escaped = escaped.replace('\b', '\\b')
    escaped = escaped.replace('\f', '\\f')
    escaped = escaped.replace('\n', '\\n')
    escaped = escaped.replace('\r', '\\r')
    escaped = escaped.replace('\t', '\\t')
    return escaped

def json_string(value):
    """Render a JSON string literal."""
    return '"' + json_escape(value) + '"'

def build_rabbitmq_definitions(admin_user, admin_password, service_user, service_password, vhost):
    """Build RabbitMQ definitions JSON for local boot-time import."""
    return """{
  "users": [
    {
      "name": %s,
      "password": %s,
      "tags": ["administrator"]
    },
    {
      "name": %s,
      "password": %s,
      "tags": []
    }
  ],
  "vhosts": [
    {
      "name": %s
    }
  ],
  "permissions": [
    {
      "user": %s,
      "vhost": %s,
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": %s,
      "vhost": %s,
      "configure": "^(amq\\\\.gen.*|currency\\\\.created|currency\\\\.created\\\\.exchange-rate-import-service(\\\\.dlq)?|DLX)$",
      "write": "^(amq\\\\.default|currency\\\\.created|DLX)$",
      "read": "^(currency\\\\.created|currency\\\\.created\\\\.exchange-rate-import-service(\\\\.dlq)?)$"
    }
  ]
}""" % (
        json_string(admin_user),
        json_string(admin_password),
        json_string(service_user),
        json_string(service_password),
        json_string(vhost),
        json_string(admin_user),
        json_string(vhost),
        json_string(service_user),
        json_string(vhost),
    )

def secret_blob(name, namespace, data):
    """Render a Kubernetes Secret as a blob."""
    encoded = encode_secret_data(data)
    lines = [
        'apiVersion: v1',
        'kind: Secret',
        'metadata:',
        '  name: ' + name,
        '  namespace: ' + namespace,
        'type: Opaque',
        'data:',
    ]
    for key in encoded:
        lines.append('  ' + key + ': ' + encoded[key])
    return blob('\n'.join(lines) + '\n')

def create_secret(name, namespace, data):
    """Apply a Kubernetes Secret generated by Tilt."""
    k8s_yaml(secret_blob(name, namespace, data))

postgresql_host = 'postgresql.' + INFRA_NAMESPACE
rabbitmq_host = 'rabbitmq.' + INFRA_NAMESPACE
redis_host = 'redis.' + INFRA_NAMESPACE

# PostgreSQL Step 2: keep the bootstrap/admin path separate from the
# service-owned database identities.
postgresql_bootstrap_password = os.getenv('POSTGRES_BOOTSTRAP_PASSWORD', 'budget-analyzer-postgres-admin')
transaction_service_pg_password = os.getenv('POSTGRES_TRANSACTION_SERVICE_PASSWORD', 'budget-analyzer-transaction-service')
currency_service_pg_password = os.getenv('POSTGRES_CURRENCY_SERVICE_PASSWORD', 'budget-analyzer-currency-service')
permission_service_pg_password = os.getenv('POSTGRES_PERMISSION_SERVICE_PASSWORD', 'budget-analyzer-permission-service')

create_secret('postgresql-bootstrap-credentials', INFRA_NAMESPACE, {
    'username': 'postgres_admin',
    'password': postgresql_bootstrap_password,
    'transaction-service-password': transaction_service_pg_password,
    'currency-service-password': currency_service_pg_password,
    'permission-service-password': permission_service_pg_password,
})

create_secret('transaction-service-postgresql-credentials', DEFAULT_NAMESPACE, {
    'username': 'transaction_service',
    'password': transaction_service_pg_password,
    'url': 'jdbc:postgresql://' + postgresql_host + ':5432/budget_analyzer?sslmode=verify-full&sslrootcert=/etc/ssl/infra/ca.crt',
})

create_secret('currency-service-postgresql-credentials', DEFAULT_NAMESPACE, {
    'username': 'currency_service',
    'password': currency_service_pg_password,
    'url': 'jdbc:postgresql://' + postgresql_host + ':5432/currency?sslmode=verify-full&sslrootcert=/etc/ssl/infra/ca.crt',
})

create_secret('permission-service-postgresql-credentials', DEFAULT_NAMESPACE, {
    'username': 'permission_service',
    'password': permission_service_pg_password,
    'url': 'jdbc:postgresql://' + postgresql_host + ':5432/permission?sslmode=verify-full&sslrootcert=/etc/ssl/infra/ca.crt',
})

rabbitmq_admin_username = 'rabbitmq-admin'
rabbitmq_admin_password = os.getenv('RABBITMQ_BOOTSTRAP_PASSWORD', 'budget-analyzer-rabbitmq-admin')
rabbitmq_currency_service_username = 'currency-service'
rabbitmq_currency_service_password = os.getenv('RABBITMQ_CURRENCY_SERVICE_PASSWORD', 'budget-analyzer-currency-service-rabbitmq')
rabbitmq_virtual_host = '/'
rabbitmq_definitions = build_rabbitmq_definitions(
    rabbitmq_admin_username,
    rabbitmq_admin_password,
    rabbitmq_currency_service_username,
    rabbitmq_currency_service_password,
    rabbitmq_virtual_host,
)

create_secret('rabbitmq-bootstrap-credentials', INFRA_NAMESPACE, {
    'username': rabbitmq_admin_username,
    'password': rabbitmq_admin_password,
    'currency-service-username': rabbitmq_currency_service_username,
    'currency-service-password': rabbitmq_currency_service_password,
    'virtual-host': rabbitmq_virtual_host,
    'definitions.json': rabbitmq_definitions,
})

create_secret('currency-service-rabbitmq-credentials', DEFAULT_NAMESPACE, {
    'host': rabbitmq_host,
    'amqp-port': '5671',
    'username': rabbitmq_currency_service_username,
    'password': rabbitmq_currency_service_password,
    'virtual-host': rabbitmq_virtual_host,
})

redis_default_password = os.getenv('REDIS_DEFAULT_PASSWORD', 'budget-analyzer-redis-default')
redis_ops_password = os.getenv('REDIS_OPS_PASSWORD', 'budget-analyzer-redis-ops')
redis_session_gateway_password = os.getenv('REDIS_SESSION_GATEWAY_PASSWORD', 'budget-analyzer-session-gateway-redis')
redis_ext_authz_password = os.getenv('REDIS_EXT_AUTHZ_PASSWORD', 'budget-analyzer-ext-authz-redis')
redis_currency_service_password = os.getenv('REDIS_CURRENCY_SERVICE_PASSWORD', 'budget-analyzer-currency-service-redis')

create_secret('redis-bootstrap-credentials', INFRA_NAMESPACE, {
    'default-username': 'default',
    'default-password': redis_default_password,
    'session-gateway-username': 'session-gateway',
    'ext-authz-username': 'ext-authz',
    'currency-service-username': 'currency-service',
    'ops-username': 'redis-ops',
    'ops-password': redis_ops_password,
    'session-gateway-password': redis_session_gateway_password,
    'ext-authz-password': redis_ext_authz_password,
    'currency-service-password': redis_currency_service_password,
})

create_secret('session-gateway-redis-credentials', DEFAULT_NAMESPACE, {
    'host': redis_host,
    'port': '6379',
    'username': 'session-gateway',
    'password': redis_session_gateway_password,
})

create_secret('ext-authz-redis-credentials', DEFAULT_NAMESPACE, {
    'host': redis_host,
    'port': '6379',
    'username': 'ext-authz',
    'password': redis_ext_authz_password,
})

create_secret('currency-service-redis-credentials', DEFAULT_NAMESPACE, {
    'host': redis_host,
    'port': '6379',
    'username': 'currency-service',
    'password': redis_currency_service_password,
})

# IDP credentials for Session Gateway
# All values loaded from .env file via dotenv()
auth0_data = encode_secret_data({
    'AUTH0_CLIENT_ID': os.getenv('AUTH0_CLIENT_ID', ''),
    'AUTH0_CLIENT_SECRET': os.getenv('AUTH0_CLIENT_SECRET', ''),
    'AUTH0_ISSUER_URI': os.getenv('AUTH0_ISSUER_URI', ''),
    'IDP_AUDIENCE': os.getenv('IDP_AUDIENCE', 'https://api.budgetanalyzer.org'),
    'IDP_LOGOUT_RETURN_TO': os.getenv('IDP_LOGOUT_RETURN_TO', 'https://app.budgetanalyzer.localhost/peace'),
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: auth0-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  AUTH0_CLIENT_ID: ''' + auth0_data['AUTH0_CLIENT_ID'] + '''
  AUTH0_CLIENT_SECRET: ''' + auth0_data['AUTH0_CLIENT_SECRET'] + '''
  AUTH0_ISSUER_URI: ''' + auth0_data['AUTH0_ISSUER_URI'] + '''
  IDP_AUDIENCE: ''' + auth0_data['IDP_AUDIENCE'] + '''
  IDP_LOGOUT_RETURN_TO: ''' + auth0_data['IDP_LOGOUT_RETURN_TO'] + '''
'''))

# FRED API credentials for Currency Service
fred_data = encode_secret_data({
    'api-key': os.getenv('FRED_API_KEY', ''),
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: fred-api-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  api-key: ''' + fred_data['api-key'] + '''
'''))

# ============================================================================
# SERVICE-COMMON SHARED LIBRARY
# ============================================================================

# Publish service-common to Maven Local when it changes
# All backend services depend on this
local_resource(
    'service-common-publish',
    cmd='cd ' + get_repo_path('service-common') + ' && ./gradlew publishToMavenLocal --parallel --build-cache && ' +
        'tilt trigger transaction-service-compile && ' +
        'tilt trigger currency-service-compile && ' +
        'tilt trigger permission-service-compile && ' +
        'tilt trigger session-gateway-compile',
    deps=[
        get_repo_path('service-common') + '/src',
        get_repo_path('service-common') + '/build.gradle.kts',
    ],
    labels=['compile'],
    allow_parallel=True,
    auto_init=True
)

# ============================================================================
# SPRING BOOT SERVICE BUILD PATTERN
# ============================================================================

def spring_boot_service(name, deps=[]):
    """
    Build pattern for Spring Boot services with live reload.

    Args:
        name: Service name (must match repository name)
        deps: Additional resource dependencies
    """
    repo_path = get_repo_path(name)
    port = SERVICE_PORTS[name]
    debug_port = DEBUG_PORTS.get(name)

    # Step 1: Local Gradle compilation
    local_resource(
        name + '-compile',
        cmd='cd ' + repo_path + ' && ./gradlew bootJar --parallel --build-cache -x test',
        deps=[
            repo_path + '/src',
            repo_path + '/build.gradle.kts',
        ],
        resource_deps=['service-common-publish'],
        labels=['compile'],
        allow_parallel=True,
        auto_init=True
    )

    # Step 2: Docker build with restart capability
    # Use inline dev Dockerfile that copies pre-built JAR (avoids Maven dependency issues)
    docker_build_with_restart(
        name,
        context=repo_path,
        dockerfile_contents='''
FROM eclipse-temurin:24-jre-alpine
WORKDIR /app
RUN addgroup -g 1001 -S appgroup && adduser -u 1001 -S appuser -G appgroup
COPY build/libs/*.jar app.jar
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE ''' + str(port) + '''
''',
        entrypoint=[
            'java',
            '-jar',
            '/app/app.jar'
        ],
        live_update=[
            sync(repo_path + '/build/libs', '/app'),
        ]
    )

    # Step 3: Load Kubernetes manifests
    k8s_yaml([
        'kubernetes/services/' + name + '/serviceaccount.yaml',
        'kubernetes/services/' + name + '/deployment.yaml',
        'kubernetes/services/' + name + '/service.yaml',
    ])

    # Step 4: Configure resource with port forwards and dependencies
    port_forwards_list = [
        port_forward(port, port, name='HTTP'),
    ]
    if debug_port:
        port_forwards_list.append(port_forward(debug_port, 5005, name='Debug'))

    base_deps = ['postgresql', 'rabbitmq', 'istio-injection'] if name == 'currency-service' else ['postgresql', 'istio-injection'] if name in ['transaction-service', 'permission-service'] else ['istio-injection']

    k8s_resource(
        name,
        port_forwards=port_forwards_list,
        labels=['backend'] if name in ['transaction-service', 'currency-service', 'permission-service'] else ['gateway'],
        resource_deps=[name + '-compile'] + base_deps + deps,
    )

# ============================================================================
# BACKEND MICROSERVICES
# ============================================================================

# Transaction Service
spring_boot_service('transaction-service')

# Currency Service
spring_boot_service('currency-service')

# Permission Service
spring_boot_service('permission-service')

# ============================================================================
# GATEWAY SERVICES
# ============================================================================

# Session Gateway
repo_path = get_repo_path('session-gateway')

local_resource(
    'session-gateway-compile',
    cmd='cd ' + repo_path + ' && ./gradlew bootJar --parallel --build-cache -x test',
    deps=[
        repo_path + '/src',
        repo_path + '/build.gradle.kts',
    ],
    resource_deps=['service-common-publish'],
    labels=['compile'],
    allow_parallel=True
)

# Use inline dev Dockerfile that copies pre-built JAR (avoids Maven dependency issues)
docker_build_with_restart(
    'session-gateway',
    context=repo_path,
    dockerfile_contents='''
FROM eclipse-temurin:24-jre-alpine
WORKDIR /app
RUN addgroup -g 1001 -S appgroup && adduser -u 1001 -S appuser -G appgroup
COPY build/libs/*.jar app.jar
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 8081
''',
    entrypoint=[
        'java',
        '-jar',
        '/app/app.jar'
    ],
    live_update=[
        sync(repo_path + '/build/libs', '/app'),
    ]
)

k8s_yaml([
    'kubernetes/services/session-gateway/serviceaccount.yaml',
    'kubernetes/services/session-gateway/deployment.yaml',
    'kubernetes/services/session-gateway/service.yaml',
    'kubernetes/services/session-gateway/configmap.yaml',
])

k8s_resource(
    'session-gateway',
    port_forwards=[
        port_forward(8081, 8081, name='HTTP'),
        port_forward(5009, 5005, name='Debug'),
    ],
    labels=['gateway'],
    resource_deps=['redis', 'permission-service', 'istio-injection']
)

# ============================================================================
# EXT-AUTHZ SERVICE (Go, HTTP external authorization)
# ============================================================================

docker_build(
    'ext-authz',
    context='ext-authz',
    dockerfile='ext-authz/Dockerfile',
)

k8s_yaml([
    'kubernetes/services/ext-authz/serviceaccount.yaml',
    'kubernetes/services/ext-authz/deployment.yaml',
    'kubernetes/services/ext-authz/service.yaml',
])

k8s_resource(
    'ext-authz',
    port_forwards=[
        port_forward(9002, 9002, name='HTTP'),
        port_forward(8090, 8090, name='Health'),
    ],
    labels=['gateway'],
    resource_deps=['redis', 'istio-injection'],
)

# ============================================================================
# NGINX GATEWAY
# ============================================================================

# Create ConfigMap from NGINX configuration with auto-reload
configmap_create(
    'nginx-gateway-config',
    namespace=DEFAULT_NAMESPACE,
    from_file=['nginx.conf=nginx/nginx.k8s.conf'],
    watch=True
)

configmap_create(
    'nginx-gateway-includes',
    namespace=DEFAULT_NAMESPACE,
    from_file=[
        'backend-headers.conf=nginx/includes/backend-headers.conf',
    ],
    watch=True
)

configmap_create(
    'nginx-gateway-docs',
    namespace=DEFAULT_NAMESPACE,
    from_file=[
        'index.html=docs-aggregator/index.html',
        'openapi.json=docs-aggregator/openapi.json',
        'openapi.yaml=docs-aggregator/openapi.yaml',
    ],
    watch=True
)

k8s_yaml([
    'kubernetes/services/nginx-gateway/serviceaccount.yaml',
    'kubernetes/services/nginx-gateway/deployment.yaml',
    'kubernetes/services/nginx-gateway/service.yaml',
])

k8s_resource(
    'nginx-gateway',
    port_forwards=[
        port_forward(8080, 8080, name='HTTP'),
    ],
    labels=['gateway'],
    resource_deps=['istio-injection']
)

# ============================================================================
# FRONTEND (React/Vite with HMR)
# ============================================================================

frontend_repo = get_repo_path('budget-analyzer-web')

# Use standard Dockerfile for frontend
# If you need live HMR with Vite dev server, create a Dockerfile.dev that runs 'npm run dev'
# instead of building for production
docker_build(
    'budget-analyzer-web',
    context=frontend_repo,
    dockerfile=frontend_repo + '/Dockerfile',
    live_update=[
        # Sync source files for instant HMR
        sync(frontend_repo + '/src', '/app/src'),
        sync(frontend_repo + '/public', '/app/public'),
        sync(frontend_repo + '/index.html', '/app/index.html'),
        # Reinstall dependencies if package.json changes
        run(
            'cd /app && npm install',
            trigger=[frontend_repo + '/package.json', frontend_repo + '/package-lock.json']
        ),
    ]
)

k8s_yaml([
    'kubernetes/services/budget-analyzer-web/serviceaccount.yaml',
    'kubernetes/services/budget-analyzer-web/deployment.yaml',
    'kubernetes/services/budget-analyzer-web/service.yaml',
])

k8s_resource(
    'budget-analyzer-web',
    port_forwards=[
        port_forward(3000, 3000, name='Vite Dev Server'),
    ],
    labels=['frontend'],
    resource_deps=['nginx-gateway', 'istio-injection'],
    links=[
        link('https://app.budgetanalyzer.localhost', 'Application'),
    ]
)

# ============================================================================
# GATEWAY API PREREQUISITES
# ============================================================================

# Gateway API CRDs (must be installed before Istio ingress gateway)
local_resource(
    'gateway-api-crds',
    cmd='kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml',
    labels=['infrastructure'],
)

# ============================================================================
# ISTIO SERVICE MESH
# ============================================================================

# Istio Base CRDs
local_resource(
    'istio-base',
    cmd='''
        helm upgrade --install istio-base istio/base \
            --namespace istio-system \
            --create-namespace \
            --version 1.24.3 \
            --wait
    ''',
    labels=['infrastructure'],
)

# Istio Control Plane
local_resource(
    'istiod',
    cmd='''
        helm upgrade --install istiod istio/istiod \
            --namespace istio-system \
            --version 1.24.3 \
            --values kubernetes/istio/istiod-values.yaml \
            --wait
    ''',
    deps=['kubernetes/istio/istiod-values.yaml'],
    resource_deps=['istio-base'],
    labels=['infrastructure'],
)

# Namespace labeling for sidecar injection and Pod Security Admission
local_resource(
    'istio-injection',
    cmd='''
        kubectl label namespace default istio-injection=enabled --overwrite
        kubectl label namespace default pod-security.kubernetes.io/warn=restricted --overwrite
        kubectl label namespace default pod-security.kubernetes.io/warn-version=v1.32 --overwrite
        kubectl label namespace default pod-security.kubernetes.io/audit=restricted --overwrite
        kubectl label namespace default pod-security.kubernetes.io/audit-version=v1.32 --overwrite
        kubectl label namespace infrastructure istio-injection=disabled --overwrite
        kubectl label namespace infrastructure pod-security.kubernetes.io/warn=baseline --overwrite
        kubectl label namespace infrastructure pod-security.kubernetes.io/warn-version=v1.32 --overwrite
        kubectl label namespace infrastructure pod-security.kubernetes.io/audit=baseline --overwrite
        kubectl label namespace infrastructure pod-security.kubernetes.io/audit-version=v1.32 --overwrite
    ''',
    resource_deps=['istiod'],
    labels=['infrastructure'],
)

# Istio security policies (PeerAuthentication + AuthorizationPolicy)
# Explicitly delete PERMISSIVE PeerAuthentication resources removed in Phase 3 Session 2.
# kubectl apply does not delete resources removed from a multi-document YAML file.
local_resource(
    'istio-security-policies',
    cmd='''
        kubectl delete peerauthentication nginx-gateway-permissive ext-authz-permissive session-gateway-permissive -n default --ignore-not-found
        kubectl apply -f kubernetes/istio/peer-authentication.yaml
        kubectl apply -f kubernetes/istio/authorization-policies.yaml
    ''',
    deps=[
        'kubernetes/istio/peer-authentication.yaml',
        'kubernetes/istio/authorization-policies.yaml',
    ],
    resource_deps=['istiod', 'istio-injection'],
    labels=['infrastructure'],
)

# Kyverno admission controller (Phase 0 scaffold)
local_resource(
    'kyverno',
    cmd='''
        helm repo add kyverno https://kyverno.github.io/kyverno/ --force-update >/dev/null 2>&1
        helm repo update kyverno >/dev/null
        helm upgrade --install kyverno kyverno/kyverno \
            --namespace kyverno \
            --create-namespace \
            --version 3.7.1 \
            --set admissionController.replicas=1 \
            --set backgroundController.replicas=1 \
            --set cleanupController.replicas=1 \
            --set reportsController.replicas=1 \
            --wait
    ''',
    resource_deps=['istio-security-policies'],
    labels=['infrastructure'],
)

local_resource(
    'kyverno-ready',
    cmd='''
        kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=5m
    ''',
    resource_deps=['kyverno'],
    labels=['infrastructure'],
)

local_resource(
    'kyverno-smoke-policy',
    cmd='kubectl apply -f kubernetes/kyverno/smoke-policy.yaml',
    deps=[
        'kubernetes/kyverno/smoke-policy.yaml',
    ],
    resource_deps=['kyverno-ready'],
    labels=['infrastructure'],
)

# ============================================================================
# NETWORK POLICIES (Phase 2 Security Hardening)
# ============================================================================

# Apply deny and allow manifests together — never apply deny without matching allows.
local_resource(
    'network-policies-core',
    cmd='''
        kubectl delete networkpolicy \
            allow-nginx-gateway-ingress-from-envoy \
            allow-ext-authz-ingress-from-envoy \
            allow-session-gateway-ingress-from-envoy \
            -n default --ignore-not-found
        kubectl apply -f kubernetes/network-policies/default-deny.yaml
        kubectl apply -f kubernetes/network-policies/default-allow.yaml
        kubectl apply -f kubernetes/network-policies/infrastructure-deny.yaml
        kubectl apply -f kubernetes/network-policies/infrastructure-allow.yaml
    ''',
    deps=[
        'kubernetes/network-policies/default-deny.yaml',
        'kubernetes/network-policies/default-allow.yaml',
        'kubernetes/network-policies/infrastructure-deny.yaml',
        'kubernetes/network-policies/infrastructure-allow.yaml',
    ],
    resource_deps=['istio-injection'],
    labels=['infrastructure'],
)

local_resource(
    'istio-ingress-network-policies',
    cmd='''
        kubectl apply -f kubernetes/network-policies/istio-ingress-deny.yaml
        kubectl apply -f kubernetes/network-policies/istio-ingress-allow.yaml
    ''',
    deps=[
        'kubernetes/network-policies/istio-ingress-deny.yaml',
        'kubernetes/network-policies/istio-ingress-allow.yaml',
    ],
    resource_deps=['istio-ingress-config'],
    labels=['infrastructure'],
)

# ============================================================================
# ISTIO INGRESS GATEWAY
# ============================================================================

# Wildcard TLS certificate for *.budgetanalyzer.localhost (using mkcert)
# This runs on the HOST machine to install the CA in browser trust stores
local_resource(
    'mkcert-tls-secret',
    cmd='./scripts/dev/setup-k8s-tls.sh',
    labels=['infrastructure'],
)

# One-time cleanup of Envoy Gateway resources from existing clusters.
# No-op on fresh clusters. Uses explicit resource names since the Envoy manifest files are deleted.
local_resource(
    'envoy-gateway-cleanup',
    cmd='''
        helm uninstall envoy-gateway -n envoy-gateway-system --ignore-not-found || true
        kubectl delete gateway ingress-gateway -n default --ignore-not-found || true
        kubectl delete clienttrafficpolicy xff-config -n default --ignore-not-found || true
        kubectl delete securitypolicy ext-authz-policy -n default --ignore-not-found || true
        kubectl delete gatewayclass envoy-proxy --ignore-not-found || true
        kubectl delete envoyproxy kind-proxy-config -n envoy-gateway-system --ignore-not-found || true
    ''',
    labels=['infrastructure'],
)

# Istio ingress gateway — auto-provisioned from the Gateway API resource.
# Applies the namespace, TLS ReferenceGrant, and Gateway, then patches NodePort to 30443.
local_resource(
    'istio-ingress-config',
    cmd='''
        kubectl apply -f kubernetes/istio/ingress-namespace.yaml
        kubectl apply -f kubernetes/istio/tls-reference-grant.yaml
        kubectl apply -f kubernetes/istio/istio-gateway.yaml
        kubectl wait --for=condition=Programmed gateway/istio-ingress-gateway -n istio-ingress --timeout=120s
        kubectl patch svc -n istio-ingress istio-ingress-gateway-istio --type=json \
            -p='[{"op":"replace","path":"/spec/ports/1/nodePort","value":30443}]'
    ''',
    deps=[
        'kubernetes/istio/ingress-namespace.yaml',
        'kubernetes/istio/tls-reference-grant.yaml',
        'kubernetes/istio/istio-gateway.yaml',
    ],
    resource_deps=['envoy-gateway-cleanup', 'istiod', 'gateway-api-crds', 'mkcert-tls-secret'],
    labels=['gateway'],
)

# HTTPRoutes and ext-authz AuthorizationPolicy
local_resource(
    'istio-ingress-routes',
    cmd='''
        kubectl apply -f kubernetes/gateway/auth-httproute.yaml
        kubectl apply -f kubernetes/gateway/api-httproute.yaml
        kubectl apply -f kubernetes/gateway/app-httproute.yaml
        kubectl apply -f kubernetes/istio/ext-authz-policy.yaml
        kubectl apply -f kubernetes/istio/ingress-rate-limit.yaml
    ''',
    deps=[
        'kubernetes/gateway/auth-httproute.yaml',
        'kubernetes/gateway/api-httproute.yaml',
        'kubernetes/gateway/app-httproute.yaml',
        'kubernetes/istio/ext-authz-policy.yaml',
        'kubernetes/istio/ingress-rate-limit.yaml',
    ],
    resource_deps=['istio-ingress-config', 'istio-ingress-network-policies', 'ext-authz', 'nginx-gateway'],
    labels=['gateway'],
)

# ============================================================================
# ISTIO EGRESS GATEWAY
# ============================================================================

# Egress namespace (source of truth for labels — not managed by istio-injection)
local_resource(
    'istio-egress-namespace',
    cmd='kubectl apply -f kubernetes/istio/egress-namespace.yaml',
    deps=['kubernetes/istio/egress-namespace.yaml'],
    resource_deps=['istiod'],
    labels=['infrastructure'],
)

# Egress gateway rendered from istio/gateway 1.24.3 and checked into the repo.
# The upstream chart rejects the required service.type input under Helm v3.20.1,
# so Tilt applies the vendored manifest directly instead of depending on the
# runtime schema bypass.
local_resource(
    'istio-egress-gateway',
    cmd='''
        helm uninstall istio-egress-gateway -n istio-egress --ignore-not-found --wait || true
        kubectl apply -f kubernetes/istio/egress-gateway.yaml
        kubectl rollout status deployment/istio-egress-gateway -n istio-egress --timeout=120s
    ''',
    deps=['kubernetes/istio/egress-gateway.yaml'],
    resource_deps=['istio-egress-namespace'],
    labels=['infrastructure'],
)

# ServiceEntries and egress routing (Gateway, DestinationRule, VirtualServices)
local_resource(
    'istio-egress-config',
    cmd='''
        kubectl apply -f kubernetes/istio/egress-service-entries.yaml
        kubectl apply -f kubernetes/istio/egress-routing.yaml
    ''',
    deps=[
        'kubernetes/istio/egress-service-entries.yaml',
        'kubernetes/istio/egress-routing.yaml',
    ],
    resource_deps=['istio-egress-gateway', 'istiod'],
    labels=['infrastructure'],
)

# Egress network policies
local_resource(
    'istio-egress-network-policies',
    cmd='''
        kubectl apply -f kubernetes/network-policies/istio-egress-deny.yaml
        kubectl apply -f kubernetes/network-policies/istio-egress-allow.yaml
    ''',
    deps=[
        'kubernetes/network-policies/istio-egress-deny.yaml',
        'kubernetes/network-policies/istio-egress-allow.yaml',
    ],
    resource_deps=['istio-egress-config'],
    labels=['infrastructure'],
)

# ============================================================================
# UI ENHANCEMENTS
# ============================================================================

# Custom buttons for common operations
cmd_button(
    'rebuild-all-backend',
    argv=['bash', '-c', 'cd ' + WORKSPACE + ' && for d in transaction-service currency-service permission-service session-gateway; do (cd $d && ./gradlew bootJar --parallel) & done; wait'],
    resource='transaction-service',
    icon_name='build',
    text='Rebuild All Backend'
)

cmd_button(
    'run-tests',
    argv=['./gradlew', 'test'],
    resource='transaction-service-compile',
    icon_name='science',
    text='Run Tests',
    location=location.RESOURCE
)
