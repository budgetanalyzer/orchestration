#!/usr/bin/env bash
# Verifies the repo-owned Istio tracing provider and mesh-default Telemetry.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ISTIOD_VALUES_FILE="${REPO_DIR}/kubernetes/istio/istiod-values.yaml"
TRACING_TELEMETRY_FILE="${REPO_DIR}/kubernetes/istio/tracing-telemetry.yaml"
JAEGER_SERVICES_FILE="${REPO_DIR}/kubernetes/monitoring/jaeger/services.yaml"
TELEMETRY_NAME="mesh-default-tracing"
TELEMETRY_NAMESPACE="istio-system"
JAEGER_PROVIDER_NAME="jaeger"
JAEGER_COLLECTOR_SERVICE="jaeger-collector.monitoring.svc.cluster.local"
JAEGER_OTLP_GRPC_PORT="4317"

log_step() {
    printf '\n==> %s\n' "$1"
}

pass() {
    printf '  [PASS] %s\n' "$1"
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "Required command not found: $1"
    fi
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -Eq -- "${pattern}" "${file}"; then
        pass "${label}"
    else
        fail "${label} is missing from ${file#"${REPO_DIR}"/}"
    fi
}

assert_text_contains() {
    local text="$1"
    local pattern="$2"
    local label="$3"

    if printf '%s\n' "${text}" | grep -Eq -- "${pattern}"; then
        pass "${label}"
    else
        fail "${label} is missing from live istiod mesh config"
    fi
}

validate_checked_in_contract() {
    log_step "Checking checked-in Istio tracing contract"

    [[ -f "${ISTIOD_VALUES_FILE}" ]] || fail "Missing ${ISTIOD_VALUES_FILE#"${REPO_DIR}"/}"
    [[ -f "${TRACING_TELEMETRY_FILE}" ]] || fail "Missing ${TRACING_TELEMETRY_FILE#"${REPO_DIR}"/}"
    [[ -f "${JAEGER_SERVICES_FILE}" ]] || fail "Missing ${JAEGER_SERVICES_FILE#"${REPO_DIR}"/}"

    assert_file_contains "${ISTIOD_VALUES_FILE}" 'enableTracing:[[:space:]]*true' \
        "istiod values enable mesh tracing"
    assert_file_contains "${ISTIOD_VALUES_FILE}" 'defaultConfig:' \
        "istiod values keep defaultConfig"
    assert_file_contains "${ISTIOD_VALUES_FILE}" 'tracing:[[:space:]]*\{\}' \
        "istiod values keep empty legacy tracing options"
    assert_file_contains "${ISTIOD_VALUES_FILE}" "name:[[:space:]]*${JAEGER_PROVIDER_NAME}" \
        "istiod values define the Jaeger extension provider"
    assert_file_contains "${ISTIOD_VALUES_FILE}" 'opentelemetry:' \
        "istiod values use the OpenTelemetry extension provider"
    assert_file_contains "${ISTIOD_VALUES_FILE}" "service:[[:space:]]*${JAEGER_COLLECTOR_SERVICE}" \
        "istiod values target the internal Jaeger collector"
    assert_file_contains "${ISTIOD_VALUES_FILE}" "port:[[:space:]]*${JAEGER_OTLP_GRPC_PORT}" \
        "istiod values target Jaeger OTLP/gRPC"

    assert_file_contains "${TRACING_TELEMETRY_FILE}" 'apiVersion:[[:space:]]*telemetry\.istio\.io/v1' \
        "Telemetry manifest uses the Istio v1 API"
    assert_file_contains "${TRACING_TELEMETRY_FILE}" 'kind:[[:space:]]*Telemetry' \
        "Telemetry manifest declares a Telemetry resource"
    assert_file_contains "${TRACING_TELEMETRY_FILE}" "name:[[:space:]]*${TELEMETRY_NAME}" \
        "Telemetry manifest uses the mesh-default tracing name"
    assert_file_contains "${TRACING_TELEMETRY_FILE}" "namespace:[[:space:]]*${TELEMETRY_NAMESPACE}" \
        "Telemetry manifest lives in the Istio root namespace"
    assert_file_contains "${TRACING_TELEMETRY_FILE}" "name:[[:space:]]*${JAEGER_PROVIDER_NAME}" \
        "Telemetry manifest selects the Jaeger provider"

    assert_file_contains "${JAEGER_SERVICES_FILE}" 'name:[[:space:]]*grpc-otlp' \
        "Jaeger collector uses an Istio-classified OTLP/gRPC service port"
    assert_file_contains "${JAEGER_SERVICES_FILE}" 'appProtocol:[[:space:]]*grpc' \
        "Jaeger collector declares OTLP/gRPC appProtocol"
    assert_file_contains "${JAEGER_SERVICES_FILE}" 'name:[[:space:]]*http-otlp' \
        "Jaeger collector uses an Istio-classified OTLP/HTTP service port"
    assert_file_contains "${JAEGER_SERVICES_FILE}" 'appProtocol:[[:space:]]*http' \
        "Jaeger collector declares OTLP/HTTP appProtocol"
}

