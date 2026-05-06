# Plan: Idempotent Pinned Prerequisites In `setup.sh`

Date: 2026-05-05
Status: Implemented

Related documents:

- `setup.sh`
- `scripts/lib/pinned-tool-versions.sh`
- `scripts/bootstrap/install-verified-tool.sh`
- `scripts/bootstrap/check-tilt-prerequisites.sh`
- `scripts/bootstrap/install-calico.sh`
- `scripts/bootstrap/setup-k8s-tls.sh`
- `scripts/bootstrap/setup-infra-tls.sh`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/tilt-kind-setup-guide.md`

## Scope

Make `setup.sh` idempotently converge every repo-pinned prerequisite that the
repo can install or reconcile from checked-in version metadata.

This plan is intentionally narrower than "install everything a developer might
need." Host-managed tools without repo-pinned, verified install metadata should
remain explicit prerequisite checks until the repo owns a safe installation
contract for them.

## Desired Contract

After this work, repeated `./setup.sh` runs should:

- install a missing repo-pinned prerequisite when a verified installer exists
- replace an installed repo-pinned prerequisite when its version is mismatched
- recreate or reconcile repo-owned cluster state that is pinned in this repo
- preserve user-owned local configuration such as `.env`
- fail with a clear action when a prerequisite is not repo-managed
- avoid certificate write operations from the AI/devcontainer context

The script should describe what it is changing before it changes it, especially
for host-level binary replacement and cluster recreation.

## Current Findings

`setup.sh` already behaves idempotently for some surfaces:

- Helm is auto-installed when missing or unsupported.
- Tilt is auto-installed when missing or mismatched.
- The Kind cluster is recreated from `kind-cluster-config.yaml` on each run.
- Calico is applied only when not ready.
- Gateway API CRDs are installed when absent.
- Helm repos are added or refreshed.
- Existing `.env` is preserved.

Remaining gaps:

- `kubectl` is pinned in `scripts/lib/pinned-tool-versions.sh` and supported by
  `install-verified-tool.sh`, but `setup.sh` only checks that it exists.
- `mkcert` is pinned and supported by `install-verified-tool.sh`, but
  `setup.sh` only checks that it exists.
- The Kind binary version is documented and installed in the devcontainer, but
  not centralized in `scripts/lib/pinned-tool-versions.sh` or enforced by
  `setup.sh`.
- Gateway API CRDs are only checked for presence, not version or source parity.
- Calico is pinned inside `install-calico.sh`, not centralized with the other
  bootstrap tool versions.
- `check-tilt-prerequisites.sh` is a mixed preflight and optional fixer for
  Gateway API CRDs; its behavior should align with the setup contract.
- `setup-k8s-tls.sh` lacks the host-execution guard that
  `setup-infra-tls.sh` already has.

## Non-Goals

Do not auto-upgrade or install these from `setup.sh` in this plan:

- Docker
- Git
- OpenSSL
- JDK
- Node.js
- npm
- sibling repository checkouts
- frontend `node_modules`

Those are host/runtime prerequisites, not currently repo-pinned verified
artifacts. `setup.sh` and the preflight may validate them and provide clear
instructions, but durable auto-management requires a separate policy decision.

## Implementation Plan

### 1. Define The Pinned-Prerequisite Inventory

Update `scripts/lib/pinned-tool-versions.sh` so every setup-managed binary has
a single version source:

- `kubectl`
- `helm`
- `tilt`
- `mkcert`
- `kind`

Add Kind URL and checksum metadata for Linux and Darwin on amd64 and arm64.
Keep the existing verified installer pattern rather than adding a second
download path.

Move or expose pinned cluster dependency versions through a shared source where
practical:

- Gateway API CRDs `v1.5.1`
- Calico `v3.32.0`

If full centralization creates more complexity than value, keep the executable
source in the owning script but add a focused guardrail that detects drift
between docs, setup, and scripts.

### 2. Extend The Verified Installer

Update `scripts/bootstrap/install-verified-tool.sh` to support Kind:

- accept `kind` in usage and validation
- download the platform-specific Kind binary
- verify its checked-in SHA-256
- install it to the requested install directory

Keep installer semantics simple: installing an already-current binary should be
safe and replace it with the same artifact.

### 3. Add Generic Version Enforcement Helpers To `setup.sh`

Replace one-off binary checks with explicit ensure functions:

- `ensure_pinned_kubectl`
- `ensure_supported_helm`
- `ensure_pinned_tilt`
- `ensure_pinned_mkcert`
- `ensure_pinned_kind`

Use strict equality for tools with exact pins. Keep Helm on its supported range
unless the team decides exact Helm pinning is required.

The helpers should:

- read expected versions from `scripts/lib/pinned-tool-versions.sh`
- parse installed versions consistently
- call `install-verified-tool.sh` for missing or mismatched tools
- re-check the version after installation
- fail if the installed executable on `PATH` is still not the expected version

### 4. Keep Host-Managed Prerequisites As Checks

Keep Docker, Git, OpenSSL, JDK, Node.js, npm, sibling repos, and
`budget-analyzer-web/node_modules` in preflight checks.

For `setup.sh`, decide whether to add early checks for JDK, Node.js, and npm
based on the supported happy path. If added, they should be validation only,
not installers.

### 5. Harden Certificate Bootstrap Boundaries

Add a host-execution guard to `scripts/bootstrap/setup-k8s-tls.sh`, matching
the intent already present in `setup-infra-tls.sh`.

Keep `setup.sh` as a host-only path for certificate writes. If it detects a
container context before TLS setup, it should stop with host-terminal
instructions instead of generating browser-trust or infrastructure certificates
inside the devcontainer.

### 6. Reconcile Cluster-Pinned State

Gateway API CRDs:

- move the CRD version into a named variable or shared helper
- make `setup.sh` apply the pinned CRD manifest every run, or add a version
  check that reapplies when the installed CRDs do not match the expected
  release
- make the preflight report mismatch clearly without surprising writes unless
  explicitly invoked in a fixer mode

Calico:

- keep `install-calico.sh` idempotent
- make its version discoverable from one source
- add a check that installed Calico matches the pinned version, not merely
  readiness

Kind cluster:

- keep the current clean-bootstrap behavior of deleting and recreating the
  cluster
- ensure the Kind binary and Kind node image pins are both validated before
  cluster creation

### 7. Align Preflight With Setup

Make `check-tilt-prerequisites.sh` read the same version helpers used by
`setup.sh` and report:

- current version
- expected version or supported range
- exact install command for repo-managed tools

Remove or gate interactive mutation from the preflight. The prerequisite check
should primarily report state; `setup.sh` should perform convergence.

### 8. Update Documentation

Update nearest docs in the same change:

- `docs/development/getting-started.md`: summarize that `setup.sh` converges
  repo-pinned prerequisites and recreates the Kind cluster.
- `docs/development/local-environment.md`: list which prerequisites are
  repo-managed versus host-managed.
- `docs/tilt-kind-setup-guide.md`: document the manual equivalent commands
  using `install-verified-tool.sh`.
- `scripts/README.md`: clarify the difference between preflight checks,
  verified tool installation, and full setup.
- `docs/dependency-notifications.md`: keep pinned tool locations accurate.

## Validation

Shell validation:

```bash
bash -n setup.sh scripts/bootstrap/check-tilt-prerequisites.sh scripts/bootstrap/install-verified-tool.sh scripts/bootstrap/setup-k8s-tls.sh scripts/bootstrap/setup-infra-tls.sh scripts/bootstrap/install-calico.sh
shellcheck setup.sh scripts/bootstrap/check-tilt-prerequisites.sh scripts/bootstrap/install-verified-tool.sh scripts/bootstrap/setup-k8s-tls.sh scripts/bootstrap/setup-infra-tls.sh scripts/bootstrap/install-calico.sh
```

Focused installer checks:

```bash
./scripts/bootstrap/install-verified-tool.sh kubectl --install-dir /tmp/ba-tools
./scripts/bootstrap/install-verified-tool.sh helm --install-dir /tmp/ba-tools
./scripts/bootstrap/install-verified-tool.sh tilt --install-dir /tmp/ba-tools
./scripts/bootstrap/install-verified-tool.sh mkcert --install-dir /tmp/ba-tools
./scripts/bootstrap/install-verified-tool.sh kind --install-dir /tmp/ba-tools
```

Preflight checks:

```bash
./scripts/bootstrap/check-tilt-prerequisites.sh
```

Host-only full bootstrap:

```bash
./setup.sh
tilt up
./scripts/smoketest/verify-clean-tilt-deployment-admission.sh
```

Do not run the certificate-writing portions from the devcontainer. Run the full
bootstrap from the host terminal.

## Completion Criteria

- Every `install-verified-tool.sh`-managed binary used by `setup.sh` is either
  installed or version-corrected by `setup.sh`.
- Kind binary management is centralized with the other pinned tool metadata.
- `setup.sh` no longer treats pinned tool presence as sufficient.
- Preflight and setup report the same expected versions.
- Gateway API and Calico checks cover version drift, not only presence or
  readiness.
- Certificate bootstrap scripts refuse to perform SSL write operations from the
  devcontainer.
- Docs clearly distinguish repo-managed pinned prerequisites from host-managed
  prerequisites.
- All changed shell scripts pass `bash -n` and `shellcheck`.
