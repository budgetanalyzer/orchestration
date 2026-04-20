#!/usr/bin/env bash
# Verifies Grafana, Prometheus, Jaeger, and Kiali access over loopback-bound kubectl port-forwards.

set -euo pipefail

MONITORING_NAMESPACE="monitoring"
GRAFANA_RESOURCE="svc/prometheus-stack-grafana"
GRAFANA_REMOTE_PORT=80
GRAFANA_LOCAL_PORT=3300
PROMETHEUS_RESOURCE="svc/prometheus-stack-kube-prom-prometheus"
PROMETHEUS_REMOTE_PORT=9090
PROMETHEUS_LOCAL_PORT=9090
JAEGER_RESOURCE="svc/jaeger-query"
JAEGER_REMOTE_PORT=16686
JAEGER_LOCAL_PORT=16686
KIALI_RESOURCE="svc/kiali"
KIALI_REMOTE_PORT=20001
KIALI_LOCAL_PORT=20001
WAIT_TIMEOUT_SECONDS=30
POLL_INTERVAL_SECONDS=1

declare -A PORT_FORWARD_PIDS=()
declare -A PORT_FORWARD_LOGS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-observability-port-forward-access.sh [options]

Starts loopback-only kubectl port-forwards for Grafana, Prometheus, Jaeger,
and Kiali, then checks their local endpoints and confirms Grafana and Kiali
unauthenticated API access is rejected.

Options:
  --grafana-port PORT      Local loopback port for Grafana. Default: 3300
  --prometheus-port PORT   Local loopback port for Prometheus. Default: 9090
  --jaeger-port PORT       Local loopback port for Jaeger. Default: 16686
  --kiali-port PORT        Local loopback port for Kiali. Default: 20001
  --wait-timeout SECONDS   Max seconds to wait for each health check.
                           Default: 30
  --poll-interval SECONDS  Poll interval while waiting. Default: 1
  -h, --help               Show this help text.
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_positive_integer() {
    local name="$1"
    local value="$2"

    if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
        printf 'ERROR: %s must be a positive integer, got: %s\n' "${name}" "${value}" >&2
        exit 1
    fi
}

require_cluster_access() {
    if ! kubectl get namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
        printf 'ERROR: cannot reach Kubernetes API or namespace %s\n' "${MONITORING_NAMESPACE}" >&2
        exit 1
    fi
}

require_service() {
    local resource="$1"

    if ! kubectl get -n "${MONITORING_NAMESPACE}" "${resource}" >/dev/null 2>&1; then
        printf 'ERROR: required resource not found: %s/%s\n' "${MONITORING_NAMESPACE}" "${resource}" >&2
        exit 1
    fi
}

ensure_loopback_port_is_free() {
    local port="$1"
    local expected_owner="$2"
    local active_listener=""

    if ! python3 - "${port}" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
    then
        if command -v lsof >/dev/null 2>&1; then
            active_listener="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -n 1 || true)"
        elif command -v ss >/dev/null 2>&1; then
            active_listener="$(ss -ltnp "( sport = :${port} )" 2>/dev/null | tail -n +2 | head -n 1 || true)"
        fi

        printf 'ERROR: loopback port 127.0.0.1:%s is already in use.\n' "${port}" >&2
        printf 'Expected owner: %s\n' "${expected_owner}" >&2
        if [[ -n "${active_listener}" ]]; then
            printf 'Current listener: %s\n' "${active_listener}" >&2
        fi
        printf 'Rerun with a free port via --grafana-port, --prometheus-port, or --jaeger-port if this listener is intentional.\n' >&2
        exit 1
    fi
}

cleanup_port_forwards() {
    local name

    for name in "${!PORT_FORWARD_PIDS[@]}"; do
        kill "${PORT_FORWARD_PIDS[${name}]}" >/dev/null 2>&1 || true
    done

    for name in "${!PORT_FORWARD_PIDS[@]}"; do
        wait "${PORT_FORWARD_PIDS[${name}]}" >/dev/null 2>&1 || true
    done

    for name in "${!PORT_FORWARD_LOGS[@]}"; do
        rm -f "${PORT_FORWARD_LOGS[${name}]}"
    done
}

wait_for_url() {
    local label="$1"
    local url="$2"
    local pid="$3"
    local log_file="$4"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

    while (( SECONDS < deadline )); do
        if curl -fsS --max-time 2 "${url}" >/dev/null; then
            return 0
        fi

        if ! kill -0 "${pid}" >/dev/null 2>&1; then
            printf 'ERROR: %s port-forward exited before %s became ready\n' "${label}" "${url}" >&2
            printf 'Port-forward log:\n' >&2
            cat "${log_file}" >&2
            return 1
        fi

        sleep "${POLL_INTERVAL_SECONDS}"
    done

    printf 'ERROR: %s health check timed out for %s\n' "${label}" "${url}" >&2
    printf 'Port-forward log:\n' >&2
    cat "${log_file}" >&2
    return 1
}

