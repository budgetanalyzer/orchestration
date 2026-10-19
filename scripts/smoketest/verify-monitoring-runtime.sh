#!/usr/bin/env bash
# Runtime verification for Prometheus scrape health, dashboard inputs, and Kiali health.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_SELECTOR='app.kubernetes.io/name=prometheus,app.kubernetes.io/managed-by=prometheus-operator,operator.prometheus.io/name=prometheus-stack-kube-prom-prometheus'
PROMETHEUS_CONTAINER="prometheus"
PROMETHEUS_URL="http://127.0.0.1:9090"
KIALI_LOCAL_PORT=20001
KUBE_STATE_METRICS_SELECTOR='app.kubernetes.io/name=kube-state-metrics,app.kubernetes.io/instance=prometheus-stack,app.kubernetes.io/managed-by=Helm'
KUBE_STATE_METRICS_IMAGE="registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0@sha256:42cfe3723a5f058171c627537fb57a3ea0f26e4380fa18555a95cb1a1b4cfc5b"
KUBE_STATE_METRICS_AMD64_DIGEST="sha256:01171220c7c059afc85034ffe687bfe7249e41c0cc46fbe9a5128503ceee3016"
KUBE_STATE_METRICS_ARM64_DIGEST="sha256:92b46557c71ecac53825772e4827dbcd9fca876b1950060f8fb2f2ef0d7a27af"
KUBE_STATE_METRICS_VERSION="v2.20.0"
KUBE_STATE_METRICS_TELEMETRY_LOCAL_PORT=18081
WAIT_TIMEOUT_SECONDS=120
POLL_INTERVAL_SECONDS=5
REQUEST_TIMEOUT_SECONDS=5

SPRING_APPS=(
    session-gateway
    transaction-service
    currency-service
    permission-service
)

MONITORING_SCRAPE_TARGETS=(
    istiod
    prometheus-stack-grafana
    prometheus-stack-kube-prom-operator
    prometheus-stack-kube-state-metrics
)

declare -A SERVICE_PORTS=(
    [session-gateway]=8081
    [transaction-service]=8082
    [currency-service]=8084
    [permission-service]=8086
)

declare -A METRICS_PATHS=(
    [session-gateway]=/actuator/prometheus
    [transaction-service]=/transaction-service/actuator/prometheus
    [currency-service]=/currency-service/actuator/prometheus
    [permission-service]=/permission-service/actuator/prometheus
)

declare -A MONITORING_TARGET_NAMESPACES=(
    [istiod]=istio-system
    [prometheus-stack-grafana]=monitoring
    [prometheus-stack-kube-prom-operator]=monitoring
    [prometheus-stack-kube-state-metrics]=monitoring
)

declare -A MONITORING_TARGET_HOSTS=(
    [istiod]=istiod.istio-system.svc.cluster.local:15014
    [prometheus-stack-grafana]=prometheus-stack-grafana.monitoring.svc.cluster.local:80
    [prometheus-stack-kube-prom-operator]=prometheus-stack-kube-prom-operator.monitoring.svc.cluster.local:8080
    [prometheus-stack-kube-state-metrics]=prometheus-stack-kube-state-metrics.monitoring.svc.cluster.local:8080
)

declare -A MONITORING_TARGET_PATHS=(
    [istiod]=/metrics
    [prometheus-stack-grafana]=/metrics
    [prometheus-stack-kube-prom-operator]=/metrics
    [prometheus-stack-kube-state-metrics]=/metrics
)

PASSED=0
FAILED=0
PROMETHEUS_POD=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-monitoring-runtime.sh [options]

Verifies that Prometheus is scraping the four Spring Boot services, the
service-DNS-backed monitoring/control-plane targets, and that Kiali no longer
reports Prometheus health as Failure. It also checks the JVM/Spring Boot
Grafana dashboard label and metric inputs plus the live Kiali-to-Jaeger
integration contract.

Options:
  --wait-timeout SECONDS   Max seconds to wait for scrape-dependent checks.
                           Default: 120
  --poll-interval SECONDS  Poll interval while waiting. Default: 5
  -h, --help               Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --wait-timeout)
            WAIT_TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --poll-interval)
            POLL_INTERVAL_SECONDS="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

pass() {
    printf '  [PASS] %s\n' "$1"
    PASSED=$((PASSED + 1))
}

fail_check() {
    printf '  [FAIL] %s\n' "$1" >&2
    FAILED=$((FAILED + 1))
}

warn_check() {
    printf '  [WARN] %s\n' "$1" >&2
}

