#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_DIR="$(mktemp -d)"
MOCK_BIN="$FIXTURE_DIR/bin"
CERT_DIR="$FIXTURE_DIR/certs"
OPENSSL_LOG="$FIXTURE_DIR/openssl.log"
MUTATION_LOG="$FIXTURE_DIR/mutation.log"
mkdir -p "$MOCK_BIN" "$CERT_DIR"
touch \
    "$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem" \
    "$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem" \
    "$CERT_DIR/_mkcert-rootCA.pem" \
    "$OPENSSL_LOG" \
    "$MUTATION_LOG"
chmod 0600 "$CERT_DIR/_wildcard.budgetanalyzer.localhost-key.pem"
export OPENSSL_LOG MUTATION_LOG
trap 'rm -rf "$FIXTURE_DIR"' EXIT

cat > "$MOCK_BIN/openssl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${OPENSSL_LOG:?}"

case "${1:-}" in
    x509)
        if [[ " $* " == *" -checkhost "* ]]; then
            printf 'Hostname %s does NOT match certificate\n' "${*: -1}"
            exit 0
        fi
        if [[ " $* " == *" -text "* ]]; then
            printf 'X509v3 Basic Constraints: critical\n    CA:TRUE\n'
        elif [[ " $* " == *" -pubkey "* ]]; then
            printf '%s\n' 'fixture-public-key'
        fi
        ;;
    pkey)
        if [[ " $* " == *" -pubout "* ]]; then
            printf '%s\n' 'fixture-public-key'
        fi
        ;;
    verify)
        [[ " $* " == *" -verify_hostname app.budgetanalyzer.localhost "* ]] || exit 92
        [[ "${FIXTURE_HOSTNAME_MATCH:-true}" == true ]] || exit 1
        ;;
    *) exit 91 ;;
esac
EOF

cat > "$MOCK_BIN/mutation-command" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "${MUTATION_LOG:?}"
exit 97
EOF

for command_name in kubectl sudo update-ca-certificates; do
    cp "$MOCK_BIN/mutation-command" "$MOCK_BIN/$command_name"
done
chmod +x "$MOCK_BIN/openssl" "$MOCK_BIN/mutation-command" \
    "$MOCK_BIN/kubectl" "$MOCK_BIN/sudo" "$MOCK_BIN/update-ca-certificates"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

if PATH="$MOCK_BIN:$PATH" openssl x509 -in "$CERT_DIR/_wildcard.budgetanalyzer.localhost.pem" \
    -noout -checkhost unrelated.invalid >/dev/null 2>&1; then
    pass "fixture reproduces x509 -checkhost mismatch with exit zero"
else
    fail "fixture did not reproduce x509 -checkhost exit behavior"
fi

: > "$OPENSSL_LOG"
if PATH="$MOCK_BIN:$PATH" FIXTURE_HOSTNAME_MATCH=false \
    "$REPO_DIR/scripts/bootstrap/install-imported-ingress-tls.sh" \
    --cert-dir "$CERT_DIR" > "$FIXTURE_DIR/mismatch.out" 2>&1; then
    fail "wrong-host ingress certificate unexpectedly passed"
fi
grep -Fq 'does not verify the ingress leaf for app.budgetanalyzer.localhost' \
    "$FIXTURE_DIR/mismatch.out" \
    || fail "wrong-host rejection did not report hostname-aware verification failure"
grep -Fq 'verify -CAfile' "$OPENSSL_LOG" \
    || fail "wrong-host check did not perform chain verification"
grep -Fq -- '-verify_hostname app.budgetanalyzer.localhost' "$OPENSSL_LOG" \
    || fail "wrong-host check did not request hostname verification"
if grep -Fq -- '-checkhost' "$OPENSSL_LOG"; then
    fail "installer still used the ineffective x509 -checkhost gate"
fi
[[ ! -s "$MUTATION_LOG" ]] \
    || fail "wrong-host rejection occurred after a mutation command"
pass "wrong-host certificate is rejected before mutation"

: > "$OPENSSL_LOG"
if ! PATH="$MOCK_BIN:$PATH" FIXTURE_HOSTNAME_MATCH=true \
    "$REPO_DIR/scripts/bootstrap/install-imported-ingress-tls.sh" \
    --validate-only --cert-dir "$CERT_DIR" > "$FIXTURE_DIR/match.out" 2>&1; then
    fail "matching-host certificate fixture was rejected"
fi
grep -Fq 'Imported ingress TLS files are valid for app.budgetanalyzer.localhost.' \
    "$FIXTURE_DIR/match.out" \
    || fail "matching-host validation did not report success"
grep -Fq -- '-verify_hostname app.budgetanalyzer.localhost' "$OPENSSL_LOG" \
    || fail "matching-host validation did not request hostname verification"
[[ ! -s "$MUTATION_LOG" ]] \
    || fail "validate-only fixture invoked a mutation command"
pass "matching-host certificate passes hostname-aware validate-only checks"

: > "$OPENSSL_LOG"
: > "$MUTATION_LOG"
if PATH="$MOCK_BIN:$PATH" \
    BUDGET_ANALYZER_WORKTREE_PARENT=/fixture/worktrees \
    BUDGET_ANALYZER_BARE_PARENT=/fixture/bares \
    "$REPO_DIR/scripts/bootstrap/install-imported-ingress-tls.sh" \
    --install-system-trust --cert-dir "$CERT_DIR" \
    > "$FIXTURE_DIR/retired-trust.out" 2>&1; then
    fail "retired orchestration trust writer unexpectedly succeeded"
fi
grep -Fq -- '--install-system-trust is retired' "$FIXTURE_DIR/retired-trust.out" \
    || fail "retired trust option did not explain ownership migration"
grep -Fq '../workspace/scripts/install-agent-vm-local-ca-trust.sh' \
    "$FIXTURE_DIR/retired-trust.out" \
    || fail "retired trust option did not report the canonical workspace command"
expected_environment_load=". \"\$HOME/.config/budget-analyzer-native/env.sh\""
grep -Fq -- "$expected_environment_load" "$FIXTURE_DIR/retired-trust.out" \
    || fail "retired trust option omitted the native environment prerequisite"
expected_worktree_arg="--worktree-parent \"\$BUDGET_ANALYZER_WORKTREE_PARENT\""
expected_bare_arg="--bare-parent \"\$BUDGET_ANALYZER_BARE_PARENT\""
grep -Fq -- "$expected_worktree_arg" \
    "$FIXTURE_DIR/retired-trust.out" \
    || fail "retired trust option omitted the canonical worktree input"
grep -Fq -- "$expected_bare_arg" \
    "$FIXTURE_DIR/retired-trust.out" \
    || fail "retired trust option omitted the canonical bare-repository input"
[[ ! -s "$OPENSSL_LOG" ]] \
    || fail "retired trust option inspected certificates before rejecting mutation"
[[ ! -s "$MUTATION_LOG" ]] \
    || fail "retired trust option invoked a mutation command"
pass "retired orchestration trust writer rejects with canonical human command"

if grep -Fq -- '--install-system-trust' "$REPO_DIR/setup.sh"; then
    fail "guest bootstrap still requests orchestration system-trust mutation"
fi
expected_setup_call="\"\$SCRIPT_DIR/scripts/bootstrap/install-imported-ingress-tls.sh\""
grep -Fq "$expected_setup_call" \
    "$REPO_DIR/setup.sh" \
    || fail "guest bootstrap no longer reconciles the imported ingress Secret"
pass "guest bootstrap delegates trust and retains Secret reconciliation"

printf 'Imported ingress TLS fixtures passed: %s checks.\n' "$pass_count"
