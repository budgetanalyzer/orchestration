# Decoupling Review Remediation Plan

Address all 15 actionable findings from the two decoupling reviews, including
the cleanup previously considered deferrable. Preserve independent orchestration
and workspace operation. Prove bundle-only trust with real OpenSSL fixtures
and keep remediation limited to the accepted review findings.

The discussion sources are `tmp/decoupling-review-1.md`,
`tmp/decoupling-review-2.md`, `tmp/decoupling.review-3.md`, and
`tmp/decoupling-review-4.md`. Review 4's reductions are accepted and control
where the earlier reviews differ. Those ignored files are optional background;
this plan contains the decisions and required outcomes needed to execute
without them.

**Accepted decisions**

- Installing a repository pin explicitly permits upgrading or downgrading a
  recognized existing destination binary. Remove downgrade refusal; do not add
  an opt-in flag or another confirmation. Print the old version, pinned
  replacement and destination before replacing a recognized binary.
- Keep full ownership, mode and ancestor checks for `/usr/local/bin` only.
  Custom installs run without sudo: create the directory with `mkdir -p`,
  reject an existing destination that is a symlink or not a regular file,
  then install verified bytes. Rely on normal filesystem permissions for
  write authority, including group-writable paths and symlinked ancestors.
- Protect the destination being written. Diagnose the caller's effective PATH
  separately; do not police untouched executables as installation destinations.
- Keep checksums and narrow required-member archive checks; remove unrelated
  archive-wide restrictions and duplicated extraction branches.
- Keep behavioral tests for removed options and the useful setup source-order
  check, accurately described as an ordering check. Do not add a stubbed run
  of the entire setup script.
- Move release verification into its own workflow using built-in event path
  filters and manual dispatch; keep offline setup checks independent.
- Prove bundle-only trust with real, long-lived public certificate fixtures
  supplied by the human before execution. No verification-time override or
  OpenSSL version-detection framework is needed.
- Workspace's existing human-run browser acceptance procedure remains its
  own responsibility. Browser-probe extraction, controller tests and live
  browser acceptance are outside this remediation plan's completion gates.

These decisions supersede the downgrade-refusal recommendation in review 3
and the corresponding orchestration installer requirements in the
[original decoupling plan](workspace-orchestration-decoupling.md). They do not
change workspace's installation policy for its remaining native tools.

**Coverage**

| Finding | Required outcome | Phase |
| --- | --- | --- |
| R1.1: cache paths and nested mkdir | Supported custom installs under umask `0002` | 1 |
| R1.2: newer installed version | Verified downgrade to the pin succeeds | 1 |
| R1.3: unrelated PATH tools | Destination safety and command selection separated | 1 |
| R1.4: host kubectl fixture dependency | Fully controlled destination fixtures | 1 |
| R1.5: mocked certificate claims | Real OpenSSL chain and hostname fixtures | 4 |
| R1.6: source-text assertions | Behavior evidence and accurate coverage descriptions | 1, 2, 3, 4 |
| R1.7: unknown-option coverage | Rejection before runtime inspection | 3 |
| R1.8: archive overvalidation | One regular required member, verified bytes, stdout extraction | 2 |
| R1.9: downloads on every PR | Relevant-change gating with manual execution retained | 2 |
| R1.10: duplicated version probing | One library implementation with deliberate error handling | 1 |
| R1.11: repeated installer branches | One download/verify path and two extraction modes | 2 |
| R1 minor: VM wording | Environment-neutral bootstrap messages | 3 |
| R1 minor: ambiguous trust prerequisite | Browser-machine versus Kind-machine trust distinguished | 4, 5 |
| R1 minor: Kind provider mismatch | Docker provider contract enforced before Kind operations | 3 |
| R2: implicit alternate trust sources | Explicit bundle cannot borrow trust from default directories/stores | 4 |

**Execution boundaries**

Use the [AI Session Handler format](../../../ai-session-handler/docs/plan-format.md).
All phases execute in orchestration; no workspace implementation is included.
Update the nearest owner documentation with each behavior change.
Update `docs/OWNERSHIP.md` first if
an ownership description changes. Apply the AGENTS authoring standard if
repository instructions need changes.

No Git writes, certificate/key generation, live trust installation, privileged
tool installation, destructive bootstrap, or cluster mutation is required for
agent execution of this plan. Do not access the personal host, staging, or
production. Existing human-only setup and trust repair remain human-only.
Run the documented workspace boundary check before agent work in that VM.

Every changed shell script must pass `bash -n` and ShellCheck without
unjustified suppressions. Changed workflows must pass actionlint. Use only
approved Actions sources; no new external action is needed for path filtering.
Do not change pins, weaken TLS verification, or import browser cookies.