section() {
    printf '\n=== %s ===\n' "$1"
}

join_apps_regex() {
    local IFS="|"
    printf '%s' "${SPRING_APPS[*]}"
}

join_apps_csv() {
    local IFS=","
    printf '%s' "${SPRING_APPS[*]}"
}

monitoring_target_specs() {
    local target

    for target in "${MONITORING_SCRAPE_TARGETS[@]}"; do
        printf '%s|%s|%s|%s|%s\n' \
            "${target}" \
            "${MONITORING_TARGET_NAMESPACES[${target}]}" \
            "${target}" \
            "${MONITORING_TARGET_HOSTS[${target}]}" \
            "${MONITORING_TARGET_PATHS[${target}]}"
    done
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_positive_integer() {
    local name="$1" value="$2"
    if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
        printf 'ERROR: %s must be a positive integer, got: %s\n' "$name" "$value" >&2
        exit 1
    fi
}

require_cluster_access() {
    if ! kubectl get namespace default >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes API or default namespace\n' >&2
        exit 1
    fi
}

discover_prometheus_pod() {
    local pod

    pod=$(kubectl get pod -n "${PROMETHEUS_NAMESPACE}" \
        -l "${PROMETHEUS_SELECTOR}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

    if [[ -z "${pod}" ]]; then
        printf 'ERROR: no Prometheus pod found in namespace %s with selector %s\n' \
            "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_SELECTOR}" >&2
        exit 1
    fi

    if ! kubectl wait -n "${PROMETHEUS_NAMESPACE}" \
        --for=condition=Ready "pod/${pod}" --timeout=60s >/dev/null 2>&1; then
        printf 'ERROR: Prometheus pod %s is not Ready\n' "${pod}" >&2
        exit 1
    fi

    PROMETHEUS_POD="${pod}"
}

verify_kube_state_metrics_image_identity() {
    local description="kube-state-metrics pod uses the reviewed image and runtime digest"
    local output tmp_dir

    tmp_dir="$(mktemp -d)"
    if ! kubectl get pods -n "${PROMETHEUS_NAMESPACE}" \
        -l "${KUBE_STATE_METRICS_SELECTOR}" -o json \
        > "${tmp_dir}/pods.json" 2> "${tmp_dir}/kubectl.stderr" \
        || ! kubectl get nodes -o json \
        > "${tmp_dir}/nodes.json" 2>> "${tmp_dir}/kubectl.stderr"; then
        fail_check "${description}"
        sed -n '1,80p' "${tmp_dir}/kubectl.stderr" | sed 's/^/    /' >&2
        rm -rf "${tmp_dir}"
        return 1
    fi

    if output=$(python3 - \
        "${tmp_dir}/pods.json" \
        "${tmp_dir}/nodes.json" \
        "${KUBE_STATE_METRICS_IMAGE}" \
        "${KUBE_STATE_METRICS_AMD64_DIGEST}" \
        "${KUBE_STATE_METRICS_ARM64_DIGEST}" 2>&1 <<'PY'
import json
import sys
from pathlib import Path

pods_path, nodes_path, expected_image, amd64_digest, arm64_digest = sys.argv[1:]
pods = json.loads(Path(pods_path).read_text(encoding="utf-8")).get("items", [])
nodes = json.loads(Path(nodes_path).read_text(encoding="utf-8")).get("items", [])
node_architectures = {
    (node.get("metadata") or {}).get("name"): (node.get("status") or {})
    .get("nodeInfo", {})
    .get("architecture")
    for node in nodes
}
expected_platform_digests = {
    "amd64": amd64_digest,
    "arm64": arm64_digest,
}
expected_source_digest = expected_image.rsplit("@", maxsplit=1)[-1]
failures = []

if not pods:
    failures.append("no kube-state-metrics pod matched the expected selector")

for pod in pods:
    metadata = pod.get("metadata") or {}
    spec = pod.get("spec") or {}
    status = pod.get("status") or {}
    pod_name = metadata.get("name") or "(unnamed)"
    node_name = spec.get("nodeName")
    architecture = node_architectures.get(node_name)
    expected_child = expected_platform_digests.get(architecture)
    containers = [
        container
        for container in spec.get("containers") or []
        if container.get("name") == "kube-state-metrics"
    ]
    statuses = [
        container
        for container in status.get("containerStatuses") or []
        if container.get("name") == "kube-state-metrics"
    ]

    if len(containers) != 1:
        failures.append(
            f"{pod_name}: expected one kube-state-metrics container, found {len(containers)}"
        )
        continue
    if containers[0].get("image") != expected_image:
        failures.append(
            f"{pod_name}: pod image is {containers[0].get('image')!r}, expected {expected_image!r}"
        )
    if expected_child is None:
        failures.append(
            f"{pod_name}: unsupported or unknown node architecture {architecture!r}"
        )
        continue
    if len(statuses) != 1:
        failures.append(
            f"{pod_name}: expected one kube-state-metrics container status, found {len(statuses)}"
        )
        continue

    image_id = statuses[0].get("imageID") or ""
    image_id_digest = image_id.rsplit("@", maxsplit=1)[-1]
    if image_id_digest not in {expected_source_digest, expected_child}:
        failures.append(
            f"{pod_name}: runtime imageID {image_id!r} matches neither the reviewed "
            f"source digest {expected_source_digest} nor the linux/{architecture} "
            f"child {expected_child}"
        )
    digest_kind = (
        "source index"
        if image_id_digest == expected_source_digest
        else f"linux/{architecture} child"
    )
    print(
        f"{pod_name}: image={containers[0].get('image')}, "
        f"platform=linux/{architecture}, imageID={image_id} ({digest_kind})"
    )

if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    raise SystemExit(1)
PY
    ); then
        pass "${description}"
        printf '%s\n' "${output}" | sed 's/^/    /'
        rm -rf "${tmp_dir}"
        return 0
    fi

    fail_check "${description}"
    printf '%s\n' "${output}" | sed 's/^/    /' >&2
    rm -rf "${tmp_dir}"
    return 1
}

verify_kube_state_metrics_build_info() {
    local description="kube-state-metrics build info reports ${KUBE_STATE_METRICS_VERSION} on its node architecture"
    local architecture deadline metrics_file node output pod port_forward_log port_forward_pid tmp_dir

    pod="$(kubectl get pod -n "${PROMETHEUS_NAMESPACE}" \
        -l "${KUBE_STATE_METRICS_SELECTOR}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -z "${pod}" ]]; then
        fail_check "${description}"
        printf '    No kube-state-metrics pod matched the expected selector.\n' >&2
        return 1
    fi

    node="$(kubectl get pod -n "${PROMETHEUS_NAMESPACE}" "${pod}" \
        -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"
    architecture="$(kubectl get node "${node}" \
        -o jsonpath='{.status.nodeInfo.architecture}' 2>/dev/null || true)"
    if [[ -z "${node}" || -z "${architecture}" ]]; then
        fail_check "${description}"
        printf '    Could not resolve the kube-state-metrics node architecture.\n' >&2
        return 1
    fi

    tmp_dir="$(mktemp -d)"
    metrics_file="${tmp_dir}/metrics.txt"
    port_forward_log="${tmp_dir}/port-forward.log"
    kubectl port-forward --address 127.0.0.1 \
        -n "${PROMETHEUS_NAMESPACE}" "pod/${pod}" \
        "${KUBE_STATE_METRICS_TELEMETRY_LOCAL_PORT}:8081" \
        > "${port_forward_log}" 2>&1 &
    port_forward_pid=$!

    deadline=$((SECONDS + 30))
    while (( SECONDS <= deadline )); do
        if curl --fail --silent --show-error --max-time "${REQUEST_TIMEOUT_SECONDS}" \
            "http://127.0.0.1:${KUBE_STATE_METRICS_TELEMETRY_LOCAL_PORT}/metrics" \
            > "${metrics_file}" 2>/dev/null; then
            break
        fi
        if ! kill -0 "${port_forward_pid}" 2>/dev/null; then
            break
        fi
        sleep 1
    done

    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true

    if [[ ! -s "${metrics_file}" ]]; then
        fail_check "${description}"
        printf '    Could not read the loopback-forwarded telemetry endpoint.\n' >&2
        sed -n '1,80p' "${port_forward_log}" | sed 's/^/    /' >&2
        rm -rf "${tmp_dir}"
        return 1
    fi

    if output=$(python3 - \
        "${metrics_file}" \
        "${KUBE_STATE_METRICS_VERSION}" \
        "${architecture}" 2>&1 <<'PY'
import re
import sys
from pathlib import Path

metrics_path = Path(sys.argv[1])
expected_version = sys.argv[2]
expected_architecture = sys.argv[3]
samples = [
    line
    for line in metrics_path.read_text(encoding="utf-8").splitlines()
    if line.startswith("kube_state_metrics_build_info{")
]
if len(samples) != 1:
    print(f"expected one kube_state_metrics_build_info sample, found {len(samples)}", file=sys.stderr)
    raise SystemExit(1)

match = re.search(r'(?:\{|,)version="([^"]+)"(?:,|})', samples[0])
if match is None:
    print("kube_state_metrics_build_info has no version label", file=sys.stderr)
    raise SystemExit(1)
if match.group(1) != expected_version:
    print(
        f"kube_state_metrics_build_info reports {match.group(1)!r}, expected {expected_version!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
architecture_match = re.search(r'(?:\{|,)goarch="([^"]+)"(?:,|})', samples[0])
if architecture_match is None:
    print("kube_state_metrics_build_info has no goarch label", file=sys.stderr)
    raise SystemExit(1)
if architecture_match.group(1) != expected_architecture:
    print(
        "kube_state_metrics_build_info reports architecture "
        f"{architecture_match.group(1)!r}, expected {expected_architecture!r}",
        file=sys.stderr,
    )
    raise SystemExit(1)
if not samples[0].endswith(" 1"):
    print(f"unexpected kube_state_metrics_build_info sample value: {samples[0]}", file=sys.stderr)
    raise SystemExit(1)

print(samples[0])
PY
    ); then
        pass "${description}"
        printf '%s\n' "${output}" | sed 's/^/    /'
        rm -rf "${tmp_dir}"
        return 0
    fi

    fail_check "${description}"
    printf '%s\n' "${output}" | sed 's/^/    /' >&2
    rm -rf "${tmp_dir}"
    return 1
}

promtool_query_json() {
    local query="$1"

    kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
        -c "${PROMETHEUS_CONTAINER}" -- \
        promtool query instant --format=json "${PROMETHEUS_URL}" "${query}"
}

promtool_label_values_json() {
    local label_name="$1" match_selector="$2"

    kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
        -c "${PROMETHEUS_CONTAINER}" -- \
        promtool query labels --format=json --match="${match_selector}" \
        "${PROMETHEUS_URL}" "${label_name}"
}

prometheus_active_targets_json() {
    kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
        -c "${PROMETHEUS_CONTAINER}" -- \
        wget -qO- "${PROMETHEUS_URL}/api/v1/targets?state=active"
}

parse_required_app_values() {
    local required_csv="$1" minimum_value="$2"

    python3 -c '
import json
import sys

required = [item for item in sys.argv[1].split(",") if item]
minimum = float(sys.argv[2])

try:
    result = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"Could not parse Prometheus JSON: {exc}", file=sys.stderr)
    sys.exit(2)

values = {}
for item in result:
    metric = item.get("metric", {})
    application = metric.get("application")
    if not application:
        continue
    try:
        value = float(item.get("value", [None, "nan"])[1])
    except (TypeError, ValueError, IndexError):
        value = float("nan")
    values[application] = max(value, values.get(application, float("-inf")))

missing = [app for app in required if app not in values]
below = [app for app in required if app in values and values[app] < minimum]

for app in required:
    if app in values:
        print(f"{app}={values[app]:g}")
    else:
        print(f"{app}=missing")

if missing or below:
    if missing:
        print("Missing applications: " + ", ".join(missing), file=sys.stderr)
    if below:
        print(
            f"Applications below required value {minimum:g}: " + ", ".join(below),
            file=sys.stderr,
        )
    sys.exit(1)
' "${required_csv}" "${minimum_value}"
}

