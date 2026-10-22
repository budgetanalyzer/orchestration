#!/usr/bin/env bash

# Offline client-trust fixtures. The helper runs real OpenSSL against the
# public test certificates in fixtures/client-trust/. Temporary bundles and
# hashed directories are test inputs; no system or NSS trust is read or changed
# except where a case deliberately reaches the host default bundle path.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
CERT_DIR="$TEST_DIR/fixtures/client-trust"
ROOT_CERT="$CERT_DIR/root.pem"
LEAF_CERT="$CERT_DIR/leaf.pem"
UNRELATED_ROOT="$CERT_DIR/unrelated-root.pem"
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# shellcheck source=scripts/lib/local-ingress-client-trust.sh
. "$REPO_DIR/scripts/lib/local-ingress-client-trust.sh"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    if [[ -f "$FIXTURE_DIR/out" ]]; then
        sed 's/^/  | /' "$FIXTURE_DIR/out" >&2
    fi
    exit 1
}

command -v openssl >/dev/null 2>&1 || fail "real openssl is required for these fixtures"
for fixture in "$ROOT_CERT" "$LEAF_CERT" "$UNRELATED_ROOT"; do
    [[ -s "$fixture" ]] || fail "missing public certificate fixture: $fixture"
done

# Isolate the default OpenSSL locations from the host for every helper call.
EMPTY_CERT_DIR="$FIXTURE_DIR/empty-cert-dir"
mkdir "$EMPTY_CERT_DIR"
export SSL_CERT_DIR="$EMPTY_CERT_DIR"
export SSL_CERT_FILE="$FIXTURE_DIR/no-default-file.pem"

run_helper() {
    assert_system_trusts_local_ingress_leaf "$@" >"$FIXTURE_DIR/out" 2>&1
}

expect_output() {
    grep -Fq "$1" "$FIXTURE_DIR/out" || fail "$2 did not report '$1'"
}

run_helper "$LEAF_CERT" app.budgetanalyzer.localhost "$ROOT_CERT" \
    || fail "matching root bundle rejected its leaf"
pass "matching root bundle verifies the leaf for app.budgetanalyzer.localhost"

if run_helper "$LEAF_CERT" app.budgetanalyzer.test "$ROOT_CERT"; then
    fail "wrong hostname unexpectedly passed"
fi
expect_output "system trust does not verify the ingress certificate for app.budgetanalyzer.test" \
    "wrong hostname"
expect_output "hostname mismatch" "wrong hostname"
pass "wrong hostname is rejected with the OpenSSL diagnostic"

if run_helper "$LEAF_CERT" app.budgetanalyzer.localhost "$UNRELATED_ROOT"; then
    fail "unrelated root bundle unexpectedly passed"
fi
expect_output "unable to get local issuer certificate" "unrelated root bundle"
pass "nonempty bundle with an unrelated root is rejected"

# The valid root is reachable only through a hashed SSL_CERT_DIR. Unrestricted
# OpenSSL accepts it; the helper must use the selected bundle alone.
HASHED_DIR="$FIXTURE_DIR/hashed-root-dir"
mkdir "$HASHED_DIR"
cp "$ROOT_CERT" "$HASHED_DIR/root.pem"
ln -s root.pem "$HASHED_DIR/$(openssl x509 -hash -noout -in "$ROOT_CERT").0"
SSL_CERT_DIR="$HASHED_DIR" openssl verify -CAfile "$UNRELATED_ROOT" \
    -verify_hostname app.budgetanalyzer.localhost "$LEAF_CERT" >/dev/null 2>&1 \
    || fail "unrestricted OpenSSL did not use SSL_CERT_DIR; the regression is not exercised"
if SSL_CERT_DIR="$HASHED_DIR" \
    run_helper "$LEAF_CERT" app.budgetanalyzer.localhost "$UNRELATED_ROOT"; then
    fail "helper borrowed trust from SSL_CERT_DIR instead of the selected bundle"
fi
expect_output "unable to get local issuer certificate" "SSL_CERT_DIR-only root"
pass "root available only through SSL_CERT_DIR is rejected although unrestricted OpenSSL accepts it"

if PATH="$FIXTURE_DIR/no-tools" run_helper "$LEAF_CERT" \
    app.budgetanalyzer.localhost "$ROOT_CERT"; then
    fail "missing openssl unexpectedly passed"
fi
expect_output "required command is missing: openssl" "missing openssl"
pass "missing openssl fails closed"

if run_helper "$FIXTURE_DIR/absent-leaf.pem" app.budgetanalyzer.localhost "$ROOT_CERT"; then
    fail "missing leaf unexpectedly passed"
fi
expect_output "ingress certificate is missing or unreadable" "missing leaf"
if run_helper "$LEAF_CERT" app.budgetanalyzer.localhost "$FIXTURE_DIR/absent-bundle.pem"; then
    fail "missing bundle unexpectedly passed"