**Prerequisites and evidence**

Complete both human pre-steps before launching Phase 1; they are execution
prerequisites, not blockers for updating this plan:

1. Confirm the effective branch-protection/ruleset required checks allow the
   release step to leave `test-setup.yml`. Keep required offline status names
   intact and ensure the new path-filtered release workflow is not required
   on unrelated PRs. Record the confirmation; branch protection has not been
   inspected by these reviews. Any required settings change remains human-owned.
2. Supply three test-only public certificates: a root, a leaf covering
   `*.budgetanalyzer.localhost`, and an unrelated root, each valid for about
   100 years. Run the following single command on the personal host from an
   orchestration checkout with OpenSSL. It creates a new fixture directory,
   keeps keys in a temporary directory, and discards those keys on exit.
   Agents must not run this command.

```bash
bash <<'BASH'
set -euo pipefail
umask 077
fixture_dir=tests/tilt-prerequisites/fixtures/client-trust
fixture_tmp=$(mktemp -d)
trap 'rm -rf -- "$fixture_tmp"' EXIT
mkdir -p "$(dirname "$fixture_dir")"
mkdir "$fixture_dir"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
  -subj '/CN=Budget Analyzer Test Root' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$fixture_tmp/root.key" -out "$fixture_tmp/root.pem"
openssl req -new -newkey rsa:2048 -nodes -sha256 \
  -subj '/CN=*.budgetanalyzer.localhost' \
  -keyout "$fixture_tmp/leaf.key" -out "$fixture_tmp/leaf.csr"
cat > "$fixture_tmp/leaf.ext" <<'EXT'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:*.budgetanalyzer.localhost
EXT
openssl x509 -req -sha256 -days 36500 -set_serial 2 \
  -in "$fixture_tmp/leaf.csr" -CA "$fixture_tmp/root.pem" \
  -CAkey "$fixture_tmp/root.key" -extfile "$fixture_tmp/leaf.ext" \
  -out "$fixture_tmp/leaf.pem"
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
  -subj '/CN=Budget Analyzer Unrelated Test Root' \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,keyCertSign,cRLSign' \
  -keyout "$fixture_tmp/unrelated-root.key" \
  -out "$fixture_tmp/unrelated-root.pem"
install -m 0644 "$fixture_tmp/root.pem" "$fixture_tmp/leaf.pem" \
  "$fixture_tmp/unrelated-root.pem" "$fixture_dir/"
BASH
```

The human transfers only the three public PEM files into the same relative
fixture directory in the execution checkout and owns committing them. Record
their human-generated test-only provenance and validity dates with the fixtures
in Phase 4. Never transfer private keys, use the live development CA, or install
these test roots into system/NSS trust. Tests use current-time verification;
long validity removes the need for `-attime` plumbing. The existing workspace
browser acceptance check is not required to execute or complete this plan.

## Phase 1: Correct Installer Authority And Allow Pinned Downgrades

### Workspace

.

### Goal

Make verified installation work for the supported cache layout and converge to
the exact repository pin regardless of the installed version's ordering.

### Scope

`scripts/bootstrap/install-verified-tool.sh`, its small repository-local
helpers, `scripts/lib/pinned-tool-versions.sh`, version-probe callers in
`setup.sh` and `scripts/bootstrap/check-tilt-prerequisites.sh`,
`tests/platform-tools/`, and corresponding owner documentation.

### Non-goals

System installation during validation, new tool managers, relaxing privileged
path checks, or changing workspace's native installer.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`, `scripts/README.md#bootstrap`.
- `docs/dependency-automation.md`.
- Installer, pin library, setup, prerequisite checker, and platform-tool tests.
- Original decoupling plan's Phase 2, interpreted with this plan's overrides.

### Execution steps

1. Define two destination contracts. Keep root ownership, no group/world
   writes, and symlink/collision protection for `/usr/local/bin` and its
   ancestors. Custom installation runs without sudo and uses `mkdir -p`,
   rejects an existing destination binary that is a symlink or not a regular
   file, then uses `install`. Do not apply ownership, mode, ancestor or
   nearest-existing-parent checks to custom paths, or recheck their safety
   before the final write. Symlinked home/worktree/temporary-directory
   ancestors are supported; normal filesystem permissions govern writes.
2. Let `mkdir -p` create missing custom directories under the invoking umask.
   Do not chmod existing workspace paths or add custom mode management.
   Preserve checksum verification before installing any binary.
