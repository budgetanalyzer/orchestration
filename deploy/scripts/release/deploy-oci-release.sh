#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/../lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
STATIC_VERIFIER="${SCRIPT_DIR}/../verify/oci-upgrade-lockstep.sh"
POD_VERSION_LABELS_SCRIPT="$(phase4_repo_path "scripts/ops/show-pod-version-labels.sh")"
SNAPSHOT_ROOT="$(phase4_repo_path "tmp/oci-release-deploy")"
PHASE6_RENDER_ROOT="$(phase4_repo_path "tmp/phase-6")"
APP_NAMESPACE="default"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly STATIC_VERIFIER
readonly POD_VERSION_LABELS_SCRIPT
readonly SNAPSHOT_ROOT
readonly PHASE6_RENDER_ROOT
readonly APP_NAMESPACE

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

DEPLOYMENT_MANIFEST=""
DEPLOYMENT_ID=""
EXPLICIT_KUBECONFIG=false
SNAPSHOT_DIR=""
SELECTIVE_APPS_OVERLAY_DIR=""
declare -a CHANGED_DEPLOYMENTS=()
declare -a UNCHANGED_DEPLOYMENTS=()

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/release/deploy-oci-release.sh --deployment-manifest PATH [options]

OCI desired-state deployment applier.

Required:
  --deployment-manifest PATH

Options:
  --kubeconfig PATH
  -h, --help

The script validates a schema v2 deployment manifest against the checked-in
production image inventory, captures pre/post cluster snapshots, applies the
managed production app set without restarting already-current workloads, waits
for changed workload rollouts, and verifies live pod metadata against the same
manifest. It does not run host-only certificate generation.
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

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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
    local schema_version

    resolve_deployment_manifest_path
    schema_version="$(manifest_value "${DEPLOYMENT_MANIFEST}" "schema_version")"
    [[ "${schema_version}" == "2" ]] || die "deployment manifest must use schema_version: 2"

    DEPLOYMENT_ID="$(manifest_map_value "${DEPLOYMENT_MANIFEST}" "deployment" "id")"
    [[ -n "${DEPLOYMENT_ID}" ]] || die "deployment manifest is missing deployment.id"
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

run_cmd() {
    "$@"
}

run_bash() {
    local command="$1"

    bash -c "${command}"
}

require_executable() {
    local path="$1"

    [[ -x "${path}" ]] || die "missing executable: ${path}"
}

artifact_for_workload() {
    case "$1" in
        nginx-gateway)
            printf '%s\n' "budget-analyzer-web"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

image_list_contains() {
    local image_list="$1"
    local expected_image="$2"
    local image
    local -a images_array=()

    IFS=',' read -r -a images_array <<< "${image_list}"
    for image in "${images_array[@]}"; do
        if [[ "${image}" == "${expected_image}" ]]; then
            return 0
        fi
    done

    return 1
}

kubectl_jsonpath() {
    local jsonpath="$1"
    shift

    kubectl get "$@" -o "jsonpath=${jsonpath}" 2>/dev/null || true
}

live_deployment_template_value() {
    local deployment="$1"
    local jsonpath="$2"

    kubectl_jsonpath "${jsonpath}" "deployment/${deployment}" -n "${APP_NAMESPACE}"
}

deployment_matches_manifest() {
    local deployment="$1"
    local artifact expected_image expected_version expected_revision expected_source_ref expected_service_common
    local live_deployment_id live_version live_image_annotation live_revision live_source_ref live_service_common live_init_images live_images live_all_images

    if ! kubectl get "deployment/${deployment}" -n "${APP_NAMESPACE}" >/dev/null 2>&1; then
        return 1
    fi

    artifact="$(artifact_for_workload "${deployment}")"
    expected_image="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "image")"
    expected_version="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "artifact_version")"
    expected_revision="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "source_commit")"
    expected_source_ref="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "source_ref")"
    expected_service_common="$(manifest_nested_value "${DEPLOYMENT_MANIFEST}" "artifacts" "${artifact}" "service_common_version")"

    live_deployment_id="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.labels.budgetanalyzer\.org/deployment-id}')"
    live_version="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.labels.app\.kubernetes\.io/version}')"
    live_image_annotation="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.annotations.budgetanalyzer\.org/image}')"
    live_revision="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.annotations.org\.opencontainers\.image\.revision}')"
    live_source_ref="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.annotations.budgetanalyzer\.org/source-ref}')"
    live_service_common="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.annotations.budgetanalyzer\.org/service-common-version}')"
    # shellcheck disable=SC2016 # Go template variables must remain literal for kubectl.
    live_init_images="$(live_deployment_template_value "${deployment}" '{range $index, $container := .spec.template.spec.initContainers}{if $index},{end}{$container.image}{end}')"
    # shellcheck disable=SC2016 # Go template variables must remain literal for kubectl.
    live_images="$(live_deployment_template_value "${deployment}" '{range $index, $container := .spec.template.spec.containers}{if $index},{end}{$container.image}{end}')"
    live_all_images="${live_init_images}${live_init_images:+,}${live_images}"

    [[ -n "${live_deployment_id}" ]] || return 1
    [[ "${live_version}" == "${expected_version}" ]] || return 1
    [[ "${live_image_annotation}" == "${expected_image}" ]] || return 1
    [[ "${live_revision}" == "${expected_revision}" ]] || return 1
    [[ "${live_source_ref}" == "${expected_source_ref}" ]] || return 1
    image_list_contains "${live_all_images}" "${expected_image}" || return 1

    if [[ -n "${expected_service_common}" && "${live_service_common}" != "${expected_service_common}" ]]; then
        return 1
    fi

    return 0
}

