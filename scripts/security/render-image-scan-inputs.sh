#!/usr/bin/env bash
# Render the repository-owned image inputs used by exact-image security scans.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=deploy/scripts/lib/version-contract.sh
# shellcheck disable=SC1091 # The repository root is resolved above.
. "${REPO_DIR}/deploy/scripts/lib/version-contract.sh"

OUTPUT_DIR=""
LOCAL_PLATFORM=""

usage() {
    cat <<'EOF'
Usage: scripts/security/render-image-scan-inputs.sh --output-dir DIR [--local-platform PLATFORM]

Renders the production Kustomize overlays and pinned controller charts without
contacting a Kubernetes API. Helm values and observability post-renderers match
the checked-in production install path. Local-only Kind and build-image sources
are copied or extracted into a separate platform directory.

PLATFORM uses the Trivy/Docker form linux/amd64 or linux/arm64. When omitted,
the local platform is derived from uname.
EOF
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

default_local_platform() {
    local architecture

    case "$(uname -m)" in
        x86_64|amd64)
            architecture="amd64"
            ;;
        arm64|aarch64)
            architecture="arm64"
            ;;
        *)
            die "unsupported local architecture: $(uname -m)"
            ;;
    esac

    printf 'linux/%s\n' "${architecture}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --local-platform)
            LOCAL_PLATFORM="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "${OUTPUT_DIR}" ]] || die "--output-dir is required"
case "${OUTPUT_DIR}" in
    /|.|..)
        die "refusing broad output directory: ${OUTPUT_DIR}"
        ;;
esac
if [[ -e "${OUTPUT_DIR}" && ! -d "${OUTPUT_DIR}" ]]; then
    die "output path exists and is not a directory: ${OUTPUT_DIR}"
fi
if [[ -d "${OUTPUT_DIR}" ]] && [[ -n "$(find "${OUTPUT_DIR}" -mindepth 1 -print -quit)" ]]; then
    die "output directory must be empty: ${OUTPUT_DIR}"
fi
LOCAL_PLATFORM="${LOCAL_PLATFORM:-$(default_local_platform)}"
case "${LOCAL_PLATFORM}" in
    linux/amd64|linux/arm64)
        ;;
    *)
        die "unsupported local platform: ${LOCAL_PLATFORM}"
        ;;
esac

require_command helm
require_command kubectl
require_command install

ARM64_DIR="${OUTPUT_DIR}/linux-arm64"
LOCAL_DIR="${OUTPUT_DIR}/${LOCAL_PLATFORM//\//-}"
mkdir -p "${ARM64_DIR}" "${LOCAL_DIR}"

KUBE_VERSION="${PHASE4_K3S_VERSION#v}"
KUBE_VERSION="${KUBE_VERSION%%+*}"

helm template istio-base base \
    --repo "${PHASE4_ISTIO_HELM_REPO_URL}" \
    --namespace istio-system \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/istio-base.yaml"

helm template istio-cni cni \
    --repo "${PHASE4_ISTIO_HELM_REPO_URL}" \
    --namespace istio-system \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "${REPO_DIR}/kubernetes/istio/cni-common-values.yaml" \
    --values "${REPO_DIR}/kubernetes/istio/cni-k3s-values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/istio-cni.yaml"

helm template istiod istiod \
    --repo "${PHASE4_ISTIO_HELM_REPO_URL}" \
    --namespace istio-system \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "${REPO_DIR}/kubernetes/istio/istiod-values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/istiod.yaml"

helm template istio-egress-gateway gateway \
    --repo "${PHASE4_ISTIO_HELM_REPO_URL}" \
    --namespace istio-egress \
    --version "${PHASE4_ISTIO_CHART_VERSION}" \
    --values "${REPO_DIR}/kubernetes/istio/egress-gateway-values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/istio-egress-gateway.yaml"

helm template external-secrets external-secrets \
    --repo "${PHASE4_EXTERNAL_SECRETS_HELM_REPO_URL}" \
    --namespace external-secrets \
    --version "${PHASE4_EXTERNAL_SECRETS_CHART_VERSION}" \
    --values "${REPO_DIR}/deploy/helm-values/external-secrets.values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/external-secrets.yaml"