3. Remove version-order refusal for a recognized destination binary. Replace
   newer and older recognized versions with the verified pin. Preserve
   rejection of unidentifiable contents and destination symlinks, plus the
   privileged destination protections. Print the replacement before writing,
   for example `Replacing helm X with pinned Y at /usr/local/bin/helm`.
   Retain the final safety recheck only for privileged installation.
4. Remove `check_resolved_system_tool_for_downgrade`. Keep effective-version
   validation in setup, including `hash -r`, and make mismatch diagnostics
   report the installed destination, resolved executable, expected version,
   and detected version. Do not mutate an unrelated PATH entry.
5. Consolidate platform-tool probing and normalization into the existing
   library. Remove setup's dead mkcert probe and unused version-order helper
   if no callers remain. Deliberately handle probe failure, stderr and
   `set -e`; keep Java/Node/npm policy checks separate.
6. Make destination validation directly testable with disposable paths using
   the smallest practical local helper extraction. Eliminate the fixture's
   dependency on whether `/usr/local/bin/kubectl` exists. Test relevant setup
   and prerequisite version behavior through shared callable logic and
   controlled command stubs, not only helper-name greps.
7. Update `scripts/README.md` for the new install and downgrade contract,
   then summaries. Add a short supersession pointer to the original plan's
   obsolete installer policy; do not rewrite historical review documents.
   Do not edit this active execution plan during a runner invocation.

### Implementation notes

Unprivileged installation relies on kernel-enforced write permissions; it does
not promise isolation from other directory writers. Keep the privileged write
contract distinct. Do not add generalized permission-policy configuration or
a test-only CLI switch that bypasses production checks.

### Validation

- Run `tests/platform-tools/test-platform-tool-safeguards.sh` under umasks
  `0022` and `0002`, with all artifacts and executables supplied by fixtures.
- Cover a mode-775 user-owned parent, multiple missing directories, old and
  newer recognized versions and their replacement messages, corrupt downloads,
  destination symlink/non-regular-file rejection, and successful custom
  installs through symlinked ancestors. Keep ownership/mode rejection cases
  scoped to privileged parent/destination fixtures.
- Cover absent and present fixture destinations independently of host kubectl,
  a later untouched PATH executable, and a shadowing executable that causes
  setup's final exact-version check to fail with an actionable diagnostic.
- Prove exact Helm enforcement through behavior, including failed probes.
- Run shell syntax and ShellCheck for changed scripts and fixture helpers.

### Completion criteria

Fixture installations upgrade and downgrade to the pin and work under the
actual cache permission pattern. Unsafe privileged writes remain rejected.
Tests require no host platform binary or privileged mutation, and
documentation no longer promises downgrade refusal.

## Phase 2: Simplify Artifact Handling And Scope Release Downloads

### Workspace

.

### Goal

Keep release verification meaningful while reducing duplicated installer code
and network work on unrelated changes.

### Scope

Installer extraction, `phase7_validate_tool_artifact`, release verification,
platform-tool fixtures, `.github/workflows/test-setup.yml`, a new
`.github/workflows/verify-platform-tool-releases.yml`, and owner docs.

### Non-goals

Changing release inputs, introducing a generic archive-security framework,
or changing required organization Actions policy.

### Required context

- Phase 1 implementation and tests.
- `scripts/lib/pinned-tool-versions.sh`.
- `scripts/bootstrap/verify-platform-tool-releases.sh`.
- `.github/workflows/test-setup.yml`.
- `scripts/README.md`, `docs/dependency-automation.md`, `docs/ci-cd.md`.

### Execution steps

1. Download and verify once. Use explicit supported-tool metadata to select
   raw binary copy or exact-member stdout extraction. An unsupported tool or
   metadata error must not silently become a raw-binary install.
2. Keep digest verification and require exactly one regular-file entry for
   the selected archive member. Remove restrictions on unrelated archive
   names and entry types that are never extracted to the filesystem.
3. Add one duplicate-member fixture proving that two matching entries cannot
   be concatenated into an installed binary by `tar -xO`. Retain normal
   successful extraction and checksum-failure coverage; do not add a broad
   matrix of synthetic archive layouts.
   Remove URL/version assertions if they merely repeat the constructor;
   identify any retained checks as metadata checks.
4. Keep offline setup checks in `test-setup.yml` running for PRs. Move the
   network release-verification step into the new dedicated workflow, with
   `paths:` filters on both `pull_request` and `push`, plus `workflow_dispatch`.
   Preserve the existing target branch restrictions. Both path filters cover:

   - `scripts/lib/pinned-tool-versions.sh`
   - `scripts/bootstrap/install-verified-tool.sh`
   - `scripts/bootstrap/verify-platform-tool-releases.sh`
   - `.github/workflows/verify-platform-tool-releases.yml`

