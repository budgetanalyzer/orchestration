#!/bin/bash

# cleanup-smoketest-residue.sh - Bounded, fail-closed removal of test resources
# left behind by interrupted live verifiers. smoketest.sh runs it first.
#
# It removes only objects that a verifier marks as its own, by the verifier's
# temp label or by an exact verifier name pattern. RESIDUE_INVENTORY below is
# the single list of what it removes; keep it aligned with the verifiers.
#
# Known limits:
# - Redis session keys created by verify-ingress-rate-limits.sh are not
#   removed. The key name is random per run and cannot be identified later.
# - /tmp/edge-browser-prod-nginx.* files that verify-edge-browser-hardening.sh
#   writes inside the nginx-gateway pod are left; they go away on pod restart.
# - ext-authz or Redis scaled to 0 is reported, not repaired.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # Repo-local library path is resolved dynamically from SCRIPT_DIR.
source "${SCRIPT_DIR}/../lib/local-kubernetes-target.sh"

KUBECTL_REQUEST_TIMEOUT="20s"
DELETE_TIMEOUT="60s"
NAMESPACE_DELETE_TIMEOUT="180s"
ROLLOUT_TIMEOUT="120s"
READY_WAIT_SECONDS=60
ENDPOINT_SETTLE_SECONDS=30
PORT_FORWARD_TERM_GRACE_SECONDS=5

# Namespaces whose Services must be backed only by controller-owned pods.
SERVICE_NAMESPACES=(default monitoring istio-ingress istio-egress)

# Deletion order matters: controllers before pods, and pods before the
# Services and policies around them. Fields:
#   kind|namespaces ("-" for cluster-scoped)|match|selector|owning verifier
# match is one of:
#   label         kubectl label selector
#   name          regex on the object name
#   unowned-name  regex on the name of a pod without ownerReferences
RESIDUE_INVENTORY=(
    "deployment|default|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "pod|default monitoring istio-ingress istio-egress|label|verify-network-policies-temp=true|verify-network-policies.sh"
    "pod|default monitoring istio-ingress istio-egress|unowned-name|^np2-|verify-network-policies.sh (unlabeled earlier run)"
    "pod|default|label|verify-transport-encryption-temp=true|verify-transport-encryption.sh"
    "pod|default|label|verify-runtime-security-guardrails-temp=true|verify-runtime-security-guardrails.sh"
    "pod|default istio-ingress|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "pod|istio-ingress|unowned-name|^p3-wrong-identity$|verify-istio-ingress.sh (unlabeled earlier run)"
    "pod|default|label|verify-ingress-rate-limits-temp=true|verify-ingress-rate-limits.sh"
    "pod|default|label|verify-security-prereqs-temp=true|verify-security-prereqs.sh"
    "pod|default|unowned-name|^istio-sidecar-smoke$|verify-security-prereqs.sh (unlabeled earlier run)"
    "service|default monitoring|label|verify-network-policies-temp=true|verify-network-policies.sh"
    "service|default monitoring|name|^np2-|verify-network-policies.sh (unlabeled earlier run)"
    "service|default|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "networkpolicy|default infrastructure|label|verify-transport-encryption-temp=true|verify-transport-encryption.sh"
    "networkpolicy|default infrastructure|label|verify-runtime-security-guardrails-temp=true|verify-runtime-security-guardrails.sh"
    "networkpolicy|default istio-ingress|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "networkpolicy|default|label|verify-ingress-rate-limits-temp=true|verify-ingress-rate-limits.sh"
    "authorizationpolicy.security.istio.io|default|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "httproute.gateway.networking.k8s.io|default|label|verify-istio-ingress-temp=true|verify-istio-ingress.sh"
    "configmap|default|label|verify-ingress-rate-limits-temp=true|verify-ingress-rate-limits.sh"
    "namespace|-|name|^ba-(netpol|psa|kyverno)-[0-9]+-[0-9]+$|verify-security-prereqs.sh"
    "namespace|-|name|^ba-phase5-psa-[0-9]+$|verify-runtime-hardening.sh"
    "clusternetworkpolicy.policy.networking.k8s.io|-|name|^edge-contract-block-ingress-to-ext-authz-[0-9]+$|verify-edge-contract.sh --inject-failures"
)

