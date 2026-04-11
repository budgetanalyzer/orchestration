# Scripts Directory Reorganization: Smoketest And Guardrails Split Plan

Date: 2026-04-11

## Goal

Reorganize `scripts/` around purpose instead of "dev vs not dev", and introduce
a single local entry point for live-cluster validation.

After this work:

1. A new `scripts/smoketest/smoketest.sh` runs the full live-cluster validation
   in one command by dispatching to the existing verify/audit scripts.
2. `scripts/dev/` is gone. Every script in it is moved into a purpose-specific
   sibling of `scripts/`: `bootstrap/`, `ops/`, `guardrails/`, `smoketest/`, or
   `loadtest/`.
3. Release/repo-management scripts currently at top-level `scripts/` move into
   `scripts/repo/`.
4. The static CI gates (`verify-phase-7-static-manifests.sh`,
   `check-phase-7-image-pinning.sh`, `check-secrets-only-handling.sh`) live
   under `scripts/guardrails/` and remain CI-safe. CI workflow file is updated
   to the new paths but continues to call the static guardrails directly; it
   never invokes the smoketest umbrella.
5. The two currently-unwired verifiers are wired into the smoketest:
   `verify-monitoring-runtime.sh` and `verify-session-architecture-phase-5.sh`.
   The session-architecture one is the most likely to be broken; the refactor
   explicitly exercises it as the first real-world check.
6. The cluster-required rendered monitoring verifier
   (`verify-monitoring-rendered-manifests.sh`) moves with the smoketest scripts,
   not the static guardrails, because it performs server-side Kubernetes
   dry-runs against a live API server.
7. `scripts/README.md` is rewritten to match reality. It currently references
   two scripts (`validate-claude-context.sh`, `doc-coverage-report.sh`) that do
   not exist.
8. All references from `setup.sh`, `Tiltfile`, `.github/workflows/`, `tests/`,
   `docs/`, inter-script `${SCRIPT_DIR}/...` calls, and the Phase 7 image
   pinning target list are updated to the new paths.

## Non-Goals

- Do NOT rename phase-named scripts. `verify-phase-*`,
  `audit-phase-6-session-3-frontend-csp.sh`, and
  `verify-phase-6-session-7-api-rate-limit-identity.sh` keep their current
  filenames. Only their containing directory moves. Phase renames are a
  separate follow-up; the noise from combining the two changes is too high.
- Do NOT rewrite verify script internals. The only edits inside existing
  scripts are path updates: `${SCRIPT_DIR}/lib/foo.sh` becomes
  `${SCRIPT_DIR}/../lib/foo.sh`, and the umbrella
  `verify-phase-7-security-guardrails.sh` adjusts its `STATIC_GATE=` path to
  cross into `guardrails/`. The one non-verify exception is the repo-management
  move: `repo-config.sh` and `generate-unified-api-docs.sh` must adjust repo-root
  derivation because they move one directory deeper.
- Do NOT introduce new verification logic. Wiring
  `verify-monitoring-runtime.sh`, `verify-monitoring-rendered-manifests.sh`,
  and `verify-session-architecture-phase-5.sh` into the smoketest does not
  modify their checks.
- Do NOT add a `--skip-runtime` or `--ci` flag to `smoketest.sh`. CI continues
  to call `guardrails/verify-phase-7-static-manifests.sh` directly. The
  smoketest umbrella is local-only.
- Do NOT add `smoketest.sh` to any GitHub Actions workflow in this change.
- Do NOT delete `verify-session-architecture-phase-5.sh` even though it
  currently has zero callers. Keep it and wire it in. If the live run after
  the refactor shows it is broken, fix or delete as a follow-up.
- Do NOT re-home `tests/setup-flow/` or `tests/security-preflight/`.
  `AGENTS.md` already flags those as stale, non-gating Phase 7 assets. They
  continue to reference `scripts/` by path; we only update those references,
  not their status.
- Do NOT cross-reference deleted or landed plan files to decide what is cruft.
  Plans are ephemeral in this repo.

## Current State

- `scripts/` top level mixes repo/release management
  (`checkout-main.sh`, `checkout-tag.sh`, `repo-config.sh`, `tag-release.sh`,
  `validate-repos.sh`, `github/add-repo-topics.sh`) with one cluster-runtime
  script (`generate-unified-api-docs.sh`).
- `scripts/README.md` documents `validate-claude-context.sh` and
  `doc-coverage-report.sh`. Neither file exists.
