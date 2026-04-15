#!/usr/bin/env bash
# Static Phase 7 guardrail gate for checked-in manifests, policy fixtures, and
# active setup guidance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATIC_TOOLS_DIR="${PHASE7_STATIC_TOOLS_DIR:-${REPO_DIR}/.cache/phase7-static-tools}"
STATIC_TOOLS_BIN="${STATIC_TOOLS_DIR}/bin"
KUBELINTER_CONFIG="${REPO_DIR}/.kube-linter.yaml"
IMAGE_PINNING_SCRIPT="${REPO_DIR}/scripts/guardrails/check-phase-7-image-pinning.sh"
SECRETS_ONLY_SCRIPT="${REPO_DIR}/scripts/guardrails/check-secrets-only-handling.sh"

# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
# shellcheck source=../lib/pinned-tool-versions.sh
. "${SCRIPT_DIR}/../lib/pinned-tool-versions.sh"

KUBECONFORM_ALLOWED_MISSING_KINDS=(
    AuthorizationPolicy
    ClusterPolicy
    DestinationRule
    EnvoyFilter
    Gateway
    HTTPRoute
    Kustomization
    PeerAuthentication
    ReferenceGrant
    ServiceEntry
    ServiceMonitor
    Test
    VirtualService
)

ACTIVE_GUIDANCE_PATHS=(
    "${REPO_DIR}/AGENTS.md"
    "${REPO_DIR}/README.md"
    "${REPO_DIR}/docs/development"
    "${REPO_DIR}/docs/tilt-kind-setup-guide.md"
    "${REPO_DIR}/scripts/README.md"
    "${REPO_DIR}/scripts/bootstrap"
    "${REPO_DIR}/scripts/ops"
    "${REPO_DIR}/scripts/guardrails"
    "${REPO_DIR}/scripts/smoketest"
    "${REPO_DIR}/scripts/loadtest"
    "${REPO_DIR}/scripts/repo"
    "${REPO_DIR}/scripts/lib"
    "${REPO_DIR}/setup.sh"
    "${REPO_DIR}/tests/shared/Dockerfile.test-env"
)

ACTIVE_NAMESPACE_MANIFESTS=(
    "${REPO_DIR}/kubernetes/infrastructure/namespace.yaml"
    "${REPO_DIR}/kubernetes/istio/egress-namespace.yaml"
    "${REPO_DIR}/kubernetes/istio/ingress-namespace.yaml"
)

usage() {
    cat <<'EOF'
Usage: scripts/guardrails/verify-phase-7-static-manifests.sh [--self-test]

Runs the Phase 7 static guardrail suite:
- kubeconform schema validation for checked-in manifests
- kube-linter with the repo-specific security baseline
- Kyverno CLI tests for the admission fixtures
- generated Kyverno replay for representative approved local Tilt deploy refs
- Tilt secret/config boundary inventory validation
- pattern scans for image pinning, namespace PSA labels, and pipe-to-shell guidance

Use --self-test to assert that the intentional failing fixtures are rejected.
EOF
}

log_step() {
    printf '\n==> %s\n' "$1"
}

remove_stale_stamps() {
    local tool

    tool="$1"
    rm -f "${STATIC_TOOLS_DIR}/.${tool}-"*.installed 2>/dev/null || true
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

    log_step "Installing pinned ${tool} ${version} into ${STATIC_TOOLS_BIN}"
    "${installer}" "${tool}" --install-dir "${STATIC_TOOLS_BIN}"
    remove_stale_stamps "${tool}"
    touch "${stamp}"
}

collect_schema_manifest_files() {
    find "${REPO_DIR}/kubernetes" -type f \( -name '*.yaml' -o -name '*.yml' \) \
        ! -name '*values.yaml' \
        | sort
}

kind_is_allowed_missing_schema() {
    local kind

    kind="$1"
    for allowed_kind in "${KUBECONFORM_ALLOWED_MISSING_KINDS[@]}"; do
        if [[ "${allowed_kind}" == "${kind}" ]]; then
            return 0
        fi
    done

    return 1
}

