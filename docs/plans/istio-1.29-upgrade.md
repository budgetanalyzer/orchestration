# Plan: Upgrade Istio to 1.29.1 Before Resuming Phase 5

## Implementation Status

Repo-side changes landed on March 25, 2026:

- Istio Helm pins now target `1.29.1`.
- Gateway API CRD install paths now target `v1.4.0`.
- Ingress gateway hardening moved to Gateway
  `spec.infrastructure.parametersRef` via
  `kubernetes/istio/ingress-gateway-config.yaml`.
- Egress gateway now installs directly from `istio/gateway` using
  `kubernetes/istio/egress-gateway-values.yaml`; the vendored manifest path was
  removed.

Fresh-cluster host validation is still required before treating the upgrade as
complete and resuming Phase 5 Session 4.

## Context

This plan started because the repo was still pinned to Istio `1.24.3` in
`Tiltfile`, and the Phase 5 implementation work assumed that old baseline.

The March 25, 2026 discovery session established the following:

- Istio `1.24` support ended on June 19, 2025.
- Istio `1.26` is also already EOL, so it is not a valid target.
- Istio `1.29.1` was the latest verified supported patch release at plan time.
- Official Istio upgrade guidance prefers canary or one-minor-step upgrades for
  long-lived clusters, but this repo is a disposable local Kind/Tilt
  environment that already expects full cluster recreation through `./setup.sh`.

That changes the execution order for
[`security-hardening-v2-phase-5-implementation.md`](./security-hardening-v2-phase-5-implementation.md):
stop after Session 3, upgrade Istio, validate the new steady state, then resume
Phase 5 Sessions 4+.

## Decision

- Target Istio `1.29.1`.
- Do not target `1.26`.
- Treat this as a repo-baseline refresh plus fresh-cluster validation, not an
  in-place multi-hop upgrade.
- Do not continue Phase 5 Sessions 4+ on the current `1.24.3` baseline.

## Why Upgrade Before Finishing Phase 5

Phase 5 now contains `1.24.3`-specific assumptions that are likely to drift on
upgrade:

- ingress gateway rendered `Deployment`, `ServiceAccount`, and `Service` names
- rendered gateway labels used by policies and runbooks
- ingress ServiceAccount principal matching in `AuthorizationPolicy`
- sidecar and Istio CNI behavior under Pod Security Admission
- Gateway API controller behavior
- verifier script expectations for ingress, egress, and runtime hardening

If Sessions 4+ land first, they will need to be revalidated and possibly
reworked again after the mesh upgrade. That is wasted churn.

## Success Criteria

The upgrade is complete only when all of the following are true:

- All repo-managed Istio version pins target `1.29.1`.
- Any vendored Istio-generated artifacts are re-rendered from the matching
  upstream version or intentionally replaced.
- A fresh `./setup.sh` followed by `tilt up` converges without manual
  post-install drift fixes outside the repo.
- The actual rendered ingress identities, labels, and selectors are reflected
  in policies, verifiers, and docs.
- The security regression stack passes:
  - `./scripts/dev/verify-security-prereqs.sh`
  - `./scripts/dev/verify-phase-2-network-policies.sh`
  - `./scripts/dev/verify-phase-3-istio-ingress.sh`
  - `./scripts/dev/verify-phase-4-transport-encryption.sh`
- Phase 5 documentation is updated to the new steady state before Session 4
  resumes.

## Scope

This is an orchestration-repo change set. The work stays inside this repo unless
documentation in sibling repos needs clarification. Do not write sibling
service code as part of this plan.

## Workstreams

### 1. Reconfirm the upgrade surface

Inventory the repo paths that currently encode `1.24.3` assumptions:

