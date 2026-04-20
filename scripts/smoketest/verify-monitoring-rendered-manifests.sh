#!/usr/bin/env bash
# Render and validate the monitoring stack before Helm install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=deploy/scripts/lib/phase-4-version-contract.sh
source "${REPO_DIR}/deploy/scripts/lib/phase-4-version-contract.sh"

CHART="prometheus-community/kube-prometheus-stack"
CHART_VERSION="${PHASE7_PROMETHEUS_STACK_CHART_VERSION}"
KIALI_CHART="kiali/kiali-server"
KIALI_CHART_VERSION="${PHASE7_KIALI_CHART_VERSION}"
NAMESPACE="monitoring"
RELEASE_NAME="prometheus-stack"
KIALI_RELEASE_NAME="kiali"
VALUES_FILE="${REPO_DIR}/kubernetes/monitoring/prometheus-stack-values.yaml"
KIALI_VALUES_FILE="${REPO_DIR}/kubernetes/monitoring/kiali-values.yaml"
KIALI_POST_RENDERER="${REPO_DIR}/scripts/ops/post-render-kiali-server.sh"
NAMESPACE_FILE="${REPO_DIR}/kubernetes/monitoring/namespace.yaml"
JAEGER_DIR="${REPO_DIR}/kubernetes/monitoring/jaeger"
JAEGER_DEPLOYMENT_FILE="${JAEGER_DIR}/deployment.yaml"
JAEGER_SERVICES_FILE="${JAEGER_DIR}/services.yaml"

