#!/usr/bin/env bash
# Static security guardrail gate for checked-in manifests, policy fixtures, and
# active setup guidance.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATIC_TOOLS_DIR="${PHASE7_STATIC_TOOLS_DIR:-${REPO_DIR}/.cache/phase7-static-tools}"
STATIC_TOOLS_BIN="${STATIC_TOOLS_DIR}/bin"
KUBELINTER_CONFIG="${REPO_DIR}/.kube-linter.yaml"
IMAGE_PINNING_SCRIPT="${REPO_DIR}/scripts/guardrails/check-image-pinning.sh"
SECRETS_ONLY_SCRIPT="${REPO_DIR}/scripts/guardrails/check-secrets-only-handling.sh"
PRODUCTION_KYVERNO_VALUES="${REPO_DIR}/deploy/helm-values/kyverno.values.yaml"
INGRESS_RATE_LIMIT_CONFIG_VERIFIER="${REPO_DIR}/scripts/guardrails/verify-ingress-rate-limit-config.sh"
KUSTOMIZE_RENDER_DIR=""

# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
# shellcheck source=../lib/pinned-tool-versions.sh
. "${SCRIPT_DIR}/../lib/pinned-tool-versions.sh"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
# shellcheck source=../lib/production-version-contract.sh
. "${REPO_DIR}/scripts/lib/production-version-contract.sh"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
# shellcheck source=../lib/guardrail-python.sh
. "${SCRIPT_DIR}/../lib/guardrail-python.sh"

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
    Telemetry
    VirtualService
)

