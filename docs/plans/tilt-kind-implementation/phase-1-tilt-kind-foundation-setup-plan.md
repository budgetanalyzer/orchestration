# Phase 1: Tilt + Kind Foundation Setup Implementation Plan

This document provides a step-by-step guide for completing Phase 1 of the Tilt and Kind deployment. Each step includes specific commands and verification checks to ensure the foundation is set up correctly for the subsequent phases.

---

## Step 1: Create the Kind Cluster

**Objective:** To provision a local Kubernetes cluster using Kind, configured to forward host ports 80 and 443 to the cluster's ingress layer.

### 1.1. Define the Cluster Configuration

**Action:** Create a file named `kind-cluster-config.yaml` in the root of this repository. This file instructs Kind to map the necessary ports.

```bash
cat <<EOF > kind-cluster-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
```

### 1.2. Provision the Cluster

**Action:** Use the Kind CLI to create the cluster from the configuration file.

```bash
kind create cluster --config kind-cluster-config.yaml
```

### 1.3. Verify Cluster Creation

**Action:** Confirm that the Kubernetes cluster is running and accessible.

```bash
kubectl cluster-info --context kind-kind
```

**Expected Output:** The command should return the address of the Kubernetes control plane.

---

## Step 2: Install Cert-Manager

**Objective:** To install cert-manager, which will automate the management of TLS certificates within the cluster. We will then create a `ClusterIssuer` to generate self-signed certificates for local development.

### 2.1. Install Cert-Manager using Helm

**Action:** Add the Jetstack Helm repository and install the `cert-manager` chart. We pin the version for reproducibility.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.2 \
  --set installCRDs=true
```

### 2.2. Verify Cert-Manager Installation

**Action:** Wait for the cert-manager pods to be in the `Running` state.

```bash
kubectl get pods --namespace cert-manager
```

**Expected Output:** You should see three running pods: `cert-manager-`, `cert-manager-cainjector-`, and `cert-manager-webhook-`. It may take a minute for them to start.

### 2.3. Create a Self-Signed ClusterIssuer

**Action:** Create a Kubernetes manifest for the `ClusterIssuer` and apply it. This issuer will generate trusted certificates for our local services.

```bash
cat <<EOF > self-signed-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
EOF

kubectl apply -f self-signed-issuer.yaml
```

### 2.4. Verify the ClusterIssuer

**Action:** Check that the `ClusterIssuer` has been created and is ready.

```bash
kubectl get clusterissuer selfsigned-issuer
```

**Expected Output:** The issuer should be listed with a `READY` status of `True`.

---

## Step 3: Install Envoy Gateway

**Objective:** To install Envoy Gateway, which will serve as our Gateway API implementation and manage all ingress traffic.

### 3.1. Install Gateway API CRDs and Envoy Gateway

**Action:** First, apply the Gateway API Custom Resource Definitions (CRDs), then install Envoy Gateway using its official Helm chart.

```bash
# 1. Install Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 2. Install Envoy Gateway
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.0.0 \
  -n envoy-gateway-system \
  --create-namespace
```

### 3.2. Verify Envoy Gateway Installation

**Action:** Check that the Envoy Gateway pods are running.

```bash
kubectl get pods -n envoy-gateway-system
```

**Expected Output:** You should see at least one `envoy-gateway-` pod in a `Running` state.

---

## Step 4: Generate Wildcard TLS Certificate

**Objective:** To create a wildcard TLS certificate for `*.budgetanalyzer.localhost` using the `selfsigned-issuer`.

### 4.1. Create the Certificate Manifest

**Action:** Define and apply a `Certificate` resource manifest. This will instruct cert-manager to generate the certificate and store it in a Kubernetes secret.

```bash
cat <<EOF > wildcard-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: budgetanalyzer-localhost-wildcard-tls
  namespace: default
spec:
  isCA: false
  privateKey:
    rotationPolicy: Always
  secretName: budgetanalyzer-localhost-wildcard-tls
  dnsNames:
  - "*.budgetanalyzer.localhost"
  issuerRef:
    name: selfsigned-issuer
    kind: ClusterIssuer
EOF

kubectl apply -f wildcard-certificate.yaml
```

### 4.2. Verify Certificate Creation

**Action:** Confirm that the certificate was issued successfully and the corresponding secret was created.

```bash
# Check certificate status
kubectl get certificate budgetanalyzer-localhost-wildcard-tls -n default

# Check for the TLS secret
kubectl get secret budgetanalyzer-localhost-wildcard-tls -n default
```

**Expected Output:** The certificate should have a `READY` status of `True`, and the secret should be listed.

---

## Step 5: Configure Local DNS

**Objective:** To ensure that your local machine resolves `app.budgetanalyzer.localhost` and `api.budgetanalyzer.localhost` to `127.0.0.1`.

### 5.1. Update Hosts File

**Action:** This step is manual and requires administrator privileges. You must add the following lines to your system's `hosts` file (e.g., `/etc/hosts` on Linux/macOS).

```
127.0.0.1 app.budgetanalyzer.localhost
127.0.0.1 api.budgetanalyzer.localhost
```
**Note:** I cannot perform this action for you. Please edit the file yourself.

### 5.2. Verify DNS Resolution

**Action:** Use a command like `ping` to test that the domains resolve correctly.

```bash
ping -c 1 app.budgetanalyzer.localhost
```

**Expected Output:** The command should show that it is pinging `127.0.0.1`.

