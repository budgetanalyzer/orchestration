#!/bin/bash

# verify-security-prereqs.sh - Deterministic runtime proof for Security Hardening v2 Phase 0.

set -euo pipefail

BUSYBOX_IMAGE="busybox:1.36.1"
HTTP_ECHO_IMAGE="hashicorp/http-echo:1.0.0"

TEMP_NAMESPACES=()
TEMP_PODS=()

print_step() {
    echo "▶ $1"
}

print_success() {
    echo "✓ $1"
}

print_error() {
    echo "✗ $1" >&2
}

fail() {
    print_error "$1"
    exit 1
}

cleanup() {
    for pod_ref in "${TEMP_PODS[@]:-}"; do
        kubectl delete pod "${pod_ref#*/}" -n "${pod_ref%%/*}" --ignore-not-found >/dev/null 2>&1 || true
    done

    for ns in "${TEMP_NAMESPACES[@]:-}"; do
        kubectl delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        fail "Cannot reach Kubernetes cluster from current kubectl context"
    fi
}

new_temp_namespace() {
    local prefix="$1"
    local ns="${prefix}-$(date +%s)-$RANDOM"
    kubectl create namespace "$ns" >/dev/null
    TEMP_NAMESPACES+=("$ns")
    echo "$ns"
}

wait_for_condition() {
    local description="$1"
    local timeout_seconds="$2"
    local command="$3"

    local waited=0
    while (( waited < timeout_seconds )); do
        if eval "$command" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done

    fail "$description (timed out after ${timeout_seconds}s)"
}

netpol_can_connect() {
    local ns="$1"
    kubectl exec -n "$ns" client -- wget -q -T 2 -O - http://server:8080 2>/dev/null | grep -q "ok"
}

prove_network_policy_enforcement() {
    print_step "Verifying NetworkPolicy enforcement (allow -> deny -> allow)..."

    local ns
    ns="$(new_temp_namespace "ba-netpol")"

    kubectl label namespace "$ns" istio-injection=disabled --overwrite >/dev/null

    cat <<MANIFEST | kubectl apply -n "$ns" -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: server
  labels:
    app: server
spec:
  containers:
    - name: server
      image: ${HTTP_ECHO_IMAGE}
      args:
        - "-listen=:8080"
        - "-text=ok"
      ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: server
spec:
  selector:
    app: server
  ports:
    - port: 8080
      targetPort: 8080
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  labels:
    app: client
spec:
  containers:
    - name: client
      image: ${BUSYBOX_IMAGE}
      command:
        - sh
        - -c
        - sleep 3600
MANIFEST

    kubectl wait --for=condition=Ready pod/server pod/client -n "$ns" --timeout=120s >/dev/null

    wait_for_condition "Client could not reach server before policy" 30 "netpol_can_connect '$ns'"

    cat <<MANIFEST | kubectl apply -n "$ns" -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-server-ingress
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
    - Ingress
MANIFEST

    local denied=false
    for _ in {1..20}; do
        if ! netpol_can_connect "$ns"; then
            denied=true
            break
        fi
        sleep 1
    done

    if [[ "$denied" != true ]]; then
        fail "Deny policy applied but client can still reach server"
    fi

    cat <<MANIFEST | kubectl apply -n "$ns" -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: client
      ports:
        - protocol: TCP
          port: 8080
MANIFEST

    wait_for_condition "Allow policy did not restore connectivity" 30 "netpol_can_connect '$ns'"
    print_success "NetworkPolicy enforcement proof passed"
}

