#!/usr/bin/env bash

# check-phase-7-image-pinning.sh
#
# Static verification for Phase 7 Session 2 image pinning. This is scoped to
# orchestration-owned active assets plus the retained DinD test assets frozen by
# the Phase 7 Session 1 contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TARGET_FILES=(
    "kind-cluster-config.yaml"
    "kubernetes/infrastructure/postgresql/statefulset.yaml"
    "kubernetes/infrastructure/redis/deployment.yaml"
    "kubernetes/infrastructure/rabbitmq/statefulset.yaml"
    "kubernetes/services/budget-analyzer-web/deployment.yaml"
    "kubernetes/services/currency-service/deployment.yaml"
    "kubernetes/services/ext-authz/deployment.yaml"
    "kubernetes/services/nginx-gateway/deployment.yaml"
    "kubernetes/services/permission-service/deployment.yaml"
    "kubernetes/services/session-gateway/deployment.yaml"
    "kubernetes/services/transaction-service/deployment.yaml"
    "Tiltfile"
    "ext-authz/Dockerfile"
    "tests/setup-flow/kind-cluster-test-config.yaml"
    "tests/shared/Dockerfile.test-env"
    "tests/setup-flow/docker-compose.test.yml"
    "tests/security-preflight/docker-compose.test.yml"
    "scripts/dev/verify-security-prereqs.sh"
    "scripts/dev/verify-phase-2-network-policies.sh"
    "scripts/dev/verify-phase-3-istio-ingress.sh"
    "scripts/dev/verify-phase-4-transport-encryption.sh"
    "scripts/dev/verify-phase-5-runtime-hardening.sh"
    "scripts/dev/verify-phase-6-edge-browser-hardening.sh"
    "scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh"
)

ALLOWED_LATEST_REFS=(
    "transaction-service:latest"
    "currency-service:latest"
    "permission-service:latest"
    "session-gateway:latest"
    "ext-authz:latest"
    "budget-analyzer-web:latest"
    "budget-analyzer-web-prod-smoke:latest"
)

declare -A ALLOWED_LATEST=()
for ref in "${ALLOWED_LATEST_REFS[@]}"; do
    ALLOWED_LATEST["$ref"]=1
done

extract_refs() {
    rg -n --no-heading '^[[:space:]]*image:[[:space:]]*|^[[:space:]]*FROM[[:space:]]+|^[A-Z0-9_]+IMAGE=' "${TARGET_FILES[@]}" |
        while IFS= read -r match; do
            local file="${match%%:*}"
            local remainder="${match#*:}"
            local line="${remainder%%:*}"
            local text="${remainder#*:}"
            local ref=""

            if [[ "$text" =~ ^[[:space:]]*image:[[:space:]]* ]]; then
                ref="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*image:[[:space:]]*([^[:space:]]+).*/\1/')"
            elif [[ "$text" =~ ^[[:space:]]*FROM[[:space:]]+ ]]; then
                ref="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*FROM[[:space:]]+([^[:space:]]+).*/\1/')"
            else
                ref="$(printf '%s' "$text" | sed -E 's/^[A-Z0-9_]+IMAGE="?([^"[:space:]]+)"?.*/\1/')"
            fi

            printf '%s\t%s\t%s\n' "$file" "$line" "$ref"
        done
}

main() {
    cd "${REPO_DIR}"

    local refs_checked=0
    local -a failures=()

    while IFS=$'\t' read -r file line ref; do
        [[ -n "${ref}" ]] || continue
        refs_checked=$((refs_checked + 1))

        if [[ "${ref}" == \$\{* ]]; then
            continue
        fi

        if [[ -n "${ALLOWED_LATEST[$ref]:-}" ]]; then
            continue
        fi

        if [[ "${ref}" == *":latest"* ]]; then
            failures+=("${file}:${line}: unexpected :latest image ref: ${ref}")
            continue
        fi

        if [[ "${ref}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            continue
        fi

        failures+=("${file}:${line}: missing @sha256 digest: ${ref}")
    done < <(extract_refs)

    if (( refs_checked == 0 )); then
        printf 'ERROR: no image references were discovered in the Phase 7 target set\n' >&2
        exit 1
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Phase 7 image pinning check failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        exit 1
    fi

    printf 'Phase 7 image pinning check passed (%d refs checked)\n' "${refs_checked}"
}

main "$@"