- `scripts/dev/` contains 30 scripts plus a `lib/` directory. The contents
  fall into five clean groups that currently live together:
  - **Host bootstrap**: `install-verified-tool.sh`, `install-calico.sh`,
    `setup-k8s-tls.sh`, `setup-infra-tls.sh`, `check-tilt-prerequisites.sh`.
  - **Interactive cluster ops**: `flush-redis.sh`, `redis-browse.sh`,
    `reset-databases.sh`, `render-istio-egress-config.sh`,
    `seed-ext-authz-session.sh`.
  - **Static guardrails** (no cluster required):
    `verify-phase-7-static-manifests.sh`, `check-phase-7-image-pinning.sh`,
    `check-secrets-only-handling.sh`.
  - **Live-cluster verify/audit**:
    `verify-security-prereqs.sh`, `verify-phase-1-credentials.sh`,
    `verify-phase-2-network-policies.sh`, `verify-phase-3-istio-ingress.sh`,
    `verify-phase-4-transport-encryption.sh`,
    `verify-phase-5-runtime-hardening.sh`,
    `verify-monitoring-rendered-manifests.sh`,
    `verify-session-architecture-phase-5.sh`,
    `audit-phase-6-session-3-frontend-csp.sh`,
    `verify-phase-6-session-7-api-rate-limit-identity.sh`,
    `verify-phase-6-edge-browser-hardening.sh`,
    `verify-phase-7-runtime-guardrails.sh`,
    `verify-phase-7-security-guardrails.sh`,
    `verify-clean-tilt-deployment-admission.sh`,
    `verify-monitoring-runtime.sh`.
  - **Loadtest**: `seed-loadtest-users.sh`, `seed-loadtest-transactions.sh`,
    `teardown-loadtest.sh`, `lib/loadtest-common.sh`.
- The `verify-phase-*` scripts form a cascade, not a redundant pile:
  `verify-phase-7-security-guardrails.sh` dispatches to
  `verify-phase-7-static-manifests.sh` and
  `verify-phase-7-runtime-guardrails.sh`; the runtime leg re-runs
  `verify-phase-6-edge-browser-hardening.sh`, which in turn re-runs
  `audit-phase-6-session-3-frontend-csp.sh`,
  `verify-phase-6-session-7-api-rate-limit-identity.sh`, and
  `verify-phase-5-runtime-hardening.sh`; phase 5 re-runs phases 1 through 4;
  phase 4 additionally re-runs phases 1 and 2. So
  `verify-phase-7-security-guardrails.sh` is already ~90 percent of a unified
  "verify this live cluster" entry point.
- `.github/workflows/security-guardrails.yml` calls
  `verify-phase-7-static-manifests.sh` directly, not the umbrella. The umbrella
  is documented as the local-only completion gate with CI kept intentionally
  static-only. There is no `--skip-runtime` flag; the pattern is simply to
  call the static script by path in CI.
- Two verify scripts currently have zero callers in the tree and are not
  referenced by Tiltfile, setup.sh, CI, or tests:
  - `verify-monitoring-runtime.sh` (brand new, Prometheus scrape + dashboard
    label check). Not known to be broken; simply never wired.
  - `verify-session-architecture-phase-5.sh` ("phase 5" here refers to the
    Session Architecture Rethink effort, not the same numbering as the
    security-hardening phases). Most likely script to be broken because it
    has been the most orphaned.
- `scripts/dev/lib/phase-7-image-pinning-targets.txt` hard-codes
  `scripts/dev/verify-*.sh` paths for eight scripts. Any directory move must
  update this file or `check-phase-7-image-pinning.sh` will fail.
- `scripts/dev/check-phase-7-image-pinning.sh` also contains a hard-coded
  error-message reference to `scripts/dev/lib/phase-7-allowed-latest.txt` in
  its help text that must be updated.

## Target Layout

```text
scripts/
├── README.md                              # rewritten
├── lib/                                   # shared across categories
│   ├── loadtest-common.sh
│   ├── phase-7-allowed-latest.txt
│   ├── phase-7-image-pinning-targets.txt
│   ├── pinned-tool-versions.sh
│   ├── redis-cli.sh
│   └── secrets-only-expected-keys.txt
├── repo/
│   ├── checkout-main.sh
│   ├── checkout-tag.sh
│   ├── generate-unified-api-docs.sh
│   ├── github/
│   │   └── add-repo-topics.sh
│   ├── repo-config.sh
│   ├── tag-release.sh
│   └── validate-repos.sh
├── bootstrap/
│   ├── check-tilt-prerequisites.sh
│   ├── install-calico.sh
│   ├── install-verified-tool.sh
│   ├── setup-infra-tls.sh
│   └── setup-k8s-tls.sh
├── ops/
│   ├── flush-redis.sh
│   ├── redis-browse.sh
│   ├── render-istio-egress-config.sh
│   ├── reset-databases.sh
│   └── seed-ext-authz-session.sh
├── guardrails/
│   ├── check-phase-7-image-pinning.sh
│   ├── check-secrets-only-handling.sh
│   └── verify-phase-7-static-manifests.sh
├── smoketest/
│   ├── smoketest.sh                       # NEW
│   ├── audit-phase-6-session-3-frontend-csp.sh
│   ├── verify-clean-tilt-deployment-admission.sh
│   ├── verify-monitoring-rendered-manifests.sh
│   ├── verify-monitoring-runtime.sh
│   ├── verify-phase-1-credentials.sh
│   ├── verify-phase-2-network-policies.sh
│   ├── verify-phase-3-istio-ingress.sh
│   ├── verify-phase-4-transport-encryption.sh
│   ├── verify-phase-5-runtime-hardening.sh
│   ├── verify-phase-6-edge-browser-hardening.sh
│   ├── verify-phase-6-session-7-api-rate-limit-identity.sh
│   ├── verify-phase-7-runtime-guardrails.sh
│   ├── verify-phase-7-security-guardrails.sh
│   ├── verify-security-prereqs.sh
│   └── verify-session-architecture-phase-5.sh
└── loadtest/
    ├── seed-loadtest-transactions.sh
    ├── seed-loadtest-users.sh
    └── teardown-loadtest.sh
```

