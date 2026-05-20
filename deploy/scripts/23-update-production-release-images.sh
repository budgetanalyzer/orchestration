#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

PRODUCTION_APPS_DIR="$(phase4_repo_path "kubernetes/production/apps")"
PRODUCTION_IMAGE_INVENTORY="${PRODUCTION_APPS_DIR}/image-inventory.yaml"
PRODUCTION_KUSTOMIZATION="${PRODUCTION_APPS_DIR}/kustomization.yaml"
PRODUCTION_IMAGE_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
LOCKSTEP_VERIFIER="${SCRIPT_DIR}/24-verify-oci-upgrade-lockstep.sh"
INSTANCE_ENV_TEMPLATE="$(phase4_repo_path "deploy/instance.env.template")"
readonly PRODUCTION_APPS_DIR
readonly PRODUCTION_IMAGE_INVENTORY
readonly PRODUCTION_KUSTOMIZATION
readonly PRODUCTION_IMAGE_VERIFIER
readonly LOCKSTEP_VERIFIER
readonly INSTANCE_ENV_TEMPLATE

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

declare -A IMAGE_REFS=()

usage() {
    cat <<'EOF'
Usage:
  ./deploy/scripts/23-update-production-release-images.sh \
    --release-version 0.0.x \
    --transaction-service ghcr.io/budgetanalyzer/transaction-service:0.0.x@sha256:<digest> \
    --currency-service ghcr.io/budgetanalyzer/currency-service:0.0.x@sha256:<digest> \
    --permission-service ghcr.io/budgetanalyzer/permission-service:0.0.x@sha256:<digest> \
    --session-gateway ghcr.io/budgetanalyzer/session-gateway:0.0.x@sha256:<digest> \
    --budget-analyzer-web ghcr.io/budgetanalyzer/budget-analyzer-web:0.0.x@sha256:<digest> \
    --ext-authz ghcr.io/budgetanalyzer/ext-authz:0.0.x@sha256:<digest>

  ./deploy/scripts/23-update-production-release-images.sh \
    --release-manifest tmp/releases/v0.0.x.yaml

Updates the checked-in OCI production application image baseline. The release
manifest form accepts release-version/version plus the six service keys listed
above, either at top level or under an images mapping.

By default the script runs:
  kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
  ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
  ./scripts/guardrails/verify-production-image-overlay.sh

Use --skip-live-production-verifier only when no live Kubernetes context is
available for the existing production verifier's Helm server-side Kiali render.
EOF
}

manifest_value() {
    local manifest="$1"
    local key="$2"

    awk -v key="${key}" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            value = $0
            sub("^[[:space:]]*" key ":[[:space:]]*", "", value)
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
        phase4_die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
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

load_manifest() {
    local manifest="$1"
    local service value

    [[ -f "${manifest}" ]] || phase4_die "release manifest not found: ${manifest}"

    if [[ -z "${release_version}" ]]; then
        release_version="$(manifest_value "${manifest}" "release-version")"
        if [[ -z "${release_version}" ]]; then
            release_version="$(manifest_value "${manifest}" "version")"
        fi
    fi

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ -z "${IMAGE_REFS[${service}]:-}" ]]; then
            value="$(manifest_value "${manifest}" "${service}")"
            if [[ -n "${value}" ]]; then
                IMAGE_REFS["${service}"]="${value}"
            fi
        fi
    done
}

validate_image_refs() {
    local service repo image_ref expected_pattern

    release_version="$(normalize_release_version "${release_version}")"

    for service in "${SERVICE_ORDER[@]}"; do
        repo="${IMAGE_REPOS[${service}]}"
        image_ref="${IMAGE_REFS[${service}]:-}"
        [[ -n "${image_ref}" ]] || phase4_die "missing image ref for ${service}"

        expected_pattern="^ghcr\\.io/budgetanalyzer/${repo}:${release_version}@sha256:[0-9a-f]{64}$"
        if [[ ! "${image_ref}" =~ ${expected_pattern} ]]; then
            phase4_die "invalid image ref for ${service}; expected ghcr.io/budgetanalyzer/${repo}:${release_version}@sha256:<64 lowercase hex>, got: ${image_ref}"
        fi

        if [[ "${image_ref}" == *":latest"* || "${image_ref}" == *":tilt-"* ]]; then
            phase4_die "mutable image ref is not allowed for ${service}: ${image_ref}"
        fi
    done
}

write_image_inventory() {
    local temp_file

    temp_file="${PRODUCTION_IMAGE_INVENTORY}.tmp"
    cat > "${temp_file}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: production-image-inventory
  namespace: default
  labels:
    app.kubernetes.io/part-of: budget-analyzer
    app.kubernetes.io/component: production-image-inventory
data:
  release-version: "${release_version}"
  transaction-service: "${IMAGE_REFS[transaction-service]}"
  currency-service: "${IMAGE_REFS[currency-service]}"
  permission-service: "${IMAGE_REFS[permission-service]}"
  session-gateway: "${IMAGE_REFS[session-gateway]}"
  budget-analyzer-web: "${IMAGE_REFS[budget-analyzer-web]}"
  ext-authz: "${IMAGE_REFS[ext-authz]}"
EOF
    mv "${temp_file}" "${PRODUCTION_IMAGE_INVENTORY}"
}

