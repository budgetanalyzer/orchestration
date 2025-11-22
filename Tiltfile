# ============================================================================
# Budget Analyzer - Tiltfile
# Phase 5: Complete Local Development Environment with Live Reload
# ============================================================================

# Load extensions
load('ext://restart_process', 'docker_build_with_restart')
load('ext://uibutton', 'cmd_button', 'location')
load('ext://configmap', 'configmap_create')

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
        port_forward(5672, 5672, name='AMQP'),
        port_forward(15672, 15672, name='Management UI'),
    ],
    labels=['infrastructure'],
)

# ============================================================================
# SECRETS
# ============================================================================

# Helper function to encode values to base64
def encode_secret_data(data):
    """Encode dictionary values to base64 for Kubernetes secrets."""
    encoded = {}
    for k, v in data.items():
        # Base64 encode the value
        encoded[k] = str(local('echo -n "' + v + '" | base64 -w0', quiet=True)).strip()
    return encoded

# PostgreSQL credentials
pg_data = encode_secret_data({
    'username': 'budget_analyzer',
    'password': 'budget_analyzer',
    'budget-analyzer-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/budget_analyzer',
    'currency-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/currency',
    'permission-url': 'jdbc:postgresql://postgresql.' + INFRA_NAMESPACE + ':5432/permission',
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  username: ''' + pg_data['username'] + '''
  password: ''' + pg_data['password'] + '''
  budget-analyzer-url: ''' + pg_data['budget-analyzer-url'] + '''
  currency-url: ''' + pg_data['currency-url'] + '''
  permission-url: ''' + pg_data['permission-url'] + '''
'''))

# Redis credentials
redis_data = encode_secret_data({
    'host': 'redis.' + INFRA_NAMESPACE,
    'port': '6379',
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: redis-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  host: ''' + redis_data['host'] + '''
  port: ''' + redis_data['port'] + '''
'''))