5. Use GitHub's built-in event filtering only. Do not implement Git diff
   selection, missing-baseline handling or tests of that selection logic.
   Preserve required offline status names under the human-confirmed policy
   from the pre-steps. Carry over the repository's existing action pins and
   workflow-scope Node 24 setting.
6. Update operational and dependency-automation documentation to describe
   precisely which changes require all eight Linux artifacts to be verified.

### Implementation notes

The separate workflow makes release downloads conditional without withholding
offline setup checks on unrelated PRs. The human confirms required-check
compatibility before execution; agents do not access GitHub credentials or
change branch protection.

### Validation

- Run platform-tool fixtures and syntax/ShellCheck for changed scripts.
- Inspect both event path lists and manual dispatch against the four inputs
  above; confirm the release step is absent from the offline setup workflow.
- Run actionlint on both changed workflow files.
- Run `scripts/bootstrap/verify-platform-tool-releases.sh` once after changes
  to its extraction contract, validating all eight amd64/arm64 inputs without
  executing or installing downloaded binaries. Report network failure as
  incomplete evidence, not a passing gate.

### Completion criteria

Archive correctness checks survive the simplification. Unrelated PRs retain
offline checks without downloading releases; relevant changes and manual runs
still verify both Linux architectures.

## Phase 3: Enforce The Kind Provider And Test Runtime Interfaces

### Workspace

.

### Goal

Ensure the Docker endpoint guard describes the backend Kind will use and make
runtime interface coverage match its documentation.

### Scope

`scripts/lib/local-kubernetes-target.sh`, setup and local-runtime callers,
`tests/local-runtime/`, relevant prerequisite tests, and bootstrap messaging.

### Non-goals

Supporting additional Kind backends, relaxing exact Kubernetes authority,
or recreating the cluster during validation.

### Required context

- `docs/architecture/autonomous-ai-execution.md`.
- `docs/development/getting-started.md`, `scripts/README.md`.
- Shared local-target helper, setup, daily wrapper and prerequisite checker.
- Existing local-runtime and local-Kubernetes-target fixtures.

### Execution steps

1. Add the rejection of a nonempty `KIND_EXPERIMENTAL_PROVIDER` other than
   `docker` directly to `assert_local_docker_endpoint`. Its existing setup,
   daily-check and prerequisite callers inherit the guard; do not duplicate
   it in each caller. Keep unset/default-Docker behavior and existing checks.
2. Add fixtures for unset, `docker`, alternate and invalid provider values.
   Show provider rejection occurs before Kind inspection or mutation.
3. Add an unknown-option runtime fixture asserting nonzero exit, useful
   diagnostics and empty Docker/Kind/kubectl logs. Retain removed-option tests
   for other entry points.
4. Retain the existing setup source-order check and describe it accurately
   as an ordering check. Do not add a stubbed execution of the whole setup
   script or claim the ordering check proves every runtime mutation path.
5. Keep prerequisites useful before a cluster exists, while requiring the
   exact target before cluster-specific checks. Cover absent and wrong-target
   cases without accessing a real cluster.
6. Rename VM-specific setup messaging/helper names where they imply a VM is
   mandatory. Preserve the intentional container guard. Update the script
   catalog and runtime owner docs to match actual behavior and coverage.

### Implementation notes

A Docker transport check is not host-isolation proof. Do not move workspace
VM policy into this helper, or make the small daily wrapper a full diagnostic
framework.

### Validation

- Run local-runtime and local-Kubernetes-target offline suites.
- Retain the setup ordering check and existing prerequisite fixtures.
- Run syntax and ShellCheck for changed shell files.
- Confirm all rejection fixtures use stubs and leave the real cluster intact.

### Completion criteria

Kind provider mismatches fail before Kind access, command-line rejection
coverage exists, the setup ordering check is accurately described, and setup
text matches its environment-independent role.

## Phase 4: Prove Bundle-Only Certificate Trust

### Workspace

.

### Goal

Fix the false-positive system-bundle check and replace mock-only certificate
claims with real chain and hostname verification.

### Scope

`scripts/lib/local-ingress-client-trust.sh`,
`tests/tilt-prerequisites/test-client-trust.sh`, public test fixtures,
prerequisite wiring tests, and TLS owner documentation.

### Non-goals

Certificate generation, trust-store installation, a local test CA service,
browser acceptance claims from OpenSSL, or a workspace dependency.

### Required context

