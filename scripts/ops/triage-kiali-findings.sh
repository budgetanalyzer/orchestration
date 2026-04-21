#!/usr/bin/env bash
# Snapshots Kiali API findings and classifies the obvious runtime-vs-noise cases.

set -euo pipefail

MONITORING_NAMESPACE="monitoring"
DEFAULT_NAMESPACE="default"
KIALI_SERVICE="svc/kiali"
KIALI_REMOTE_PORT=20001
KIALI_LOCAL_PORT=20001
WAIT_TIMEOUT_SECONDS=30
POLL_INTERVAL_SECONDS=1
LOG_TAIL_LINES=200
EXPECTED_APP_DEPLOYMENTS=(
    budget-analyzer-web
    currency-service
    ext-authz
    nginx-gateway
    permission-service
    session-gateway
    transaction-service
)

declare -a SELECTED_NAMESPACES=()
PORT_FORWARD_PID=""
TMP_DIR=""
COOKIES_FILE=""
OUTPUT_DIR=""
KEEP_ARTIFACTS=0

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/triage-kiali-findings.sh [options]

Authenticates to the local Kiali instance, snapshots its current API findings,
and classifies the obvious "real issue" vs "runtime absent" vs "likely
low-signal" cases.

Options:
  --namespace NAME         Limit the report to a namespace Kiali can access.
                           Repeat to select multiple namespaces. Default: all
                           namespaces returned by Kiali.
  --kiali-port PORT        Local loopback port for Kiali. Default: 20001
  --wait-timeout SECONDS   Max seconds to wait for a local Kiali endpoint.
                           Default: 30
  --poll-interval SECONDS  Poll interval while waiting. Default: 1
  --output-dir DIR         Persist fetched JSON and log artifacts to DIR.
                           Default: temporary directory deleted on exit
  --log-tail-lines COUNT   Kiali log lines to inspect for startup/runtime
                           warnings. Default: 200
  -h, --help               Show this help text.

Examples:
  ./scripts/ops/triage-kiali-findings.sh
  ./scripts/ops/triage-kiali-findings.sh --namespace default
  ./scripts/ops/triage-kiali-findings.sh --output-dir tmp/kiali-triage
EOF
}

cleanup() {
    local exit_code=$?

    if [[ -n "${PORT_FORWARD_PID}" ]]; then
        kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
        wait "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
    fi

    if [[ -n "${TMP_DIR}" && "${KEEP_ARTIFACTS}" -eq 0 ]]; then
        rm -rf "${TMP_DIR}"
    fi

    exit "${exit_code}"
}

trap cleanup EXIT

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_positive_integer() {
    local name="$1"
    local value="$2"

    if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
        printf 'ERROR: %s must be a positive integer, got: %s\n' "${name}" "${value}" >&2
        exit 1
    fi
}

append_namespace() {
    local namespace="$1"
    local existing

    for existing in "${SELECTED_NAMESPACES[@]:-}"; do
        if [[ "${existing}" == "${namespace}" ]]; then
            return 0
        fi
    done

    SELECTED_NAMESPACES+=("${namespace}")
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace)
            append_namespace "${2:-}"
            shift 2
            ;;
        --kiali-port)
            KIALI_LOCAL_PORT="${2:-}"
            shift 2
            ;;
        --wait-timeout)
            WAIT_TIMEOUT_SECONDS="${2:-}"
            shift 2
            ;;
        --poll-interval)
            POLL_INTERVAL_SECONDS="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --log-tail-lines)
            LOG_TAIL_LINES="${2:-}"
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

require_command curl
require_command jq
require_command kubectl

require_positive_integer "--kiali-port" "${KIALI_LOCAL_PORT}"
require_positive_integer "--wait-timeout" "${WAIT_TIMEOUT_SECONDS}"
require_positive_integer "--poll-interval" "${POLL_INTERVAL_SECONDS}"
require_positive_integer "--log-tail-lines" "${LOG_TAIL_LINES}"