All six shared `lib/` files hoist from `scripts/dev/lib/` to `scripts/lib/`.
Every script that sources them changes `${SCRIPT_DIR}/lib/foo.sh` to
`${SCRIPT_DIR}/../lib/foo.sh`. This is a deterministic, purely mechanical edit
that can be verified by search.

## Design Decisions

### Why split guardrails from smoketest

The two have different runtime environments. Guardrails run in CI without a
cluster. Smoketest requires a live `kubectl` context pointed at a Kind cluster
with Tilt resources rolled out. Putting them in one directory obscures which
scripts are CI-safe and which are not. The split also makes the CI workflow
diff reviewable: executable guardrail runs point at `scripts/guardrails/`, while
syntax-only checks may still reference `scripts/bootstrap/`, `scripts/ops/`, or
`scripts/lib/` when those scripts support the static gate.

### Why monitoring rendered validation is not a guardrail script

`verify-monitoring-rendered-manifests.sh` looks static because it renders Helm
manifests, but it also runs `kubectl apply --dry-run=server` and requires the
repo-managed `monitoring` namespace to exist. That makes it a live-cluster
validation script, not a CI-safe static guardrail. It moves to
`scripts/smoketest/` and remains wired from the Tilt monitoring resource.

### Why `scripts/smoketest/smoketest.sh` and not top-level

Top-level would be discoverable. Subdirectory keeps the umbrella and every
script it calls physically adjacent, which matches how the current `phase-7`
umbrella and its children live together. Discovery is handled by
`scripts/README.md` and by `AGENTS.md`.

### Why the umbrella stays in `smoketest/` despite calling into `guardrails/`

`verify-phase-7-security-guardrails.sh` already does this: it calls the static
gate first and the runtime gate second. Moving it into `guardrails/` would
mislabel it (it hits a live cluster), and splitting it would duplicate logic.
Its internal `STATIC_GATE=` path updates from
`scripts/dev/verify-phase-7-static-manifests.sh` to
`scripts/guardrails/verify-phase-7-static-manifests.sh`. That is the only
internal reference that crosses the boundary.

### Why `verify-session-architecture-phase-5.sh` gets wired in despite being suspect

Wiring it in and running the smoketest once is the fastest way to get a
signal. If it passes, it was never broken and belonged in the tree all along.
If it fails, the failure tells us exactly what drifted and the follow-up is
either fix-or-delete on a real basis, not on guesswork. The script already
has a `--static-only` flag, which gives us a graceful fallback if the live
checks are stale but the static checks still pass.

### Why `verify-monitoring-runtime.sh` gets wired in

Zero callers, but there is no evidence it is broken. The Tiltfile already
wires the rendered-manifests variant. Adding the runtime variant to the
smoketest closes the obvious gap and costs one line in `smoketest.sh`.

### Why not add `--skip-runtime` to `smoketest.sh`

CI already has the right pattern: call the static guardrail script by path,
never touch the umbrella. Adding a skip flag duplicates that pattern with a
weaker variant and invites CI to eventually depend on the umbrella in a way
that silently degrades to static-only. Keeping CI on the direct path forces
the static half to stay genuinely standalone, which is the property we want.

## Script Destination Map

