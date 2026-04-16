#!/usr/bin/env bash

PHASE4_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHASE4_REPO_ROOT="$(cd "${PHASE4_COMMON_DIR}/../../.." && pwd)"
readonly PHASE4_COMMON_DIR
readonly PHASE4_REPO_ROOT

# shellcheck source=deploy/scripts/lib/phase-4-version-contract.sh
source "${PHASE4_COMMON_DIR}/phase-4-version-contract.sh"
# shellcheck source=scripts/lib/pinned-tool-versions.sh
source "${PHASE4_REPO_ROOT}/scripts/lib/pinned-tool-versions.sh"

PHASE4_INSTANCE_ENV_FILE="${INSTANCE_ENV_FILE:-${HOME}/.config/budget-analyzer/instance.env}"
readonly PHASE4_INSTANCE_ENV_FILE
PHASE4_DEFAULT_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
readonly PHASE4_DEFAULT_KUBECONFIG
PHASE4_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/phase-4"
readonly PHASE4_RENDER_ROOT
PHASE4_INGRESS_GATEWAY_NAMESPACE="istio-ingress"
readonly PHASE4_INGRESS_GATEWAY_NAMESPACE
PHASE4_INGRESS_GATEWAY_NAME="istio-ingress-gateway"
readonly PHASE4_INGRESS_GATEWAY_NAME
PHASE4_INGRESS_GATEWAY_LABEL_SELECTOR="gateway.networking.k8s.io/gateway-name=${PHASE4_INGRESS_GATEWAY_NAME}"
readonly PHASE4_INGRESS_GATEWAY_LABEL_SELECTOR

phase4_info() {
    printf '[phase4] %s\n' "$*"
}

phase4_warn() {
    printf '[phase4] WARN: %s\n' "$*" >&2
}

phase4_die() {
    printf '[phase4] ERROR: %s\n' "$*" >&2
    exit 1
}

phase4_command_install_hint() {
    local command_name="$1"

    case "${command_name}" in
        kubectl|helm|tilt|mkcert|kubeconform|kube-linter|kyverno)
            phase7_install_hint "${command_name}" "${PHASE4_REPO_ROOT}"
            ;;
        *)
            return 1
            ;;
    esac
}

phase4_require_commands() {
    local command_name
    local install_hint

    for command_name in "$@"; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            if install_hint="$(phase4_command_install_hint "${command_name}")"; then
                phase4_die "required command not found: ${command_name}. Install with: ${install_hint}"
            fi

            phase4_die "required command not found: ${command_name}"
        fi
    done
}

phase4_use_default_kubeconfig() {
    if [[ -z "${KUBECONFIG:-}" && -f "${PHASE4_DEFAULT_KUBECONFIG}" ]]; then
        export KUBECONFIG="${PHASE4_DEFAULT_KUBECONFIG}"
    fi
}

phase4_load_instance_env() {
    if [[ ! -f "${PHASE4_INSTANCE_ENV_FILE}" ]]; then
        phase4_die "missing instance config at ${PHASE4_INSTANCE_ENV_FILE}; copy deploy/instance.env.template there first"
    fi

    set -a
    # shellcheck disable=SC1090
    source "${PHASE4_INSTANCE_ENV_FILE}"
    set +a

    phase4_use_default_kubeconfig
}

