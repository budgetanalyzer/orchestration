#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_INFRASTRUCTURE_RENDER_ROOT="${PHASE4_REPO_ROOT}/tmp/production-infrastructure"
readonly PRODUCTION_INFRASTRUCTURE_RENDER_ROOT
INFRASTRUCTURE_NAMESPACE="infrastructure"
readonly INFRASTRUCTURE_NAMESPACE
APP_NAMESPACE="default"
readonly APP_NAMESPACE
REDIS_READY_TIMEOUT="300s"
readonly REDIS_READY_TIMEOUT
OLD_REDIS_DEPLOYMENT="redis"
readonly OLD_REDIS_DEPLOYMENT
OLD_REDIS_PVC="redis-data"
readonly OLD_REDIS_PVC
NEW_REDIS_POD="redis-0"
readonly NEW_REDIS_POD
REDIS_CLIENT_DEPLOYMENTS=(session-gateway ext-authz currency-service)
readonly REDIS_CLIENT_DEPLOYMENTS

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/19-migrate-production-redis-statefulset.sh --confirm-destroy-redis [--restart-redis-clients] [--output-dir DIR]

Destructively migrates an existing production Redis Deployment plus standalone
PersistentVolumeClaim into the shared production StatefulSet baseline.

Required flag:
  --confirm-destroy-redis     Acknowledge that Redis session/cache data may be deleted.

Options:
  --restart-redis-clients     Roll out session-gateway, ext-authz, and currency-service
                              after Redis is healthy to force clean connections.
  --output-dir DIR            Render review output directory. Defaults to
                              tmp/production-infrastructure/.

This script never deletes PostgreSQL or RabbitMQ resources, never generates
certificates, and never writes secret values.
EOF
}

delete_old_redis_deployment_if_present() {
    if kubectl get deployment "${OLD_REDIS_DEPLOYMENT}" -n "${INFRASTRUCTURE_NAMESPACE}" >/dev/null 2>&1; then
        phase4_warn "scaling old Deployment/${OLD_REDIS_DEPLOYMENT} to zero before deletion"
        kubectl scale "deployment/${OLD_REDIS_DEPLOYMENT}" \
            -n "${INFRASTRUCTURE_NAMESPACE}" \
            --replicas=0
        kubectl rollout status "deployment/${OLD_REDIS_DEPLOYMENT}" \
            -n "${INFRASTRUCTURE_NAMESPACE}" \
            --timeout=120s

        phase4_warn "deleting old Deployment/${OLD_REDIS_DEPLOYMENT}"
        kubectl delete deployment "${OLD_REDIS_DEPLOYMENT}" \
            -n "${INFRASTRUCTURE_NAMESPACE}" \
            --wait=true
    else
        phase4_info "old Deployment/${OLD_REDIS_DEPLOYMENT} is already absent"
    fi
}

delete_old_redis_pvc_if_present() {
    if kubectl get pvc "${OLD_REDIS_PVC}" -n "${INFRASTRUCTURE_NAMESPACE}" >/dev/null 2>&1; then
        phase4_warn "deleting old standalone PersistentVolumeClaim/${OLD_REDIS_PVC}"
        kubectl delete pvc "${OLD_REDIS_PVC}" \
            -n "${INFRASTRUCTURE_NAMESPACE}" \
            --wait=true
    else
        phase4_info "old standalone PersistentVolumeClaim/${OLD_REDIS_PVC} is already absent"
    fi
}

verify_redis_tls_ping() {
    local output

    phase4_info "waiting for Pod/${NEW_REDIS_POD} to become Ready"
    kubectl wait \
        --for=condition=Ready \
        "pod/${NEW_REDIS_POD}" \
        -n "${INFRASTRUCTURE_NAMESPACE}" \
        --timeout="${REDIS_READY_TIMEOUT}"

    phase4_info "verifying Redis TLS PING through Pod/${NEW_REDIS_POD}"
    output="$(kubectl exec -n "${INFRASTRUCTURE_NAMESPACE}" "${NEW_REDIS_POD}" -- \
        redis-cli --tls --cacert /tls-ca/ca.crt ping | tr -d '\r')"

    [[ "${output}" == "PONG" ]] || phase4_die "Redis TLS PING failed; expected PONG, got: ${output}"
}

restart_redis_clients_if_requested() {
    local restart_clients="$1"
    local deployment_name

    if [[ "${restart_clients}" != true ]]; then
        phase4_info "Redis clients were not restarted; rerun with --restart-redis-clients if reconnect behavior needs a forced reset"
        return
    fi

    for deployment_name in "${REDIS_CLIENT_DEPLOYMENTS[@]}"; do
        if kubectl get deployment "${deployment_name}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
            phase4_info "restarting Deployment/${deployment_name}"
            kubectl rollout restart "deployment/${deployment_name}" -n "${APP_NAMESPACE}"
            kubectl rollout status "deployment/${deployment_name}" -n "${APP_NAMESPACE}" --timeout=300s
        else
            phase4_warn "Deployment/${deployment_name} is absent in ${APP_NAMESPACE}; skipping restart"
        fi
    done
}

main() {
    local confirm_destroy_redis=false
    local restart_clients=false
    local output_dir="${PRODUCTION_INFRASTRUCTURE_RENDER_ROOT}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --confirm-destroy-redis)
                confirm_destroy_redis=true
                ;;
            --restart-redis-clients)
                restart_clients=true
                ;;
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
    [[ "${confirm_destroy_redis}" == true ]] || {
        usage >&2
        phase4_die "refusing destructive Redis migration without --confirm-destroy-redis"
    }

    phase4_load_instance_env
    phase4_require_commands kubectl
    phase4_require_cluster_access

    phase4_warn "this migration may delete Redis session/cache data; PostgreSQL and RabbitMQ resources are not deleted"

    delete_old_redis_deployment_if_present
    delete_old_redis_pvc_if_present

    phase4_info "applying the broad production infrastructure target"
    "${SCRIPT_DIR}/18-apply-production-infrastructure.sh" --output-dir "${output_dir}"

    verify_redis_tls_ping
    restart_redis_clients_if_requested "${restart_clients}"

    phase4_info "Redis StatefulSet migration completed"
    kubectl get \
        "statefulset/redis" \
        "pod/${NEW_REDIS_POD}" \
        "pvc/redis-data-redis-0" \
        -n "${INFRASTRUCTURE_NAMESPACE}"
}

main "$@"
