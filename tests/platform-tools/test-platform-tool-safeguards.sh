#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_PARENT="${RUNNER_TEMP:-${HOME:?}}"
FIXTURE_DIR="$(mktemp -d "$FIXTURE_PARENT/platform-tool-fixtures.XXXXXX")"
FIXTURE_REPO="$FIXTURE_DIR/repo"
MOCK_BIN="$FIXTURE_DIR/mock-bin"
CURL_LOG="$FIXTURE_DIR/curl.log"
mkdir -p "$FIXTURE_REPO/scripts/bootstrap" "$FIXTURE_REPO/scripts/lib" "$MOCK_BIN"
cp "$REPO_DIR/scripts/bootstrap/install-verified-tool.sh" "$FIXTURE_REPO/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/pinned-tool-versions.sh" "$FIXTURE_REPO/scripts/lib/"
chmod 0755 "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh"
touch "$CURL_LOG"
trap 'rm -rf "$FIXTURE_DIR"' EXIT

# shellcheck source=scripts/lib/pinned-tool-versions.sh
. "$REPO_DIR/scripts/lib/pinned-tool-versions.sh"

pass_count=0

pass() {
    printf 'PASS: %s\n' "$1"
    ((pass_count += 1))
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

expect_failure() {
    local description expected_text output

    description="$1"
    expected_text="$2"
    shift 2
    output="$FIXTURE_DIR/failure.out"
    if "$@" >"$output" 2>&1; then
        fail "$description unexpectedly passed"
    fi
    grep -Fq "$expected_text" "$output" \
        || fail "$description did not report '$expected_text'"
    pass "$description fails closed"
}

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG:?}"
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            output="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done
cp -- "${FIXTURE_ARTIFACT:?}" "$output"
EOF

cat > "$MOCK_BIN/stat" <<'EOF'
#!/usr/bin/env bash
target="${*: -1}"
if [[ -n "${FIXTURE_STAT_PATH:-}" && "$target" == "$FIXTURE_STAT_PATH" ]]; then
    case "${1:-}:${2:-}" in
        -c:%u|-f:%u) printf '%s\n' "${FIXTURE_STAT_UID:-0}" ;;
        -c:%a|-f:%Lp) printf '%s\n' "${FIXTURE_STAT_MODE:?}" ;;
        *) exec /usr/bin/stat "$@" ;;
    esac
else
    exec /usr/bin/stat "$@"
fi
EOF
chmod 0755 "$MOCK_BIN/curl" "$MOCK_BIN/stat"

