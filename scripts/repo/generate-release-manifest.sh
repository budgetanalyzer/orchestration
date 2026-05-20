#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/repo/repo-config.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/repo-config.sh"

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

declare -A ARTIFACT_SOURCE_REPOS=(
    ["transaction-service"]="transaction-service"
    ["currency-service"]="currency-service"
    ["permission-service"]="permission-service"
    ["session-gateway"]="session-gateway"
    ["budget-analyzer-web"]="budget-analyzer-web"
    ["ext-authz"]="orchestration"
)

declare -A WORKFLOW_RUN_URLS=()

platform_changed=false
infrastructure_changed=false
secrets_changed=false
observability_changed=false
public_tls_reapply_required=false

usage() {
    cat <<'EOF'
Usage:
  ./scripts/repo/generate-release-manifest.sh 0.0.x \
    --workflow-run-url transaction-service=https://github.com/budgetanalyzer/transaction-service/actions/runs/<id> \
    --workflow-run-url currency-service=https://github.com/budgetanalyzer/currency-service/actions/runs/<id> \
    --workflow-run-url permission-service=https://github.com/budgetanalyzer/permission-service/actions/runs/<id> \
    --workflow-run-url session-gateway=https://github.com/budgetanalyzer/session-gateway/actions/runs/<id> \
    --workflow-run-url budget-analyzer-web=https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/<id> \
    --workflow-run-url ext-authz=https://github.com/budgetanalyzer/orchestration/actions/runs/<id>

Options:
  --release-version <version>            Release version as X.Y.Z or vX.Y.Z.
  --output <path>                        Output manifest path. Defaults to
                                         tmp/releases/v<version>.yaml.
  --workflow-run-url <artifact=url>      Required for each runtime artifact.
  --platform-changed                     Set phase_flags.platform_changed true.
  --infrastructure-changed               Set phase_flags.infrastructure_changed true.
  --secrets-changed                      Set phase_flags.secrets_changed true.
  --observability-changed                Set phase_flags.observability_changed true.
  --public-tls-reapply-required          Set phase_flags.public_tls_reapply_required true.
  --force                                Overwrite an existing output file.
  -h, --help                             Show this help.

The script resolves GHCR tag digests for the six runtime application images and
writes the release manifest consumed by:

  ./deploy/scripts/23-update-production-release-images.sh --release-manifest <path>

Docker Buildx is used first when available so existing docker login credentials
can access GHCR. If that is unavailable, the script falls back to the GHCR
registry API with curl. For private GHCR packages, set GHCR_USERNAME and
GHCR_TOKEN before using the curl fallback.
EOF
}

info() {
    printf '[release-manifest] %s\n' "$*"
}

die() {
    printf '[release-manifest] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name="$1"

    command -v "${command_name}" >/dev/null 2>&1 || die "required command not found: ${command_name}"
}

normalize_release_version() {
    local version="$1"

    version="${version#v}"
    [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
        die "release version must use X.Y.Z or vX.Y.Z format: ${version}"
    printf '%s\n' "${version}"
}

validate_digest() {
    local digest="$1"

    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]]
}

