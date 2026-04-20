#!/usr/bin/env bash
# Starts loopback-only observability port-forwards and keeps them running until interrupted.

set -euo pipefail

MONITORING_NAMESPACE="monitoring"
DEFAULT_COMPONENTS=(grafana prometheus jaeger kiali)

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

declare -a SELECTED_COMPONENTS=()
declare -A PORT_FORWARD_PIDS=()
declare -A PORT_FORWARD_LOGS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/start-observability-port-forwards.sh [options]

Starts loopback-only kubectl port-forwards for Grafana, Prometheus, Jaeger,
and Kiali, then keeps them running in the foreground until interrupted.

Options:
  --component NAME         Forward only the named component. Repeat to select
                           multiple components. Valid names: grafana,
                           prometheus, jaeger, kiali. Default: all four
  --grafana-port PORT      Local loopback port for Grafana. Default: 3300
  --prometheus-port PORT   Local loopback port for Prometheus. Default: 9090
  --jaeger-port PORT       Local loopback port for Jaeger. Default: 16686
  --kiali-port PORT        Local loopback port for Kiali. Default: 20001
  --wait-timeout SECONDS   Max seconds to wait for each forward to become
                           reachable. Default: 30
  --poll-interval SECONDS  Poll interval while waiting. Default: 1
  -h, --help               Show this help text.

Examples:
  ./scripts/ops/start-observability-port-forwards.sh
  ./scripts/ops/start-observability-port-forwards.sh --component grafana --component prometheus
  ./scripts/ops/start-observability-port-forwards.sh --jaeger-port 26686 --kiali-port 30001

This helper binds only to 127.0.0.1 and does not support detached daemon mode.
Press Ctrl+C to stop all started port-forwards.
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

component_label() {
    case "$1" in
        grafana) printf 'Grafana' ;;
        prometheus) printf 'Prometheus' ;;
        jaeger) printf 'Jaeger' ;;
        kiali) printf 'Kiali' ;;
        *)
            printf 'ERROR: unknown component: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

component_resource() {
    case "$1" in
        grafana) printf '%s' "${GRAFANA_RESOURCE}" ;;
        prometheus) printf '%s' "${PROMETHEUS_RESOURCE}" ;;
        jaeger) printf '%s' "${JAEGER_RESOURCE}" ;;
        kiali) printf '%s' "${KIALI_RESOURCE}" ;;
        *)
            printf 'ERROR: unknown component: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

component_local_port() {
    case "$1" in
        grafana) printf '%s' "${GRAFANA_LOCAL_PORT}" ;;
        prometheus) printf '%s' "${PROMETHEUS_LOCAL_PORT}" ;;
        jaeger) printf '%s' "${JAEGER_LOCAL_PORT}" ;;
        kiali) printf '%s' "${KIALI_LOCAL_PORT}" ;;
        *)
            printf 'ERROR: unknown component: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

component_remote_port() {
    case "$1" in
        grafana) printf '%s' "${GRAFANA_REMOTE_PORT}" ;;
        prometheus) printf '%s' "${PROMETHEUS_REMOTE_PORT}" ;;
        jaeger) printf '%s' "${JAEGER_REMOTE_PORT}" ;;
        kiali) printf '%s' "${KIALI_REMOTE_PORT}" ;;
        *)
            printf 'ERROR: unknown component: %s\n' "$1" >&2
            exit 1
            ;;
    esac
}

component_health_url() {
    local component="$1"
    local port="$2"

    case "${component}" in
        grafana) printf 'http://127.0.0.1:%s/api/health' "${port}" ;;
        prometheus) printf 'http://127.0.0.1:%s/-/ready' "${port}" ;;
        jaeger) printf 'http://127.0.0.1:%s/jaeger/api/services' "${port}" ;;
        kiali) printf 'http://127.0.0.1:%s/kiali/' "${port}" ;;
        *)
            printf 'ERROR: unknown component: %s\n' "${component}" >&2
            exit 1
            ;;
    esac
}

component_local_url() {
    local component="$1"
    local port="$2"

    case "${component}" in
        grafana) printf 'http://127.0.0.1:%s' "${port}" ;;
        prometheus) printf 'http://127.0.0.1:%s' "${port}" ;;
        jaeger) printf 'http://127.0.0.1:%s/jaeger' "${port}" ;;
        kiali) printf 'http://127.0.0.1:%s/kiali' "${port}" ;;
        *)
            printf 'ERROR: unknown component: %s\n' "${component}" >&2
            exit 1
            ;;
    esac
}

append_selected_component() {
    local component="$1"
    local existing

    component_label "${component}" >/dev/null

    for existing in "${SELECTED_COMPONENTS[@]:-}"; do
        if [[ "${existing}" == "${component}" ]]; then
            return 0
        fi
    done

    SELECTED_COMPONENTS+=("${component}")
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
        printf 'Pick a different local port with the matching --*-port flag or stop the competing listener.\n' >&2
        exit 1
    fi
}