phase4_require_env_vars() {
    local variable_name
    local missing=()

    for variable_name in "$@"; do
        if [[ -z "${!variable_name:-}" ]]; then
            missing+=("${variable_name}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        phase4_die "missing required environment values in ${PHASE4_INSTANCE_ENV_FILE}: ${missing[*]}"
    fi
}

phase4_require_cluster_access() {
    phase4_use_default_kubeconfig
    kubectl cluster-info >/dev/null 2>&1 || phase4_die "cannot reach the Kubernetes cluster from the current kubectl context"
}

phase4_run_sudo() {
    if (( EUID == 0 )); then
        "$@"
        return
    fi

    sudo "$@"
}

phase4_repo_path() {
    printf '%s/%s\n' "${PHASE4_REPO_ROOT}" "$1"
}

phase4_render_output_dir() {
    mkdir -p "${PHASE4_RENDER_ROOT}"
    printf '%s\n' "${PHASE4_RENDER_ROOT}"
}

phase4_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

phase4_render_template() {
    local template_path="$1"
    local output_path="$2"
    local placeholder
    local value
    local escaped_value
    local rendered

    [[ -f "${template_path}" ]] || phase4_die "missing template: ${template_path}"

    rendered=$(cat "${template_path}")
    shift 2

    while [[ $# -gt 0 ]]; do
        placeholder="${1%%=*}"
        value="${1#*=}"
        escaped_value=$(phase4_escape_sed_replacement "${value}")
        rendered=$(printf '%s' "${rendered}" | sed "s|__${placeholder}__|${escaped_value}|g")
        shift
    done

    printf '%s\n' "${rendered}" > "${output_path}"

    if grep -Eq '__[A-Z0-9_]+__' "${output_path}"; then
        phase4_die "unrendered placeholders remain in ${output_path}"
    fi
}

phase4_create_or_update_namespace() {
    local namespace="$1"

    kubectl create namespace "${namespace}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

phase4_label_namespace() {
    local namespace="$1"
    shift

    kubectl label namespace "${namespace}" "$@" --overwrite >/dev/null
}

phase4_ensure_helm_repo() {
    local name="$1"
    local url="$2"

    if helm repo list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "${name}"; then
        helm repo add "${name}" "${url}" --force-update >/dev/null
        return
    fi

    helm repo add "${name}" "${url}" >/dev/null
}

phase4_find_service_nodeport() {
    local namespace="$1"
    local service_name="$2"
    local service_port="$3"

    kubectl get service "${service_name}" -n "${namespace}" \
        -o jsonpath="{.spec.ports[?(@.port==${service_port})].nodePort}" 2>/dev/null || true
}

phase4_ingress_service_name() {
    kubectl get service -n "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" \
        -l "${PHASE4_INGRESS_GATEWAY_LABEL_SELECTOR}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

phase4_list_nat_redirect_delete_rules() {
    local public_port="$1"

    phase4_run_sudo iptables -t nat -S PREROUTING | awk -v port="${public_port}" '
        $1 == "-A" && $2 == "PREROUTING" &&
        $0 ~ ("-p tcp") &&
        $0 ~ ("--dport " port " ") &&
        $0 ~ /-j REDIRECT/ {
            sub(/^-A /, "-D ")
            print
        }
    '
}

phase4_remove_nat_redirects() {
    local public_port="$1"
    local redirect_rules=()
    local rule
    local rule_parts=()
    local stale_rule_removed=false

    mapfile -t redirect_rules < <(phase4_list_nat_redirect_delete_rules "${public_port}")

    for rule in "${redirect_rules[@]}"; do
        read -r -a rule_parts <<< "${rule}"
        phase4_run_sudo iptables -t nat "${rule_parts[@]}"
        stale_rule_removed=true
    done

    if [[ "${stale_rule_removed}" == true ]]; then
        phase4_info "removed stale iptables redirect(s) for port ${public_port}"
    else
        phase4_info "no iptables redirects to remove for port ${public_port}"
    fi
}

phase4_add_nat_redirect() {
    local public_port="$1"
    local node_port="$2"
    local redirect_rules=()
    local rule
    local rule_parts=()
    local stale_rule_removed=false

    mapfile -t redirect_rules < <(phase4_list_nat_redirect_delete_rules "${public_port}")

    for rule in "${redirect_rules[@]}"; do
        read -r -a rule_parts <<< "${rule}"
        phase4_run_sudo iptables -t nat "${rule_parts[@]}"
        stale_rule_removed=true
    done

    # Insert before kube-proxy's KUBE-SERVICES jump so external traffic is
    # rewritten to the NodePort before kube-proxy evaluates service rules.
    phase4_run_sudo iptables -t nat -I PREROUTING 1 -p tcp --dport "${public_port}" -j REDIRECT --to-port "${node_port}"
    if [[ "${stale_rule_removed}" == true ]]; then
        phase4_info "reconciled iptables redirect ${public_port} -> ${node_port} at the top of PREROUTING"
    else
        phase4_info "added iptables redirect ${public_port} -> ${node_port} at the top of PREROUTING"
    fi
}
