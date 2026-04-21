#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_WAIT_TIMEOUT="${PHASE7_MONITORING_HELM_WAIT_TIMEOUT:-5m}"
VERIFY_RUNTIME=false
APPLY_JAEGER_KIALI=true

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # common.sh is resolved from SCRIPT_DIR at runtime.
source "${SCRIPT_DIR}/lib/common.sh"

MONITORING_NAMESPACE="monitoring"
readonly MONITORING_NAMESPACE
PROMETHEUS_RELEASE_NAME="prometheus-stack"
readonly PROMETHEUS_RELEASE_NAME
PROMETHEUS_CHART_NAME="prometheus-community/kube-prometheus-stack"
readonly PROMETHEUS_CHART_NAME
MONITORING_NAMESPACE_FILE="$(phase4_repo_path "kubernetes/monitoring/namespace.yaml")"
readonly MONITORING_NAMESPACE_FILE
GRAFANA_DASHBOARDS_FILE="$(phase4_repo_path "kubernetes/monitoring/grafana-dashboards-configmap.yaml")"
readonly GRAFANA_DASHBOARDS_FILE
PROMETHEUS_VALUES_FILE="$(phase4_repo_path "kubernetes/monitoring/prometheus-stack-values.yaml")"
readonly PROMETHEUS_VALUES_FILE
PROMETHEUS_PRODUCTION_VALUES_FILE="$(phase4_repo_path "kubernetes/production/monitoring/prometheus-stack-values.override.yaml")"
readonly PROMETHEUS_PRODUCTION_VALUES_FILE
PROMETHEUS_POST_RENDERER="$(phase4_repo_path "scripts/ops/post-render-prometheus-stack.sh")"
readonly PROMETHEUS_POST_RENDERER
SPRING_BOOT_SERVICE_MONITOR_FILE="$(phase4_repo_path "kubernetes/monitoring/servicemonitor-spring-boot.yaml")"
readonly SPRING_BOOT_SERVICE_MONITOR_FILE
PRODUCTION_VERIFIER="$(phase4_repo_path "scripts/guardrails/verify-production-image-overlay.sh")"
readonly PRODUCTION_VERIFIER
MONITORING_RUNTIME_VERIFIER="$(phase4_repo_path "scripts/smoketest/verify-monitoring-runtime.sh")"
readonly MONITORING_RUNTIME_VERIFIER

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/22-apply-production-monitoring.sh [options]

Idempotently reapplies the production monitoring stack: Prometheus/Grafana,
Grafana dashboards, Spring Boot ServiceMonitor, and by default the reviewed
Jaeger/Kiali observability apply path.

Options:
  --skip-jaeger-kiali   Reapply only the Prometheus/Grafana baseline.
  --verify-runtime      Run the Spring Boot/Grafana dashboard input verifier
                        after the apply completes.
  -h, --help            Show this help text.
EOF
}

require_file() {
    local path="$1"

    [[ -f "${path}" ]] || phase4_die "missing required file: ${path}"
}

wait_for_monitoring_pods() {
    phase4_info "waiting for Grafana Deployment"
    kubectl rollout status deployment/prometheus-stack-grafana \
        -n "${MONITORING_NAMESPACE}" \
        --timeout="${HELM_WAIT_TIMEOUT}"

    phase4_info "waiting for Prometheus pods"
    kubectl wait pod \
        -n "${MONITORING_NAMESPACE}" \
        -l app.kubernetes.io/name=prometheus \
        --for=condition=Ready \
        --timeout="${HELM_WAIT_TIMEOUT}"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-jaeger-kiali)
                APPLY_JAEGER_KIALI=false
                ;;
            --verify-runtime)
                VERIFY_RUNTIME=true
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                phase4_die "unknown option: $1"
                ;;
        esac
        shift
    done

    phase4_load_instance_env
    phase4_require_commands helm kubectl
    phase4_require_cluster_access

    require_file "${MONITORING_NAMESPACE_FILE}"
    require_file "${GRAFANA_DASHBOARDS_FILE}"
    require_file "${PROMETHEUS_VALUES_FILE}"
    require_file "${PROMETHEUS_PRODUCTION_VALUES_FILE}"
    require_file "${SPRING_BOOT_SERVICE_MONITOR_FILE}"
    [[ -x "${PROMETHEUS_POST_RENDERER}" ]] || phase4_die "missing executable Prometheus post-renderer: ${PROMETHEUS_POST_RENDERER}"
    [[ -x "${PRODUCTION_VERIFIER}" ]] || phase4_die "missing executable production verifier: ${PRODUCTION_VERIFIER}"

    phase4_info "applying monitoring namespace"
    kubectl apply -f "${MONITORING_NAMESPACE_FILE}"

    phase4_info "re-running the production verifier before live monitoring apply"
    "${PRODUCTION_VERIFIER}"

    phase4_info "applying Grafana dashboard ConfigMap"
    kubectl apply -f "${GRAFANA_DASHBOARDS_FILE}"

    phase4_info "updating Helm repo prometheus-community"
    phase4_ensure_helm_repo prometheus-community "${PHASE7_PROMETHEUS_STACK_HELM_REPO_URL}"
    helm repo update prometheus-community >/dev/null

    phase4_info "installing kube-prometheus-stack ${PHASE7_PROMETHEUS_STACK_CHART_VERSION} (timeout ${HELM_WAIT_TIMEOUT})"
    helm upgrade --install "${PROMETHEUS_RELEASE_NAME}" "${PROMETHEUS_CHART_NAME}" \
        --namespace "${MONITORING_NAMESPACE}" \
        --version "${PHASE7_PROMETHEUS_STACK_CHART_VERSION}" \
        --values "${PROMETHEUS_VALUES_FILE}" \
        --values "${PROMETHEUS_PRODUCTION_VALUES_FILE}" \
        --post-renderer "${PROMETHEUS_POST_RENDERER}" \
        --wait \
        --timeout "${HELM_WAIT_TIMEOUT}"

    phase4_info "applying Spring Boot ServiceMonitor"
    kubectl apply -f "${SPRING_BOOT_SERVICE_MONITOR_FILE}"

    phase4_info "restarting Grafana so dashboard provisioning reloads the ConfigMap"
    kubectl rollout restart deployment/prometheus-stack-grafana -n "${MONITORING_NAMESPACE}"
    wait_for_monitoring_pods

    if [[ "${APPLY_JAEGER_KIALI}" == "true" ]]; then
        phase4_info "reapplying Jaeger and Kiali"
        "${SCRIPT_DIR}/21-apply-phase-7-observability.sh"
    fi

    if [[ "${VERIFY_RUNTIME}" == "true" ]]; then
        [[ -x "${MONITORING_RUNTIME_VERIFIER}" ]] || phase4_die "missing executable runtime verifier: ${MONITORING_RUNTIME_VERIFIER}"
        phase4_info "running monitoring runtime verifier"
        "${MONITORING_RUNTIME_VERIFIER}" --wait-timeout 180
    fi

    phase4_info "production monitoring service snapshot"
    kubectl get svc -n "${MONITORING_NAMESPACE}" \
        prometheus-stack-grafana \
        prometheus-stack-kube-prom-prometheus \
        jaeger-query \
        kiali \
        --ignore-not-found
}

main "$@"