replace_literal_in_file() {
    local file="$1"
    local old="$2"
    local new="$3"
    local temp_file
    local escaped_old
    local escaped_new

    [[ -f "${file}" ]] || return 0
    [[ "${old}" != "${new}" ]] || return 0

    escaped_old="$(phase4_escape_sed_replacement "${old}")"
    escaped_new="$(phase4_escape_sed_replacement "${new}")"
    temp_file="${file}.tmp"

    sed "s/${escaped_old}/${escaped_new}/g" "${file}" > "${temp_file}"
    mv "${temp_file}" "${file}"
}

replace_image_ref_in_kustomization() {
    local service="$1"
    local repo="${IMAGE_REPOS[${service}]}"
    local old_ref new_ref temp_file

    old_ref="$(inventory_value "${service}")"
    new_ref="${IMAGE_REFS[${service}]}"

    [[ -n "${old_ref}" ]] || phase4_die "current production image inventory is missing ${service}"
    if ! grep -Fq "${old_ref}" "${PRODUCTION_KUSTOMIZATION}"; then
        phase4_die "current kustomization does not contain the inventory image for ${service}: ${old_ref}"
    fi

    temp_file="${PRODUCTION_KUSTOMIZATION}.tmp"
    sed -E "s#ghcr\\.io/budgetanalyzer/${repo}:[^[:space:]\"']+@sha256:[0-9a-f]{64}#${new_ref}#g" \
        "${PRODUCTION_KUSTOMIZATION}" > "${temp_file}"
    mv "${temp_file}" "${PRODUCTION_KUSTOMIZATION}"
}

update_kustomization() {
    local service

    for service in "${SERVICE_ORDER[@]}"; do
        replace_image_ref_in_kustomization "${service}"
    done
}

update_release_version_references() {
    local old_release_version="$1"
    local doc

    replace_literal_in_file "${INSTANCE_ENV_TEMPLATE}" \
        "PRODUCTION_RELEASE_VERSION=${old_release_version}" \
        "PRODUCTION_RELEASE_VERSION=${release_version}"

    for doc in \
        "$(phase4_repo_path "kubernetes/production/README.md")" \
        "$(phase4_repo_path "scripts/README.md")" \
        "$(phase4_repo_path "docs/ci-cd.md")"; do
        replace_literal_in_file "${doc}" "${old_release_version}" "${release_version}"
        replace_literal_in_file "${doc}" "v${old_release_version}" "v${release_version}"
    done
}

verify_updates() {
    phase4_require_commands kubectl

    kubectl kustomize "${PRODUCTION_APPS_DIR}" --load-restrictor=LoadRestrictionsNone >/dev/null

    if [[ -x "${LOCKSTEP_VERIFIER}" ]]; then
        "${LOCKSTEP_VERIFIER}"
    else
        phase4_warn "lockstep verifier is not executable yet: ${LOCKSTEP_VERIFIER}"
    fi

    if [[ "${skip_live_production_verifier}" == false ]]; then
        "${PRODUCTION_IMAGE_VERIFIER}"
    else
        phase4_warn "skipped live production verifier; run ${PRODUCTION_IMAGE_VERIFIER} before OCI apply"
    fi
}

main() {
    local release_manifest=""
    local old_release_version

    release_version=""
    skip_live_production_verifier=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release-version)
                release_version="${2:-}"
                shift
                ;;
            --release-manifest)
                release_manifest="${2:-}"
                shift
                ;;
            --transaction-service|--currency-service|--permission-service|--session-gateway|--budget-analyzer-web|--ext-authz)
                IMAGE_REFS["${1#--}"]="${2:-}"
                shift
                ;;
            --skip-live-production-verifier)
                skip_live_production_verifier=true
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

    [[ -f "${PRODUCTION_IMAGE_INVENTORY}" ]] || phase4_die "missing image inventory: ${PRODUCTION_IMAGE_INVENTORY}"
    [[ -f "${PRODUCTION_KUSTOMIZATION}" ]] || phase4_die "missing production kustomization: ${PRODUCTION_KUSTOMIZATION}"

    if [[ -n "${release_manifest}" ]]; then
        load_manifest "${release_manifest}"
    fi

    [[ -n "${release_version}" ]] || phase4_die "missing --release-version or release-version in manifest"
    old_release_version="$(inventory_value "release-version")"
    [[ -n "${old_release_version}" ]] || phase4_die "current production image inventory is missing release-version"

    validate_image_refs
    update_kustomization
    write_image_inventory
    update_release_version_references "${old_release_version}"
    verify_updates

    phase4_info "updated production release image baseline to ${release_version}"
    phase4_info "review the diff before tagging or deploying to OCI"
}

main "$@"
