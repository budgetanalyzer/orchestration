#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
LOCKSTEP_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
PRODUCTION_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
POD_VERSION_LABELS_SCRIPT="$(phase4_repo_path "scripts/ops/show-pod-version-labels.sh")"
OBSERVABILITY_ACCESS_VERIFIER="$(phase4_repo_path "scripts/smoketest/verify-observability-port-forward-access.sh")"
MONITORING_RUNTIME_VERIFIER="$(phase4_repo_path "scripts/smoketest/verify-monitoring-runtime.sh")"
SNAPSHOT_ROOT="$(phase4_repo_path "tmp/oci-release-deploy")"
PHASE6_RENDER_ROOT="$(phase4_repo_path "tmp/phase-6")"
PHASE11_RENDER_ROOT="$(phase4_repo_path "tmp/phase-11")"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly LOCKSTEP_VERIFIER
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
RELEASE_VERSION=""
RELEASE_MANIFEST=""
DRY_RUN=false
SKIP_PLATFORM=false
SKIP_INFRASTRUCTURE=false
SKIP_SECRETS=false
SKIP_OBSERVABILITY=false
REAPPLY_PUBLIC_TLS=false
ACKNOWLEDGE_PUBLIC_TLS_DOWNGRADE=false
EXPLICIT_KUBECONFIG=false
SNAPSHOT_DIR=""

FLAG_PLATFORM_CHANGED=""
FLAG_INFRASTRUCTURE_CHANGED=""
FLAG_SECRETS_CHANGED=""
FLAG_OBSERVABILITY_CHANGED=""
FLAG_PUBLIC_TLS_REAPPLY_REQUIRED=""

RUN_PLATFORM=false
RUN_INFRASTRUCTURE=false
RUN_SECRETS=false
RUN_APP=false
RUN_ADMISSION=false
RUN_OBSERVABILITY=false
RUN_PUBLIC_TLS=false

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/25-deploy-oci-release.sh --mode MODE [options]

Operator-facing OCI release deployment wrapper.

Required:
  --mode app-only|lockstep|platform-only|infrastructure-only|verify-only

Options:
  --release-version VERSION
  --release-manifest PATH
  --kubeconfig PATH
  --dry-run
  --skip-platform
  --skip-infrastructure
  --skip-secrets
  --skip-observability
  --reapply-public-tls
  --acknowledge-public-tls-downgrade
  -h, --help

The script composes the reviewed deploy/scripts entry points, captures pre and
post snapshots under tmp/oci-release-deploy/, waits for touched rollouts, and
verifies live runtime release labels after application rollout or verify-only
checks. It prints the final verification checklist, including the browser
release metadata endpoint. It does not run the host-only
deploy/scripts/11-generate-phase-5-infra-tls.sh certificate generation path.
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