assert_distinct_local_ports() {
    local component
    local port
    local label
    local seen_component
    declare -A seen_ports=()

    for component in "${SELECTED_COMPONENTS[@]}"; do
        port="$(component_local_port "${component}")"
        label="$(component_label "${component}")"
        seen_component="${seen_ports[${port}]:-}"
        if [[ -n "${seen_component}" ]]; then
            printf 'ERROR: %s and %s cannot use the same local port %s in one helper run\n' \
                "$(component_label "${seen_component}")" "${label}" "${port}" >&2
            exit 1
        fi
        seen_ports["${port}"]="${component}"
    done
}

# shellcheck disable=SC2317  # Invoked indirectly by trap cleanup_port_forwards EXIT INT TERM.
cleanup_port_forwards() {
    local component

    for component in "${!PORT_FORWARD_PIDS[@]}"; do
        kill "${PORT_FORWARD_PIDS[${component}]}" >/dev/null 2>&1 || true
    done

    for component in "${!PORT_FORWARD_PIDS[@]}"; do
        wait "${PORT_FORWARD_PIDS[${component}]}" >/dev/null 2>&1 || true
    done

    for component in "${!PORT_FORWARD_LOGS[@]}"; do
        rm -f "${PORT_FORWARD_LOGS[${component}]}"
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
    local component="$1"
    local label
    local resource
    local local_port
    local remote_port
    local log_file
    local pid

    label="$(component_label "${component}")"
    resource="$(component_resource "${component}")"
    local_port="$(component_local_port "${component}")"
    remote_port="$(component_remote_port "${component}")"

    ensure_loopback_port_is_free \
        "${local_port}" \
        "kubectl port-forward -n ${MONITORING_NAMESPACE} ${resource} ${local_port}:${remote_port} --address 127.0.0.1"

    log_file="$(mktemp)"
    kubectl port-forward -n "${MONITORING_NAMESPACE}" "${resource}" \
        "${local_port}:${remote_port}" --address 127.0.0.1 >"${log_file}" 2>&1 &
    pid=$!

    PORT_FORWARD_PIDS["${component}"]="${pid}"
    PORT_FORWARD_LOGS["${component}"]="${log_file}"

    printf 'Started %s port-forward for %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}"
}

wait_for_component_health() {
    local component="$1"
    local label
    local local_port
    local health_url

    label="$(component_label "${component}")"
    local_port="$(component_local_port "${component}")"
    health_url="$(component_health_url "${component}" "${local_port}")"

    if wait_for_url \
        "${label}" \
        "${health_url}" \
        "${PORT_FORWARD_PIDS[${component}]}" \
        "${PORT_FORWARD_LOGS[${component}]}"; then
        printf '[READY] %s on %s\n' "${label}" "$(component_local_url "${component}" "${local_port}")"
        return 0
    fi

    return 1
}

print_access_summary() {
    local component
    local label
    local local_port

    printf '\nObservability port-forwards are ready and bound to 127.0.0.1 only:\n'
    for component in "${SELECTED_COMPONENTS[@]}"; do
        label="$(component_label "${component}")"
        local_port="$(component_local_port "${component}")"
        printf '  - %s: %s\n' "${label}" "$(component_local_url "${component}" "${local_port}")"
    done

    if [[ " ${SELECTED_COMPONENTS[*]} " == *" grafana "* ]]; then
        printf '\nGrafana admin password:\n'
        printf '  kubectl get secret -n monitoring prometheus-stack-grafana \\\n'
        printf '    -o jsonpath="{.data.admin-password}" | base64 --decode\n'
        printf '  echo\n'
    fi

    if [[ " ${SELECTED_COMPONENTS[*]} " == *" kiali "* ]]; then
        printf '\nKiali login token:\n'
        printf '  kubectl -n monitoring create token kiali\n'
    fi

    printf '\nPress Ctrl+C to stop all started port-forwards.\n'
}

monitor_port_forwards() {
    local component

    set +e
    wait -n
    set -e

    for component in "${SELECTED_COMPONENTS[@]}"; do
        if ! kill -0 "${PORT_FORWARD_PIDS[${component}]}" >/dev/null 2>&1; then
            printf 'ERROR: %s port-forward exited unexpectedly.\n' "$(component_label "${component}")" >&2
            printf 'Port-forward log:\n' >&2
            cat "${PORT_FORWARD_LOGS[${component}]}" >&2
            exit 1
        fi
    done

    exit 1
}

main() {
    local component

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --component)
                append_selected_component "${2:-}"
                shift 2
                ;;
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

    if [[ "${#SELECTED_COMPONENTS[@]}" -eq 0 ]]; then
        SELECTED_COMPONENTS=("${DEFAULT_COMPONENTS[@]}")
    fi

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
    trap cleanup_port_forwards EXIT INT TERM

    printf 'Using kubectl context: %s\n' "$(kubectl config current-context)"

    for component in "${SELECTED_COMPONENTS[@]}"; do
        require_service "$(component_resource "${component}")"
    done

    for component in "${SELECTED_COMPONENTS[@]}"; do
        start_port_forward "${component}"
    done

    for component in "${SELECTED_COMPONENTS[@]}"; do
        wait_for_component_health "${component}"
    done

    print_access_summary
    monitor_port_forwards
}

main "$@"
