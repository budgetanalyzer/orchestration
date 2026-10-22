#!/usr/bin/env bash
# Offline fixtures for the verified platform-tool installer, its destination
# contracts and the shared exact-version probes used by setup and the
# prerequisite checker. Every artifact and executable comes from a fixture; no
# host platform binary, sudo or privileged write is used.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TEST_DIR/../.." && pwd)"
FIXTURE_PARENT="${RUNNER_TEMP:-${HOME:?}}"
# Physical path so privileged ancestor checks see no inherited symlinks.
FIXTURE_DIR="$(cd "$(mktemp -d "$FIXTURE_PARENT/platform-tool-fixtures.XXXXXX")" && pwd -P)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
FIXTURE_REPO="$FIXTURE_DIR/repo"
INSTALLER="$FIXTURE_REPO/scripts/bootstrap/install-verified-tool.sh"
MOCK_BIN="$FIXTURE_DIR/mock-bin"
UTIL_BIN="$FIXTURE_DIR/util-bin"
CURL_LOG="$FIXTURE_DIR/curl.log"
SUDO_LOG="$FIXTURE_DIR/sudo.log"
mkdir -p "$FIXTURE_REPO/scripts/bootstrap" "$FIXTURE_REPO/scripts/lib" "$MOCK_BIN" "$UTIL_BIN"
cp "$REPO_DIR/scripts/bootstrap/install-verified-tool.sh" "$FIXTURE_REPO/scripts/bootstrap/"
cp "$REPO_DIR/scripts/lib/pinned-tool-versions.sh" \
    "$REPO_DIR/scripts/lib/verified-tool-destination.sh" "$FIXTURE_REPO/scripts/lib/"
chmod 0755 "$INSTALLER"
touch "$CURL_LOG" "$SUDO_LOG"

# shellcheck source=scripts/lib/pinned-tool-versions.sh
# shellcheck disable=SC1091 # Resolved through REPO_DIR at runtime; run shellcheck -x when following sources.
. "$REPO_DIR/scripts/lib/pinned-tool-versions.sh"
# shellcheck source=scripts/lib/verified-tool-destination.sh
# shellcheck disable=SC1091 # Resolved through REPO_DIR at runtime; run shellcheck -x when following sources.
. "$REPO_DIR/scripts/lib/verified-tool-destination.sh"

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
    grep -Fq -- "$expected_text" "$output" \
        || fail "$description did not report '$expected_text': $(cat "$output")"
    pass "$description fails closed"
}

run_installer() {
    env PATH="$MOCK_BIN:$PATH" "$INSTALLER" "$@"
}

write_stub() {
    # write_stub PATH STDOUT [EXIT_STATUS] [STDERR]
    cat > "$1" <<EOF
#!$BASH
printf '%s\n' '${4:-}' >&2
[[ -z '$2' ]] || printf '%s\n' '$2'
exit ${3:-0}
EOF
    chmod 0755 "$1"
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

cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SUDO_LOG:?}"
echo "sudo is not available in platform-tool fixtures" >&2
exit 1
EOF

# Reports ownership/mode from FIXTURE_STAT_TABLE ("path uid mode" lines),
# otherwise FIXTURE_STAT_DEFAULT ("uid mode") when set, otherwise real stat.
cat > "$MOCK_BIN/stat" <<'EOF'
#!/usr/bin/env bash
target="${*: -1}"
entry=""
if [[ -n "${FIXTURE_STAT_TABLE:-}" ]]; then
    entry="$(awk -v p="$target" '$1 == p {print $2, $3; exit}' "$FIXTURE_STAT_TABLE")"
fi
[[ -n "$entry" ]] || entry="${FIXTURE_STAT_DEFAULT:-}"
if [[ -z "$entry" ]]; then
    exec /usr/bin/stat "$@"
fi
read -r uid mode <<< "$entry"
case "${1:-}:${2:-}" in
    -c:%u|-f:%u) printf '%s\n' "$uid" ;;
    -c:%a|-f:%Lp) printf '%s\n' "$mode" ;;
    *) exec /usr/bin/stat "$@" ;;
esac
EOF
chmod 0755 "$MOCK_BIN/curl" "$MOCK_BIN/sudo" "$MOCK_BIN/stat"
export CURL_LOG SUDO_LOG