| Current path | New path |
|---|---|
| `scripts/checkout-main.sh` | `scripts/repo/checkout-main.sh` |
| `scripts/checkout-tag.sh` | `scripts/repo/checkout-tag.sh` |
| `scripts/generate-unified-api-docs.sh` | `scripts/repo/generate-unified-api-docs.sh` |
| `scripts/github/add-repo-topics.sh` | `scripts/repo/github/add-repo-topics.sh` |
| `scripts/repo-config.sh` | `scripts/repo/repo-config.sh` |
| `scripts/tag-release.sh` | `scripts/repo/tag-release.sh` |
| `scripts/validate-repos.sh` | `scripts/repo/validate-repos.sh` |
| `scripts/dev/check-tilt-prerequisites.sh` | `scripts/bootstrap/check-tilt-prerequisites.sh` |
| `scripts/dev/install-calico.sh` | `scripts/bootstrap/install-calico.sh` |
| `scripts/dev/install-verified-tool.sh` | `scripts/bootstrap/install-verified-tool.sh` |
| `scripts/dev/setup-infra-tls.sh` | `scripts/bootstrap/setup-infra-tls.sh` |
| `scripts/dev/setup-k8s-tls.sh` | `scripts/bootstrap/setup-k8s-tls.sh` |
| `scripts/dev/flush-redis.sh` | `scripts/ops/flush-redis.sh` |
| `scripts/dev/redis-browse.sh` | `scripts/ops/redis-browse.sh` |
| `scripts/dev/render-istio-egress-config.sh` | `scripts/ops/render-istio-egress-config.sh` |
| `scripts/dev/reset-databases.sh` | `scripts/ops/reset-databases.sh` |
| `scripts/dev/seed-ext-authz-session.sh` | `scripts/ops/seed-ext-authz-session.sh` |
| `scripts/dev/check-phase-7-image-pinning.sh` | `scripts/guardrails/check-phase-7-image-pinning.sh` |
| `scripts/dev/check-secrets-only-handling.sh` | `scripts/guardrails/check-secrets-only-handling.sh` |
| `scripts/dev/verify-phase-7-static-manifests.sh` | `scripts/guardrails/verify-phase-7-static-manifests.sh` |
| `scripts/dev/audit-phase-6-session-3-frontend-csp.sh` | `scripts/smoketest/audit-phase-6-session-3-frontend-csp.sh` |
| `scripts/dev/verify-clean-tilt-deployment-admission.sh` | `scripts/smoketest/verify-clean-tilt-deployment-admission.sh` |
| `scripts/dev/verify-monitoring-rendered-manifests.sh` | `scripts/smoketest/verify-monitoring-rendered-manifests.sh` |
| `scripts/dev/verify-monitoring-runtime.sh` | `scripts/smoketest/verify-monitoring-runtime.sh` |
| `scripts/dev/verify-phase-1-credentials.sh` | `scripts/smoketest/verify-phase-1-credentials.sh` |
| `scripts/dev/verify-phase-2-network-policies.sh` | `scripts/smoketest/verify-phase-2-network-policies.sh` |
| `scripts/dev/verify-phase-3-istio-ingress.sh` | `scripts/smoketest/verify-phase-3-istio-ingress.sh` |
| `scripts/dev/verify-phase-4-transport-encryption.sh` | `scripts/smoketest/verify-phase-4-transport-encryption.sh` |
| `scripts/dev/verify-phase-5-runtime-hardening.sh` | `scripts/smoketest/verify-phase-5-runtime-hardening.sh` |
| `scripts/dev/verify-phase-6-edge-browser-hardening.sh` | `scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` |
| `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` | `scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh` |
| `scripts/dev/verify-phase-7-runtime-guardrails.sh` | `scripts/smoketest/verify-phase-7-runtime-guardrails.sh` |
| `scripts/dev/verify-phase-7-security-guardrails.sh` | `scripts/smoketest/verify-phase-7-security-guardrails.sh` |
| `scripts/dev/verify-security-prereqs.sh` | `scripts/smoketest/verify-security-prereqs.sh` |
| `scripts/dev/verify-session-architecture-phase-5.sh` | `scripts/smoketest/verify-session-architecture-phase-5.sh` |
| `scripts/dev/seed-loadtest-users.sh` | `scripts/loadtest/seed-loadtest-users.sh` |
| `scripts/dev/seed-loadtest-transactions.sh` | `scripts/loadtest/seed-loadtest-transactions.sh` |
| `scripts/dev/teardown-loadtest.sh` | `scripts/loadtest/teardown-loadtest.sh` |
| `scripts/dev/lib/loadtest-common.sh` | `scripts/lib/loadtest-common.sh` |
| `scripts/dev/lib/phase-7-allowed-latest.txt` | `scripts/lib/phase-7-allowed-latest.txt` |
| `scripts/dev/lib/phase-7-image-pinning-targets.txt` | `scripts/lib/phase-7-image-pinning-targets.txt` |
| `scripts/dev/lib/pinned-tool-versions.sh` | `scripts/lib/pinned-tool-versions.sh` |
| `scripts/dev/lib/redis-cli.sh` | `scripts/lib/redis-cli.sh` |
| `scripts/dev/lib/secrets-only-expected-keys.txt` | `scripts/lib/secrets-only-expected-keys.txt` |

`scripts/dev/` is removed after the moves complete.

## The New smoketest.sh

Thin dispatcher at `scripts/smoketest/smoketest.sh`. No business logic; no new
checks; no CI hooks. Calls existing scripts in dependency order so earlier
failures short-circuit later work. Exits non-zero on the first failing step.

Execution order:

1. `../guardrails/verify-phase-7-static-manifests.sh`
   - Fastest, no cluster needed. Catches file drift before spending time on
     runtime probes. Mirrors what CI runs.
2. `./verify-security-prereqs.sh`
   - Phase 0 runtime baseline (NetworkPolicy, PSA, Istio readiness, Kyverno
     smoke policy).
3. `./verify-clean-tilt-deployment-admission.sh`
   - Confirms the seven default-namespace deployments are rolled out and
     admission is not blocking on image digests.
4. `./verify-monitoring-rendered-manifests.sh`
   - Re-renders the monitoring Helm chart, checks digest pinning and pod-shape
     constraints, and server-dry-runs the rendered workload objects.
5. `./verify-monitoring-runtime.sh`
   - Prometheus scrape and Grafana dashboard label check for the four Spring
     Boot services.
6. `./verify-session-architecture-phase-5.sh`
   - Session Architecture Rethink Phase 5 contract. Run before the phase-7
     umbrella so an architectural mismatch surfaces early with a clear name.
7. `./verify-phase-7-security-guardrails.sh`
   - Umbrella that cascades through phase 7 runtime, phase 6 edge, phase 6
     session 7, phase 6 session 3 audit, phase 5 runtime hardening, and phases
     1 through 4 as regression coverage. This is ~90 percent of the work.

Pass-through flags to keep contributors happy without adding skip logic:

