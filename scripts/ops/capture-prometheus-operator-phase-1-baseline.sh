#!/usr/bin/env bash
# Capture the current Prometheus Operator RBAC and permission baseline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck disable=SC1091
# Repo-relative helper; resolved from REPO_DIR at runtime.
# shellcheck source=deploy/scripts/lib/phase-4-version-contract.sh
source "${REPO_DIR}/deploy/scripts/lib/phase-4-version-contract.sh"

CHART="prometheus-community/kube-prometheus-stack"
RELEASE_NAME="prometheus-stack"
NAMESPACE="monitoring"
VALUES_FILE="${REPO_DIR}/kubernetes/monitoring/prometheus-stack-values.yaml"
OPERATOR_SERVICE_ACCOUNT="prometheus-stack-kube-prom-operator"
OUTPUT_FILE="${REPO_DIR}/docs/research/prometheus-operator-least-privilege-phase-1-baseline.md"
TMP_DIR=""

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/capture-prometheus-operator-phase-1-baseline.sh [options]

Renders the current kube-prometheus-stack manifests, extracts the Prometheus
Operator RBAC objects, builds a representative kubectl auth can-i matrix for
the operator service account, and writes a checked-in Markdown baseline
document.

Options:
  --output PATH   Output Markdown path. Relative paths resolve from the repo
                  root. Default:
                  docs/research/prometheus-operator-least-privilege-phase-1-baseline.md
  -h, --help      Show this help text.
EOF
}

cleanup() {
    local exit_code=$?

    if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
        rm -rf "${TMP_DIR}"
    fi

    exit "${exit_code}"
}

trap cleanup EXIT

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

