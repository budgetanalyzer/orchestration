#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/lib/common.sh"

label_baseline_namespace() {
    local namespace="$1"

    phase4_create_or_update_namespace "${namespace}"
    phase4_label_namespace "${namespace}" \
        pod-security.kubernetes.io/enforce=baseline \
        "pod-security.kubernetes.io/enforce-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/warn=baseline \
        "pod-security.kubernetes.io/warn-version=${PHASE4_POD_SECURITY_VERSION}" \
        pod-security.kubernetes.io/audit=baseline \
        "pod-security.kubernetes.io/audit-version=${PHASE4_POD_SECURITY_VERSION}"
}

phase4_load_instance_env
phase4_require_commands helm kubectl
phase4_require_cluster_access

phase4_info "ensuring kyverno namespace exists with baseline Pod Security labels"
label_baseline_namespace kyverno

phase4_info "installing Kyverno ${PHASE7_KYVERNO_CHART_VERSION}"
phase4_ensure_helm_repo kyverno "${PHASE7_KYVERNO_HELM_REPO_URL}"
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno \
    --namespace kyverno \
    --create-namespace \
    --version "${PHASE7_KYVERNO_CHART_VERSION}" \
    --values "$(phase4_repo_path "deploy/helm-values/kyverno.values.yaml")" \
    --wait

phase4_info "verifying Kyverno controller deployments"
kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=300s >/dev/null
kubectl wait --for=condition=Available deployment/kyverno-background-controller -n kyverno --timeout=300s >/dev/null
kubectl wait --for=condition=Available deployment/kyverno-cleanup-controller -n kyverno --timeout=300s >/dev/null
kubectl wait --for=condition=Available deployment/kyverno-reports-controller -n kyverno --timeout=300s >/dev/null

phase4_info "Kyverno namespace labels"
kubectl get namespace kyverno --show-labels

phase4_info "Kyverno controller snapshot"
kubectl get deployments,pods -n kyverno