validate_live_contract() {
    local mesh_config
    local collector_ports

    log_step "Checking live Istio tracing resources"

    kubectl cluster-info >/dev/null 2>&1 || fail "Cannot reach Kubernetes cluster from current kubectl context"
    kubectl apply --dry-run=server -f "${TRACING_TELEMETRY_FILE}" >/dev/null
    pass "Kubernetes server accepts the Telemetry manifest"

    kubectl get "telemetry.telemetry.istio.io/${TELEMETRY_NAME}" \
        -n "${TELEMETRY_NAMESPACE}" >/dev/null 2>&1 || \
        fail "Live Telemetry ${TELEMETRY_NAMESPACE}/${TELEMETRY_NAME} is missing; rerun Tilt or apply ${TRACING_TELEMETRY_FILE#"${REPO_DIR}"/}"
    pass "Live mesh-default Telemetry resource exists"

    mesh_config="$(kubectl get configmap istio -n istio-system -o jsonpath='{.data.mesh}' 2>/dev/null || true)"
    [[ -n "${mesh_config}" ]] || fail "Could not read live istiod mesh ConfigMap"

    assert_text_contains "${mesh_config}" 'enableTracing:[[:space:]]*true' \
        "live istiod mesh config enables tracing"
    assert_text_contains "${mesh_config}" "name:[[:space:]]*${JAEGER_PROVIDER_NAME}" \
        "live istiod mesh config exposes the Jaeger provider"
    assert_text_contains "${mesh_config}" "service:[[:space:]]*${JAEGER_COLLECTOR_SERVICE}" \
        "live istiod mesh config targets the internal Jaeger collector"
    assert_text_contains "${mesh_config}" "port:[[:space:]]*${JAEGER_OTLP_GRPC_PORT}" \
        "live istiod mesh config targets Jaeger OTLP/gRPC"

    collector_ports="$(kubectl get service jaeger-collector -n monitoring \
        -o jsonpath='{range .spec.ports[*]}{.name}:{.appProtocol}:{.port}{"\n"}{end}' 2>/dev/null || true)"
    printf '%s\n' "${collector_ports}" | grep -Fxq "grpc-otlp:grpc:${JAEGER_OTLP_GRPC_PORT}" || \
        fail "Live jaeger-collector Service must expose ${JAEGER_OTLP_GRPC_PORT} as grpc-otlp with appProtocol grpc"
    pass "Live Jaeger collector exposes OTLP/gRPC with Istio protocol classification"
}

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-istio-tracing-config.sh

Verifies the checked-in Istio tracing provider, server-dry-runs the
mesh-default Telemetry manifest, and confirms the live cluster has consumed the
repo-owned Jaeger extension provider.
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

require_command kubectl
validate_checked_in_contract
validate_live_contract

printf '\nIstio tracing configuration verification passed.\n'