start_port_forward() {
    local name="$1"
    local label="$2"
    local resource="$3"
    local local_port="$4"
    local remote_port="$5"
    local expected_owner="$6"
    local log_file
    local pid

    ensure_loopback_port_is_free "${local_port}" "${expected_owner}"

    log_file="$(mktemp)"
    kubectl port-forward -n "${MONITORING_NAMESPACE}" "${resource}" \
        "${local_port}:${remote_port}" --address 127.0.0.1 >"${log_file}" 2>&1 &
    pid=$!
    PORT_FORWARD_PIDS["${name}"]="${pid}"
    PORT_FORWARD_LOGS["${name}"]="${log_file}"

    printf 'Started %s port-forward for %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}"
}

wait_for_port_forward_health() {
    local name="$1"
    local label="$2"
    local resource="$3"
    local local_port="$4"
    local url="$5"

    if wait_for_url "${label}" "${url}" "${PORT_FORWARD_PIDS[${name}]}" "${PORT_FORWARD_LOGS[${name}]}"; then
        printf '[PASS] %s via %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}"
        return 0
    fi

    return 1
}

assert_distinct_local_ports() {
    if [[ "${GRAFANA_LOCAL_PORT}" == "${PROMETHEUS_LOCAL_PORT}" ]]; then
        printf 'ERROR: --grafana-port and --prometheus-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi

    if [[ "${GRAFANA_LOCAL_PORT}" == "${JAEGER_LOCAL_PORT}" ]]; then
        printf 'ERROR: --grafana-port and --jaeger-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi

    if [[ "${PROMETHEUS_LOCAL_PORT}" == "${JAEGER_LOCAL_PORT}" ]]; then
        printf 'ERROR: --prometheus-port and --jaeger-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi

    if [[ "${GRAFANA_LOCAL_PORT}" == "${KIALI_LOCAL_PORT}" ]]; then
        printf 'ERROR: --grafana-port and --kiali-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi

    if [[ "${PROMETHEUS_LOCAL_PORT}" == "${KIALI_LOCAL_PORT}" ]]; then
        printf 'ERROR: --prometheus-port and --kiali-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi

    if [[ "${JAEGER_LOCAL_PORT}" == "${KIALI_LOCAL_PORT}" ]]; then
        printf 'ERROR: --jaeger-port and --kiali-port must be different when both port-forwards run together\n' >&2
        exit 1
    fi
}

assert_grafana_authentication_required() {
    local body_file
    local status_code

    body_file="$(mktemp)"
    status_code="$(curl -sS -o "${body_file}" -w '%{http_code}' --max-time 5 \
        "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/search?type=dash-db")"

    case "${status_code}" in
        302|401|403)
            printf '[PASS] Grafana anonymous dashboard access rejected with HTTP %s\n' "${status_code}"
            ;;
        200)
            printf 'ERROR: Grafana dashboard search is accessible without authentication on 127.0.0.1:%s\n' "${GRAFANA_LOCAL_PORT}" >&2
            printf 'Response excerpt:\n' >&2
            sed -n '1,20p' "${body_file}" >&2
            rm -f "${body_file}"
            return 1
            ;;
        *)
            printf 'ERROR: unexpected Grafana anonymous-access response on 127.0.0.1:%s: HTTP %s\n' \
                "${GRAFANA_LOCAL_PORT}" "${status_code}" >&2
            printf 'Response excerpt:\n' >&2
            sed -n '1,20p' "${body_file}" >&2
            rm -f "${body_file}"
            return 1
            ;;
    esac

    rm -f "${body_file}"
}

assert_kiali_authentication_required() {
    local body_file
    local status_code

    body_file="$(mktemp)"
    status_code="$(curl -sS -o "${body_file}" -w '%{http_code}' --max-time 5 \
        "http://127.0.0.1:${KIALI_LOCAL_PORT}/kiali/api/status")"

    case "${status_code}" in
        401|403)
            printf '[PASS] Kiali unauthenticated API access rejected with HTTP %s\n' "${status_code}"
            ;;
        200)
            printf 'ERROR: Kiali status API is accessible without authentication on 127.0.0.1:%s\n' "${KIALI_LOCAL_PORT}" >&2
            printf 'Response excerpt:\n' >&2
            sed -n '1,20p' "${body_file}" >&2
            rm -f "${body_file}"
            return 1
            ;;
        *)
            printf 'ERROR: unexpected Kiali unauthenticated API response on 127.0.0.1:%s: HTTP %s\n' \
                "${KIALI_LOCAL_PORT}" "${status_code}" >&2
            printf 'Response excerpt:\n' >&2
            sed -n '1,20p' "${body_file}" >&2
            rm -f "${body_file}"
            return 1
            ;;
    esac

    rm -f "${body_file}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --grafana-port)
            GRAFANA_LOCAL_PORT="${2:-}"
            shift 2
            ;;
        --prometheus-port)
            PROMETHEUS_LOCAL_PORT="${2:-}"
            shift 2
            ;;
        --jaeger-port)
            JAEGER_LOCAL_PORT="${2:-}"
            shift 2
            ;;
        --kiali-port)
            KIALI_LOCAL_PORT="${2:-}"
            shift 2
            ;;
        --wait-timeout)
            WAIT_TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --poll-interval)
            POLL_INTERVAL_SECONDS="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command kubectl