parse_required_labels() {
    local required_csv="$1"

    python3 -c '
import json
import sys

required = [item for item in sys.argv[1].split(",") if item]

try:
    values = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"Could not parse Prometheus label JSON: {exc}", file=sys.stderr)
    sys.exit(2)

actual = set(values)
for app in required:
    if app in actual:
        print(f"{app}=present")
    else:
        print(f"{app}=missing")

missing = [app for app in required if app not in actual]
if missing:
    print("Missing dashboard application labels: " + ", ".join(missing), file=sys.stderr)
    sys.exit(1)
' "${required_csv}"
}

print_failed_target_errors() {
    local targets_json

    if ! targets_json=$(prometheus_active_targets_json 2>/dev/null); then
        printf '  Could not fetch Prometheus target details.\n' >&2
        return
    fi

    python3 -c '
import json
import sys

expected = set(item for item in sys.argv[1].split(",") if item)

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"  Could not parse Prometheus target details: {exc}", file=sys.stderr)
    sys.exit(0)

targets = payload.get("data", {}).get("activeTargets", [])
matched = []

for target in targets:
    labels = target.get("labels", {})
    app = labels.get("application")
    if labels.get("namespace") != "default" or app not in expected:
        continue
    matched.append(app)
    if target.get("health") == "up":
        continue

    health = target.get("health", "unknown")
    last_error = target.get("lastError") or "(no lastError reported)"
    scrape_url = target.get("scrapeUrl") or "(unknown scrape URL)"
    print(f"  {app}: {health} {scrape_url}")
    print(f"    lastError: {last_error}")

