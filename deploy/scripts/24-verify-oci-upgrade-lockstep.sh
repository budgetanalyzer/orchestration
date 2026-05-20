#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

TILTFILE="$(phase4_repo_path "Tiltfile")"
PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
PRODUCTION_KUSTOMIZATION="${PRODUCTION_APPS_DIR}/kustomization.yaml"
PRODUCTION_IMAGE_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
PRODUCTION_INFRASTRUCTURE_DIR="$(phase4_repo_path "kubernetes/production/infrastructure")"
PROMETHEUS_VALUES_FILE="$(phase4_repo_path "kubernetes/monitoring/prometheus-stack-values.yaml")"
KIALI_VALUES_FILE="$(phase4_repo_path "kubernetes/monitoring/kiali-values.yaml")"
KYVERNO_VALUES_FILE="$(phase4_repo_path "deploy/helm-values/kyverno.values.yaml")"
EXTERNAL_SECRETS_VALUES_FILE="$(phase4_repo_path "deploy/helm-values/external-secrets.values.yaml")"
CERT_MANAGER_VALUES_FILE="$(phase4_repo_path "deploy/helm-values/cert-manager.values.yaml")"
readonly TILTFILE
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly PRODUCTION_KUSTOMIZATION
readonly PRODUCTION_IMAGE_VERIFIER
readonly PRODUCTION_INFRASTRUCTURE_DIR
readonly PROMETHEUS_VALUES_FILE
readonly KIALI_VALUES_FILE
readonly KYVERNO_VALUES_FILE
readonly EXTERNAL_SECRETS_VALUES_FILE
readonly CERT_MANAGER_VALUES_FILE

SERVICE_ORDER=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "ext-authz"
)
readonly SERVICE_ORDER

declare -A IMAGE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="ext-authz"
)

declare -A INVENTORY_REFS=()
TEMP_DIR=""

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh

Runs static OCI lockstep checks before release or deployment work:
  - local Tilt chart pins match OCI phase version contracts
  - production image inventory and production app kustomization agree
  - production image verifier consumes the inventory instead of hardcoded refs
  - production /api-docs ConfigMaps and nginx-gateway volume wiring render
  - production infrastructure images are digest-pinned
  - production Helm values carry digest pin inputs for chart-managed images

This script is non-mutating and does not require a live Kubernetes cluster.
EOF
}

fail() {
    printf '[lockstep] ERROR: %s\n' "$1" >&2
    exit 1
}

warn() {
    printf '[lockstep] WARN: %s\n' "$*" >&2
}

