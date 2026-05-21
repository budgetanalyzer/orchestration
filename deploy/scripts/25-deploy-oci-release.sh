#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
STATIC_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
PRODUCTION_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
POD_VERSION_LABELS_SCRIPT="$(phase4_repo_path "scripts/ops/show-pod-version-labels.sh")"
OBSERVABILITY_ACCESS_VERIFIER="$(phase4_repo_path "scripts/smoketest/verify-observability-port-forward-access.sh")"
MONITORING_RUNTIME_VERIFIER="$(phase4_repo_path "scripts/smoketest/verify-monitoring-runtime.sh")"
SNAPSHOT_ROOT="$(phase4_repo_path "tmp/oci-release-deploy")"
PHASE6_RENDER_ROOT="$(phase4_repo_path "tmp/phase-6")"
PHASE11_RENDER_ROOT="$(phase4_repo_path "tmp/phase-11")"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly STATIC_VERIFIER
readonly PRODUCTION_VERIFIER
readonly POD_VERSION_LABELS_SCRIPT
readonly OBSERVABILITY_ACCESS_VERIFIER
readonly MONITORING_RUNTIME_VERIFIER
readonly SNAPSHOT_ROOT
readonly PHASE6_RENDER_ROOT
readonly PHASE11_RENDER_ROOT

SERVICE_DEPLOYMENTS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "ext-authz"
    "nginx-gateway"
)
readonly SERVICE_DEPLOYMENTS

SERVICE_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly SERVICE_ORDER

MODE=""
DEPLOYMENT_MANIFEST=""
DEPLOYMENT_ID=""
DRY_RUN=false
SKIP_PLATFORM=false
SKIP_INFRASTRUCTURE=false
SKIP_SECRETS=false
SKIP_OBSERVABILITY=false
REAPPLY_PUBLIC_TLS=false
ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE=false
EXPLICIT_KUBECONFIG=false
SNAPSHOT_DIR=""

FLAG_PLATFORM_CHANGED=false
FLAG_INFRASTRUCTURE_CHANGED=false
FLAG_SECRETS_CHANGED=false
FLAG_OBSERVABILITY_CHANGED=false
FLAG_PUBLIC_TLS_REAPPLY_REQUIRED=false

RUN_PLATFORM=false
RUN_INFRASTRUCTURE=false
RUN_SECRETS=false
RUN_APP=false
RUN_ADMISSION=false
RUN_OBSERVABILITY=false
RUN_PUBLIC_TLS=false

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/25-deploy-oci-release.sh --mode MODE --deployment-manifest PATH [options]

Operator-facing OCI deployment wrapper.

Required:
  --mode app-only|manifest|platform-only|infrastructure-only|verify-only
  --deployment-manifest PATH

Options:
  --kubeconfig PATH
  --dry-run
  --skip-platform
  --skip-infrastructure
  --skip-secrets
  --skip-observability
  --reapply-public-tls
  --acknowledge-public-tls-downgrade
  -h, --help

The script validates a schema v2 deployment manifest against the checked-in
production image inventory, captures pre/post snapshots, composes reviewed
deployment phases, waits for touched rollouts, and verifies live pod metadata
against the same manifest. It does not run host-only certificate generation.
EOF
}

die() {
    phase4_die "$1"
}

info() {
    phase4_info "$*"
}

warn() {
    phase4_warn "$*"
}

manifest_value() {
    local manifest="$1"
    local key="$2"

    awk -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${manifest}"
}

