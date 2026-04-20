#!/usr/bin/env bash
# Opens workstation-to-OCI SSH tunnels for the loopback-only observability UIs.

set -euo pipefail

DEFAULT_COMPONENTS=(grafana prometheus jaeger kiali)

GRAFANA_LOCAL_PORT=3300
GRAFANA_REMOTE_PORT=3300

PROMETHEUS_LOCAL_PORT=9090
PROMETHEUS_REMOTE_PORT=9090

JAEGER_LOCAL_PORT=16686
JAEGER_REMOTE_PORT=16686

KIALI_LOCAL_PORT=20001
KIALI_REMOTE_PORT=20001

SSH_USER="${BUDGET_ANALYZER_OCI_SSH_USER:-ubuntu}"
SSH_KEY="${BUDGET_ANALYZER_OCI_SSH_KEY:-${HOME}/.ssh/oci-budgetanalyzer}"

WAIT_TIMEOUT_SECONDS="${BUDGET_ANALYZER_OCI_TUNNEL_WAIT_TIMEOUT:-30}"
POLL_INTERVAL_SECONDS="${BUDGET_ANALYZER_OCI_TUNNEL_POLL_INTERVAL:-1}"

SSH_PID=""
SSH_LOG=""
SHUTTING_DOWN=0
CLEANUP_COMPLETE=0

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/start-observability-ssh-tunnels.sh [OCI_HOST]

Starts one foreground SSH session with loopback-only local tunnels for the
canonical production observability ports:

  - Grafana:    http://127.0.0.1:3300
  - Prometheus: http://127.0.0.1:9090
  - Jaeger:     http://127.0.0.1:16686/jaeger
  - Kiali:      http://127.0.0.1:20001/kiali

The OCI host must already be running the matching loopback-bound Kubernetes
port-forwards, for example through:

  ./scripts/ops/start-observability-port-forwards.sh

Assumptions:
  - SSH user: ubuntu
  - SSH key:  ~/.ssh/oci-budgetanalyzer
  - OCI host: OCI_HOST argument, or OCI_INSTANCE_IP from the environment

Optional environment overrides:
  OCI_INSTANCE_IP
  BUDGET_ANALYZER_OCI_SSH_USER
  BUDGET_ANALYZER_OCI_SSH_KEY
  BUDGET_ANALYZER_OCI_TUNNEL_WAIT_TIMEOUT
  BUDGET_ANALYZER_OCI_TUNNEL_POLL_INTERVAL

Example:
  ./scripts/ops/start-observability-ssh-tunnels.sh 152.70.145.68
  OCI_INSTANCE_IP=152.70.145.68 ./scripts/ops/start-observability-ssh-tunnels.sh

Press Ctrl+C to stop the SSH tunnel.
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

require_ssh_key() {
    if [[ ! -r "${SSH_KEY}" ]]; then
        printf 'ERROR: SSH key is not readable: %s\n' "${SSH_KEY}" >&2
        printf 'Set BUDGET_ANALYZER_OCI_SSH_KEY to override the default key path.\n' >&2
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

# shellcheck disable=SC2317  # Invoked indirectly by trap cleanup_ssh_tunnel EXIT.
cleanup_ssh_tunnel() {
    if [[ "${CLEANUP_COMPLETE}" -eq 1 ]]; then
        return 0
    fi
    CLEANUP_COMPLETE=1

    if [[ -n "${SSH_PID}" ]]; then
        kill "${SSH_PID}" >/dev/null 2>&1 || true
        wait "${SSH_PID}" >/dev/null 2>&1 || true
    fi

    if [[ -n "${SSH_LOG}" ]]; then
        rm -f "${SSH_LOG}"
    fi
}

# shellcheck disable=SC2317  # Invoked indirectly by trap handle_shutdown_signal INT TERM.
handle_shutdown_signal() {
    SHUTTING_DOWN=1
    printf '\nStopping observability SSH tunnel...\n'
    cleanup_ssh_tunnel
    exit 0
}

wait_for_url() {
    local label="$1"
    local url="$2"
    local deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))

    while (( SECONDS < deadline )); do
        if [[ -z "${SSH_PID}" ]] || ! kill -0 "${SSH_PID}" >/dev/null 2>&1; then
            printf 'ERROR: SSH tunnel exited before %s became ready\n' "${url}" >&2
            printf 'SSH log:\n' >&2
            cat "${SSH_LOG}" >&2
            return 1
        fi

        if curl -fsS --max-time 2 "${url}" >/dev/null 2>&1; then
            return 0
        fi

        sleep "${POLL_INTERVAL_SECONDS}"
    done

    printf 'ERROR: %s health check timed out for %s\n' "${label}" "${url}" >&2
    printf 'Confirm the OCI host is running ./scripts/ops/start-observability-port-forwards.sh.\n' >&2
    printf 'SSH log:\n' >&2
    cat "${SSH_LOG}" >&2
    return 1
}

