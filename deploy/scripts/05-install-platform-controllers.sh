#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_WAIT_TIMEOUT="${PHASE4_HELM_WAIT_TIMEOUT:-10m}"
PLATFORM_CONTROLLERS="${PHASE4_PLATFORM_CONTROLLERS:-all}"
readonly HELM_WAIT_TIMEOUT
readonly PLATFORM_CONTROLLERS

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

show_namespace_diagnostics() {
    local namespace="$1"

    phase4_warn "namespace snapshot for ${namespace}"
    kubectl get deployments,replicasets,pods,jobs -n "${namespace}" || true

    phase4_warn "recent events for ${namespace}"
    kubectl get events -n "${namespace}" --sort-by=.metadata.creationTimestamp | tail -n 40 || true
}

show_helm_release_diagnostics() {
    local release_name="$1"
    local namespace="$2"

    phase4_warn "helm status for ${release_name} in ${namespace}"
    helm status "${release_name}" --namespace "${namespace}" || true
}

controller_selected() {
    local controller_name="$1"

    case ",${PLATFORM_CONTROLLERS}," in
        *,all,*|*,"${controller_name}",*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_valid_controller_selection() {
    local selection
    local selected_controller

    IFS=',' read -r -a selection <<< "${PLATFORM_CONTROLLERS}"

    if (( ${#selection[@]} == 0 )); then
        phase4_die "PHASE4_PLATFORM_CONTROLLERS must be all, cert-manager, external-secrets, or cert-manager,external-secrets"
    fi

    for selected_controller in "${selection[@]}"; do
        case "${selected_controller}" in
            all|cert-manager|external-secrets)
                ;;
            *)
                phase4_die "unsupported PHASE4_PLATFORM_CONTROLLERS value: ${selected_controller}"
                ;;
        esac
    done
}

on_install_error() {
    local exit_code="$?"

    phase4_warn "platform controller install failed; collecting diagnostics"

    if controller_selected external-secrets; then
        show_helm_release_diagnostics external-secrets external-secrets
        show_namespace_diagnostics external-secrets
    fi

    if controller_selected cert-manager; then
        show_helm_release_diagnostics cert-manager cert-manager
        show_namespace_diagnostics cert-manager
    fi

    exit "${exit_code}"
}

trap on_install_error ERR

phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access
require_valid_controller_selection

if controller_selected external-secrets; then
    phase4_info "updating Helm repo external-secrets"
    phase4_ensure_helm_repo external-secrets "${PHASE4_EXTERNAL_SECRETS_HELM_REPO_URL}"
    helm repo update external-secrets >/dev/null

    phase4_info "installing External Secrets Operator ${PHASE4_EXTERNAL_SECRETS_CHART_VERSION} (timeout ${HELM_WAIT_TIMEOUT})"
    helm upgrade --install external-secrets external-secrets/external-secrets \
        --namespace external-secrets \
        --create-namespace \
        --version "${PHASE4_EXTERNAL_SECRETS_CHART_VERSION}" \
        --values "$(phase4_repo_path "deploy/helm-values/external-secrets.values.yaml")" \
        --wait \
        --timeout "${HELM_WAIT_TIMEOUT}"
fi

if controller_selected cert-manager; then
    phase4_info "updating Helm repo jetstack"
    phase4_ensure_helm_repo jetstack "${PHASE4_CERT_MANAGER_HELM_REPO_URL}"
    helm repo update jetstack >/dev/null

    phase4_info "installing cert-manager ${PHASE4_CERT_MANAGER_CHART_VERSION} (timeout ${HELM_WAIT_TIMEOUT})"
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version "${PHASE4_CERT_MANAGER_CHART_VERSION}" \
        --values "$(phase4_repo_path "deploy/helm-values/cert-manager.values.yaml")" \
        --wait \
        --timeout "${HELM_WAIT_TIMEOUT}"
fi

phase4_info "controller namespace snapshot"
if controller_selected external-secrets; then
    kubectl get pods -n external-secrets
fi
if controller_selected cert-manager; then
    kubectl get pods -n cert-manager
fi