# RabbitMQ credentials
rabbitmq_data = encode_secret_data({
    'host': 'rabbitmq.' + INFRA_NAMESPACE,
    'amqp-port': '5672',
    'username': 'guest',
    'password': 'guest',
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: rabbitmq-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  host: ''' + rabbitmq_data['host'] + '''
  amqp-port: ''' + rabbitmq_data['amqp-port'] + '''
  username: ''' + rabbitmq_data['username'] + '''
  password: ''' + rabbitmq_data['password'] + '''
'''))

# Auth0 credentials for Session Gateway
# NOTE: Replace these placeholder values with your actual Auth0 credentials
auth0_data = encode_secret_data({
    'client-id': os.getenv('AUTH0_CLIENT_ID', 'your-auth0-client-id'),
    'client-secret': os.getenv('AUTH0_CLIENT_SECRET', 'your-auth0-client-secret'),
    'issuer-uri': os.getenv('AUTH0_ISSUER_URI', 'https://dev-gcz1r8453xzz0317.us.auth0.com/'),
})

k8s_yaml(blob('''
apiVersion: v1
kind: Secret
metadata:
  name: auth0-credentials
  namespace: ''' + DEFAULT_NAMESPACE + '''
type: Opaque
data:
  client-id: ''' + auth0_data['client-id'] + '''
  client-secret: ''' + auth0_data['client-secret'] + '''
  issuer-uri: ''' + auth0_data['issuer-uri'] + '''
'''))

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
            '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005',
            '-jar',
            '/app/app.jar'
        ],
        live_update=[
            sync(repo_path + '/build/libs', '/app'),
        ]
    )

    # Step 3: Load Kubernetes manifests
    k8s_yaml([
        'kubernetes/services/' + name + '/deployment.yaml',
        'kubernetes/services/' + name + '/service.yaml',
    ])

    # Step 4: Configure resource with port forwards and dependencies
    port_forwards_list = [
        port_forward(port, port, name='HTTP'),
    ]
    if debug_port:
        port_forwards_list.append(port_forward(debug_port, 5005, name='Debug'))

    base_deps = ['postgresql', 'rabbitmq'] if name in ['transaction-service', 'currency-service', 'permission-service'] else []

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

# Token Validation Service
spring_boot_service('token-validation-service', deps=['redis'])

# Session Gateway
repo_path = get_repo_path('session-gateway')

local_resource(
    'session-gateway-compile',
    cmd='cd ' + repo_path + ' && ./gradlew bootJar --parallel --build-cache -x test',
    deps=[
        repo_path + '/src',
        repo_path + '/build.gradle.kts',
    ],
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
        '-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005',
        '-jar',
        '/app/app.jar'
    ],
    live_update=[
        sync(repo_path + '/build/libs', '/app'),
    ]
)

k8s_yaml([
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
    resource_deps=['redis', 'token-validation-service']
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
        'api-protection.conf=nginx/includes/api-protection.conf',
        'admin-api-protection.conf=nginx/includes/admin-api-protection.conf',
        'backend-headers.conf=nginx/includes/backend-headers.conf',
    ],
    watch=True
)

k8s_yaml([
    'kubernetes/services/nginx-gateway/deployment.yaml',
    'kubernetes/services/nginx-gateway/service.yaml',
])

k8s_resource(
    'nginx-gateway',
    port_forwards=[
        port_forward(8080, 8080, name='HTTP'),
    ],
    labels=['gateway'],
    resource_deps=['session-gateway', 'token-validation-service']
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
    'kubernetes/services/budget-analyzer-web/deployment.yaml',
    'kubernetes/services/budget-analyzer-web/service.yaml',
])

k8s_resource(
    'budget-analyzer-web',
    port_forwards=[
        port_forward(3000, 3000, name='Vite Dev Server'),
    ],
    labels=['frontend'],
    resource_deps=['nginx-gateway'],
    links=[
        link('https://app.budgetanalyzer.localhost', 'Application'),
    ]
)

# ============================================================================
# GATEWAY API PREREQUISITES
# ============================================================================

# Gateway API CRDs (must be installed before Envoy Gateway)
local_resource(
    'gateway-api-crds',
    cmd='kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml',
    labels=['infrastructure'],
)

# cert-manager for TLS certificate management
local_resource(
    'cert-manager',
    cmd='''
        helm repo add jetstack https://charts.jetstack.io --force-update
        helm upgrade --install cert-manager jetstack/cert-manager \
            --namespace cert-manager \
            --create-namespace \
            --version v1.16.1 \
            --set crds.enabled=true \
            --wait
    ''',
    resource_deps=['gateway-api-crds'],
    labels=['infrastructure'],
)

# Self-signed ClusterIssuer for local development certificates
local_resource(
    'cluster-issuer',
    cmd='kubectl apply -f kubernetes/gateway/cluster-issuer.yaml',
    resource_deps=['cert-manager'],
    labels=['infrastructure'],
)

# Envoy Gateway - the Gateway API controller
local_resource(
    'envoy-gateway',
    cmd='''
        helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
            --namespace envoy-gateway-system \
            --create-namespace \
            --version v1.2.0 \
            --wait
    ''',
    resource_deps=['gateway-api-crds'],
    labels=['infrastructure'],
)

# ============================================================================
# GATEWAY API RESOURCES
# ============================================================================

# EnvoyProxy configuration (needs envoy-gateway-system namespace from helm chart)
local_resource(
    'envoy-proxy-config',
    cmd='kubectl apply -f kubernetes/gateway/envoy-proxy-config.yaml',
    resource_deps=['envoy-gateway'],
    labels=['infrastructure'],
)

# GatewayClass (needs EnvoyProxy config)
local_resource(
    'gateway-class',
    cmd='kubectl apply -f kubernetes/gateway/envoy-proxy-gatewayclass.yaml',
    resource_deps=['envoy-proxy-config'],
    labels=['infrastructure'],
)

# Wildcard TLS certificate for *.budgetanalyzer.localhost
local_resource(
    'wildcard-certificate',
    cmd='kubectl apply -f wildcard-certificate.yaml',
    resource_deps=['cluster-issuer'],
    labels=['infrastructure'],
)

# Gateway and HTTPRoutes
local_resource(
    'ingress-gateway',
    cmd='''
        kubectl apply -f kubernetes/gateway/gateway.yaml
        kubectl apply -f kubernetes/gateway/api-httproute.yaml
        kubectl apply -f kubernetes/gateway/app-httproute.yaml
    ''',
    resource_deps=['gateway-class', 'wildcard-certificate'],
    labels=['gateway'],
)

# ============================================================================
# UI ENHANCEMENTS
# ============================================================================

# Custom buttons for common operations
cmd_button(
    'rebuild-all-backend',
    argv=['bash', '-c', 'cd ' + WORKSPACE + ' && for d in transaction-service currency-service permission-service; do (cd $d && ./gradlew bootJar --parallel) & done; wait'],
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

cmd_button(
    'db-migrate',
    argv=['./gradlew', 'flywayMigrate'],
    resource='transaction-service-compile',
    icon_name='storage',
    text='Run Migrations',
    location=location.RESOURCE
)

# ============================================================================
# LOCAL RESOURCES FOR DEVELOPMENT TASKS
# ============================================================================

# Database migration runner
local_resource(
    'run-all-migrations',
    cmd='cd ' + get_repo_path('transaction-service') + ' && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/budget_analyzer -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer && ' +
        'cd ' + get_repo_path('currency-service') + ' && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/currency -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer && ' +
        'cd ' + get_repo_path('permission-service') + ' && ./gradlew flywayMigrate -Pflyway.url=jdbc:postgresql://localhost:5432/permission -Pflyway.user=budget_analyzer -Pflyway.password=budget_analyzer',
    labels=['database'],
    resource_deps=['postgresql'],
    trigger_mode=TRIGGER_MODE_MANUAL,
    auto_init=False
)

# Kind image loader (for manual reloads)
local_resource(
    'load-images-to-kind',
    cmd='''
        for img in transaction-service currency-service permission-service token-validation-service session-gateway budget-analyzer-web; do
            kind load docker-image $img:latest 2>/dev/null || true
        done
    ''',
    labels=['setup'],
    trigger_mode=TRIGGER_MODE_MANUAL,
    auto_init=False
)
