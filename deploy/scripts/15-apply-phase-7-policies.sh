#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

POLICIES=(
    "kubernetes/kyverno/policies/00-smoke-disallow-privileged.yaml"
    "kubernetes/kyverno/policies/10-require-namespace-pod-security-labels.yaml"
    "kubernetes/kyverno/policies/20-require-workload-automount-disabled.yaml"
    "kubernetes/kyverno/policies/30-require-workload-security-context.yaml"
    "kubernetes/kyverno/policies/40-disallow-obvious-default-credentials.yaml"
    "kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml"
)
readonly POLICIES

policy_names=(
    smoke-disallow-privileged
    phase7-require-namespace-pod-security-labels
    phase7-require-workload-automount-disabled
    phase7-require-workload-security-context
    phase7-disallow-obvious-default-credentials
    phase7-require-third-party-image-digests
)
readonly policy_names

verify_live_production_image_policy() {
    local live_policy

    live_policy="$(kubectl get clusterpolicy phase7-require-third-party-image-digests -o yaml)"

    if ! printf '%s\n' "${live_policy}" | grep -Fq 'name: require-digest-pinned-images'; then
        phase4_die "live phase7-require-third-party-image-digests policy is missing the production rule name"
    fi

    if printf '%s\n' "${live_policy}" | grep -Eq \
        'require-digest-or-approved-local-image|require-image-pull-policy-never-for-approved-local-latest-image|require-image-pull-policy-for-approved-local-tilt-image|budget-analyzer-web-prod-smoke'; then
        phase4_die "live phase7-require-third-party-image-digests policy still contains local Tilt/latest exception rules"
    fi
}

phase4_load_instance_env
phase4_require_commands kubectl
phase4_require_cluster_access

phase4_info "verifying the checked-in production image baseline before live policy apply"
"${REPO_DIR}/scripts/guardrails/verify-production-image-overlay.sh"

phase4_info "ensuring Kyverno admission controller is available"
kubectl wait --for=condition=Available deployment/kyverno-admission-controller -n kyverno --timeout=300s >/dev/null

phase4_info "applying Phase 7 production policy set"
for policy_path in "${POLICIES[@]}"; do
    kubectl apply -f "$(phase4_repo_path "${policy_path}")" >/dev/null
done

verify_live_production_image_policy

phase4_info "Phase 7 ClusterPolicy snapshot"
kubectl get clusterpolicy "${policy_names[@]}"