missing = sorted(expected.difference(matched))
for app in missing:
    print(f"  {app}: no active Prometheus target found")
' "$(join_apps_csv)" <<< "${targets_json}"
}

parse_required_monitoring_targets() {
    python3 -c '
import json
import sys
from urllib.parse import urlparse

specs = []
for raw in sys.argv[1:]:
    name, namespace, service_name, expected_host, expected_path = raw.split("|", 4)
    specs.append(
        {
            "name": name,
            "namespace": namespace,
            "service_name": service_name,
            "expected_host": expected_host,
            "expected_path": expected_path,
        }
    )

try:
    payload = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    print(f"Could not parse Prometheus target JSON: {exc}", file=sys.stderr)
    sys.exit(2)

targets = payload.get("data", {}).get("activeTargets", [])
overall_ok = True

for spec in specs:
    matches = []

    for target in targets:
        labels = target.get("labels") or {}
        discovered = target.get("discoveredLabels") or {}
        namespaces = {
            value
            for value in (
                labels.get("namespace"),
                discovered.get("__meta_kubernetes_namespace"),
            )
            if value
        }
        service_names = {
            value
            for value in (
                labels.get("service"),
                labels.get("job"),
                discovered.get("__meta_kubernetes_service_name"),
            )
            if value
        }

        if spec["namespace"] not in namespaces:
            continue
        if spec["service_name"] not in service_names:
            continue
        matches.append(target)

    if not matches:
        overall_ok = False
        print(
            "{}: missing active target for {}/{}".format(
                spec["name"],
                spec["namespace"],
                spec["service_name"],
            )
        )
        continue

    target_ok = True
    for target in matches:
        scrape_url = target.get("scrapeUrl") or ""
        parsed = urlparse(scrape_url)
        actual_host = parsed.netloc or "(missing host)"
        actual_path = parsed.path or "/"
        health = target.get("health") or "unknown"
        last_error = target.get("lastError") or "(no lastError reported)"
        status = "OK"

        if actual_host != spec["expected_host"]:
            status = f"unexpected host {actual_host}"
            target_ok = False
        elif actual_path != spec["expected_path"]:
            status = f"unexpected path {actual_path}"
            target_ok = False
        elif health != "up":
            status = f"health={health}"
            target_ok = False

        print("{}: {} {} [{}]".format(spec["name"], health, scrape_url, status))
        if health != "up":
            print(f"  lastError: {last_error}")

    if not target_ok:
        overall_ok = False

if not overall_ok:
    sys.exit(1)
' "$@"
}

