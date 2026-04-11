#!/bin/bash

# Runtime verification for Security Hardening v2 Phase 7 Session 7.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROBE_NAMESPACE="default"
INFRA_NAMESPACE="infrastructure"
TEMP_LABEL_KEY="verify-phase7-temp"
TEMP_LABEL_VALUE="true"
REDIS_PROBE_NAME="phase7-redis-acl-probe"
POSTGRES_PROBE_NAME="phase7-postgresql-authz-probe"
RABBITMQ_PROBE_NAME="phase7-rabbitmq-authz-probe"
REDIS_PROBE_IMAGE="redis:7-alpine@sha256:8b81dd37ff027bec4e516d41acfbe9fe2460070dc6d4a4570a2ac5b9d59df065"
POSTGRES_PROBE_IMAGE="postgres:16-alpine@sha256:20edbde7749f822887a1a022ad526fde0a47d6b2be9a8364433605cf65099416"
RABBITMQ_PROBE_IMAGE="python:3.12-alpine@sha256:7747d47f92cfca63a6e2b50275e23dba8407c30d8ae929a88ddd49a5d3f2d331"
WAIT_TIMEOUT="${PHASE7_WAIT_TIMEOUT:-120s}"
REGRESSION_TIMEOUT="${PHASE7_REGRESSION_TIMEOUT:-35m}"
RUN_ID="$(date +%s)"
REDIS_ALLOWED_KEY="currency-service:phase7-runtime:${RUN_ID}"
REDIS_DENIED_KEY="session:phase7-runtime:${RUN_ID}"
RABBITMQ_TEMP_VHOST="phase7-runtime-${RUN_ID}"
RABBITMQ_FORBIDDEN_QUEUE="phase7.runtime.forbidden.queue.${RUN_ID}"
RABBITMQ_FORBIDDEN_EXCHANGE="phase7.runtime.forbidden.exchange.${RUN_ID}"
REDIS_CURRENCY_SERVICE_USERNAME="currency-service"
POSTGRES_TRANSACTION_USERNAME="transaction_service"
POSTGRES_PERMISSION_USERNAME="permission_service"
RABBITMQ_ADMIN_USERNAME="rabbitmq-admin"
RABBITMQ_ADMIN_VHOST="/"
RABBITMQ_CURRENCY_SERVICE_USERNAME="currency-service"

NEW_PASSED=0
NEW_FAILED=0
REUSED_PASSED=0
REUSED_FAILED=0
RABBITMQ_TEMP_VHOST_CREATED=false