if ! kubectl get namespace "${MONITORING_NAMESPACE}" >/dev/null 2>&1; then
    printf 'ERROR: cannot reach Kubernetes API or namespace %s\n' "${MONITORING_NAMESPACE}" >&2
    exit 1
fi

if ! kubectl get -n "${MONITORING_NAMESPACE}" "${KIALI_SERVICE}" >/dev/null 2>&1; then
    printf 'ERROR: required resource not found: %s/%s\n' "${MONITORING_NAMESPACE}" "${KIALI_SERVICE}" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
COOKIES_FILE="${TMP_DIR}/kiali.cookies"

if [[ -n "${OUTPUT_DIR}" ]]; then
    mkdir -p "${OUTPUT_DIR}"
    KEEP_ARTIFACTS=1
fi

kiali_url="http://127.0.0.1:${KIALI_LOCAL_PORT}/kiali"

port_is_ready() {
    curl -fsS --max-time 5 "${kiali_url}/" >/dev/null 2>&1
}

wait_for_kiali() {
    local waited=0

    while (( waited < WAIT_TIMEOUT_SECONDS )); do
        if port_is_ready; then
            return 0
        fi
        sleep "${POLL_INTERVAL_SECONDS}"
        waited=$((waited + POLL_INTERVAL_SECONDS))
    done

    return 1
}

if ! port_is_ready; then
    kubectl port-forward --address 127.0.0.1 \
        -n "${MONITORING_NAMESPACE}" "${KIALI_SERVICE}" \
        "${KIALI_LOCAL_PORT}:${KIALI_REMOTE_PORT}" \
        >"${TMP_DIR}/port-forward.log" 2>&1 &
    PORT_FORWARD_PID=$!

    if ! wait_for_kiali; then
        printf 'ERROR: Kiali did not become reachable on 127.0.0.1:%s\n' "${KIALI_LOCAL_PORT}" >&2
        printf 'Port-forward log:\n' >&2
        sed -n '1,120p' "${TMP_DIR}/port-forward.log" >&2
        exit 1
    fi
fi

kiali_token="$(kubectl -n "${MONITORING_NAMESPACE}" create token kiali)"

auth_status="$(
    curl -sS -o "${TMP_DIR}/authenticate.json" -w '%{http_code}' \
        -c "${COOKIES_FILE}" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data-urlencode "token=${kiali_token}" \
        "${kiali_url}/api/authenticate"
)"

if [[ "${auth_status}" != "200" ]]; then
    printf 'ERROR: failed to authenticate to Kiali. HTTP %s\n' "${auth_status}" >&2
    sed -n '1,120p' "${TMP_DIR}/authenticate.json" >&2
    exit 1
fi

fetch_api_json() {
    local relative_path="$1"
    local output_file="$2"
    local status_code

    status_code="$(
        curl -sS -o "${output_file}" -w '%{http_code}' \
            -b "${COOKIES_FILE}" \
            "${kiali_url}/${relative_path}"
    )"

    if [[ "${status_code}" != "200" ]]; then
        printf 'ERROR: Kiali API request failed for %s. HTTP %s\n' "${relative_path}" "${status_code}" >&2
        sed -n '1,120p' "${output_file}" >&2
        exit 1
    fi
}

fetch_api_json "api/status" "${TMP_DIR}/status.json"
fetch_api_json "api/namespaces" "${TMP_DIR}/namespaces.json"
fetch_api_json "api/istio/status" "${TMP_DIR}/istio-status.json"
fetch_api_json "api/clusters/health" "${TMP_DIR}/clusters-health.json"
fetch_api_json "api/istio/validations" "${TMP_DIR}/validations-summary.json"

kubectl logs -n "${MONITORING_NAMESPACE}" deployment/kiali --tail="${LOG_TAIL_LINES}" \
    >"${TMP_DIR}/kiali.log" 2>&1 || true

