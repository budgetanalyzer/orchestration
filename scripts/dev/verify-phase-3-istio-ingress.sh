#!/bin/bash

# Runtime verification for Security Hardening v2 Phase 3.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROBE_IMAGE="postgres:16-alpine@sha256:20edbde7749f822887a1a022ad526fde0a47d6b2be9a8364433605cf65099416"
HEADER_ECHO_IMAGE="mendhak/http-https-echo:38@sha256:c73e039e883944a38e37eaba829eb9a67641cd03eff868827683951feceef96e"
CURL_TIMEOUT=10
AUTH_RATE_LIMIT_BURST=15
AUTH_RATE_LIMIT_MATCH_HEADER="x-local-rate-limit: auth-sensitive"
FORGED_XFF_SENTINEL="198.51.100.77"
INGRESS_GATEWAY_LABEL_KEY="gateway.networking.k8s.io/gateway-name"
INGRESS_GATEWAY_LABEL_VALUE="istio-ingress-gateway"
INGRESS_GATEWAY_LABEL_SELECTOR="${INGRESS_GATEWAY_LABEL_KEY}=${INGRESS_GATEWAY_LABEL_VALUE}"
INGRESS_GATEWAY_WORKLOAD_NAME="istio-ingress-gateway-istio"
INGRESS_GATEWAY_SERVICE_ACCOUNT="istio-ingress-gateway-istio"
INGRESS_GATEWAY_PRINCIPAL="cluster.local/ns/istio-ingress/sa/${INGRESS_GATEWAY_SERVICE_ACCOUNT}"

PASSED=0
FAILED=0
TEMP_PODS=()