- `docs/OWNERSHIP.md`, `docs/development/local-environment.md`.
- `docs/development/getting-started.md`.
- `docs/architecture/autonomous-ai-execution.md`.
- Client-trust helper, prerequisite caller and imported-TLS fixtures.
- This plan's public-fixture prerequisite.

### Execution steps

1. Use the three public fixture certificates supplied in the human pre-step.
   Document provenance and validity dates alongside them; fixtures are ready
   before plan execution, not generated or requested midway through Phase 4.
2. Add `-no-CApath -no-CAstore` to explicit-bundle verification. Surface
   OpenSSL's stderr so unsupported options or verification errors are
   diagnosable. Older implementations that reject an option already fail
   closed; do not add version probing, option detection or fallback handling.
3. Exercise the actual helper with a valid matching root/leaf bundle, a wrong
   hostname, an unrelated nonempty root bundle, and a valid root available
   only through `SSL_CERT_DIR`. Demonstrate the last case is rejected even
   though an unrestricted OpenSSL invocation can verify it.
4. Retain useful missing-tool/file and error-propagation cases. Replace the
   claim that mocked empty files constitute valid certificates. Exercise the
   prerequisite caller's trust-failure reporting with controlled dependencies
   rather than relying only on source greps.
5. Update TLS owner docs first, then bootstrap/architecture summaries.
   Distinguish browser-machine certificate preparation, Kind-machine
   system-bundle verification, NSS store diagnosis, and the live browser
   check. Clarify that local client-trust installation does not gate
   destructive bootstrap, while browser-machine trust remains required for
   browser use.

### Implementation notes

Fixtures must run on a clean CI machine without a workspace checkout, live
ingress or developer CA. Temporary hashed directories and bundles are test
inputs, not changes to system/NSS trust. Live-certificate diagnostics alone
are insufficient completion evidence for the portable regression suite.

### Validation

- Run real-OpenSSL client-trust fixtures and imported-ingress-TLS fixtures.
- Run controlled prerequisite integration tests and shell checks.
- Verify the alternate-trust regression fails against the old helper and
  passes against the corrected helper without modifying live trust.
- Inspect fixture contents to confirm no private keys and document validity
  and provenance.

### Completion criteria

The selected bundle is the only trust source. Real certificates prove chain,
hostname and alternate-source behavior in portable offline tests. Documents
accurately separate system-bundle verification from browser acceptance.

## Phase 5: Reconcile Documentation And Supersession Pointers

### Workspace

.

### Goal

Keep owner documents, summaries and the original plan's supersession pointers
consistent with the completed review remediation.

### Scope

Orchestration documentation cross-links, coverage descriptions and the
original decoupling plan's supersession pointers.

### Non-goals

New implementation work, workspace changes, historical ADR/archive edits,
repeating phase validation without a new reason, or live browser acceptance.

### Required context

- `docs/OWNERSHIP.md`, `scripts/README.md`.
- `docs/development/getting-started.md`, `docs/development/local-environment.md`.
- `docs/architecture/autonomous-ai-execution.md`.
- `docs/dependency-automation.md`, `docs/ci-cd.md`.
- `docs/plans/workspace-orchestration-decoupling.md` and prior phase results.

### Execution steps

1. Reconcile cross-links and summaries with the owner documentation updated
   in Phases 1–4. Describe source-order checks as structural evidence and
   real-OpenSSL tests as chain, hostname and bundle-only verification.
2. Confirm the original plan's obsolete installer requirements point to this
   remediation, including pinned downgrades and the simpler custom-directory
   contract. Preserve historical review documents and decision records.
3. Keep links to workspace's existing human-run browser acceptance procedure
   where relevant. Distinguish browser-machine trust from Kind-machine
   system-bundle verification without introducing a new browser procedure
   or an executable workspace dependency.
4. Reconcile the coverage table with prior phase results and report the
   existing offline and release-verification evidence accurately. Do not
   edit this active execution plan during a runner invocation or introduce
   a final repeat of the phase test suites.

### Implementation notes

Owner documents were updated with each behavior change. This checkpoint
finishes documentation reconciliation; it does not add another integration
or live-validation gate. Reuse the evidence recorded by Phases 1–4.

### Validation

- Check affected relative links and anchors, including supersession pointers.
- Read the affected summaries against their canonical owners and the coverage
  table; remove stale downgrade-refusal, custom-path permission-audit or
  unconditional release-download claims.
- Confirm documentation does not claim a new browser probe, browser test
  result or workspace implementation as part of this remediation.

### Completion criteria

All review findings have a documented disposition backed by the focused
validation in Phases 1–4. Owner documents, summaries and supersession pointers
agree, links resolve, and completion does not depend on live browser acceptance.