info() {
    printf '[lockstep] %s\n' "$*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

cleanup() {
    if [[ -n "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
    fi
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

load_inventory_refs() {
    local release_version service repo image_ref expected_pattern

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || fail "missing production image inventory: ${PRODUCTION_IMAGE_INVENTORY}"

    release_version="$(inventory_value "release-version")"
    [[ "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        fail "production image inventory release-version must use X.Y.Z format"

    for service in "${SERVICE_ORDER[@]}"; do
        repo="${IMAGE_REPOS[${service}]}"
        image_ref="$(inventory_value "${service}")"
        [[ -n "${image_ref}" ]] || fail "production image inventory is missing ${service}"

        expected_pattern="^ghcr\\.io/budgetanalyzer/${repo}:${release_version}@sha256:[0-9a-f]{64}$"
        if [[ ! "${image_ref}" =~ ${expected_pattern} ]]; then
            fail "invalid production image ref for ${service}: ${image_ref}"
        fi

        INVENTORY_REFS["${service}"]="${image_ref}"
    done
}

extract_tilt_chart_versions() {
    local chart_pattern="$1"

    awk -v chart_pattern="${chart_pattern}" '
        $0 ~ chart_pattern {
            in_chart = 1
        }
        in_chart && /--version[[:space:]]+/ {
            for (i = 1; i <= NF; i++) {
                if ($i == "--version") {
                    version = $(i + 1)
                    gsub(/\\/, "", version)
                    print version
                    in_chart = 0
                    next
                }
            }
        }
    ' "${TILTFILE}" | sort -u
}

assert_single_tilt_version() {
    local label="$1"
    local chart_pattern="$2"
    local expected="$3"
    local versions
    local version_count

    versions="$(extract_tilt_chart_versions "${chart_pattern}")"
    [[ -n "${versions}" ]] || fail "could not find local Tilt chart version for ${label}"

    version_count="$(printf '%s\n' "${versions}" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "${version_count}" != "1" ]]; then
        fail "local Tilt uses multiple ${label} versions: ${versions//$'\n'/, }"
    fi

    if [[ "${versions}" != "${expected}" ]]; then
        fail "${label} version drift: local Tilt=${versions}, OCI=${expected}"
    fi
}

verify_version_lockstep() {
    [[ -f "${TILTFILE}" ]] || fail "missing Tiltfile: ${TILTFILE}"

    if [[ "${PHASE4_GATEWAY_API_CRDS_VERSION}" != "${PHASE7_GATEWAY_API_VERSION}" ]]; then
        fail "Gateway API version drift: local=${PHASE7_GATEWAY_API_VERSION}, OCI=${PHASE4_GATEWAY_API_CRDS_VERSION}"
    fi

    assert_single_tilt_version "Istio" 'helm upgrade --install .*istio/(base|cni|istiod|gateway)([[:space:]]|$)' "${PHASE4_ISTIO_CHART_VERSION}"
    assert_single_tilt_version "Kyverno" 'helm upgrade --install .*kyverno/kyverno([[:space:]]|$)' "${PHASE7_KYVERNO_CHART_VERSION}"
    assert_single_tilt_version "kube-prometheus-stack" 'helm upgrade --install .*prometheus-community/kube-prometheus-stack([[:space:]]|$)' "${PHASE7_PROMETHEUS_STACK_CHART_VERSION}"
    assert_single_tilt_version "Kiali" 'helm upgrade --install .*kiali/kiali-server([[:space:]]|$)' "${PHASE7_KIALI_CHART_VERSION}"

    if ! grep -Fq "pod-security.kubernetes.io/enforce-version=${PHASE4_POD_SECURITY_VERSION}" "${TILTFILE}"; then
        fail "Tiltfile Pod Security enforce-version does not match OCI ${PHASE4_POD_SECURITY_VERSION}"
    fi

    warn "Kind node image and k3s version are intentionally non-identical surfaces; verify Kubernetes compatibility in the upgrade notes."
    warn "Calico is local-only for Kind; OCI relies on k3s NetworkPolicy enforcement."
    warn "Tilt is local-only and has no OCI runtime component."
}

literal_count() {
    local file="$1"
    local needle="$2"

    { grep -F -o -- "${needle}" "${file}" || true; } | wc -l | tr -d ' '
}

extract_image_fields() {
    local file="$1"

    sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "${file}"
}

image_ref_is_inventory_ref() {
    local image_ref="$1"
    local service

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ "${image_ref}" == "${INVENTORY_REFS[${service}]}" ]]; then
            return 0
        fi
    done

    return 1
}

verify_image_alignment() {
    local rendered_apps_file="$1"
    local image_fields_file="$2"
    local service ref count image_ref

    [[ -f "${PRODUCTION_KUSTOMIZATION}" ]] || fail "missing production kustomization: ${PRODUCTION_KUSTOMIZATION}"
    [[ -f "${PRODUCTION_IMAGE_VERIFIER}" ]] || fail "missing production image verifier: ${PRODUCTION_IMAGE_VERIFIER}"

    for service in "${SERVICE_ORDER[@]}"; do
        ref="${INVENTORY_REFS[${service}]}"
        count="$(literal_count "${PRODUCTION_KUSTOMIZATION}" "${ref}")"
        [[ "${count}" == "1" ]] || fail "${service} image appears ${count} times in production kustomization; expected 1"
    done

    extract_image_fields "${rendered_apps_file}" > "${image_fields_file}"
    for service in "${SERVICE_ORDER[@]}"; do
        ref="${INVENTORY_REFS[${service}]}"
        count="$(grep -Fxc "${ref}" "${image_fields_file}" || true)"
        [[ "${count}" == "1" ]] || fail "${service} image appears ${count} times as a rendered workload image; expected 1"
    done

    while IFS= read -r image_ref; do
        [[ -n "${image_ref}" ]] || continue
        if [[ "${image_ref}" == ghcr.io/budgetanalyzer/* ]] && ! image_ref_is_inventory_ref "${image_ref}"; then
            fail "rendered production app overlay contains a Budget Analyzer image outside the inventory: ${image_ref}"
        fi
    done < "${image_fields_file}"

    if grep -Eq 'ghcr\.io/budgetanalyzer/[a-z0-9-]+:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' "${PRODUCTION_IMAGE_VERIFIER}"; then
        fail "production image verifier still carries hardcoded Budget Analyzer release refs instead of consuming image-inventory.yaml"
    fi
}

assert_contains_literal() {
    local file="$1"
    local needle="$2"
    local description="$3"

    grep -Fq "${needle}" "${file}" || fail "${description}"
}

verify_api_docs_render_wiring() {
    local rendered_apps_file="$1"

    assert_contains_literal "${rendered_apps_file}" 'name: nginx-gateway-docs' \
        "rendered apps overlay is missing nginx-gateway-docs ConfigMap"
    assert_contains_literal "${rendered_apps_file}" 'name: nginx-gateway-openapi-json' \
        "rendered apps overlay is missing nginx-gateway-openapi-json ConfigMap"
    assert_contains_literal "${rendered_apps_file}" 'name: nginx-gateway-openapi-yaml' \
        "rendered apps overlay is missing nginx-gateway-openapi-yaml ConfigMap"
    assert_contains_literal "${rendered_apps_file}" 'mountPath: /custom-docs' \
        "nginx-gateway no longer mounts the docs ConfigMap into the docs init container"
    assert_contains_literal "${rendered_apps_file}" 'mountPath: /custom-openapi-json' \
        "nginx-gateway no longer mounts the OpenAPI JSON ConfigMap into the docs init container"
    assert_contains_literal "${rendered_apps_file}" 'mountPath: /custom-openapi-yaml' \
        "nginx-gateway no longer mounts the OpenAPI YAML ConfigMap into the docs init container"
    assert_contains_literal "${rendered_apps_file}" 'cp /custom-docs/* /workdir/docs/' \
        "nginx-gateway docs init command no longer copies custom docs"
    assert_contains_literal "${rendered_apps_file}" 'cp /custom-openapi-json/* /workdir/docs/' \
        "nginx-gateway docs init command no longer copies OpenAPI JSON"
    assert_contains_literal "${rendered_apps_file}" 'cp /custom-openapi-yaml/* /workdir/docs/' \
        "nginx-gateway docs init command no longer copies OpenAPI YAML"
}

verify_rendered_images_are_digest_pinned() {
    local file="$1"
    local description="$2"
    local image_ref
    local refs_checked=0

    while IFS= read -r image_ref; do
        [[ -n "${image_ref}" ]] || continue
        refs_checked=$((refs_checked + 1))
        if [[ ! "${image_ref}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            fail "${description} contains non-digest-pinned image: ${image_ref}"
        fi
    done < <(extract_image_fields "${file}")

    (( refs_checked > 0 )) || fail "${description} did not render any image fields"
}

verify_prometheus_values_digest_inputs() {
    awk '
        /^[[:space:]]*repository:[[:space:]]*/ {
            repo_line = NR
            repo = $0
            sub(/^[[:space:]]*repository:[[:space:]]*/, "", repo)
            gsub(/"/, "", repo)
            waiting = 1
            next
        }
        waiting && /^[[:space:]]*sha:[[:space:]]*(sha256:)?[0-9a-f]{64}[[:space:]]*$/ {
            waiting = 0
            next
        }
        waiting && NR > repo_line + 4 {
            print repo
            bad = 1
            waiting = 0
        }
        END {
            if (waiting) {
                print repo
                bad = 1
            }
            exit bad ? 1 : 0
        }
    ' "${PROMETHEUS_VALUES_FILE}" >/dev/null || \
        fail "Prometheus stack values contain image repositories without nearby sha digest pins"
}

verify_kyverno_values_digest_inputs() {
    if grep -E '^[[:space:]]+repository:[[:space:]]+' "${KYVERNO_VALUES_FILE}" | grep -Ev '@sha256[[:space:]]*$' >/dev/null; then
        fail "Kyverno values contain image repositories without @sha256"
    fi

    if grep -E '^[[:space:]]+tag:[[:space:]]*"?[0-9a-f]{64}"?[[:space:]]*$' "${KYVERNO_VALUES_FILE}" >/dev/null; then
        return
    fi

    fail "Kyverno values do not contain digest-form tag values"
}

verify_simple_digest_fields() {
    local file="$1"
    local description="$2"

    if grep -Eq 'digest:[[:space:]]*sha256:[0-9a-f]{64}' "${file}"; then
        return
    fi

    fail "${description} values do not contain sha256 digest fields"
}

verify_helm_values_digest_inputs() {
    [[ -f "${PROMETHEUS_VALUES_FILE}" ]] || fail "missing Prometheus values: ${PROMETHEUS_VALUES_FILE}"
    [[ -f "${KIALI_VALUES_FILE}" ]] || fail "missing Kiali values: ${KIALI_VALUES_FILE}"
    [[ -f "${KYVERNO_VALUES_FILE}" ]] || fail "missing Kyverno values: ${KYVERNO_VALUES_FILE}"
    [[ -f "${EXTERNAL_SECRETS_VALUES_FILE}" ]] || fail "missing External Secrets values: ${EXTERNAL_SECRETS_VALUES_FILE}"
    [[ -f "${CERT_MANAGER_VALUES_FILE}" ]] || fail "missing cert-manager values: ${CERT_MANAGER_VALUES_FILE}"

    verify_prometheus_values_digest_inputs
    verify_kyverno_values_digest_inputs
    verify_simple_digest_fields "${EXTERNAL_SECRETS_VALUES_FILE}" "External Secrets"
    verify_simple_digest_fields "${CERT_MANAGER_VALUES_FILE}" "cert-manager"

    if ! grep -Eq 'image_digest:[[:space:]]*sha256:[0-9a-f]{64}' "${KIALI_VALUES_FILE}"; then
        fail "Kiali values do not contain image_digest: sha256:<digest>"
    fi
}

main() {
    local rendered_apps_file rendered_infrastructure_file image_fields_file

    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 0 ]] || fail "unknown option: $1"

    require_command kubectl
    load_inventory_refs
    verify_version_lockstep

    TEMP_DIR="$(mktemp -d)"
    trap cleanup EXIT
    rendered_apps_file="${TEMP_DIR}/production-apps.yaml"
    rendered_infrastructure_file="${TEMP_DIR}/production-infrastructure.yaml"
    image_fields_file="${TEMP_DIR}/production-app-images.txt"

    kubectl kustomize "${PRODUCTION_APPS_DIR}" --load-restrictor=LoadRestrictionsNone > "${rendered_apps_file}"
    kubectl kustomize "${PRODUCTION_INFRASTRUCTURE_DIR}" --load-restrictor=LoadRestrictionsNone > "${rendered_infrastructure_file}"

    verify_image_alignment "${rendered_apps_file}" "${image_fields_file}"
    verify_api_docs_render_wiring "${rendered_apps_file}"
    verify_rendered_images_are_digest_pinned "${rendered_infrastructure_file}" "production infrastructure overlay"
    verify_helm_values_digest_inputs

    info "OCI upgrade lockstep verification passed"
}

main "$@"