run_query_check_once() {
    local description="$1" query="$2" minimum_value="$3"
    local output query_json

    if ! query_json=$(promtool_query_json "${query}" 2>/dev/null); then
        fail_check "${description}"
        printf '    Prometheus query failed: %s\n' "${query}" >&2
        return 1
    fi

    if output=$(printf '%s' "${query_json}" \
        | parse_required_app_values "$(join_apps_csv)" "${minimum_value}" 2>&1); then
        pass "${description}"
        printf '%s\n' "${output}" | sed 's/^/    /'
        return 0
    fi

    fail_check "${description}"
    printf '%s\n' "${output}" | sed 's/^/    /' >&2
    return 1
}

wait_for_query_check() {
    local description="$1" query="$2" minimum_value="$3"
    local deadline output query_json

    deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    while (( SECONDS <= deadline )); do
        if query_json=$(promtool_query_json "${query}" 2>/dev/null) \
            && output=$(printf '%s' "${query_json}" \
                | parse_required_app_values "$(join_apps_csv)" "${minimum_value}" 2>&1); then
            pass "${description}"
            printf '%s\n' "${output}" | sed 's/^/    /'
            return 0
        fi

        if (( SECONDS >= deadline )); then
            break
        fi
        sleep "${POLL_INTERVAL_SECONDS}"
    done

    fail_check "${description}"
    printf '    Timed out after %ss waiting for query:\n' "${WAIT_TIMEOUT_SECONDS}" >&2
    printf '    %s\n' "${query}" >&2
    if [[ -n "${output:-}" ]]; then
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
    fi
    return 1
}

