#!/bin/bash

# verify-phase-4-transport-encryption.sh
#
# Runtime verification for infrastructure transport encryption.
# Proves client-side TLS validation for Redis, PostgreSQL, and RabbitMQ,
# confirms RabbitMQ listener state as secondary broker proof, runs regressions
# for earlier security verifiers, and checks the readiness of all
# transport-encrypted client pods.
#
# Prerequisites: Tilt running with infrastructure TLS secrets created from the
# host via ./scripts/bootstrap/setup-infra-tls.sh.
#
# Usage:
#   ./scripts/smoketest/verify-phase-4-transport-encryption.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REDIS_PROBE_IMAGE="redis:7-alpine@sha256:7aec734b2bb298a1d769fd8729f13b8514a41bf90fcdd1f38ec52267fbaa8ee6"
POSTGRES_PROBE_IMAGE="postgres:16-alpine@sha256:4e6e670bb069649261c9c18031f0aded7bb249a5b6664ddec29c013a89310d50"
RABBITMQ_PROBE_IMAGE="python:3.12-alpine@sha256:7747d47f92cfca63a6e2b50275e23dba8407c30d8ae929a88ddd49a5d3f2d331"
REDIS_PROBE="phase4-redis-client"
POSTGRES_PROBE="phase4-postgresql-client"
RABBITMQ_PROBE="phase4-rabbitmq-client"
WAIT_TIMEOUT="120s"
TEMP_LABEL_KEY="verify-phase4-temp"
TEMP_LABEL_VALUE="true"
REDIS_SESSION_GATEWAY_USERNAME="session-gateway"
POSTGRES_TRANSACTION_USERNAME="transaction_service"

PASSED=0
FAILED=0

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-phase-4-transport-encryption.sh

Options:
  -h, --help                    Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

section() { printf '\n=== %s ===\n' "$1"; }
pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }

cleanup_temp_resources() {
    kubectl delete pod -n default -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete networkpolicy -n default -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete networkpolicy -n infrastructure -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

cleanup() {
    set +e
    echo ""
    echo "Cleaning up temporary verification resources..."
    cleanup_temp_resources
}

trap cleanup EXIT

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

current_context() {
    kubectl config current-context 2>/dev/null || printf 'unknown'
}

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes cluster from current kubectl context (%s)\n' "$(current_context)" >&2
        exit 1
    fi
}

namespace_exists() {
    kubectl get namespace "$1" >/dev/null 2>&1
}

pod_count() {
    kubectl get pods -n "$1" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

find_pod() {
    local namespace="$1"
    local selector="$2"

    kubectl get pods -n "$namespace" -l "$selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

require_pod() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local pod

    if ! namespace_exists "$namespace"; then
        printf 'ERROR: namespace %s not found in current kubectl context (%s)\n' "$namespace" "$(current_context)" >&2
        exit 1
    fi

    pod=$(find_pod "$namespace" "$selector")
    if [[ -z "$pod" ]]; then
        printf 'ERROR: %s pod not found in namespace %s (context: %s, pods in namespace: %s)\n' \
            "$label" "$namespace" "$(current_context)" "$(pod_count "$namespace")" >&2
        printf '       Tilt may be stopped, still reconciling, or running against a different cluster/context than kubectl.\n' >&2
        exit 1
    fi

    printf '%s' "$pod"
}

require_secret_exists() {
    local namespace="$1"
    local secret_name="$2"

    if ! kubectl get secret "$secret_name" -n "$namespace" >/dev/null 2>&1; then
        printf 'ERROR: required secret not found: %s/%s (context: %s)\n' \
            "$namespace" "$secret_name" "$(current_context)" >&2
        exit 1
    fi
}

read_secret() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local encoded

    encoded=$(kubectl get secret "$secret_name" -n "$namespace" -o "jsonpath={.data['${key}']}" 2>/dev/null || true)
    if [[ -z "$encoded" ]]; then
        return 1
    fi

    printf '%s' "$encoded" | base64 -d
}

require_secret_value() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local value

    require_secret_exists "$namespace" "$secret_name"
    value=$(read_secret "$namespace" "$secret_name" "$key" || true)
    if [[ -z "$value" ]]; then
        printf 'ERROR: missing secret value %s/%s[%s] (context: %s)\n' \
            "$namespace" "$secret_name" "$key" "$(current_context)" >&2
        exit 1
    fi

    printf '%s' "$value"
}

