#!/bin/bash

# Read-only client-trust check for the imported local ingress certificate.
# Source this file; do not execute it directly.

assert_system_trusts_local_ingress_leaf() {
    local certificate_file="$1"
    local expected_hostname="${2:-app.budgetanalyzer.localhost}"
    local system_trust_bundle="${3:-/etc/ssl/certs/ca-certificates.crt}"

    if ! command -v openssl >/dev/null 2>&1; then
        printf 'ERROR: required command is missing: openssl\n' >&2
        return 1
    fi

    if [[ ! -f "$certificate_file" || ! -r "$certificate_file" ]]; then
        printf 'ERROR: ingress certificate is missing or unreadable: %s\n' \
            "$certificate_file" >&2
        return 1
    fi

    if [[ ! -f "$system_trust_bundle" || ! -r "$system_trust_bundle" ]]; then
        printf 'ERROR: system trust bundle is missing or unreadable: %s\n' \
            "$system_trust_bundle" >&2
        return 1
    fi

    if ! openssl verify -CAfile "$system_trust_bundle" \
        -verify_hostname "$expected_hostname" \
        "$certificate_file" >/dev/null 2>&1; then
        printf 'ERROR: system trust does not verify the ingress certificate for %s.\n' \
            "$expected_hostname" >&2
        return 1
    fi

    return 0
}
