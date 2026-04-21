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
PROMETHEUS_POST_RENDERER="${REPO_DIR}/scripts/ops/post-render-prometheus-stack.sh"
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
    --post-renderer "${PROMETHEUS_POST_RENDERER}" \
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

log_step "Checking rendered Prometheus Operator namespace scoping"
if ! search_file '^[[:space:]]*-[[:space:]]*--namespaces=monitoring,default$' "${render_file}" >/dev/null; then
    fail "Rendered Prometheus Operator does not scope watched namespaces to monitoring,default."
fi

if ! search_file '^[[:space:]]*-[[:space:]]*--alertmanager-instance-namespaces=monitoring$' "${render_file}" >/dev/null; then
    fail "Rendered Prometheus Operator does not scope Alertmanager instance namespaces to monitoring."
fi

if ! search_file '^[[:space:]]*-[[:space:]]*--alertmanager-config-namespaces=monitoring$' "${render_file}" >/dev/null; then
    fail "Rendered Prometheus Operator does not scope Alertmanager config namespaces to monitoring."
fi

if ! search_file '^[[:space:]]*-[[:space:]]*--prometheus-instance-namespaces=monitoring$' "${render_file}" >/dev/null; then
    fail "Rendered Prometheus Operator does not scope Prometheus instance namespaces to monitoring."
fi

if ! search_file '^[[:space:]]*-[[:space:]]*--thanos-ruler-instance-namespaces=monitoring$' "${render_file}" >/dev/null; then
    fail "Rendered Prometheus Operator does not scope ThanosRuler instance namespaces to monitoring."
fi

log_step "Checking rendered Prometheus Operator RBAC reduction"
python3 - <<'PY' "${render_file}"
import sys
from pathlib import Path

import yaml

render_path = Path(sys.argv[1])
docs = [
    document
    for document in yaml.safe_load_all(render_path.read_text(encoding="utf-8"))
    if isinstance(document, dict)
]

objects = {}
subjects_for = {}

for document in docs:
    kind = document.get("kind")
    metadata = document.get("metadata") or {}
    name = metadata.get("name")
    namespace = metadata.get("namespace")
    if not kind or not name:
        continue
    objects[(kind, name, namespace)] = document
    if kind in {"RoleBinding", "ClusterRoleBinding"}:
        for subject in document.get("subjects") or []:
            if not isinstance(subject, dict):
                continue
            if subject.get("kind") != "ServiceAccount":
                continue
            if (
                subject.get("name") == "prometheus-stack-kube-prom-operator"
                and subject.get("namespace") == "monitoring"
            ):
                subjects_for[(kind, name, namespace)] = document


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def require_object(kind: str, name: str, namespace: str | None = None):
    obj = objects.get((kind, name, namespace))
    if obj is None:
        scope = namespace if namespace is not None else "cluster"
        fail(f"Rendered manifest is missing {kind}/{name} in {scope}.")
    return obj


if ("ClusterRole", "prometheus-stack-kube-prom-operator", None) in objects:
    fail("Rendered manifest still contains the upstream broad operator ClusterRole.")

if ("ClusterRoleBinding", "prometheus-stack-kube-prom-operator", None) in objects:
    fail("Rendered manifest still contains the upstream broad operator ClusterRoleBinding.")

cluster_role = require_object(
    "ClusterRole",
    "prometheus-stack-kube-prom-operator-cluster-read",
)
cluster_role_binding = require_object(
    "ClusterRoleBinding",
    "prometheus-stack-kube-prom-operator-cluster-read",
)
monitoring_role = require_object(
    "Role",
    "prometheus-stack-kube-prom-operator-monitoring",
    "monitoring",
)
require_object(
    "RoleBinding",
    "prometheus-stack-kube-prom-operator-monitoring",
    "monitoring",
)
default_role = require_object(
    "Role",
    "prometheus-stack-kube-prom-operator-default-read",
    "default",
)
require_object(
    "RoleBinding",
    "prometheus-stack-kube-prom-operator-default-read",
    "default",
)