create_temp_resources() {
    cleanup_temp_resources

    kubectl apply -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${REDIS_PROBE}
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase4-role: redis-client
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${REDIS_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POSTGRES_PROBE}
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase4-role: postgresql-client
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${POSTGRES_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: v1
kind: Pod
metadata:
  name: ${RABBITMQ_PROBE}
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase4-role: rabbitmq-client
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${RABBITMQ_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-redis-probe-egress
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      verify-phase4-role: redis-client
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: infrastructure
          podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-postgresql-probe-egress
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      verify-phase4-role: postgresql-client
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: infrastructure
          podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-rabbitmq-probe-egress
  namespace: default
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      verify-phase4-role: rabbitmq-client
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: infrastructure
          podSelector:
            matchLabels:
              app: rabbitmq
      ports:
        - protocol: TCP
          port: 5671
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-redis-probe-ingress
  namespace: infrastructure
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              verify-phase4-role: redis-client
      ports:
        - protocol: TCP
          port: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-postgresql-probe-ingress
  namespace: infrastructure
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              verify-phase4-role: postgresql-client
      ports:
        - protocol: TCP
          port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-phase4-rabbitmq-probe-ingress
  namespace: infrastructure
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              verify-phase4-role: rabbitmq-client
      ports:
        - protocol: TCP
          port: 5671
MANIFEST

    kubectl wait --for=condition=Ready "pod/${REDIS_PROBE}" -n default --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1
    kubectl wait --for=condition=Ready "pod/${POSTGRES_PROBE}" -n default --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1
    kubectl wait --for=condition=Ready "pod/${RABBITMQ_PROBE}" -n default --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1
}

find_system_ca_bundle() {
    local pod="$1"

    # shellcheck disable=SC2016 # This script is evaluated inside the target pod.
    kubectl exec -n default "$pod" -- sh -ceu '
for candidate in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/ssl/certs/ca-bundle.crt; do
    if [ -f "$candidate" ]; then
        printf "%s\n" "$candidate"
        exit 0
    fi
done

printf "No system CA bundle found\n" >&2
exit 1
' 2>/dev/null
}

run_redis_tls_ping() {
    local username="$1"
    local password="$2"
    local cacert="${3:-}"

    if [[ -n "$cacert" ]]; then
        # shellcheck disable=SC2016 # This script is evaluated inside the Redis probe pod.
        kubectl exec -n default "$REDIS_PROBE" -- sh -ceu '
redis-cli \
    --tls \
    --cacert "$1" \
    -h redis.infrastructure \
    -p 6379 \
    --user "$2" \
    --pass "$3" \
    --no-auth-warning \
    ping
' sh "$cacert" "$username" "$password"
        return
    fi

    # shellcheck disable=SC2016 # This script is evaluated inside the Redis probe pod.
    kubectl exec -n default "$REDIS_PROBE" -- sh -ceu '
redis-cli \
    --tls \
    -h redis.infrastructure \
    -p 6379 \
    --user "$1" \
    --pass "$2" \
    --no-auth-warning \
    ping
' sh "$username" "$password"
}

run_redis_plaintext_ping() {
    local username="$1"
    local password="$2"

    # shellcheck disable=SC2016 # This script is evaluated inside the Redis probe pod.
    kubectl exec -n default "$REDIS_PROBE" -- sh -ceu '
redis-cli \
    -h redis.infrastructure \
    -p 6379 \
    --user "$1" \
    --pass "$2" \
    --no-auth-warning \
    ping
' sh "$username" "$password"
}

run_postgresql_verify_full() {
    local username="$1"
    local password="$2"
    local sslrootcert="$3"

    # shellcheck disable=SC2016 # This script is evaluated inside the PostgreSQL probe pod.
    kubectl exec -n default "$POSTGRES_PROBE" -- sh -ceu '
export PGPASSWORD="$1"
export PGHOST="postgresql.infrastructure"
export PGPORT="5432"
export PGDATABASE="budget_analyzer"
export PGUSER="$2"
export PGSSLMODE="verify-full"
export PGSSLROOTCERT="$3"

psql -X -v ON_ERROR_STOP=1 -tA -c "SELECT current_user;"
' sh "$password" "$username" "$sslrootcert"
}

rabbitmq_listeners() {
    kubectl exec -n infrastructure "$RABBITMQ_POD" -- rabbitmq-diagnostics -q listeners
}

run_rabbitmq_tls_probe() {
    local cacert="$1"
    local server_hostname="$2"

    # shellcheck disable=SC2016 # This script is evaluated inside the RabbitMQ probe pod.
    kubectl exec -n default "$RABBITMQ_PROBE" -- sh -ceu '
python - "$1" "$2" <<'"'"'PY'"'"'
import socket
import ssl
import sys

cafile = sys.argv[1]
server_hostname = sys.argv[2]
context = ssl.create_default_context(cafile=cafile)
context.check_hostname = True
context.verify_mode = ssl.CERT_REQUIRED

with socket.create_connection(("rabbitmq.infrastructure", 5671), timeout=5) as sock:
    with context.wrap_socket(sock, server_hostname=server_hostname) as tls:
        print(f"TLS_OK {tls.version()}")
PY
' sh "$cacert" "$server_hostname"
}

assert_pod_ready() {
    local app="$1"

    if kubectl wait --for=condition=Ready pod -n default -l "app=${app}" --timeout="$WAIT_TIMEOUT" >/dev/null 2>&1; then
        pass "${app} readiness probe is passing"
    else
        fail "${app} readiness probe is not passing"
    fi
}

main() {
    echo "=============================================="
    echo "  Infrastructure Transport Encryption Verification"
    echo "=============================================="

    require_host_command kubectl
    require_cluster_access

    require_secret_exists default infra-ca
    require_secret_exists infrastructure infra-ca
    require_secret_exists infrastructure infra-tls-redis
    require_secret_exists infrastructure infra-tls-postgresql
    require_secret_exists infrastructure infra-tls-rabbitmq

    REDIS_USERNAME="${REDIS_SESSION_GATEWAY_USERNAME}"
    REDIS_PASSWORD=$(require_secret_value infrastructure redis-bootstrap-credentials session-gateway-password)
    PG_USERNAME="${POSTGRES_TRANSACTION_USERNAME}"
    PG_PASSWORD=$(require_secret_value default transaction-service-postgresql-credentials password)
    RABBITMQ_POD=$(require_pod infrastructure app=rabbitmq RabbitMQ)

    section "Temporary Client Probes"

    if create_temp_resources; then
        REDIS_WRONG_CA=$(find_system_ca_bundle "$REDIS_PROBE")
        POSTGRES_WRONG_CA=$(find_system_ca_bundle "$POSTGRES_PROBE")
        RABBITMQ_WRONG_CA=$(find_system_ca_bundle "$RABBITMQ_PROBE")
        pass "Created disposable Redis, PostgreSQL, and RabbitMQ client probes"
    else
        printf 'ERROR: Failed to create temporary transport-encryption probes\n' >&2
        exit 1
    fi

    section "Redis TLS"

    if out=$(run_redis_tls_ping "$REDIS_USERNAME" "$REDIS_PASSWORD" "/tls-ca/ca.crt" 2>&1); then
        if printf '%s\n' "$out" | grep -qx 'PONG'; then
            pass "Redis TLS succeeds with the service hostname and infra CA"
        else
            fail "Redis TLS returned unexpected output: ${out:0:160}"
        fi
    else
        fail "Redis TLS failed with the service hostname and infra CA: ${out:0:160}"
    fi

    if out=$(run_redis_plaintext_ping "$REDIS_USERNAME" "$REDIS_PASSWORD" 2>&1); then
        fail "Redis plaintext unexpectedly succeeded: ${out:0:160}"
    else
        pass "Redis rejects plaintext clients on port 6379"
    fi

    if out=$(run_redis_tls_ping "$REDIS_USERNAME" "$REDIS_PASSWORD" "$REDIS_WRONG_CA" 2>&1); then
        fail "Redis unexpectedly trusted the wrong CA bundle: ${out:0:160}"
    else
        pass "Redis rejects TLS clients that do not trust the infra CA"
    fi

    section "PostgreSQL TLS"

    if out=$(run_postgresql_verify_full "$PG_USERNAME" "$PG_PASSWORD" "/tls-ca/ca.crt" 2>&1); then
        if printf '%s\n' "$out" | grep -qx "$PG_USERNAME"; then
            pass "PostgreSQL verify-full succeeds with the service hostname and infra CA"
        else
            fail "PostgreSQL verify-full returned unexpected output: ${out:0:160}"
        fi
    else
        fail "PostgreSQL verify-full failed with the service hostname and infra CA: ${out:0:160}"
    fi

    if out=$(run_postgresql_verify_full "$PG_USERNAME" "$PG_PASSWORD" "$POSTGRES_WRONG_CA" 2>&1); then
        fail "PostgreSQL unexpectedly trusted the wrong CA bundle: ${out:0:160}"
    else
        pass "PostgreSQL verify-full rejects clients that do not trust the infra CA"
    fi

    section "RabbitMQ TLS"

    if out=$(run_rabbitmq_tls_probe "/tls-ca/ca.crt" "rabbitmq.infrastructure" 2>&1); then
        if printf '%s\n' "$out" | grep -q '^TLS_OK '; then
            pass "RabbitMQ TLS succeeds with the service hostname and infra CA"
        else
            fail "RabbitMQ TLS returned unexpected output: ${out:0:160}"
        fi
    else
        fail "RabbitMQ TLS failed with the service hostname and infra CA: ${out:0:160}"
    fi

    if out=$(run_rabbitmq_tls_probe "$RABBITMQ_WRONG_CA" "rabbitmq.infrastructure" 2>&1); then
        fail "RabbitMQ unexpectedly trusted the wrong CA bundle: ${out:0:160}"
    else
        pass "RabbitMQ rejects TLS clients that do not trust the infra CA"
    fi

    if out=$(run_rabbitmq_tls_probe "/tls-ca/ca.crt" "wrong-rabbitmq.infrastructure" 2>&1); then
        fail "RabbitMQ unexpectedly accepted a hostname mismatch: ${out:0:160}"
    else
        pass "RabbitMQ rejects TLS clients with the wrong expected hostname"
    fi

    section "RabbitMQ Listener State"

    if out=$(rabbitmq_listeners 2>&1); then
        if printf '%s\n' "$out" | grep -q 'port: 5671' && printf '%s\n' "$out" | grep -q 'protocol: amqp/ssl'; then
            pass "RabbitMQ exposes the AMQPS listener on port 5671"
        else
            fail "RabbitMQ listeners do not show port 5671 with protocol amqp/ssl: ${out:0:160}"
        fi

        if printf '%s\n' "$out" | grep -q 'port: 5672'; then
            fail "RabbitMQ plaintext AMQP listener 5672 is still enabled"
        else
            pass "RabbitMQ plaintext AMQP listener 5672 is disabled"
        fi
    else
        fail "Could not inspect RabbitMQ listeners: ${out:0:160}"
        fail "RabbitMQ plaintext listener state could not be verified"
    fi

    section "Regression: Earlier Security Phases"

    if "${SCRIPT_DIR}/verify-phase-1-credentials.sh"; then
        pass "Credential verification still passes after transport-TLS cutover"
    else
        fail "Credential verification failed after transport-TLS cutover"
    fi

    # The temporary transport client probes add a small amount of extra policy and
    # DNS churn in default/infrastructure. Give the nested NetworkPolicy rerun a
    # slightly longer warmup budget so it validates policy intent instead of
    # flaking on probe startup timing.
    if PHASE2_ALLOW_ATTEMPTS=8 PHASE2_PROBE_STABILIZATION_SECONDS=8 \
        "${SCRIPT_DIR}/verify-phase-2-network-policies.sh"; then
        pass "NetworkPolicy verification still passes after RabbitMQ port cutover"
    else
        fail "NetworkPolicy verification failed after RabbitMQ port cutover"
    fi

    section "Client Pod Readiness"

    assert_pod_ready ext-authz
    assert_pod_ready session-gateway
    assert_pod_ready currency-service
    assert_pod_ready transaction-service
    assert_pod_ready permission-service

    echo ""
    echo "=============================================="
    total=$((PASSED + FAILED))
    if [[ "$FAILED" -eq 0 ]]; then
        echo "  ${PASSED} passed (out of ${total})"
    else
        echo "  ${PASSED} passed, ${FAILED} failed (out of ${total})"
    fi
    echo "=============================================="

    [[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