# Minimal utilities for PATH-controlled probe checks, so no host platform
# binary can be selected.
for util in dirname sed head cat; do
    ln -s "$(command -v "$util")" "$UTIL_BIN/$util"
done

for tool in kubectl helm tilt mkcert kind kubeconform kube-linter kyverno yq; do
    kind="$(phase7_tool_artifact_kind "$tool")" || fail "$tool has no artifact kind"
    if [[ "$kind" == archive ]]; then
        phase7_tool_archive_member "$tool" linux-amd64 >/dev/null || fail "$tool archive has no member"
    fi
    for platform in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64; do
        [[ "$(phase7_tool_sha256 "$tool" "$platform")" =~ ^[0-9a-f]{64}$ ]] \
            || fail "$tool/$platform checksum is incomplete"
    done
done
pass "every installable tool declares an artifact kind and complete checksums (metadata check)"

UNKNOWN_OUTPUT="$FIXTURE_DIR/unknown-staged"
if phase7_stage_tool_binary unknown-tool linux-amd64 "$FIXTURE_DIR" "$UNKNOWN_OUTPUT" 2>/dev/null; then
    fail "unknown tool was staged"
fi
[[ ! -e "$UNKNOWN_OUTPUT" ]] || fail "unknown tool staging wrote output"
pass "a tool without artifact metadata is not staged as a raw binary"

# --- Exact Helm enforcement through the shared probe -----------------------

PROBE_DIR="$FIXTURE_DIR/probe"
mkdir -p "$PROBE_DIR"
write_stub "$PROBE_DIR/helm-pinned" "$PHASE7_HELM_VERSION" 0 "WARNING: noisy stderr"
write_stub "$PROBE_DIR/helm-other" "v3.99.0"
write_stub "$PROBE_DIR/helm-fails" "$PHASE7_HELM_VERSION" 1
write_stub "$PROBE_DIR/helm-stderr-only" "" 0 "$PHASE7_HELM_VERSION"

raw="$(phase7_tool_raw_version_at helm "$PROBE_DIR/helm-pinned")" \
    || fail "pinned Helm probe failed"
[[ "$raw" == "$PHASE7_HELM_VERSION" ]] || fail "Helm probe read stderr or extra lines: $raw"
phase7_tool_version_matches helm "$raw" || fail "pinned Helm version was rejected"
pass "pinned Helm is accepted from stdout while stderr is ignored"

raw="$(phase7_tool_raw_version_at helm "$PROBE_DIR/helm-other")" \
    || fail "non-pinned Helm probe failed"
if phase7_tool_version_matches helm "$raw"; then
    fail "non-pinned Helm version was accepted"
fi
pass "non-pinned Helm is rejected by exact matching"

for stub in helm-fails helm-stderr-only; do
    status=0
    raw="$(phase7_tool_raw_version_at helm "$PROBE_DIR/$stub")" || status=$?
    [[ "$status" == 1 && -z "$raw" ]] \
        || fail "$stub probe did not fail deliberately (status $status, output '$raw')"
    if phase7_tool_version_matches helm "$raw"; then
        fail "$stub probe result was accepted"
    fi
done
pass "failed Helm probes (nonzero exit, stderr-only version) return status 1 and are rejected"

if grep -Fq 'phase7_verify_effective_tool_version' "$REPO_DIR/setup.sh" \
    && grep -Fq 'phase7_tool_raw_version_at' "$REPO_DIR/setup.sh" \
    && grep -Fq 'phase7_tool_raw_version_at' "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh" \
    && grep -Fq 'check_pinned_tool_version helm' "$REPO_DIR/scripts/bootstrap/check-tilt-prerequisites.sh"; then
    pass "setup and the prerequisite checker call the shared probe (source wiring check)"
else
    fail "setup or the prerequisite checker no longer calls the shared probe"
fi

# --- Custom installs --------------------------------------------------------

PLATFORM="$(phase7_platform_key "" "")"
set_fixture_sha() {
    # Point the fixture repo's checksum for TOOL on this platform at ARTIFACT.
    sed -i -E "s/^( *$1:$PLATFORM\) printf ')[0-9a-f]{64}/\1$(phase7_sha256_file "$2")/" \
        "$FIXTURE_REPO/scripts/lib/pinned-tool-versions.sh"
}
FIXTURE_ARTIFACT="$FIXTURE_DIR/kubectl-fixture"
export FIXTURE_ARTIFACT
cat > "$FIXTURE_ARTIFACT" <<EOF
#!/usr/bin/env bash
printf '%s\n' 'Client Version: ${PHASE7_KUBECTL_VERSION}'
EOF
chmod 0755 "$FIXTURE_ARTIFACT"
set_fixture_sha kubectl "$FIXTURE_ARTIFACT"