verify_dashboard_labels() {
    local description="Dashboard application labels exist on jvm_info"
    local labels_json output

    if ! labels_json=$(promtool_label_values_json application 'jvm_info{namespace="default"}' 2>/dev/null); then
        fail_check "${description}"
        printf '    Prometheus label query failed.\n' >&2
        return 1
    fi

    if output=$(printf '%s' "${labels_json}" | parse_required_labels "$(join_apps_csv)" 2>&1); then
        pass "${description}"
        printf '%s\n' "${output}" | sed 's/^/    /'
        return 0
    fi

    fail_check "${description}"
    printf '%s\n' "${output}" | sed 's/^/    /' >&2
    return 1
}

wait_for_monitoring_targets_check() {
    local description="$1"
    local deadline output
    local -a target_specs=()

    mapfile -t target_specs < <(monitoring_target_specs)

    deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    while (( SECONDS <= deadline )); do
        if output=$(
            prometheus_active_targets_json 2>/dev/null \
                | parse_required_monitoring_targets "${target_specs[@]}" 2>&1
        ); then
            pass "${description}"
            printf '%s\n' "${output}" | sed 's/^/    /'
            return 0
        fi

        if (( SECONDS >= deadline )); then
            break
        fi
        sleep "${POLL_INTERVAL_SECONDS}"
    done

    fail_check "${description}"
    printf '    Timed out after %ss waiting for Prometheus active targets to match the service-DNS contract.\n' \
        "${WAIT_TIMEOUT_SECONDS}" >&2
    if [[ -n "${output:-}" ]]; then
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
    fi
    return 1
}

parse_kiali_prometheus_health() {
    local clusters_health_file="$1"

    python3 - "${clusters_health_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

def iter_matches(section_name):
    section = payload.get(section_name, {}).get("monitoring", {})
    if not isinstance(section, dict):
        return []
    matches = []
    for name, data in section.items():
        if name not in {"prometheus", "prometheus-stack-kube-prom-prometheus"}:
            continue
        status = ((data or {}).get("status") or {}).get("status", "Unknown")
        error_ratio = ((data or {}).get("status") or {}).get("errorRatio", "n/a")
        request_rate = ((data or {}).get("status") or {}).get("totalRequestRate", "n/a")
        matches.append((section_name, name, status, error_ratio, request_rate))
    return matches

matches = iter_matches("namespaceWorkloadHealth") + iter_matches("namespaceAppHealth")

if not matches:
    print("No Kiali monitoring health entry for Prometheus was returned.", file=sys.stderr)
    sys.exit(1)

overall_ok = True
exact_prometheus_seen = False

for section_name, name, status, error_ratio, request_rate in matches:
    if name == "prometheus":
        exact_prometheus_seen = True
    print(
        f"{section_name}/monitoring/{name}: status={status}, "
        f"errorRatio={error_ratio}, requestRate={request_rate}"
    )
    if name == "prometheus" and status == "Failure":
        overall_ok = False

if not exact_prometheus_seen:
    if any(status == "Failure" for _, _, status, _, _ in matches):
        overall_ok = False

if not overall_ok:
    sys.exit(1)
PY
}

parse_kiali_jaeger_integration() {
    local status_file="$1"
    local istio_status_file="$2"
    local kiali_log_file="$3"
    local kiali_configmap_file="$4"

    python3 - "${status_file}" "${istio_status_file}" "${kiali_log_file}" "${kiali_configmap_file}" <<'PY'
import json
import sys
from pathlib import Path

status_file, istio_status_file, kiali_log_file, kiali_configmap_file = sys.argv[1:5]

with open(status_file, encoding="utf-8") as handle:
    status_payload = json.load(handle)

with open(istio_status_file, encoding="utf-8") as handle:
    istio_status_payload = json.load(handle)

with open(kiali_configmap_file, encoding="utf-8") as handle:
    kiali_configmap_payload = json.load(handle)

failures = []

jaeger_service = next(
    (
        service
        for service in (status_payload.get("externalServices") or [])
        if (service.get("name") or "").lower() == "jaeger"
    ),
    None,
)
if jaeger_service is None:
    failures.append("Kiali status API does not report an externalServices/jaeger entry.")
else:
    version = jaeger_service.get("version") or "not reported"
    print(f"status/externalServices/jaeger: present, version={version}")

tracing_status = next(
    (
        item
        for item in istio_status_payload
        if (item.get("name") or "") == "tracing"
    ),
    None,
)
if tracing_status is None:
    failures.append("Kiali istio-status API does not report the tracing component.")
else:
    status = tracing_status.get("status") or "Unknown"
    print(f"istio-status/tracing: status={status}")
    if status != "Healthy":
        failures.append(f"Kiali reports tracing status {status!r} instead of 'Healthy'.")

config_yaml = ((kiali_configmap_payload.get("data") or {}).get("config.yaml") or "")
expected_contract = {
    "jaeger grpc internal_url": "internal_url: http://jaeger-query.monitoring:16685/jaeger",
    "jaeger http health_check_url": "health_check_url: http://jaeger-query.monitoring:16686/jaeger",
    "jaeger grpc enabled": "use_grpc: true",
    "jaeger version check disabled": "disable_version_check: true",
}
for label, snippet in expected_contract.items():
    if snippet not in config_yaml:
        failures.append(f"Live Kiali config is missing {label}: {snippet}")
    else:
        print(f"config/{label}: ok")

kiali_log_text = Path(kiali_log_file).read_text(encoding="utf-8")
if "jaeger version check failed" in kiali_log_text:
    failures.append("Kiali pod logs still contain 'jaeger version check failed'.")
else:
    print("logs/jaeger-version-check: absent")

if failures:
    for failure in failures:
        print(failure, file=sys.stderr)
    sys.exit(1)
PY
}

