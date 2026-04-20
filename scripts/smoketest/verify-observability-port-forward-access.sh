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
declare -A PORT_FORWARD_MODES=()

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-observability-port-forward-access.sh [options]

Starts temporary loopback-only kubectl port-forwards for Grafana, Prometheus,
Jaeger, and Kiali when they are not already present, reuses expected existing
loopback forwards on the canonical ports when they are already running, then
checks the local endpoints and confirms Grafana and Kiali unauthenticated API
access is rejected.

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

loopback_port_is_free() {
    local port="$1"

    python3 - "${port}" <<'PY'
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
}

# shellcheck disable=SC2317  # Invoked indirectly by trap cleanup_port_forwards EXIT INT TERM.
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

linux_proc_listener_records() {
    local port="$1"

    python3 - "${port}" <<'PY'
import os
import socket
import sys

port = int(sys.argv[1])
target_port_hex = f"{port:04X}"
records = []

if os.path.exists("/proc/net/tcp"):
    with open("/proc/net/tcp", encoding="utf-8") as tcp_file:
        next(tcp_file, None)
        for line in tcp_file:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            local_address = fields[1]
            ip_hex, port_hex = local_address.split(":")
            if port_hex.upper() != target_port_hex:
                continue
            ip = socket.inet_ntoa(bytes.fromhex(ip_hex)[::-1])
            records.append((ip, fields[9]))

inode_to_pids = {}
for pid in filter(str.isdigit, os.listdir("/proc")):
    fd_dir = f"/proc/{pid}/fd"
    try:
        fd_names = os.listdir(fd_dir)
    except OSError:
        continue

    for fd_name in fd_names:
        fd_path = f"{fd_dir}/{fd_name}"
        try:
            target = os.readlink(fd_path)
        except OSError:
            continue
        if not target.startswith("socket:[") or not target.endswith("]"):
            continue
        inode = target[8:-1]
        inode_to_pids.setdefault(inode, set()).add(pid)

for address, inode in records:
    pids = sorted(inode_to_pids.get(inode, set()), key=int)
    if not pids:
        print(f"{address}:{port}\t\t")
        continue
    for pid in pids:
        cmdline_path = f"/proc/{pid}/cmdline"
        command = ""
        try:
            with open(cmdline_path, "rb") as cmdline_file:
                parts = [part.decode("utf-8", "replace") for part in cmdline_file.read().split(b"\0") if part]
                command = " ".join(parts)
        except OSError:
            pass
        print(f"{address}:{port}\t{pid}\t{command}")
PY
}

listener_details() {
    local port="$1"

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | tail -n +2 || true
    elif command -v ss >/dev/null 2>&1; then
        ss -H -ltnp "( sport = :${port} )" 2>/dev/null || true
    elif [[ -r /proc/net/tcp ]]; then
        linux_proc_listener_records "${port}" | awk -F '\t' '
            NF {
                printf "address=%s", $1
                if ($2 != "") {
                    printf " pid=%s", $2
                }
                if ($3 != "") {
                    printf " command=%s", $3
                }
                printf "\n"
            }
        '
    fi
}

listener_addresses() {
    local port="$1"

    if command -v lsof >/dev/null 2>&1; then
        lsof -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | awk 'NR > 1 {print $9}'
    elif command -v ss >/dev/null 2>&1; then
        ss -H -ltnp "( sport = :${port} )" 2>/dev/null | awk '{print $4}'
    elif [[ -r /proc/net/tcp ]]; then
        linux_proc_listener_records "${port}" | awk -F '\t' 'NF {print $1}'
    fi
}

listener_pids() {
    local port="$1"

    if command -v lsof >/dev/null 2>&1; then
        lsof -t -nP -iTCP:"${port}" -sTCP:LISTEN 2>/dev/null | sort -u
    elif command -v ss >/dev/null 2>&1; then
        ss -H -ltnp "( sport = :${port} )" 2>/dev/null | grep -o 'pid=[0-9]\+' | cut -d= -f2 | sort -u
    elif [[ -r /proc/net/tcp ]]; then
        linux_proc_listener_records "${port}" | awk -F '\t' '$2 != "" {print $2}' | sort -u
    fi
}