- `--help` prints usage and the step list.
- `--runtime-wait-timeout <dur>` and `--runtime-regression-timeout <dur>`
  pass through to `verify-phase-7-security-guardrails.sh` unchanged.
- No `--skip-runtime`. No `--ci`. No `--phase-7-only`. If a contributor needs
  one specific step, they run it directly by path.

Failure behavior: `set -euo pipefail` at the top; each step runs under a
single header line so the output makes it obvious which step failed. No
aggregation, no "run everything and print summary" mode. First failure wins.

## Reference Updates Required

Every file below has at least one path that needs rewriting. This is
exhaustive as of the current repo state.

### `setup.sh`

- Lines 11 and 12: `pinned-tool-versions.sh` shellcheck/source path
- Line 63: `install-verified-tool.sh` path
- Line 175: advisory text for `check-tilt-prerequisites.sh`
- Line 215: `install-calico.sh` path
- Line 300: `setup-k8s-tls.sh` path
- Line 307: `setup-infra-tls.sh` path

### `Tiltfile`

- Lines 880, 891: `verify-monitoring-rendered-manifests.sh` path to
  `scripts/smoketest/`
- Line 965: `setup-k8s-tls.sh` path
- Lines 1074, 1076: `render-istio-egress-config.sh` path

### `.github/workflows/security-guardrails.yml`

- Lines 20 through 24: `bash -n` syntax checks for
  `check-phase-7-image-pinning.sh`, `install-verified-tool.sh`,
  `pinned-tool-versions.sh`, `render-istio-egress-config.sh`,
  `verify-phase-7-static-manifests.sh`
- Lines 27, 30: `verify-phase-7-static-manifests.sh` execution path
- Note: `install-verified-tool.sh` is in `bootstrap/` and
  `render-istio-egress-config.sh` is in `ops/`. CI still only syntax-checks
  those two without a cluster, which is fine; only the paths change.

### `scripts/repo/*` root calculation

Moving the repo-management scripts one directory deeper changes their path
assumptions. Update these explicitly:

- `scripts/repo/repo-config.sh`: `REPO_ROOT` must become the parent of
  `scripts/`, not the parent of `scripts/repo/`. Derive it with
  `$(cd "${SCRIPT_DIR}/../.." && pwd)` or equivalent, then keep
  `PARENT_DIR="$(dirname "$REPO_ROOT")"`.
- `scripts/repo/generate-unified-api-docs.sh`: `REPO_ROOT` must similarly point
  at the orchestration repo root, so `OUTPUT_DIR="$REPO_ROOT/docs-aggregator"`
  and sibling frontend output paths remain correct.
- `scripts/repo/tag-release.sh`: the nested call to
  `"${SCRIPT_DIR}/validate-repos.sh"` remains valid after the group move.

### `.github/workflows/test-setup.yml`

- Inspect and update any script paths it references during this refactor.

### Tests

- `tests/setup-flow/test-setup-flow.sh` line 178: `install-calico.sh` path
- `tests/security-preflight/test-security-preflight.sh` line 68:
  `install-calico.sh` path
- `tests/security-preflight/test-security-preflight.sh` line 136:
  `verify-security-prereqs.sh` path
- Leave the "stale, non-gating" status from `AGENTS.md` alone. We only update
  paths here.

### Inter-script `${SCRIPT_DIR}/...` references

- `scripts/smoketest/verify-phase-1-credentials.sh` line 555:
  `${SCRIPT_DIR}/seed-ext-authz-session.sh` becomes
  `${SCRIPT_DIR}/../ops/seed-ext-authz-session.sh`.
- `scripts/smoketest/verify-phase-3-istio-ingress.sh` lines 948 and 1225:
  same change as above.
- `scripts/smoketest/verify-phase-4-transport-encryption.sh` lines 695 and
  706: sibling references inside `smoketest/`, unchanged once the whole
  verify-phase-N-* set moves together.
- `scripts/smoketest/verify-phase-5-runtime-hardening.sh` lines 864 through
  867: sibling references inside `smoketest/`, unchanged.
- `scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` lines 929,
  933, 937: sibling references inside `smoketest/`, unchanged.
- `scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh`
  lines 318 and 344: `${SCRIPT_DIR}/seed-ext-authz-session.sh` becomes
  `${SCRIPT_DIR}/../ops/seed-ext-authz-session.sh`.
- `scripts/smoketest/verify-phase-7-runtime-guardrails.sh` line 1005:
  sibling reference inside `smoketest/`, unchanged.
- `scripts/smoketest/verify-phase-7-security-guardrails.sh` lines 9 and 10:
  `STATIC_GATE=` and `RUNTIME_GATE=` paths. Update `STATIC_GATE=` to
  `${REPO_DIR}/scripts/guardrails/verify-phase-7-static-manifests.sh`;
  `RUNTIME_GATE=` stays in `smoketest/`.
- `scripts/guardrails/verify-phase-7-static-manifests.sh` lines 12 and 13:
  `IMAGE_PINNING_SCRIPT=` and `SECRETS_ONLY_SCRIPT=` paths, both remain inside
  `guardrails/`, so the leading segment changes once.
- `scripts/guardrails/verify-phase-7-static-manifests.sh` line 83:
  `installer=` path points at `bootstrap/install-verified-tool.sh`.
