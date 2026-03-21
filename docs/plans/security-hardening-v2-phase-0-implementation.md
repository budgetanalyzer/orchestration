# Phase 0 Implementation Plan: Security Hardening v2

## Context

This document expands Phase 0 from [security-hardening-v2.md](./security-hardening-v2.md) into an implementation plan for this repository.

Phase 0 exists to make later hardening phases real. Until the local Kind cluster actually enforces `NetworkPolicy`, and until admission/policy plumbing is installed and testable, every later security control is partly theoretical.

## Goals

1. Make local Kind clusters enforce `NetworkPolicy`.
2. Establish a namespace-level admission baseline without breaking current workloads.
3. Install the policy engine scaffolding needed for later phases.
4. Add deterministic verification that proves the platform preconditions work.
5. Keep all changes orchestration-only.

## Non-Goals

1. Do not implement Phase 1 credential changes.
2. Do not add the real application `NetworkPolicy` allowlists yet. That belongs to Phase 2.
3. Do not enforce `restricted` Pod Security on existing workloads yet. Current manifests are not ready for that.
4. Do not add the full Kyverno policy catalog yet. That belongs to Phase 7.
5. Do not require code changes in sibling service repositories.

## Current-State Gaps

The repository is not ready for Phase 2+ security work yet:

- `kind-cluster-config.yaml` uses Kind's default CNI and does not pin a `kindest/node` image.
- `tests/setup-flow/kind-cluster-test-config.yaml` mirrors the same gap.
- `setup.sh` creates a cluster and immediately continues to DNS/CRDs/TLS setup; it never installs a `NetworkPolicy`-capable CNI.
- `scripts/dev/check-tilt-prerequisites.sh` is a human-oriented prerequisite helper with interactive installs. It does not perform deterministic runtime security verification.
- `Tiltfile` only labels namespaces for Istio sidecar injection. It does not manage Pod Security Admission labels or Kyverno.
- `kubernetes/infrastructure/namespace.yaml` has no Pod Security Admission labels.
- The current test coverage validates the setup flow, but not the security preconditions that Phase 0 needs.

## Recommended Implementation Decisions

### 1. Vendor or pin Calico explicitly

Do not rely on an unpinned "latest" install command for the CNI. Phase 0 should choose one reproducible Calico version compatible with the pinned `kindest/node` version and keep that version explicit.

Recommended shape:

- add a small installer script such as `scripts/dev/install-calico.sh`
- keep the Calico version in one place
- prefer a repo-owned, version-pinned manifest or a version-pinned upstream URL

If the implementation has to choose between convenience and reproducibility here, reproducibility wins.

### 2. Split "prerequisite hints" from "runtime security proof"

`scripts/dev/check-tilt-prerequisites.sh` should remain the entry point users know about, but it is the wrong place for all the runtime probe logic.

Recommended shape:

- keep `check-tilt-prerequisites.sh` for tool/cluster/bootstrap checks
- add a new non-interactive script such as `scripts/dev/verify-security-prereqs.sh`
- have `check-tilt-prerequisites.sh` delegate to the new script when the cluster and required control-plane components exist

This keeps the human-friendly preflight flow while giving Phase 0 a deterministic verifier.

### 3. Stage Pod Security labels before enforcement

The source plan is already correct on sequencing: use `warn` and `audit` first, then flip `enforce` later after Phase 5 manifest hardening.

Phase 0 should not pretend current workloads are `restricted`-clean.

### 4. Keep Phase 0 testing separate from `setup.sh` testing

`tests/setup-flow/` should continue validating bootstrap mechanics.

Phase 0 also needs a second layer of testing for post-bootstrap runtime behavior:

- `NetworkPolicy` enforcement
- Pod Security Admission behavior
- Istio sidecar injection and policy resource presence
- Kyverno readiness and smoke-policy behavior

That warrants a dedicated security-preflight test path instead of overloading the setup-flow test.

## Workstream 1: Kind and CNI Bootstrap

### Objective

Ensure every newly created local cluster can actually enforce `NetworkPolicy`.

### Files to Modify

- `kind-cluster-config.yaml`
- `tests/setup-flow/kind-cluster-test-config.yaml`
- `setup.sh`
- new `scripts/dev/install-calico.sh`

### Planned Changes

1. Pin a `kindest/node` image in both Kind config files.
2. Add `networking.disableDefaultCNI: true` in both Kind config files.
3. Install Calico immediately after cluster creation in `setup.sh`.
4. Wait for Calico readiness before continuing to later setup steps.
5. Detect incompatible pre-existing clusters and fail with a clear rebuild instruction instead of proceeding with a non-enforcing cluster.

### Implementation Notes