log_step() {
    printf '\n==> %s\n' "$1"
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

search_file() {
    local pattern file

    pattern="$1"
    file="$2"

    if command -v rg >/dev/null 2>&1; then
        rg -n "${pattern}" "${file}"
    else
        grep -En "${pattern}" "${file}"
    fi
}

extract_workloads() {
    local input_file output_file

    input_file="$1"
    output_file="$2"

    awk '
        BEGIN {
            RS = "---"
            ORS = "---\n"
        }
        $0 ~ /(^|\n)kind:[[:space:]]*(Deployment|StatefulSet|DaemonSet|Job)($|\n)/ {
            print $0
        }
    ' "${input_file}" > "${output_file}"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

render_file="${tmp_dir}/prometheus-stack-render.yaml"
workload_file="${tmp_dir}/prometheus-stack-workloads.yaml"
kiali_render_file="${tmp_dir}/kiali-render.yaml"
kiali_workload_file="${tmp_dir}/kiali-workloads.yaml"

log_step "Refreshing prometheus-community Helm repo metadata"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update prometheus-community >/dev/null

log_step "Refreshing kiali Helm repo metadata"
helm repo add kiali https://kiali.org/helm-charts --force-update >/dev/null
helm repo update kiali >/dev/null

log_step "Checking the monitoring namespace manifest"
kubectl apply --dry-run=server -f "${NAMESPACE_FILE}" >/dev/null
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 || fail "Namespace ${NAMESPACE} does not exist. Apply kubernetes/monitoring/namespace.yaml first."

log_step "Server-dry-running Jaeger manifests"
kubectl apply --dry-run=server -f "${JAEGER_DIR}" >/dev/null

log_step "Rendering ${CHART} ${CHART_VERSION}"
helm template "${RELEASE_NAME}" "${CHART}" \
    --namespace "${NAMESPACE}" \
    --version "${CHART_VERSION}" \
    --values "${VALUES_FILE}" \
    > "${render_file}"

log_step "Rendering ${KIALI_CHART} ${KIALI_CHART_VERSION}"
helm template "${KIALI_RELEASE_NAME}" "${KIALI_CHART}" \
    --namespace "${NAMESPACE}" \
    --version "${KIALI_CHART_VERSION}" \
    --values "${KIALI_VALUES_FILE}" \
    --post-renderer "${KIALI_POST_RENDERER}" \
    > "${kiali_render_file}"

log_step "Checking rendered and checked-in image pinning"
mapfile -t rendered_images < <(
    grep -hE '^[[:space:]]*image:[[:space:]]*' \
        "${render_file}" \
        "${kiali_render_file}" \
        "${JAEGER_DEPLOYMENT_FILE}" \
        | sed -E 's/^[[:space:]]*image:[[:space:]]*"?([^"]+)"?/\1/' \
        | sort -u
)

(( ${#rendered_images[@]} > 0 )) || fail "No rendered workload images were found."

for image in "${rendered_images[@]}"; do
    [[ "${image}" =~ @sha256:[a-f0-9]{64}$ ]] || fail "Rendered image is not digest-pinned: ${image}"
done

log_step "Checking rendered pod hardening markers"
if search_file 'automountServiceAccountToken:[[:space:]]*true' "${render_file}" >/dev/null; then
    fail "Rendered manifests still contain automountServiceAccountToken: true."
fi

if search_file '(^|[[:space:]])hostPath:' "${render_file}" >/dev/null; then
    fail "Rendered manifests still contain hostPath volumes."
fi

if search_file 'host(Network|PID|IPC):[[:space:]]*true' "${render_file}" >/dev/null; then
    fail "Rendered manifests still contain host namespace access."
fi

if search_file '^kind:[[:space:]]*DaemonSet$' "${render_file}" >/dev/null; then
    fail "Rendered manifests still contain a DaemonSet; node-exporter should be disabled."
fi

log_step "Checking checked-in Jaeger contract"
if [[ "$(grep -Ec '^[[:space:]]*type:[[:space:]]*ClusterIP([[:space:]]|$)' "${JAEGER_SERVICES_FILE}")" -ne 2 ]]; then
    fail "Checked-in Jaeger services do not remain ClusterIP-only."
fi

if grep -Eq '^[[:space:]]*type:[[:space:]]*(LoadBalancer|NodePort|ExternalName)([[:space:]]|$)' "${JAEGER_SERVICES_FILE}"; then
    fail "Checked-in Jaeger services expose a non-ClusterIP service type."
fi

if ! grep -Eq 'name:[[:space:]]*jaeger-collector' "${JAEGER_SERVICES_FILE}" || \
    ! grep -Eq 'name:[[:space:]]*jaeger-query' "${JAEGER_SERVICES_FILE}"; then
    fail "Checked-in Jaeger services are missing the collector or query service."
fi

if grep -Eq '^kind:[[:space:]]*(Ingress|HTTPRoute|Gateway)($|[[:space:]])' "${JAEGER_DIR}"/*.yaml; then
    fail "Checked-in Jaeger manifests create an ingress, HTTPRoute, or Gateway."
fi

if grep -Eiq '\b(elasticsearch|opensearch)\b' "${JAEGER_DIR}"/*.yaml; then
    fail "Checked-in Jaeger manifests depend on Elasticsearch/OpenSearch."
fi

log_step "Checking rendered Kiali contract"
if ! grep -Eq 'strategy:[[:space:]]*token' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not use token auth."
fi

if grep -Eq 'strategy:[[:space:]]*anonymous' "${kiali_render_file}"; then
    fail "Rendered Kiali config enables anonymous auth."
fi

if ! grep -Eq 'view_only_mode:[[:space:]]*true' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not enable view_only_mode."
fi

if ! grep -Eq 'cluster_wide_access:[[:space:]]*false' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not disable cluster-wide access."
fi

if ! grep -Eq 'type:[[:space:]]*ClusterIP' "${kiali_render_file}"; then
    fail "Rendered Kiali service does not remain ClusterIP-only."
fi

if grep -Eq 'type:[[:space:]]*(LoadBalancer|NodePort|ExternalName)([[:space:]]|$)' "${kiali_render_file}"; then
    fail "Rendered Kiali manifests expose a non-ClusterIP service type."
fi

if grep -Eq '^kind:[[:space:]]*(Ingress|HTTPRoute|Gateway)($|[[:space:]])' "${kiali_render_file}"; then
    fail "Rendered Kiali manifests create an ingress, HTTPRoute, or Gateway."
fi

if grep -Eq 'external_url:[[:space:]]*https?://' "${kiali_render_file}"; then
    fail "Rendered Kiali config sets a public external_url."
fi

if grep -Eq 'kind:[[:space:]]*Cluster(Role|RoleBinding)' "${kiali_render_file}"; then
    fail "Rendered Kiali manifests request cluster-wide RBAC."
fi

if ! grep -Eq 'automountServiceAccountToken:[[:space:]]*false' "${kiali_render_file}"; then
    fail "Rendered Kiali Deployment does not explicitly disable service account token automount."
fi

if ! grep -Eq 'seccompProfile:' "${kiali_render_file}" || ! grep -Eq 'type:[[:space:]]*RuntimeDefault' "${kiali_render_file}"; then
    fail "Rendered Kiali Deployment does not set pod-level RuntimeDefault seccomp."
fi

if ! grep -Eq 'name:[[:space:]]*kiali-api-token' "${kiali_render_file}"; then
    fail "Rendered Kiali Deployment does not mount the explicit projected API token."
fi

log_step "Server-dry-running rendered workload objects"
extract_workloads "${render_file}" "${workload_file}"
[[ -s "${workload_file}" ]] || fail "No rendered Deployment/StatefulSet/DaemonSet/Job objects were found."
dry_run_stderr="${tmp_dir}/kubectl-dry-run.stderr"
if ! kubectl apply --dry-run=server -f "${workload_file}" >/dev/null 2>"${dry_run_stderr}"; then
    cat "${dry_run_stderr}" >&2
    fail "kubectl apply --dry-run=server rejected the rendered workload objects."
fi

log_step "Server-dry-running rendered Kiali workload objects"
extract_workloads "${kiali_render_file}" "${kiali_workload_file}"
[[ -s "${kiali_workload_file}" ]] || fail "No rendered Kiali Deployment/StatefulSet/DaemonSet/Job objects were found."
if ! kubectl apply --dry-run=server -f "${kiali_workload_file}" >/dev/null 2>"${dry_run_stderr}"; then
    cat "${dry_run_stderr}" >&2
    fail "kubectl apply --dry-run=server rejected the rendered Kiali workload objects."
fi

printf '\nMonitoring render verification passed.\n'