require_command curl
require_command python3
require_positive_integer "--grafana-port" "${GRAFANA_LOCAL_PORT}"
require_positive_integer "--prometheus-port" "${PROMETHEUS_LOCAL_PORT}"
require_positive_integer "--jaeger-port" "${JAEGER_LOCAL_PORT}"
require_positive_integer "--kiali-port" "${KIALI_LOCAL_PORT}"
require_positive_integer "--wait-timeout" "${WAIT_TIMEOUT_SECONDS}"
require_positive_integer "--poll-interval" "${POLL_INTERVAL_SECONDS}"
assert_distinct_local_ports
require_cluster_access
require_service "${GRAFANA_RESOURCE}"
require_service "${PROMETHEUS_RESOURCE}"
require_service "${JAEGER_RESOURCE}"
require_service "${KIALI_RESOURCE}"
trap cleanup_port_forwards EXIT INT TERM

printf 'Using kubectl context: %s\n' "$(kubectl config current-context)"

start_port_forward \
    "grafana" \
    "Grafana" \
    "${GRAFANA_RESOURCE}" \
    "${GRAFANA_LOCAL_PORT}" \
    "${GRAFANA_REMOTE_PORT}" \
    "kubectl port-forward -n ${MONITORING_NAMESPACE} ${GRAFANA_RESOURCE} ${GRAFANA_LOCAL_PORT}:${GRAFANA_REMOTE_PORT} --address 127.0.0.1"

start_port_forward \
    "prometheus" \
    "Prometheus" \
    "${PROMETHEUS_RESOURCE}" \
    "${PROMETHEUS_LOCAL_PORT}" \
    "${PROMETHEUS_REMOTE_PORT}" \
    "kubectl port-forward -n ${MONITORING_NAMESPACE} ${PROMETHEUS_RESOURCE} ${PROMETHEUS_LOCAL_PORT}:${PROMETHEUS_REMOTE_PORT} --address 127.0.0.1"

start_port_forward \
    "jaeger" \
    "Jaeger" \
    "${JAEGER_RESOURCE}" \
    "${JAEGER_LOCAL_PORT}" \
    "${JAEGER_REMOTE_PORT}" \
    "kubectl port-forward -n ${MONITORING_NAMESPACE} ${JAEGER_RESOURCE} ${JAEGER_LOCAL_PORT}:${JAEGER_REMOTE_PORT} --address 127.0.0.1"

start_port_forward \
    "kiali" \
    "Kiali" \
    "${KIALI_RESOURCE}" \
    "${KIALI_LOCAL_PORT}" \
    "${KIALI_REMOTE_PORT}" \
    "kubectl port-forward -n ${MONITORING_NAMESPACE} ${KIALI_RESOURCE} ${KIALI_LOCAL_PORT}:${KIALI_REMOTE_PORT} --address 127.0.0.1"

wait_for_port_forward_health \
    "grafana" \
    "Grafana health" \
    "${GRAFANA_RESOURCE}" \
    "${GRAFANA_LOCAL_PORT}" \
    "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/health"

wait_for_port_forward_health \
    "prometheus" \
    "Prometheus readiness" \
    "${PROMETHEUS_RESOURCE}" \
    "${PROMETHEUS_LOCAL_PORT}" \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/-/ready"

wait_for_port_forward_health \
    "jaeger" \
    "Jaeger query API" \
    "${JAEGER_RESOURCE}" \
    "${JAEGER_LOCAL_PORT}" \
    "http://127.0.0.1:${JAEGER_LOCAL_PORT}/jaeger/api/services"

wait_for_port_forward_health \
    "kiali" \
    "Kiali UI shell" \
    "${KIALI_RESOURCE}" \
    "${KIALI_LOCAL_PORT}" \
    "http://127.0.0.1:${KIALI_LOCAL_PORT}/kiali/"

assert_grafana_authentication_required
assert_kiali_authentication_required

printf 'Observability port-forward verification passed.\n'
