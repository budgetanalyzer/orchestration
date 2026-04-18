#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_WAIT_TIMEOUT="${PHASE4_HELM_WAIT_TIMEOUT:-10m}"
readonly HELM_WAIT_TIMEOUT

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

on_install_error() {
    local exit_code="$?"

    phase4_warn "platform controller install failed; collecting diagnostics"
    show_helm_release_diagnostics external-secrets external-secrets
    show_namespace_diagnostics external-secrets
    show_helm_release_diagnostics cert-manager cert-manager
    show_namespace_diagnostics cert-manager
    exit "${exit_code}"
}

trap on_install_error ERR

phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access

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

phase4_info "controller namespace snapshot"
kubectl get pods -n external-secrets
kubectl get pods -n cert-manager
