#!/bin/bash

# Human-operated personal-host renewal. Generates only a new ingress leaf/key
# from the existing host mkcert CA and republishes that CA's public root. It
# never contacts Kubernetes and must never run in the development VM or by an
# agent process.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CERT_DIR="$ORCHESTRATION_DIR/nginx/certs/k8s"
CERT_FILE="$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY_FILE="$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem"
CA_FILE="$CERT_DIR/_mkcert-rootCA.pem"

if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    printf 'ERROR: run this renewal only on the personal host.\n' >&2
    exit 1
fi

for command_name in mkcert openssl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'ERROR: required command is missing: %s\n' "$command_name" >&2
        exit 1
    fi
done

CA_ROOT="$(mkcert -CAROOT)"
SOURCE_CA="$CA_ROOT/rootCA.pem"
if [[ ! -r "$SOURCE_CA" ]]; then
    printf 'ERROR: the personal host mkcert public root is unreadable.\n' >&2
    exit 1
fi

# Keep the personal browser trust tied to this existing host-owned CA. This is
# deliberately a human-operated personal-host action.
mkcert -install

install -d -m 0750 "$CERT_DIR"
TMP_DIR="$(mktemp -d "$CERT_DIR/.renew-ingress-tls.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

install -m 0644 "$SOURCE_CA" "$TMP_DIR/_mkcert-rootCA.pem"
mkcert \
    -cert-file "$TMP_DIR/_wildcard.budgetanalyzer.localhost.pem" \
    -key-file "$TMP_DIR/_wildcard.budgetanalyzer.localhost-key.pem" \
    '*.budgetanalyzer.localhost' budgetanalyzer.localhost

"$SCRIPT_DIR/install-imported-ingress-tls.sh" \
    --validate-only \
    --cert-dir "$TMP_DIR"

install -m 0644 "$TMP_DIR/_wildcard.budgetanalyzer.localhost.pem" "$CERT_FILE"
install -m 0600 "$TMP_DIR/_wildcard.budgetanalyzer.localhost-key.pem" "$KEY_FILE"
install -m 0644 "$TMP_DIR/_mkcert-rootCA.pem" "$CA_FILE"

printf 'Renewed the host-owned ingress files without changing any Kind cluster.\n'
printf 'Copy the three approved files to the development VM and rerun its imported-TLS installer.\n'
