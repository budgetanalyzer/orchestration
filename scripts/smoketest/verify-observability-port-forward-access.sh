#!/usr/bin/env bash
# Verifies Grafana and Prometheus health over loopback-bound kubectl port-forwards.

set -euo pipefail

MONITORING_NAMESPACE="monitoring"
GRAFANA_RESOURCE="svc/prometheus-stack-grafana"
GRAFANA_REMOTE_PORT=80
GRAFANA_LOCAL_PORT=3300
PROMETHEUS_RESOURCE="svc/prometheus-stack-kube-prom-prometheus"
PROMETHEUS_REMOTE_PORT=9090
PROMETHEUS_LOCAL_PORT=9090
WAIT_TIMEOUT_SECONDS=30
POLL_INTERVAL_SECONDS=1
CURRENT_PORT_FORWARD_PID=""
CURRENT_PORT_FORWARD_LOG=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-observability-port-forward-access.sh [options]

Starts loopback-only kubectl port-forwards for Grafana and Prometheus, then
checks their health endpoints over localhost.

Options:
  --grafana-port PORT      Local loopback port for Grafana. Default: 3300
  --prometheus-port PORT   Local loopback port for Prometheus. Default: 9090
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
        printf 'ERROR: loopback port 127.0.0.1:%s is already in use; rerun with a free port via --grafana-port or --prometheus-port\n' "${port}" >&2
        exit 1
    fi
}

cleanup_current_port_forward() {
    if [[ -n "${CURRENT_PORT_FORWARD_PID}" ]]; then
        kill "${CURRENT_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
        wait "${CURRENT_PORT_FORWARD_PID}" >/dev/null 2>&1 || true
        CURRENT_PORT_FORWARD_PID=""
    fi

    if [[ -n "${CURRENT_PORT_FORWARD_LOG}" ]]; then
        rm -f "${CURRENT_PORT_FORWARD_LOG}"
        CURRENT_PORT_FORWARD_LOG=""
    fi
}

wait_for_url() {
    local url="$1"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

    while (( SECONDS < deadline )); do
        if curl -fsS --max-time 2 "${url}" >/dev/null; then
            return 0
        fi

        sleep "${POLL_INTERVAL_SECONDS}"
    done

    return 1
}

run_port_forward_check() {
    local label="$1"
    local resource="$2"
    local local_port="$3"
    local remote_port="$4"
    local url="$5"
    local log_file
    local pid

    ensure_loopback_port_is_free "${local_port}"

    log_file="$(mktemp)"
    kubectl port-forward -n "${MONITORING_NAMESPACE}" "${resource}" \
        "${local_port}:${remote_port}" --address 127.0.0.1 >"${log_file}" 2>&1 &
    pid=$!
    CURRENT_PORT_FORWARD_PID="${pid}"
    CURRENT_PORT_FORWARD_LOG="${log_file}"

    if wait_for_url "${url}"; then
        printf '[PASS] %s via %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}"
        cleanup_current_port_forward
        return 0
    fi

    printf 'ERROR: %s health check failed for %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}" >&2
    printf 'Port-forward log:\n' >&2
    cat "${log_file}" >&2
    cleanup_current_port_forward
    return 1
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
require_positive_integer "--wait-timeout" "${WAIT_TIMEOUT_SECONDS}"
require_positive_integer "--poll-interval" "${POLL_INTERVAL_SECONDS}"
require_cluster_access
require_service "${GRAFANA_RESOURCE}"
require_service "${PROMETHEUS_RESOURCE}"
trap cleanup_current_port_forward EXIT INT TERM

printf 'Using kubectl context: %s\n' "$(kubectl config current-context)"

run_port_forward_check \
    "Grafana health" \
    "${GRAFANA_RESOURCE}" \
    "${GRAFANA_LOCAL_PORT}" \
    "${GRAFANA_REMOTE_PORT}" \
    "http://127.0.0.1:${GRAFANA_LOCAL_PORT}/api/health"

run_port_forward_check \
    "Prometheus readiness" \
    "${PROMETHEUS_RESOURCE}" \
    "${PROMETHEUS_LOCAL_PORT}" \
    "${PROMETHEUS_REMOTE_PORT}" \
    "http://127.0.0.1:${PROMETHEUS_LOCAL_PORT}/-/ready"

printf 'Observability port-forward verification passed.\n'
