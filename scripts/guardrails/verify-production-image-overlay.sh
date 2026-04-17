#!/usr/bin/env bash
# Static verifier for the Phase 6 production render baseline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OVERLAY_DIR="${REPO_DIR}/kubernetes/production/apps"
REDIS_OVERLAY_DIR="${REPO_DIR}/kubernetes/production/infrastructure/redis"
PRODUCTION_IMAGE_POLICY="${REPO_DIR}/kubernetes/kyverno/policies/production/50-require-third-party-image-digests.yaml"
STATIC_TOOLS_DIR="${PHASE7_STATIC_TOOLS_DIR:-${REPO_DIR}/.cache/phase7-static-tools}"
STATIC_TOOLS_BIN="${STATIC_TOOLS_DIR}/bin"
LOCKED_DEMO_DOMAIN="demo.budgetanalyzer.org"
LOCKED_GRAFANA_DOMAIN="grafana.budgetanalyzer.org"
LOCKED_AUTH0_ISSUER_URI="https://auth.budgetanalyzer.org/"
TEMP_DIR=""
RENDERED_APPS_FILE=""
RENDERED_REDIS_FILE=""
PHASE6_RENDER_DIR=""
INSTANCE_ENV_FILE_TMP=""

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
    if [[ -n "${TEMP_DIR}" ]]; then
        rm -rf "${TEMP_DIR}"
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

render_kustomize() {
    local overlay_dir output_file

    overlay_dir="$1"
    output_file="$2"

    [[ -d "${overlay_dir}" ]] || fail "overlay directory not found: ${overlay_dir}"
    kubectl kustomize "${overlay_dir}" --load-restrictor=LoadRestrictionsNone > "${output_file}"
}

assert_no_phase6_forbidden_patterns() {
    local file

    file="$1"

    assert_not_contains "${file}" ':[[:alnum:]._-]*latest([[:space:]"]|$)' "Phase 6 production artifact contains a :latest ref: ${file}"
    assert_not_contains "${file}" ':tilt-[a-f0-9]{16}([[:space:]"]|$)' "Phase 6 production artifact contains a Tilt image ref: ${file}"
    assert_not_contains "${file}" 'imagePullPolicy:[[:space:]]*Never' "Phase 6 production artifact contains imagePullPolicy: Never: ${file}"
    assert_not_contains "${file}" 'budgetanalyzer\.localhost' "Phase 6 production artifact contains a localhost hostname: ${file}"
    assert_not_contains "${file}" 'auth0-issuer\.placeholder\.invalid' "Phase 6 production artifact contains the placeholder Auth0 issuer host: ${file}"
}

create_temp_instance_env() {
    INSTANCE_ENV_FILE_TMP="${TEMP_DIR}/instance.env"
    cat > "${INSTANCE_ENV_FILE_TMP}" <<EOF
DEMO_DOMAIN=${LOCKED_DEMO_DOMAIN}
GRAFANA_DOMAIN=${LOCKED_GRAFANA_DOMAIN}
AUTH0_ISSUER_URI=${LOCKED_AUTH0_ISSUER_URI}
EOF
}