RENDERED_KUSTOMIZE_OVERLAYS=(
    "${REPO_DIR}/kubernetes/production/apps"
    "${REPO_DIR}/kubernetes/production/infrastructure"
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

OBSERVABILITY_ROUTE_PATHS=(
    "${REPO_DIR}/kubernetes"
)

OBSERVABILITY_PRODUCTION_INPUT_PATHS=(
    "${REPO_DIR}/deploy/README.md"
    "${REPO_DIR}/deploy/scripts/render"
)

OBSERVABILITY_GRAFANA_VALUES_FILES=(
    "${REPO_DIR}/kubernetes/monitoring/prometheus-stack-values.yaml"
    "${REPO_DIR}/kubernetes/production/monitoring/prometheus-stack-values.override.yaml"
)

OBSERVABILITY_INGRESS_POLICY_PATHS=(
    "${REPO_DIR}/kubernetes/network-policies/istio-ingress-allow.yaml"
    "${REPO_DIR}/kubernetes/production/istio-ingress-policies"
)

ISTIOD_VALUES_FILE="${REPO_DIR}/kubernetes/istio/istiod-values.yaml"
EGRESS_GATEWAY_VALUES_FILE="${REPO_DIR}/kubernetes/istio/egress-gateway-values.yaml"
ISTIO_AUTHORIZATION_POLICIES_FILE="${REPO_DIR}/kubernetes/istio/authorization-policies.yaml"
ISTIO_TRACING_TELEMETRY_FILE="${REPO_DIR}/kubernetes/istio/tracing-telemetry.yaml"
JAEGER_MANIFEST_DIR="${REPO_DIR}/kubernetes/monitoring/jaeger"
JAEGER_SERVICES_FILE="${REPO_DIR}/kubernetes/monitoring/jaeger/services.yaml"
KIALI_VALUES_FILE="${REPO_DIR}/kubernetes/monitoring/kiali-values.yaml"
NGINX_BACKEND_HEADERS_INCLUDE="${REPO_DIR}/nginx/includes/backend-headers.conf"
NGINX_API_ROUTES_INCLUDE="${REPO_DIR}/nginx/includes/api-routes.conf"
NGINX_API_DOCS_ROUTES_INCLUDE="${REPO_DIR}/nginx/includes/api-docs-routes.conf"
NGINX_SERVER_CONFIG_FILES=(
    "${REPO_DIR}/nginx/nginx.k8s.conf"
    "${REPO_DIR}/nginx/nginx.production.k8s.conf"
)
INGRESS_PATH_HARDENING_FILE="${REPO_DIR}/kubernetes/istio/ingress-path-hardening.yaml"
PRODUCTION_INGRESS_POLICIES_OVERLAY="${REPO_DIR}/kubernetes/production/istio-ingress-policies"
INGRESS_EXACT_ORIGIN_FILE="${REPO_DIR}/kubernetes/istio/ingress-exact-origin.yaml"
BROWSER_ROUTE_FILES=(
    "${REPO_DIR}/kubernetes/gateway/app-httproute.yaml"
    "${REPO_DIR}/kubernetes/gateway/api-httproute.yaml"
    "${REPO_DIR}/kubernetes/gateway/auth-httproute.yaml"
)
PRODUCTION_GATEWAY_ROUTES_OVERLAY="${REPO_DIR}/kubernetes/production/gateway-routes"

usage() {
    cat <<'EOF'
Usage: scripts/guardrails/verify-static-security-manifests.sh [--self-test]

Runs the static security guardrail suite:
- kubeconform schema validation for checked-in manifests
- kubeconform schema validation for rendered production Kustomize overlays
- kube-linter with the repo-specific security baseline
- Kyverno CLI tests for the admission fixtures
- generated Kyverno replay for representative approved local Tilt deploy refs
- production Kyverno Helm render check for digest-pinned controller/hook images
- ingress rate-limit policy and production gateway diagnostics render checks
- Tilt secret/config boundary inventory validation
- pattern scans for image pinning, namespace PSA labels, and pipe-to-shell guidance
- Istio AuthorizationPolicy structure: explicit default-deny-all and exact
  NGINX path allowlists on backend policies
- NGINX shared route includes: one copy of the API and /api-docs routes and
  the decoded ";" rejection
- ingress path hardening: DENY of a literal ";" and %3b at any percent-encoding
  depth in the path, locally and in the production render
- ingress exact Origin: DENY of unsafe methods without the exact browser
  origin, restricted to the routed browser application host, locally and in
  the production render
- istio-egress private destinations: no NetworkPolicy in istio-egress allows
  TCP 443 to private, link-local or carrier-grade NAT ranges

Use --self-test to assert that the intentional failing fixtures are rejected.

Python checks use .cache/phase7-static-tools/pyyaml-venv/bin/python unless
INGRESS_RATE_LIMIT_PYTHON selects another interpreter. There is no python3
fallback.
EOF
}

log_step() {
    printf '\n==> %s\n' "$1"
}

cleanup_static_guardrails() {
    if [[ -n "${KUSTOMIZE_RENDER_DIR}" ]]; then
        rm -rf "${KUSTOMIZE_RENDER_DIR}"
    fi
}

trap cleanup_static_guardrails EXIT

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
        ! -name '*values.override.yaml' \
        ! -path '*/patches/*' \
        ! -path "${REPO_DIR}/kubernetes/production/apps/deployment-manifest.yaml" \
        ! -path "${REPO_DIR}/kubernetes/production/docs-aggregator/*" \
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

run_kubeconform_for_files() {
    local subject="$1"
    shift
    local output_file
    local summary_line=""
    local kubeconform_rc=0
    local -a unexpected_lines=()
    local -a missing_kind_lines=()
    local line

    if (( $# == 0 )); then
        echo "ERROR: no files provided for ${subject} kubeconform validation" >&2
        exit 1
    fi

    output_file="$(mktemp)"
    if "${STATIC_TOOLS_BIN}/kubeconform" -strict -summary "$@" >"${output_file}" 2>&1; then
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
        printf '%s kubeconform validation reported unexpected errors:\n' "${subject}" >&2
        printf '  - %s\n' "${unexpected_lines[@]}" >&2
        exit 1
    fi

    if (( kubeconform_rc != 0 && ${#missing_kind_lines[@]} == 0 )); then
        printf '%s kubeconform validation failed without a recognized schema-gap exception\n' "${subject}" >&2
        exit "${kubeconform_rc}"
    fi

    if [[ -n "${summary_line}" ]]; then
        printf '%s: %s\n' "${subject}" "${summary_line}"
    fi

    if (( ${#missing_kind_lines[@]} > 0 )); then
        printf '%s allowed kubeconform schema gaps: %s\n' "${subject}" \
            "$(printf '%s\n' "${missing_kind_lines[@]}" | sort -u | awk 'BEGIN { first = 1 } { if (!first) { printf ", " } printf "%s", $0; first = 0 } END { printf "\n" }' | tr -d '\n')"
    fi
}

run_rendered_kustomize_schema_validation() {
    local overlay overlay_name safe_name rendered_file

    KUSTOMIZE_RENDER_DIR="$(mktemp -d)"

    for overlay in "${RENDERED_KUSTOMIZE_OVERLAYS[@]}"; do
        if [[ ! -d "${overlay}" ]]; then
            printf 'ERROR: rendered Kustomize overlay is missing: %s\n' "${overlay#"${REPO_DIR}"/}" >&2
            exit 1
        fi

        overlay_name="${overlay#"${REPO_DIR}"/}"
        safe_name="${overlay_name//\//_}"
        rendered_file="${KUSTOMIZE_RENDER_DIR}/${safe_name}.yaml"

        printf 'Rendering %s\n' "${overlay_name}"
        if ! "${STATIC_TOOLS_BIN}/kubectl" kustomize "${overlay}" --load-restrictor=LoadRestrictionsNone > "${rendered_file}"; then
            printf 'ERROR: failed to render Kustomize overlay: %s\n' "${overlay_name}" >&2
            exit 1
        fi

        run_kubeconform_for_files "rendered overlay ${overlay_name}" "${rendered_file}"
    done

    rm -rf "${KUSTOMIZE_RENDER_DIR}"
    KUSTOMIZE_RENDER_DIR=""
}

run_kubeconform() {
    local -a manifest_files=()
    local line

    while IFS= read -r line; do
        manifest_files+=("${line}")
    done < <(collect_schema_manifest_files)

    if (( ${#manifest_files[@]} == 0 )); then
        echo "ERROR: no manifest files found for kubeconform" >&2
        exit 1
    fi

    run_kubeconform_for_files "checked-in manifests" "${manifest_files[@]}"
    run_rendered_kustomize_schema_validation
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
      image: busybox:1.38.0@sha256:fd7dc98638c8e305f4dc34e979f1c0fdfdcaeb0fbf8fcff77ae834b6da3d7e6e
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

run_kyverno_production_helm_render_check() {
    local temp_dir rendered_file chart_metadata chart_app_version image expected_image
    local refs_checked=0 image_occurrences=0
    local -a failures=()
    local -a expected_images=(
        "reg.kyverno.io/kyverno/kyverno-cli@sha256:ced7b2be0b04250cabfe695f15307f69eb715fe23234816388af4f3812915b2a"
        "reg.kyverno.io/kyverno/kyvernopre@sha256:c25c47461f06f2845a48c319ae86fbbc1730a7b9ed5b701889c9dc1f9ee94b09"
        "reg.kyverno.io/kyverno/kyverno@sha256:b31d8511ae5fd6010e2a01ea72ebae08eb82fa51d91af14a1d9fe989949b4edb"
        "reg.kyverno.io/kyverno/background-controller@sha256:8f1e9143373a27578cafc2d28d2c66ba0926c63b4c77e63de8d2fdd4a122859f"
        "reg.kyverno.io/kyverno/cleanup-controller@sha256:67a48e62a8d8f8120c86914ff822b90017c54054c7b64ef8a1555645e9d9761e"
        "reg.kyverno.io/kyverno/reports-controller@sha256:c0eee97b9b44a0dd35805d56b358fa52548480f79d4944602b9609538eccd64c"
        "ghcr.io/kyverno/readiness-checker@sha256:31bb42ce7f5b2e27c1cf633aeff4f0cad1f5bb63761e2cb09f0e25cdd26572bf"
    )
    local -A rendered_images=()

    [[ -f "${PRODUCTION_KYVERNO_VALUES}" ]] || {
        echo "ERROR: production Kyverno values file is missing: ${PRODUCTION_KYVERNO_VALUES}" >&2
        exit 1
    }

    temp_dir="$(mktemp -d)"
    rendered_file="${temp_dir}/kyverno-production.yaml"

    HELM_CACHE_HOME="${temp_dir}/cache" \
    HELM_CONFIG_HOME="${temp_dir}/config" \
    HELM_DATA_HOME="${temp_dir}/data" \
    HELM_REPOSITORY_CACHE="${temp_dir}/repository-cache" \
    HELM_REPOSITORY_CONFIG="${temp_dir}/repositories.yaml" \
        "${STATIC_TOOLS_BIN}/helm" repo add kyverno "${PRODUCTION_KYVERNO_HELM_REPO_URL}" >/dev/null

    HELM_CACHE_HOME="${temp_dir}/cache" \
    HELM_CONFIG_HOME="${temp_dir}/config" \
    HELM_DATA_HOME="${temp_dir}/data" \
    HELM_REPOSITORY_CACHE="${temp_dir}/repository-cache" \
    HELM_REPOSITORY_CONFIG="${temp_dir}/repositories.yaml" \
        "${STATIC_TOOLS_BIN}/helm" repo update kyverno >/dev/null

    chart_metadata="$(
        HELM_CACHE_HOME="${temp_dir}/cache" \
        HELM_CONFIG_HOME="${temp_dir}/config" \
        HELM_DATA_HOME="${temp_dir}/data" \
        HELM_REPOSITORY_CACHE="${temp_dir}/repository-cache" \
        HELM_REPOSITORY_CONFIG="${temp_dir}/repositories.yaml" \
            "${STATIC_TOOLS_BIN}/helm" show chart kyverno/kyverno \
                --version "${PRODUCTION_KYVERNO_CHART_VERSION}"
    )"
    chart_app_version="$(awk '$1 == "appVersion:" { gsub(/"/, "", $2); print $2; exit }' <<< "${chart_metadata}")"
    if [[ "${chart_app_version}" != "v${PRODUCTION_KYVERNO_APP_VERSION}" ]]; then
        echo "production Kyverno chart app version mismatch: expected v${PRODUCTION_KYVERNO_APP_VERSION}, got ${chart_app_version:-missing}" >&2
        exit 1
    fi

    HELM_CACHE_HOME="${temp_dir}/cache" \
    HELM_CONFIG_HOME="${temp_dir}/config" \
    HELM_DATA_HOME="${temp_dir}/data" \
    HELM_REPOSITORY_CACHE="${temp_dir}/repository-cache" \
    HELM_REPOSITORY_CONFIG="${temp_dir}/repositories.yaml" \
        "${STATIC_TOOLS_BIN}/helm" template kyverno kyverno/kyverno \
            --version "${PRODUCTION_KYVERNO_CHART_VERSION}" \
            --namespace kyverno \
            --kube-version "${PRODUCTION_KUBERNETES_VERSION}" \
            --values "${PRODUCTION_KYVERNO_VALUES}" > "${rendered_file}"

    while IFS= read -r image; do
        [[ -n "${image}" ]] || continue
        refs_checked=$((refs_checked + 1))
        rendered_images["${image}"]=1

        if [[ ! "${image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
            failures+=("${image}")
        fi
    done < <(sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "${rendered_file}" | sort -u)

    image_occurrences="$(sed -nE 's/^[[:space:]]*image:[[:space:]]*"?([^"[:space:]]+)"?.*$/\1/p' "${rendered_file}" | wc -l)"
    if (( image_occurrences != 13 )); then
        failures+=("expected 13 controller, init, migration, hook, and test image occurrences, rendered ${image_occurrences}")
    fi

    for expected_image in "${expected_images[@]}"; do
        if [[ -z "${rendered_images[${expected_image}]+present}" ]]; then
            failures+=("missing reviewed image: ${expected_image}")
        fi
    done

    if (( ${#rendered_images[@]} != ${#expected_images[@]} )); then
        failures+=("expected ${#expected_images[@]} unique reviewed images, rendered ${#rendered_images[@]}")
    fi

    rm -rf "${temp_dir}"

    if (( refs_checked == 0 )); then
        echo "production Kyverno Helm render check found no image references" >&2
        exit 1
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'production Kyverno Helm render check failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        exit 1
    fi

    printf 'production Kyverno Helm render check passed (chart %s / app %s; %d occurrences across %d unique refs)\n' \
        "${PRODUCTION_KYVERNO_CHART_VERSION}" "${PRODUCTION_KYVERNO_APP_VERSION}" \
        "${image_occurrences}" "${refs_checked}"
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

grafana_anonymous_access_enabled() {
    local file="$1"

    awk '
        function indentation(line) {
            match(line, /^[[:space:]]*/)
            return RLENGTH
        }
        {
            raw = $0
            line = tolower($0)
            indent = indentation(raw)

            if (in_auth_anonymous && indent <= auth_anonymous_indent &&
                line !~ /^[[:space:]]*#/ && line !~ /^[[:space:]]*$/) {
                in_auth_anonymous = 0
            }

            if (line ~ /^[[:space:]]*auth\.anonymous:[[:space:]]*$/) {
                in_auth_anonymous = 1
                auth_anonymous_indent = indent
                next
            }

            if (in_auth_anonymous && line ~ /^[[:space:]]*enabled:[[:space:]]*true([[:space:]]|$)/) {
                found = 1
                exit 0
            }

            if (line ~ /auth\.anonymous\.enabled:[[:space:]]*true([[:space:]]|$)/) {
                found = 1
                exit 0
            }

            if (line ~ /gf_auth_anonymous_enabled[^[:alnum:]]*["'\'']?true(["'\'']|[[:space:]]|$)/) {
                found = 1
                exit 0
            }
        }
        END {
            exit found ? 0 : 1
        }
    ' "${file}"
}

scan_observability_httproutes() {
    local file
    local -a failures=()

    while IFS= read -r file; do
        [[ -n "${file}" ]] || continue

        if grep -Eq '^kind:[[:space:]]*HTTPRoute([[:space:]]|$)' "${file}" &&
            grep -Eiq '\b(grafana|prometheus|kiali|jaeger)\b' "${file}"; then
            failures+=("${file#"${REPO_DIR}"/}")
        fi
    done < <(find "${OBSERVABILITY_ROUTE_PATHS[@]}" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

    if (( ${#failures[@]} > 0 )); then
        printf 'observability HTTPRoute scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'observability HTTPRoute scan passed\n'
}

scan_observability_ingresses() {
    local file
    local -a failures=()

    while IFS= read -r file; do
        [[ -n "${file}" ]] || continue

        if grep -Eq '^kind:[[:space:]]*Ingress([[:space:]]|$)' "${file}" &&
            grep -Eiq '\b(grafana|prometheus|kiali|jaeger)\b' "${file}"; then
            failures+=("${file#"${REPO_DIR}"/}")
        fi
    done < <(find "${OBSERVABILITY_ROUTE_PATHS[@]}" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

    if (( ${#failures[@]} > 0 )); then
        printf 'observability Ingress scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'observability Ingress scan passed\n'
}

scan_observability_public_entry_hostnames() {
    local file
    local -a failures=()

    while IFS= read -r file; do
        [[ -n "${file}" ]] || continue

        if grep -Eq '^kind:[[:space:]]*(Ingress|HTTPRoute|Gateway)([[:space:]]|$)' "${file}" &&
            grep -Eiq '(^|[[:space:]-])["'\'']?(grafana|prometheus|kiali|jaeger)\.[[:alnum:].-]+' "${file}"; then
            failures+=("${file#"${REPO_DIR}"/}")
        fi
    done < <(find "${OBSERVABILITY_ROUTE_PATHS[@]}" -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)

    if (( ${#failures[@]} > 0 )); then
        printf 'observability public-entry hostname scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'observability public-entry hostname scan passed\n'
}

scan_observability_production_inputs() {
    local -a matches=()
    local line
    local pattern='\b(GRAFANA_DOMAIN|KIALI_DOMAIN|JAEGER_DOMAIN)\b'

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        matches+=("${line}")
    done < <(search_guidance_paths "${pattern}" "${OBSERVABILITY_PRODUCTION_INPUT_PATHS[@]}")

    if (( ${#matches[@]} > 0 )); then
        printf 'observability production input scan failed:\n' >&2
        printf '  - %s\n' "${matches[@]}" >&2
        return 1
    fi

    printf 'observability production input scan passed\n'
}

scan_grafana_values_contract() {
    local file
    local line
    local -a hostname_matches=()
    local hostname_pattern='grafana\.budgetanalyzer\.(localhost|org)'
    local -a anonymous_failures=()

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        hostname_matches+=("${line}")
    done < <(search_guidance_paths "${hostname_pattern}" "${OBSERVABILITY_GRAFANA_VALUES_FILES[@]}")

    for file in "${OBSERVABILITY_GRAFANA_VALUES_FILES[@]}"; do
        [[ -f "${file}" ]] || continue
        if grafana_anonymous_access_enabled "${file}"; then
            anonymous_failures+=("${file#"${REPO_DIR}"/}: Grafana anonymous access is enabled")
        fi
    done

    if (( ${#hostname_matches[@]} > 0 || ${#anonymous_failures[@]} > 0 )); then
        printf 'Grafana values contract scan failed:\n' >&2
        if (( ${#hostname_matches[@]} > 0 )); then
            printf '  - %s\n' "${hostname_matches[@]}" >&2
        fi
        if (( ${#anonymous_failures[@]} > 0 )); then
            printf '  - %s\n' "${anonymous_failures[@]}" >&2
        fi
        return 1
    fi

    printf 'Grafana values contract scan passed\n'
}

scan_kiali_values_contract() {
    local -a failures=()

    if [[ ! -f "${KIALI_VALUES_FILE}" ]]; then
        failures+=("${KIALI_VALUES_FILE#"${REPO_DIR}"/}: file is missing")
    else
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'strategy:[[:space:]]*token' \
            'Kiali token auth strategy'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'view_only_mode:[[:space:]]*true' \
            'Kiali view-only mode'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'cluster_wide_access:[[:space:]]*false' \
            'Kiali non-cluster-wide RBAC'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'service_type:[[:space:]]*ClusterIP' \
            'Kiali ClusterIP service exposure'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'internal_url:[[:space:]]*http://jaeger-query\.monitoring:16685/jaeger' \
            'Kiali Jaeger gRPC query URL'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'health_check_url:[[:space:]]*http://jaeger-query\.monitoring:16686/jaeger' \
            'Kiali Jaeger HTTP health URL'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'use_grpc:[[:space:]]*true' \
            'Kiali Jaeger gRPC mode'
        assert_pattern_in_file failures "${KIALI_VALUES_FILE}" \
            'disable_version_check:[[:space:]]*true' \
            'Kiali Jaeger version-check suppression'

        if grep -Eq 'strategy:[[:space:]]*anonymous([[:space:]]|$)' "${KIALI_VALUES_FILE}"; then
            failures+=("${KIALI_VALUES_FILE#"${REPO_DIR}"/}: Kiali anonymous auth is enabled")
        fi

        if grep -Eq 'cluster_wide_access:[[:space:]]*true([[:space:]]|$)' "${KIALI_VALUES_FILE}"; then
            failures+=("${KIALI_VALUES_FILE#"${REPO_DIR}"/}: Kiali requests cluster-wide access")
        fi

        if grep -Eq 'external_url:[[:space:]]*https?://' "${KIALI_VALUES_FILE}"; then
            failures+=("${KIALI_VALUES_FILE#"${REPO_DIR}"/}: Kiali sets a public external_url")
        fi
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Kiali values contract scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'Kiali values contract scan passed\n'
}

scan_jaeger_manifest_contract() {
    local -a failures=()

    if [[ ! -d "${JAEGER_MANIFEST_DIR}" ]]; then
        failures+=("${JAEGER_MANIFEST_DIR#"${REPO_DIR}"/}: directory is missing")
    fi

    if [[ ! -f "${JAEGER_SERVICES_FILE}" ]]; then
        failures+=("${JAEGER_SERVICES_FILE#"${REPO_DIR}"/}: file is missing")
    else
        if [[ "$(grep -Ec '^[[:space:]]*type:[[:space:]]*ClusterIP([[:space:]]|$)' "${JAEGER_SERVICES_FILE}")" -ne 2 ]]; then
            failures+=("${JAEGER_SERVICES_FILE#"${REPO_DIR}"/}: Jaeger services must remain ClusterIP-only")
        fi

        if grep -Eq '^[[:space:]]*type:[[:space:]]*(LoadBalancer|NodePort|ExternalName)([[:space:]]|$)' "${JAEGER_SERVICES_FILE}"; then
            failures+=("${JAEGER_SERVICES_FILE#"${REPO_DIR}"/}: Jaeger services expose a non-ClusterIP type")
        fi

        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'name:[[:space:]]*jaeger-collector' \
            'Jaeger collector Service'
        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'name:[[:space:]]*jaeger-query' \
            'Jaeger query Service'
    fi

    if [[ -d "${JAEGER_MANIFEST_DIR}" ]]; then
        if grep -Eq '^kind:[[:space:]]*(Ingress|HTTPRoute|Gateway)([[:space:]]|$)' "${JAEGER_MANIFEST_DIR}"/*.yaml; then
            failures+=("${JAEGER_MANIFEST_DIR#"${REPO_DIR}"/}: Jaeger manifests create a public entry resource")
        fi

        if grep -Eiq '\b(elasticsearch|opensearch)\b' "${JAEGER_MANIFEST_DIR}"/*.yaml; then
            failures+=("${JAEGER_MANIFEST_DIR#"${REPO_DIR}"/}: Jaeger manifests depend on Elasticsearch/OpenSearch")
        fi
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Jaeger manifest contract scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'Jaeger manifest contract scan passed\n'
}

scan_istio_ingress_observability_allowances() {
    local expected_jaeger_policy_file="${REPO_DIR}/kubernetes/network-policies/istio-ingress-allow.yaml"
    local -a failures=()
    local -a jaeger_matches=()
    local line
    local file
    local pattern='kubernetes\.io/metadata\.name:[[:space:]]*monitoring|app\.kubernetes\.io/name:[[:space:]]*(grafana|prometheus|kiali|jaeger)|prometheus-stack-grafana|prometheus-stack-kube-prom-prometheus'
    local forbidden_pattern='app\.kubernetes\.io/name:[[:space:]]*(grafana|prometheus|kiali)|prometheus-stack-grafana|prometheus-stack-kube-prom-prometheus'

    while IFS= read -r line; do
        [[ -n "${line}" ]] || continue
        file="${line%%:*}"

        if [[ "${line}" =~ ${forbidden_pattern} ]]; then
            failures+=("${line}")
            continue
        fi

        if [[ "${file}" == "${expected_jaeger_policy_file}" ]] && \
            [[ "${line}" =~ kubernetes\.io/metadata\.name:[[:space:]]*monitoring|app\.kubernetes\.io/name:[[:space:]]*jaeger ]]; then
            jaeger_matches+=("${line}")
            continue
        fi

        failures+=("${line}")
    done < <(search_guidance_paths "${pattern}" "${OBSERVABILITY_INGRESS_POLICY_PATHS[@]}")

    if (( ${#jaeger_matches[@]} > 0 )); then
        if ! grep -Eq 'name:[[:space:]]*allow-istio-ingress-egress-to-jaeger-collector' "${expected_jaeger_policy_file}" || \
            ! grep -Eq 'app\.kubernetes\.io/name:[[:space:]]*jaeger' "${expected_jaeger_policy_file}" || \
            ! grep -Eq 'port:[[:space:]]*4317' "${expected_jaeger_policy_file}" || \
            ! grep -Eq 'port:[[:space:]]*4318' "${expected_jaeger_policy_file}"; then
            failures+=("${expected_jaeger_policy_file#"${REPO_DIR}"/}: expected narrow istio-ingress OTLP egress policy to Jaeger collector is missing required selectors or ports")
        fi
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Istio ingress observability allowance scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'Istio ingress observability allowance scan passed\n'
}

assert_pattern_in_file() {
    local -n failures_ref="$1"
    local file="$2"
    local pattern="$3"
    local label="$4"

    if ! grep -Eq "${pattern}" "${file}"; then
        failures_ref+=("${file#"${REPO_DIR}"/}: missing ${label}")
    fi
}

scan_istio_tracing_contract() {
    local -a failures=()

    if [[ ! -f "${ISTIOD_VALUES_FILE}" ]]; then
        failures+=("${ISTIOD_VALUES_FILE#"${REPO_DIR}"/}: file is missing")
    else
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'enableTracing:[[:space:]]*true' \
            'meshConfig.enableTracing: true'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'defaultConfig:' \
            'meshConfig.defaultConfig'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'tracing:[[:space:]]*\{\}' \
            'empty meshConfig.defaultConfig.tracing'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'name:[[:space:]]*jaeger' \
            'Jaeger extension provider name'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'opentelemetry:' \
            'OpenTelemetry extension provider block'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'service:[[:space:]]*jaeger-collector\.monitoring\.svc\.cluster\.local' \
            'internal Jaeger collector service'
        assert_pattern_in_file failures "${ISTIOD_VALUES_FILE}" \
            'port:[[:space:]]*4317' \
            'Jaeger OTLP/gRPC provider port'
    fi

    if [[ ! -f "${ISTIO_TRACING_TELEMETRY_FILE}" ]]; then
        failures+=("${ISTIO_TRACING_TELEMETRY_FILE#"${REPO_DIR}"/}: file is missing")
    else
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'apiVersion:[[:space:]]*telemetry\.istio\.io/v1' \
            'Telemetry v1 apiVersion'
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'kind:[[:space:]]*Telemetry' \
            'Telemetry kind'
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'name:[[:space:]]*mesh-default-tracing' \
            'mesh-default tracing resource name'
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'namespace:[[:space:]]*istio-system' \
            'Istio root namespace'
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'providers:' \
            'Telemetry tracing providers block'
        assert_pattern_in_file failures "${ISTIO_TRACING_TELEMETRY_FILE}" \
            'name:[[:space:]]*jaeger' \
            'Telemetry Jaeger provider selection'
    fi

    if [[ ! -f "${JAEGER_SERVICES_FILE}" ]]; then
        failures+=("${JAEGER_SERVICES_FILE#"${REPO_DIR}"/}: file is missing")
    else
        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'name:[[:space:]]*grpc-otlp' \
            'Istio-classified Jaeger OTLP/gRPC service port name'
        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'appProtocol:[[:space:]]*grpc' \
            'Jaeger OTLP/gRPC service appProtocol'
        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'name:[[:space:]]*http-otlp' \
            'Istio-classified Jaeger OTLP/HTTP service port name'
        assert_pattern_in_file failures "${JAEGER_SERVICES_FILE}" \
            'appProtocol:[[:space:]]*http' \
            'Jaeger OTLP/HTTP service appProtocol'
    fi

    if grep -Eq 'randomSamplingPercentage:' "${ISTIOD_VALUES_FILE}" "${ISTIO_TRACING_TELEMETRY_FILE}" 2>/dev/null; then
        failures+=("Istio tracing sampling must stay on defaults until an explicit reviewed setting is documented")
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Istio tracing contract scan failed:\n' >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'Istio tracing contract scan passed\n'
}

# The ext-authz provider must fail closed, bound every check with a timeout
# and report authorizer failures as 503 instead of Istio's 403 default, and
# only content-type may reach the client from a denial.
scan_istio_ext_authz_denial_contract() {
    local subject="$1"
    local values_file="$2"
    local label="${values_file#"${REPO_DIR}"/}"
    local provider_count policy_count fail_open status_on_error timeout
    local -a deny_headers=()
    local -a provider_fields=()
    local -a failures=()

    if [[ ! -f "${values_file}" ]]; then
        failures+=("${label}: file is missing")
    else
        provider_count=$(grep -Ec '^    - name:[[:space:]]*ext-authz-http[[:space:]]*$' "${values_file}" || true)
        if [[ "${provider_count}" -ne 1 ]]; then
            failures+=("${label}: expected exactly one ext-authz-http extension provider, found ${provider_count}")
        fi

        policy_count=$(grep -Ec '^[[:space:]]*headersToDownstreamOnDeny:[[:space:]]*$' "${values_file}" || true)
        if [[ "${policy_count}" -ne 1 ]]; then
            failures+=("${label}: expected exactly one headersToDownstreamOnDeny policy, found ${policy_count}")
        fi

        mapfile -t deny_headers < <(
            awk '
                /^        headersToDownstreamOnDeny:[[:space:]]*$/ {
                    in_deny_list = 1
                    next
                }
                in_deny_list && /^          -[[:space:]]+/ {
                    sub(/^          -[[:space:]]+/, "")
                    print
                    next
                }
                in_deny_list { exit }
            ' "${values_file}"
        )

        if (( ${#deny_headers[@]} != 1 )) || [[ "${deny_headers[0]:-}" != "content-type" ]]; then
            failures+=("${label}: ext-authz deny responses must forward only content-type")
        fi

        # Scalar fields of the ext-authz-http envoyExtAuthzHttp block, as
        # key=value with surrounding quotes removed.
        mapfile -t provider_fields < <(
            awk '
                /^    - name:[[:space:]]*ext-authz-http[[:space:]]*$/ {
                    in_provider = 1
                    next
                }
                in_provider && /^    - / { exit }
                in_provider && /^        [A-Za-z]+:[[:space:]]*[^[:space:]]/ {
                    line = $0
                    sub(/^        /, "", line)
                    key = line
                    sub(/:.*/, "", key)
                    value = line
                    sub(/^[A-Za-z]+:[[:space:]]*/, "", value)
                    sub(/[[:space:]]*(#.*)?$/, "", value)
                    gsub(/^["\047]|["\047]$/, "", value)
                    print key "=" value
                }
            ' "${values_file}"
        )

        fail_open=$(printf '%s\n' "${provider_fields[@]}" | sed -n 's/^failOpen=//p')
        status_on_error=$(printf '%s\n' "${provider_fields[@]}" | sed -n 's/^statusOnError=//p')
        timeout=$(printf '%s\n' "${provider_fields[@]}" | sed -n 's/^timeout=//p')

        if [[ "${fail_open}" != "false" ]]; then
            failures+=("${label}: ext-authz-http must set failOpen: false")
        fi
        if [[ "${status_on_error}" != "503" ]]; then
            failures+=("${label}: ext-authz-http must set statusOnError: \"503\" so authorizer failures are not reported as Istio's default 403")
        fi
        if ! [[ "${timeout}" =~ ^[0-9]+(\.[0-9]+)?s$ ]] || [[ "${timeout}" =~ ^0+(\.0+)?s$ ]]; then
            failures+=("${label}: ext-authz-http must set a positive timeout in seconds (Istio's default is 600s)")
        fi
    fi

    if (( ${#failures[@]} > 0 )); then
        printf 'Istio ext-authz denial contract scan failed (%s):\n' "${subject}" >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf 'Istio ext-authz denial contract scan passed (%s)\n' "${subject}"
}

# Structural check for the mesh public/internal boundary. Each file is read as
# a complete policy set: it must contain default-deny-all in default with an
# empty spec, and every backend policy rule that admits the nginx-gateway
# identity must restrict paths without a service- or version-wide wildcard.
scan_istio_authorization_policy_contract() {
    local subject="$1"
    shift

    if ! "${GUARDRAIL_PYTHON}" -I - "${REPO_DIR}" "$@" <<'AUTHZ_PY'
import sys
from pathlib import Path

import yaml

NGINX_PRINCIPAL = "cluster.local/ns/default/sa/nginx-gateway"
BACKEND_APPS = ("transaction-service", "currency-service", "permission-service")
# Fewer than three fixed segments before a wildcard covers a whole service or
# API version, for example /transaction-service/* or /transaction-service/v1/*.
MIN_FIXED_SEGMENTS = 3

repo_dir = Path(sys.argv[1])
failures = []


def label(path):
    try:
        return str(Path(path).resolve().relative_to(repo_dir))
    except ValueError:
        return str(path)


def wildcard_problem(path):
    if not isinstance(path, str) or not path.startswith("/"):
        return "is not an absolute path"
    if "{**}" in path:
        return "uses a multi-segment {**} template"
    if "*" in path.replace("{*}", "") and not path.endswith("*"):
        return "uses a non-suffix wildcard"
    if path.endswith("*") and not path.endswith("{*}"):
        fixed = [segment for segment in path[:-1].split("/") if segment]
        if len(fixed) < MIN_FIXED_SEGMENTS:
            return "is a service- or version-wide wildcard"
    return None


for policy_file in sys.argv[2:]:
    name = label(policy_file)
    try:
        documents = [
            document
            for document in yaml.safe_load_all(Path(policy_file).read_text(encoding="utf-8"))
            if isinstance(document, dict)
        ]
    except (OSError, yaml.YAMLError) as error:
        failures.append(f"{name}: cannot parse: {error}")
        continue

    policies = [document for document in documents if document.get("kind") == "AuthorizationPolicy"]

    deny_all = [
        policy
        for policy in policies
        if (policy.get("metadata") or {}).get("name") == "default-deny-all"
        and (policy.get("metadata") or {}).get("namespace") == "default"
    ]
    if len(deny_all) != 1:
        failures.append(f"{name}: expected exactly one default/default-deny-all, found {len(deny_all)}")
    elif deny_all[0].get("spec") not in ({}, None):
        failures.append(f"{name}: default-deny-all must have an empty spec, found {deny_all[0].get('spec')!r}")

    nginx_rules_seen = {app: 0 for app in BACKEND_APPS}
    for policy in policies:
        spec = policy.get("spec") or {}
        app = ((spec.get("selector") or {}).get("matchLabels") or {}).get("app")
        if app not in BACKEND_APPS:
            continue
        policy_name = (policy.get("metadata") or {}).get("name", "<unnamed>")
        for index, rule in enumerate(spec.get("rules") or []):
            principals = [
                principal
                for source in (rule.get("from") or [])
                for principal in ((source.get("source") or {}).get("principals") or [])
            ]
            if NGINX_PRINCIPAL not in principals:
                continue
            nginx_rules_seen[app] += 1
            where = f"{name}: {policy_name} rule {index}"
            operations = rule.get("to") or []
            if not operations:
                failures.append(f"{where}: nginx-gateway rule has no to restriction")
                continue
            for op_index, entry in enumerate(operations):
                paths = (entry.get("operation") or {}).get("paths") or []
                if not paths:
                    failures.append(f"{where}: to[{op_index}] does not restrict paths")
                for path in paths:
                    problem = wildcard_problem(path)
                    if problem:
                        failures.append(f"{where}: path {path!r} {problem}")

    for app, count in nginx_rules_seen.items():
        if count == 0:
            failures.append(f"{name}: no {app} policy rule admits nginx-gateway, so the backend contract is not checkable")

if failures:
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)
AUTHZ_PY
    then
        printf '%s Istio AuthorizationPolicy contract scan failed\n' "${subject}" >&2
        return 1
    fi

    printf '%s Istio AuthorizationPolicy contract scan passed\n' "${subject}"
}

# The shared backend include must strip browser credentials and send the real
# scheme, and every /api proxy location in the shared API routes include must
# use it.
scan_nginx_backend_header_contract() {
    local subject="$1"
    local include_file="$2"
    shift 2
    local -a config_files=("$@")
    local -a failures=()
    local -a directives=()
    local config_file directive count line
    local -A required=(
        ['proxy_set_header Cookie "";']=1
        ['proxy_set_header Authorization "";']=1
        ['proxy_set_header X-Forwarded-Proto https;']=1
    )

    if [[ ! -f "${include_file}" ]]; then
        failures+=("${include_file#"${REPO_DIR}"/}: file is missing")
    else
        mapfile -t directives < <(
            sed -E -e 's/#.*$//' -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' -e 's/[[:space:]]+/ /g' \
                "${include_file}" |
                grep -Ei '^proxy_set_header (Cookie|Authorization|X-Forwarded-Proto) ' || true
        )

        for directive in "${!required[@]}"; do
            count=0
            for line in "${directives[@]}"; do
                [[ "${line}" == "${directive}" ]] && count=$((count + 1))
            done
            if (( count != 1 )); then
                failures+=("${include_file#"${REPO_DIR}"/}: expected exactly one '${directive}', found ${count}")
            fi
        done

        for line in "${directives[@]}"; do
            if [[ -z "${required[${line}]:-}" ]]; then
                failures+=("${include_file#"${REPO_DIR}"/}: unexpected credential or scheme directive '${line}'")
            fi
        done
    fi

    for config_file in "${config_files[@]}"; do
        if [[ ! -f "${config_file}" ]]; then
            failures+=("${config_file#"${REPO_DIR}"/}: file is missing")
            continue
        fi

        while IFS= read -r line; do
            failures+=("${config_file#"${REPO_DIR}"/}: ${line}")
        done < <(
            awk '
                function finish() {
                    if (path ~ /^\/api(\/|$)/ && has_proxy) {
                        api_locations++
                        if (!has_include) {
                            printf "location %s proxies without include includes/backend-headers.conf\n", path
                        }
                    }
                    in_location = 0
                }
                {
                    text = $0
                    sub(/#.*/, "", text)
                }
                !in_location && text ~ /^[[:space:]]*location[[:space:]].*\{[[:space:]]*$/ {
                    path = text
                    sub(/^[[:space:]]*location[[:space:]]+(=|\^~|~\*?)?[[:space:]]*/, "", path)
                    sub(/[[:space:]]*\{[[:space:]]*$/, "", path)
                    in_location = 1
                    depth = 1
                    has_proxy = 0
                    has_include = 0
                    next
                }
                in_location {
                    if (text ~ /^[[:space:]]*proxy_pass[[:space:]]/) has_proxy = 1
                    if (text ~ /^[[:space:]]*include[[:space:]]+includes\/backend-headers\.conf;/) has_include = 1
                    depth += gsub(/\{/, "{", text)
                    depth -= gsub(/\}/, "}", text)
                    if (depth <= 0) finish()
                }
                END {
                    if (api_locations == 0) print "no /api proxy location found"
                }
            ' "${config_file}"
        )
    done

    if (( ${#failures[@]} > 0 )); then
        printf '%s NGINX backend header contract scan failed:\n' "${subject}" >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf '%s NGINX backend header contract scan passed\n' "${subject}"
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

# Both NGINX server configs must take the API and /api-docs routes from the
# shared includes instead of keeping their own copies, and the API include
# must reject a decoded ";" at server level.
scan_nginx_shared_route_contract() {
    local subject="$1"
    local api_include="$2"
    local docs_include="$3"
    shift 3
    local -a config_files=("$@")
    local -a failures=()
    local config_file include_name count collapsed line

    for include_name in "${api_include}" "${docs_include}"; do
        if [[ ! -f "${include_name}" ]]; then
            failures+=("${include_name#"${REPO_DIR}"/}: file is missing")
        fi
    done

    if [[ -f "${api_include}" ]]; then
        collapsed=$(sed -E -e 's/#.*$//' "${api_include}" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g')
        # shellcheck disable=SC2016 # $uri is the literal NGINX variable being matched, not a shell expansion.
        if ! grep -Eq 'if \(\$uri ~ ";"\) \{ return 400; \}' <<<"${collapsed}"; then
            failures+=("${api_include#"${REPO_DIR}"/}: missing server-level 'if (\$uri ~ \";\") { return 400; }'")
        fi
    fi

    for config_file in "${config_files[@]}"; do
        if [[ ! -f "${config_file}" ]]; then
            failures+=("${config_file#"${REPO_DIR}"/}: file is missing")
            continue
        fi

        for include_name in api-routes.conf api-docs-routes.conf; do
            count=$(sed -E 's/#.*$//' "${config_file}" |
                grep -Ec "^[[:space:]]*include[[:space:]]+includes/${include_name//./\\.};" || true)
            if (( count != 1 )); then
                failures+=("${config_file#"${REPO_DIR}"/}: expected exactly one 'include includes/${include_name};', found ${count}")
            fi
        done

        while IFS= read -r line; do
            failures+=("${config_file#"${REPO_DIR}"/}: ${line} duplicates a shared route; move it to the shared include")
        done < <(
            sed -E 's/#.*$//' "${config_file}" |
                sed -nE 's/^[[:space:]]*location[[:space:]]+((=|\^~|~\*?)[[:space:]]*)?([^[:space:]{]+).*$/\3/p' |
                grep -E '^\^?/api' | sed 's/^/location /' || true
        )
    done

    if (( ${#failures[@]} > 0 )); then
        printf '%s NGINX shared route contract scan failed:\n' "${subject}" >&2
        printf '  - %s\n' "${failures[@]}" >&2
        return 1
    fi

    printf '%s NGINX shared route contract scan passed\n' "${subject}"
}

# The ingress path-hardening EnvoyFilter must insert one RBAC DENY filter
# before ext_authz whose :path regexes deny a literal ";" and %3b at any
# percent-encoding depth before the query string and leave other paths alone.
scan_istio_ingress_path_hardening_contract() {
    local subject="$1"
    shift

    if ! "${GUARDRAIL_PYTHON}" -I - "${REPO_DIR}" "$@" <<'PATH_HARDENING_PY'
import re
import sys
from pathlib import Path

import yaml

FILTER_NAME = "ingress-path-hardening"
RBAC_TYPE = "type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC"
# Paths as the filter sees them after HCM normalize_path. A literal "..;" or
# ".;" segment never reaches the filter, because normalization resolves it.
MUST_DENY = (
    "/api/v1/transactions;x",
    "/api/v1/transactions/%2e%2e;/actuator/prometheus",
    "/api/v1/transactions%3bx",
    "/api/v1/transactions%3Bx",
    "/api/v1/transactions%253bx",
    "/api/v1/transactions%253Bx",
    "/api/v1/transactions%25253bx",
    "/api/v1/transactions%25253Bx",
    "/api/v1/transactions%2525253bx",
    "/auth/v1/%2e%2e;/internal/v1/sessions/users/x",
    "/auth/v1/%2e%2e%3b/actuator/prometheus",
    "/x;",
    "/x;?a=b",
)
MUST_ALLOW = (
    "/",
    "/api/v1/transactions",
    "/api/v1/transactions%2533",
    "/api/v1/transactions%25",
    "/api/v1/exchange-rates?targetCurrency=THB",
    "/api/v1/transactions?q=a;b",
    "/api/v1/transactions?q=%3b",
    "/auth/v1/session",
    "/oauth2/authorization/idp",
    "/login/oauth2/code/idp?code=a&state=b",
)

repo_dir = Path(sys.argv[1])
failures = []


def label(path):
    try:
        return str(Path(path).resolve().relative_to(repo_dir))
    except ValueError:
        return str(path)


def check(resource, name):
    if resource.get("apiVersion") != "networking.istio.io/v1alpha3":
        failures.append(f"{name}: unexpected apiVersion {resource.get('apiVersion')!r}")
    if (resource.get("metadata") or {}).get("namespace") != "istio-ingress":
        failures.append(f"{name}: must be in istio-ingress")
    spec = resource.get("spec") or {}
    if (spec.get("workloadSelector") or {}).get("labels") != {
        "gateway.networking.k8s.io/gateway-name": "istio-ingress-gateway"
    }:
        failures.append(f"{name}: must select only the istio-ingress-gateway workload")

    patches = spec.get("configPatches") or []
    if len(patches) != 1:
        failures.append(f"{name}: expected exactly one config patch, found {len(patches)}")
        return
    patch = patches[0]
    match = patch.get("match") or {}
    sub_filter = (
        ((((match.get("listener") or {}).get("filterChain") or {}).get("filter") or {}).get("subFilter") or {})
        .get("name")
    )
    if patch.get("applyTo") != "HTTP_FILTER" or match.get("context") != "GATEWAY":
        failures.append(f"{name}: patch must apply to a GATEWAY HTTP_FILTER")
    if sub_filter != "envoy.filters.http.ext_authz" or (patch.get("patch") or {}).get("operation") != "INSERT_BEFORE":
        failures.append(f"{name}: patch must be INSERT_BEFORE envoy.filters.http.ext_authz")

    typed = ((patch.get("patch") or {}).get("value") or {}).get("typed_config") or {}
    if typed.get("@type") != RBAC_TYPE:
        failures.append(f"{name}: filter must be the Envoy RBAC HTTP filter, found {typed.get('@type')!r}")
        return
    if set(typed) != {"@type", "rules"}:
        # shadow_rules do not enforce, and a stat prefix hides the denials
        # from the gateway stats matcher, which exports only *rbac.denied.
        failures.append(f"{name}: RBAC filter must set only @type and rules, found {sorted(typed)}")
    rules = typed.get("rules") or {}
    if rules.get("action") != "DENY":
        failures.append(f"{name}: RBAC action must be DENY, found {rules.get('action')!r}")
        return

    regexes = []
    for policy_name, policy in (rules.get("policies") or {}).items():
        if (policy or {}).get("principals") != [{"any": True}]:
            failures.append(f"{name}: policy {policy_name} must apply to any principal")
        for permission in (policy or {}).get("permissions") or []:
            header = permission.get("header") or {}
            regex = ((header.get("string_match") or {}).get("safe_regex") or {}).get("regex")
            if header.get("name") != ":path" or not isinstance(regex, str) or set(permission) != {"header"}:
                failures.append(f"{name}: policy {policy_name} has a permission that is not a :path regex")
                continue
            try:
                regexes.append(re.compile(regex))
            except re.error as error:
                failures.append(f"{name}: invalid regex {regex!r}: {error}")
    if not regexes:
        failures.append(f"{name}: no :path regex permission found")
        return

    def denied(path):
        # Envoy safe_regex matches the whole header value.
        return any(pattern.fullmatch(path) for pattern in regexes)

    for path in MUST_DENY:
        if not denied(path):
            failures.append(f"{name}: does not deny {path!r}")
    for path in MUST_ALLOW:
        if denied(path):
            failures.append(f"{name}: denies legitimate path {path!r}")


for manifest in sys.argv[2:]:
    name = label(manifest)
    try:
        documents = [
            document
            for document in yaml.safe_load_all(Path(manifest).read_text(encoding="utf-8"))
            if isinstance(document, dict)
        ]
    except (OSError, yaml.YAMLError) as error:
        failures.append(f"{name}: cannot parse: {error}")
        continue
    matches = [
        document
        for document in documents
        if document.get("kind") == "EnvoyFilter"
        and (document.get("metadata") or {}).get("name") == FILTER_NAME
    ]
    if len(matches) != 1:
        failures.append(f"{name}: expected exactly one {FILTER_NAME} EnvoyFilter, found {len(matches)}")
        continue
    check(matches[0], name)

if failures:
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)
PATH_HARDENING_PY
    then
        printf '%s ingress path hardening contract scan failed\n' "${subject}" >&2
        return 1
    fi

    printf '%s ingress path hardening contract scan passed\n' "${subject}"
}

# Usage: scan_istio_ingress_exact_origin_contract SUBJECT ROUTES_FILE... -- POLICY_FILE...
# The browser application host comes from the app, api and auth HTTPRoutes,
# so the policy must name the same host the browser lanes route.
scan_istio_ingress_exact_origin_contract() {
    local subject="$1"
    shift

    if ! "${GUARDRAIL_PYTHON}" -I - "${REPO_DIR}" "$@" <<'EXACT_ORIGIN_PY'
import sys
from pathlib import Path

import yaml

POLICY_NAME = "ingress-exact-origin"
BROWSER_ROUTES = {"app-route", "api-route", "auth-route"}
SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}
GATEWAY_SELECTOR = {"gateway.networking.k8s.io/gateway-name": "istio-ingress-gateway"}

repo_dir = Path(sys.argv[1])
arguments = sys.argv[2:]
if "--" not in arguments:
    sys.exit("usage: ROUTES_FILE... -- POLICY_FILE...")
separator = arguments.index("--")
route_files, policy_files = arguments[:separator], arguments[separator + 1:]
failures = []


def label(path):
    try:
        return str(Path(path).resolve().relative_to(repo_dir))
    except ValueError:
        return str(path)


def documents(path):
    try:
        return [
            document
            for document in yaml.safe_load_all(Path(path).read_text(encoding="utf-8"))
            if isinstance(document, dict)
        ]
    except (OSError, yaml.YAMLError) as error:
        failures.append(f"{label(path)}: cannot parse: {error}")
        return []


route_hosts = set()
seen_routes = set()
for path in route_files:
    for document in documents(path):
        name = (document.get("metadata") or {}).get("name")
        if document.get("kind") == "HTTPRoute" and name in BROWSER_ROUTES:
            seen_routes.add(name)
            route_hosts.update((document.get("spec") or {}).get("hostnames") or [])
if seen_routes != BROWSER_ROUTES or len(route_hosts) != 1:
    failures.append(
        f"browser routes {sorted(seen_routes)} must all name one hostname, found {sorted(route_hosts)}"
    )
    host = None
else:
    host = next(iter(route_hosts))
    if "*" in host or ":" in host:
        failures.append(f"browser route hostname {host!r} must be one exact host without a port")
        host = None


def check(policy, name):
    if policy.get("apiVersion") != "security.istio.io/v1":
        failures.append(f"{name}: unexpected apiVersion {policy.get('apiVersion')!r}")
    if (policy.get("metadata") or {}).get("namespace") != "istio-ingress":
        failures.append(f"{name}: must be in istio-ingress")
    spec = policy.get("spec") or {}
    if set(spec) != {"selector", "action", "rules"}:
        failures.append(f"{name}: spec must set only selector, action and rules, found {sorted(spec)}")
    if spec.get("selector") != {"matchLabels": GATEWAY_SELECTOR}:
        failures.append(f"{name}: must select only the istio-ingress-gateway workload")
    if spec.get("action") != "DENY":
        # Other ALLOW policies are additive, so an ALLOW rule cannot enforce this.
        failures.append(f"{name}: action must be DENY, found {spec.get('action')!r}")
    rules = spec.get("rules") or []
    if len(rules) != 1:
        failures.append(f"{name}: expected exactly one rule, found {len(rules)}")
        return
    rule = rules[0]
    if set(rule) != {"to", "when"}:
        # A from clause would narrow the rule to some callers.
        failures.append(f"{name}: rule must set only to and when, found {sorted(rule)}")

    operations = rule.get("to") or []
    operation = (operations[0] or {}).get("operation") or {} if len(operations) == 1 else {}
    if len(operations) != 1 or set(operation) != {"hosts", "notMethods"}:
        failures.append(f"{name}: rule needs exactly one operation with only hosts and notMethods")
    hosts = operation.get("hosts")
    if not hosts:
        failures.append(f"{name}: lost its host restriction to the browser application host")
    elif host is not None and sorted(hosts) != sorted([host, f"{host}:*"]):
        failures.append(
            f"{name}: hosts must be exactly {host!r} and {host + ':*'!r} (any port), found {hosts}"
        )
    methods = operation.get("notMethods") or []
    if len(methods) != len(SAFE_METHODS) or set(methods) != SAFE_METHODS:
        failures.append(f"{name}: notMethods must be exactly GET, HEAD and OPTIONS, found {methods}")

    conditions = rule.get("when") or []
    if len(conditions) != 1:
        # A second condition, such as Sec-Fetch-Site, would add an exception.
        failures.append(f"{name}: expected exactly one when condition, found {len(conditions)}")
        return
    condition = conditions[0] or {}
    if set(condition) != {"key", "notValues"} or condition.get("key") != "request.headers[origin]":
        failures.append(f"{name}: condition must be request.headers[origin] with only notValues")
    if host is not None and condition.get("notValues") != [f"https://{host}"]:
        failures.append(
            f"{name}: notValues must be exactly ['https://{host}'], found {condition.get('notValues')}"
        )


policies = []
for path in policy_files:
    policies.extend(
        (document, label(path))
        for document in documents(path)
        if document.get("kind") == "AuthorizationPolicy"
        and (document.get("metadata") or {}).get("name") == POLICY_NAME
    )
if len(policies) != 1:
    failures.append(f"expected exactly one {POLICY_NAME} AuthorizationPolicy, found {len(policies)}")
else:
    check(*policies[0])

if failures:
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)
EXACT_ORIGIN_PY
    then
        printf '%s ingress exact-Origin contract scan failed\n' "${subject}" >&2
        return 1
    fi

    printf '%s ingress exact-Origin contract scan passed\n' "${subject}"
}

# Args: subject egress-gateway-values-file manifest-file...
scan_istio_egress_private_destination_contract() {
    local subject="$1"
    shift

    if ! "${GUARDRAIL_PYTHON}" -I - "${REPO_DIR}" "$@" <<'EGRESS_PRIVATE_PY'
import ipaddress
import sys
from pathlib import Path

import yaml

NAMESPACE = "istio-egress"
POLICY_NAME = "allow-istio-egress-external-egress"
REQUIRED_EXCEPT = (
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "100.64.0.0/10",
)
PRIVATE = [ipaddress.ip_network(cidr) for cidr in REQUIRED_EXCEPT]
PORT = 443

repo_dir = Path(sys.argv[1])
values_file = sys.argv[2]
manifest_files = sys.argv[3:]
failures = []


def label(path):
    try:
        return str(Path(path).resolve().relative_to(repo_dir))
    except ValueError:
        return str(path)


def documents(path):
    try:
        return [
            document
            for document in yaml.safe_load_all(Path(path).read_text(encoding="utf-8"))
            if isinstance(document, dict)
        ]
    except (OSError, yaml.YAMLError) as error:
        failures.append(f"{label(path)}: cannot parse: {error}")
        return []


def allows_port(rule):
    ports = rule.get("ports") or []
    if not ports:
        return True
    for entry in ports:
        port = (entry or {}).get("port")
        if port is None or isinstance(port, str):
            # A missing port allows every port; a named port may resolve to 443.
            return True
        if port == PORT or (entry.get("endPort") is not None and port <= PORT <= entry["endPort"]):
            return True
    return False


def uncovered_private(block):
    try:
        network = ipaddress.ip_network(block.get("cidr"))
        excepts = [ipaddress.ip_network(cidr) for cidr in block.get("except") or []]
    except (TypeError, ValueError) as error:
        return [f"invalid ipBlock: {error}"]
    if network.version != 4:
        return ["an IPv6 ipBlock; the cluster is IPv4-only, so add IPv6 exclusions to this check first"]
    uncovered = []
    for private in PRIVATE:
        if not network.overlaps(private):
            continue
        remaining = [private if private.subnet_of(network) else network]
        for excluded in (e for e in excepts if e.version == 4):
            next_remaining = []
            for part in remaining:
                if part.subnet_of(excluded):
                    continue
                if excluded.subnet_of(part):
                    next_remaining.extend(part.address_exclude(excluded))
                else:
                    next_remaining.append(part)
            remaining = next_remaining
        uncovered.extend(str(part) for part in ipaddress.collapse_addresses(remaining))
    return uncovered


def check_policy(policy, name):
    spec = policy.get("spec") or {}
    policy_types = spec.get("policyTypes")
    egress = spec.get("egress") or []
    if policy_types is not None and "Egress" not in policy_types:
        return
    for index, rule in enumerate(egress):
        rule = rule or {}
        if not allows_port(rule):
            continue
        peers = rule.get("to") or []
        if not peers:
            failures.append(f"{name}: egress rule {index} allows {PORT} to every destination")
            continue
        for peer in peers:
            peer = peer or {}
            if "ipBlock" in peer:
                for gap in uncovered_private(peer.get("ipBlock") or {}):
                    failures.append(f"{name}: egress rule {index} allows {PORT} to {gap}")
            else:
                failures.append(
                    f"{name}: egress rule {index} allows {PORT} to a pod or namespace selector peer"
                )


def check_external_policy(policy, name):
    spec = policy.get("spec") or {}
    expected = [
        {
            "to": [{"ipBlock": {"cidr": "0.0.0.0/0", "except": list(REQUIRED_EXCEPT)}}],
            "ports": [{"protocol": "TCP", "port": PORT}],
        }
    ]
    if spec.get("podSelector") != {"matchLabels": {"istio": "egress-gateway"}}:
        failures.append(f"{name}: must select only istio=egress-gateway")
    if spec.get("policyTypes") != ["Egress"]:
        failures.append(f"{name}: policyTypes must be exactly [Egress]")
    if spec.get("egress") != expected:
        failures.append(
            f"{name}: egress must be exactly TCP {PORT} to 0.0.0.0/0 except {', '.join(REQUIRED_EXCEPT)}"
        )


try:
    values = yaml.safe_load(Path(values_file).read_text(encoding="utf-8")) or {}
except (OSError, yaml.YAMLError) as error:
    failures.append(f"{label(values_file)}: cannot parse: {error}")
    values = {}
if ((values.get("networkPolicy") or {}).get("enabled")) is True:
    failures.append(f"{label(values_file)}: the chart NetworkPolicy must stay disabled")

external = []
for path in manifest_files:
    for document in documents(path):
        metadata = document.get("metadata") or {}
        if document.get("kind") != "NetworkPolicy" or metadata.get("namespace") != NAMESPACE:
            continue
        # The namespace hosts only the egress gateway, so every policy in it
        # is treated as selecting the gateway.
        name = f"{label(path)}: {metadata.get('name')}"
        check_policy(document, name)
        if metadata.get("name") == POLICY_NAME:
            external.append((document, name))

if len(external) != 1:
    failures.append(f"expected exactly one {POLICY_NAME} NetworkPolicy, found {len(external)}")
else:
    check_external_policy(*external[0])

if failures:
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    sys.exit(1)
EGRESS_PRIVATE_PY
    then
        printf '%s istio-egress private-destination contract scan failed\n' "${subject}" >&2
        return 1
    fi

    printf '%s istio-egress private-destination contract scan passed\n' "${subject}"
}

collect_network_policy_manifest_files() {
    find "${REPO_DIR}/kubernetes" -type f \( -name '*.yaml' -o -name '*.yml' \) \
        -exec grep -lE "kind:[[:space:]]*['\"]?NetworkPolicy" {} + | sort
}

run_repo_pattern_scans() {
    "${IMAGE_PINNING_SCRIPT}"
    scan_namespace_psa_labels_in_files "repo" "${ACTIVE_NAMESPACE_MANIFESTS[@]}"
    scan_pipe_to_shell_guidance "repo" "${ACTIVE_GUIDANCE_PATHS[@]}"
    scan_observability_httproutes
    scan_observability_ingresses
    scan_observability_public_entry_hostnames
    scan_observability_production_inputs
    scan_grafana_values_contract
    scan_kiali_values_contract
    scan_jaeger_manifest_contract
    scan_istio_ingress_observability_allowances
    scan_istio_ext_authz_denial_contract "repo" "${ISTIOD_VALUES_FILE}"
    scan_istio_authorization_policy_contract "repo" "${ISTIO_AUTHORIZATION_POLICIES_FILE}"
    scan_istio_tracing_contract
    scan_nginx_backend_header_contract "repo" "${NGINX_BACKEND_HEADERS_INCLUDE}" "${NGINX_API_ROUTES_INCLUDE}"
    scan_nginx_shared_route_contract "repo" "${NGINX_API_ROUTES_INCLUDE}" "${NGINX_API_DOCS_ROUTES_INCLUDE}" \
        "${NGINX_SERVER_CONFIG_FILES[@]}"
    scan_istio_ingress_path_hardening_contract "repo" "${INGRESS_PATH_HARDENING_FILE}"
    scan_istio_ingress_exact_origin_contract "repo" "${BROWSER_ROUTE_FILES[@]}" -- "${INGRESS_EXACT_ORIGIN_FILE}"
    local -a network_policy_files=()
    local network_policy_file
    while IFS= read -r network_policy_file; do
        network_policy_files+=("${network_policy_file}")
    done < <(collect_network_policy_manifest_files)
    scan_istio_egress_private_destination_contract "repo" "${EGRESS_GATEWAY_VALUES_FILE}" \
        "${network_policy_files[@]}"

    KUSTOMIZE_RENDER_DIR="$(mktemp -d)"
    "${STATIC_TOOLS_BIN}/kubectl" kustomize "${PRODUCTION_INGRESS_POLICIES_OVERLAY}" \
        --load-restrictor=LoadRestrictionsNone > "${KUSTOMIZE_RENDER_DIR}/istio-ingress-policies.yaml"
    "${STATIC_TOOLS_BIN}/kubectl" kustomize "${PRODUCTION_GATEWAY_ROUTES_OVERLAY}" \
        --load-restrictor=LoadRestrictionsNone > "${KUSTOMIZE_RENDER_DIR}/gateway-routes.yaml"
    scan_istio_ingress_path_hardening_contract "production render" "${KUSTOMIZE_RENDER_DIR}/istio-ingress-policies.yaml"
    scan_istio_ingress_exact_origin_contract "production render" "${KUSTOMIZE_RENDER_DIR}/gateway-routes.yaml" -- \
        "${KUSTOMIZE_RENDER_DIR}/istio-ingress-policies.yaml"
    rm -rf "${KUSTOMIZE_RENDER_DIR}"
    KUSTOMIZE_RENDER_DIR=""
}

run_self_test() {
    local fixture_dir="${REPO_DIR}/tests/security-guardrails/fixtures/fail"
    local pipe_fixture="${fixture_dir}/pipe-to-shell-guidance.md"
    local self_test_failures=0
    local authz_fixture nginx_fixture path_fixture provider_fixture origin_fixture egress_fixture
    local -a fixture_files=()
    local line

    while IFS= read -r line; do
        fixture_files+=("${line}")
    done < <(find "${fixture_dir}" -type f | sort)

    if (( ${#fixture_files[@]} == 0 )); then
        echo "Static security guardrail self-test fixtures are missing" >&2
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

    for authz_fixture in "${fixture_dir}"/authorization-policy-*.yaml; do
        if scan_istio_authorization_policy_contract "self-test" "${authz_fixture}"; then
            echo "self-test ${authz_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for nginx_fixture in "${fixture_dir}"/nginx-backend-headers-include-*.conf; do
        if scan_nginx_backend_header_contract "self-test" "${nginx_fixture}" "${NGINX_API_ROUTES_INCLUDE}"; then
            echo "self-test ${nginx_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for nginx_fixture in "${fixture_dir}"/nginx-backend-headers-config-*.conf; do
        if scan_nginx_backend_header_contract "self-test" "${NGINX_BACKEND_HEADERS_INCLUDE}" "${nginx_fixture}"; then
            echo "self-test ${nginx_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for nginx_fixture in "${fixture_dir}"/nginx-shared-routes-include-*.conf; do
        if scan_nginx_shared_route_contract "self-test" "${nginx_fixture}" "${NGINX_API_DOCS_ROUTES_INCLUDE}" \
            "${NGINX_SERVER_CONFIG_FILES[@]}"; then
            echo "self-test ${nginx_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for nginx_fixture in "${fixture_dir}"/nginx-shared-routes-config-*.conf; do
        if scan_nginx_shared_route_contract "self-test" "${NGINX_API_ROUTES_INCLUDE}" "${NGINX_API_DOCS_ROUTES_INCLUDE}" \
            "${nginx_fixture}"; then
            echo "self-test ${nginx_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for provider_fixture in "${fixture_dir}"/istio-ext-authz-provider-*.yaml; do
        if scan_istio_ext_authz_denial_contract "self-test" "${provider_fixture}"; then
            echo "self-test ${provider_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for path_fixture in "${fixture_dir}"/ingress-path-hardening-*.yaml; do
        if scan_istio_ingress_path_hardening_contract "self-test" "${path_fixture}"; then
            echo "self-test ${path_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for origin_fixture in "${fixture_dir}"/ingress-exact-origin-*.yaml; do
        if scan_istio_ingress_exact_origin_contract "self-test" "${BROWSER_ROUTE_FILES[@]}" -- "${origin_fixture}"; then
            echo "self-test ${origin_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    for egress_fixture in "${fixture_dir}"/istio-egress-private-destination-*.yaml; do
        if scan_istio_egress_private_destination_contract "self-test" "${EGRESS_GATEWAY_VALUES_FILE}" \
            "${egress_fixture}"; then
            echo "self-test ${egress_fixture#"${REPO_DIR}"/} unexpectedly passed" >&2
            self_test_failures=$((self_test_failures + 1))
        fi
    done

    if (( self_test_failures > 0 )); then
        printf 'Static security guardrail self-test failed (%d unexpected passes)\n' "${self_test_failures}" >&2
        exit 1
    fi

    echo "Static security guardrail self-test passed"
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

    require_guardrail_python

    if (( self_test == 1 )); then
        run_self_test
        return 0
    fi

    ensure_static_tool kubeconform
    ensure_static_tool kubectl
    ensure_static_tool kube-linter
    ensure_static_tool kyverno
    ensure_static_tool helm

    log_step "Ingress headers and environment-specific CSP rendering"
    "${GUARDRAIL_PYTHON}" "${SCRIPT_DIR}/verify-edge-headers.py"

    log_step "kubeconform schema validation"
    run_kubeconform

    log_step "kube-linter security lint"
    run_kube_linter

    log_step "Kyverno policy fixtures"
    run_kyverno_tests

    log_step "Generated Tilt local-image contract replay"
    run_generated_tilt_local_image_replay

    log_step "Production Kyverno Helm render immutability"
    run_kyverno_production_helm_render_check

    log_step "Ingress rate-limit policy and gateway diagnostics renders"
    PATH="${STATIC_TOOLS_BIN}:${PATH}" "${INGRESS_RATE_LIMIT_CONFIG_VERIFIER}"

    log_step "Tilt secret/config boundary inventory"
    "${SECRETS_ONLY_SCRIPT}"

    log_step "Repo-specific pattern scans"
    run_repo_pattern_scans

    echo
    echo "Static security manifest verification passed"
}

main "$@"