if [[ "${#SELECTED_NAMESPACES[@]}" -eq 0 ]]; then
    while IFS= read -r namespace; do
        [[ -n "${namespace}" ]] || continue
        append_namespace "${namespace}"
    done < <(jq -r '.[].name' "${TMP_DIR}/namespaces.json")
fi

if [[ "${#SELECTED_NAMESPACES[@]}" -eq 0 ]]; then
    printf 'ERROR: Kiali did not return any accessible namespaces\n' >&2
    exit 1
fi

namespace_file() {
    local namespace="$1"
    printf '%s/ns-%s-istio-validate.json' "${TMP_DIR}" "${namespace}"
}

pod_count() {
    local namespace="$1"
    kubectl get pods -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

service_count() {
    local namespace="$1"
    kubectl get svc -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

service_account_count() {
    local namespace="$1"
    kubectl get sa -n "${namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' '
}

expected_app_deployment_total() {
    printf '%s' "${#EXPECTED_APP_DEPLOYMENTS[@]}"
}

expected_app_deployment_present_count() {
    local present=0
    local deployment

    for deployment in "${EXPECTED_APP_DEPLOYMENTS[@]}"; do
        if kubectl get deployment "${deployment}" -n "${DEFAULT_NAMESPACE}" >/dev/null 2>&1; then
            present=$((present + 1))
        fi
    done

    printf '%s' "${present}"
}

missing_expected_app_deployments() {
    local deployment
    local -a missing=()

    for deployment in "${EXPECTED_APP_DEPLOYMENTS[@]}"; do
        if ! kubectl get deployment "${deployment}" -n "${DEFAULT_NAMESPACE}" >/dev/null 2>&1; then
            missing+=("${deployment}")
        fi
    done

    if (( ${#missing[@]} == 0 )); then
        return 0
    fi

    printf '%s\n' "${missing[@]}"
}

namespace_is_ambient() {
    local namespace="$1"
    jq -r --arg namespace "${namespace}" \
        '.[] | select(.name == $namespace) | (.isAmbient // false)' \
        "${TMP_DIR}/namespaces.json"
}

classify_finding() {
    local code="$1"
    local pods="$3"
    local services="$4"
    local service_accounts="$5"
    local is_ambient="$6"

    case "${code}" in
        KIA0004)
            if [[ "${pods}" == "0" ]]; then
                printf 'likely runtime-absent: namespace has no running pods'
            else
                printf 'review: selector does not match a current workload'
            fi
            ;;
        KIA0106)
            if [[ "${service_accounts}" == "1" ]]; then
                printf 'likely runtime-absent: only the default service account exists'
            else
                printf 'review: principal references a missing service account'
            fi
            ;;
        KIA1402)
            if [[ "${services}" == "1" ]]; then
                printf 'likely runtime-absent: namespace only has the kubernetes service'
            else
                printf 'review: route references a service that does not currently exist'
            fi
            ;;
        KIA1317)
            if [[ "${is_ambient}" == "false" ]]; then
                printf 'low-signal candidate: waypoint warning in a non-ambient namespace'
            else
                printf 'review: waypoint-related warning in an ambient namespace'
            fi
            ;;
        *)
            printf 'review manually'
            ;;
    esac
}

printf 'Kiali triage snapshot\n'
printf 'Generated at: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'Kiali URL: %s\n' "${kiali_url}/"

app_deployments_present="$(expected_app_deployment_present_count)"
app_deployments_total="$(expected_app_deployment_total)"
missing_app_deployments="$(missing_expected_app_deployments || true)"

printf '\n== App runtime preflight ==\n'
printf 'Expected default deployments present: %s/%s\n' \
    "${app_deployments_present}" "${app_deployments_total}"

if [[ -n "${missing_app_deployments}" ]]; then
    printf 'Missing default deployments:\n'
    while IFS= read -r deployment; do
        [[ -n "${deployment}" ]] || continue
        printf '  - %s\n' "${deployment}"
    done <<< "${missing_app_deployments}"