for tool in kubectl helm tilt kind; do
    version="$(phase7_normalize_semver "$(phase7_tool_version "$tool")")"
    for platform in linux-amd64 linux-arm64; do
        url="$(phase7_tool_url "$tool" "$platform")"
        checksum="$(phase7_tool_sha256 "$tool" "$platform")"
        [[ "$url" == https://*"$version"* ]] \
            || fail "$tool/$platform URL is not tied to its pin"
        [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] \
            || fail "$tool/$platform checksum is incomplete"
    done
done
pass "all four platform tools declare version-coupled amd64/arm64 release inputs"

phase7_tool_version_matches helm "v${PHASE7_HELM_VERSION#v}" \
    || fail "pinned Helm version was rejected"
if phase7_tool_version_matches helm 'v3.99.0'; then
    fail "non-pinned Helm version was accepted"
fi
grep -Fq 'ensure_pinned_tool "helm"' "$REPO_DIR/setup.sh" \
    || fail "setup does not enforce Helm through ensure_pinned_tool"
grep -Fq 'check_pinned_tool_version helm' \
    "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    || fail "prerequisite checker does not enforce exact Helm"
if grep -Eq 'ensure_supported_helm|check_helm_version|SUPPORTED_HELM_(MINIMUM|MAXIMUM)' \
    "$REPO_DIR/setup.sh" "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh"; then
    fail "a Helm supported-range check remains"
fi
pass "non-pinned Helm is rejected by the exact setup and prerequisite contract"

PLATFORM="$(phase7_platform_key "" "")"
ORIGINAL_KUBECTL_SHA="$(phase7_tool_sha256 kubectl "$PLATFORM")"
FIXTURE_ARTIFACT="$FIXTURE_DIR/kubectl-fixture"
export FIXTURE_ARTIFACT CURL_LOG
cat > "$FIXTURE_ARTIFACT" <<EOF
#!/usr/bin/env bash
printf '%s\n' 'Client Version: ${PHASE7_KUBECTL_VERSION}'
EOF
chmod 0755 "$FIXTURE_ARTIFACT"
FIXTURE_KUBECTL_SHA="$(phase7_sha256_file "$FIXTURE_ARTIFACT")"
sed -i "s/$ORIGINAL_KUBECTL_SHA/$FIXTURE_KUBECTL_SHA/" \
    "$FIXTURE_REPO/scripts/lib/pinned-tool-versions.sh"

SAFE_INSTALL_DIR="$FIXTURE_DIR/safe-tools"
PATH="$MOCK_BIN:$PATH" "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$SAFE_INSTALL_DIR" >/dev/null
[[ -x "$SAFE_INSTALL_DIR/kubectl" ]] \
    || fail "safe user-owned custom install did not produce kubectl"
pass "safe user-owned custom install directories remain supported"

CORRUPT_ARTIFACT="$FIXTURE_DIR/corrupt-artifact"
printf 'corrupt\n' > "$CORRUPT_ARTIFACT"
FIXTURE_ARTIFACT="$CORRUPT_ARTIFACT"
export FIXTURE_ARTIFACT
CHECKSUM_DIR="$FIXTURE_DIR/checksum-target"
expect_failure "checksum mismatch" "Checksum mismatch" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$CHECKSUM_DIR"
[[ ! -e "$CHECKSUM_DIR" ]] \
    || fail "checksum mismatch wrote the install directory"

MISSING_ARCHIVE="$FIXTURE_DIR/helm-missing-member.tar.gz"
ARCHIVE_SOURCE="$FIXTURE_DIR/archive-source"
mkdir -p "$ARCHIVE_SOURCE"
printf 'not helm\n' > "$ARCHIVE_SOURCE/README"
tar -czf "$MISSING_ARCHIVE" -C "$ARCHIVE_SOURCE" README
ORIGINAL_HELM_SHA="$(phase7_tool_sha256 helm "$PLATFORM")"
MISSING_ARCHIVE_SHA="$(phase7_sha256_file "$MISSING_ARCHIVE")"
sed -i "s/$ORIGINAL_HELM_SHA/$MISSING_ARCHIVE_SHA/" \
    "$FIXTURE_REPO/scripts/lib/pinned-tool-versions.sh"
FIXTURE_ARTIFACT="$MISSING_ARCHIVE"
export FIXTURE_ARTIFACT
MISSING_MEMBER_DIR="$FIXTURE_DIR/missing-member-target"
expect_failure "missing archive member" "Required archive member is missing" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    helm --install-dir "$MISSING_MEMBER_DIR"
[[ ! -e "$MISSING_MEMBER_DIR" ]] \
    || fail "missing archive member wrote the install directory"

COLLISION_DIR="$FIXTURE_DIR/collision-tools"
mkdir -m 0755 "$COLLISION_DIR"
printf '#!/usr/bin/env bash\necho unexpected\n' > "$COLLISION_DIR/kubectl"
chmod 0755 "$COLLISION_DIR/kubectl"
: > "$CURL_LOG"
expect_failure "unexpected destination collision" "Destination collision" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$COLLISION_DIR"
[[ ! -s "$CURL_LOG" ]] || fail "destination collision reached download"

DOWNGRADE_DIR="$FIXTURE_DIR/downgrade-tools"
mkdir -m 0755 "$DOWNGRADE_DIR"
cat > "$DOWNGRADE_DIR/kubectl" <<'EOF'
#!/usr/bin/env bash
echo 'Client Version: v99.0.0'
EOF
chmod 0755 "$DOWNGRADE_DIR/kubectl"
DOWNGRADE_BEFORE="$(phase7_sha256_file "$DOWNGRADE_DIR/kubectl")"
: > "$CURL_LOG"
expect_failure "unexpected downgrade" "Refusing to downgrade" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$DOWNGRADE_DIR"
[[ ! -s "$CURL_LOG" ]] || fail "downgrade rejection reached download"
[[ "$(phase7_sha256_file "$DOWNGRADE_DIR/kubectl")" == "$DOWNGRADE_BEFORE" ]] \
    || fail "downgrade rejection changed the destination"

SYMLINK_DEST_DIR="$FIXTURE_DIR/symlink-destination"
mkdir -m 0755 "$SYMLINK_DEST_DIR"
ln -s "$FIXTURE_ARTIFACT" "$SYMLINK_DEST_DIR/kubectl"
expect_failure "symlinked destination" "Symlinked install destination" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$SYMLINK_DEST_DIR"

REAL_PARENT="$FIXTURE_DIR/real-parent"
mkdir -m 0755 "$REAL_PARENT"
ln -s "$REAL_PARENT" "$FIXTURE_DIR/symlink-parent"
expect_failure "symlinked parent" "Symlinked install parent" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$FIXTURE_DIR/symlink-parent/tools"

for mode in 0775 0777; do
    WRITABLE_DIR="$FIXTURE_DIR/writable-$mode"
    mkdir -m "$mode" "$WRITABLE_DIR"
    expect_failure "mode $mode user-owned destination" "Group/world-writable install parent" \
        env PATH="$MOCK_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
        kubectl --install-dir "$WRITABLE_DIR"
done

for mode in 0775 0777; do
    WRITABLE_DEST_DIR="$FIXTURE_DIR/writable-destination-$mode"
    mkdir -m 0755 "$WRITABLE_DEST_DIR"
    cat > "$WRITABLE_DEST_DIR/kubectl" <<EOF
#!/usr/bin/env bash
echo 'Client Version: ${PHASE7_KUBECTL_VERSION}'
EOF
    chmod "$mode" "$WRITABLE_DEST_DIR/kubectl"
    expect_failure "mode $mode user-owned destination file" \
        "Group/world-writable install destination" \
        env PATH="$MOCK_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
        kubectl --install-dir "$WRITABLE_DEST_DIR"
done

export FIXTURE_STAT_PATH=/usr/local/bin
for mode in 0775 0777; do
    export FIXTURE_STAT_MODE="$mode"
    : > "$CURL_LOG"
    expect_failure "mode $mode root-owned destination parent" \
        "Group/world-writable install parent: /usr/local/bin" \
        env PATH="$MOCK_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" kubectl
    [[ ! -s "$CURL_LOG" ]] \
        || fail "unsafe root-owned path reached download"
done
export FIXTURE_STAT_UID=1000 FIXTURE_STAT_MODE=0755
expect_failure "non-root-owned system parent" "System install parent is not root-owned" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" kubectl

export FIXTURE_STAT_PATH=/usr/local/bin/kubectl FIXTURE_STAT_UID=0
for mode in 0775 0777; do
    export FIXTURE_STAT_MODE="$mode"
    expect_failure "mode $mode root-owned destination file" \
        "Group/world-writable install destination" \
        env PATH="$MOCK_BIN:$PATH" \
        "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" kubectl
done

FOREIGN_DIR="$FIXTURE_DIR/foreign-owner"
mkdir -m 0755 "$FOREIGN_DIR"
export FIXTURE_STAT_PATH="$FOREIGN_DIR" FIXTURE_STAT_UID=4242 FIXTURE_STAT_MODE=0755
expect_failure "foreign-owned custom parent" "Custom install parent is not owned" \
    env PATH="$MOCK_BIN:$PATH" \
    "$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh" \
    kubectl --install-dir "$FOREIGN_DIR"
unset FIXTURE_STAT_PATH FIXTURE_STAT_MODE FIXTURE_STAT_UID

printf 'Platform-tool safeguard fixtures passed: %s checks.\n' "$pass_count"