is_loopback_listener_address() {
    local address="$1"

    case "${address}" in
        127.0.0.1:*|localhost:*|'[::1]':*|::1:*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

listener_is_loopback_only() {
    local port="$1"
    local address
    local found=0

    while IFS= read -r address; do
        [[ -n "${address}" ]] || continue
        found=1
        if ! is_loopback_listener_address "${address}"; then
            return 1
        fi
    done < <(listener_addresses "${port}")

    [[ "${found}" -eq 1 ]]
}

command_matches_expected_port_forward() {
    local command="$1"
    local expected_resource_name="$2"
    local local_port="$3"
    local remote_port="$4"

    [[ "${command}" == *kubectl* ]] || return 1
    [[ "${command}" == *port-forward* ]] || return 1
    [[ "${command}" == *"${MONITORING_NAMESPACE}"* ]] || return 1
    [[ "${command}" == *"${expected_resource_name}"* ]] || return 1
    [[ "${command}" == *"${local_port}:${remote_port}"* ]] || return 1

    return 0
}

expected_listener_commands() {
    local port="$1"
    local pid
    local command

    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        command="$(ps -o command= -p "${pid}" 2>/dev/null || true)"
        if [[ -n "${command}" ]]; then
            printf '%s\n' "${command}"
        fi
    done < <(listener_pids "${port}")
}

fail_unexpected_listener() {
    local port="$1"
    local expected_owner="$2"
    local details
    local commands

    details="$(listener_details "${port}")"
    commands="$(expected_listener_commands "${port}")"

    printf 'ERROR: loopback port 127.0.0.1:%s is already in use by an unexpected listener.\n' "${port}" >&2
    printf 'Expected owner: %s\n' "${expected_owner}" >&2
    if [[ -n "${details}" ]]; then
        printf 'Current listener details:\n%s\n' "${details}" >&2
    fi
    if [[ -n "${commands}" ]]; then
        printf 'Current listener commands:\n%s\n' "${commands}" >&2
    fi
    printf 'Use a free port via --grafana-port, --prometheus-port, --jaeger-port, or --kiali-port if this listener is intentional.\n' >&2
    exit 1
}

reuse_existing_port_forward() {
    local name="$1"
    local label="$2"
    local local_port="$3"
    local remote_port="$4"
    local expected_owner="$5"
    local expected_resource_name="$6"
    local pid
    local command

    if ! command -v lsof >/dev/null 2>&1 && ! command -v ss >/dev/null 2>&1 && [[ ! -r /proc/net/tcp ]]; then
        printf 'ERROR: loopback port 127.0.0.1:%s is already in use, but no supported listener-inspection method is available.\n' \
            "${local_port}" >&2
        printf 'Expected owner: %s\n' "${expected_owner}" >&2
        exit 1
    fi

    if ! listener_is_loopback_only "${local_port}"; then
        fail_unexpected_listener "${local_port}" "${expected_owner}"
    fi

    while IFS= read -r pid; do
        [[ -n "${pid}" ]] || continue
        command="$(ps -o command= -p "${pid}" 2>/dev/null || true)"
        if command_matches_expected_port_forward "${command}" "${expected_resource_name}" "${local_port}" "${remote_port}"; then
            PORT_FORWARD_MODES["${name}"]="reused"
            printf 'Reusing existing %s loopback port-forward on 127.0.0.1:%s\n' "${label}" "${local_port}"
            return 0
        fi
    done < <(listener_pids "${local_port}")

    fail_unexpected_listener "${local_port}" "${expected_owner}"
}

wait_for_started_url() {
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

wait_for_existing_url() {
    local label="$1"
    local url="$2"
    local local_port="$3"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    local details
    local commands

    while (( SECONDS < deadline )); do
        if curl -fsS --max-time 2 "${url}" >/dev/null; then
            return 0
        fi

        sleep "${POLL_INTERVAL_SECONDS}"
    done

    details="$(listener_details "${local_port}")"
    commands="$(expected_listener_commands "${local_port}")"
    printf 'ERROR: %s health check timed out for existing listener on 127.0.0.1:%s (%s)\n' \
        "${label}" "${local_port}" "${url}" >&2
    if [[ -n "${details}" ]]; then
        printf 'Current listener details:\n%s\n' "${details}" >&2
    fi
    if [[ -n "${commands}" ]]; then
        printf 'Current listener commands:\n%s\n' "${commands}" >&2
    fi
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

    if ! loopback_port_is_free "${local_port}"; then
        reuse_existing_port_forward "${name}" "${label}" "${local_port}" "${remote_port}" "${expected_owner}" "${resource#*/}"
        return 0
    fi

    log_file="$(mktemp)"
    kubectl port-forward -n "${MONITORING_NAMESPACE}" "${resource}" \
        "${local_port}:${remote_port}" --address 127.0.0.1 >"${log_file}" 2>&1 &
    pid=$!
    PORT_FORWARD_PIDS["${name}"]="${pid}"
    PORT_FORWARD_LOGS["${name}"]="${log_file}"
    PORT_FORWARD_MODES["${name}"]="started"

    printf 'Started %s port-forward for %s on 127.0.0.1:%s\n' "${label}" "${resource}" "${local_port}"
}

wait_for_port_forward_health() {
    local name="$1"
    local label="$2"
    local resource="$3"
    local local_port="$4"
    local url="$5"

    if [[ "${PORT_FORWARD_MODES[${name}]:-}" == "reused" ]]; then
        if wait_for_existing_url "${label}" "${url}" "${local_port}"; then
            printf '[PASS] %s via existing listener on 127.0.0.1:%s\n' "${label}" "${local_port}"
            return 0
        fi

        return 1
    fi

    if wait_for_started_url "${label}" "${url}" "${PORT_FORWARD_PIDS[${name}]}" "${PORT_FORWARD_LOGS[${name}]}"; then
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