- `scripts/guardrails/verify-phase-7-static-manifests.sh` line 39:
  `ACTIVE_GUIDANCE_PATHS` must stop pointing only at `scripts/dev` before that
  directory is deleted. The final list should cover the active moved script
  directories: `scripts/bootstrap`, `scripts/ops`, `scripts/guardrails`,
  `scripts/smoketest`, `scripts/loadtest`, `scripts/repo`, and `scripts/lib`.
- `scripts/bootstrap/check-tilt-prerequisites.sh` lines 279, 284, 389, 402:
  text and path references to `install-calico.sh`, `setup-infra-tls.sh`,
  `verify-security-prereqs.sh`.
- `scripts/bootstrap/setup-infra-tls.sh` lines 46 and 233: advisory text
  references.
- `scripts/bootstrap/setup-k8s-tls.sh` line 17: advisory text reference to
  `install-verified-tool.sh`.
- `scripts/loadtest/seed-loadtest-transactions.sh` line 99: advisory
  text points at `scripts/loadtest/seed-loadtest-users.sh`.

### Shared `lib/` sourcing

Every script that currently sources `${SCRIPT_DIR}/lib/foo.sh` now sources
`${SCRIPT_DIR}/../lib/foo.sh`. Affected files:

- `scripts/bootstrap/check-tilt-prerequisites.sh` (pinned-tool-versions.sh)
- `scripts/bootstrap/install-verified-tool.sh` (pinned-tool-versions.sh)
- `scripts/guardrails/check-phase-7-image-pinning.sh` (two `.txt` inventories)
- `scripts/guardrails/check-secrets-only-handling.sh` (secrets-only-expected-keys.txt)
- `scripts/guardrails/verify-phase-7-static-manifests.sh` (pinned-tool-versions.sh)
- `scripts/ops/flush-redis.sh` (redis-cli.sh)
- `scripts/ops/redis-browse.sh` (redis-cli.sh)
- `scripts/ops/seed-ext-authz-session.sh` (redis-cli.sh)
- `scripts/smoketest/verify-phase-1-credentials.sh` (redis-cli.sh)
- `scripts/loadtest/seed-loadtest-users.sh` (loadtest-common.sh)
- `scripts/loadtest/seed-loadtest-transactions.sh` (loadtest-common.sh)
- `scripts/loadtest/teardown-loadtest.sh` (loadtest-common.sh)

`setup.sh` is the exception because it is at repo root: its source path becomes
`${SCRIPT_DIR}/scripts/lib/pinned-tool-versions.sh`, and the shellcheck source
comment must match.

### `scripts/lib/phase-7-image-pinning-targets.txt`

Every entry currently reading `scripts/dev/verify-*.sh` becomes the
corresponding `scripts/smoketest/verify-*.sh` path. Eight lines.

### `scripts/guardrails/check-phase-7-image-pinning.sh`

- Line 13: `TARGET_LIST_FILE=` base path update to `../lib/`
- Line 14: `ALLOWED_LATEST_FILE=` base path update to `../lib/`
- Line 156: hard-coded error string
  `scripts/dev/lib/phase-7-allowed-latest.txt.` becomes `scripts/lib/...`.

### `scripts/lib/pinned-tool-versions.sh` line 225

- `installer_path="${repo_root%/}/scripts/dev/install-verified-tool.sh"`
  becomes `.../scripts/bootstrap/install-verified-tool.sh`.

### `scripts/README.md`

Full rewrite. The current version documents two nonexistent scripts and a
stale directory tree. Replace with:

- Directory-by-directory overview matching the target layout above
- Canonical entry points: `setup.sh` for bootstrap, `smoketest/smoketest.sh`
  for local validation, `guardrails/verify-phase-7-static-manifests.sh` for
  CI-safe manifest checks
- Path to the new umbrella and its execution order
- Notes about shared `lib/` helpers
- Removal of the "validate-claude-context.sh" and "doc-coverage-report.sh"
  sections

### Active `docs/` references to `scripts/dev/`

Every active `docs/*.md` file with a `scripts/dev/` or top-level `scripts/`
path needs a pass. Known active locations from the current grep:

- `docs/ci-cd.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/development/secrets-only-handling.md`
- `docs/development/database-setup.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/tilt-kind-setup-guide.md`
- `docs/architecture/observability.md`
- `docs/architecture/port-reference.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `docs/architecture/autonomous-ai-execution.md`
- `docs/dependency-notifications.md`
- `docs/research/single-instance-demo-hosting.md`
- `docs/setup/auth0-setup.md`

Do not update `docs/decisions/*` or `docs/archive/*`; `AGENTS.md` marks those
as historical and off-limits. Older, already-landed plan files under
`docs/plans/` may still contain the path names that were true when those plans
were written; do not use those historical plan references as current setup or
execution guidance.

These are prose updates only. No behavior changes.

### `AGENTS.md`

- Line 341 through 344: the Phase 7 Contract Freeze block mentions
  `scripts/dev/lib/phase-7-image-pinning-targets.txt` and
  `scripts/dev/lib/phase-7-allowed-latest.txt`. Update both to `scripts/lib/`.
- Any other script-path references encountered during the pass.

### `README.md` (repo root)

- Update any `scripts/dev/` or top-level-script references to match the new
  layout.

### `docs-aggregator/README.md`, `nginx/README.md`, `kubernetes/kyverno/README.md`, `tests/security-preflight/README.md`

- Prose updates only where they reference script paths.

### `kubernetes/istio/egress-routing.yaml` and `egress-service-entries.yaml`

- Contain script-path references in comments or generated-by headers. Update
  those strings.

### `.kube-linter.yaml`

- If it references any script path, update. Otherwise leave alone.

## Execution Order

Do the work in an order that keeps the repository runnable at every commit.

1. **Create target directories** under `scripts/` without deleting anything
   yet: `repo/`, `bootstrap/`, `ops/`, `guardrails/`, `smoketest/`,
   `loadtest/`, `lib/`.
2. **Move shared `lib/` files first** from `scripts/dev/lib/` to
   `scripts/lib/`. Update every `${SCRIPT_DIR}/lib/foo.sh` sourcing line in
   the scripts that are still in `scripts/dev/` to
   `${SCRIPT_DIR}/../lib/foo.sh`, and update the repo-root `setup.sh` source
   path to `scripts/lib/pinned-tool-versions.sh`. Run shellcheck and `bash -n`
   on all changed scripts.
3. **Move bootstrap scripts** from `scripts/dev/` to `scripts/bootstrap/`.
   Update `setup.sh`, `Tiltfile`, tests, and internal references in the
   bootstrap scripts themselves.
4. **Move ops scripts** from `scripts/dev/` to `scripts/ops/`. Update
   internal references (notably `seed-ext-authz-session.sh` callers in the
   verify scripts, even though those verify scripts are still under
   `scripts/dev/` at this intermediate step, so the reference becomes
   `../ops/seed-ext-authz-session.sh`).
5. **Move guardrail scripts** from `scripts/dev/` to `scripts/guardrails/`.
   Update CI workflow paths. Update `scripts/lib/phase-7-image-pinning-targets.txt`
   to point at the still-in-dev verify-phase-*.sh paths (interim). Keep
   `verify-phase-7-static-manifests.sh` `ACTIVE_GUIDANCE_PATHS` covering both
   already-moved directories and the remaining `scripts/dev` directory until
   the final cleanup.
6. **Move smoketest scripts** from `scripts/dev/` to `scripts/smoketest/`.
   Update the `verify-phase-7-security-guardrails.sh` `STATIC_GATE=` path to
   `guardrails/`, update any remaining `seed-ext-authz-session.sh` references
   to `../ops/`, move `verify-monitoring-rendered-manifests.sh` here, and
   rewrite `scripts/lib/phase-7-image-pinning-targets.txt` to the final
   `scripts/smoketest/verify-phase-*.sh` paths.
7. **Move loadtest scripts** from `scripts/dev/` to `scripts/loadtest/`.
8. **Move repo-management scripts** from top-level `scripts/` to
   `scripts/repo/`, including `generate-unified-api-docs.sh`. Update any
   external callers, and fix repo-root derivation in `repo-config.sh` and
   `generate-unified-api-docs.sh` so they still resolve the orchestration root
   rather than `scripts/`.
9. **Delete** the now-empty `scripts/dev/` and `scripts/github/` directories.
10. **Author `scripts/smoketest/smoketest.sh`** as the thin dispatcher
    described above.
11. **Rewrite `scripts/README.md`** to match the new layout.
12. **Update `AGENTS.md`, repo root `README.md`, `docs/*.md`,
    `docs-aggregator/README.md`, and other affected README files**. Continue to
    leave `docs/decisions/*` and `docs/archive/*` untouched.
13. **Run the full verification pass** (see below).

Each step above is a small, mergeable commit if desired. The one critical
invariant: between steps, every script reference in `setup.sh`, `Tiltfile`,
and CI must either be fully on the old path or fully on the new path. No
half-moved state.

## Verification

After every step, run:

- `bash -n` on every moved or edited `.sh` file.
- `shellcheck -x` on the same set.

  If `shellcheck` is installed locally, run it directly:

  ```bash
  shellcheck -x path/to/changed-script.sh path/to/changed-helper.sh
  ```

  If it is not installed locally, use the ShellCheck container from the repo
  root:

  ```bash
  docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x \
    path/to/changed-script.sh path/to/changed-helper.sh
  ```

  During the intermediate Step 2 layout, scripts that still live in
  `scripts/dev/` source shared helpers through `../lib/...`. Run those
  checks with the container working directory set to `scripts/dev` so
  ShellCheck resolves the source annotations correctly:

  ```bash
  docker run --rm -v "$PWD:/mnt" -w /mnt/scripts/dev koalaman/shellcheck:stable -x \
    check-tilt-prerequisites.sh install-verified-tool.sh \
    verify-phase-7-static-manifests.sh seed-loadtest-users.sh \
    seed-loadtest-transactions.sh teardown-loadtest.sh \
    seed-ext-authz-session.sh verify-phase-1-credentials.sh \
    flush-redis.sh redis-browse.sh check-secrets-only-handling.sh \
    check-phase-7-image-pinning.sh
  ```

  Check repo-root scripts and shared helpers from the repo root:

  ```bash
  docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:stable -x \
    setup.sh scripts/lib/loadtest-common.sh \
    scripts/lib/pinned-tool-versions.sh scripts/lib/redis-cli.sh
  ```
- Targeted functional runs:
  - Step 2 (lib move): `./scripts/bootstrap/install-verified-tool.sh --help`
    (after step 3), or the pre-move equivalent.
  - Step 5 (guardrails): `./scripts/guardrails/verify-phase-7-static-manifests.sh --self-test`
    and `./scripts/guardrails/verify-phase-7-static-manifests.sh`.
	  - Step 6 (smoketest): individually run each moved verify script against
	    a live `tilt up` cluster, including
	    `./scripts/smoketest/verify-monitoring-rendered-manifests.sh` after the
	    `monitoring` namespace exists. This is where
	    `verify-session-architecture-phase-5.sh` is exercised for real. If it
	    fails, document the failure mode and stop to decide fix-or-delete rather
	    than continuing the refactor with a broken wired-in dependency.
	  - Step 7 (loadtest): run the full
	    seed-users, seed-transactions, teardown pipeline against Tilt.
	  - Step 8 (repo scripts): run `bash -n` on every moved repo script and
	    dry-check root-derived variables without writing generated OpenAPI output
	    or performing git operations.
- Final full pass: `./scripts/smoketest/smoketest.sh` against a clean
  `tilt up` cluster. This is the acceptance gate for the refactor.
- CI replay: push to a branch and confirm
  `.github/workflows/security-guardrails.yml` passes. CI should remain green
  because it continues to call the static guardrails directly.

## Rollback

Each step is a directory move plus reference updates, all committed
atomically. Rollback for any individual step is `git revert` of that commit.
Because `scripts/dev/` is only deleted in the final steps, a revert of step
9 reinstates the old layout without touching the new one. The shared
`lib/` move in step 2 is the most coupled; keep it as its own commit so a
revert does not drag other changes with it.

If `verify-session-architecture-phase-5.sh` turns out to be broken at
step 6, the rollback decision is not to unwind the refactor. It is either:

1. Fix the script in a follow-up commit before the final `smoketest.sh` wire
   in step 10, or
2. Delete the script and remove its line from `smoketest.sh` before step 10.

Either way, the refactor proceeds; only the optional wire-in changes.

## Risks and Mitigations

- **Phase 7 image pinning check fails mid-refactor.** The target-list file
  hard-codes paths that change during the move. Mitigation: update
  `scripts/lib/phase-7-image-pinning-targets.txt` in the same commit that
  moves the smoketest scripts, so the check points at the new paths
  immediately. Validate with
  `./scripts/guardrails/check-phase-7-image-pinning.sh` right after the
  step 6 commit.
- **`verify-phase-7-security-guardrails.sh` breaks because `STATIC_GATE=`
  crosses directories.** Mitigation: update `STATIC_GATE=` in the same
  commit that moves the umbrella into `smoketest/`. Run
  `./scripts/smoketest/verify-phase-7-security-guardrails.sh` immediately
  after.
- **CI green but local smoketest still broken.** CI only runs the static
  half, so it cannot detect runtime regressions introduced by the refactor.
  Mitigation: step 13's full `./scripts/smoketest/smoketest.sh` run is a
  blocking acceptance gate. Do not merge the refactor without that pass.
- **Rendered monitoring validation is accidentally treated as CI-safe.** It
  calls `kubectl apply --dry-run=server`, so moving it to `guardrails/` would
  make the directory semantics false. Mitigation: keep it in `smoketest/`, keep
  the Tiltfile pointed there, and leave CI on the Phase 7 static gate only.
- **Repo-management scripts resolve the wrong root after moving to
  `scripts/repo/`.** Their current `dirname "$SCRIPT_DIR"` logic assumes they
  live directly under `scripts/`. Mitigation: update root derivation in the same
  commit as the move and dry-check `REPO_ROOT`, `PARENT_DIR`, and generated
  docs output paths before running any script that writes or performs git
  operations.
- **`verify-session-architecture-phase-5.sh` is broken.** Expected possible
  outcome. Handled by the rollback section. Do not add a skip flag to hide it.
- **Documentation drift during the pass.** Many `docs/*.md` files reference
  script paths. Mitigation: grep for `scripts/dev/` and for each moved
  top-level path after every commit; fix any stragglers in the same commit
  or the immediate follow-up.
- **Sibling repos pin orchestration script paths.** The `AGENTS.md`
  boundary forbids orchestration from writing code in sibling repos, so any
  sibling breakage is surfaced via documentation updates to those siblings.
  Mitigation: grep the sibling repos under `../` for `scripts/dev/` and
  top-level `scripts/` references; report and update sibling docs only.
- **Someone runs the old path from muscle memory.** Mitigation: no symlinks,
  no shims. A hard break is better than a half-working forwarding layer that
  hides the reorganization. The `scripts/README.md` rewrite and updated
  `setup.sh` output make the new paths discoverable.

## Open Decisions

- `verify-session-architecture-phase-5.sh` fix-or-delete is deferred until
  step 6's live run gives a real signal.
- Phase script renames (`verify-phase-*` to something less plan-specific)
  are out of scope and will be a later plan.
