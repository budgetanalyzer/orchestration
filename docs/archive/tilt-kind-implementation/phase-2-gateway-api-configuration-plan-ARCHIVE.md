# Phase 2: Gateway API Configuration Implementation Plan

This document provides a step-by-step guide for completing Phase 2 of the Tilt and Kind deployment. The goal is to configure the core routing rules that direct traffic from the public-facing hostnames to the correct internal services.

---

## Step 1: Create Placeholder Services

**Objective:** To create placeholder Kubernetes `Service` objects for `session-gateway` and `nginx-gateway`. The `HTTPRoute` resources we create in the next steps need to point to valid backend services to become "Accepted". We will deploy the actual applications in a later phase.

### 1.1. Define Placeholder Service Manifest

**Action:** Create a file named `placeholder-services.yaml` that defines the two services. We will place this and all subsequent Kubernetes manifests in a new `kubernetes/` directory to keep the project organized.

```bash
mkdir -p kubernetes/placeholders

cat <<EOF > kubernetes/placeholders/placeholder-services.yaml
apiVersion: v1
kind: Service
metadata:
  name: session-gateway
spec:
  ports:
  - port: 80
    targetPort: 8081
  selector:
    app: session-gateway-placeholder # Dummy selector for now
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-gateway
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: nginx-gateway-placeholder # Dummy selector for now
EOF
```

### 1.2. Apply the Manifest

**Action:** Apply the manifest to create the services in the `default` namespace.

```bash
kubectl apply -f kubernetes/placeholders/placeholder-services.yaml
```

### 1.3. Verify Service Creation

**Action:** Confirm that the services have been created successfully.

```bash
kubectl get svc session-gateway nginx-gateway
```

**Expected Output:** The command should list both services.

---

## Step 2: Create the Gateway Resource

**Objective:** To define the main `Gateway` resource. This tells the Envoy Gateway which ports to listen on, what TLS certificate to use, and which hostnames to handle.

### 2.1. Define the Gateway Manifest

**Action:** Create a file named `gateway.yaml` in a new `kubernetes/gateway` directory. This manifest defines our primary entry point.

```bash
mkdir -p kubernetes/gateway

cat <<EOF > kubernetes/gateway/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: budget-analyzer-gateway
  namespace: default
spec:
  gatewayClassName: envoy-proxy
  listeners:
  - name: https
    hostname: "*.budgetanalyzer.localhost"
    port: 443
    protocol: HTTPS
    tls:
      mode: Terminate
      certificateRefs:
      - name: budgetanalyzer-localhost-wildcard-tls
    allowedRoutes:
      namespaces:
        from: Same
EOF
```

### 2.2. Apply the Manifest

**Action:** Apply the manifest to create the `Gateway`.

```bash
kubectl apply -f kubernetes/gateway/gateway.yaml
```

### 2.3. Verify the Gateway

**Action:** Check that the `Gateway` has been created and is in a `Ready` state. This may take a minute as Envoy provisions a load balancer service.

```bash
kubectl get gateway budget-analyzer-gateway
```

**Expected Output:** The `READY` status should eventually become `True`.

---

## Step 3: Create the `app` HTTPRoute

**Objective:** To create the routing rule that forwards all traffic for `app.budgetanalyzer.localhost` to our placeholder `session-gateway` service.

### 3.1. Define the `app` HTTPRoute Manifest

**Action:** Create a file named `app-httproute.yaml` in the `kubernetes/gateway` directory.

```bash
cat <<EOF > kubernetes/gateway/app-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
  namespace: default
spec:
  parentRefs:
  - name: budget-analyzer-gateway
  hostnames:
  - "app.budgetanalyzer.localhost"
  rules:
  - backendRefs:
    - name: session-gateway
      port: 80
EOF
```

### 3.2. Apply the Manifest

**Action:** Apply the manifest to create the route.

```bash
kubectl apply -f kubernetes/gateway/app-httproute.yaml
```

### 3.3. Verify the HTTPRoute

**Action:** Check that the `HTTPRoute` has been created and is accepted by the parent `Gateway`.

```bash
kubectl get httproute app-route
```

**Expected Output:** The `ACCEPTED` status should be `True`.

---

## Step 4: Create the `api` HTTPRoute

**Objective:** To create the routing rule that forwards all traffic for `api.budgetanalyzer.localhost` to our placeholder `nginx-gateway` service.

### 4.1. Define the `api` HTTPRoute Manifest

**Action:** Create a file named `api-httproute.yaml` in the `kubernetes/gateway` directory.

```bash
cat <<EOF > kubernetes/gateway/api-httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: default
spec:
  parentRefs:
  - name: budget-analyzer-gateway
  hostnames:
  - "api.budgetanalyzer.localhost"
  rules:
  - backendRefs:
    - name: nginx-gateway
      port: 80
EOF
```

### 4.2. Apply the Manifest

**Action:** Apply the manifest to create the route.

```bash
kubectl apply -f kubernetes/gateway/api-httproute.yaml
```

### 4.3. Verify the HTTPRoute

**Action:** Check that the `HTTPRoute` has been created and is accepted by the parent `Gateway`.

```bash
kubectl get httproute api-route
```

**Expected Output:** The `ACCEPTED` status should be `True`.