log_step() {
    printf '\n==> %s\n' "$1"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        fail "required command not found: $1"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_FILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'ERROR: unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${OUTPUT_FILE}" != /* ]]; then
    OUTPUT_FILE="${REPO_DIR}/${OUTPUT_FILE}"
fi

require_command helm
require_command kubectl
require_command python3

TMP_DIR="$(mktemp -d)"
RENDER_FILE="${TMP_DIR}/prometheus-stack-render.yaml"
RBAC_FILE="${TMP_DIR}/operator-rbac.yaml"
RBAC_SUMMARY_FILE="${TMP_DIR}/operator-rbac-summary.json"
CAN_I_FILE="${TMP_DIR}/operator-can-i.tsv"
CAPTURE_DATE="$(date -u +%F)"

mkdir -p "$(dirname "${OUTPUT_FILE}")"

log_step "Checking cluster access"
kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1 \
    || fail "cannot reach Kubernetes API or namespace ${NAMESPACE}"
kubectl get -n "${NAMESPACE}" "serviceaccount/${OPERATOR_SERVICE_ACCOUNT}" >/dev/null 2>&1 \
    || fail "service account ${NAMESPACE}/${OPERATOR_SERVICE_ACCOUNT} does not exist"

log_step "Refreshing prometheus-community Helm repo metadata"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo update prometheus-community >/dev/null

log_step "Rendering ${CHART} ${PHASE7_PROMETHEUS_STACK_CHART_VERSION}"
helm template "${RELEASE_NAME}" "${CHART}" \
    --namespace "${NAMESPACE}" \
    --version "${PHASE7_PROMETHEUS_STACK_CHART_VERSION}" \
    --values "${VALUES_FILE}" \
    > "${RENDER_FILE}"

log_step "Extracting operator RBAC from the rendered chart"
python3 - <<'PY' \
    "${RENDER_FILE}" \
    "${RBAC_FILE}" \
    "${RBAC_SUMMARY_FILE}" \
    "${OPERATOR_SERVICE_ACCOUNT}" \
    "${NAMESPACE}"
import json
import sys
from pathlib import Path

import yaml

render_path = Path(sys.argv[1])
rbac_path = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
service_account_name = sys.argv[4]
service_account_namespace = sys.argv[5]

selected = []
summary = {
    "objects": [],
    "rule_summary": [],
}

for document in yaml.safe_load_all(render_path.read_text(encoding="utf-8")):
    if not isinstance(document, dict):
        continue

    kind = document.get("kind")
    if kind not in {"ClusterRole", "ClusterRoleBinding", "Role", "RoleBinding"}:
        continue

    metadata = document.get("metadata") or {}
    name = metadata.get("name") or ""
    subjects = document.get("subjects") or []
    matches_subject = any(
        isinstance(subject, dict)
        and subject.get("kind") == "ServiceAccount"
        and subject.get("name") == service_account_name
        and subject.get("namespace") == service_account_namespace
        for subject in subjects
    )

    if name != service_account_name and not matches_subject:
        continue

    selected.append(document)
    summary["objects"].append({"kind": kind, "name": name})

    if kind == "ClusterRole":
        for rule in document.get("rules") or []:
            summary["rule_summary"].append(
                {
                    "apiGroups": rule.get("apiGroups") or [],
                    "resources": rule.get("resources") or [],
                    "verbs": rule.get("verbs") or [],
                }
            )

if not selected:
    raise SystemExit("No Prometheus Operator RBAC objects were found in the rendered chart.")

rbac_path.write_text(
    yaml.safe_dump_all(selected, sort_keys=False),
    encoding="utf-8",
)
summary_path.write_text(
    json.dumps(summary, indent=2),
    encoding="utf-8",
)
PY

log_step "Building kubectl auth can-i matrix for ${OPERATOR_SERVICE_ACCOUNT}"
{
    printf 'scope\tverb\tresource\treason\tallowed\n'

    while IFS='|' read -r scope verb resource reason; do
        [[ -n "${scope}" ]] || continue

        if [[ "${scope}" == "cluster" ]]; then
            allowed="$(kubectl auth can-i \
                --as="system:serviceaccount:${NAMESPACE}:${OPERATOR_SERVICE_ACCOUNT}" \
                "${verb}" "${resource}")"
        else
            allowed="$(kubectl auth can-i \
                --as="system:serviceaccount:${NAMESPACE}:${OPERATOR_SERVICE_ACCOUNT}" \
                --namespace "${scope}" \
                "${verb}" "${resource}")"
        fi

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${scope}" "${verb}" "${resource}" "${reason}" "${allowed}"
    done <<'EOF'
monitoring|get|servicemonitors.monitoring.coreos.com|Current monitoring CR reads in the owned namespace
monitoring|create|statefulsets.apps|Prometheus StatefulSet reconciliation in monitoring
monitoring|get|secrets|Prometheus config secret access in monitoring
monitoring|create|services|Operator-managed Service reconciliation in monitoring
monitoring|delete|endpointslices.discovery.k8s.io|Operator-managed EndpointSlice cleanup in monitoring
default|get|servicemonitors.monitoring.coreos.com|Current cross-namespace ServiceMonitor reads
default|create|servicemonitors.monitoring.coreos.com|Baseline check for cross-namespace monitoring CR mutation
default|get|secrets|Baseline check for cross-namespace secret reads
default|create|services|Baseline check for cross-namespace Service mutation
default|delete|pods|Baseline check for cross-namespace Pod delete
default|create|statefulsets.apps|Baseline check for cross-namespace StatefulSet mutation
infrastructure|get|servicemonitors.monitoring.coreos.com|Unrelated-namespace monitoring CR read baseline
infrastructure|create|servicemonitors.monitoring.coreos.com|Unrelated-namespace monitoring CR mutation baseline
infrastructure|get|secrets|Unrelated-namespace secret read baseline
infrastructure|create|services|Unrelated-namespace Service mutation baseline
infrastructure|delete|pods|Unrelated-namespace Pod delete baseline
istio-system|get|servicemonitors.monitoring.coreos.com|Control-plane namespace monitoring CR read baseline
istio-system|get|secrets|Control-plane namespace secret read baseline
istio-system|create|services|Control-plane namespace Service mutation baseline
cluster|list|namespaces|Cluster namespace discovery
cluster|watch|nodes|Cluster node watch
cluster|get|storageclasses.storage.k8s.io|Cluster StorageClass read
cluster|watch|ingresses.networking.k8s.io|Cluster Ingress watch
EOF
} > "${CAN_I_FILE}"

log_step "Writing Phase 1 baseline document"
python3 - <<'PY' \
    "${RBAC_SUMMARY_FILE}" \
    "${RBAC_FILE}" \
    "${CAN_I_FILE}" \
    "${OUTPUT_FILE}" \
    "${CAPTURE_DATE}" \
    "${PHASE7_PROMETHEUS_STACK_CHART_VERSION}"
import csv
import json
import sys
from pathlib import Path

summary = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
rbac_yaml = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
can_i_rows = list(csv.DictReader(Path(sys.argv[3]).open(encoding="utf-8"), delimiter="\t"))
output_path = Path(sys.argv[4])
capture_date = sys.argv[5]
chart_version = sys.argv[6]

scope_order = {"monitoring": 0, "default": 1, "infrastructure": 2, "istio-system": 3, "cluster": 4}
can_i_rows.sort(key=lambda row: (scope_order.get(row["scope"], 99), row["verb"], row["resource"]))

rule_summary = summary["rule_summary"]
all_yes_outside_monitoring = [
    row for row in can_i_rows
    if row["scope"] not in {"monitoring", "cluster"} and row["allowed"] == "yes"
]

def rule_matches(resources, verbs=None, api_groups=None):
    wanted_resources = set(resources)
    wanted_verbs = set(verbs or [])
    wanted_api_groups = set(api_groups or [])

    for rule in rule_summary:
        rule_resources = set(rule["resources"])
        rule_verbs = set(rule["verbs"])
        rule_api_groups = set(rule["apiGroups"])

        if not wanted_resources.intersection(rule_resources):
            continue
        if wanted_verbs and not (wanted_verbs.intersection(rule_verbs) or "*" in rule_verbs):
            continue
        if wanted_api_groups and not wanted_api_groups.intersection(rule_api_groups):
            continue
        return True
    return False

baseline_findings = []
namespaced_objects = [
    obj for obj in summary["objects"]
    if obj["kind"] in {"Role", "RoleBinding"}
]

baseline_findings.append(
    "The current render still emits a single cluster-scoped operator binding: "
    f"{len(summary['objects']) - len(namespaced_objects)} cluster-scoped object(s) and "
    f"{len(namespaced_objects)} namespaced Role/RoleBinding object(s)."
)

if rule_matches({"servicemonitors", "podmonitors", "prometheuses", "prometheusrules"}, api_groups={"monitoring.coreos.com"}):
    baseline_findings.append(
        "The operator ClusterRole still grants broad `monitoring.coreos.com` access instead of a read-only split for current CR consumers."
    )

if rule_matches({"statefulsets"}, verbs={"create", "update", "delete", "*"}, api_groups={"apps"}):
    baseline_findings.append(
        "The operator can mutate `statefulsets.apps`, which matches Prometheus reconciliation in `monitoring` but is not namespaced by the current RBAC layer."
    )

if rule_matches({"configmaps", "secrets"}, verbs={"get", "list", "watch", "create", "update", "delete", "*"}, api_groups={""}):
    baseline_findings.append(
        "The operator still has cluster-wide `configmaps` and `secrets` authority."
    )

if rule_matches({"services", "endpoints", "endpointslices"}, verbs={"create", "update", "delete", "*"}):
    baseline_findings.append(
        "The operator still has cross-namespace mutation on `services`, `endpoints`, and `endpointslices`."
    )

if rule_matches({"pods"}, verbs={"delete"}, api_groups={""}):
    baseline_findings.append(
        "The operator still holds `pods delete`, which is broader than the expected final posture."
    )

if rule_matches({"nodes", "namespaces", "storageclasses", "ingresses"}, verbs={"get", "list", "watch"}):
    baseline_findings.append(
        "The operator still depends on cluster-scoped reads for `nodes`, `namespaces`, `storageclasses`, and `ingresses`."
    )

if all_yes_outside_monitoring:
    examples = ", ".join(
        f"`{row['scope']} {row['verb']} {row['resource']}`"
        for row in all_yes_outside_monitoring[:4]
    )
    baseline_findings.append(
        "Live `kubectl auth can-i` confirms the service account can operate outside `monitoring`, including "
        f"{examples}."
    )

lines = []
lines.append("# Prometheus Operator Least-Privilege Phase 1 Baseline")
lines.append("")
lines.append(f"**Date:** {capture_date}")
lines.append("**Status:** Baseline evidence for Phase 1 of "
             "[Prometheus Operator Least Privilege](../plans/prometheus-operator-least-privilege-plan.md).")
lines.append("**Generated by:** `./scripts/ops/capture-prometheus-operator-phase-1-baseline.sh`")
lines.append("")
lines.append(
    "This note captures the current `kube-prometheus-stack` operator RBAC and live authorization evidence "
    "before any least-privilege reduction work."
)
lines.append("")
lines.append("## Baseline Findings")
lines.append("")
for finding in baseline_findings:
    lines.append(f"- {finding}")
lines.append("")
lines.append("## Rendered Operator RBAC")
lines.append("")
lines.append(
    f"Chart render: `{chart_version}` from `prometheus-community/kube-prometheus-stack` with "
    "`kubernetes/monitoring/prometheus-stack-values.yaml`."
)
lines.append("")
lines.append("Rendered objects:")
for obj in summary["objects"]:
    lines.append(f"- `{obj['kind']}/{obj['name']}`")
lines.append("")
lines.append("### Rule Summary")
lines.append("")
lines.append("| API Groups | Resources | Verbs |")
lines.append("| --- | --- | --- |")
for rule in rule_summary:
    api_groups = ", ".join(rule["apiGroups"]) or "(core)"
    resources = ", ".join(rule["resources"])
    verbs = ", ".join(rule["verbs"])
    lines.append(f"| `{api_groups}` | `{resources}` | `{verbs}` |")
lines.append("")
lines.append("### Rendered YAML")
lines.append("")
lines.append("```yaml")
lines.append(rbac_yaml)
lines.append("```")
lines.append("")
lines.append("## `kubectl auth can-i` Matrix")
lines.append("")
lines.append(
    "Service account under test: "
    "`system:serviceaccount:monitoring:prometheus-stack-kube-prom-operator`."
)
lines.append("")
lines.append("| Scope | Verb | Resource | Why This Check Exists | Allowed |")
lines.append("| --- | --- | --- | --- | --- |")
for row in can_i_rows:
    lines.append(
        f"| `{row['scope']}` | `{row['verb']}` | `{row['resource']}` | {row['reason']} | `{row['allowed']}` |"
    )
lines.append("")
lines.append("## Manual Runtime Follow-Up")
lines.append("")
lines.append(
    "Run `./scripts/smoketest/verify-monitoring-runtime.sh` separately after Tilt has brought up the full app "
    "stack. Phase 1 still requires that runtime result as evidence, but the capture script no longer blocks on it."
)
lines.append("")

output_path.write_text("\n".join(lines), encoding="utf-8")
PY

printf 'Wrote %s\n' "${OUTPUT_FILE}"
