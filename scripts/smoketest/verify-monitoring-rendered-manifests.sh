#!/usr/bin/env bash
# Render and validate the monitoring stack before Helm install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CHART="prometheus-community/kube-prometheus-stack"
CHART_VERSION="83.4.0"
NAMESPACE="monitoring"
RELEASE_NAME="prometheus-stack"
VALUES_FILE="${REPO_DIR}/kubernetes/monitoring/prometheus-stack-values.yaml"
NAMESPACE_FILE="${REPO_DIR}/kubernetes/monitoring/namespace.yaml"
JAEGER_DIR="${REPO_DIR}/kubernetes/monitoring/jaeger"

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

log_step "Refreshing prometheus-community Helm repo metadata"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update prometheus-community >/dev/null

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

log_step "Checking rendered image pinning"
mapfile -t rendered_images < <(
    grep -E '^[[:space:]]*image:[[:space:]]*' "${render_file}" \
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

log_step "Server-dry-running rendered workload objects"
extract_workloads "${render_file}" "${workload_file}"
[[ -s "${workload_file}" ]] || fail "No rendered Deployment/StatefulSet/DaemonSet/Job objects were found."
dry_run_stderr="${tmp_dir}/kubectl-dry-run.stderr"
if ! kubectl apply --dry-run=server -f "${workload_file}" >/dev/null 2>"${dry_run_stderr}"; then
    cat "${dry_run_stderr}" >&2
    fail "kubectl apply --dry-run=server rejected the rendered workload objects."
fi

printf '\nMonitoring render verification passed.\n'