fi
expect_output "system trust bundle is missing or unreadable" "missing bundle"
pass "missing leaf or trust bundle fails before verification"

# A failing openssl (for example one rejecting an option) must surface stderr
# and fail closed.
MOCK_BIN="$FIXTURE_DIR/bin"
mkdir "$MOCK_BIN"
cat > "$MOCK_BIN/openssl" <<'EOF'
#!/usr/bin/env bash
printf 'verify: Unknown option: fixture\n' >&2
exit 1
EOF
chmod 0755 "$MOCK_BIN/openssl"
if PATH="$MOCK_BIN:$PATH" run_helper "$LEAF_CERT" \
    app.budgetanalyzer.localhost "$ROOT_CERT"; then
    fail "failing openssl unexpectedly passed"
fi
expect_output "verify: Unknown option: fixture" "failing openssl"
expect_output "system trust does not verify" "failing openssl"
pass "openssl errors are surfaced and fail closed"

# Run the real prerequisite checker in a copied repository. Docker, Kind and
# kubectl are failing stubs, and the imported-TLS validator is a passing stub,
# so section 11 reaches the client-trust helper without any cluster access.
FIXTURE_REPO="$FIXTURE_DIR/orchestration"
STUB_BIN="$FIXTURE_DIR/stub-bin"
mkdir -p "$FIXTURE_REPO/scripts/bootstrap" "$FIXTURE_REPO/scripts/lib" \
    "$FIXTURE_REPO/nginx/certs/k8s" "$STUB_BIN"
cp "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    "$FIXTURE_REPO/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/pinned-tool-versions.sh" \
    "$REPO_DIR/scripts/lib/local-kubernetes-target.sh" \
    "$REPO_DIR/scripts/lib/local-ingress-client-trust.sh" \
    "$FIXTURE_REPO/scripts/lib/"
cp "$REPO_DIR/kind-cluster-config.yaml" "$FIXTURE_REPO/"
printf '#!/usr/bin/env bash\nexit 0\n' \
    > "$FIXTURE_REPO/scripts/bootstrap/install-imported-ingress-tls.sh"
for stub in docker kind kubectl; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB_BIN/$stub"
done
chmod 0755 "$FIXTURE_REPO/scripts/bootstrap/install-imported-ingress-tls.sh" \
    "$STUB_BIN/docker" "$STUB_BIN/kind" "$STUB_BIN/kubectl"
FIXTURE_LEAF="$FIXTURE_REPO/nginx/certs/k8s/_wildcard.budgetanalyzer.localhost.pem"

run_prerequisites() {
    # The checker exits with its error count; inspect its report instead.
    env -u DOCKER_HOST -u DOCKER_CONTEXT -u KIND_EXPERIMENTAL_PROVIDER \
        PATH="$STUB_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/check-tilt-prerequisites.sh" \
        >"$FIXTURE_DIR/out" 2>&1 || true
}

expect_trust_failure_report() {
    expect_output "All three imported ingress TLS files are valid" "$1"
    expect_output "The current ingress certificate is not trusted by the system client store" "$1"
    expect_output "docs/development/local-environment.md#development-vm-import-and-renewal" "$1"
    if grep -Fq "System trust verifies the ingress certificate" "$FIXTURE_DIR/out"; then
        fail "$1 reported system trust success"
    fi
}

run_prerequisites
expect_trust_failure_report "missing ingress leaf"
expect_output "ingress certificate is missing or unreadable: $FIXTURE_LEAF" \
    "missing ingress leaf"
pass "prerequisite checker reports a missing ingress leaf as a trust failure"

# The test root is never in any system bundle, so the checker's default
# bundle path rejects the leaf whether or not that bundle exists here.
cp "$LEAF_CERT" "$FIXTURE_LEAF"
run_prerequisites
expect_trust_failure_report "untrusted ingress leaf"
expect_output "system trust" "untrusted ingress leaf"
if grep -Fq "ingress certificate is missing or unreadable" "$FIXTURE_DIR/out"; then
    fail "untrusted ingress leaf was reported as missing"
fi
if grep -Fiq mkcert "$FIXTURE_DIR/out"; then
    fail "Tilt prerequisites still check or mention mkcert"
fi
pass "prerequisite checker reports an untrusted ingress leaf and does not require mkcert"

if "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" --guest-local \
    >"$FIXTURE_DIR/out" 2>&1; then
    fail "retired guest-local mode unexpectedly passed"
fi
expect_output 'unknown argument: --guest-local' "retired guest-local mode"
pass "retired guest-local mode fails through the generic parser"

printf 'Tilt client-trust fixtures passed: %s checks.\n' "$pass_count"