helm template cert-manager cert-manager \
    --repo "${PHASE4_CERT_MANAGER_HELM_REPO_URL}" \
    --namespace cert-manager \
    --version "${PHASE4_CERT_MANAGER_CHART_VERSION}" \
    --values "${REPO_DIR}/deploy/helm-values/cert-manager.values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/cert-manager.yaml"

helm template kyverno kyverno \
    --repo "${PHASE7_KYVERNO_HELM_REPO_URL}" \
    --namespace kyverno \
    --version "${PHASE7_KYVERNO_CHART_VERSION}" \
    --values "${REPO_DIR}/deploy/helm-values/kyverno.values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    > "${ARM64_DIR}/kyverno.yaml"

helm template prometheus-stack kube-prometheus-stack \
    --repo "${PHASE7_PROMETHEUS_STACK_HELM_REPO_URL}" \
    --namespace monitoring \
    --version "${PHASE7_PROMETHEUS_STACK_CHART_VERSION}" \
    --values "${REPO_DIR}/kubernetes/monitoring/prometheus-stack-values.yaml" \
    --values "${REPO_DIR}/kubernetes/production/monitoring/prometheus-stack-values.override.yaml" \
    --kube-version "${KUBE_VERSION}" \
    --post-renderer "${REPO_DIR}/scripts/ops/post-render-prometheus-stack.sh" \
    > "${ARM64_DIR}/prometheus-stack.yaml"

helm template kiali kiali-server \
    --repo "${PHASE7_KIALI_HELM_REPO_URL}" \
    --namespace monitoring \
    --version "${PHASE7_KIALI_CHART_VERSION}" \
    --values "${REPO_DIR}/kubernetes/monitoring/kiali-values.yaml" \
    --kube-version "${KUBE_VERSION}" \
    --post-renderer "${REPO_DIR}/scripts/ops/post-render-kiali-server.sh" \
    > "${ARM64_DIR}/kiali.yaml"

kubectl kustomize "${REPO_DIR}/kubernetes/production/apps" \
    --load-restrictor=LoadRestrictionsNone \
    > "${ARM64_DIR}/production-apps.yaml"

kubectl kustomize "${REPO_DIR}/kubernetes/production/infrastructure" \
    --load-restrictor=LoadRestrictionsNone \
    > "${ARM64_DIR}/production-infrastructure.yaml"

install -m 0644 \
    "${REPO_DIR}/kubernetes/monitoring/jaeger/deployment.yaml" \
    "${ARM64_DIR}/jaeger.yaml"

install -m 0644 \
    "${REPO_DIR}/kind-cluster-config.yaml" \
    "${LOCAL_DIR}/kind-cluster-config.yaml"

TEMURIN_REF="$(awk '$1 == "FROM" && $2 ~ /^eclipse-temurin:/ { print $2; exit }' "${REPO_DIR}/Tiltfile")"
SMOKE_BASE_REF="$(awk '$1 == "FROM" { print $2; exit }' "${REPO_DIR}/nginx/Dockerfile.prod-smoke-assets")"
[[ -n "${TEMURIN_REF}" ]] || die "could not extract the Tilt Temurin image"
[[ -n "${SMOKE_BASE_REF}" ]] || die "could not extract the production-smoke base image"

{
    printf '%s\n' 'apiVersion: dependency-automation.budgetanalyzer.org/v1'
    printf '%s\n' 'kind: ImageScanSource'
    printf '%s\n' 'metadata:'
    printf '%s\n' '  name: tilt-temurin-base'
    printf 'image: %s\n' "${TEMURIN_REF}"
    printf '%s\n' '---'
    printf '%s\n' 'apiVersion: dependency-automation.budgetanalyzer.org/v1'
    printf '%s\n' 'kind: ImageScanSource'
    printf '%s\n' 'metadata:'
    printf '%s\n' '  name: frontend-production-smoke-base'
    printf 'image: %s\n' "${SMOKE_BASE_REF}"
} > "${LOCAL_DIR}/local-build-images.yaml"

printf 'Rendered exact-image scan inputs into %s\n' "${OUTPUT_DIR}"
printf 'Production/controller platform: linux/arm64\n'
printf 'Local-only platform: %s\n' "${LOCAL_PLATFORM}"