manifest_map_value() {
    local manifest="$1"
    local section="$2"
    local key="$3"

    awk -v section="${section}" -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 == section ":" {
            in_section = 1
            next
        }
        in_section && $0 ~ /^[^[:space:]][^:]*:/ {
            in_section = 0
        }
        in_section && index($0, "  " key ":") == 1 {
            value = $0
            sub("^  " key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${manifest}"
}

manifest_nested_value() {
    local manifest="$1"
    local section="$2"
    local item="$3"
    local key="$4"

    awk -v section="${section}" -v item="${item}" -v key="${key}" '
        function clean(value) {
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            if (value ~ /^".*"$/) {
                sub(/^"/, "", value)
                sub(/"$/, "", value)
            }
            return value
        }
        $0 == section ":" {
            in_section = 1
            next
        }
        in_section && $0 ~ /^[^[:space:]][^:]*:/ {
            in_section = 0
            in_item = 0
        }
        in_section && $0 == "  " item ":" {
            in_item = 1
            next
        }
        in_section && in_item && $0 ~ /^  [^[:space:]][^:]*:/ {
            in_item = 0
        }
        in_section && in_item && index($0, "    " key ":") == 1 {
            value = $0
            sub("^    " key ":[[:space:]]*", "", value)
            print clean(value)
            exit
        }
    ' "${manifest}"
}

inventory_value() {
    local key="$1"

    awk -v key="${key}" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' "${PRODUCTION_IMAGE_INVENTORY}"
}

valid_bool() {
    [[ "$1" == "true" || "$1" == "false" ]]
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                MODE="${2:-}"
                [[ -n "${MODE}" ]] || die "missing value for --mode"
                shift
                ;;
            --deployment-manifest)
                DEPLOYMENT_MANIFEST="${2:-}"
                [[ -n "${DEPLOYMENT_MANIFEST}" ]] || die "missing value for --deployment-manifest"
                shift
                ;;
            --kubeconfig)
                export KUBECONFIG="${2:-}"
                [[ -n "${KUBECONFIG}" ]] || die "missing value for --kubeconfig"
                EXPLICIT_KUBECONFIG=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --skip-platform)
                SKIP_PLATFORM=true
                ;;
            --skip-infrastructure)
                SKIP_INFRASTRUCTURE=true
                ;;
            --skip-secrets)
                SKIP_SECRETS=true
                ;;
            --skip-observability)
                SKIP_OBSERVABILITY=true
                ;;
            --reapply-public-tls)
                REAPPLY_PUBLIC_TLS=true
                ;;
            --acknowledge-public-tls-downgrade)
                ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
        shift
    done
}