prove_pod_security_admission() {
    print_step "Verifying Pod Security Admission restricted enforcement..."

    local ns
    ns="$(new_temp_namespace "ba-psa")"

    kubectl label namespace "$ns" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
    kubectl label namespace "$ns" pod-security.kubernetes.io/enforce-version=latest --overwrite >/dev/null

    set +e
    local output
    output=$(kubectl apply -n "$ns" -f - 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: insecure-psa-smoke
spec:
  containers:
    - name: app
      image: ${BUSYBOX_IMAGE}
      securityContext:
        privileged: true
      command: ["sh", "-c", "sleep 30"]
MANIFEST
)
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected Pod Security Admission to reject insecure pod, but apply succeeded"
    fi

    if ! echo "$output" | grep -Eqi "PodSecurity|violates|forbidden"; then
        fail "Pod creation failed, but output does not indicate Pod Security Admission enforcement: $output"
    fi

    print_success "Pod Security Admission restricted enforcement proof passed"
}

prove_istio_readiness_and_injection() {
    print_step "Verifying Istio readiness, policy resources, and sidecar injection..."

    kubectl wait --for=condition=Available deployment/istiod -n istio-system --timeout=180s >/dev/null

    local required_peer_auth=(
        "default-strict"
        "nginx-gateway-permissive"
        "ext-authz-permissive"
        "session-gateway-permissive"
    )

    local required_authz=(
        "transaction-service-policy"
        "currency-service-policy"
        "permission-service-policy"
        "budget-analyzer-web-policy"
    )

    local name
    for name in "${required_peer_auth[@]}"; do
        kubectl get peerauthentication.security.istio.io "$name" -n default >/dev/null 2>&1 || fail "Missing Istio PeerAuthentication: $name"
    done

    for name in "${required_authz[@]}"; do
        kubectl get authorizationpolicy.security.istio.io "$name" -n default >/dev/null 2>&1 || fail "Missing Istio AuthorizationPolicy: $name"
    done

    local pod_name="istio-sidecar-smoke"
    kubectl delete pod "$pod_name" -n default --ignore-not-found >/dev/null 2>&1 || true

    cat <<MANIFEST | kubectl apply -n default -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: ${pod_name}
  labels:
    app: ${pod_name}
spec:
  containers:
    - name: app
      image: ${BUSYBOX_IMAGE}
      command: ["sh", "-c", "sleep 300"]
MANIFEST

    TEMP_PODS+=("default/${pod_name}")

    wait_for_condition "Istio sidecar was not injected into smoke pod" 45 "kubectl get pod ${pod_name} -n default -o jsonpath='{.spec.containers[*].name}' | grep -qw istio-proxy"
    print_success "Istio readiness and sidecar injection proof passed"
}

prove_kyverno_smoke_policy() {
    print_step "Verifying Kyverno smoke policy rejection..."

    kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=180s >/dev/null
    kubectl get clusterpolicy smoke-disallow-privileged >/dev/null 2>&1 || fail "Missing Kyverno smoke policy: smoke-disallow-privileged"

    local ns
    ns="$(new_temp_namespace "ba-kyverno")"

    kubectl label namespace "$ns" security.budgetanalyzer.io/kyverno-smoke=true --overwrite >/dev/null
    kubectl label namespace "$ns" istio-injection=disabled --overwrite >/dev/null

    set +e
    local output
    output=$(kubectl apply -n "$ns" -f - 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: insecure-kyverno-smoke
spec:
  containers:
    - name: app
      image: ${BUSYBOX_IMAGE}
      securityContext:
        privileged: true
      command: ["sh", "-c", "sleep 30"]
MANIFEST
)
    local status=$?
    set -e

    if [[ $status -eq 0 ]]; then
        fail "Expected Kyverno smoke policy to reject insecure pod, but apply succeeded"
    fi

    if ! echo "$output" | grep -Eqi "kyverno|smoke-disallow-privileged|validation"; then
        fail "Pod creation failed, but output does not indicate Kyverno smoke policy enforcement: $output"
    fi

    print_success "Kyverno smoke policy proof passed"
}

main() {
    echo "=============================================="
    echo "  Security Prerequisite Verifier (Phase 0)"
    echo "=============================================="
    echo

    require_cluster_access
    prove_network_policy_enforcement
    prove_pod_security_admission
    prove_istio_readiness_and_injection
    prove_kyverno_smoke_policy

    echo
    print_success "All security prerequisite proofs passed"
}

main "$@"