assert_pinned_kubectl() {
    cmp -s "$FIXTURE_ARTIFACT" "$1/kubectl" \
        || fail "$2 did not install the verified kubectl bytes"
}

expected_dir_mode() {
    printf '%o\n' $(( 8#777 & ~8#$1 ))
}

CURRENT_UMASK="$(umask)"
NESTED_DIR="$FIXTURE_DIR/cache-current/a/b/tools"
run_installer kubectl --install-dir "$NESTED_DIR" >/dev/null
assert_pinned_kubectl "$NESTED_DIR" "nested custom install"
[[ "$(stat -c '%a' "$NESTED_DIR")" == "$(expected_dir_mode "$CURRENT_UMASK")" ]] \
    || fail "nested custom directories did not follow umask $CURRENT_UMASK"
pass "multiple missing custom directories are created under umask $CURRENT_UMASK"

UMASK_DIR="$FIXTURE_DIR/cache-0002/phase7-static-tools/bin"
(umask 0002 && run_installer kubectl --install-dir "$UMASK_DIR" >/dev/null)
assert_pinned_kubectl "$UMASK_DIR" "umask 0002 custom install"
for dir in "$FIXTURE_DIR/cache-0002" "$FIXTURE_DIR/cache-0002/phase7-static-tools" "$UMASK_DIR"; do
    [[ "$(stat -c '%a' "$dir")" == 775 ]] || fail "umask 0002 did not create mode 775 at $dir"
done
pass "umask 0002 cache layout installs into mode-775 created directories"

GROUP_PARENT="$FIXTURE_DIR/group-writable-parent"
mkdir -m 0775 "$GROUP_PARENT"
chmod 0775 "$GROUP_PARENT"
run_installer kubectl --install-dir "$GROUP_PARENT" >/dev/null
assert_pinned_kubectl "$GROUP_PARENT" "mode-775 parent install"
[[ "$(stat -c '%a' "$GROUP_PARENT")" == 775 ]] || fail "installer changed the existing parent mode"
pass "existing mode-775 user-owned parent is supported and left unchanged"

REAL_PARENT="$FIXTURE_DIR/real-parent"
mkdir "$REAL_PARENT"
ln -s "$REAL_PARENT" "$FIXTURE_DIR/symlink-parent"
run_installer kubectl --install-dir "$FIXTURE_DIR/symlink-parent/nested/tools" >/dev/null
assert_pinned_kubectl "$REAL_PARENT/nested/tools" "symlinked-ancestor install"
pass "custom installs through symlinked ancestors succeed"

for case_version in v99.0.0 v1.0.0; do
    REPLACE_DIR="$FIXTURE_DIR/replace-$case_version"
    mkdir "$REPLACE_DIR"
    write_stub "$REPLACE_DIR/kubectl" "Client Version: $case_version"
    chmod 0775 "$REPLACE_DIR/kubectl"
    output="$(run_installer kubectl --install-dir "$REPLACE_DIR")"
    grep -Fxq "Replacing kubectl ${case_version#v} with pinned $PHASE7_KUBECTL_VERSION at $REPLACE_DIR/kubectl" \
        <<< "$output" || fail "replacement of $case_version was not announced: $output"
    assert_pinned_kubectl "$REPLACE_DIR" "replacement of $case_version"
    pass "recognized kubectl $case_version is replaced with the pin and announced"
done

LATER_DIR="$FIXTURE_DIR/later-path"
mkdir "$LATER_DIR"
write_stub "$LATER_DIR/kubectl" "Client Version: v99.0.0"
LATER_BEFORE="$(phase7_sha256_file "$LATER_DIR/kubectl")"
UNTOUCHED_DIR="$FIXTURE_DIR/untouched-target"
env PATH="$LATER_DIR:$MOCK_BIN:$PATH" "$INSTALLER" kubectl --install-dir "$UNTOUCHED_DIR" >/dev/null
assert_pinned_kubectl "$UNTOUCHED_DIR" "install with another kubectl on PATH"
[[ "$(phase7_sha256_file "$LATER_DIR/kubectl")" == "$LATER_BEFORE" ]] \
    || fail "installer modified an unrelated PATH executable"
pass "an unrelated kubectl on PATH is neither checked nor modified"

SYMLINK_DEST_DIR="$FIXTURE_DIR/symlink-destination"
mkdir "$SYMLINK_DEST_DIR"
ln -s "$FIXTURE_ARTIFACT" "$SYMLINK_DEST_DIR/kubectl"
: > "$CURL_LOG"
expect_failure "symlinked custom destination" "Symlinked install destination" \
    run_installer kubectl --install-dir "$SYMLINK_DEST_DIR"
[[ ! -s "$CURL_LOG" ]] || fail "symlinked destination reached download"

NONREGULAR_DIR="$FIXTURE_DIR/nonregular-destination"
mkdir -p "$NONREGULAR_DIR/kubectl"
expect_failure "non-regular custom destination" "not a regular file" \
    run_installer kubectl --install-dir "$NONREGULAR_DIR"

COLLISION_DIR="$FIXTURE_DIR/collision-tools"
mkdir "$COLLISION_DIR"
write_stub "$COLLISION_DIR/kubectl" "unexpected"
COLLISION_BEFORE="$(phase7_sha256_file "$COLLISION_DIR/kubectl")"
: > "$CURL_LOG"
expect_failure "unidentifiable destination contents" "cannot identify existing kubectl" \
    run_installer kubectl --install-dir "$COLLISION_DIR"
[[ ! -s "$CURL_LOG" ]] || fail "unidentifiable destination reached download"
[[ "$(phase7_sha256_file "$COLLISION_DIR/kubectl")" == "$COLLISION_BEFORE" ]] \
    || fail "unidentifiable destination was changed"

CORRUPT_ARTIFACT="$FIXTURE_DIR/corrupt-artifact"
printf 'corrupt\n' > "$CORRUPT_ARTIFACT"
CHECKSUM_DIR="$FIXTURE_DIR/checksum-target"
expect_failure "corrupt kubectl download" "Checksum mismatch" \
    env FIXTURE_ARTIFACT="$CORRUPT_ARTIFACT" PATH="$MOCK_BIN:$PATH" \
    "$INSTALLER" kubectl --install-dir "$CHECKSUM_DIR"
[[ ! -e "$CHECKSUM_DIR" ]] || fail "checksum mismatch wrote the install directory"

# Helm is an archive tool whose member is "<platform>/helm".
HELM_MEMBER="$(phase7_tool_archive_member helm "$PLATFORM")"
ARCHIVE_SOURCE="$FIXTURE_DIR/archive-source"
DUPLICATE_SOURCE="$FIXTURE_DIR/archive-duplicate"
mkdir -p "$ARCHIVE_SOURCE/$PLATFORM" "$DUPLICATE_SOURCE/$PLATFORM"
write_stub "$ARCHIVE_SOURCE/$HELM_MEMBER" "$PHASE7_HELM_VERSION"
printf 'not helm\n' > "$ARCHIVE_SOURCE/README"
printf 'appended bytes\n' > "$DUPLICATE_SOURCE/$HELM_MEMBER"

HELM_ARCHIVE="$FIXTURE_DIR/helm.tar.gz"
tar -czf "$HELM_ARCHIVE" -C "$ARCHIVE_SOURCE" README "$HELM_MEMBER"
set_fixture_sha helm "$HELM_ARCHIVE"
HELM_DIR="$FIXTURE_DIR/helm-target"
env FIXTURE_ARTIFACT="$HELM_ARCHIVE" PATH="$MOCK_BIN:$PATH" \
    "$INSTALLER" helm --install-dir "$HELM_DIR" >/dev/null
cmp -s "$ARCHIVE_SOURCE/$HELM_MEMBER" "$HELM_DIR/helm" \
    || fail "archive install did not stage exactly the required member"
pass "archive install extracts only the verified required member"

DUPLICATE_ARCHIVE="$FIXTURE_DIR/helm-duplicate-member.tar.gz"
tar -czf "$DUPLICATE_ARCHIVE" -C "$ARCHIVE_SOURCE" "$HELM_MEMBER" \
    -C "$DUPLICATE_SOURCE" "$HELM_MEMBER"
[[ "$(tar -xOzf "$DUPLICATE_ARCHIVE" "$HELM_MEMBER" | wc -l)" -gt \
    "$(wc -l < "$ARCHIVE_SOURCE/$HELM_MEMBER")" ]] \
    || fail "duplicate fixture does not concatenate under tar -xO"
set_fixture_sha helm "$DUPLICATE_ARCHIVE"
DUPLICATE_DIR="$FIXTURE_DIR/duplicate-member-target"
expect_failure "duplicated archive member" "Required archive member is duplicated" \
    env FIXTURE_ARTIFACT="$DUPLICATE_ARCHIVE" PATH="$MOCK_BIN:$PATH" \
    "$INSTALLER" helm --install-dir "$DUPLICATE_DIR"
[[ ! -e "$DUPLICATE_DIR" ]] || fail "duplicated archive member wrote the install directory"

MISSING_ARCHIVE="$FIXTURE_DIR/helm-missing-member.tar.gz"
tar -czf "$MISSING_ARCHIVE" -C "$ARCHIVE_SOURCE" README
set_fixture_sha helm "$MISSING_ARCHIVE"
MISSING_MEMBER_DIR="$FIXTURE_DIR/missing-member-target"
expect_failure "missing archive member" "Required archive member is missing" \
    env FIXTURE_ARTIFACT="$MISSING_ARCHIVE" PATH="$MOCK_BIN:$PATH" \
    "$INSTALLER" helm --install-dir "$MISSING_MEMBER_DIR"
[[ ! -e "$MISSING_MEMBER_DIR" ]] || fail "missing archive member wrote the install directory"

# --- Privileged destination contract (disposable paths, stat stub) ---------

STAT_TABLE="$FIXTURE_DIR/stat-table"
PRIV_ROOT="$FIXTURE_DIR/privileged"
PRIV_BIN="$PRIV_ROOT/bin"
mkdir -p "$PRIV_BIN"

privileged_check() {
    # Fixture ancestors outside the table report root-owned 0755.
    # shellcheck disable=SC2016 # The inner script expands its own positional arguments.
    env PATH="$MOCK_BIN:$PATH" FIXTURE_STAT_TABLE="$STAT_TABLE" FIXTURE_STAT_DEFAULT="0 755" \
        bash -c '
            set -euo pipefail
            . "$1"
            . "$2"
            verified_tool_validate_privileged_destination "$3"
            verified_tool_existing_destination_version kubectl "$3"
        ' privileged-check \
        "$REPO_DIR/scripts/lib/pinned-tool-versions.sh" \
        "$REPO_DIR/scripts/lib/verified-tool-destination.sh" "$1"
}

: > "$STAT_TABLE"
[[ -z "$(privileged_check "$PRIV_BIN/kubectl")" ]] \
    || fail "absent privileged destination reported a version"
pass "absent privileged fixture destination with safe parents is accepted"

write_stub "$PRIV_BIN/kubectl" "Client Version: v99.0.0"
[[ "$(privileged_check "$PRIV_BIN/kubectl")" == 99.0.0 ]] \
    || fail "present safe privileged destination was not recognized"
pass "present root-owned privileged fixture destination is recognized for replacement"

for mode in 775 777; do
    printf '%s 0 %s\n' "$PRIV_BIN" "$mode" > "$STAT_TABLE"
    expect_failure "mode $mode privileged parent" "Group/world-writable install parent: $PRIV_BIN" \
        privileged_check "$PRIV_BIN/kubectl"
    printf '%s 0 %s\n' "$PRIV_BIN/kubectl" "$mode" > "$STAT_TABLE"
    expect_failure "mode $mode privileged destination" \
        "Group/world-writable install destination: $PRIV_BIN/kubectl" \
        privileged_check "$PRIV_BIN/kubectl"
done

printf '%s 1000 755\n' "$PRIV_BIN" > "$STAT_TABLE"
expect_failure "non-root-owned privileged parent" "System install parent is not root-owned" \
    privileged_check "$PRIV_BIN/kubectl"
printf '%s 1000 755\n' "$PRIV_BIN/kubectl" > "$STAT_TABLE"
expect_failure "non-root-owned privileged destination" "System install destination is not root-owned" \
    privileged_check "$PRIV_BIN/kubectl"

printf '%s 0 777\n' "$PRIV_ROOT" > "$STAT_TABLE"
expect_failure "unsafe nearest existing privileged parent" \
    "Group/world-writable install parent: $PRIV_ROOT" \
    privileged_check "$PRIV_ROOT/missing/bin/kubectl"

: > "$STAT_TABLE"
ln -s "$PRIV_BIN" "$FIXTURE_DIR/privileged-link"
expect_failure "symlinked privileged parent" "Symlinked install parent" \
    privileged_check "$FIXTURE_DIR/privileged-link/kubectl"
rm "$PRIV_BIN/kubectl"
ln -s "$FIXTURE_ARTIFACT" "$PRIV_BIN/kubectl"
expect_failure "symlinked privileged destination" "Symlinked install destination" \
    privileged_check "$PRIV_BIN/kubectl"

# The default destination applies the privileged contract before download.
# Every stat result is unsafe, so the first checked path fails whether or not
# the host has /usr/local/bin/kubectl.
: > "$CURL_LOG"
expect_failure "default /usr/local/bin destination with unsafe parents" \
    "Group/world-writable install parent" \
    env FIXTURE_STAT_DEFAULT="0 777" PATH="$MOCK_BIN:$PATH" "$INSTALLER" kubectl
[[ ! -s "$CURL_LOG" ]] || fail "unsafe privileged path reached download"
[[ ! -s "$SUDO_LOG" ]] || fail "fixtures invoked sudo"

# --- Effective PATH selection after installation (setup's final check) ------

SHADOW_DIR="$FIXTURE_DIR/shadow"
EMPTY_DIR="$FIXTURE_DIR/empty"
mkdir -p "$SHADOW_DIR" "$EMPTY_DIR"
write_stub "$UNTOUCHED_DIR/kubectl" "Client Version: $PHASE7_KUBECTL_VERSION"
write_stub "$SHADOW_DIR/kubectl" "Client Version: v1.0.0"

raw="$(PATH="$UNTOUCHED_DIR:$LATER_DIR:$UTIL_BIN" \
    phase7_verify_effective_tool_version kubectl "$UNTOUCHED_DIR/kubectl")" \
    || fail "effective-version check rejected the installed pin ahead of a later PATH entry"
[[ "$raw" == "Client Version: $PHASE7_KUBECTL_VERSION" ]] || fail "unexpected effective version: $raw"
pass "effective-version check accepts the installed pin ahead of a later PATH executable"

SHADOW_OUT="$FIXTURE_DIR/shadow.out"
if PATH="$SHADOW_DIR:$UNTOUCHED_DIR:$UTIL_BIN" \
    phase7_verify_effective_tool_version kubectl "$UNTOUCHED_DIR/kubectl" >/dev/null 2>"$SHADOW_OUT"; then
    fail "shadowing kubectl passed the effective-version check"
fi
for line in \
    "Installed destination: $UNTOUCHED_DIR/kubectl" \
    "Resolved executable: $SHADOW_DIR/kubectl" \
    "Expected version: $PHASE7_KUBECTL_VERSION" \
    "Detected version: Client Version: v1.0.0" \
    "An earlier PATH entry shadows $UNTOUCHED_DIR/kubectl"; do
    grep -Fq -- "$line" "$SHADOW_OUT" || fail "shadow diagnostic is missing '$line'"
done
pass "shadowing executable fails setup's exact-version check with an actionable diagnostic"

write_stub "$SHADOW_DIR/helm" "$PHASE7_HELM_VERSION" 1
if PATH="$SHADOW_DIR:$UTIL_BIN" \
    phase7_verify_effective_tool_version helm "$SHADOW_DIR/helm" >/dev/null 2>"$SHADOW_OUT"; then
    fail "failing Helm probe passed the effective-version check"
fi
grep -Fq "Detected version: unknown (version probe failed)" "$SHADOW_OUT" \
    || fail "failed Helm probe was not reported"
pass "failed Helm probe fails setup's exact-version check"

if PATH="$EMPTY_DIR:$UTIL_BIN" \
    phase7_verify_effective_tool_version kubectl "$UNTOUCHED_DIR/kubectl" >/dev/null 2>"$SHADOW_OUT"; then
    fail "missing kubectl passed the effective-version check"
fi
grep -Fq "kubectl is not on PATH" "$SHADOW_OUT" || fail "missing kubectl was not reported"
pass "missing executable fails setup's exact-version check"
hash -r

printf 'Platform-tool safeguard fixtures passed: %s checks.\n' "$pass_count"