fi

if [[ "${app_deployments_present}" == "0" ]]; then
    printf '%s\n' \
        "App runtime is not up. Treat Kiali findings for \`default\` as secondary symptoms until the seven app deployments exist."
fi

printf '\n== Global status ==\n'
jq -r '
    "Kiali state: \(.status["Kiali state"])",
    "Kiali version: \(.status["Kiali version"])",
    "Warning messages from status API: \(.warningMessages | length)"
' "${TMP_DIR}/status.json"

printf '\n== Istio integrations ==\n'
if ! jq -r '.[] | select(.status != "Healthy") | "- \(.name): \(.status)"' \
    "${TMP_DIR}/istio-status.json"; then
    :
fi

if [[ "$(jq 'map(select(.status != "Healthy")) | length' "${TMP_DIR}/istio-status.json")" == "0" ]]; then
    printf 'No unhealthy Istio integrations reported by Kiali.\n'
fi

if grep -Fq 'Unable to read CA bundle' "${TMP_DIR}/kiali.log"; then
    printf '%s\n' '- Kiali log: missing additional CA bundle file. Likely benign unless a custom CA bundle is expected.'
fi

if grep -Fq "Unable to list webhooks for cluster [Kubernetes]" "${TMP_DIR}/kiali.log"; then
    printf '%s\n' "- Kiali log: cannot read mutating webhooks. Expected under namespace-scoped RBAC unless webhook inspection is required."
fi

printf '\n== Health findings ==\n'
health_lines="$(
    jq -r '
        [
          (.namespaceWorkloadHealth // {}
            | to_entries[]
            | .key as $ns
            | .value
            | to_entries[]?
            | select(.value.status.status != "Healthy" and .value.status.status != "NA")
            | "- workload \($ns)/\(.key): \(.value.status.status) (errorRatio=\(.value.status.errorRatio // "n/a"), requestRate=\(.value.status.totalRequestRate // "n/a"))"),
          (.namespaceAppHealth // {}
            | to_entries[]
            | .key as $ns
            | .value
            | to_entries[]?
            | select(.value.status.status != "Healthy" and .value.status.status != "NA")
            | "- app \($ns)/\(.key): \(.value.status.status) (errorRatio=\(.value.status.errorRatio // "n/a"), requestRate=\(.value.status.totalRequestRate // "n/a"))")
        ] | flatten | unique[]?
    ' "${TMP_DIR}/clusters-health.json"
)"

if [[ -n "${health_lines}" ]]; then
    printf '%s\n' "${health_lines}"
else
    printf 'No non-healthy workload or app health reported by Kiali.\n'
fi

printf '\n== Namespace findings ==\n'
for namespace in "${SELECTED_NAMESPACES[@]}"; do
    ns_file="$(namespace_file "${namespace}")"
    fetch_api_json "api/namespaces/${namespace}/istio?validate=true" "${ns_file}"

    pods="$(pod_count "${namespace}")"
    services="$(service_count "${namespace}")"
    service_accounts="$(service_account_count "${namespace}")"
    is_ambient="$(namespace_is_ambient "${namespace}")"

    printf '\n[%s]\n' "${namespace}"
    printf 'Pods: %s, Services: %s, ServiceAccounts: %s, Ambient: %s\n' \
        "${pods}" "${services}" "${service_accounts}" "${is_ambient}"

    validation_lines="$(
        jq -r --arg namespace "${namespace}" '
            [
              .validations
              | ..
              | objects
              | select(has("checks") and .namespace == $namespace)
              | .checks[]?
              | {code, severity, message}
            ]
            | group_by(.code + "|" + .severity + "|" + .message)
            | map({
                count: length,
                code: .[0].code,
                severity: .[0].severity,
                message: .[0].message
              })
            | sort_by(.severity, .code, .message)
            | .[]
            | "\(.severity)\t\(.code)\t\(.count)\t\(.message)"
        ' "${ns_file}"
    )"

    if [[ -z "${validation_lines}" ]]; then
        printf 'No Kiali validation findings for this namespace.\n'
        continue
    fi

    while IFS=$'\t' read -r severity code count message; do
        classification="$(classify_finding "${code}" "${namespace}" "${pods}" "${services}" "${service_accounts}" "${is_ambient}")"
        printf -- '- %s %s x%s: %s\n' "${severity}" "${code}" "${count}" "${message}"
        printf '  classification: %s\n' "${classification}"
    done <<< "${validation_lines}"