verify_apps_overlay() {
    local image repo

    for image in "${EXPECTED_IMAGE_REFS[@]}"; do
        assert_contains_literal "${RENDERED_APPS_FILE}" "${image}" "expected production image ref is missing from rendered overlay: ${image}"
    done

    while IFS= read -r image; do
        [[ -n "${image}" ]] || continue
        if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            fail "rendered image is not digest-pinned: ${image}"
        fi
    done < <(sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "${RENDERED_APPS_FILE}")

    assert_no_phase6_forbidden_patterns "${RENDERED_APPS_FILE}"
    assert_not_contains "${RENDERED_APPS_FILE}" 'budget-analyzer-web-prod-smoke' "rendered production overlay contains the local production-smoke image path"

    for repo in "${LOCAL_IMAGE_REPOS[@]}"; do
        assert_not_contains "${RENDERED_APPS_FILE}" "image:[[:space:]]*(docker\\.io/library/)?${repo}:" \
            "rendered production overlay contains unqualified local image repo: ${repo}"
    done

    assert_not_contains "${OVERLAY_DIR}/kustomization.yaml" 'nginx/nginx\.k8s\.conf' \
        "production overlay references the local NGINX config instead of nginx.production.k8s.conf"
    assert_not_contains "${PRODUCTION_IMAGE_POLICY}" 'budget-analyzer-web-prod-smoke|tilt-[a-f0-9]|\(latest\|tilt|:latest|approved local' \
        "production image policy contains local Tilt image exception text"

    assert_contains_literal "${RENDERED_APPS_FILE}" 'name: nginx-gateway-config' "rendered production overlay is missing the production nginx-gateway-config ConfigMap"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'name: nginx-gateway-docs' "rendered production overlay is missing the production nginx-gateway-docs ConfigMap"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'location = /api-docs {' "rendered production nginx config is missing the /api-docs route"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'location = /login {' "rendered production nginx config is missing the /login route"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'location = / {' "rendered production nginx config is missing the root route"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'location = /@vite/client {' "rendered production nginx config is missing the explicit Vite deny route"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'location = /_prod-smoke {' "rendered production nginx config is missing the explicit prod-smoke deny route"
    assert_contains_literal "${RENDERED_APPS_FILE}" 'https://demo.budgetanalyzer.org/api' "rendered production docs bundle is missing the production API server URL"

    "${STATIC_TOOLS_BIN}/kyverno" apply "${PRODUCTION_IMAGE_POLICY}" \
        --resource "${RENDERED_APPS_FILE}" \
        --remove-color >/dev/null
}

verify_phase6_render_outputs() {
    local gateway_file ingress_file monitoring_file egress_file

    gateway_file="${PHASE6_RENDER_DIR}/gateway-routes.yaml"
    ingress_file="${PHASE6_RENDER_DIR}/istio-ingress-policies.yaml"
    monitoring_file="${PHASE6_RENDER_DIR}/prometheus-stack-values.override.yaml"
    egress_file="${PHASE6_RENDER_DIR}/istio-egress.yaml"

    [[ -f "${gateway_file}" ]] || fail "Phase 6 render output is missing gateway-routes.yaml"
    [[ -f "${ingress_file}" ]] || fail "Phase 6 render output is missing istio-ingress-policies.yaml"
    [[ -f "${monitoring_file}" ]] || fail "Phase 6 render output is missing prometheus-stack-values.override.yaml"
    [[ -f "${egress_file}" ]] || fail "Phase 6 render output is missing istio-egress.yaml"

    assert_no_phase6_forbidden_patterns "${gateway_file}"
    assert_no_phase6_forbidden_patterns "${ingress_file}"
    assert_no_phase6_forbidden_patterns "${monitoring_file}"
    assert_no_phase6_forbidden_patterns "${egress_file}"

    assert_contains_literal "${gateway_file}" 'name: app-route' "rendered gateway routes are missing app-route"
    assert_contains_literal "${gateway_file}" 'name: api-route' "rendered gateway routes are missing api-route"
    assert_contains_literal "${gateway_file}" 'name: auth-route' "rendered gateway routes are missing auth-route"
    assert_contains_literal "${gateway_file}" 'name: grafana-route' "rendered gateway routes are missing grafana-route"
    assert_contains_literal "${gateway_file}" "${LOCKED_DEMO_DOMAIN}" "rendered gateway routes are missing the production demo hostname"
    assert_contains_literal "${gateway_file}" "${LOCKED_GRAFANA_DOMAIN}" "rendered gateway routes are missing the production Grafana hostname"
    assert_contains_literal "${gateway_file}" 'value: /auth' "rendered auth route is missing the /auth path prefix"
    assert_contains_literal "${gateway_file}" 'value: /oauth2' "rendered auth route is missing the /oauth2 path prefix"
    assert_contains_literal "${gateway_file}" 'value: /login/oauth2' "rendered auth route is missing the /login/oauth2 path prefix"
    assert_contains_literal "${gateway_file}" 'value: /logout' "rendered auth route is missing the /logout path prefix"

    assert_contains_literal "${ingress_file}" 'name: ext-authz-at-ingress' "rendered ingress policies are missing ext-authz-at-ingress"
    assert_contains_literal "${ingress_file}" 'name: ingress-auth-local-rate-limit' "rendered ingress policies are missing ingress-auth-local-rate-limit"
    assert_contains_literal "${ingress_file}" "${LOCKED_DEMO_DOMAIN}" "rendered ingress policies are missing the production demo hostname"

    assert_contains_literal "${monitoring_file}" 'domain: grafana.budgetanalyzer.org' "rendered monitoring override is missing the production Grafana domain"
    assert_contains_literal "${monitoring_file}" 'root_url: https://grafana.budgetanalyzer.org' "rendered monitoring override is missing the production Grafana root_url"
    assert_contains_literal "${monitoring_file}" 'prometheus-stack-grafana' "rendered monitoring override no longer documents the expected Grafana Service contract"

    assert_contains_literal "${egress_file}" 'name: auth0-idp' "rendered Istio egress output is missing the Auth0 ServiceEntry"
    assert_contains_literal "${egress_file}" 'auth.budgetanalyzer.org' "rendered Istio egress output is missing the production Auth0 host"
    assert_contains_literal "${egress_file}" 'api.stlouisfed.org' "rendered Istio egress output is missing the FRED host"
    assert_contains_literal "${egress_file}" 'name: auth0-via-egress' "rendered Istio egress output is missing the Auth0 VirtualService"
}