manifest_release_value() {
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
        $0 == "release:" {
            in_release = 1
            next
        }
        in_release && $0 ~ /^[^[:space:]][^:]*:/ {
            in_release = 0
        }
        in_release && index($0, "  " key ":") == 1 {
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

manifest_flag_value() {
    local manifest="$1"
    local flag="$2"

    awk -v flag="${flag}" '
        $0 == "phase_flags:" {
            in_flags = 1
            next
        }
        in_flags && $0 ~ /^[^[:space:]][^:]*:/ {
            in_flags = 0
        }
        in_flags && index($0, "  " flag ":") == 1 {
            value = $0
            sub("^  " flag ":[[:space:]]*", "", value)
            sub(/^[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            gsub(/^"/, "", value)
            gsub(/"$/, "", value)
            print value
            exit
        }
    ' "${manifest}"
}

normalize_release_version() {
    local version="$1"

    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
}

valid_bool() {
    local value="$1"

    [[ "${value}" == "true" || "${value}" == "false" ]]
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode)
                MODE="${2:-}"
                [[ -n "${MODE}" ]] || die "missing value for --mode"
                shift
                ;;
            --release-version)
                RELEASE_VERSION="${2:-}"
                [[ -n "${RELEASE_VERSION}" ]] || die "missing value for --release-version"
                shift
                ;;
            --release-manifest)
                RELEASE_MANIFEST="${2:-}"
                [[ -n "${RELEASE_MANIFEST}" ]] || die "missing value for --release-manifest"
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

resolve_release_manifest_path() {
    if [[ -z "${RELEASE_MANIFEST}" ]]; then
        return
    fi

    if [[ "${RELEASE_MANIFEST}" != /* && ! -f "${RELEASE_MANIFEST}" ]]; then
        RELEASE_MANIFEST="$(phase4_repo_path "${RELEASE_MANIFEST}")"
    fi

    [[ -f "${RELEASE_MANIFEST}" ]] || die "release manifest not found: ${RELEASE_MANIFEST}"
}

load_release_manifest() {
    local manifest_version
    local manifest_image_tag
    local flag
    local value

    resolve_release_manifest_path
    [[ -n "${RELEASE_MANIFEST}" ]] || return

    manifest_version="$(manifest_release_value "${RELEASE_MANIFEST}" "version")"
    manifest_image_tag="$(manifest_release_value "${RELEASE_MANIFEST}" "image_tag")"
    [[ -n "${manifest_version}" ]] || die "release manifest is missing release.version"
    [[ -n "${manifest_image_tag}" ]] || die "release manifest is missing release.image_tag"
    [[ "${manifest_version}" == v* ]] || die "release manifest release.version must use vX.Y.Z form"
    [[ "${manifest_image_tag}" != v* ]] || die "release manifest release.image_tag must use X.Y.Z form"

    manifest_version="$(normalize_release_version "${manifest_version}")"
    manifest_image_tag="$(normalize_release_version "${manifest_image_tag}")"
    [[ "${manifest_version}" == "${manifest_image_tag}" ]] || \
        die "release manifest release.version and release.image_tag disagree"

    if [[ -n "${RELEASE_VERSION}" ]]; then
        [[ "$(normalize_release_version "${RELEASE_VERSION}")" == "${manifest_version}" ]] || \
            die "release manifest version does not match --release-version"
    fi
    RELEASE_VERSION="${manifest_version}"

    for flag in platform_changed infrastructure_changed secrets_changed observability_changed public_tls_reapply_required; do
        value="$(manifest_flag_value "${RELEASE_MANIFEST}" "${flag}")"
        [[ -n "${value}" ]] || die "release manifest is missing phase_flags.${flag}"
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

validate_manifest_images_match_inventory() {
    local service
    local manifest_ref
    local inventory_ref

    [[ -n "${RELEASE_MANIFEST}" ]] || return

    for service in "${SERVICE_ORDER[@]}"; do
        manifest_ref="$(manifest_nested_value "${RELEASE_MANIFEST}" "artifacts" "${service}" "image")"
        [[ -n "${manifest_ref}" ]] || die "release manifest is missing artifacts.${service}.image"
        inventory_ref="$(inventory_value "${service}")"
        [[ "${manifest_ref}" == "${inventory_ref}" ]] || \
            die "release manifest image for ${service} does not match the checked-in production image inventory"
    done
}

resolve_release_version() {
    local inventory_version

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || die "missing production image inventory: ${PRODUCTION_IMAGE_INVENTORY}"

    inventory_version="$(inventory_value "release-version")"
    [[ -n "${inventory_version}" ]] || die "production image inventory is missing release-version"

    if [[ -z "${RELEASE_VERSION}" ]]; then
        RELEASE_VERSION="${inventory_version}"
    fi

    RELEASE_VERSION="$(normalize_release_version "${RELEASE_VERSION}")"
    [[ "${RELEASE_VERSION}" == "$(normalize_release_version "${inventory_version}")" ]] || \
        die "release version ${RELEASE_VERSION} does not match the checked-in production image inventory ${inventory_version}; update and review the image baseline first"

    validate_manifest_images_match_inventory
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
        lockstep)
            [[ -n "${RELEASE_MANIFEST}" ]] || die "--mode lockstep requires --release-manifest so phase flags are explicit"
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

    if [[ "${SKIP_PLATFORM}" == "true" ]]; then
        RUN_PLATFORM=false
    fi
    if [[ "${SKIP_INFRASTRUCTURE}" == "true" ]]; then
        RUN_INFRASTRUCTURE=false
    fi
    if [[ "${SKIP_SECRETS}" == "true" ]]; then
        RUN_SECRETS=false
    fi
    if [[ "${SKIP_OBSERVABILITY}" == "true" ]]; then
        RUN_OBSERVABILITY=false
    fi
    if [[ "${REAPPLY_PUBLIC_TLS}" == "true" ]]; then
        RUN_PUBLIC_TLS=true
    fi
}

selected_apply_count() {
    local count=0

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
    require_executable "${LOCKSTEP_VERIFIER}"
    info "running OCI lockstep static verifier"
    "${LOCKSTEP_VERIFIER}"
}

run_live_production_verifier() {
    require_executable "${PRODUCTION_VERIFIER}"
    info "running production image/render verifier"
    "${PRODUCTION_VERIFIER}"
}

run_pod_version_label_verifier() {
    require_executable "${POD_VERSION_LABELS_SCRIPT}"
    info "verifying live runtime release labels"
    run_cmd "${POD_VERSION_LABELS_SCRIPT}" --expected-version "v${RELEASE_VERSION}" --tracked-only --strict
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

    run_pod_version_label_verifier
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
    run_pod_version_label_verifier
    run_cmd "${OBSERVABILITY_ACCESS_VERIFIER}"
    run_cmd "${MONITORING_RUNTIME_VERIFIER}" --wait-timeout 180
}

print_plan_summary() {
    info "deployment selection"
    printf '  mode: %s\n' "${MODE}"
    printf '  release-version: %s\n' "${RELEASE_VERSION}"
    printf '  release-manifest: %s\n' "${RELEASE_MANIFEST:-none}"
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
    info "OCI release deployment wrapper complete"
    printf '\nCompletion checklist:\n'
    printf '  - Review snapshots under %s\n' "${SNAPSHOT_DIR}"
    printf '  - Confirm live images match kubernetes/production/apps/image-inventory.yaml\n'
    printf '  - Confirm live release labels: ./scripts/ops/show-pod-version-labels.sh --expected-version v%s --tracked-only --strict\n' "${RELEASE_VERSION}"
    printf '  - Confirm observability remains internal-only; no Grafana, Prometheus, Jaeger, or Kiali public routes\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/api-docs\n'
    printf '  - From a workstation, verify: curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json\n'
}

main() {
    parse_args "$@"
    load_release_manifest
    resolve_release_version
    configure_mode
    configure_kubeconfig
    phase4_load_instance_env
    phase4_require_commands kubectl helm
    phase4_require_cluster_access

    SNAPSHOT_DIR="${SNAPSHOT_ROOT}/$(date -u +%Y%m%dT%H%M%SZ)-${MODE}-${RELEASE_VERSION}"
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
