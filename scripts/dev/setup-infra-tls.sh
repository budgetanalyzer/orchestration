#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERTS_DIR="$ORCHESTRATION_DIR/nginx/certs/infra"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

CA_CERT="$CERTS_DIR/infra-ca.pem"
CA_KEY="$CERTS_DIR/infra-ca.key"
CA_SERIAL="$TEMP_DIR/infra-ca.srl"

SERVICES=(redis postgresql rabbitmq)

info() {
    echo "[INFO] $1"
}

ok() {
    echo "[OK] $1"
}

error() {
    echo "[ERROR] $1" >&2
}

require_command() {
    local cmd=$1
    local install_hint=$2

    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd is installed"
        return 0
    fi

    error "$cmd is not installed"
    echo "        Install with: $install_hint" >&2
    exit 1
}

assert_host_execution() {
    if [ -f "/.dockerenv" ] || [ -f "/run/.containerenv" ]; then
        error "This script must be run from your host machine, not from the devcontainer or Tilt."
        echo "        Open a host terminal in $ORCHESTRATION_DIR and run:" >&2
        echo "        ./scripts/dev/setup-infra-tls.sh" >&2
        exit 1
    fi
}

ensure_cluster_access() {
    if kubectl cluster-info >/dev/null 2>&1; then
        ok "Kubernetes cluster is reachable"
        return 0
    fi

    error "Cannot connect to the Kubernetes cluster"
    echo "        Ensure your Kind cluster is running and kubectl is pointed at it." >&2
    exit 1
}

ensure_namespace() {
    local namespace=$1
    local injection_label="disabled"
    local psa_level="restricted"

    if kubectl get namespace "$namespace" >/dev/null 2>&1; then
        ok "Namespace '$namespace' exists"
        return 0
    fi

    case "$namespace" in
        default)
            injection_label="enabled"
            psa_level="restricted"
            ;;
        infrastructure)
            injection_label="disabled"
            psa_level="baseline"
            ;;
    esac

    info "Creating namespace '$namespace'"
    cat <<MANIFEST | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Namespace
metadata:
  name: ${namespace}
  labels:
    istio-injection: ${injection_label}
    pod-security.kubernetes.io/enforce: ${psa_level}
    pod-security.kubernetes.io/enforce-version: v1.32
    pod-security.kubernetes.io/warn: ${psa_level}
    pod-security.kubernetes.io/warn-version: v1.32
    pod-security.kubernetes.io/audit: ${psa_level}
    pod-security.kubernetes.io/audit-version: v1.32
MANIFEST
    ok "Namespace '$namespace' created"
}

service_cert_path() {
    printf '%s/%s.pem' "$CERTS_DIR" "$1"
}

service_key_path() {
    printf '%s/%s.key' "$CERTS_DIR" "$1"
}

generate_ca() {
    if [ -f "$CA_CERT" ] && [ -f "$CA_KEY" ]; then
        ok "Infrastructure CA already exists"
        return 0
    fi

    info "Generating infrastructure CA"
    openssl genrsa -out "$CA_KEY" 4096 >/dev/null 2>&1
    openssl req -x509 -new -nodes \
        -key "$CA_KEY" \
        -sha256 \
        -days 3650 \
        -out "$CA_CERT" \
        -subj "/CN=Budget Analyzer Infrastructure CA" >/dev/null 2>&1
    ok "Infrastructure CA generated"
}

generate_service_cert() {
    local service=$1
    local fqdn="$service.infrastructure.svc.cluster.local"
    local cert_file
    local key_file
    local csr_file
    local ext_file

    cert_file="$(service_cert_path "$service")"
    key_file="$(service_key_path "$service")"
    csr_file="$TEMP_DIR/$service.csr"
    ext_file="$TEMP_DIR/$service.ext"

    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        ok "$service certificate already exists"
        return 0
    fi

    cat <<EOF >"$ext_file"
subjectAltName=DNS:$service.infrastructure.svc.cluster.local,DNS:$service.infrastructure.svc,DNS:$service.infrastructure,DNS:$service,DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

    info "Generating $service server certificate"
    openssl genrsa -out "$key_file" 4096 >/dev/null 2>&1
    openssl req -new \
        -key "$key_file" \
        -out "$csr_file" \
        -subj "/CN=$fqdn" >/dev/null 2>&1
    openssl x509 -req \
        -in "$csr_file" \
        -CA "$CA_CERT" \
        -CAkey "$CA_KEY" \
        -CAcreateserial \
        -CAserial "$CA_SERIAL" \
        -out "$cert_file" \
        -days 3650 \
        -sha256 \
        -extfile "$ext_file" >/dev/null 2>&1
    ok "$service server certificate generated"
}

recreate_tls_secret() {
    local namespace=$1
    local secret_name=$2
    local cert_file=$3
    local key_file=$4

    kubectl delete secret "$secret_name" -n "$namespace" --ignore-not-found >/dev/null
    kubectl create secret tls "$secret_name" \
        --cert="$cert_file" \
        --key="$key_file" \
        -n "$namespace" >/dev/null
    ok "Secret '$secret_name' recreated in namespace '$namespace'"
}

recreate_ca_secret() {
    local namespace=$1

    kubectl delete secret infra-ca -n "$namespace" --ignore-not-found >/dev/null
    kubectl create secret generic infra-ca \
        --from-file=ca.crt="$CA_CERT" \
        -n "$namespace" >/dev/null
    ok "Secret 'infra-ca' recreated in namespace '$namespace'"
}

echo "=== Budget Analyzer - Infrastructure TLS Setup ==="
echo
echo "This script generates internal CA material for Redis, PostgreSQL, and RabbitMQ."
echo "Run it from your host terminal before 'tilt up'."
echo

assert_host_execution
require_command "openssl" "Use your OS package manager to install OpenSSL."
require_command "kubectl" "https://kubernetes.io/docs/tasks/tools/"
ensure_cluster_access

mkdir -p "$CERTS_DIR"
ok "Certificate output directory ready at $CERTS_DIR"

ensure_namespace "default"
ensure_namespace "infrastructure"

generate_ca

for service in "${SERVICES[@]}"; do
    generate_service_cert "$service"
done

recreate_tls_secret "infrastructure" "infra-tls-redis" "$(service_cert_path redis)" "$(service_key_path redis)"
recreate_tls_secret "infrastructure" "infra-tls-postgresql" "$(service_cert_path postgresql)" "$(service_key_path postgresql)"
recreate_tls_secret "infrastructure" "infra-tls-rabbitmq" "$(service_cert_path rabbitmq)" "$(service_key_path rabbitmq)"

recreate_ca_secret "default"
recreate_ca_secret "infrastructure"

echo
echo "=== Setup Complete ==="
echo
echo "Generated files:"
echo "  $CA_CERT"
echo "  $(service_cert_path redis)"
echo "  $(service_cert_path postgresql)"
echo "  $(service_cert_path rabbitmq)"
echo
echo "Next steps:"
echo "  ./scripts/dev/check-tilt-prerequisites.sh"
echo "  tilt up"
