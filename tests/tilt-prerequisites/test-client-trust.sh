#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
MOCK_BIN="$FIXTURE_DIR/bin"
CERT_FILE="$FIXTURE_DIR/leaf.pem"
CA_FILE="$FIXTURE_DIR/root.pem"
SYSTEM_BUNDLE="$FIXTURE_DIR/system-bundle.pem"
OPENSSL_LOG="$FIXTURE_DIR/openssl.log"
mkdir -p "$MOCK_BIN"
touch "$CERT_FILE" "$CA_FILE" "$SYSTEM_BUNDLE" "$OPENSSL_LOG"
export OPENSSL_LOG CA_FILE SYSTEM_BUNDLE
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$MOCK_BIN/openssl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${OPENSSL_LOG:?}"
[[ "${1:-}" == verify ]] || exit 90
if [[ " $* " == *" -CAfile ${CA_FILE:?} "* ]]; then
    exit 0
fi
if [[ " $* " == *" -CAfile ${SYSTEM_BUNDLE:?} "* ]]; then
    [[ "${FIXTURE_SYSTEM_TRUST:-false}" == true ]]
    exit
fi
exit 91
EOF
chmod 0755 "$MOCK_BIN/openssl"

# shellcheck source=scripts/lib/local-ingress-client-trust.sh
. "$REPO_DIR/scripts/lib/local-ingress-client-trust.sh"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

PATH="$MOCK_BIN:$PATH" openssl verify -CAfile "$CA_FILE" \
    -verify_hostname app.budgetanalyzer.localhost "$CERT_FILE" >/dev/null \
    || fail "fixture supplied root did not verify its leaf"

if PATH="$MOCK_BIN:$PATH" \
    assert_system_trusts_local_ingress_leaf "$CERT_FILE" \
    app.budgetanalyzer.localhost "$SYSTEM_BUNDLE" \
    >"$FIXTURE_DIR/untrusted.out" 2>&1; then
    fail "leaf absent from system trust unexpectedly passed"
fi
grep -Fq 'system trust does not verify' "$FIXTURE_DIR/untrusted.out" \
    || fail "missing system trust did not report the client-trust failure"
grep -Fq "verify -CAfile $SYSTEM_BUNDLE -verify_hostname app.budgetanalyzer.localhost" \
    "$OPENSSL_LOG" \
    || fail "client-trust check did not use hostname-aware default trust"
pass "valid supplied root and leaf fail when the system bundle lacks that root"

PATH="$MOCK_BIN:$PATH" FIXTURE_SYSTEM_TRUST=true \
    assert_system_trusts_local_ingress_leaf "$CERT_FILE" \
    app.budgetanalyzer.localhost "$SYSTEM_BUNDLE" \
    || fail "system-trusted leaf was rejected"
pass "system-trusted ingress leaf passes hostname-aware verification"

expected_source=". \"\$SCRIPT_DIR/../lib/local-ingress-client-trust.sh\""
expected_assertion="assert_system_trusts_local_ingress_leaf \"\$LOCAL_INGRESS_CERT\""
grep -Fq "$expected_source" \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    || fail "Tilt prerequisite checker does not source the client-trust helper"
grep -Fq "$expected_assertion" \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    || fail "Tilt prerequisite checker does not enforce system client trust"
pass "Tilt prerequisite checker wires the system client-trust assertion"

if "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" --guest-local \
    >"$FIXTURE_DIR/unknown-mode.out" 2>&1; then
    fail "retired guest-local mode unexpectedly passed"
fi
grep -Fq 'unknown argument: --guest-local' "$FIXTURE_DIR/unknown-mode.out" \
    || fail "retired guest-local mode did not fail through the generic parser"
if grep -Fq 'check_command "mkcert"' \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh"; then
    fail "Tilt prerequisites still require mkcert"
fi
pass "Tilt prerequisites expose one mode and do not require mkcert"

printf 'Tilt client-trust fixtures passed: %s checks.\n' "$pass_count"
