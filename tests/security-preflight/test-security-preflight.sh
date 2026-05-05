#!/bin/bash

# test-security-preflight.sh - Runs inside test container to validate runtime security preconditions.

set -euo pipefail

REPOS_DIR="/repos"
ORCHESTRATION_DIR="$REPOS_DIR/orchestration"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
    echo -e "${BLUE}▶${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_error "Missing required command: $1"
        exit 1
    fi
}

print_step "Checking required commands"
for cmd in docker kind kubectl helm; do
    require_cmd "$cmd"
done
print_success "Required commands are available"

print_step "Checking Docker daemon access"
docker info >/dev/null
print_success "Docker daemon is accessible"

print_step "Creating fresh Kind cluster"
kind delete cluster --name kind >/dev/null 2>&1 || true

KIND_CONFIG="$ORCHESTRATION_DIR/tests/setup-flow/kind-cluster-test-config.yaml"
if [ -f "$REPOS_DIR/kind-cluster-test-config.yaml" ]; then
    KIND_CONFIG="$REPOS_DIR/kind-cluster-test-config.yaml"
fi

kind create cluster --config "$KIND_CONFIG" >/dev/null
kubectl config use-context kind-kind >/dev/null

# DinD needs kubeconfig endpoint rewrite away from the host-only localhost
# address emitted by Kind.
if [ -n "${DOCKER_HOST:-}" ]; then
    API_PORT=$(kubectl config view -o jsonpath='{.clusters[?(@.name=="kind-kind")].cluster.server}' | sed 's/.*://')
    DOCKER_ENDPOINT="${DOCKER_HOST#tcp://}"
    DOCKER_ENDPOINT_HOST="${DOCKER_ENDPOINT%%:*}"
    kubectl config set-cluster kind-kind --server="https://${DOCKER_ENDPOINT_HOST}:${API_PORT}" --insecure-skip-tls-verify=true >/dev/null
fi

kubectl get nodes >/dev/null
print_success "Kind cluster is ready"

print_step "Installing Calico"
"$ORCHESTRATION_DIR/scripts/bootstrap/install-calico.sh"
print_success "Calico is installed"

print_step "Installing Gateway API CRDs"
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml >/dev/null
print_success "Gateway API CRDs installed"

print_step "Installing Envoy Gateway"
helm upgrade --install envoy-gateway oci://docker.io/envoyproxy/gateway-helm \
    --namespace envoy-gateway-system \
    --create-namespace \
    --version v1.2.1 \
    --wait >/dev/null
print_success "Envoy Gateway installed"

print_step "Installing Istio base + istiod"
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
helm repo update istio >/dev/null

helm upgrade --install istio-base istio/base \
    --namespace istio-system \
    --create-namespace \
    --version 1.24.3 \
    --wait >/dev/null

helm upgrade --install istiod istio/istiod \
    --namespace istio-system \
    --version 1.24.3 \
    --set pilot.resources.requests.memory=256Mi \
    --set pilot.resources.requests.cpu=100m \
    --wait >/dev/null

print_success "Istio control plane installed"

print_step "Applying namespace baseline labels"
kubectl apply -f "$ORCHESTRATION_DIR/kubernetes/infrastructure/namespace.yaml" >/dev/null
kubectl label namespace default istio-injection=enabled --overwrite >/dev/null
kubectl label namespace default pod-security.kubernetes.io/warn=restricted --overwrite >/dev/null
kubectl label namespace default pod-security.kubernetes.io/audit=restricted --overwrite >/dev/null
kubectl label namespace infrastructure istio-injection=disabled --overwrite >/dev/null
kubectl label namespace infrastructure pod-security.kubernetes.io/warn=baseline --overwrite >/dev/null
kubectl label namespace infrastructure pod-security.kubernetes.io/audit=baseline --overwrite >/dev/null
kubectl label namespace envoy-gateway-system istio-injection=disabled --overwrite >/dev/null
kubectl label namespace envoy-gateway-system pod-security.kubernetes.io/warn=baseline --overwrite >/dev/null
kubectl label namespace envoy-gateway-system pod-security.kubernetes.io/audit=baseline --overwrite >/dev/null
print_success "Namespace labels applied"

print_step "Applying Istio security resources"
kubectl apply -f "$ORCHESTRATION_DIR/kubernetes/istio/peer-authentication.yaml" >/dev/null
kubectl apply -f "$ORCHESTRATION_DIR/kubernetes/istio/authorization-policies.yaml" >/dev/null
print_success "Istio policy resources applied"

print_step "Installing Kyverno"
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --version 3.8.0 \
    --wait >/dev/null
kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=5m >/dev/null
print_success "Kyverno is ready"

print_step "Applying Kyverno smoke policy"
kubectl apply -f "$ORCHESTRATION_DIR/kubernetes/kyverno/policies/00-smoke-disallow-privileged.yaml" >/dev/null
print_success "Kyverno smoke policy applied"

print_step "Running runtime verifier"
"$ORCHESTRATION_DIR/scripts/smoketest/verify-security-prereqs.sh"
print_success "Runtime verifier passed"

echo
print_success "Security preflight test passed"
