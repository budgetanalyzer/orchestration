# Bitnami Image Migration Plan

## Problem

Since August 2025, Bitnami restricted free access to their container images. Our Helm-based infrastructure (RabbitMQ, PostgreSQL, Redis) uses Bitnami charts that now fail to pull images.

**Current workaround**: Using official images with `global.security.allowInsecureImages: true` - this is a hack and may cause runtime issues due to path/script incompatibilities.

## Recommended Solution

Replace Bitnami Helm charts with raw Kubernetes manifests using official images. This approach:
- Uses official, always-available images
- Simpler to understand and debug
- Better aligns with production parity (we control the exact config)
- No dependency on third-party chart maintenance

## Implementation Steps

### 1. RabbitMQ Migration

**Current**: `helm_resource` with `bitnami/rabbitmq`

**Target**: `k8s_yaml` with StatefulSet using `rabbitmq:3.13-management`

Files to create:
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `kubernetes/infrastructure/rabbitmq/service.yaml`
- `kubernetes/infrastructure/rabbitmq/configmap.yaml` (for rabbitmq.conf)

Key configuration:
- Enable management plugin
- Set guest/guest credentials (dev only)
- 1Gi persistent volume
- Ports: 5672 (AMQP), 15672 (management)

### 2. PostgreSQL Migration

**Current**: `helm_resource` with `bitnami/postgresql`

**Target**: `k8s_yaml` with StatefulSet using `postgres:16-alpine`

Files to create:
- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `kubernetes/infrastructure/postgresql/service.yaml`

Key configuration:
- Init script for creating databases
- Credentials from docker-compose.yml parity
- 1Gi persistent volume
- Port: 5432

### 3. Redis Migration

**Current**: `helm_resource` with `bitnami/redis`

**Target**: `k8s_yaml` with Deployment using `redis:7-alpine`

Files to create:
- `kubernetes/infrastructure/redis/deployment.yaml`
- `kubernetes/infrastructure/redis/service.yaml`

Key configuration:
- No persistence needed for dev (session cache)
- Port: 6379

### 4. Update Tiltfile

Replace `helm_resource` calls with `k8s_yaml`:

```python
# Before
helm_resource('rabbitmq', 'bitnami/rabbitmq', ...)

# After
k8s_yaml('kubernetes/infrastructure/rabbitmq/')
k8s_resource('rabbitmq', port_forwards=['5672:5672', '15672:15672'])
```

### 5. Cleanup

- Remove `kubernetes/infrastructure/values/` directory
- Remove Helm repo setup from prerequisites script
- Update documentation

## Priority

**High** - Current hack may cause runtime failures at any time.

## Estimated Effort

~2 hours for all three services.
