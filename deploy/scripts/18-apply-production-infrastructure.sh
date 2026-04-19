#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_INFRASTRUCTURE_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/production-infrastructure"
readonly PRODUCTION_INFRASTRUCTURE_RENDER_ROOT
PRODUCTION_INFRASTRUCTURE_MANIFEST="infrastructure.yaml"
readonly PRODUCTION_INFRASTRUCTURE_MANIFEST
INFRASTRUCTURE_NAMESPACE="infrastructure"
readonly INFRASTRUCTURE_NAMESPACE
STATEFULSET_WAIT_TIMEOUT="300s"
readonly STATEFULSET_WAIT_TIMEOUT

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/18-apply-production-infrastructure.sh [--output-dir DIR]

Refreshes the reviewed production infrastructure render output, applies it to
the current Kubernetes context, and waits for PostgreSQL, RabbitMQ, and Redis
StatefulSets when they are present.
EOF
}

wait_for_statefulset_if_present() {
    local name="$1"

    if kubectl get statefulset "${name}" -n "${INFRASTRUCTURE_NAMESPACE}" >/dev/null 2>&1; then
        phase4_info "waiting for StatefulSet/${name}"
        kubectl rollout status "statefulset/${name}" \
            -n "${INFRASTRUCTURE_NAMESPACE}" \
            --timeout="${STATEFULSET_WAIT_TIMEOUT}"
    else
        phase4_warn "StatefulSet/${name} is not present in ${INFRASTRUCTURE_NAMESPACE}; skipping wait"
    fi
}

main() {
    local output_dir="${PRODUCTION_INFRASTRUCTURE_RENDER_ROOT}"
    local manifest_path

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                output_dir="${2:-}"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                phase4_die "unknown option: $1"
                ;;
        esac
        shift
    done

    [[ -n "${output_dir}" ]] || phase4_die "--output-dir requires a non-empty value"

    phase4_load_instance_env
    phase4_require_commands kubectl
    phase4_require_cluster_access

    phase4_info "refreshing the rendered production infrastructure manifest"
    "${SCRIPT_DIR}/17-render-production-infrastructure.sh" --output-dir "${output_dir}" >/dev/null

    manifest_path="${output_dir}/${PRODUCTION_INFRASTRUCTURE_MANIFEST}"
    [[ -s "${manifest_path}" ]] || phase4_die "missing rendered production infrastructure manifest: ${manifest_path}"

    phase4_info "applying ${manifest_path}"
    kubectl apply -f "${manifest_path}"

    wait_for_statefulset_if_present postgresql
    wait_for_statefulset_if_present rabbitmq
    wait_for_statefulset_if_present redis

    phase4_info "production infrastructure StatefulSet snapshot"
    kubectl get statefulset -n "${INFRASTRUCTURE_NAMESPACE}"
}

main "$@"