resolve_deployment_manifest_path() {
    [[ -n "${DEPLOYMENT_MANIFEST}" ]] || die "missing --deployment-manifest"
    if [[ "${DEPLOYMENT_MANIFEST}" != /* && ! -f "${DEPLOYMENT_MANIFEST}" ]]; then
        DEPLOYMENT_MANIFEST="$(phase4_repo_path "${DEPLOYMENT_MANIFEST}")"
    fi
    [[ -f "${DEPLOYMENT_MANIFEST}" ]] || die "deployment manifest not found: ${DEPLOYMENT_MANIFEST}"
}

load_deployment_manifest() {
    local schema_version flag value

    resolve_deployment_manifest_path
    schema_version="$(manifest_value "${DEPLOYMENT_MANIFEST}" "schema_version")"
    [[ "${schema_version}" == "2" ]] || die "deployment manifest must use schema_version: 2"

    DEPLOYMENT_ID="$(manifest_map_value "${DEPLOYMENT_MANIFEST}" "deployment" "id")"
    [[ -n "${DEPLOYMENT_ID}" ]] || die "deployment manifest is missing deployment.id"

    for flag in platform_changed infrastructure_changed secrets_changed observability_changed public_tls_reapply_required; do
        value="$(manifest_map_value "${DEPLOYMENT_MANIFEST}" "phase_flags" "${flag}")"
        [[ -n "${value}" ]] || die "deployment manifest is missing phase_flags.${flag}"
        valid_bool "${value}" || die "phase_flags.${flag} must be true or false"
        case "${flag}" in
            platform_changed)
                FLAG_PLATFORM_CHANGED="${value}"
                ;;
            infrastructure_changed)
                FLAG_INFRASTRUCTURE_CHANGED="${value}"
                ;;
            secrets_changed)
                FLAG_SECRETS_CHANGED="${value}"
                ;;
            observability_changed)
                FLAG_OBSERVABILITY_CHANGED="${value}"
                ;;
            public_tls_reapply_required)
                FLAG_PUBLIC_TLS_REAPPLY_REQUIRED="${value}"
                ;;
        esac
    done
}

validate_manifest_matches_inventory() {
    local service manifest_ref inventory_ref manifest_version inventory_version
    local manifest_deployment_id inventory_deployment_id

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || die "missing production image inventory: ${PRODUCTION_IMAGE_INVENTORY}"
    [[ "$(inventory_value "schema-version")" == "2" ]] || die "production image inventory must use schema-version: \"2\""

    manifest_deployment_id="$(manifest_map_value "${DEPLOYMENT_MANIFEST}" "deployment" "id")"
    inventory_deployment_id="$(inventory_value "deployment-id")"
    [[ "${manifest_deployment_id}" == "${inventory_deployment_id}" ]] || \
        die "deployment manifest id ${manifest_deployment_id} does not match checked-in inventory deployment-id ${inventory_deployment_id}"

    for service in "${SERVICE_ORDER[@]}"; do
        manifest_ref="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${service}" "image")"
        inventory_ref="$(inventory_value "${service}")"
        [[ -n "${manifest_ref}" ]] || die "deployment manifest is missing artifacts.${service}.image"
        [[ "${manifest_ref}" == "${inventory_ref}" ]] || \
            die "deployment manifest image for ${service} does not match the checked-in production image inventory"

        manifest_version="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${service}" "artifact_version")"
        inventory_version="$(inventory_value "${service}.artifact-version")"
        [[ "${manifest_version}" == "${inventory_version}" ]] || \
            die "deployment manifest artifact version for ${service} does not match the checked-in production image inventory"
    done
}

configure_kubeconfig() {
    if [[ -z "${KUBECONFIG:-}" && -f "${PHASE4_DEFAULT_KUBECONFIG}" ]]; then
        export KUBECONFIG="${PHASE4_DEFAULT_KUBECONFIG}"
    fi

    if [[ -z "${KUBECONFIG:-}" ]]; then
        die "missing KUBECONFIG; export KUBECONFIG=${PHASE4_DEFAULT_KUBECONFIG} on the OCI host or pass --kubeconfig"
    fi

    if [[ "${EXPLICIT_KUBECONFIG}" == "false" && "${KUBECONFIG}" != "${PHASE4_DEFAULT_KUBECONFIG}" ]]; then
        warn "using KUBECONFIG from the environment: ${KUBECONFIG}"
    fi
}

configure_mode() {
    case "${MODE}" in
        app-only)
            RUN_APP=true
            ;;
        manifest)
            RUN_PLATFORM="${FLAG_PLATFORM_CHANGED}"
            RUN_INFRASTRUCTURE="${FLAG_INFRASTRUCTURE_CHANGED}"
            RUN_SECRETS="${FLAG_SECRETS_CHANGED}"
            RUN_APP=true
            RUN_ADMISSION=true
            RUN_OBSERVABILITY="${FLAG_OBSERVABILITY_CHANGED}"
            RUN_PUBLIC_TLS="${FLAG_PUBLIC_TLS_REAPPLY_REQUIRED}"
            ;;
        platform-only)
            RUN_PLATFORM=true
            RUN_ADMISSION=true
            RUN_OBSERVABILITY=true
            ;;
        infrastructure-only)
            RUN_INFRASTRUCTURE=true
            RUN_SECRETS=true
            ;;
        verify-only)
            ;;
        "")
            die "missing --mode"
            ;;
        *)
            die "unsupported --mode: ${MODE}"
            ;;
    esac

    [[ "${SKIP_PLATFORM}" == "true" ]] && RUN_PLATFORM=false
    [[ "${SKIP_INFRASTRUCTURE}" == "true" ]] && RUN_INFRASTRUCTURE=false
    [[ "${SKIP_SECRETS}" == "true" ]] && RUN_SECRETS=false
    [[ "${SKIP_OBSERVABILITY}" == "true" ]] && RUN_OBSERVABILITY=false
    [[ "${REAPPLY_PUBLIC_TLS}" == "true" ]] && RUN_PUBLIC_TLS=true
}

selected_apply_count() {
    local count=0 selected

    for selected in \
        "${RUN_PLATFORM}" \
        "${RUN_INFRASTRUCTURE}" \
        "${RUN_SECRETS}" \
        "${RUN_APP}" \
        "${RUN_ADMISSION}" \
        "${RUN_OBSERVABILITY}" \
        "${RUN_PUBLIC_TLS}"; do
        if [[ "${selected}" == "true" ]]; then
            count=$((count + 1))
        fi
    done

    printf '%s\n' "${count}"
}

run_cmd() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        printf '[dry-run] '
        printf '%q ' "$@"
        printf '\n'
        return
    fi

    "$@"
}

run_bash() {
    local command="$1"

    if [[ "${DRY_RUN}" == "true" ]]; then
        printf '[dry-run] %s\n' "${command}"
        return
    fi

    bash -c "${command}"
}

require_executable() {
    local path="$1"

    [[ -x "${path}" ]] || die "missing executable: ${path}"
}

capture_snapshot() {
    local label="$1"
    local output_dir="${SNAPSHOT_DIR}/${label}"

    mkdir -p "${output_dir}"
    info "capturing ${label} cluster snapshot in ${output_dir}"

    kubectl get nodes -o wide > "${output_dir}/nodes.txt"
    kubectl get pods -A -o wide > "${output_dir}/pods.txt"
    kubectl get deploy,statefulset -A > "${output_dir}/workloads.txt"
    kubectl get gateway,httproute -A > "${output_dir}/gateway-routes.txt" 2>&1 || true
    kubectl get peerauthentication,authorizationpolicy -A > "${output_dir}/istio-policies.txt" 2>&1 || true
    kubectl get networkpolicy -A > "${output_dir}/network-policies.txt" 2>&1 || true
    kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr ' ' '\n' | sort -u > "${output_dir}/container-images.txt"
    kubectl get pods -A -o jsonpath='{.items[*].spec.initContainers[*].image}' | tr ' ' '\n' | sort -u > "${output_dir}/init-container-images.txt"
    helm list -A > "${output_dir}/helm-releases.txt"
}

run_static_preflight() {
    require_executable "${STATIC_VERIFIER}"
    info "running OCI static verifier"
    "${STATIC_VERIFIER}"
}

run_live_production_verifier() {
    require_executable "${PRODUCTION_VERIFIER}"
    info "running production image/render verifier"
    "${PRODUCTION_VERIFIER}"
}

run_pod_metadata_verifier() {
    require_executable "${POD_VERSION_LABELS_SCRIPT}"
    info "verifying live runtime deployment metadata"
    run_cmd "${POD_VERSION_LABELS_SCRIPT}" --deployment-manifest "${DEPLOYMENT_MANIFEST}" --tracked-only --strict
}

run_platform_phase() {
    local istio_args=()

    if [[ "${ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE}" == "true" ]]; then
        istio_args+=("--acknowledge-public-tls-downgrade")
    fi

    info "running platform phase"
    run_cmd "${SCRIPT_DIR}/01-install-k3s.sh"
    run_cmd "${SCRIPT_DIR}/02-bootstrap-cluster.sh"
    run_cmd "${SCRIPT_DIR}/03-render-phase-4-istio-manifests.sh"
    run_cmd "${SCRIPT_DIR}/04-install-istio.sh" "${istio_args[@]}"
    run_cmd "${SCRIPT_DIR}/05-install-platform-controllers.sh"
    run_cmd "${SCRIPT_DIR}/07-apply-network-policies.sh"
    run_cmd "${SCRIPT_DIR}/08-verify-network-policy-enforcement.sh"
}

run_infrastructure_phase() {
    info "running infrastructure phase"
    run_cmd "${SCRIPT_DIR}/18-apply-production-infrastructure.sh"
}

run_secrets_phase() {
    info "running secret-sync phase"
    run_cmd "${SCRIPT_DIR}/09-render-phase-5-secrets.sh"
    run_cmd "${SCRIPT_DIR}/10-apply-phase-5-secrets.sh"
}

run_application_phase() {
    local deployment

    info "running application phase"
    run_cmd "${SCRIPT_DIR}/13-render-phase-6-production-manifests.sh"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/gateway-routes.yaml"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/istio-ingress-policies.yaml"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/istio-egress.yaml"

    run_live_production_verifier
    run_bash "kubectl kustomize '${PRODUCTION_APPS_DIR}' --load-restrictor=LoadRestrictionsNone | kubectl apply --server-side -f -"

    for deployment in "${SERVICE_DEPLOYMENTS[@]}"; do
        run_cmd kubectl rollout status "deployment/${deployment}" --timeout=300s
    done

    run_pod_metadata_verifier
}

run_admission_phase() {
    info "running admission phase"
    run_cmd "${SCRIPT_DIR}/14-install-phase-7-kyverno.sh"
    run_cmd "${SCRIPT_DIR}/15-apply-phase-7-policies.sh"
}

run_observability_phase() {
    info "running observability phase"
    run_cmd "${SCRIPT_DIR}/22-apply-production-monitoring.sh" --verify-runtime
}

run_public_tls_phase() {
    info "running public TLS reapply phase"
    run_cmd "${SCRIPT_DIR}/16-render-phase-11-public-tls-manifests.sh"
    run_cmd kubectl apply -f "${PHASE11_RENDER_ROOT}/cluster-issuer.yaml"
    run_cmd kubectl apply -f "${PHASE11_RENDER_ROOT}/public-certificate.yaml"
    run_cmd kubectl apply -f "${PHASE11_RENDER_ROOT}/reference-grant.yaml"
    run_cmd kubectl apply -f "${PHASE11_RENDER_ROOT}/ingress-gateway-config.yaml"
    run_cmd kubectl apply -f "${PHASE11_RENDER_ROOT}/istio-gateway.yaml"
    run_cmd kubectl wait --for=condition=Programmed gateway/istio-ingress-gateway -n istio-ingress --timeout=180s
    run_cmd kubectl rollout status deployment/istio-ingress-gateway-istio -n istio-ingress --timeout=180s
    run_cmd kubectl wait --for=condition=Ready certificate/budgetanalyzer-org-public -n default --timeout=300s
}

run_verify_only() {
    info "running verify-only checks"
    run_live_production_verifier
    run_cmd "${SCRIPT_DIR}/08-verify-network-policy-enforcement.sh"
    require_executable "${OBSERVABILITY_ACCESS_VERIFIER}"
    require_executable "${MONITORING_RUNTIME_VERIFIER}"
    run_pod_metadata_verifier
    run_cmd "${OBSERVABILITY_ACCESS_VERIFIER}"
    run_cmd "${MONITORING_RUNTIME_VERIFIER}" --wait-timeout 180
}

print_plan_summary() {
    info "deployment selection"
    printf '  mode: %s\n' "${MODE}"
    printf '  deployment-id: %s\n' "${DEPLOYMENT_ID}"
    printf '  deployment-manifest: %s\n' "${DEPLOYMENT_MANIFEST}"
    printf '  dry-run: %s\n' "${DRY_RUN}"
    printf '  platform: %s\n' "${RUN_PLATFORM}"
    printf '  infrastructure: %s\n' "${RUN_INFRASTRUCTURE}"
    printf '  secrets: %s\n' "${RUN_SECRETS}"
    printf '  app: %s\n' "${RUN_APP}"
    printf '  admission: %s\n' "${RUN_ADMISSION}"
    printf '  observability: %s\n' "${RUN_OBSERVABILITY}"
    printf '  public-tls: %s\n' "${RUN_PUBLIC_TLS}"
}

print_completion_checklist() {
    info "OCI deployment wrapper complete"
    printf '\nCompletion checklist:\n'
    printf '  - Review snapshots under %s\n' "${SNAPSHOT_DIR}"
    printf '  - Confirm live images match kubernetes/production/apps/image-inventory.yaml\n'
    printf '  - Confirm live deployment metadata: ./scripts/ops/show-pod-version-labels.sh --deployment-manifest %s --tracked-only --strict\n' "${DEPLOYMENT_MANIFEST}"
    printf '  - Confirm observability remains internal-only; no Grafana, Prometheus, Jaeger, or Kiali public routes\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/api-docs\n'
    printf '  - From a workstation, verify: curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json\n'
}

main() {
    parse_args "$@"
    load_deployment_manifest
    validate_manifest_matches_inventory
    configure_mode
    configure_kubeconfig
    phase4_load_instance_env
    phase4_require_commands kubectl helm
    phase4_require_cluster_access

    SNAPSHOT_DIR="${SNAPSHOT_ROOT}/$(date -u +%Y%m%dT%H%M%SZ)-${MODE}-${DEPLOYMENT_ID}"
    mkdir -p "${SNAPSHOT_DIR}"

    print_plan_summary
    run_static_preflight
    capture_snapshot preflight

    if [[ "${MODE}" == "verify-only" ]]; then
        run_verify_only
    else
        if [[ "$(selected_apply_count)" == "0" ]]; then
            warn "no apply phases selected after mode and skip flags"
        fi

        [[ "${RUN_PLATFORM}" == "true" ]] && run_platform_phase
        [[ "${RUN_INFRASTRUCTURE}" == "true" ]] && run_infrastructure_phase
        [[ "${RUN_SECRETS}" == "true" ]] && run_secrets_phase
        [[ "${RUN_APP}" == "true" ]] && run_application_phase
        [[ "${RUN_ADMISSION}" == "true" ]] && run_admission_phase
        [[ "${RUN_OBSERVABILITY}" == "true" ]] && run_observability_phase
        [[ "${RUN_PUBLIC_TLS}" == "true" ]] && run_public_tls_phase
    fi

    capture_snapshot post-deploy
    print_completion_checklist
}

main "$@"