- Recreate messaging needs to be explicit because an old Kind cluster created with `kindnet` cannot be "fixed" by applying `NetworkPolicy` YAML later.
- The DinD test config must be updated in parallel with the main Kind config or the setup-flow test will stop matching real bootstrap behavior.
- Calico install should be idempotent so rerunning `setup.sh` does not churn the cluster.

### Definition of Done

- A new Kind cluster created by `setup.sh` has default CNI disabled and Calico ready.
- The setup flow fails fast when it detects a cluster that was created with the old networking model.
- The DinD setup-flow test creates the same kind of cluster the real setup uses.

## Workstream 2: Namespace Baselines and Label Management

### Objective

Establish the namespace-level security baseline required for Pod Security Admission and future policy work.

### Files to Modify

- `Tiltfile`
- `kubernetes/infrastructure/namespace.yaml`
- optionally new namespace metadata manifests under `kubernetes/`

### Planned Changes

1. Expand the current namespace-labeling step so it manages both Istio injection labels and Pod Security Admission labels.
2. Keep `default` and `infrastructure` under explicit label management.
3. Label `envoy-gateway-system` after the Helm release creates the namespace.
4. Defer `enforce` labels until the workloads are made compliant in Phase 5.

### Initial Label Matrix

| Namespace | Istio | PSA warn | PSA audit | PSA enforce | Notes |
|-----------|-------|----------|-----------|-------------|-------|
| `default` | `enabled` | `restricted` | `restricted` | none | Current application workloads are not yet `restricted`-compliant |
| `infrastructure` | `disabled` | `baseline` | `baseline` | none | Re-evaluate `restricted` after infra hardening |
| `envoy-gateway-system` | `disabled` | `baseline` | `baseline` | none | Gateway proxy remains outside the mesh in current topology |

### Explicit Deferrals

- `istio-system` should not be labeled in Phase 0 unless the chosen chart version is validated against that profile first.
- The Kyverno namespace should also be left out of the first PSA pass unless chart behavior is validated first.

Those are control-plane namespaces. Treating them like application namespaces too early is an avoidable failure mode.

### Implementation Notes

- The current Tilt graph already depends on the `istio-injection` resource name in several places. Either preserve that resource name and expand its responsibility, or update every dependent resource in one change. Preserving the name is lower-risk.
- For the `default` namespace, imperative `kubectl label ... --overwrite` remains practical because the namespace already exists.
- For `infrastructure`, keep the namespace manifest as the source of truth and add the PSA labels there.

### Definition of Done

- Namespace labels are applied reproducibly by Tilt, not ad hoc by manual operator action.
- `default`, `infrastructure`, and `envoy-gateway-system` have the expected labels after a normal `tilt up`.
- No namespace is prematurely placed into a breaking `enforce` mode.

## Workstream 3: Kyverno Installation Scaffold

### Objective

Install the admission controller now so later phases can add real policy without reworking the platform layer again.

### Files to Modify

- `Tiltfile`
- new `kubernetes/kyverno/` directory for smoke-policy and later policy expansion

### Planned Changes

1. Install Kyverno through Tilt using a pinned chart version.
2. Add a dedicated Tilt resource for Kyverno readiness.
3. Add one narrowly scoped smoke policy that proves the admission controller is active without affecting normal app workloads.

### Recommended Smoke Policy

Create a policy that only applies in a dedicated temporary test namespace, for example one labeled `security.budgetanalyzer.io/kyverno-smoke=true`, and rejects a clearly insecure pod shape such as `securityContext.privileged: true`.

That gives Phase 0 a real admission proof without coupling current application manifests to Phase 7 policy requirements.

### Implementation Notes

- Do not start with broad deny policies on all namespaces. That would be a hidden Phase 7 change and would create noisy breakage.
- Keep the policy directory layout stable so later phases can add real policies without moving files around again.

### Definition of Done

- Kyverno is installed and healthy in the cluster through normal Tilt bootstrap.
- A dedicated smoke policy is present and can be exercised by the runtime verifier.

## Workstream 4: Runtime Security Preflight Verifier

### Objective

Add a deterministic proof that Phase 0 actually works.

### Files to Modify

- `scripts/dev/check-tilt-prerequisites.sh`
- new `scripts/dev/verify-security-prereqs.sh`
- possibly new helper manifests or inline here-doc manifests used only by the verifier

### Planned Checks

1. `NetworkPolicy` enforcement
2. Pod Security Admission enforcement behavior
3. Istio sidecar injection
4. Istio policy-resource presence
5. Kyverno readiness and smoke-policy rejection

### Required Behavior

The verifier should:

1. Create temporary namespaces and test pods with cleanup traps.
2. Use pinned test images.
3. Fail clearly on timeouts.
4. Be non-interactive.
5. Return a non-zero exit code on any failed proof.

### Concrete Probe Design

#### A. `NetworkPolicy` proof