cluster_binding_ref = cluster_role_binding.get("roleRef") or {}
if cluster_binding_ref.get("kind") != "ClusterRole" or \
        cluster_binding_ref.get("name") != "prometheus-stack-kube-prom-operator-cluster-read":
    fail("Rendered operator ClusterRoleBinding does not point to the repo-owned cluster-read role.")

approved_cluster_resources = {
    ("", "namespaces", ("get", "list", "watch")),
    ("", "nodes", ("list", "watch")),
    ("networking.k8s.io", "ingresses", ("get", "list", "watch")),
    ("storage.k8s.io", "storageclasses", ("get",)),
}
actual_cluster_resources = set()

for rule in cluster_role.get("rules") or []:
    api_groups = rule.get("apiGroups") or [""]
    resources = rule.get("resources") or []
    verbs = tuple(rule.get("verbs") or [])
    for api_group in api_groups:
        for resource in resources:
            actual_cluster_resources.add((api_group, resource, verbs))

if actual_cluster_resources != approved_cluster_resources:
    fail(
        "Rendered operator cluster-scoped RBAC drifted from the approved "
        f"read-only set: {sorted(actual_cluster_resources)!r}"
    )

for forbidden in ("secrets", "configmaps", "services", "endpoints", "endpointslices", "pods"):
    if forbidden in {
        resource
        for _, resource, _ in actual_cluster_resources
    }:
        fail(f"Rendered operator cluster-scoped RBAC still grants {forbidden}.")

default_rules = default_role.get("rules") or []
default_api_groups = {
    api_group
    for rule in default_rules
    for api_group in (rule.get("apiGroups") or [])
}
default_resources = {
    resource
    for rule in default_rules
    for resource in (rule.get("resources") or [])
}
default_verbs = {
    verb
    for rule in default_rules
    for verb in (rule.get("verbs") or [])
}

if "monitoring.coreos.com" not in default_api_groups:
    fail("Rendered default namespace operator Role no longer grants monitoring CR reads.")

if {"create", "update", "patch", "delete"} & default_verbs - {"create", "patch"}:
    fail("Rendered default namespace operator Role regained broad mutation verbs.")

if {"secrets", "configmaps", "services", "endpoints", "endpointslices", "pods", "statefulsets"} & default_resources:
    fail("Rendered default namespace operator Role regained non-CR resource access.")

monitoring_resources = {
    resource
    for rule in (monitoring_role.get("rules") or [])
    for resource in (rule.get("resources") or [])
}
if "secrets" not in monitoring_resources or "statefulsets" not in monitoring_resources:
    fail("Rendered monitoring namespace operator Role is missing expected owned-resource access.")

bound_objects = {
    (kind, name, namespace)
    for kind, name, namespace in subjects_for
}
expected_bound_objects = {
    ("ClusterRoleBinding", "prometheus-stack-kube-prom-operator-cluster-read", None),
    ("RoleBinding", "prometheus-stack-kube-prom-operator-monitoring", "monitoring"),
    ("RoleBinding", "prometheus-stack-kube-prom-operator-default-read", "default"),
}
if bound_objects != expected_bound_objects:
    fail(
        "Rendered operator service account bindings drifted from the approved "
        f"set: {sorted(bound_objects)!r}"
    )
PY

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

if ! grep -Eq 'internal_url:[[:space:]]*http://jaeger-query\.monitoring:16685/jaeger' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not keep the Jaeger gRPC query URL."
fi

if ! grep -Eq 'health_check_url:[[:space:]]*http://jaeger-query\.monitoring:16686/jaeger' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not keep the Jaeger HTTP health URL."
fi

if ! grep -Eq 'use_grpc:[[:space:]]*true' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not keep Jaeger gRPC enabled."
fi

if ! grep -Eq 'disable_version_check:[[:space:]]*true' "${kiali_render_file}"; then
    fail "Rendered Kiali config does not disable the Jaeger version check."
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