# Temporary vhosts created by verify-runtime-security-guardrails.sh.
RABBITMQ_NAMESPACE="infrastructure"
RABBITMQ_ADMIN_USERNAME="rabbitmq-admin"
RABBITMQ_TEMP_VHOST_PATTERN='^runtime-guardrails-[0-9]+$'

# Verifier port-forwards always use a random local port (":<remote>") and no
# --address flag. Arguments after "kubectl" must match one of these exactly.
# Fixed-port or --address forwards are operator guest publication and never
# match.
PORT_FORWARD_SIGNATURES=(
    '^port-forward -n infrastructure service/rabbitmq :15672$'
    '^port-forward -n default deployment/ext-authz :(8090|9002)$'
    '^port-forward deployment/nginx-gateway -n default :8080$'
    '^port-forward -n istio-ingress pod/istio-ingress-gateway-istio-[a-z0-9]+-[a-z0-9]+ :443$'
)

INGRESS_NAMESPACE="istio-ingress"
INGRESS_DEPLOYMENT="istio-ingress-gateway-istio"
# kubernetes/istio/ingress-gateway-config.yaml, the Gateway parametersRef, sets
# no replica count and the Istio gateway controller does not own
# spec.replicas, so the Kubernetes Deployment default of 1 applies.
# verify-ingress-rate-limits.sh requires that value before it scales to 2.
INGRESS_INTENDED_REPLICAS=1

# Workloads that verify-edge-contract.sh --inject-failures scales to 0. The
# intended counts come from kubernetes/services/ext-authz/deployment.yaml and
# kubernetes/infrastructure/redis/statefulset.yaml.
REQUIRED_WORKLOADS=(
    "default|deployment|ext-authz|1"
    "infrastructure|statefulset|redis|1"
)

DRY_RUN=false
FAILURES=0
REMOVED_TOTAL=0
TMP_DIR=""

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/cleanup-smoketest-residue.sh [--dry-run]

Removes test resources left by interrupted live verifiers: labeled or
verifier-named pods, Services, policies, ConfigMaps and Deployments, temporary
namespaces, the edge-contract ClusterNetworkPolicy, temporary RabbitMQ vhosts,
and orphaned verifier kubectl port-forwards. It restores the ingress gateway
replica count, then fails unless no residue remains, every Service endpoint in
default, monitoring, istio-ingress and istio-egress is a controller-owned pod,
and ext-authz and Redis have a ready replica.

Every mutation requires the exact local kind-kind target.

Options:
  --dry-run   List what would be removed or restored and change nothing.
  -h, --help  Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

cleanup_tmp() {
    [[ -z "${TMP_DIR}" ]] || rm -rf "${TMP_DIR}"
}
trap cleanup_tmp EXIT

k() {
    kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" "$@"
}

info() { printf '  %s\n' "$1"; }
failure() {
    printf '  [FAIL] %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

print_stderr_file() {
    sed -n '1,20s/^/    /p' "${TMP_DIR}/stderr" >&2
}

# Prints "<kind>/<name>" refs for one inventory entry in one namespace.
list_refs() {
    local kind="$1" namespace="$2" match="$3" selector="$4"
    local -a scope=()
    local output ref

    [[ "${namespace}" == "-" ]] || scope=(-n "${namespace}")

    case "${match}" in
        label)
            output=$(k get "${kind}" "${scope[@]}" -l "${selector}" -o name 2>"${TMP_DIR}/stderr") ||
                { list_error "${kind}" "${namespace}"; return $?; }
            printf '%s' "${output}${output:+$'\n'}"
            ;;
        name)
            output=$(k get "${kind}" "${scope[@]}" -o name 2>"${TMP_DIR}/stderr") ||
                { list_error "${kind}" "${namespace}"; return $?; }
            while IFS= read -r ref; do
                if [[ -n "${ref}" && "${ref##*/}" =~ ${selector} ]]; then
                    printf '%s\n' "${ref}"
                fi
            done <<<"${output}"
            ;;
        unowned-name)
            output=$(k get "${kind}" "${scope[@]}" -o json 2>"${TMP_DIR}/stderr") ||
                { list_error "${kind}" "${namespace}"; return $?; }
            jq -r --arg re "${selector}" '
                .items[]
                | select((.metadata.ownerReferences // []) | length == 0)
                | select(.metadata.name | test($re))
                | "pod/" + .metadata.name' <<<"${output}"
            ;;
        *)
            printf 'ERROR: unknown inventory match type: %s\n' "${match}" >&2
            return 1
            ;;
    esac
}

