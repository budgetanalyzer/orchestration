#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access

phase4_info "installing External Secrets Operator ${PHASE4_EXTERNAL_SECRETS_CHART_VERSION}"
phase4_ensure_helm_repo external-secrets "${PHASE4_EXTERNAL_SECRETS_HELM_REPO_URL}"
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
    --namespace external-secrets \
    --version "${PHASE4_EXTERNAL_SECRETS_CHART_VERSION}" \
    --values "$(phase4_repo_path "deploy/helm-values/external-secrets.values.yaml")" \
    --wait

phase4_info "installing cert-manager ${PHASE4_CERT_MANAGER_CHART_VERSION}"
phase4_ensure_helm_repo jetstack "${PHASE4_CERT_MANAGER_HELM_REPO_URL}"
helm repo update jetstack >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version "${PHASE4_CERT_MANAGER_CHART_VERSION}" \
    --values "$(phase4_repo_path "deploy/helm-values/cert-manager.values.yaml")" \
    --wait

phase4_info "controller namespace snapshot"
kubectl get pods -n external-secrets
kubectl get pods -n cert-manager