verify_redis_overlay() {
    assert_no_phase6_forbidden_patterns "${RENDERED_REDIS_FILE}"
    assert_contains_literal "${RENDERED_REDIS_FILE}" 'name: redis-acl-bootstrap' "rendered production Redis overlay is missing the redis-acl-bootstrap ConfigMap"
    assert_contains_literal "${RENDERED_REDIS_FILE}" 'kind: PersistentVolumeClaim' "rendered production Redis overlay is missing the PersistentVolumeClaim"
    assert_contains_literal "${RENDERED_REDIS_FILE}" 'name: redis-data' "rendered production Redis overlay is missing the redis-data volume/PVC name"
    assert_contains_literal "${RENDERED_REDIS_FILE}" 'claimName: redis-data' "rendered production Redis overlay does not mount redis-data from a PersistentVolumeClaim"
    assert_contains_literal "${RENDERED_REDIS_FILE}" 'storage: 5Gi' "rendered production Redis overlay is missing the expected 5Gi PVC request"
}

render_phase6_manifests() {
    create_temp_instance_env
    PHASE6_RENDER_DIR="${TEMP_DIR}/phase-6"

    INSTANCE_ENV_FILE="${INSTANCE_ENV_FILE_TMP}" \
        "${REPO_DIR}/deploy/scripts/13-render-phase-6-production-manifests.sh" \
        --output-dir "${PHASE6_RENDER_DIR}" >/dev/null
}

main() {
    require_command kubectl
    ensure_static_tool kyverno

    [[ -d "${OVERLAY_DIR}" ]] || fail "production overlay directory not found: ${OVERLAY_DIR}"
    [[ -d "${REDIS_OVERLAY_DIR}" ]] || fail "production Redis overlay directory not found: ${REDIS_OVERLAY_DIR}"
    [[ -f "${PRODUCTION_IMAGE_POLICY}" ]] || fail "production image policy not found: ${PRODUCTION_IMAGE_POLICY}"

    TEMP_DIR="$(mktemp -d)"
    RENDERED_APPS_FILE="${TEMP_DIR}/apps.yaml"
    RENDERED_REDIS_FILE="${TEMP_DIR}/redis.yaml"
    trap cleanup EXIT

    render_kustomize "${OVERLAY_DIR}" "${RENDERED_APPS_FILE}"
    render_kustomize "${REDIS_OVERLAY_DIR}" "${RENDERED_REDIS_FILE}"
    render_phase6_manifests

    verify_apps_overlay
    verify_phase6_render_outputs
    verify_redis_overlay

    printf 'Phase 6 production verification passed: %s, %s, %s\n' \
        "${OVERLAY_DIR}" "${PHASE6_RENDER_DIR}" "${REDIS_OVERLAY_DIR}"
}

main "$@"
