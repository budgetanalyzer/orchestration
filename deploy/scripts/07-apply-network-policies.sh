#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

phase4_load_instance_env
phase4_require_commands kubectl
phase4_require_cluster_access

phase4_info "applying checked-in NetworkPolicy manifests"
kubectl apply -f "$(phase4_repo_path "kubernetes/network-policies")" >/dev/null

phase4_info "network policy snapshot"
kubectl get networkpolicy -A
phase4_warn "runtime NetworkPolicy enforcement still needs proof on the k3s CNI; run deploy/scripts/08-verify-network-policy-enforcement.sh before Phase 5"