- `Tiltfile`
- `kubernetes/istio/egress-gateway-values.yaml`
- `kubernetes/istio/ingress-gateway-config.yaml`
- `kubernetes/istio/istio-gateway.yaml`
- `kubernetes/istio/istiod-values.yaml`
- `kubernetes/istio/cni-values.yaml`
- `scripts/dev/verify-security-prereqs.sh`
- `scripts/dev/verify-phase-2-network-policies.sh`
- `scripts/dev/verify-phase-3-istio-ingress.sh`
- `scripts/dev/verify-phase-4-transport-encryption.sh`
- `scripts/dev/verify-phase-5-runtime-hardening.sh`
- `docs/architecture/security-architecture.md`
- `docs/development/devcontainer-installed-software.md`
- `docs/development/local-environment.md`
- `docs/dependency-notifications.md`
- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-5-implementation.md`
- `README.md`
- `AGENTS.md`

Also inventory label and identity coupling before changing anything:

- rendered ingress gateway pod labels
- rendered ingress `ServiceAccount` name
- rendered SPIFFE principal expected by ingress-only policies
- egress gateway labels and service selectors

### 2. Update core Istio install pins and values

Update the repo's install source of truth to `1.29.1`:

- change the `istio/base`, `istio/cni`, and `istio/istiod` Helm versions in
  `Tiltfile`
- review `kubernetes/istio/istiod-values.yaml` and
  `kubernetes/istio/cni-values.yaml` for renamed, removed, or newly required
  values
- update any comments that currently describe `1.24.3`-specific behavior as if
  it were a steady-state property

Do not assume the current values files are forward-compatible.

### 3. Reconcile ingress gateway customization on 1.29.1

The old ingress hardening path exists because `1.24.3` predates Gateway
deployment customization through `spec.infrastructure.parametersRef`.

Implementation choice for `1.29.1`:

- `parametersRef` now cleanly covers the repo's ingress hardening needs, so the
  checked-in overlay flow is removed
- ingress pod seccomp, ServiceAccount token retention, and the fixed `30443`
  NodePort now live in `kubernetes/istio/ingress-gateway-config.yaml`

Revalidate all assumptions tied to the rendered gateway objects:

- `Deployment` name
- `ServiceAccount` name
- service name and ports
- labels consumed by network policies and runbooks
- principal strings consumed by Istio authorization policy

### 4. Reconcile the egress gateway packaging path

The repo previously vendored `kubernetes/istio/egress-gateway.yaml` because the
`istio/gateway` `1.24.3` chart rejected the required `service.type=ClusterIP`
override under the tested Helm `v3.20.1` toolchain.

Implementation choice for `1.29.1`:

- the chart now accepts the required inputs, so the vendored manifest path is
  removed and the repo installs `istio/gateway` directly from Helm
- `kubernetes/istio/egress-gateway-values.yaml` is the source of truth for the
  `ClusterIP` service type, the low-port binding sysctl the non-root proxy
  still needs, and pod seccomp hardening

In both cases, verify that the rendered labels, selectors, and pod security
hardening still match the policies in this repo.

### 5. Reconcile policy, verifier, and Pod Security drift

The upgrade is not done when the charts install. It is done when the repo's
security assumptions still hold on the actual rendered resources.

Re-check and update:

- ingress `AuthorizationPolicy` principal matching
- ingress and egress `NetworkPolicy` selectors tied to rendered gateway labels
- runtime-hardening verifier exceptions for gateway token mounts
- any checks that assume old gateway names, labels, or rollout timing
- any Pod Security assumptions tied to sidecar or CNI behavior
- any Gateway API CRD pin that must move with Istio `1.29.1`

### 6. Validate from a fresh cluster

Use the repo's normal disposable-cluster flow:

1. Run `./setup.sh`.
2. Start the platform with `tilt up`.
3. Confirm Istio base, CNI, control plane, ingress, and egress resources settle
   cleanly.
4. Run the regression stack:
   - `./scripts/dev/verify-security-prereqs.sh`
   - `./scripts/dev/verify-phase-2-network-policies.sh`
   - `./scripts/dev/verify-phase-3-istio-ingress.sh`
   - `./scripts/dev/verify-phase-4-transport-encryption.sh`
5. Re-run the live ingress and egress spot checks needed to prove the rendered
   labels, principals, and routing behavior are the ones the repo now documents.

Do not call the upgrade complete if this only works after ad-hoc `kubectl patch`
or hand-edited cluster state.

### 7. Update documentation before resuming Phase 5

Once the new baseline is proven, update the docs that still describe `1.24.3`
or document `1.24.3`-only workarounds as the current design:

- `README.md`
- `AGENTS.md`
- `docs/dependency-notifications.md`
- `docs/development/devcontainer-installed-software.md`
- `docs/development/local-environment.md`
- `docs/architecture/security-architecture.md`
- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-5-implementation.md`

Specifically revisit the Phase 5 Session 3 narrative. If `1.29.1` removes the
need for the current ingress overlay workaround, the plan should say so before
Session 4 starts.

## Resume Gate for Phase 5

Resume Phase 5 Sessions 4+ only after:

- the repo is pinned to Istio `1.29.1`
- the fresh-cluster validation flow is green
- the gateway names, labels, and principals used by policy are re-baselined
- the relevant docs reflect the new steady state

At that point, restart from Phase 5 Session 4 on top of the upgraded mesh.

## Stop Conditions

Stop and resolve the platform baseline first if any of these occur:

- Istio `1.29.1` requires a different Gateway API CRD level than the repo's
  current pin and the routes do not reconcile cleanly
- the ingress or egress gateway render paths produce new labels or identities
  that invalidate existing security policy assumptions
- sidecar or CNI behavior changes in ways that break the current Pod Security
  posture
- the security regression scripts fail on the upgraded baseline

Do not continue with more Phase 5 hardening until the upgraded mesh is stable.

## Discovery Sources

The March 25, 2026 discovery session for this plan referenced:

- Istio 1.24 EOL notice:
  <https://istio.io/latest/news/support/announcing-1.24-eol-final/>
- Istio 1.26 EOL notice:
  <https://istio.io/latest/news/support/announcing-1.26-eol/>
- Istio 1.29.x releases:
  <https://istio.io/latest/news/releases/1.29.x/>
- Istio upgrade overview:
  <https://istio.io/latest/docs/setup/upgrade/>
- Istio in-place upgrade guidance:
  <https://istio.io/latest/docs/setup/upgrade/in-place/>
- Istio canary upgrade guidance:
  <https://istio.io/latest/docs/setup/upgrade/canary/>