classify_deployments_for_selective_apply() {
    local deployment

    CHANGED_DEPLOYMENTS=()
    UNCHANGED_DEPLOYMENTS=()

    for deployment in "${SERVICE_DEPLOYMENTS[@]}"; do
        if deployment_matches_manifest "${deployment}"; then
            UNCHANGED_DEPLOYMENTS+=("${deployment}")
        else
            CHANGED_DEPLOYMENTS+=("${deployment}")
        fi
    done
}

yaml_double_quote() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/'
}

relative_path() {
    local from_dir="$1"
    local to_path="$2"

    realpath --relative-to="${from_dir}" "${to_path}"
}

write_selective_apps_overlay() {
    local production_apps_relative
    local deployment live_deployment_id quoted_deployment_id

    SELECTIVE_APPS_OVERLAY_DIR="${SNAPSHOT_DIR}/selective-apps-kustomize"
    mkdir -p "${SELECTIVE_APPS_OVERLAY_DIR}"

    production_apps_relative="$(relative_path "${SELECTIVE_APPS_OVERLAY_DIR}" "${PRODUCTION_APPS_DIR}")"

    {
        printf 'apiVersion: kustomize.config.k8s.io/v1beta1\n'
        printf 'kind: Kustomization\n'
        printf 'resources:\n'
        printf '  - %s\n' "${production_apps_relative}"

        if (( ${#UNCHANGED_DEPLOYMENTS[@]} > 0 )); then
            printf 'patches:\n'
        fi

        for deployment in "${UNCHANGED_DEPLOYMENTS[@]}"; do
            live_deployment_id="$(live_deployment_template_value "${deployment}" '{.spec.template.metadata.labels.budgetanalyzer\.org/deployment-id}')"
            quoted_deployment_id="$(yaml_double_quote "${live_deployment_id}")"
            printf '  - target:\n'
            printf '      kind: Deployment\n'
            printf '      name: %s\n' "${deployment}"
            printf '    patch: |-\n'
            printf '      - op: replace\n'
            printf '        path: /spec/template/metadata/labels/budgetanalyzer.org~1deployment-id\n'
            printf '        value: %s\n' "${quoted_deployment_id}"
        done
    } > "${SELECTIVE_APPS_OVERLAY_DIR}/kustomization.yaml"
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

run_pod_metadata_verifier() {
    local args=(--deployment-manifest "${DEPLOYMENT_MANIFEST}" --tracked-only --strict --allow-mixed-deployment-id)

    require_executable "${POD_VERSION_LABELS_SCRIPT}"
    info "verifying live runtime deployment metadata"
    run_cmd "${POD_VERSION_LABELS_SCRIPT}" "${args[@]}"
}

apply_production_apps() {
    classify_deployments_for_selective_apply
    write_selective_apps_overlay

    info "applying production apps with selective workload rollout"
    if (( ${#CHANGED_DEPLOYMENTS[@]} == 0 )); then
        printf '  changed deployments: <none>\n'
    else
        printf '  changed deployments: %s\n' "${CHANGED_DEPLOYMENTS[*]}"
    fi
    if (( ${#UNCHANGED_DEPLOYMENTS[@]} == 0 )); then
        printf '  already-current deployments: <none>\n'
    else
        printf '  already-current deployments: %s\n' "${UNCHANGED_DEPLOYMENTS[*]}"
    fi

    run_bash "kubectl kustomize '${SELECTIVE_APPS_OVERLAY_DIR}' --load-restrictor=LoadRestrictionsNone | kubectl apply --server-side -f -"
}

run_application_phase() {
    local deployment

    info "running application phase"
    run_cmd "${SCRIPT_DIR}/../render/phase-6-production-manifests.sh"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/gateway-routes.yaml"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/istio-ingress-policies.yaml"
    run_cmd kubectl apply -f "${PHASE6_RENDER_ROOT}/istio-egress.yaml"

    apply_production_apps

    for deployment in "${CHANGED_DEPLOYMENTS[@]}"; do
        run_cmd kubectl rollout status "deployment/${deployment}" -n "${APP_NAMESPACE}" --timeout=300s
    done

    run_pod_metadata_verifier
}

print_plan_summary() {
    info "deployment desired state"
    printf '  deployment-id: %s\n' "${DEPLOYMENT_ID}"
    printf '  deployment-manifest: %s\n' "${DEPLOYMENT_MANIFEST}"
}

print_completion_checklist() {
    info "OCI deployment wrapper complete"
    printf '\nCompletion checklist:\n'
    printf '  - Review snapshots under %s\n' "${SNAPSHOT_DIR}"
    printf '  - Confirm OCI pods match the checked-in manifest: ./scripts/ops/show-pod-version-labels.sh --deployment-manifest %s --tracked-only --strict --allow-mixed-deployment-id\n' "${DEPLOYMENT_MANIFEST}"
    printf '  - Confirm observability remains internal-only; no Grafana, Prometheus, Jaeger, or Kiali public routes\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/\n'
    printf '  - From a workstation, verify: curl -I https://demo.budgetanalyzer.org/api-docs\n'
    printf '  - From a workstation, verify: curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json\n'
}

main() {
    parse_args "$@"
    load_deployment_manifest
    validate_manifest_matches_inventory
    configure_kubeconfig
    phase4_load_instance_env
    phase4_require_commands kubectl helm realpath
    phase4_require_cluster_access

    SNAPSHOT_DIR="${SNAPSHOT_ROOT}/$(date -u +%Y%m%dT%H%M%SZ)-manifest-${DEPLOYMENT_ID}"
    mkdir -p "${SNAPSHOT_DIR}"

    print_plan_summary
    run_static_preflight
    capture_snapshot preflight

    run_application_phase

    capture_snapshot post-deploy
    print_completion_checklist
}

main "$@"
