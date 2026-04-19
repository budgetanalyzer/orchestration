#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

SERVICES=(postgresql redis rabbitmq)
DEFAULT_OUTPUT_DIR="${HOME}/.local/share/budget-analyzer/infra-tls"
readonly SERVICES
readonly DEFAULT_OUTPUT_DIR

OUTPUT_DIR="${DEFAULT_OUTPUT_DIR}"
ROTATE_CERTS=false
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TEMP_DIR}"' EXIT

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/11-generate-phase-5-infra-tls.sh [options]

Generates the private Phase 5 infrastructure CA and service certificates
outside the repo, then applies the expected Kubernetes Secret objects:
  - default/infra-ca
  - infrastructure/infra-ca
  - infrastructure/infra-tls-postgresql
  - infrastructure/infra-tls-redis
  - infrastructure/infra-tls-rabbitmq

Options:
  --output-dir DIR   Directory for the generated CA and service keypairs.
                     Default: ~/.local/share/budget-analyzer/infra-tls
  --rotate           Regenerate the CA and service certificates even if files
                     already exist.
  -h, --help         Show this help text.
EOF
}

ca_cert_path() {
    printf '%s/infra-ca.pem\n' "${OUTPUT_DIR}"
}

ca_key_path() {
    printf '%s/infra-ca.key\n' "${OUTPUT_DIR}"
}

ca_serial_path() {
    printf '%s/infra-ca.srl\n' "${OUTPUT_DIR}"
}

service_cert_path() {
    printf '%s/%s.pem\n' "${OUTPUT_DIR}" "$1"
}

service_key_path() {
    printf '%s/%s.key\n' "${OUTPUT_DIR}" "$1"
}

ensure_not_container_execution() {
    if [[ -f "/.dockerenv" || -f "/run/.containerenv" ]]; then
        phase4_die "run this script from the OCI host or another trusted machine outside the AI/container workspace"
    fi
}

prepare_output_dir() {
    mkdir -p "${OUTPUT_DIR}"
    OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"

    case "${OUTPUT_DIR}" in
        "${PHASE4_REPO_ROOT}"|"${PHASE4_REPO_ROOT}/"*)
            phase4_die "refusing to store private key material under ${PHASE4_REPO_ROOT}; use an output directory outside the repo"
            ;;
    esac
}

maybe_rotate_existing_material() {
    if [[ "${ROTATE_CERTS}" != true ]]; then
        return 0
    fi

    phase4_warn "rotating the Phase 5 infrastructure CA and service certificates in ${OUTPUT_DIR}"
    rm -f \
        "$(ca_cert_path)" \
        "$(ca_key_path)" \
        "$(ca_serial_path)"

    local service
    for service in "${SERVICES[@]}"; do
        rm -f "$(service_cert_path "${service}")" "$(service_key_path "${service}")"
    done
}

generate_ca() {
    if [[ -f "$(ca_cert_path)" && -f "$(ca_key_path)" ]]; then
        phase4_info "reusing existing infrastructure CA from ${OUTPUT_DIR}"
        return 0
    fi

    phase4_info "generating infrastructure CA"
    openssl genrsa -out "$(ca_key_path)" 4096 >/dev/null 2>&1
    openssl req -x509 -new -nodes \
        -key "$(ca_key_path)" \
        -sha256 \
        -days 3650 \
        -out "$(ca_cert_path)" \
        -subj "/CN=Budget Analyzer Infrastructure CA" >/dev/null 2>&1
}

generate_service_cert() {
    local service="$1"
    local fqdn="${service}.infrastructure.svc.cluster.local"
    local cert_file
    local key_file
    local csr_file="${TEMP_DIR}/${service}.csr"
    local ext_file="${TEMP_DIR}/${service}.ext"

    cert_file="$(service_cert_path "${service}")"
    key_file="$(service_key_path "${service}")"

    if [[ -f "${cert_file}" && -f "${key_file}" ]]; then
        phase4_info "reusing existing ${service} certificate from ${OUTPUT_DIR}"
        return 0
    fi

    cat <<EOF > "${ext_file}"
subjectAltName=DNS:${service}.infrastructure.svc.cluster.local,DNS:${service}.infrastructure.svc,DNS:${service}.infrastructure,DNS:${service},DNS:localhost,IP:127.0.0.1
extendedKeyUsage=serverAuth
keyUsage=digitalSignature,keyEncipherment
EOF

    phase4_info "generating ${service} service certificate"
    openssl genrsa -out "${key_file}" 4096 >/dev/null 2>&1
    openssl req -new \
        -key "${key_file}" \
        -out "${csr_file}" \
        -subj "/CN=${fqdn}" >/dev/null 2>&1
    openssl x509 -req \
        -in "${csr_file}" \
        -CA "$(ca_cert_path)" \
        -CAkey "$(ca_key_path)" \
        -CAcreateserial \
        -CAserial "$(ca_serial_path)" \
        -out "${cert_file}" \
        -days 3650 \
        -sha256 \
        -extfile "${ext_file}" >/dev/null 2>&1
}

require_namespace() {
    local namespace="$1"

    kubectl get namespace "${namespace}" >/dev/null 2>&1 || phase4_die "required namespace missing: ${namespace}"
}

apply_tls_secret() {
    local namespace="$1"
    local secret_name="$2"
    local cert_file="$3"
    local key_file="$4"

    kubectl create secret tls "${secret_name}" \
        --cert="${cert_file}" \
        --key="${key_file}" \
        -n "${namespace}" \
        --dry-run=client \
        -o yaml | kubectl apply -f -
}

apply_ca_secret() {
    local namespace="$1"

    kubectl create secret generic infra-ca \
        --from-file=ca.crt="$(ca_cert_path)" \
        -n "${namespace}" \
        --dry-run=client \
        -o yaml | kubectl apply -f -
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output-dir)
                OUTPUT_DIR="${2:-}"
                shift
                ;;
            --rotate)
                ROTATE_CERTS=true
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

    ensure_not_container_execution
    prepare_output_dir
    maybe_rotate_existing_material

    phase4_require_commands kubectl openssl
    phase4_use_default_kubeconfig
    phase4_require_cluster_access

    require_namespace default
    require_namespace infrastructure

    generate_ca

    local service
    for service in "${SERVICES[@]}"; do
        generate_service_cert "${service}"
    done

    phase4_info "applying infrastructure TLS secrets"
    apply_tls_secret infrastructure infra-tls-postgresql "$(service_cert_path postgresql)" "$(service_key_path postgresql)"
    apply_tls_secret infrastructure infra-tls-redis "$(service_cert_path redis)" "$(service_key_path redis)"
    apply_tls_secret infrastructure infra-tls-rabbitmq "$(service_cert_path rabbitmq)" "$(service_key_path rabbitmq)"
    apply_ca_secret default
    apply_ca_secret infrastructure

    phase4_info "Phase 5 infrastructure TLS material stored in ${OUTPUT_DIR}"
    kubectl get secret -n default infra-ca
    kubectl get secret -n infrastructure infra-ca infra-tls-postgresql infra-tls-redis infra-tls-rabbitmq
}

main "$@"