run_kubeconform() {
    local output_file
    local summary_line=""
    local kubeconform_rc=0
    local -a manifest_files=()
    local -a unexpected_lines=()
    local -a missing_kind_lines=()
    local line

    while IFS= read -r line; do
        manifest_files+=("${line}")
    done < <(collect_schema_manifest_files)

    if (( ${#manifest_files[@]} == 0 )); then
        echo "ERROR: no manifest files found for kubeconform" >&2
        exit 1
    fi

    output_file="$(mktemp)"
    if "${STATIC_TOOLS_BIN}/kubeconform" -strict -summary "${manifest_files[@]}" >"${output_file}" 2>&1; then
        :
    else
        kubeconform_rc=$?
    fi

    while IFS= read -r line; do
        if [[ "${line}" == Summary:* ]]; then
            summary_line="${line}"
            continue
        fi

        if [[ "${line}" == *"could not find schema for "* ]]; then
            local missing_kind="${line##*could not find schema for }"
            if kind_is_allowed_missing_schema "${missing_kind}"; then
                missing_kind_lines+=("${missing_kind}")
                continue
            fi
        fi

        if [[ -n "${line}" ]]; then
            unexpected_lines+=("${line}")
        fi
    done < "${output_file}"

    rm -f "${output_file}"

    if (( ${#unexpected_lines[@]} > 0 )); then
        printf 'kubeconform reported unexpected validation errors:\n' >&2
        printf '  - %s\n' "${unexpected_lines[@]}" >&2
        exit 1
    fi

    if (( kubeconform_rc != 0 && ${#missing_kind_lines[@]} == 0 )); then
        echo "kubeconform failed without a recognized schema-gap exception" >&2
        exit "${kubeconform_rc}"
    fi

    if [[ -n "${summary_line}" ]]; then
        printf '%s\n' "${summary_line}"
    fi

    if (( ${#missing_kind_lines[@]} > 0 )); then
        printf 'Allowed kubeconform schema gaps: %s\n' \
            "$(printf '%s\n' "${missing_kind_lines[@]}" | sort -u | awk 'BEGIN { first = 1 } { if (!first) { printf ", " } printf "%s", $0; first = 0 } END { printf "\n" }' | tr -d '\n')"
    fi
}

run_kube_linter() {
    "${STATIC_TOOLS_BIN}/kube-linter" lint "${REPO_DIR}/kubernetes" \
        --config "${KUBELINTER_CONFIG}" \
        --ignore-paths 'kubernetes/kyverno/tests/**' \
        --ignore-paths 'kubernetes/placeholders/**' \
        --format plain
}

run_kyverno_tests() {
    "${STATIC_TOOLS_BIN}/kyverno" test "${REPO_DIR}/kubernetes/kyverno/tests"
}

run_generated_tilt_local_image_replay() {
    local temp_dir resources_file test_file
    local canonical_repo=""
    local safe_name
    local repo
    local tilt_hash="0123456789abcdef"
    local -a repos=()

    mapfile -t repos < <("${IMAGE_PINNING_SCRIPT}" --print-approved-local-repos)
    if (( ${#repos[@]} == 0 )); then
        echo "ERROR: no approved local repos were returned for the Tilt local-image replay" >&2
        exit 1
    fi

    temp_dir="$(mktemp -d)"
    resources_file="${temp_dir}/workloads.yaml"
    test_file="${temp_dir}/kyverno-test.yaml"

    for repo in "${repos[@]}"; do
        if [[ "${repo}" == "ext-authz" ]]; then
            canonical_repo="${repo}"
            break
        fi
    done
    if [[ -z "${canonical_repo}" ]]; then
        canonical_repo="${repos[0]}"
    fi

    : > "${resources_file}"
    : > "${test_file}"

    for repo in "${repos[@]}"; do
        safe_name="${repo//./-}"
        safe_name="${safe_name//_/-}"

        cat >> "${resources_file}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: replay-${safe_name}-tilt-ref
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: replay-${safe_name}-tilt-ref
  template:
    metadata:
      labels:
        app: replay-${safe_name}-tilt-ref
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: ${repo}:tilt-${tilt_hash}
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "sleep 3600"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            runAsUser: 65534
---
EOF
    done

    cat >> "${resources_file}" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: replay-docker-library-local-ref
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: replay-docker-library-local-ref
  template:
    metadata:
      labels:
        app: replay-docker-library-local-ref
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: docker.io/library/${canonical_repo}:tilt-${tilt_hash}
          imagePullPolicy: IfNotPresent
          command: ["sh", "-c", "sleep 3600"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            runAsUser: 65534
---
EOF

    if printf '%s\n' "${repos[@]}" | grep -Fxq 'budget-analyzer-web-prod-smoke'; then
        cat >> "${resources_file}" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: replay-local-smoke-init-ref
  namespace: default
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  initContainers:
    - name: web-prod-smoke-assets
      image: docker.io/library/budget-analyzer-web-prod-smoke:tilt-0123456789abcdef
      imagePullPolicy: IfNotPresent
      command: ["sh", "-c", "true"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
  containers:
    - name: app
      image: busybox:1.36.1@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
---
EOF
    fi

    cat >> "${resources_file}" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: replay-unapproved-local-ref
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: replay-unapproved-local-ref
  template:
    metadata:
      labels:
        app: replay-unapproved-local-ref
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          image: rogue-local-service:tilt-0123456789abcdef
          imagePullPolicy: Never
          command: ["sh", "-c", "sleep 3600"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            runAsUser: 65534
EOF

    cat >> "${test_file}" <<EOF
apiVersion: cli.kyverno.io/v1alpha1
kind: Test
metadata:
  name: phase7-generated-local-image-replay
policies:
  - ${REPO_DIR}/kubernetes/kyverno/policies/50-require-third-party-image-digests.yaml
resources:
  - workloads.yaml
results:
EOF

    for repo in "${repos[@]}"; do
        safe_name="${repo//./-}"
        safe_name="${safe_name//_/-}"
        cat >> "${test_file}" <<EOF
  - policy: phase7-require-third-party-image-digests
    rule: require-digest-or-approved-local-image
    resources:
      - default/replay-${safe_name}-tilt-ref
    kind: Deployment
    result: pass
  - policy: phase7-require-third-party-image-digests
    rule: require-image-pull-policy-for-approved-local-tilt-image
    resources:
      - default/replay-${safe_name}-tilt-ref
    kind: Deployment
    result: pass
EOF
    done

    cat >> "${test_file}" <<EOF
  - policy: phase7-require-third-party-image-digests
    rule: require-digest-or-approved-local-image
    resources:
      - default/replay-docker-library-local-ref
    kind: Deployment
    result: pass
  - policy: phase7-require-third-party-image-digests
    rule: require-image-pull-policy-for-approved-local-tilt-image
    resources:
      - default/replay-docker-library-local-ref
    kind: Deployment
    result: pass
EOF

    if printf '%s\n' "${repos[@]}" | grep -Fxq 'budget-analyzer-web-prod-smoke'; then
        cat >> "${test_file}" <<'EOF'
  - policy: phase7-require-third-party-image-digests
    rule: require-digest-or-approved-local-image
    resources:
      - default/replay-local-smoke-init-ref
    kind: Pod
    result: pass
  - policy: phase7-require-third-party-image-digests
    rule: require-image-pull-policy-for-approved-local-tilt-image
    resources:
      - default/replay-local-smoke-init-ref
    kind: Pod
    result: pass
EOF
    fi

    cat >> "${test_file}" <<'EOF'
  - policy: phase7-require-third-party-image-digests
    rule: require-digest-or-approved-local-image
    resources:
      - default/replay-unapproved-local-ref
    kind: Deployment
    result: fail
EOF

    "${STATIC_TOOLS_BIN}/kyverno" test "${temp_dir}"
    rm -rf "${temp_dir}"
}

scan_namespace_psa_labels_in_files() {
    local label
    local subject="${1}"
    shift
    local -a files=("$@")
    local -a failures=()
    local required_labels=(
        'pod-security.kubernetes.io/enforce:'
        'pod-security.kubernetes.io/enforce-version:'
        'pod-security.kubernetes.io/warn:'
        'pod-security.kubernetes.io/warn-version:'
        'pod-security.kubernetes.io/audit:'
        'pod-security.kubernetes.io/audit-version:'
    )

    for file in "${files[@]}"; do
        [[ -f "${file}" ]] || continue
        if ! grep -Eq '^kind:[[:space:]]*Namespace([[:space:]]|$)' "${file}"; then
            continue
        fi

        for label in "${required_labels[@]}"; do
            if ! grep -Fq "${label}" "${file}"; then
                failures+=("${file#"${REPO_DIR}"/}: missing ${label}")
            fi
        done
    done

    if (( ${#failures[@]} > 0 )); then
        printf '%s namespace PSA label scan failed:\n' "${subject}" >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf '%s namespace PSA label scan passed\n' "${subject}"
}

scan_pipe_to_shell_guidance() {
    local subject="${1}"
    shift
    local -a paths=("$@")
    local -a matches=()
    local line
    local pattern='(curl|wget)[^|[:cntrl:]]*\|[[:space:]]*(bash|sh)|stable\.txt|latest\?for='

    while IFS= read -r line; do
        matches+=("${line}")
    done < <(search_guidance_paths "${pattern}" "${paths[@]}")

    if (( ${#matches[@]} > 0 )); then
        printf '%s pipe-to-shell guidance scan failed:\n' "${subject}" >&2
        printf '  - %s\n' "${matches[@]}" >&2
        return 1
    fi

    printf '%s pipe-to-shell guidance scan passed\n' "${subject}"
}

extract_image_refs_from_files() {
    local -a files=("$@")
    local match file remainder line text ref

    if (( ${#files[@]} == 0 )); then
        return 0
    fi

    search_image_refs_in_files "${files[@]}" |
        while IFS= read -r match; do
            file="${match%%:*}"
            remainder="${match#*:}"
            line="${remainder%%:*}"
            text="${remainder#*:}"
            ref=""

            if [[ "${text}" =~ ^[[:space:]]*image:[[:space:]]* ]]; then
                ref="$(printf '%s' "${text}" | sed -E 's/^[[:space:]]*image:[[:space:]]*([^[:space:]]+).*/\1/')"
            elif [[ "${text}" =~ ^[[:space:]]*FROM[[:space:]]+ ]]; then
                ref="$(printf '%s' "${text}" | sed -E 's/^[[:space:]]*FROM[[:space:]]+([^[:space:]]+).*/\1/')"
            else
                ref="$(printf '%s' "${text}" | sed -E 's/^[A-Z0-9_]+IMAGE="?([^"[:space:]]+)"?.*/\1/')"
            fi

            printf '%s\t%s\t%s\n' "${file}" "${line}" "${ref}"
        done
}

search_guidance_paths() {
    local pattern="$1"
    shift

    if command -v rg >/dev/null 2>&1; then
        rg -n "${pattern}" "$@" 2>/dev/null || true
        return 0
    fi

    grep -R -n -E --binary-files=without-match "${pattern}" "$@" 2>/dev/null || true
}

search_image_refs_in_files() {
    local pattern='^[[:space:]]*image:[[:space:]]*|^[[:space:]]*FROM[[:space:]]+|^[A-Z0-9_]+IMAGE='

    if command -v rg >/dev/null 2>&1; then
        rg -n --no-heading "${pattern}" "$@" || true
        return 0
    fi

    grep -nH -E --binary-files=without-match "${pattern}" "$@" || true
}

scan_image_pinning_in_files() {
    local subject="${1}"
    shift
    local -a files=("$@")
    local refs_checked=0
    local -a failures=()
    local file line ref

    while IFS=$'\t' read -r file line ref; do
        [[ -n "${ref}" ]] || continue
        refs_checked=$((refs_checked + 1))

        if [[ "${ref}" == \$\{* ]]; then
            continue
        fi

        if [[ "${ref}" == *":latest"* ]]; then
            failures+=("${file#"${REPO_DIR}"/}:${line}: unexpected :latest image ref: ${ref}")
            continue
        fi

        if [[ "${ref}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            continue
        fi

        failures+=("${file#"${REPO_DIR}"/}:${line}: missing @sha256 digest: ${ref}")
    done < <(extract_image_refs_from_files "${files[@]}")

    if (( refs_checked == 0 )); then
        echo "${subject} image pinning self-test found no image references" >&2
        return 1
    fi

    if (( ${#failures[@]} > 0 )); then
        printf '%s image pinning scan failed:\n' "${subject}" >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf '%s image pinning scan passed (%d refs checked)\n' "${subject}" "${refs_checked}"
}

run_repo_pattern_scans() {
    "${IMAGE_PINNING_SCRIPT}"
    scan_namespace_psa_labels_in_files "repo" "${ACTIVE_NAMESPACE_MANIFESTS[@]}"
    scan_pipe_to_shell_guidance "repo" "${ACTIVE_GUIDANCE_PATHS[@]}"
}

run_self_test() {
    local fixture_dir="${REPO_DIR}/tests/security-guardrails/fixtures/fail"
    local pipe_fixture="${fixture_dir}/pipe-to-shell-guidance.md"
    local self_test_failures=0
    local -a fixture_files=()
    local line

    while IFS= read -r line; do
        fixture_files+=("${line}")
    done < <(find "${fixture_dir}" -type f | sort)

    if (( ${#fixture_files[@]} == 0 )); then
        echo "Phase 7 static self-test fixtures are missing" >&2
        exit 1
    fi

    log_step "Asserting the intentional failing fixtures are rejected"

    if scan_image_pinning_in_files "self-test" "${fixture_files[@]}"; then
        echo "self-test image pinning fixture unexpectedly passed" >&2
        self_test_failures=$((self_test_failures + 1))
    fi

    if scan_namespace_psa_labels_in_files "self-test" "${fixture_files[@]}"; then
        echo "self-test namespace PSA fixture unexpectedly passed" >&2
        self_test_failures=$((self_test_failures + 1))
    fi

    if scan_pipe_to_shell_guidance "self-test" "${pipe_fixture}"; then
        echo "self-test pipe-to-shell fixture unexpectedly passed" >&2
        self_test_failures=$((self_test_failures + 1))
    fi

    if (( self_test_failures > 0 )); then
        printf 'Phase 7 static self-test failed (%d unexpected passes)\n' "${self_test_failures}" >&2
        exit 1
    fi

    echo "Phase 7 static self-test passed"
}

main() {
    local self_test=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --self-test)
                self_test=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage
                exit 1
                ;;
        esac
    done

    cd "${REPO_DIR}"

    if (( self_test == 1 )); then
        run_self_test
        return 0
    fi

    ensure_static_tool kubeconform
    ensure_static_tool kube-linter
    ensure_static_tool kyverno

    log_step "kubeconform schema validation"
    run_kubeconform

    log_step "kube-linter security lint"
    run_kube_linter

    log_step "Kyverno policy fixtures"
    run_kyverno_tests

    log_step "Generated Tilt local-image contract replay"
    run_generated_tilt_local_image_replay

    log_step "Tilt secret/config boundary inventory"
    "${SECRETS_ONLY_SCRIPT}"

    log_step "Repo-specific pattern scans"
    run_repo_pattern_scans

    echo
    echo "Phase 7 static manifest verification passed"
}

main "$@"