usage() {
    cat <<'EOF'
Usage: ./scripts/smoketest/verify-phase-7-runtime-guardrails.sh

Options:
  -h, --help                    Show this help text.

Environment:
  PHASE7_WAIT_TIMEOUT           Timeout for temporary probe readiness (default: 120s)
  PHASE7_REGRESSION_TIMEOUT     Timeout for the reused Phase 6 regression umbrella
                                verifier (default: 35m)
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

section()      { printf '\n=== %s ===\n' "$1"; }
info()         { printf '  [INFO] %s\n' "$1"; }
pass_new()     { printf '  [PASS] %s\n' "$1"; NEW_PASSED=$((NEW_PASSED + 1)); }
fail_new()     { printf '  [FAIL] %s\n' "$1" >&2; NEW_FAILED=$((NEW_FAILED + 1)); }
pass_reused()  { printf '  [PASS] %s\n' "$1"; REUSED_PASSED=$((REUSED_PASSED + 1)); }
fail_reused()  { printf '  [FAIL] %s\n' "$1" >&2; REUSED_FAILED=$((REUSED_FAILED + 1)); }

cleanup_temp_resources() {
    kubectl delete pod -n "${PROBE_NAMESPACE}" -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found --wait=false >/dev/null 2>&1 || true
    kubectl delete networkpolicy -n "${PROBE_NAMESPACE}" -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete networkpolicy -n "${INFRA_NAMESPACE}" -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" \
        --ignore-not-found >/dev/null 2>&1 || true
}

delete_rabbitmq_temp_vhost() {
    local rabbitmq_pod admin_username admin_password admin_vhost

    if [[ "${RABBITMQ_TEMP_VHOST_CREATED}" != true ]]; then
        return
    fi

    rabbitmq_pod=$(kubectl get pods -n "${INFRA_NAMESPACE}" -l app=rabbitmq \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    admin_username="${RABBITMQ_ADMIN_USERNAME}"
    admin_password=$(kubectl get secret rabbitmq-bootstrap-credentials -n "${INFRA_NAMESPACE}" \
        -o "jsonpath={.data['password']}" 2>/dev/null | base64 -d 2>/dev/null || true)
    admin_vhost="${RABBITMQ_ADMIN_VHOST}"

    if [[ -n "${rabbitmq_pod}" && -n "${admin_username}" && -n "${admin_password}" ]]; then
        kubectl exec -n "${INFRA_NAMESPACE}" "${rabbitmq_pod}" -- \
            rabbitmqadmin -q -u "${admin_username}" -p "${admin_password}" -V "${admin_vhost}" \
            delete vhost name="${RABBITMQ_TEMP_VHOST}" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    set +e
    echo ""
    echo "Cleaning up temporary verification resources..."
    delete_rabbitmq_temp_vhost
    cleanup_temp_resources
}

trap cleanup EXIT

require_host_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

current_context() {
    kubectl config current-context 2>/dev/null || printf 'unknown'
}

require_cluster_access() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        printf 'ERROR: Cannot reach Kubernetes cluster from current kubectl context (%s)\n' "$(current_context)" >&2
        exit 1
    fi
}

require_secret_exists() {
    local namespace="$1"
    local secret_name="$2"

    if ! kubectl get secret "${secret_name}" -n "${namespace}" >/dev/null 2>&1; then
        printf 'ERROR: required secret not found: %s/%s (context: %s)\n' \
            "${namespace}" "${secret_name}" "$(current_context)" >&2
        exit 1
    fi
}

require_secret_value() {
    local namespace="$1"
    local secret_name="$2"
    local key="$3"
    local encoded value

    require_secret_exists "${namespace}" "${secret_name}"
    encoded=$(kubectl get secret "${secret_name}" -n "${namespace}" \
        -o "jsonpath={.data['${key}']}" 2>/dev/null || true)

    if [[ -z "${encoded}" ]]; then
        printf 'ERROR: missing secret value %s/%s[%s] (context: %s)\n' \
            "${namespace}" "${secret_name}" "${key}" "$(current_context)" >&2
        exit 1
    fi

    value=$(printf '%s' "${encoded}" | base64 -d)
    if [[ -z "${value}" ]]; then
        printf 'ERROR: decoded secret value is empty for %s/%s[%s] (context: %s)\n' \
            "${namespace}" "${secret_name}" "${key}" "$(current_context)" >&2
        exit 1
    fi

    printf '%s' "${value}"
}

require_pod() {
    local namespace="$1"
    local selector="$2"
    local label="$3"
    local pod

    pod=$(kubectl get pods -n "${namespace}" -l "${selector}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [[ -z "${pod}" ]]; then
        printf 'ERROR: %s pod not found in namespace %s (selector: %s, context: %s)\n' \
            "${label}" "${namespace}" "${selector}" "$(current_context)" >&2
        exit 1
    fi

    printf '%s' "${pod}"
}

capture_command() {
    local out_var_name="$1"
    shift

    local -n out_ref="${out_var_name}"
    local captured_output status
    set +e
    captured_output="$("$@" 2>&1)"
    status=$?
    set -e

    out_ref="${captured_output}"
    return "${status}"
}

create_temp_resources() {
    cleanup_temp_resources

    kubectl apply -f - >/dev/null <<MANIFEST
apiVersion: v1
kind: Pod
metadata:
  name: ${REDIS_PROBE_NAME}
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase7-role: redis
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${REDIS_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 999
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: v1
kind: Pod
metadata:
  name: ${POSTGRES_PROBE_NAME}
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase7-role: postgresql
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${POSTGRES_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: v1
kind: Pod
metadata:
  name: ${RABBITMQ_PROBE_NAME}
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
    verify-phase7-role: rabbitmq
  annotations:
    sidecar.istio.io/inject: "false"
spec:
  automountServiceAccountToken: false
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: probe
      image: ${RABBITMQ_PROBE_IMAGE}
      command: ["sh", "-c", "sleep 3600"]
      env:
        - name: HOME
          value: /tmp
      volumeMounts:
        - name: infra-ca
          mountPath: /tls-ca
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
  terminationGracePeriodSeconds: 0
  volumes:
    - name: infra-ca
      secret:
        secretName: infra-ca
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-redis-probe-egress
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
      verify-phase7-role: redis
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INFRA_NAMESPACE}
          podSelector:
            matchLabels:
              app: redis
      ports:
        - protocol: TCP
          port: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-postgresql-probe-egress
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
      verify-phase7-role: postgresql
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INFRA_NAMESPACE}
          podSelector:
            matchLabels:
              app: postgresql
      ports:
        - protocol: TCP
          port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-rabbitmq-probe-egress
  namespace: ${PROBE_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
      verify-phase7-role: rabbitmq
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${INFRA_NAMESPACE}
          podSelector:
            matchLabels:
              app: rabbitmq
      ports:
        - protocol: TCP
          port: 5671
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-redis-probe-ingress
  namespace: ${INFRA_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: redis
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${PROBE_NAMESPACE}
          podSelector:
            matchLabels:
              ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
              verify-phase7-role: redis
      ports:
        - protocol: TCP
          port: 6379
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-postgresql-probe-ingress
  namespace: ${INFRA_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: postgresql
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${PROBE_NAMESPACE}
          podSelector:
            matchLabels:
              ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
              verify-phase7-role: postgresql
      ports:
        - protocol: TCP
          port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: phase7-rabbitmq-probe-ingress
  namespace: ${INFRA_NAMESPACE}
  labels:
    ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ${PROBE_NAMESPACE}
          podSelector:
            matchLabels:
              ${TEMP_LABEL_KEY}: "${TEMP_LABEL_VALUE}"
              verify-phase7-role: rabbitmq
      ports:
        - protocol: TCP
          port: 5671
MANIFEST
}

wait_for_probe_ready() {
    kubectl wait --for=condition=Ready "pod/$1" -n "${PROBE_NAMESPACE}" --timeout="${WAIT_TIMEOUT}" >/dev/null
}

redis_cli_probe() {
    local username="$1"
    local password="$2"
    shift 2

    kubectl exec -n "${PROBE_NAMESPACE}" "${REDIS_PROBE_NAME}" -- \
        env "REDISCLI_AUTH=${password}" \
        redis-cli \
        --tls \
        --cacert /tls-ca/ca.crt \
        --user "${username}" \
        --no-auth-warning \
        -h redis.infrastructure \
        "$@"
}

postgres_probe() {
    local username="$1"
    local password="$2"
    local database="$3"
    local sql="$4"

    kubectl exec -n "${PROBE_NAMESPACE}" "${POSTGRES_PROBE_NAME}" -- \
        env "PGPASSWORD=${password}" \
        psql -X -tA \
        "host=postgresql.infrastructure user=${username} dbname=${database} sslmode=verify-full sslrootcert=/tls-ca/ca.crt" \
        -c "${sql}"
}

rabbitmq_admin() {
    local pod="$1"
    local username="$2"
    local password="$3"
    local vhost="$4"
    shift 4

    kubectl exec -n "${INFRA_NAMESPACE}" "${pod}" -- \
        rabbitmqadmin -q -u "${username}" -p "${password}" -V "${vhost}" "$@"
}

rabbitmq_amqps_probe() {
    local action="$1"
    local username="$2"
    local password="$3"
    local vhost="$4"
    local resource_name="${5:-}"

    kubectl exec -n "${PROBE_NAMESPACE}" "${RABBITMQ_PROBE_NAME}" -- sh -ceu '
python - "$@" <<'"'"'PY'"'"'
import socket
import ssl
import struct
import sys

ACTION, USERNAME, PASSWORD, VHOST, RESOURCE = sys.argv[1:6]
HOST = "rabbitmq.infrastructure"
PORT = 5671
SERVER_NAME = "rabbitmq.infrastructure"
FRAME_END = 0xCE
FRAME_METHOD = 1
FRAME_HEARTBEAT = 8
CONNECTION_CLASS = 10
CHANNEL_CLASS = 20
EXCHANGE_CLASS = 40
QUEUE_CLASS = 50


class ProbeError(Exception):
    pass


class BrokerClosed(Exception):
    def __init__(self, scope, code, text, class_id, method_id):
        super().__init__(f"{scope} close {code} {text}")
        self.scope = scope
        self.code = code
        self.text = text
        self.class_id = class_id
        self.method_id = method_id


def recv_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise ProbeError(f"socket closed while reading {size} bytes")
        data.extend(chunk)
    return bytes(data)


def read_frame(sock):
    header = recv_exact(sock, 7)
    frame_type = header[0]
    channel = struct.unpack(">H", header[1:3])[0]
    size = struct.unpack(">I", header[3:7])[0]
    payload = recv_exact(sock, size)
    frame_end = recv_exact(sock, 1)[0]
    if frame_end != FRAME_END:
        raise ProbeError(f"unexpected frame terminator {frame_end}")
    return frame_type, channel, payload


def method_parts(payload):
    class_id, method_id = struct.unpack(">HH", payload[:4])
    return class_id, method_id, payload[4:]


def read_shortstr(payload, offset):
    length = payload[offset]
    start = offset + 1
    end = start + length
    return payload[start:end].decode(), end


def read_close(payload):
    reply_code = struct.unpack(">H", payload[:2])[0]
    reply_text, offset = read_shortstr(payload, 2)
    class_id, method_id = struct.unpack(">HH", payload[offset:offset + 4])
    return reply_code, reply_text, class_id, method_id


def encode_shortstr(value):
    encoded = value.encode()
    if len(encoded) > 255:
        raise ProbeError("shortstr too long")
    return bytes([len(encoded)]) + encoded


def encode_longstr_bytes(value):
    return struct.pack(">I", len(value)) + value


def empty_table():
    return struct.pack(">I", 0)


def send_method(sock, channel, class_id, method_id, args=b""):
    payload = struct.pack(">HH", class_id, method_id) + args
    frame = bytes([FRAME_METHOD]) + struct.pack(">H", channel) + struct.pack(">I", len(payload)) + payload + bytes([FRAME_END])
    sock.sendall(frame)


def next_method(sock):
    while True:
        frame_type, channel, payload = read_frame(sock)
        if frame_type == FRAME_HEARTBEAT:
            continue
        if frame_type != FRAME_METHOD:
            raise ProbeError(f"unexpected frame type {frame_type}")
        class_id, method_id, args = method_parts(payload)
        if class_id == CONNECTION_CLASS and method_id == 50:
            reply_code, reply_text, close_class_id, close_method_id = read_close(args)
            send_method(sock, 0, CONNECTION_CLASS, 51)
            raise BrokerClosed("connection", reply_code, reply_text, close_class_id, close_method_id)
        if class_id == CHANNEL_CLASS and method_id == 40:
            reply_code, reply_text, close_class_id, close_method_id = read_close(args)
            send_method(sock, channel, CHANNEL_CLASS, 41)
            raise BrokerClosed("channel", reply_code, reply_text, close_class_id, close_method_id)
        return channel, class_id, method_id, args


def expect_method(sock, expected_channel, expected_class, expected_method):
    channel, class_id, method_id, args = next_method(sock)
    if channel != expected_channel or class_id != expected_class or method_id != expected_method:
        raise ProbeError(
            f"expected channel={expected_channel} class={expected_class} method={expected_method}, "
            f"got channel={channel} class={class_id} method={method_id}"
        )
    return args


def close_connection(sock):
    try:
        args = struct.pack(">H", 200) + encode_shortstr("bye") + struct.pack(">HH", 0, 0)
        send_method(sock, 0, CONNECTION_CLASS, 50, args)
        expect_method(sock, 0, CONNECTION_CLASS, 51)
    except Exception:
        pass


def connect(username, password, vhost):
    raw_sock = socket.create_connection((HOST, PORT), timeout=5)
    context = ssl.create_default_context(cafile="/tls-ca/ca.crt")
    context.check_hostname = True
    context.verify_mode = ssl.CERT_REQUIRED
    sock = context.wrap_socket(raw_sock, server_hostname=SERVER_NAME)
    sock.settimeout(5)
    sock.sendall(b"AMQP\x00\x00\x09\x01")

    expect_method(sock, 0, CONNECTION_CLASS, 10)
    start_ok_args = (
        empty_table()
        + encode_shortstr("PLAIN")
        + encode_longstr_bytes(f"\0{username}\0{password}".encode())
        + encode_shortstr("en_US")
    )
    send_method(sock, 0, CONNECTION_CLASS, 11, start_ok_args)

    tune_args = expect_method(sock, 0, CONNECTION_CLASS, 30)
    channel_max, frame_max, heartbeat = struct.unpack(">HIH", tune_args[:8])
    send_method(sock, 0, CONNECTION_CLASS, 31, struct.pack(">HIH", channel_max, frame_max, heartbeat))
    open_args = encode_shortstr(vhost) + encode_shortstr("") + b"\x00"
    send_method(sock, 0, CONNECTION_CLASS, 40, open_args)
    expect_method(sock, 0, CONNECTION_CLASS, 41)
    return sock


def open_channel(sock, channel):
    send_method(sock, channel, CHANNEL_CLASS, 10, encode_shortstr(""))
    expect_method(sock, channel, CHANNEL_CLASS, 11)


def queue_declare(sock, channel, queue_name, exclusive=False, auto_delete=False):
    flags = 0
    if exclusive:
        flags |= 1 << 2
    if auto_delete:
        flags |= 1 << 3
    args = struct.pack(">H", 0) + encode_shortstr(queue_name) + bytes([flags]) + empty_table()
    send_method(sock, channel, QUEUE_CLASS, 10, args)
    declare_ok = expect_method(sock, channel, QUEUE_CLASS, 11)
    generated_name, _ = read_shortstr(declare_ok, 0)
    return generated_name


def exchange_declare(sock, channel, exchange_name, exchange_type):
    flags = 0
    args = (
        struct.pack(">H", 0)
        + encode_shortstr(exchange_name)
        + encode_shortstr(exchange_type)
        + bytes([flags])
        + empty_table()
    )
    send_method(sock, channel, EXCHANGE_CLASS, 10, args)
    expect_method(sock, channel, EXCHANGE_CLASS, 11)


sock = None
connected = False

try:
    sock = connect(USERNAME, PASSWORD, VHOST)
    connected = True

    if ACTION == "vhost-deny":
        print(f"UNEXPECTED_OK vhost {VHOST}")
        sys.exit(0)

    if ACTION == "smoke":
        open_channel(sock, 1)
        generated_queue = queue_declare(sock, 1, "", exclusive=True, auto_delete=True)
        print(f"SMOKE_OK {generated_queue}")
        sys.exit(0)

    if ACTION == "queue-deny":
        open_channel(sock, 1)
        queue_declare(sock, 1, RESOURCE, exclusive=False, auto_delete=False)
        print(f"UNEXPECTED_OK queue {RESOURCE}")
        sys.exit(0)

    if ACTION == "exchange-deny":
        open_channel(sock, 1)
        exchange_declare(sock, 1, RESOURCE, "fanout")
        print(f"UNEXPECTED_OK exchange {RESOURCE}")
        sys.exit(0)

    raise ProbeError(f"unknown action {ACTION}")
except BrokerClosed as exc:
    if ACTION == "vhost-deny" and exc.scope == "connection":
        print(f"ACCESS_REFUSED {exc.scope} {exc.code} {exc.text}")
        sys.exit(1)
    if ACTION in {"queue-deny", "exchange-deny"} and exc.scope == "channel":
        print(f"ACCESS_REFUSED {exc.scope} {exc.code} {exc.text}")
        sys.exit(1)
    print(f"PROBE_ERROR unexpected broker close {exc.scope} {exc.code} {exc.text}")
    sys.exit(2)
except Exception as exc:
    print(f"PROBE_ERROR {exc}")
    sys.exit(2)
finally:
    if sock is not None:
        if connected:
            close_connection(sock)
        sock.close()
PY
' sh "${action}" "${username}" "${password}" "${vhost}" "${resource_name}"
}

wait_for_labeled_resources_gone() {
    local resource_types="$1"
    local namespace_flag="$2"
    local deadline seconds_left

    deadline=$((SECONDS + 60))
    while true; do
        if [[ -z "$(kubectl get ${resource_types} ${namespace_flag} -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" -o name 2>/dev/null || true)" ]]; then
            return 0
        fi

        seconds_left=$((deadline - SECONDS))
        if (( seconds_left <= 0 )); then
            return 1
        fi
        sleep 2
    done
}

verify_cleanup_proof() {
    local rabbitmq_pod temp_resources vhosts_output

    section "New Phase 7 Assertions: Cleanup Proof"

    delete_rabbitmq_temp_vhost
    cleanup_temp_resources

    if wait_for_labeled_resources_gone "pod,networkpolicy" "-A"; then
        pass_new "Phase 7 probe pods and temporary NetworkPolicy resources were cleaned up"
    else
        temp_resources=$(kubectl get pod,networkpolicy -A -l "${TEMP_LABEL_KEY}=${TEMP_LABEL_VALUE}" -o name 2>/dev/null || true)
        fail_new "Phase 7 temporary Kubernetes resources remain after cleanup: ${temp_resources:0:220}"
    fi

    rabbitmq_pod=$(require_pod "${INFRA_NAMESPACE}" app=rabbitmq RabbitMQ)
    if capture_command vhosts_output \
        kubectl exec -n "${INFRA_NAMESPACE}" "${rabbitmq_pod}" -- rabbitmqctl list_vhosts name; then
        if printf '%s\n' "${vhosts_output}" | grep -Fxq "${RABBITMQ_TEMP_VHOST}"; then
            fail_new "Temporary RabbitMQ vhost ${RABBITMQ_TEMP_VHOST} still exists after cleanup"
        else
            RABBITMQ_TEMP_VHOST_CREATED=false
            pass_new "Temporary RabbitMQ vhost ${RABBITMQ_TEMP_VHOST} was cleaned up"
        fi
    else
        fail_new "Could not verify RabbitMQ temporary vhost cleanup: ${vhosts_output:0:220}"
    fi
}

verify_probe_setup() {
    section "Phase 7 Runtime Probe Setup"
    create_temp_resources
    wait_for_probe_ready "${REDIS_PROBE_NAME}"
    wait_for_probe_ready "${POSTGRES_PROBE_NAME}"
    wait_for_probe_ready "${RABBITMQ_PROBE_NAME}"
    info "Temporary Redis, PostgreSQL, and RabbitMQ probe pods are Ready"
}

verify_redis_acl_guardrails() {
    local redis_username redis_password output=""

    section "New Phase 7 Assertions: Redis ACL Guardrails"

    redis_username="${REDIS_CURRENCY_SERVICE_USERNAME}"
    redis_password=$(require_secret_value "${PROBE_NAMESPACE}" currency-service-redis-credentials password)

    if capture_command output \
        redis_cli_probe "${redis_username}" "${redis_password}" \
        set "${REDIS_ALLOWED_KEY}" guarded; then
        if printf '%s\n' "${output}" | grep -qx 'OK'; then
            pass_new "currency-service can still write inside its allowed Redis keyspace"
        else
            fail_new "currency-service Redis allow-path returned unexpected output: ${output:0:220}"
        fi
    else
        fail_new "currency-service could not write inside its allowed Redis keyspace: ${output:0:220}"
    fi

    if capture_command output \
        redis_cli_probe "${redis_username}" "${redis_password}" \
        hgetall "${REDIS_ALLOWED_KEY}"; then
        if printf '%s\n' "${output}" | grep -q "NOPERM User ${redis_username} has no permissions to run the 'hgetall' command"; then
            pass_new "currency-service is denied forbidden Redis commands even on its own keyspace"
        else
            fail_new "currency-service forbidden Redis command returned unexpected output: ${output:0:220}"
        fi
    else
        fail_new "currency-service forbidden Redis command failed for an unexpected reason: ${output:0:220}"
    fi

    if capture_command output \
        redis_cli_probe "${redis_username}" "${redis_password}" \
        get "${REDIS_DENIED_KEY}"; then
        if printf '%s\n' "${output}" | grep -q 'NOPERM No permissions to access a key'; then
            pass_new "currency-service is denied Redis access outside its allowed key patterns"
        else
            fail_new "currency-service forbidden Redis key-pattern probe returned unexpected output: ${output:0:220}"
        fi
    else
        fail_new "currency-service forbidden Redis key-pattern probe failed for an unexpected reason: ${output:0:220}"
    fi

    capture_command output \
        redis_cli_probe "${redis_username}" "${redis_password}" \
        del "${REDIS_ALLOWED_KEY}" >/dev/null || true
}

verify_postgresql_guardrails() {
    local txn_user txn_password perm_user perm_password output=""

    section "New Phase 7 Assertions: PostgreSQL Database Isolation"

    txn_user="${POSTGRES_TRANSACTION_USERNAME}"
    txn_password=$(require_secret_value "${PROBE_NAMESPACE}" transaction-service-postgresql-credentials password)
    perm_user="${POSTGRES_PERMISSION_USERNAME}"
    perm_password=$(require_secret_value "${PROBE_NAMESPACE}" permission-service-postgresql-credentials password)

    if capture_command output \
        postgres_probe "${txn_user}" "${txn_password}" budget_analyzer 'select current_database();'; then
        if printf '%s\n' "${output}" | grep -qx 'budget_analyzer'; then
            pass_new "transaction-service can still connect to its own PostgreSQL database"
        else
            fail_new "transaction-service PostgreSQL allow-path returned unexpected output: ${output:0:220}"
        fi
    else
        fail_new "transaction-service could not connect to its own PostgreSQL database: ${output:0:220}"
    fi

    if capture_command output \
        postgres_probe "${txn_user}" "${txn_password}" currency 'select 1;'; then
        fail_new "transaction-service unexpectedly connected to the currency PostgreSQL database"
    else
        if printf '%s\n' "${output}" | grep -q 'permission denied for database "currency"'; then
            pass_new "transaction-service is denied cross-database PostgreSQL access to currency"
        else
            fail_new "transaction-service cross-database denial returned unexpected output: ${output:0:220}"
        fi
    fi

    if capture_command output \
        postgres_probe "${perm_user}" "${perm_password}" budget_analyzer 'select 1;'; then
        fail_new "permission-service unexpectedly connected to the budget_analyzer PostgreSQL database"
    else
        if printf '%s\n' "${output}" | grep -q 'permission denied for database "budget_analyzer"'; then
            pass_new "permission-service is denied cross-database PostgreSQL access to budget_analyzer"
        else
            fail_new "permission-service cross-database denial returned unexpected output: ${output:0:220}"
        fi
    fi
}

verify_rabbitmq_guardrails() {
    local rabbitmq_pod admin_username admin_password admin_vhost
    local currency_username currency_password currency_vhost output=""

    section "New Phase 7 Assertions: RabbitMQ Permission Boundaries"

    rabbitmq_pod=$(require_pod "${INFRA_NAMESPACE}" app=rabbitmq RabbitMQ)
    admin_username="${RABBITMQ_ADMIN_USERNAME}"
    admin_password=$(require_secret_value "${INFRA_NAMESPACE}" rabbitmq-bootstrap-credentials password)
    admin_vhost="${RABBITMQ_ADMIN_VHOST}"
    currency_username="${RABBITMQ_CURRENCY_SERVICE_USERNAME}"
    currency_password=$(require_secret_value "${PROBE_NAMESPACE}" currency-service-rabbitmq-credentials password)
    currency_vhost="${RABBITMQ_ADMIN_VHOST}"

    if capture_command output \
        rabbitmq_admin "${rabbitmq_pod}" "${admin_username}" "${admin_password}" "${admin_vhost}" \
        declare vhost "name=${RABBITMQ_TEMP_VHOST}"; then
        RABBITMQ_TEMP_VHOST_CREATED=true
        info "Created temporary RabbitMQ vhost ${RABBITMQ_TEMP_VHOST} for denied-access verification"
    else
        fail_new "Could not create temporary RabbitMQ vhost ${RABBITMQ_TEMP_VHOST}: ${output:0:220}"
        return
    fi

    if capture_command output \
        rabbitmq_amqps_probe smoke "${currency_username}" "${currency_password}" "${currency_vhost}"; then
        if printf '%s\n' "${output}" | grep -q '^SMOKE_OK amq\.gen'; then
            pass_new "currency-service can still open an AMQPS connection and declare an allowed server-named queue"
        else
            fail_new "RabbitMQ allow-path smoke check returned unexpected output: ${output:0:220}"
        fi
    else
        fail_new "currency-service could not complete the RabbitMQ allow-path smoke check: ${output:0:220}"
    fi

    if capture_command output \
        rabbitmq_amqps_probe vhost-deny "${currency_username}" "${currency_password}" "${RABBITMQ_TEMP_VHOST}"; then
        fail_new "currency-service unexpectedly accessed the unauthorized RabbitMQ vhost ${RABBITMQ_TEMP_VHOST}"
    else
        if printf '%s\n' "${output}" | grep -q '^ACCESS_REFUSED connection '; then
            pass_new "currency-service is denied access to an unauthorized RabbitMQ vhost"
        else
            fail_new "RabbitMQ unauthorized-vhost denial returned unexpected output: ${output:0:220}"
        fi
    fi

    if capture_command output \
        rabbitmq_amqps_probe queue-deny "${currency_username}" "${currency_password}" "${currency_vhost}" "${RABBITMQ_FORBIDDEN_QUEUE}"; then
        fail_new "currency-service unexpectedly declared an unauthorized RabbitMQ queue"
    else
        if printf '%s\n' "${output}" | grep -q '^ACCESS_REFUSED channel '; then
            pass_new "currency-service is denied unauthorized RabbitMQ queue declarations"
        else
            fail_new "RabbitMQ unauthorized-queue denial returned unexpected output: ${output:0:220}"
        fi
    fi

    if capture_command output \
        rabbitmq_amqps_probe exchange-deny "${currency_username}" "${currency_password}" "${currency_vhost}" "${RABBITMQ_FORBIDDEN_EXCHANGE}"; then
        fail_new "currency-service unexpectedly declared an unauthorized RabbitMQ exchange"
    else
        if printf '%s\n' "${output}" | grep -q '^ACCESS_REFUSED channel '; then
            pass_new "currency-service is denied unauthorized RabbitMQ exchange declarations"
        else
            fail_new "RabbitMQ unauthorized-exchange denial returned unexpected output: ${output:0:220}"
        fi
    fi
}

run_reused_regression_umbrella() {
    section "Reused Runtime Regressions: Phase 2 Through Phase 6"
    info "Timeout for reused regression umbrella: ${REGRESSION_TIMEOUT}"

    if env \
        PHASE2_ALLOW_ATTEMPTS="${PHASE2_ALLOW_ATTEMPTS:-8}" \
        PHASE2_PROBE_STABILIZATION_SECONDS="${PHASE2_PROBE_STABILIZATION_SECONDS:-8}" \
        timeout --foreground --kill-after=10s "${REGRESSION_TIMEOUT}" \
        "${SCRIPT_DIR}/verify-phase-6-edge-browser-hardening.sh"; then
        pass_reused "Phase 6 edge/browser hardening verifier passed and reran the Phase 5 runtime cascade plus the intended Phase 2 through Phase 4 regressions"
        pass_reused "Phase 6 auth-edge throttling and API rate-limit identity proofs remain intact under the Phase 7 runtime baseline"
    else
        local exit_code=$?
        if [[ "${exit_code}" -eq 124 || "${exit_code}" -eq 137 ]]; then
            fail_reused "Phase 6 edge/browser hardening verifier timed out after ${REGRESSION_TIMEOUT}"
        else
            fail_reused "Phase 6 edge/browser hardening verifier failed under the Phase 7 runtime baseline"
        fi
    fi
}

main() {
    echo "==============================================================="
    echo "  Phase 7 Runtime Guardrail Verifier"
    echo "==============================================================="
    echo

    require_host_command kubectl
    require_host_command timeout
    require_cluster_access
    require_secret_exists "${PROBE_NAMESPACE}" infra-ca
    require_secret_exists "${PROBE_NAMESPACE}" currency-service-redis-credentials
    require_secret_exists "${PROBE_NAMESPACE}" transaction-service-postgresql-credentials
    require_secret_exists "${PROBE_NAMESPACE}" permission-service-postgresql-credentials
    require_secret_exists "${PROBE_NAMESPACE}" currency-service-rabbitmq-credentials
    require_secret_exists "${INFRA_NAMESPACE}" rabbitmq-bootstrap-credentials

    verify_probe_setup
    verify_redis_acl_guardrails
    verify_postgresql_guardrails
    verify_rabbitmq_guardrails
    verify_cleanup_proof
    run_reused_regression_umbrella

    section "Summary"
    printf 'New Phase 7 assertions: %d passed, %d failed\n' "${NEW_PASSED}" "${NEW_FAILED}"
    printf 'Reused Phase 2-6 regressions: %d passed, %d failed\n' "${REUSED_PASSED}" "${REUSED_FAILED}"

    echo
    echo "==============================================================="
    total_passed=$((NEW_PASSED + REUSED_PASSED))
    total_failed=$((NEW_FAILED + REUSED_FAILED))
    total_checks=$((total_passed + total_failed))
    if [[ "${total_failed}" -eq 0 ]]; then
        echo "  ${total_passed} passed (out of ${total_checks})"
    else
        echo "  ${total_passed} passed, ${total_failed} failed (out of ${total_checks})"
    fi
    echo "==============================================================="

    [[ "${total_failed}" -gt 0 ]] && exit 1 || exit 0
}

main "$@"
