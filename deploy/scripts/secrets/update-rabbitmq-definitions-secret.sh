#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime; run shellcheck -x when following sources.
source "${SCRIPT_DIR}/../lib/common.sh"

DEFAULT_GENERATED_ENV_FILE="${HOME}/.local/share/budget-analyzer/vault-secrets/secret-sync-generated-secrets.env"
DEFAULT_OUTPUT_FILE="${HOME}/.local/share/budget-analyzer/vault-secrets/rabbitmq-definitions.json"
TEMPLATE_FILE="${PHASE4_REPO_ROOT}/deploy/manifests/secret-sync/rabbitmq-definitions.template.json"
SECRET_NAME="budget-analyzer-rabbitmq-definitions"
readonly DEFAULT_GENERATED_ENV_FILE
readonly DEFAULT_OUTPUT_FILE
readonly TEMPLATE_FILE
readonly SECRET_NAME

GENERATED_ENV_FILE="${DEFAULT_GENERATED_ENV_FILE}"
OUTPUT_FILE="${DEFAULT_OUTPUT_FILE}"

usage() {
    cat <<'EOF'
Usage: ./deploy/scripts/secrets/update-rabbitmq-definitions-secret.sh [options]

Renders deploy/manifests/secret-sync/rabbitmq-definitions.template.json with the
generated RabbitMQ passwords, validates the v0.0.14 destination contract, and
creates or updates the OCI Vault secret:
  budget-analyzer-rabbitmq-definitions

Options:
  --generated-env-file FILE  File created by deploy/scripts/secrets/bootstrap-vault-secrets.sh.
                             Default: ~/.local/share/budget-analyzer/vault-secrets/secret-sync-generated-secrets.env
  --output-file FILE         Rendered definitions file. Must stay outside the repo.
                             Default: ~/.local/share/budget-analyzer/vault-secrets/rabbitmq-definitions.json
  -h, --help                 Show this help text.
EOF
}

ensure_not_container_execution() {
    if [[ -f "/.dockerenv" || -f "/run/.containerenv" ]]; then
        phase4_die "run this script from the OCI host, Cloud Shell, or another trusted machine outside the AI/container workspace"
    fi
}

prepare_output_path() {
    local output_dir

    output_dir="$(dirname "${OUTPUT_FILE}")"
    mkdir -p "${output_dir}"
    output_dir="$(cd "${output_dir}" && pwd)"
    OUTPUT_FILE="${output_dir}/$(basename "${OUTPUT_FILE}")"

    case "${OUTPUT_FILE}" in
        "${PHASE4_REPO_ROOT}"|"${PHASE4_REPO_ROOT}/"*)
            phase4_die "refusing to write RabbitMQ definitions under ${PHASE4_REPO_ROOT}; use a path outside the repo"
            ;;
    esac
}

load_generated_secret_material() {
    [[ -f "${GENERATED_ENV_FILE}" ]] || \
        phase4_die "missing generated secret material: ${GENERATED_ENV_FILE}; run deploy/scripts/secrets/bootstrap-vault-secrets.sh first"

    set -a
    # shellcheck disable=SC1090
    source "${GENERATED_ENV_FILE}"
    set +a

    phase4_require_env_vars_from_generated_file \
        RABBITMQ_ADMIN_PASSWORD \
        RABBITMQ_CURRENCY_SERVICE_PASSWORD
}

phase4_require_env_vars_from_generated_file() {
    local variable_name
    local missing=()

    for variable_name in "$@"; do
        if [[ -z "${!variable_name:-}" ]]; then
            missing+=("${variable_name}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        phase4_die "missing required values in ${GENERATED_ENV_FILE}: ${missing[*]}"
    fi
}

render_definitions() {
    local admin_password
    local service_password

    [[ -f "${TEMPLATE_FILE}" ]] || phase4_die "missing RabbitMQ definitions template: ${TEMPLATE_FILE}"

    admin_password="$(phase4_escape_sed_replacement "${RABBITMQ_ADMIN_PASSWORD}")"
    service_password="$(phase4_escape_sed_replacement "${RABBITMQ_CURRENCY_SERVICE_PASSWORD}")"

    umask 077
    sed \
        -e "s|\${RABBITMQ_ADMIN_PASSWORD}|${admin_password}|g" \
        -e "s|\${RABBITMQ_CURRENCY_SERVICE_PASSWORD}|${service_password}|g" \
        "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"
    chmod 600 "${OUTPUT_FILE}"
}

validate_definitions() {
    if grep -Eq '\$\{RABBITMQ_[A-Z_]+\}' "${OUTPUT_FILE}"; then
        phase4_die "unrendered RabbitMQ password placeholders remain in ${OUTPUT_FILE}"
    fi

    if ! grep -Fq 'exchange-rate\\.import\\.requested' "${OUTPUT_FILE}"; then
        phase4_die "RabbitMQ definitions do not include exchange-rate.import.requested; check that ${TEMPLATE_FILE} is from the current release checkout"
    fi

    if grep -Fq 'currency\\.created' "${OUTPUT_FILE}"; then
        phase4_die "RabbitMQ definitions still include removed currency.created destination"
    fi
}

base64_encode_file() {
    base64 < "$1" | tr -d '\n'
}

vault_secret_id() {
    oci secrets secret-bundle get-secret-bundle-by-name \
        --secret-name "${SECRET_NAME}" \
        --vault-id "${OCI_VAULT_OCID}" \
        --query 'data."secret-id"' \
        --raw-output 2>/dev/null || true
}

create_or_update_vault_secret() {
    local secret_id
    local encoded_content

    encoded_content="$(base64_encode_file "${OUTPUT_FILE}")"
    secret_id="$(vault_secret_id)"

    if [[ -n "${secret_id}" && "${secret_id}" != "null" ]]; then
        phase4_info "updating vault secret version: ${SECRET_NAME}"
        oci vault secret update-base64 \
            --secret-id "${secret_id}" \
            --secret-content-content "${encoded_content}" \
            --wait-for-state ACTIVE \
            --max-wait-seconds 1200 >/dev/null
        return
    fi

    phase4_info "creating vault secret: ${SECRET_NAME}"
    oci vault secret create-base64 \
        --compartment-id "${OCI_COMPARTMENT_OCID}" \
        --vault-id "${OCI_VAULT_OCID}" \
        --key-id "${OCI_VAULT_KEY_OCID}" \
        --secret-name "${SECRET_NAME}" \
        --secret-content-content "${encoded_content}" \
        --wait-for-state ACTIVE \
        --max-wait-seconds 1200 >/dev/null
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --generated-env-file)
                GENERATED_ENV_FILE="${2:-}"
                shift
                ;;
            --output-file)
                OUTPUT_FILE="${2:-}"
                shift
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
    prepare_output_path

    phase4_require_commands oci base64 sed grep
    phase4_load_instance_env
    phase4_require_env_vars OCI_COMPARTMENT_OCID OCI_VAULT_OCID OCI_VAULT_KEY_OCID

    load_generated_secret_material
    render_definitions
    validate_definitions
    create_or_update_vault_secret

    phase4_info "rendered RabbitMQ definitions to ${OUTPUT_FILE}"
    phase4_info "created or updated OCI Vault secret ${SECRET_NAME}"
}

main "$@"