valid_workflow_run_url() {
    local url="$1"

    [[ "${url}" =~ ^https://github\.com/budgetanalyzer/[A-Za-z0-9_.-]+/actions/runs/[0-9]+(/.*)?$ ]]
}

service_exists() {
    local candidate="$1"
    local service

    for service in "${SERVICE_ORDER[@]}"; do
        if [[ "${service}" == "${candidate}" ]]; then
            return 0
        fi
    done

    return 1
}

repo_commit_sha() {
    local repo="$1"
    local repo_path="${PARENT_DIR}/${repo}"

    [[ -d "${repo_path}/.git" ]] || die "missing git repository: ../${repo}"
    git -C "${repo_path}" rev-parse HEAD
}

validate_required_workflow_urls() {
    local service url

    for service in "${SERVICE_ORDER[@]}"; do
        url="${WORKFLOW_RUN_URLS[${service}]:-}"
        [[ -n "${url}" ]] || die "missing --workflow-run-url ${service}=https://github.com/budgetanalyzer/.../actions/runs/<id>"
        valid_workflow_run_url "${url}" || die "invalid workflow run URL for ${service}: ${url}"
    done
}

parse_workflow_run_url() {
    local assignment="$1"
    local service="${assignment%%=*}"
    local url="${assignment#*=}"

    [[ "${assignment}" == *=* ]] || die "--workflow-run-url must use artifact=url form"
    service_exists "${service}" || die "unknown artifact for --workflow-run-url: ${service}"
    valid_workflow_run_url "${url}" || die "invalid workflow run URL for ${service}: ${url}"

    WORKFLOW_RUN_URLS["${service}"]="${url}"
}

docker_buildx_available() {
    command -v docker >/dev/null 2>&1 && docker buildx version >/dev/null 2>&1
}

resolve_digest_with_docker_buildx() {
    local image_ref="$1"
    local output
    local digest

    output="$(docker buildx imagetools inspect "${image_ref}" --format '{{.Manifest.Digest}}' 2>/dev/null || true)"
    if validate_digest "${output}"; then
        printf '%s\n' "${output}"
        return 0
    fi

    output="$(docker buildx imagetools inspect "${image_ref}" --format '{{.Digest}}' 2>/dev/null || true)"
    if validate_digest "${output}"; then
        printf '%s\n' "${output}"
        return 0
    fi

    output="$(docker buildx imagetools inspect "${image_ref}" 2>/dev/null || true)"
    digest="$(printf '%s\n' "${output}" | awk '$1 == "Digest:" {print $2; exit}')"
    if validate_digest "${digest}"; then
        printf '%s\n' "${digest}"
        return 0
    fi

    return 1
}

ghcr_bearer_token() {
    local repo="$1"
    local token_url
    local response
    local token
    local curl_args=()
    local username

    token_url="https://ghcr.io/token?service=ghcr.io&scope=repository:budgetanalyzer/${repo}:pull"

    if [[ -n "${GHCR_TOKEN:-}" ]]; then
        username="${GHCR_USERNAME:-${GITHUB_ACTOR:-}}"
        [[ -n "${username}" ]] || die "GHCR_TOKEN is set, but GHCR_USERNAME or GITHUB_ACTOR is not set"
        curl_args=(-u "${username}:${GHCR_TOKEN}")
    fi

    response="$(curl -fsSL "${curl_args[@]}" "${token_url}" 2>/dev/null || true)"
    token="$(printf '%s' "${response}" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [[ -n "${token}" ]] || return 1

    printf '%s\n' "${token}"
}

resolve_digest_with_ghcr_api() {
    local repo="$1"
    local version="$2"
    local token
    local manifest_url
    local accept_header
    local headers
    local digest

    require_command curl

    token="$(ghcr_bearer_token "${repo}")" || return 1
    manifest_url="https://ghcr.io/v2/budgetanalyzer/${repo}/manifests/${version}"
    accept_header="application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

    headers="$(
        curl -fsSL \
            -D - \
            -o /dev/null \
            -H "Authorization: Bearer ${token}" \
            -H "Accept: ${accept_header}" \
            "${manifest_url}" 2>/dev/null || true
    )"
    digest="$(printf '%s\n' "${headers}" | awk 'BEGIN {IGNORECASE = 1} /^Docker-Content-Digest:/ {gsub("\r", "", $2); print $2; exit}')"
    if validate_digest "${digest}"; then
        printf '%s\n' "${digest}"
        return 0
    fi

    return 1
}

resolve_digest() {
    local service="$1"
    local repo="$2"
    local version="$3"
    local image_ref="ghcr.io/budgetanalyzer/${repo}:${version}"
    local digest

    if docker_buildx_available; then
        digest="$(resolve_digest_with_docker_buildx "${image_ref}" || true)"
        if [[ -n "${digest}" ]]; then
            printf '%s\n' "${digest}"
            return 0
        fi
    fi

    digest="$(resolve_digest_with_ghcr_api "${repo}" "${version}" || true)"
    if [[ -n "${digest}" ]]; then
        printf '%s\n' "${digest}"
        return 0
    fi

    die "could not resolve digest for ${service} (${image_ref}); confirm the tag exists and your workstation can pull from GHCR"
}

write_manifest() {
    local output_path="$1"
    local version="$2"
    local temp_file="${output_path}.tmp"
    local service
    local repo
    local digest
    local image_ref
    local source_repo

    mkdir -p "$(dirname "${output_path}")"

    {
        printf 'release:\n'
        printf '  version: "v%s"\n' "${version}"
        printf '  image_tag: "%s"\n' "${version}"
        printf 'repositories:\n'
        # shellcheck disable=SC2153 # REPOS is defined by repo-config.sh.
        for repo in "${REPOS[@]}"; do
            printf '  %s:\n' "${repo}"
            printf '    commit: "%s"\n' "$(repo_commit_sha "${repo}")"
        done
        printf 'artifacts:\n'
        for service in "${SERVICE_ORDER[@]}"; do
            repo="${IMAGE_REPOS[${service}]}"
            source_repo="${ARTIFACT_SOURCE_REPOS[${service}]}"
            info "resolving ghcr.io/budgetanalyzer/${repo}:${version}" >&2
            digest="$(resolve_digest "${service}" "${repo}" "${version}")"
            image_ref="ghcr.io/budgetanalyzer/${repo}:${version}@${digest}"
            printf '  %s:\n' "${service}"
            printf '    source_repository: "%s"\n' "${source_repo}"
            printf '    workflow_run_url: "%s"\n' "${WORKFLOW_RUN_URLS[${service}]}"
            printf '    image: "%s"\n' "${image_ref}"
        done
        printf 'phase_flags:\n'
        printf '  platform_changed: %s\n' "${platform_changed}"
        printf '  infrastructure_changed: %s\n' "${infrastructure_changed}"
        printf '  secrets_changed: %s\n' "${secrets_changed}"
        printf '  observability_changed: %s\n' "${observability_changed}"
        printf '  public_tls_reapply_required: %s\n' "${public_tls_reapply_required}"
    } > "${temp_file}"

    mv "${temp_file}" "${output_path}"
}

main() {
    local release_version=""
    local output_path=""
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --release-version)
                release_version="${2:-}"
                [[ -n "${release_version}" ]] || die "missing value for --release-version"
                shift
                ;;
            --output)
                output_path="${2:-}"
                [[ -n "${output_path}" ]] || die "missing value for --output"
                shift
                ;;
            --workflow-run-url)
                parse_workflow_run_url "${2:-}"
                shift
                ;;
            --platform-changed)
                platform_changed=true
                ;;
            --infrastructure-changed)
                infrastructure_changed=true
                ;;
            --secrets-changed)
                secrets_changed=true
                ;;
            --observability-changed)
                observability_changed=true
                ;;
            --public-tls-reapply-required)
                public_tls_reapply_required=true
                ;;
            --force)
                force=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "unknown option: $1"
                ;;
            *)
                [[ -z "${release_version}" ]] || die "release version was provided more than once"
                release_version="$1"
                ;;
        esac
        shift
    done

    [[ -n "${release_version}" ]] || die "missing release version"
    release_version="$(normalize_release_version "${release_version}")"
    validate_required_workflow_urls

    if [[ -z "${output_path}" ]]; then
        output_path="${REPO_ROOT}/tmp/releases/v${release_version}.yaml"
    elif [[ "${output_path}" != /* ]]; then
        output_path="${REPO_ROOT}/${output_path}"
    fi

    if [[ -e "${output_path}" && "${force}" != true ]]; then
        die "output file already exists: ${output_path}; use --force to overwrite"
    fi

    write_manifest "${output_path}" "${release_version}"
    info "wrote ${output_path}"
}

main "$@"
