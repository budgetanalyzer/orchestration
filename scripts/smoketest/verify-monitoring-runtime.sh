#!/usr/bin/env bash
# Runtime verification for Spring Boot metrics and Grafana dashboard inputs.

set -euo pipefail

PROMETHEUS_NAMESPACE="monitoring"
PROMETHEUS_SELECTOR='app.kubernetes.io/name=prometheus'
PROMETHEUS_CONTAINER="prometheus"
PROMETHEUS_URL="http://127.0.0.1:9090"
WAIT_TIMEOUT_SECONDS=120
POLL_INTERVAL_SECONDS=5
REQUEST_TIMEOUT_SECONDS=5

SPRING_APPS=(
    session-gateway
    transaction-service
    currency-service
    permission-service
)

declare -A SERVICE_PORTS=(
    [session-gateway]=8081
    [transaction-service]=8082
    [currency-service]=8084
    [permission-service]=8086
)

declare -A HEALTH_PATHS=(
    [session-gateway]=/actuator/health
    [transaction-service]=/transaction-service/actuator/health
    [currency-service]=/currency-service/actuator/health
    [permission-service]=/permission-service/actuator/health
)

PASSED=0
FAILED=0
PROMETHEUS_POD=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-monitoring-runtime.sh [options]

Verifies that Prometheus is scraping the four Spring Boot services and that the
JVM/Spring Boot Grafana dashboards have the labels and metrics they depend on.

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

    if ! targets_json=$(kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
        -c "${PROMETHEUS_CONTAINER}" -- \
        wget -qO- "${PROMETHEUS_URL}/api/v1/targets?state=active" 2>/dev/null); then
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

generate_health_traffic() {
    local app port path url
    local response status
    local failed=0

    for app in "${SPRING_APPS[@]}"; do
        port="${SERVICE_PORTS[${app}]}"
        path="${HEALTH_PATHS[${app}]}"
        url="http://${app}.default.svc.cluster.local:${port}${path}"

        response=$(kubectl exec -n "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}" \
            -c "${PROMETHEUS_CONTAINER}" -- \
            wget -S -T "${REQUEST_TIMEOUT_SECONDS}" -O /dev/null "${url}" 2>&1 || true)
        status=$(printf '%s\n' "${response}" \
            | sed -n 's/^[[:space:]]*HTTP\/[^[:space:]]*[[:space:]]*\([0-9][0-9][0-9]\).*/\1/p' \
            | tail -n 1)

        if [[ -n "${status}" ]]; then
            pass "Health request generated for ${app} (HTTP ${status})"
        else
            fail_check "Health request generated for ${app}"
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
    require_command python3
    require_cluster_access
    discover_prometheus_pod

    printf 'Using Prometheus pod: %s/%s\n' "${PROMETHEUS_NAMESPACE}" "${PROMETHEUS_POD}"

    section "Required Objects"
    verify_required_objects || true

    section "Traffic"
    generate_health_traffic || true

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

    printf '\nMonitoring runtime verification complete: %s passed, %s failed.\n' "${PASSED}" "${FAILED}"
    if (( FAILED > 0 )); then
        exit 1
    fi
}

main "$@"