wait_for_kiali_prometheus_health() {
    local description="$1"
    local deadline output
    local tmp_dir triage_log

    deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    while (( SECONDS <= deadline )); do
        tmp_dir="$(mktemp -d)"
        triage_log="${tmp_dir}/triage.log"

        if "${REPO_DIR}/scripts/ops/triage-kiali-findings.sh" \
            --namespace monitoring \
            --kiali-port "${KIALI_LOCAL_PORT}" \
            --wait-timeout "${WAIT_TIMEOUT_SECONDS}" \
            --poll-interval "${POLL_INTERVAL_SECONDS}" \
            --log-tail-lines 50 \
            --output-dir "${tmp_dir}" >"${triage_log}" 2>&1 \
            && output=$(parse_kiali_prometheus_health "${tmp_dir}/clusters-health.json" 2>&1); then
            pass "${description}"
            printf '%s\n' "${output}" | sed 's/^/    /'
            rm -rf "${tmp_dir}"
            return 0
        fi

        output="$(sed -n '1,160p' "${triage_log}" 2>/dev/null || true)"
        rm -rf "${tmp_dir}"

        if (( SECONDS >= deadline )); then
            break
        fi
        sleep "${POLL_INTERVAL_SECONDS}"
    done

    fail_check "${description}"
    printf '    Timed out after %ss waiting for Kiali to stop reporting Prometheus health as Failure.\n' \
        "${WAIT_TIMEOUT_SECONDS}" >&2
    if [[ -n "${output:-}" ]]; then
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
    fi
    return 1
}

wait_for_kiali_jaeger_integration() {
    local description="$1"
    local deadline output
    local tmp_dir triage_log kubectl_log

    deadline=$((SECONDS + WAIT_TIMEOUT_SECONDS))
    while (( SECONDS <= deadline )); do
        tmp_dir="$(mktemp -d)"
        triage_log="${tmp_dir}/triage.log"
        kubectl_log="${tmp_dir}/kubectl.log"

        if "${REPO_DIR}/scripts/ops/triage-kiali-findings.sh" \
            --namespace monitoring \
            --kiali-port "${KIALI_LOCAL_PORT}" \
            --wait-timeout "${WAIT_TIMEOUT_SECONDS}" \
            --poll-interval "${POLL_INTERVAL_SECONDS}" \
            --log-tail-lines 200 \
            --output-dir "${tmp_dir}" >"${triage_log}" 2>&1 \
            && kubectl get configmap -n monitoring kiali -o json >"${tmp_dir}/kiali-configmap.json" 2>"${kubectl_log}" \
            && output=$(
                parse_kiali_jaeger_integration \
                    "${tmp_dir}/status.json" \
                    "${tmp_dir}/istio-status.json" \
                    "${tmp_dir}/kiali.log" \
                    "${tmp_dir}/kiali-configmap.json" 2>&1
            ); then
            pass "${description}"
            printf '%s\n' "${output}" | sed 's/^/    /'
            rm -rf "${tmp_dir}"
            return 0
        fi

        output="$(sed -n '1,160p' "${triage_log}" 2>/dev/null || true)"
        if [[ -s "${kubectl_log}" ]]; then
            output+=$'\n'
            output+="$(sed -n '1,80p' "${kubectl_log}")"
        fi
        rm -rf "${tmp_dir}"

        if (( SECONDS >= deadline )); then
            break
        fi
        sleep "${POLL_INTERVAL_SECONDS}"
    done

    fail_check "${description}"
    printf '    Timed out after %ss waiting for Kiali to keep tracing healthy without Jaeger version-check failures.\n' \
        "${WAIT_TIMEOUT_SECONDS}" >&2
    if [[ -n "${output:-}" ]]; then
        printf '%s\n' "${output}" | sed 's/^/    /' >&2
    fi
    return 1
}

