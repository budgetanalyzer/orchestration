#!/usr/bin/env bash
# Static verifier for the Phase 3 production image overlay.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAY_DIR="${REPO_DIR}/kubernetes/production/apps"
PRODUCTION_IMAGE_POLICY="${REPO_DIR}/kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml"
STATIC_TOOLS_DIR="${PHASE7_STATIC_TOOLS_DIR:-${REPO_DIR}/.cache/phase7-static-tools}"
STATIC_TOOLS_BIN="${STATIC_TOOLS_DIR}/bin"
RENDERED_FILE=""

# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
# shellcheck source=../lib/pinned-tool-versions.sh
. "${SCRIPT_DIR}/../lib/pinned-tool-versions.sh"

EXPECTED_IMAGE_REFS=(
    "ghcr.io/budgetanalyzer/transaction-service:0.0.12@sha256:835e31a29b73c41aaed7a5a4f70703921978b3f4effd1a770cf3d4d0ebf2d4d7"
    "ghcr.io/budgetanalyzer/currency-service:0.0.12@sha256:7315de56adc51d4887b3d51284c4291f22e520998e16cad43cf93527c1e3403f"
    "ghcr.io/budgetanalyzer/permission-service:0.0.12@sha256:d4b4e9c58a391a7bbb0e25bb64dfb6ed8fc69b8400f196f7d7b791735f5445a3"
    "ghcr.io/budgetanalyzer/session-gateway:0.0.12@sha256:0cd9a1af8bff10410125155bbad2c4db0e3d7312655f658e30a79ee5f2b4fbd7"
    "ghcr.io/budgetanalyzer/budget-analyzer-web:0.0.12@sha256:3299d088121fcfca8dc69f0d9de92944b311cc408ccbcb08e1bb5243523eb03e"
    "ghcr.io/budgetanalyzer/ext-authz:0.0.12@sha256:4a116b9d9598bb23551c6403570bef4310b8b812d1606d27b95a8b7e15d4196d"
)

LOCAL_IMAGE_REPOS=(
    "transaction-service"
    "currency-service"
    "permission-service"
    "session-gateway"
    "budget-analyzer-web"
    "budget-analyzer-web-prod-smoke"
    "ext-authz"
)

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

ensure_static_tool() {
    local tool version stamp installer

    tool="$1"
    version="$(phase7_tool_version "$tool")"
    stamp="${STATIC_TOOLS_DIR}/.${tool}-${version}.installed"
    installer="${REPO_DIR}/scripts/bootstrap/install-verified-tool.sh"

    mkdir -p "${STATIC_TOOLS_BIN}"

    if [[ -x "${STATIC_TOOLS_BIN}/${tool}" && -f "${stamp}" ]]; then
        return 0
    fi

    "${installer}" "${tool}" --install-dir "${STATIC_TOOLS_BIN}"
    rm -f "${STATIC_TOOLS_DIR}/.${tool}-"*.installed 2>/dev/null || true
    touch "${stamp}"
}

cleanup() {
    if [[ -n "${RENDERED_FILE}" ]]; then
        rm -f "${RENDERED_FILE}"
    fi
}

assert_not_contains() {
    local file pattern description

    file="$1"
    pattern="$2"
    description="$3"

    if grep -Eq "${pattern}" "${file}"; then
        fail "${description}"
    fi
}

assert_contains_literal() {
    local file needle description

    file="$1"
    needle="$2"
    description="$3"

    if ! grep -Fq "${needle}" "${file}"; then
        fail "${description}"
    fi
}

main() {
    local image repo

    require_command kubectl
    ensure_static_tool kyverno

    [[ -d "${OVERLAY_DIR}" ]] || fail "production overlay directory not found: ${OVERLAY_DIR}"
    [[ -f "${PRODUCTION_IMAGE_POLICY}" ]] || fail "production image policy not found: ${PRODUCTION_IMAGE_POLICY}"

    RENDERED_FILE="$(mktemp)"
    trap cleanup EXIT

    kubectl kustomize "${OVERLAY_DIR}" --load-restrictor=LoadRestrictionsNone > "${RENDERED_FILE}"

    for image in "${EXPECTED_IMAGE_REFS[@]}"; do
        assert_contains_literal "${RENDERED_FILE}" "${image}" "expected production image ref is missing from rendered overlay: ${image}"
    done

    while IFS= read -r image; do
        [[ -n "${image}" ]] || continue
        if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            fail "rendered image is not digest-pinned: ${image}"
        fi
    done < <(sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "${RENDERED_FILE}")

    assert_not_contains "${RENDERED_FILE}" ':[[:alnum:]._-]*latest([[:space:]"]|$)' "rendered production overlay contains a :latest image ref"
    assert_not_contains "${RENDERED_FILE}" ':tilt-[a-f0-9]{16}([[:space:]"]|$)' "rendered production overlay contains a Tilt image ref"
    assert_not_contains "${RENDERED_FILE}" 'imagePullPolicy:[[:space:]]*Never' "rendered production overlay contains imagePullPolicy: Never"
    assert_not_contains "${RENDERED_FILE}" 'budget-analyzer-web-prod-smoke' "rendered production overlay contains the local production-smoke image path"

    for repo in "${LOCAL_IMAGE_REPOS[@]}"; do
        assert_not_contains "${RENDERED_FILE}" "image:[[:space:]]*(docker\\.io/library/)?${repo}:" \
            "rendered production overlay contains unqualified local image repo: ${repo}"
    done

    assert_not_contains "${OVERLAY_DIR}/kustomization.yaml" 'nginx/nginx\.k8s\.conf' \
        "production overlay references the local NGINX config instead of nginx.production.k8s.conf"
    assert_not_contains "${PRODUCTION_IMAGE_POLICY}" 'budget-analyzer-web-prod-smoke|tilt-[a-f0-9]|\(latest\|tilt|:latest|approved local' \
        "production image policy contains local Tilt image exception text"

    "${STATIC_TOOLS_BIN}/kyverno" apply "${PRODUCTION_IMAGE_POLICY}" \
        --resource "${RENDERED_FILE}" \
        --remove-color >/dev/null

    printf 'Production image overlay verification passed: %s\n' "${OVERLAY_DIR}"
}

main "$@"