start_ssh_tunnel() {
    local oci_host="$1"
    local target="${SSH_USER}@${oci_host}"
    local component
    local local_port
    local remote_port
    declare -a ssh_args=()

    SSH_LOG="$(mktemp)"

    for component in "${DEFAULT_COMPONENTS[@]}"; do
        local_port="$(component_local_port "${component}")"
        remote_port="$(component_remote_port "${component}")"
        ssh_args+=("-L" "127.0.0.1:${local_port}:127.0.0.1:${remote_port}")
    done

    ssh \
        -i "${SSH_KEY}" \
        -N \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        "${ssh_args[@]}" \
        "${target}" >"${SSH_LOG}" 2>&1 &
    SSH_PID=$!

    printf 'Started observability SSH tunnel to %s with PID %s\n' "${target}" "${SSH_PID}"
}

wait_for_component_health() {
    local component="$1"
    local label
    local local_port
    local health_url

    label="$(component_label "${component}")"
    local_port="$(component_local_port "${component}")"
    health_url="$(component_health_url "${component}" "${local_port}")"

    if wait_for_url "${label}" "${health_url}"; then
        printf '[READY] %s on %s\n' "${label}" "$(component_local_url "${component}" "${local_port}")"
        return 0
    fi

    return 1
}

print_access_summary() {
    local oci_host="$1"
    local component
    local label
    local local_port

    printf '\nObservability SSH tunnels are ready and bound to 127.0.0.1 only:\n'
    for component in "${DEFAULT_COMPONENTS[@]}"; do
        label="$(component_label "${component}")"
        local_port="$(component_local_port "${component}")"
        printf '  - %s: %s\n' "${label}" "$(component_local_url "${component}" "${local_port}")"
    done

    printf '\nCredentials still come from commands on the OCI host:\n'
    printf '  Grafana password: ssh -i "%s" "%s@%s" '\''kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 --decode; echo'\''\n' \
        "${SSH_KEY}" "${SSH_USER}" "${oci_host}"
    printf '  Kiali token:      ssh -i "%s" "%s@%s" '\''kubectl -n monitoring create token kiali'\''\n' \
        "${SSH_KEY}" "${SSH_USER}" "${oci_host}"

    printf '\nPress Ctrl+C to stop the SSH tunnel.\n'
}

monitor_ssh_tunnel() {
    local wait_status

    set +e
    wait "${SSH_PID}"
    wait_status=$?
    set -e

    if [[ "${SHUTTING_DOWN}" -eq 1 ]]; then
        return 0
    fi

    if [[ "${wait_status}" -eq 0 ]]; then
        printf 'Observability SSH tunnel closed.\n'
        return 0
    fi

    printf 'ERROR: observability SSH tunnel exited unexpectedly with status %s.\n' "${wait_status}" >&2
    if [[ -f "${SSH_LOG}" ]]; then
        printf 'SSH log:\n' >&2
        cat "${SSH_LOG}" >&2
    fi
    exit "${wait_status}"
}

main() {
    local oci_host="${1:-${OCI_INSTANCE_IP:-}}"
    local component

    if [[ $# -gt 1 || "${oci_host}" == "-h" || "${oci_host}" == "--help" ]]; then
        usage
        if [[ $# -eq 1 && ( "${oci_host}" == "-h" || "${oci_host}" == "--help" ) ]]; then
            exit 0
        fi
        exit 1
    fi

    if [[ -z "${oci_host}" ]]; then
        printf 'ERROR: OCI host is required. Pass OCI_HOST or set OCI_INSTANCE_IP.\n' >&2
        usage >&2
        exit 1
    fi

    if [[ "${oci_host}" == -* ]]; then
        printf 'ERROR: OCI_HOST must be a hostname or IP address, got: %s\n' "${oci_host}" >&2
        usage >&2
        exit 1
    fi

    require_command ssh
    require_command curl
    require_positive_integer "BUDGET_ANALYZER_OCI_TUNNEL_WAIT_TIMEOUT" "${WAIT_TIMEOUT_SECONDS}"
    require_positive_integer "BUDGET_ANALYZER_OCI_TUNNEL_POLL_INTERVAL" "${POLL_INTERVAL_SECONDS}"
    require_ssh_key
    trap cleanup_ssh_tunnel EXIT
    trap handle_shutdown_signal INT TERM

    start_ssh_tunnel "${oci_host}"

    for component in "${DEFAULT_COMPONENTS[@]}"; do
        wait_for_component_health "${component}"
    done

    print_access_summary "${oci_host}"
    monitor_ssh_tunnel
}

main "$@"