generate_metrics_traffic() {
    local app port path url
    local response status
    local failed=0

    for app in "${SPRING_APPS[@]}"; do
        port="${SERVICE_PORTS[${app}]}"
        path="${METRICS_PATHS[${app}]}"
        url="http://${app}.default.svc.cluster.local:${port}${path}"

        response=$(kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
            -c "${PROMETHEUS_CONTAINER}" -- \
            wget -S -T "${REQUEST_TIMEOUT_SECONDS}" -O /dev/null "${url}" 2>&1 || true)
        status=$(printf '%s\n' "${response}" \
            | sed -n 's/^[[:space:]]*HTTP\/[^[:space:]]*[[:space:]]*\([0-9][0-9][0-9]\).*/\1/p' \
            | tail -n 1)

        if [[ -n "${status}" ]]; then
            pass "Metrics request generated for ${app} (HTTP ${status})"
        else
            warn_check "Metrics request warmup skipped for ${app}"
            printf '    Failed request: %s\n' "${url}" >&2
            printf '%s\n' "${response}" | sed 's/^/    /' >&2
            failed=1
        fi
    done

    return "${failed}"
}

verify_required_objects() {
    local missing=0

    if kubectl get servicemonitor spring-boot-services -n default >/dev/null 2>&1; then
        pass "ServiceMonitor/default/spring-boot-services exists"
    else
        fail_check "ServiceMonitor/default/spring-boot-services exists"
        missing=1
    fi

    for app in "${SPRING_APPS[@]}"; do
        if kubectl get service "${app}" -n default >/dev/null 2>&1; then
            pass "Service/default/${app} exists"
        else
            fail_check "Service/default/${app} exists"
            missing=1
        fi
    done

    return "${missing}"
}

main() {
    local app_regex target_query jvm_query http_query targets_ok=0

    require_positive_integer "--wait-timeout" "${WAIT_TIMEOUT_SECONDS}"
    require_positive_integer "--poll-interval" "${POLL_INTERVAL_SECONDS}"
    require_command kubectl
    require_command curl
    require_command jq
    require_command python3
    require_cluster_access
    discover_prometheus_pod

    printf 'Using Prometheus pod: %s/%s\n' "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}"

    section "kube-state-metrics Runtime Identity"
    verify_kube_state_metrics_image_identity || true
    verify_kube_state_metrics_build_info || true

    section "Required Objects"
    verify_required_objects || true

    section "Traffic"
    generate_metrics_traffic || true

    app_regex="$(join_apps_regex)"
    target_query="min by (application) (up{namespace=\"default\", application=~\"${app_regex}\"})"
    jvm_query="count by (application) (jvm_info{namespace=\"default\"})"
    http_query="count by (application) (http_server_requests_seconds_count{namespace=\"default\"})"

    section "Prometheus Targets"
    if wait_for_query_check "Spring Boot scrape targets are up" "${target_query}" 1; then
        targets_ok=1
    else
        print_failed_target_errors
    fi

    wait_for_monitoring_targets_check \
        "Monitoring and control-plane scrape targets are up via Service DNS" || true

    section "Metrics"
    if (( targets_ok == 1 )); then
        wait_for_query_check "JVM metrics exist for all Spring Boot services" "${jvm_query}" 1 || true
        wait_for_query_check "Spring HTTP metrics exist for all Spring Boot services" "${http_query}" 1 || true
    else
        run_query_check_once "JVM metrics exist for all Spring Boot services" "${jvm_query}" 1 || true
        run_query_check_once "Spring HTTP metrics exist for all Spring Boot services" "${http_query}" 1 || true
    fi

    section "Dashboard Contract"
    verify_dashboard_labels || true

    section "Kiali Health"
    wait_for_kiali_prometheus_health \
        "Kiali no longer reports monitoring/prometheus as Failure" || true
    wait_for_kiali_jaeger_integration \
        "Kiali tracing integration stays healthy without Jaeger version-check failures" || true

    printf '\nMonitoring runtime verification complete: %s passed, %s failed.\n' "${PASSED}" "${FAILED}"
    if (( FAILED > 0 )); then
        exit 1
    fi
}

main "$@"