usage() {
    cat <<'EOF'
Usage: ./scripts/dev/verify-phase-3-istio-ingress.sh

Options:
  -h, --help    Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

pass()    { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail()    { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
section() { printf '\n=== %s ===\n' "$1"; }

cleanup_temp_resources() {
    kubectl delete \
        deployment,service,networkpolicy,authorizationpolicy.security.istio.io,httproute.gateway.networking.k8s.io \
        -n default -l verify-phase3-temp=true --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete networkpolicy \
        -n istio-ingress -l verify-phase3-temp=true --ignore-not-found --wait=false >/dev/null 2>&1 || true
}

cleanup() {
    set +e
    echo ""
    echo "Cleaning up temporary verification resources..."
    cleanup_temp_resources
    for pod_ref in "${TEMP_PODS[@]:-}"; do
        [[ -n "$pod_ref" ]] || continue
        kubectl delete pod "${pod_ref#*/}" -n "${pod_ref%%/*}" \
            --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true
    done
}

trap cleanup EXIT

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_cluster_access() {
    if ! kubectl get namespace default >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes API or default namespace\n' >&2
        exit 1
    fi
}

extract_http_status() {
    printf '%s\n' "$1" | sed -n 's/^[[:space:]]*HTTP\/[^[:space:]]* \([0-9][0-9][0-9]\).*/\1/p' | tail -n 1
}

extract_header_value() {
    local header_name="$1" response="$2"
    printf '%s\n' "$response" | sed -n "s/^[[:space:]]*${header_name}:[[:space:]]*//Ip" | tail -n 1 | tr -d '\r'
}

resource_exists() {
    kubectl get "$1" "$2" -n "$3" >/dev/null 2>&1
}

wait_for_pod_ready() {
    kubectl wait --for=condition=Ready "pod/$2" -n "$1" --timeout="${3:-60s}" >/dev/null 2>&1
}

create_probe() {
    local ns="$1" name="$2"
    shift 2

    local label_lines=""
    for lbl in "$@"; do
        label_lines="${label_lines}    ${lbl%%=*}: \"${lbl#*=}\"
"
    done

    kubectl delete pod "$name" -n "$ns" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "$ns" -f - >/dev/null 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "false"
  labels:
${label_lines}spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
MANIFEST

    TEMP_PODS+=("${ns}/${name}")
}

create_sidecar_probe() {
    local ns="$1" name="$2" sa="$3"
    shift 3

    local label_lines=""
    for lbl in "$@"; do
        label_lines="${label_lines}    ${lbl%%=*}: \"${lbl#*=}\"
"
    done

    kubectl delete pod "$name" -n "$ns" \
        --ignore-not-found --grace-period=0 --force >/dev/null 2>&1 || true

    kubectl apply -n "$ns" -f - >/dev/null 2>&1 <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${name}
  annotations:
    sidecar.istio.io/inject: "true"
  labels:
${label_lines}spec:
  serviceAccountName: ${sa}
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
MANIFEST

    TEMP_PODS+=("${ns}/${name}")
}

http_request_from_pod() {
    local ns="$1" pod="$2" url="$3"
    kubectl exec -n "$ns" "$pod" -- sh -c "wget -S -O - '$url' 2>&1" 2>&1 || true
}

external_status() {
    local path="$1"
    shift
    local status
    status=$(curl -sk -o /dev/null -w '%{http_code}' --max-time "$CURL_TIMEOUT" --max-redirs 0 \
        "$@" "https://app.budgetanalyzer.localhost${path}" 2>/dev/null || true)
    printf '%s\n' "${status:-000}"
}

external_headers_and_status() {
    local path="$1"
    shift
    curl -sk -D - -o /dev/null --max-time "$CURL_TIMEOUT" --max-redirs 0 \
        -w 'HTTP_STATUS:%{http_code}\n' \
        "$@" "https://app.budgetanalyzer.localhost${path}" 2>/dev/null || true
}

retry_external_status() {
    local path="$1"
    shift

    local attempt status
    for attempt in 1 2 3 4 5; do
        status=$(external_status "$path" "$@")
        if [[ "$status" != "000" ]]; then
            printf '%s\n' "$status"
            return 0
        fi
        sleep 2
    done

    printf '%s\n' "${status:-000}"
}

count_status() {
    local status="$1"
    grep -c "^${status}$" || true
}

require_ingress_rate_limit() {
    local path="$1" path_label="$2"
    shift 2

    local tmpdir i num_429s proof_response
    tmpdir=$(mktemp -d)

    for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
        (
            external_headers_and_status "$path" "$@" >"${tmpdir}/${i}"
        ) &
    done

    wait

    num_429s=$(
        for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
            sed -n 's/^HTTP_STATUS://p' "${tmpdir}/${i}"
        done | count_status 429
    )
    if [[ "$num_429s" -ge 1 ]]; then
        pass "${path_label} is rate limited at ingress (saw $num_429s HTTP 429 responses)"
    else
        fail "${path_label} never returned HTTP 429 during a $AUTH_RATE_LIMIT_BURST-request burst"
        rm -rf "$tmpdir"
        return
    fi

    proof_response=$(
        for ((i = 1; i <= AUTH_RATE_LIMIT_BURST; i++)); do
            if [[ "$(sed -n 's/^HTTP_STATUS://p' "${tmpdir}/${i}" | tail -n 1)" == "429" ]]; then
                cat "${tmpdir}/${i}"
                break
            fi
        done
    )

    if printf '%s\n' "$proof_response" | tr -d '\r' | grep -Fqi "${AUTH_RATE_LIMIT_MATCH_HEADER}"; then
        pass "Rate-limited ${path_label} response includes the local rate-limit marker header"
    else
        fail "Rate-limited ${path_label} response did not include ${AUTH_RATE_LIMIT_MATCH_HEADER}"
    fi

    rm -rf "$tmpdir"
}

require_named_resources() {
    local resource_type="$1" namespace="$2"
    shift 2

    local name
    for name in "$@"; do
        if resource_exists "$resource_type" "$name" "$namespace"; then
            pass "${resource_type} ${namespace}/${name} exists"
        else
            fail "Missing ${resource_type} ${namespace}/${name}"
        fi
    done
}

require_named_resources_absent() {
    local resource_type="$1" namespace="$2"
    shift 2

    local name
    for name in "$@"; do
        if resource_exists "$resource_type" "$name" "$namespace"; then
            fail "${resource_type} ${namespace}/${name} still exists"
        else
            pass "${resource_type} ${namespace}/${name} is absent"
        fi
    done
}

egress_policy_targets_gateway_pods() {
    local policy_name="$1" policy_yaml
    policy_yaml=$(kubectl get networkpolicy "$policy_name" -n default -o yaml 2>/dev/null || true)
    [[ -n "$policy_yaml" ]] || return 1

    printf '%s\n' "$policy_yaml" | grep -q "kubernetes.io/metadata.name: istio-egress" &&
        printf '%s\n' "$policy_yaml" | grep -q "app: istio-egress-gateway" &&
        printf '%s\n' "$policy_yaml" | grep -q "istio: egress-gateway"
}

create_header_echo_resources() {
    cleanup_temp_resources

    kubectl apply -f - >/dev/null <<MANIFEST
apiVersion: apps/v1
kind: Deployment
metadata:
  name: p3-header-echo
  namespace: default
  labels:
    app: p3-header-echo
    verify-phase3-temp: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: p3-header-echo
  template:
    metadata:
      labels:
        app: p3-header-echo
        verify-phase3-temp: "true"
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: echo
          image: ${HEADER_ECHO_IMAGE}
          env:
            - name: HTTP_PORT
              value: "8080"
            - name: DISABLE_REQUEST_LOGS
              value: "true"
          ports:
            - containerPort: 8080
              name: http
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
---
apiVersion: v1
kind: Service
metadata:
  name: p3-header-echo
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  selector:
    app: p3-header-echo
  ports:
    - name: http
      port: 8080
      targetPort: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: p3-header-echo-route
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  parentRefs:
    - name: istio-ingress-gateway
      namespace: istio-ingress
  hostnames:
    - app.budgetanalyzer.localhost
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /api/p3-header-echo
      backendRefs:
        - name: p3-header-echo
          port: 8080
---
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: p3-header-echo-policy
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  selector:
    matchLabels:
      app: p3-header-echo
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["${INGRESS_GATEWAY_PRINCIPAL}"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: p3-header-echo-allow
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  podSelector:
    matchLabels:
      app: p3-header-echo
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-ingress
          podSelector:
            matchLabels:
              ${INGRESS_GATEWAY_LABEL_KEY}: ${INGRESS_GATEWAY_LABEL_VALUE}
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istiod
      ports:
        - protocol: TCP
          port: 15012
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: p3-header-echo-egress
  namespace: istio-ingress
  labels:
    verify-phase3-temp: "true"
spec:
  podSelector:
    matchLabels:
      ${INGRESS_GATEWAY_LABEL_KEY}: ${INGRESS_GATEWAY_LABEL_VALUE}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              app: p3-header-echo
      ports:
        - protocol: TCP
          port: 8080
MANIFEST

    kubectl wait --for=condition=Available deployment/p3-header-echo -n default --timeout=180s >/dev/null 2>&1
    kubectl wait --for=jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'=True \
        httproute/p3-header-echo-route -n default --timeout=120s >/dev/null 2>&1
}

create_mtls_echo_resources() {
    cleanup_temp_resources

    kubectl apply -f - >/dev/null <<MANIFEST
apiVersion: apps/v1
kind: Deployment
metadata:
  name: p3-mtls-echo
  namespace: default
  labels:
    app: p3-mtls-echo
    verify-phase3-temp: "true"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: p3-mtls-echo
  template:
    metadata:
      labels:
        app: p3-mtls-echo
        verify-phase3-temp: "true"
    spec:
      automountServiceAccountToken: false
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: echo
          image: ${HEADER_ECHO_IMAGE}
          env:
            - name: HTTP_PORT
              value: "8080"
            - name: DISABLE_REQUEST_LOGS
              value: "true"
          ports:
            - containerPort: 8080
              name: http
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
---
apiVersion: v1
kind: Service
metadata:
  name: p3-mtls-echo
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  selector:
    app: p3-mtls-echo
  ports:
    - name: http
      port: 8080
      targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: p3-mtls-echo-allow
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  podSelector:
    matchLabels:
      app: p3-mtls-echo
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              verify-phase3-temp: "true"
              phase3-role: mtls-client
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istiod
      ports:
        - protocol: TCP
          port: 15012
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: p3-mtls-client-egress
  namespace: default
  labels:
    verify-phase3-temp: "true"
spec:
  podSelector:
    matchLabels:
      verify-phase3-temp: "true"
      phase3-role: mtls-client
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: default
          podSelector:
            matchLabels:
              app: p3-mtls-echo
      ports:
        - protocol: TCP
          port: 8080
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: istio-system
          podSelector:
            matchLabels:
              app: istiod
      ports:
        - protocol: TCP
          port: 15012
MANIFEST

    kubectl wait --for=condition=Available deployment/p3-mtls-echo -n default --timeout=180s >/dev/null 2>&1
}

find_nginx_log_line() {
    local probe_id="$1" attempt nginx_log_line

    for attempt in 1 2 3 4 5; do
        nginx_log_line=$(kubectl logs deployment/nginx-gateway --tail=800 2>/dev/null | grep "$probe_id" | tail -n 1 || true)
        if [[ -n "$nginx_log_line" ]]; then
            printf '%s\n' "$nginx_log_line"
            return 0
        fi
        sleep 2
    done

    return 1
}

verify_forwarded_chain_log() {
    local description="$1" probe_id="$2" nginx_log_line

    nginx_log_line=$(find_nginx_log_line "$probe_id" || true)
    if [[ -n "$nginx_log_line" ]]; then
        pass "NGINX logged the controlled forwarded-chain probe request for ${description}"
    else
        fail "NGINX log does not contain the controlled forwarded-chain probe request for ${description}"
        return
    fi

    if printf '%s\n' "$nginx_log_line" | grep -q 'remote_addr='; then
        pass "NGINX access log emits remote_addr for ${description}"
    else
        fail "NGINX access log format does not emit remote_addr for ${description}"
    fi

    if printf '%s\n' "$nginx_log_line" | grep -q 'proxy_addr='; then
        pass "NGINX access log emits the trusted proxy hop for ${description}"
    else
        fail "NGINX access log format does not emit the trusted proxy hop for ${description}"
    fi

    if printf '%s\n' "$nginx_log_line" | grep -q 'xrealip="'; then
        pass "NGINX access log emits X-Real-IP for ${description}"
    else
        fail "NGINX access log format does not emit X-Real-IP for ${description}"
    fi

    if printf '%s\n' "$nginx_log_line" | grep -Eq "xff=\"${FORGED_XFF_SENTINEL}, ?[^\"]+\""; then
        pass "Istio ingress appended the downstream client hop to X-Forwarded-For for ${description}"
    else
        fail "NGINX access log does not show the expected X-Forwarded-For chain for ${description}"
    fi
}

main() {
    echo "=============================================="
    echo "  Phase 3 Istio Ingress/Egress Verifier"
    echo "=============================================="
    echo

    require_host_command kubectl
    require_host_command curl
    require_cluster_access

    section "Envoy Gateway Removal"

    local envoy_pods
    envoy_pods=$(kubectl get pods -n envoy-gateway-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$envoy_pods" -eq 0 ]]; then
        pass "No pods remain in envoy-gateway-system"
    else
        fail "Found $envoy_pods pod(s) in envoy-gateway-system"
    fi

    if ! kubectl get gatewayclass envoy-proxy >/dev/null 2>&1; then
        pass "Envoy GatewayClass envoy-proxy removed"
    else
        fail "Envoy GatewayClass envoy-proxy still exists"
    fi

    if ! kubectl get gateway ingress-gateway -n default >/dev/null 2>&1; then
        pass "Old Envoy Gateway ingress-gateway removed from default namespace"
    else
        fail "Old Envoy Gateway ingress-gateway still exists in default namespace"
    fi

    section "Gateway Inventory"

    local istio_gatewayclass_status
    istio_gatewayclass_status=$(kubectl get gatewayclass istio \
        -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    if [[ "$istio_gatewayclass_status" == "True" ]]; then
        pass "GatewayClass istio exists and is accepted"
    else
        fail "GatewayClass istio is missing or not accepted"
    fi

    local ingress_programmed
    ingress_programmed=$(kubectl get gateway.gateway.networking.k8s.io istio-ingress-gateway -n istio-ingress \
        -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
    if [[ "$ingress_programmed" == "True" ]]; then
        pass "Gateway API gateway istio-ingress/istio-ingress-gateway is Programmed=True"
    else
        fail "Gateway API gateway istio-ingress/istio-ingress-gateway is missing or not Programmed=True"
    fi

    local ingress_pods
    ingress_pods=$(kubectl get pods -n istio-ingress -l "${INGRESS_GATEWAY_LABEL_SELECTOR}" --no-headers 2>/dev/null | grep -c Running || true)
    if [[ "$ingress_pods" -ge 1 ]]; then
        pass "Istio ingress gateway pod Running ($ingress_pods instance(s))"
    else
        fail "No Running Istio ingress gateway pods"
    fi

    local ingress_service_selector ingress_service_account ingress_https_target_port
    ingress_service_selector=$(kubectl get svc -n istio-ingress "${INGRESS_GATEWAY_WORKLOAD_NAME}" \
        -o go-template='{{ range $k, $v := .spec.selector }}{{ $k }}={{ $v }}{{ end }}' 2>/dev/null || true)
    if [[ "$ingress_service_selector" == *"${INGRESS_GATEWAY_LABEL_SELECTOR}"* ]]; then
        pass "Istio ingress Service selector matches ${INGRESS_GATEWAY_LABEL_SELECTOR}"
    else
        fail "Istio ingress Service selector is ${ingress_service_selector:-missing} (expected ${INGRESS_GATEWAY_LABEL_SELECTOR})"
    fi

    ingress_service_account=$(kubectl get deployment -n istio-ingress "${INGRESS_GATEWAY_WORKLOAD_NAME}" \
        -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || true)
    if [[ "$ingress_service_account" == "$INGRESS_GATEWAY_SERVICE_ACCOUNT" ]]; then
        pass "Istio ingress Deployment uses ServiceAccount ${INGRESS_GATEWAY_SERVICE_ACCOUNT}"
    else
        fail "Istio ingress Deployment uses ServiceAccount ${ingress_service_account:-missing} (expected ${INGRESS_GATEWAY_SERVICE_ACCOUNT})"
    fi

    ingress_https_target_port=$(kubectl get svc -n istio-ingress "${INGRESS_GATEWAY_WORKLOAD_NAME}" \
        -o go-template='{{ range .spec.ports }}{{ if eq .name "https" }}{{ .targetPort }}{{ end }}{{ end }}' 2>/dev/null || true)
    if [[ "$ingress_https_target_port" == "443" ]]; then
        pass "Istio ingress Service https targetPort is 443"
    else
        fail "Istio ingress Service https targetPort is ${ingress_https_target_port:-missing} (expected 443)"
    fi

    if resource_exists gateway.networking.istio.io istio-egress-gateway default; then
        pass "Istio networking gateway default/istio-egress-gateway exists"
    else
        fail "Missing Istio networking gateway default/istio-egress-gateway"
    fi

    local egress_pods
    egress_pods=$(kubectl get pods -n istio-egress -l istio=egress-gateway --no-headers 2>/dev/null | grep -c Running || true)
    if [[ "$egress_pods" -ge 1 ]]; then
        pass "Istio egress gateway pod Running ($egress_pods instance(s))"
    else
        fail "No Running Istio egress gateway pods"
    fi

    require_named_resources serviceentry default auth0-idp fred-api

    section "Ingress Path"

    local app_status api_status login_headers login_status oauth2_headers oauth2_status oauth2_location
    local auth_route_matches auth_route_backends health_status
    app_status=$(external_status "/")
    if [[ "$app_status" == "200" ]]; then
        pass "GET / returns 200"
    else
        fail "GET / returns $app_status (expected 200)"
    fi

    api_status=$(external_status "/api/v1/transactions")
    if [[ "$api_status" == "401" || "$api_status" == "403" ]]; then
        pass "GET /api/v1/transactions returns $api_status for an unauthenticated client"
    else
        fail "GET /api/v1/transactions returns $api_status (expected 401 or 403)"
    fi

    login_headers=$(external_headers_and_status "/login")
    login_status=$(printf '%s\n' "$login_headers" | sed -n 's/^HTTP_STATUS://p' | tail -n 1)
    if [[ "$login_status" == "200" ]]; then
        pass "GET /login returns 200"
    else
        fail "GET /login returns $login_status (expected 200)"
    fi

    oauth2_headers=$(external_headers_and_status "/oauth2/authorization/idp")
    oauth2_status=$(printf '%s\n' "$oauth2_headers" | sed -n 's/^HTTP_STATUS://p' | tail -n 1)
    if [[ "$oauth2_status" == "302" ]]; then
        pass "GET /oauth2/authorization/idp returns 302"
    else
        fail "GET /oauth2/authorization/idp returns $oauth2_status (expected 302)"
    fi

    oauth2_location=$(extract_header_value "location" "$oauth2_headers")
    if [[ "$oauth2_location" == *"redirect_uri=https://app.budgetanalyzer.localhost/login/oauth2/code/idp"* ]] ||
       [[ "$oauth2_location" == *"redirect_uri=https%3A%2F%2Fapp.budgetanalyzer.localhost%2Flogin%2Foauth2%2Fcode%2Fidp"* ]]; then
        pass "OAuth2 initiation redirect uses the Session Gateway callback path"
    else
        fail "OAuth2 initiation redirect does not reference https://app.budgetanalyzer.localhost/login/oauth2/code/idp"
    fi

    auth_route_matches=$(kubectl get httproute auth-route -n default \
        -o go-template='{{ range .spec.rules }}{{ range .matches }}{{ if .path }}{{ printf "%s:%s\n" .path.type .path.value }}{{ end }}{{ end }}{{ end }}' 2>/dev/null || true)
    if printf '%s\n' "$auth_route_matches" | grep -Fxq 'PathPrefix:/login/oauth2'; then
        pass "HTTPRoute default/auth-route matches the Session Gateway callback prefix"
    else
        fail "HTTPRoute default/auth-route is missing PathPrefix /login/oauth2"
    fi

    if ! printf '%s\n' "$auth_route_matches" | grep -Fxq 'PathPrefix:/login'; then
        pass "HTTPRoute default/auth-route no longer claims bare /login"
    else
        fail "HTTPRoute default/auth-route still claims bare /login"
    fi

    auth_route_backends=$(kubectl get httproute auth-route -n default \
        -o go-template='{{ range .spec.rules }}{{ range .backendRefs }}{{ printf "%s:%v\n" .name .port }}{{ end }}{{ end }}' 2>/dev/null || true)
    if printf '%s\n' "$auth_route_backends" | grep -Fxq 'session-gateway:8081'; then
        pass "HTTPRoute default/auth-route still targets session-gateway:8081"
    else
        fail "HTTPRoute default/auth-route is not targeting session-gateway:8081"
    fi

    health_status=$(external_status "/health")
    if [[ "$health_status" == "200" ]]; then
        pass "GET /health returns 200"
    else
        fail "GET /health returns $health_status (expected 200)"
    fi

    section "Auth Endpoint Rate Limiting"

    if resource_exists envoyfilter ingress-auth-local-rate-limit istio-ingress; then
        pass "EnvoyFilter istio-ingress/ingress-auth-local-rate-limit exists"
    else
        fail "Missing EnvoyFilter istio-ingress/ingress-auth-local-rate-limit"
    fi

    require_ingress_rate_limit "/login?phase3-ingress-rate-limit=1" "/login"
    require_ingress_rate_limit "/oauth2/authorization/idp" "/oauth2/authorization/idp"
    require_ingress_rate_limit "/user" "/user"

    section "Header Sanitization"

    echo "  Creating temporary echo route for end-to-end header verification..."
    create_header_echo_resources

    local session_id echo_response echo_status echo_body
    session_id="phase3-echo-$(date +%s)"
    "${SCRIPT_DIR}/seed-ext-authz-session.sh" "$session_id" >/dev/null

    echo_response=$(curl -sk --max-time "$CURL_TIMEOUT" \
        -H 'X-User-Id: forged-user-999' \
        -H 'X-Roles: ROLE_FORGED' \
        -H 'X-Permissions: forged:all' \
        --cookie "SESSION=${session_id}" \
        -w '\nHTTP_STATUS:%{http_code}\n' \
        "https://app.budgetanalyzer.localhost/api/p3-header-echo?phase3_header_echo=${session_id}" 2>/dev/null || true)
    echo_status=$(printf '%s\n' "$echo_response" | sed -n 's/^HTTP_STATUS://p' | tail -n 1)
    echo_body=$(printf '%s\n' "$echo_response" | sed '/^HTTP_STATUS:/d')

    if [[ "$echo_status" == "200" ]]; then
        pass "Temporary header echo route returned 200 with a seeded SESSION cookie"
    else
        fail "Temporary header echo route returned $echo_status (expected 200)"
    fi

    if printf '%s\n' "$echo_body" | grep -Fq 'test-user-001'; then
        pass "Echo backend received the ext_authz user id"
    else
        fail "Echo backend did not receive the ext_authz user id"
    fi

    if printf '%s\n' "$echo_body" | grep -Fq 'ROLE_USER,ROLE_ADMIN'; then
        pass "Echo backend received the ext_authz roles"
    else
        fail "Echo backend did not receive the ext_authz roles"
    fi

    if printf '%s\n' "$echo_body" | grep -Fq 'transactions:read,transactions:write,currencies:read'; then
        pass "Echo backend received the ext_authz permissions"
    else
        fail "Echo backend did not receive the ext_authz permissions"
    fi

    if ! printf '%s\n' "$echo_body" | grep -Fq 'forged-user-999'; then
        pass "Forged X-User-Id header was overwritten before reaching the backend"
    else
        fail "Forged X-User-Id header survived the ingress path"
    fi

    if ! printf '%s\n' "$echo_body" | grep -Fq 'ROLE_FORGED'; then
        pass "Forged X-Roles header was overwritten before reaching the backend"
    else
        fail "Forged X-Roles header survived the ingress path"
    fi

    if ! printf '%s\n' "$echo_body" | grep -Fq 'forged:all'; then
        pass "Forged X-Permissions header was overwritten before reaching the backend"
    else
        fail "Forged X-Permissions header survived the ingress path"
    fi

    cleanup_temp_resources

    section "mTLS Enforcement"

    require_named_resources peerauthentication default default-strict
    require_named_resources_absent peerauthentication default \
        nginx-gateway-permissive \
        ext-authz-permissive \
        session-gateway-permissive

    echo "  Creating temporary in-mesh echo service for STRICT mTLS verification..."
    create_mtls_echo_resources

    echo "  Creating sidecar and no-sidecar probes for HTTP-level mTLS verification..."
    create_sidecar_probe default "p3-mtls-sidecar" "default" \
        "verify-phase3-temp=true" \
        "app=p3-mtls-sidecar" \
        "phase3-role=mtls-client"
    create_probe default "p3-mtls-probe" \
        "verify-phase3-temp=true" \
        "app=p3-mtls-probe" \
        "phase3-role=mtls-client"
    wait_for_pod_ready default p3-mtls-sidecar 90s
    wait_for_pod_ready default p3-mtls-probe 30s

    local mtls_sidecar_output mtls_sidecar_status mtls_nosidecar_output mtls_nosidecar_status
    mtls_sidecar_output=$(http_request_from_pod \
        default p3-mtls-sidecar \
        "http://p3-mtls-echo.default.svc.cluster.local:8080/")
    mtls_sidecar_status=$(extract_http_status "$mtls_sidecar_output")
    if [[ "$mtls_sidecar_status" == "200" ]]; then
        pass "Sidecar-injected probe completed an HTTP request to p3-mtls-echo under STRICT mTLS"
    else
        fail "Sidecar-injected probe returned HTTP ${mtls_sidecar_status:-none} from p3-mtls-echo (expected 200)"
    fi

    mtls_nosidecar_output=$(http_request_from_pod \
        default p3-mtls-probe \
        "http://p3-mtls-echo.default.svc.cluster.local:8080/")
    mtls_nosidecar_status=$(extract_http_status "$mtls_nosidecar_output")
    if [[ "$mtls_nosidecar_status" != "200" ]]; then
        pass "No-sidecar probe could not complete an HTTP request to p3-mtls-echo under STRICT mTLS"
    else
        fail "No-sidecar probe unexpectedly received HTTP 200 from p3-mtls-echo"
    fi

    cleanup_temp_resources

    section "AuthorizationPolicy (Ingress Identity)"

    require_named_resources authorizationpolicy default \
        transaction-service-policy \
        currency-service-policy \
        permission-service-policy \
        budget-analyzer-web-policy \
        nginx-gateway-policy \
        ext-authz-policy \
        session-gateway-policy
    require_named_resources authorizationpolicy istio-ingress ext-authz-at-ingress

    local ext_authz_selector nginx_principal ext_authz_principal session_principal
    ext_authz_selector=$(kubectl get authorizationpolicy.security.istio.io ext-authz-at-ingress -n istio-ingress \
        -o go-template='{{ range $k, $v := .spec.selector.matchLabels }}{{ $k }}={{ $v }}{{ end }}' 2>/dev/null || true)
    if [[ "$ext_authz_selector" == *"${INGRESS_GATEWAY_LABEL_SELECTOR}"* ]]; then
        pass "ext-authz-at-ingress targets ${INGRESS_GATEWAY_LABEL_SELECTOR}"
    else
        fail "ext-authz-at-ingress selector is ${ext_authz_selector:-missing} (expected ${INGRESS_GATEWAY_LABEL_SELECTOR})"
    fi

    nginx_principal=$(kubectl get authorizationpolicy.security.istio.io nginx-gateway-policy -n default \
        -o jsonpath='{.spec.rules[0].from[0].source.principals[0]}' 2>/dev/null || true)
    if [[ "$nginx_principal" == "$INGRESS_GATEWAY_PRINCIPAL" ]]; then
        pass "nginx-gateway-policy allows ${INGRESS_GATEWAY_PRINCIPAL}"
    else
        fail "nginx-gateway-policy allows ${nginx_principal:-missing} (expected ${INGRESS_GATEWAY_PRINCIPAL})"
    fi

    ext_authz_principal=$(kubectl get authorizationpolicy.security.istio.io ext-authz-policy -n default \
        -o jsonpath='{.spec.rules[0].from[0].source.principals[0]}' 2>/dev/null || true)
    if [[ "$ext_authz_principal" == "$INGRESS_GATEWAY_PRINCIPAL" ]]; then
        pass "ext-authz-policy allows ${INGRESS_GATEWAY_PRINCIPAL}"
    else
        fail "ext-authz-policy allows ${ext_authz_principal:-missing} (expected ${INGRESS_GATEWAY_PRINCIPAL})"
    fi

    session_principal=$(kubectl get authorizationpolicy.security.istio.io session-gateway-policy -n default \
        -o jsonpath='{.spec.rules[0].from[0].source.principals[0]}' 2>/dev/null || true)
    if [[ "$session_principal" == "$INGRESS_GATEWAY_PRINCIPAL" ]]; then
        pass "session-gateway-policy allows ${INGRESS_GATEWAY_PRINCIPAL}"
    else
        fail "session-gateway-policy allows ${session_principal:-missing} (expected ${INGRESS_GATEWAY_PRINCIPAL})"
    fi

    echo "  Creating wrong-identity sidecar probe in istio-ingress namespace..."
    create_sidecar_probe istio-ingress "p3-wrong-identity" "default" \
        "${INGRESS_GATEWAY_LABEL_SELECTOR}"
    wait_for_pod_ready istio-ingress p3-wrong-identity 90s

    local authz_output authz_status
    authz_output=$(http_request_from_pod \
        istio-ingress p3-wrong-identity \
        "http://nginx-gateway.default.svc.cluster.local:8080/health")
    authz_status=$(extract_http_status "$authz_output")
    if [[ "$authz_status" == "403" ]]; then
        pass "Wrong-identity mesh workload received HTTP 403 from nginx-gateway"
    else
        fail "Wrong-identity mesh workload returned HTTP ${authz_status:-none} (expected 403)"
    fi

    section "Egress Control"

    local mesh_config
    mesh_config=$(kubectl get cm istio -n istio-system -o jsonpath='{.data.mesh}' 2>/dev/null || true)
    if printf '%s\n' "$mesh_config" | grep -q "REGISTRY_ONLY"; then
        pass "Mesh outboundTrafficPolicy is REGISTRY_ONLY"
    else
        fail "Mesh outboundTrafficPolicy is not REGISTRY_ONLY"
    fi

    local auth0_host auth0_output fred_host fred_output denied_output
    auth0_host=$(kubectl get serviceentry auth0-idp -n default -o jsonpath='{.spec.hosts[0]}' 2>/dev/null || true)
    if [[ -n "$auth0_host" ]]; then
        auth0_output=$(kubectl exec deployment/session-gateway -c session-gateway -- \
            wget -S --spider --timeout=10 "https://${auth0_host}/" 2>&1 || true)
        if printf '%s\n' "$auth0_output" | grep -qE "HTTP/[0-9.]+ [0-9]+"; then
            pass "session-gateway reaches approved Auth0 host via the egress gateway"
        else
            fail "session-gateway could not reach approved Auth0 host ${auth0_host}"
        fi
    else
        fail "Could not determine Auth0 host from ServiceEntry auth0-idp"
    fi

    fred_host=$(kubectl get serviceentry fred-api -n default -o jsonpath='{.spec.hosts[0]}' 2>/dev/null || true)
    if [[ -n "$fred_host" ]]; then
        fred_output=$(kubectl exec deployment/currency-service -c currency-service -- \
            wget -S --spider --timeout=10 "https://${fred_host}/" 2>&1 || true)
        if printf '%s\n' "$fred_output" | grep -qE "HTTP/[0-9.]+ [0-9]+"; then
            pass "currency-service reaches approved FRED host via the egress gateway"
        else
            fail "currency-service could not reach approved FRED host ${fred_host}"
        fi
    else
        fail "Could not determine FRED host from ServiceEntry fred-api"
    fi

    denied_output=$(kubectl exec deployment/session-gateway -c session-gateway -- \
        wget -S --spider --timeout=5 "https://example.com/" 2>&1 || true)
    if printf '%s\n' "$denied_output" | grep -qE "HTTP/[0-9.]+ [0-9]+"; then
        fail "session-gateway reached unapproved host example.com"
    else
        pass "session-gateway is blocked from unapproved host example.com"
    fi

    section "Client IP Forwarding"

    local app_probe_id api_probe_id session_id app_probe_status api_probe_status
    app_probe_id="phase3-xff-app-$(date +%s)"
    app_probe_status=$(retry_external_status "/?phase3_client_ip_test=${app_probe_id}" \
        -H "X-Forwarded-For: ${FORGED_XFF_SENTINEL}" \
        -A "phase3-xff/${app_probe_id}")
    if [[ "$app_probe_status" == "200" ]]; then
        pass "Frontend forwarded-chain probe returned 200"
    else
        fail "Frontend forwarded-chain probe returned ${app_probe_status:-000} (expected 200)"
    fi

    session_id="phase3-xff-api-$(date +%s)"
    "${SCRIPT_DIR}/seed-ext-authz-session.sh" "$session_id" >/dev/null
    api_probe_id="phase3-xff-api-$(date +%s)"
    api_probe_status=$(retry_external_status "/api/v1/transactions?phase3_client_ip_test=${api_probe_id}" \
        -H "X-Forwarded-For: ${FORGED_XFF_SENTINEL}" \
        -A "phase3-xff/${api_probe_id}" \
        --cookie "SESSION=${session_id}")
    if [[ "$api_probe_status" == "200" ]]; then
        pass "Authenticated API forwarded-chain probe returned 200"
    else
        fail "Authenticated API forwarded-chain probe returned ${api_probe_status:-000} (expected 200)"
    fi

    verify_forwarded_chain_log "frontend traffic" "$app_probe_id"
    verify_forwarded_chain_log "API traffic" "$api_probe_id"

    section "Network Policies"

    require_named_resources networkpolicy istio-ingress \
        istio-ingress-deny-all \
        allow-istio-ingress-dns-egress \
        allow-istio-ingress-istiod-egress \
        allow-istio-ingress-external-ingress \
        allow-istio-ingress-egress-to-default-services
    require_named_resources networkpolicy istio-egress \
        istio-egress-deny-all \
        allow-istio-egress-dns-egress \
        allow-istio-egress-istiod-egress \
        allow-istio-egress-ingress-from-default \
        allow-istio-egress-external-egress

    if egress_policy_targets_gateway_pods allow-session-gateway-egress; then
        pass "session-gateway egress is constrained to the istio-egress gateway pods"
    else
        fail "session-gateway egress policy is not constrained to the istio-egress gateway pods"
    fi

    if egress_policy_targets_gateway_pods allow-currency-service-egress; then
        pass "currency-service egress is constrained to the istio-egress gateway pods"
    else
        fail "currency-service egress policy is not constrained to the istio-egress gateway pods"
    fi

    echo ""
    echo "=============================================="
    local total=$((PASSED + FAILED))
    if [[ "$FAILED" -eq 0 ]]; then
        echo "  ${PASSED} passed (out of ${total})"
    else
        echo "  ${PASSED} passed, ${FAILED} failed (out of ${total})"
    fi
    echo "=============================================="

    [[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