- Create a temporary namespace with a simple server pod and a simple client pod.
- Confirm baseline connectivity first.
- Apply a deny-all ingress policy to the server pod.
- Confirm the client can no longer connect.
- Optionally add a narrow allow policy and confirm connectivity is restored.

The allow step is important. It proves the failure was policy enforcement, not broken networking.

#### B. Pod Security Admission proof

- Create a temporary namespace labeled `pod-security.kubernetes.io/enforce=restricted`.
- Attempt to create an intentionally non-compliant pod.
- Assert that the API rejects it for Pod Security reasons.

#### C. Istio proof

- Confirm `istiod` is ready.
- Confirm the current Istio policy resources in `kubernetes/istio/` exist in-cluster.
- Launch a disposable pod in an injection-enabled namespace and assert sidecar injection happened.

#### D. Kyverno proof

- Create a temporary namespace matching the smoke policy.
- Attempt to create a pod the smoke policy should reject.
- Assert the admission failure is from Kyverno.

### Integration Plan

- `check-tilt-prerequisites.sh` should surface the new verifier rather than duplicating the logic.
- The verifier should also be usable directly by humans and test scripts.

### Definition of Done

- There is one command that proves Phase 0 prerequisites are enforced, not just configured.
- The command is suitable for both local use and automated test harnesses.

## Workstream 5: Tests and Documentation

### Objective

Keep the repository's bootstrap and troubleshooting docs aligned with the new platform baseline.

### Files to Modify

- `tests/setup-flow/test-setup-flow.sh`
- `tests/setup-flow/README.md`
- new `tests/security-preflight/` test harness
- `docs/tilt-kind-setup-guide.md`
- `docs/runbooks/tilt-debugging.md`
- optionally `docs/plans/security-hardening-v2.md` with a link to this detailed plan

### Planned Changes

1. Update the setup-flow test to install and wait for Calico.
2. Add assertions that the cluster is using the Phase 0 networking model.
3. Create a separate security-preflight test that brings up only the minimum required platform resources, then runs `verify-security-prereqs.sh`.
4. Update setup and troubleshooting docs to explain:
   - why Kind's default CNI is no longer acceptable
   - how Calico is installed
   - how to rebuild an old cluster
   - how to run the new security preflight check

### Implementation Notes

- Do not turn `tests/setup-flow/` into a full Tilt integration test. Keep it focused on `setup.sh`.
- The new security-preflight test should validate runtime behavior after the relevant Tilt resources are up.

### Definition of Done

- The bootstrap test still covers `setup.sh`.
- A second test covers runtime security preconditions.
- Docs explain both the new happy path and the rebuild/troubleshooting path.

## Execution Sequence

Implement Phase 0 in this order:

1. Land Kind config pinning and Calico install path.
2. Update the setup-flow test to match the new cluster bootstrap.
3. Extend namespace label management in Tilt.
4. Install Kyverno and the smoke policy scaffold.
5. Add the runtime verifier.
6. Add the dedicated security-preflight test harness.
7. Update docs last, once the command shapes are final.

This order keeps the cluster bootstrap stable before adding policy and verification layers on top of it.

## Acceptance Criteria

Phase 0 is complete when all of the following are true:

1. `setup.sh` creates a Kind cluster that uses a `NetworkPolicy`-capable CNI.
2. A stale Kind cluster created with the old defaults is detected and rejected with a rebuild instruction.
3. `tilt up` applies the namespace baseline labels expected for this phase.
4. Kyverno installs successfully and a smoke policy is active.
5. The runtime verifier proves:
   - default-deny `NetworkPolicy` blocks traffic
   - Pod Security Admission rejects a non-compliant pod in an enforcing test namespace
   - Istio sidecar injection works
   - Istio security resources are present
   - Kyverno rejects a pod covered by the smoke policy
6. `tests/setup-flow/` passes with the new bootstrap path.
7. The new security-preflight test passes against the minimal required platform stack.

## Risks and Watchpoints

1. Version compatibility is the main technical risk. The pinned `kindest/node`, Calico version, and Kyverno chart version must be chosen together.
2. Namespace PSA labels on control-plane namespaces can easily break Helm installs. Keep those namespaces out of the initial rollout unless explicitly validated.
3. If the runtime verifier only checks "deny" and not "allow then deny", it can generate false confidence from unrelated connectivity failures.
4. The current Tilt dependency graph references `istio-injection` by name. Renaming that resource carelessly will create avoidable regressions.
5. Existing developer clusters will need a rebuild. That migration cost should be documented plainly rather than hidden.

## Deliverables Summary

Expected Phase 0 deliverables:

- updated Kind configs with pinned node image and default CNI disabled
- Calico installation path in setup and tests
- namespace baseline management in Tilt
- Kyverno install resource and smoke policy scaffold
- deterministic runtime security verifier
- updated setup-flow tests
- new security-preflight test harness
- updated setup and troubleshooting documentation