# A kind whose API is not installed cannot have residue; any other listing
# error fails closed.
list_error() {
    if grep -q "doesn't have a resource type" "${TMP_DIR}/stderr"; then
        return 0
    fi
    printf '  [FAIL] Could not list %s in %s\n' "$1" "$2" >&2
    print_stderr_file
    return 1
}

delete_refs() {
    local kind="$1" namespace="$2"
    shift 2
    local -a scope=() options=(--ignore-not-found --wait=true)

    [[ "${namespace}" == "-" ]] || scope=(-n "${namespace}")
    case "${kind}" in
        pod) options+=(--grace-period=0 --force --timeout="${DELETE_TIMEOUT}") ;;
        namespace) options+=(--timeout="${NAMESPACE_DELETE_TIMEOUT}") ;;
        *) options+=(--timeout="${DELETE_TIMEOUT}") ;;
    esac

    k delete "${scope[@]}" "$@" "${options[@]}" >/dev/null 2>"${TMP_DIR}/stderr"
}

report_stuck_namespace() {
    local namespace="$1"

    failure "Namespace ${namespace} is still present after ${NAMESPACE_DELETE_TIMEOUT}; finalizers were not removed"
    k get namespace "${namespace}" -o json 2>/dev/null | jq -r '
        "    phase: \(.status.phase // "unknown")",
        "    spec.finalizers: \((.spec.finalizers // []) | join(", "))",
        "    metadata.finalizers: \((.metadata.finalizers // []) | join(", "))",
        (.status.conditions // [] | .[] | select(.status == "True") | "    \(.type): \(.message)")
    ' >&2 || true
    info "Remaining contents:" >&2
    k get all -n "${namespace}" --no-headers 2>&1 | sed -n '1,20s/^/    /p' >&2 || true
}

remove_inventory_residue() {
    local entry kind namespaces match selector owner namespace output count where ref
    local -a refs
    # Legacy name entries also match labeled objects; handle each object once.
    local -A seen=()

    for entry in "${RESIDUE_INVENTORY[@]}"; do
        IFS='|' read -r kind namespaces match selector owner <<<"${entry}"
        for namespace in ${namespaces}; do
            if ! output=$(list_refs "${kind}" "${namespace}" "${match}" "${selector}"); then
                FAILURES=$((FAILURES + 1))
                continue
            fi
            refs=()
            while IFS= read -r ref; do
                [[ -n "${ref}" && -z "${seen["${namespace}|${ref}"]:-}" ]] || continue
                seen["${namespace}|${ref}"]=1
                refs+=("${ref}")
            done <<<"${output}"
            [[ "${#refs[@]}" -gt 0 ]] || continue
            count="${#refs[@]}"
            where="in ${namespace}"
            [[ "${namespace}" != "-" ]] || where="(cluster-scoped)"

            if [[ "${DRY_RUN}" == true ]]; then
                info "Would remove ${count} ${kind} ${where} (${match} ${selector}; ${owner}):"
                printf '    %s\n' "${refs[@]}"
                REMOVED_TOTAL=$((REMOVED_TOTAL + count))
                continue
            fi

            if delete_refs "${kind}" "${namespace}" "${refs[@]}"; then
                info "Removed ${count} ${kind} ${where} (${match} ${selector}; ${owner})"
                REMOVED_TOTAL=$((REMOVED_TOTAL + count))
            elif [[ "${kind}" == namespace ]]; then
                for ref in "${refs[@]}"; do
                    if k get "${ref}" >/dev/null 2>&1; then
                        report_stuck_namespace "${ref#*/}"
                    fi
                done
            else
                failure "Could not remove ${count} ${kind} ${where} (${match} ${selector})"
                print_stderr_file
            fi
        done
    done
}

count_inventory_residue() {
    local entry kind namespaces match selector owner namespace refs remaining=0

    for entry in "${RESIDUE_INVENTORY[@]}"; do
        IFS='|' read -r kind namespaces match selector owner <<<"${entry}"
        for namespace in ${namespaces}; do
            if ! refs=$(list_refs "${kind}" "${namespace}" "${match}" "${selector}"); then
                remaining=$((remaining + 1))
                continue
            fi
            if [[ -n "${refs}" ]]; then
                printf '    %s %s: %s\n' "${namespace}" "${kind}" "$(tr '\n' ' ' <<<"${refs}")" >&2
                remaining=$((remaining + $(wc -l <<<"${refs}")))
            fi
        done
    done

    printf '%s\n' "${remaining}"
}

# Prints "<ns>/<service> -> pod/<name>" for every EndpointSlice pod target
# that has no ownerReferences or no longer exists. With "skip-verifier",
# Services carrying a verifier temp label are left out.
unowned_endpoint_targets() {
    local skip_verifier=false namespace

    [[ "${1:-}" != skip-verifier ]] || skip_verifier=true
    for namespace in "${SERVICE_NAMESPACES[@]}"; do
        k get endpointslices -n "${namespace}" -o json >"${TMP_DIR}/slices.json" 2>"${TMP_DIR}/stderr" ||
            { print_stderr_file; return 1; }
        k get pods -n "${namespace}" -o json >"${TMP_DIR}/pods.json" 2>"${TMP_DIR}/stderr" ||
            { print_stderr_file; return 1; }
        jq -rn --arg ns "${namespace}" --argjson skip_verifier "${skip_verifier}" \
            --slurpfile slices "${TMP_DIR}/slices.json" \
            --slurpfile pods "${TMP_DIR}/pods.json" '
            ($pods[0].items
                | map({key: .metadata.name, value: ((.metadata.ownerReferences // []) | length > 0)})
                | from_entries) as $owned
            | $slices[0].items[]
            | select($skip_verifier and ((.metadata.labels // {})
                | to_entries
                | any(.key | test("^verify-[a-z0-9-]+-temp$"))) | not)
            | .metadata.labels["kubernetes.io/service-name"] as $svc
            | .endpoints[]?
            | select(.targetRef.kind == "Pod")
            | .targetRef.name as $pod
            | select(($owned[$pod] // false) | not)
            | "\($ns)/\($svc) -> pod/\($pod)"
                + (if $owned | has($pod) then "" else " (pod not found)" end)'
    done | sort -u
}

report_impersonating_pods() {
    local targets

    targets=$(unowned_endpoint_targets skip-verifier) ||
        { failure "Could not read Service EndpointSlices"; return; }
    [[ -n "${targets}" ]] || return 0

    info "Unowned pods were backing Services before cleanup and received their traffic:"
    printf '    %s\n' "${targets//$'\n'/$'\n    '}"
    info "Kiali health uses a 10-minute rate window, so verify-monitoring-runtime.sh can"
    info "report these errors as Kiali Failure until about 10 minutes after cleanup."
}

assert_owned_endpoint_targets() {
    local deadline=$((SECONDS + ENDPOINT_SETTLE_SECONDS)) targets

    while true; do
        targets=$(unowned_endpoint_targets) || { failure "Could not read Service EndpointSlices"; return; }
        [[ -n "${targets}" ]] || return 0
        (( SECONDS < deadline )) || break
        sleep 2
    done

    failure "Services in ${SERVICE_NAMESPACES[*]} are still backed by pods without an owner:"
    printf '    %s\n' "${targets//$'\n'/$'\n    '}" >&2
}

rabbitmq_pod() {
    k get pods -n "${RABBITMQ_NAMESPACE}" -l app=rabbitmq \
        -o jsonpath='{.items[0].metadata.name}' 2>"${TMP_DIR}/stderr"
}

list_temp_vhosts() {
    local pod="$1" output vhost

    output=$(timeout 30s kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" \
        exec -n "${RABBITMQ_NAMESPACE}" "${pod}" -- \
        rabbitmqctl list_vhosts name --silent --timeout 20 2>"${TMP_DIR}/stderr") || return 1
    while IFS= read -r vhost; do
        if [[ "${vhost}" =~ ${RABBITMQ_TEMP_VHOST_PATTERN} ]]; then
            printf '%s\n' "${vhost}"
        fi
    done <<<"${output}"
}

remove_rabbitmq_vhosts() {
    local pod password vhost output removed=0
    local -a vhosts

    if ! pod=$(rabbitmq_pod) || [[ -z "${pod}" ]]; then
        failure "Could not find the RabbitMQ pod to check temporary vhosts"
        return
    fi
    if ! output=$(list_temp_vhosts "${pod}"); then
        failure "Could not list RabbitMQ vhosts"
        print_stderr_file
        return
    fi
    [[ -n "${output}" ]] || return 0
    mapfile -t vhosts <<<"${output}"

    if [[ "${DRY_RUN}" == true ]]; then
        info "Would remove ${#vhosts[@]} RabbitMQ vhost (verify-runtime-security-guardrails.sh):"
        printf '    %s\n' "${vhosts[@]}"
        REMOVED_TOTAL=$((REMOVED_TOTAL + ${#vhosts[@]}))
        return
    fi

    password=$(k get secret rabbitmq-bootstrap-credentials -n "${RABBITMQ_NAMESPACE}" \
        -o "jsonpath={.data['password']}" 2>/dev/null | base64 -d 2>/dev/null || true)
    if [[ -z "${password}" ]]; then
        failure "Could not read the RabbitMQ admin password to remove temporary vhosts"
        return
    fi

    for vhost in "${vhosts[@]}"; do
        # The pattern check above guarantees this is never the default "/" vhost.
        if timeout 30s kubectl --request-timeout="${KUBECTL_REQUEST_TIMEOUT}" \
            exec -n "${RABBITMQ_NAMESPACE}" "${pod}" -- \
            rabbitmqadmin -q --timeout 20 -u "${RABBITMQ_ADMIN_USERNAME}" -p "${password}" \
            delete vhost --name "${vhost}" --idempotently >/dev/null 2>"${TMP_DIR}/stderr"; then
            removed=$((removed + 1))
        else
            failure "Could not remove RabbitMQ vhost ${vhost}"
            print_stderr_file
        fi
    done
    if (( removed > 0 )); then
        info "Removed ${removed} RabbitMQ vhost (verify-runtime-security-guardrails.sh)"
        REMOVED_TOTAL=$((REMOVED_TOTAL + removed))
    fi
}

assert_no_temp_vhosts() {
    local pod remaining

    pod=$(rabbitmq_pod) || return 0
    if ! remaining=$(list_temp_vhosts "${pod}"); then
        failure "Could not re-list RabbitMQ vhosts"
        return
    fi
    if [[ -n "${remaining}" ]]; then
        failure "Temporary RabbitMQ vhosts remain: $(tr '\n' ' ' <<<"${remaining}")"
    fi
}

# Prints "<pid> <args>" for orphaned verifier port-forwards owned by this user.
orphaned_verifier_port_forwards() {
    local proc_dir pid ppid args signature
    local -a argv

    for proc_dir in /proc/[0-9]*; do
        [[ -O "${proc_dir}" ]] || continue
        pid="${proc_dir#/proc/}"
        ppid=$(awk '/^PPid:/ { print $2 }' "${proc_dir}/status" 2>/dev/null) || continue
        [[ "${ppid}" == "1" ]] || continue
        mapfile -d '' -t argv 2>/dev/null <"${proc_dir}/cmdline" || continue
        [[ "${#argv[@]}" -gt 1 && "${argv[0]##*/}" == kubectl ]] || continue
        args="${argv[*]:1}"
        for signature in "${PORT_FORWARD_SIGNATURES[@]}"; do
            if [[ "${args}" =~ ${signature} ]]; then
                printf '%s %s\n' "${pid}" "${args}"
                break
            fi
        done
    done
}

remove_orphaned_port_forwards() {
    local -a lines pids=()
    local line pid alive waited=0

    mapfile -t lines < <(orphaned_verifier_port_forwards)
    [[ "${#lines[@]}" -gt 0 ]] || return 0

    if [[ "${DRY_RUN}" == true ]]; then
        info "Would stop ${#lines[@]} orphaned verifier kubectl port-forward process:"
        printf '    %s\n' "${lines[@]}"
        REMOVED_TOTAL=$((REMOVED_TOTAL + ${#lines[@]}))
        return
    fi

    for line in "${lines[@]}"; do
        pids+=("${line%% *}")
    done
    kill -TERM "${pids[@]}" 2>/dev/null || true
    while (( waited < PORT_FORWARD_TERM_GRACE_SECONDS )); do
        alive=false
        for pid in "${pids[@]}"; do
            if kill -0 "${pid}" 2>/dev/null; then
                alive=true
                break
            fi
        done
        [[ "${alive}" == true ]] || break
        sleep 1
        waited=$((waited + 1))
    done
    for pid in "${pids[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    done
    info "Stopped ${#pids[@]} orphaned verifier kubectl port-forward process"
    REMOVED_TOTAL=$((REMOVED_TOTAL + ${#pids[@]}))
}

restore_ingress_replicas() {
    local replicas probes

    if ! replicas=$(k get deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
        -o jsonpath='{.spec.replicas}' 2>"${TMP_DIR}/stderr"); then
        failure "Could not read deployment/${INGRESS_DEPLOYMENT} in ${INGRESS_NAMESPACE}"
        print_stderr_file
        return
    fi
    [[ "${replicas}" != "${INGRESS_INTENDED_REPLICAS}" ]] || return 0

    if [[ "${DRY_RUN}" == true ]]; then
        info "Would restore deployment/${INGRESS_DEPLOYMENT} from ${replicas} to ${INGRESS_INTENDED_REPLICAS} replicas (verify-ingress-rate-limits.sh)"
        return
    fi

    if ! probes=$(list_refs pod default name '^ingress-rate-limit-probe-'); then
        FAILURES=$((FAILURES + 1))
        return
    fi
    if [[ -n "${probes}" ]]; then
        failure "Ingress has ${replicas} replicas and rate-limit probe pods still exist; not restoring"
        return
    fi

    if k scale deployment "${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
        --replicas="${INGRESS_INTENDED_REPLICAS}" >/dev/null 2>"${TMP_DIR}/stderr" &&
        k rollout status deployment/"${INGRESS_DEPLOYMENT}" -n "${INGRESS_NAMESPACE}" \
            --timeout="${ROLLOUT_TIMEOUT}" >/dev/null 2>"${TMP_DIR}/stderr"; then
        info "Restored deployment/${INGRESS_DEPLOYMENT} from ${replicas} to ${INGRESS_INTENDED_REPLICAS} replicas (verify-ingress-rate-limits.sh)"
        REMOVED_TOTAL=$((REMOVED_TOTAL + 1))
    else
        failure "Could not restore deployment/${INGRESS_DEPLOYMENT} to ${INGRESS_INTENDED_REPLICAS} replicas"
        print_stderr_file
    fi
}

assert_required_workloads() {
    local entry namespace kind name intended replicas ready deadline

    for entry in "${REQUIRED_WORKLOADS[@]}"; do
        IFS='|' read -r namespace kind name intended <<<"${entry}"
        if ! replicas=$(k get "${kind}" "${name}" -n "${namespace}" \
            -o jsonpath='{.spec.replicas}' 2>"${TMP_DIR}/stderr"); then
            failure "Could not read ${kind}/${name} in ${namespace}"
            print_stderr_file
            continue
        fi
        if [[ "${replicas}" == "0" ]]; then
            failure "${kind}/${name} in ${namespace} is scaled to 0, likely by an interrupted verify-edge-contract.sh --inject-failures run. Not scaling it back. To recover:"
            printf '    kubectl scale %s %s -n %s --replicas=%s\n' "${kind}" "${name}" "${namespace}" "${intended}" >&2
            continue
        fi

        deadline=$((SECONDS + READY_WAIT_SECONDS))
        while true; do
            ready=$(k get "${kind}" "${name}" -n "${namespace}" \
                -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
            (( ${ready:-0} >= 1 )) && break
            if (( SECONDS >= deadline )); then
                failure "${kind}/${name} in ${namespace} has no ready replica after ${READY_WAIT_SECONDS}s"
                break
            fi
            sleep 3
        done
    done
}

# Deleting residue while a verifier runs would break that verifier.
live_verifier_processes() {
    pgrep -u "$(id -u)" -a -f '^[^ ]*bash [^ ]*smoketest/verify-[a-z0-9-]+\.sh' || true
}

main() {
    local command_name live remaining

    for command_name in kubectl kind jq timeout pgrep; do
        if ! command -v "${command_name}" >/dev/null 2>&1; then
            printf 'ERROR: required command not found: %s\n' "${command_name}" >&2
            exit 1
        fi
    done

    if ! assert_local_kind_target; then
        printf 'ERROR: refusing to inspect or clean smoketest residue outside the exact local Kind target.\n' >&2
        exit 1
    fi

    TMP_DIR=$(mktemp -d)

    live=$(live_verifier_processes)
    if [[ -n "${live}" ]]; then
        printf 'Live verifier processes found:\n%s\n' "${live}" | sed 's/^/  /' >&2
        if [[ "${DRY_RUN}" != true ]]; then
            printf 'ERROR: a verifier is running; cleanup would delete its resources. Stop it or wait for it to finish.\n' >&2
            exit 1
        fi
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        echo "Dry run: listing smoketest residue without changing anything."
    fi

    report_impersonating_pods
    remove_inventory_residue
    remove_rabbitmq_vhosts
    remove_orphaned_port_forwards
    restore_ingress_replicas

    if [[ "${DRY_RUN}" == true ]]; then
        assert_required_workloads
        if (( FAILURES > 0 )); then
            printf 'Dry run found %d problem(s) that cleanup will not repair.\n' "${FAILURES}" >&2
            exit 1
        fi
        if (( REMOVED_TOTAL == 0 )); then
            echo "Dry run: no smoketest residue found."
        else
            printf 'Dry run: cleanup would remove or restore %d item(s).\n' "${REMOVED_TOTAL}"
        fi
        exit 0
    fi

    remaining=$(count_inventory_residue)
    if [[ "${remaining}" != "0" ]]; then
        failure "${remaining} inventory residue object(s) remain after cleanup"
    fi
    assert_no_temp_vhosts
    if [[ -n "$(orphaned_verifier_port_forwards)" ]]; then
        failure "Orphaned verifier port-forwards remain after SIGKILL"
    fi
    assert_owned_endpoint_targets
    assert_required_workloads

    if (( FAILURES > 0 )); then
        printf 'Smoketest residue cleanup failed with %d problem(s).\n' "${FAILURES}" >&2
        exit 1
    fi

    if (( REMOVED_TOTAL == 0 )); then
        echo "No smoketest residue found."
    else
        printf 'Smoketest residue cleanup removed or restored %d item(s).\n' "${REMOVED_TOTAL}"
    fi
}

main