done

printf '\n== Suggested interpretation ==\n'
if [[ "${app_deployments_present}" == "0" ]]; then
    printf '%s\n' "- The main blocker is cluster bring-up: none of the seven expected app deployments exist in \`${DEFAULT_NAMESPACE}\`."
    printf '%s\n' "- Do not spend time classifying most \`${DEFAULT_NAMESPACE}\` Kiali validations until the app stack is up; they mostly reflect missing runtime."
elif [[ "$(pod_count "${DEFAULT_NAMESPACE}")" == "0" ]]; then
    printf '%s\n' "- \`${DEFAULT_NAMESPACE}\` has deployment objects missing pods, so Kiali findings there still mostly reflect failed bring-up rather than Kiali integration bugs."
fi

if ! kubectl get svc -n "${MONITORING_NAMESPACE}" jaeger-query >/dev/null 2>&1; then
    printf '%s\n' "- Tracing is a real dependency gap in this cluster: Kiali has tracing enabled, but \`svc/jaeger-query\` is absent."
fi

if jq -e '
    .namespaceWorkloadHealth.monitoring
    | to_entries[]
    | any(.value.status.status == "Failure")
' "${TMP_DIR}/clusters-health.json" >/dev/null 2>&1; then
    printf '%s\n' "- The Prometheus failure in \`monitoring\` is worth investigating separately from the empty-namespace noise. Check Prometheus targets and Envoy telemetry paths."
    printf '%s\n' "- For meshed Prometheus, \`istiod\`, Grafana, Prometheus Operator, and kube-state-metrics should scrape through Service DNS hosts, not pod IPs. Inspect each target \`scrapeUrl\` before treating the failure as a Kiali false positive."
fi

printf '\n== Next commands ==\n'
printf '%s\n' "kubectl get deploy -n ${DEFAULT_NAMESPACE}"
printf '%s\n' './scripts/smoketest/verify-clean-tilt-deployment-admission.sh'
printf '%s\n' './scripts/smoketest/verify-monitoring-runtime.sh'
printf '%s\n' './scripts/smoketest/verify-istio-tracing-config.sh'
printf '%s\n' "kubectl get pods,svc,sa -n ${DEFAULT_NAMESPACE}"
printf '%s\n' "kubectl get svc -n monitoring jaeger-query"

if [[ -n "${OUTPUT_DIR}" ]]; then
    cp "${TMP_DIR}/status.json" "${OUTPUT_DIR}/status.json"
    cp "${TMP_DIR}/namespaces.json" "${OUTPUT_DIR}/namespaces.json"
    cp "${TMP_DIR}/istio-status.json" "${OUTPUT_DIR}/istio-status.json"
    cp "${TMP_DIR}/clusters-health.json" "${OUTPUT_DIR}/clusters-health.json"
    cp "${TMP_DIR}/validations-summary.json" "${OUTPUT_DIR}/validations-summary.json"
    cp "${TMP_DIR}/kiali.log" "${OUTPUT_DIR}/kiali.log"

    for namespace in "${SELECTED_NAMESPACES[@]}"; do
        cp "$(namespace_file "${namespace}")" "${OUTPUT_DIR}/ns-${namespace}-istio-validate.json"
    done

    printf '\nArtifacts written to %s\n' "${OUTPUT_DIR}"
fi
