#!/bin/bash

# Validate host-created ingress TLS files and reconcile their Kubernetes
# ingress Secret. This script never invokes mkcert, generates key material or
# changes a trust store.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCHESTRATION_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/local-kubernetes-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-kubernetes-target.sh"
CERT_DIR="$ORCHESTRATION_DIR/nginx/certs/k8s"
VALIDATE_ONLY=false
INSTALL_SYSTEM_TRUST=false
EXPECTED_HOSTNAME="app.budgetanalyzer.localhost"
SECRET_NAME="budgetanalyzer-localhost-wildcard-tls"
NAMESPACE="default"

usage() {
    cat <<'EOF'
Usage: scripts/bootstrap/install-imported-ingress-tls.sh [options]

Options:
  --validate-only         Validate files without changing trust or Kubernetes.
  --install-system-trust  Rejected legacy option; workspace owns guest trust.
  --cert-dir DIR          Validate/install the three required files from DIR.
  --help                  Show this help.
EOF
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

reject_legacy_trust_writer() {
    cat >&2 <<'EOF'
ERROR: --install-system-trust is retired; orchestration does not change guest trust.
After reviewing workspace changes and ending affected workers, the human must run:
  . "$HOME/.config/budget-analyzer-native/env.sh"
  ../workspace/scripts/install-agent-vm-local-ca-trust.sh \
    --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
    --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --validate-only)
            VALIDATE_ONLY=true
            shift
            ;;
        --install-system-trust)
            INSTALL_SYSTEM_TRUST=true
            shift
            ;;
        --cert-dir)
            [[ $# -ge 2 ]] || fail "--cert-dir requires a value"
            CERT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            fail "unknown argument: $1"
            ;;
    esac
done

if [[ "$INSTALL_SYSTEM_TRUST" == true ]]; then
    reject_legacy_trust_writer
fi

CERT_FILE="$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem"
KEY_FILE="$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem"
CA_FILE="$CERT_DIR/_mkcert-rootCA.pem"

command -v openssl >/dev/null 2>&1 || fail "required command is missing: openssl"

for required_file in "$CERT_FILE" "$KEY_FILE" "$CA_FILE"; do
    [[ -f "$required_file" && -r "$required_file" ]] \
        || fail "required imported TLS file is missing or unreadable: $required_file"
done

KEY_MODE="$(stat -c '%a' "$KEY_FILE" 2>/dev/null || true)"
if [[ ! "$KEY_MODE" =~ ^[0-7]{3,4}$ ]] \
    || (( (8#$KEY_MODE & 8#077) != 0 )); then
    fail "the imported ingress private key must not be group- or world-accessible"
fi

if find "$CERT_DIR" -maxdepth 1 -type f -name 'rootCA-key.pem' -print -quit | grep -q .; then
    fail "the mkcert signing key is prohibited from the guest certificate directory"
fi

openssl x509 -in "$CA_FILE" -noout >/dev/null 2>&1 \
    || fail "the imported public root is not a parseable certificate"
openssl x509 -in "$CERT_FILE" -noout >/dev/null 2>&1 \
    || fail "the imported ingress leaf is not a parseable certificate"
openssl pkey -in "$KEY_FILE" -noout >/dev/null 2>&1 \
    || fail "the imported ingress private key is not parseable"

openssl x509 -in "$CA_FILE" -checkend 0 -noout >/dev/null 2>&1 \
    || fail "the imported public root is expired or not yet valid"
openssl x509 -in "$CERT_FILE" -checkend 0 -noout >/dev/null 2>&1 \
    || fail "the imported ingress leaf is expired or not yet valid"
openssl x509 -in "$CA_FILE" -noout -text 2>/dev/null | grep -q 'CA:TRUE' \
    || fail "the imported public root is not marked as a CA"
openssl verify -CAfile "$CA_FILE" -verify_hostname "$EXPECTED_HOSTNAME" \
    "$CERT_FILE" >/dev/null 2>&1 \
    || fail "the imported public root does not verify the ingress leaf for $EXPECTED_HOSTNAME"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
openssl x509 -in "$CERT_FILE" -pubkey -noout > "$TMP_DIR/leaf.pub"
openssl pkey -in "$KEY_FILE" -pubout > "$TMP_DIR/key.pub"
cmp -s "$TMP_DIR/leaf.pub" "$TMP_DIR/key.pub" \
    || fail "the imported ingress leaf and private key do not match"

printf 'Imported ingress TLS files are valid for %s.\n' "$EXPECTED_HOSTNAME"

if [[ "$VALIDATE_ONLY" == true ]]; then
    exit 0
fi

if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    fail "install mode must run on the machine hosting the local Kind cluster, not in a container"
fi

assert_local_kind_target || exit 1

kubectl create secret tls "$SECRET_NAME" \
    --cert="$CERT_FILE" \
    --key="$KEY_FILE" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

[[ "$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')" == "kubernetes.io/tls" ]] \
    || fail "installed Secret has an unexpected type"

printf "Installed ingress TLS Secret '%s' in namespace '%s'.\n" "$SECRET_NAME" "$NAMESPACE"
