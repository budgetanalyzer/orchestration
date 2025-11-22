# Gateway API Tiltfile Fix Plan

**Date:** November 22, 2025
**Status:** Ready for Implementation

---

## Problem Statement

The Tiltfile applies Gateway API resources (Gateway, HTTPRoutes) but **never installs the required controllers**:
- cert-manager (for TLS certificates)
- Envoy Gateway (the controller that processes Gateway API resources)
- Gateway API CRDs

Without Envoy Gateway running, there's nothing listening on port 443 - hence `https://app.budgetanalyzer.localhost/` fails to connect even though:
- All Tilt services show green
- DNS resolves correctly (ping returns 127.0.0.1)
- Kind cluster has port mappings configured

---

## Architecture Clarification

### Old Docker Compose Design (being replaced)
```
NGINX (443/SSL) → Session Gateway (8081) → NGINX (8080) → Services
```
This was a workaround because we couldn't terminate SSL on two different ports.

### New Kubernetes Design (target)
```
Browser → Envoy Gateway (443/SSL termination) → Session Gateway (8081) → NGINX → Backend Services
```

**Key principle:** Envoy Gateway only replaces SSL termination. NGINX remains in the path for:
- JWT validation via Token Validation Service
- Resource-based routing to backend services
- Rate limiting and other middleware

### M2M API Traffic
```
API Client → Envoy Gateway (443/SSL) → NGINX → Backend Services
```
NGINX handles JWT validation for all traffic (both browser via Session Gateway and M2M direct).

---

## Solution

### Phase 1: Update Tiltfile to Install Prerequisites

Add the following to the Tiltfile **before** applying Gateway API resources:

#### 1.1 Install Gateway API CRDs
```python
# Gateway API CRDs (must be installed before Envoy Gateway)
local_resource(
    'gateway-api-crds',
    cmd='kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml',
    labels=['infrastructure']
)
```

#### 1.2 Install cert-manager
```python
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
    labels=['infrastructure']
)
```

#### 1.3 Create Self-Signed ClusterIssuer
```python
# Self-signed issuer for local development certificates
k8s_yaml('kubernetes/gateway/cluster-issuer.yaml')
k8s_resource(
    'selfsigned-cluster-issuer',
    resource_deps=['cert-manager'],
    labels=['infrastructure']
)
```

#### 1.4 Install Envoy Gateway
```python
# Envoy Gateway - the Gateway API controller
local_resource(
    'envoy-gateway',
    cmd='''
        helm repo add envoy-gateway https://charts.envoygateway.io --force-update
        helm upgrade --install envoy-gateway envoy-gateway/gateway-helm \
            --namespace envoy-gateway-system \
            --create-namespace \
            --version v1.2.0 \
            --wait
    ''',
    resource_deps=['gateway-api-crds'],
    labels=['infrastructure']
)
```

#### 1.5 Apply Gateway API Resources (with dependencies)
```python
# GatewayClass and EnvoyProxy configuration
k8s_yaml('kubernetes/gateway/envoy-proxy-gatewayclass.yaml')
k8s_yaml('kubernetes/gateway/envoy-proxy-config.yaml')

# Gateway and HTTPRoutes
k8s_yaml('kubernetes/gateway/gateway.yaml')
k8s_yaml('kubernetes/gateway/app-httproute.yaml')
k8s_yaml('kubernetes/gateway/api-httproute.yaml')

# Set dependencies
k8s_resource(
    'envoy-gateway',  # The gateway resource
    resource_deps=['envoy-gateway', 'selfsigned-cluster-issuer'],
    labels=['gateway']
)
```

### Phase 2: Verify Gateway API Resources

Ensure these files exist and are correctly configured:

1. **`kubernetes/gateway/cluster-issuer.yaml`** (may need to create):
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-cluster-issuer
spec:
  selfSigned: {}
```

2. **`kubernetes/gateway/envoy-proxy-gatewayclass.yaml`** - verify it's applied
3. **`kubernetes/gateway/envoy-proxy-config.yaml`** - verify NodePort 30443 config
4. **`kubernetes/gateway/gateway.yaml`** - verify TLS certificate reference

---

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `/workspace/orchestration/Tiltfile` | Modify | Add cert-manager and Envoy Gateway installation |
| `/workspace/orchestration/kubernetes/gateway/cluster-issuer.yaml` | Create if missing | Self-signed ClusterIssuer |

---

## Expected Result

After implementation:
1. `tilt up` installs all prerequisites automatically
2. Envoy Gateway listens on port 443 (mapped from NodePort 30443)
3. `https://app.budgetanalyzer.localhost/` connects successfully
4. Traffic flows: Browser → Envoy Gateway → Session Gateway → NGINX → Backend Services
5. NGINX handles JWT validation via Token Validation Service for all traffic

---

## Testing

1. Run `tilt up` and wait for all resources to be green
2. Verify Envoy Gateway is running: `kubectl get pods -n envoy-gateway-system`
3. Verify Gateway is programmed: `kubectl get gateway -A`
4. Test connection: `curl -v https://app.budgetanalyzer.localhost/`
5. Check for valid TLS certificate in browser

---

## Rollback

If issues occur:
1. `tilt down` to clean up
2. Delete namespaces: `kubectl delete ns cert-manager envoy-gateway-system`
3. Revert Tiltfile changes
4. Restart with `tilt up`
