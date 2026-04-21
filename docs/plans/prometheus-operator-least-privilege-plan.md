# Plan: Prometheus Operator Least Privilege

Date: 2026-04-21

Related files and documents:

- [Tiltfile](/workspace/orchestration/Tiltfile:868)
- [kubernetes/monitoring/prometheus-stack-values.yaml](/workspace/orchestration/kubernetes/monitoring/prometheus-stack-values.yaml:1)
- [kubernetes/monitoring/servicemonitor-spring-boot.yaml](/workspace/orchestration/kubernetes/monitoring/servicemonitor-spring-boot.yaml:1)
- [kubernetes/network-policies/monitoring-allow.yaml](/workspace/orchestration/kubernetes/network-policies/monitoring-allow.yaml:1)
- [kubernetes/istio/authorization-policies.yaml](/workspace/orchestration/kubernetes/istio/authorization-policies.yaml:85)
- [docs/architecture/observability.md](/workspace/orchestration/docs/architecture/observability.md:40)
- [scripts/ops/capture-prometheus-operator-phase-1-baseline.sh](/workspace/orchestration/scripts/ops/capture-prometheus-operator-phase-1-baseline.sh:1)
- [docs/research/prometheus-operator-least-privilege-phase-1-baseline.md](/workspace/orchestration/docs/research/prometheus-operator-least-privilege-phase-1-baseline.md:1)

## Scope

This plan keeps `Prometheus Operator` in the repo and reduces its privilege as far as possible
without breaking the currently documented observability behavior.

This plan is intentionally limited to the operator.

It does not:

- remove `Prometheus Operator`
- replace `ServiceMonitor` / `PodMonitor` with plain Prometheus config
- reduce `Prometheus` server privileges in the same work
- reduce `kube-state-metrics` privileges in the same work
- drop existing current-state observability features as a shortcut

## Problem Statement

The current `kube-prometheus-stack` installation is convenient but the rendered
`Prometheus Operator` RBAC is materially broader than the repo should accept as a final posture.

The operator currently behaves like a platform control-plane component, not a narrow monitoring
helper. In practical terms, that means a compromise of the operator pod is much closer to
environment compromise than to "one monitoring pod compromised."

That is out of proportion to what this repo actually needs.

## Current-State Facts

The current stack is installed from `prometheus-community/kube-prometheus-stack` `83.4.0` via
Tilt: [Tiltfile](/workspace/orchestration/Tiltfile:868).

The repo currently uses the chart for:

- `Prometheus`
- `Grafana`
- `kube-state-metrics`
- `Prometheus Operator`
- CRD-driven discovery via `ServiceMonitor` and `PodMonitor`

The current documented scrape topology is small and explicit:

- Spring Boot `ServiceMonitor` in `default`
- chart-managed monitoring `ServiceMonitor` objects in `monitoring`
- one chart-managed `PodMonitor` for Envoy sidecars
- one chart-managed `ServiceMonitor` for `istiod`

See [docs/architecture/observability.md](/workspace/orchestration/docs/architecture/observability.md:40).

The chart already exposes namespace-scoping values for the operator:

- `prometheusOperator.namespaces`
- `prometheusOperator.denyNamespaces`
- `prometheusOperator.alertmanagerInstanceNamespaces`
- `prometheusOperator.alertmanagerConfigNamespaces`
- `prometheusOperator.prometheusInstanceNamespaces`
- `prometheusOperator.thanosRulerInstanceNamespaces`

Those values are necessary, but they should not be treated as sufficient until the rendered RBAC
and live permissions prove that they actually shrink the operator's effective authority.

## Goals

1. Keep the current operator-based architecture.
2. Preserve the current observability contract:
   - Spring Boot metrics stay `UP`
   - Envoy metrics stay `UP`
   - `istiod`, Grafana, Prometheus Operator, and `kube-state-metrics` monitoring targets stay `UP`
   - Kiali continues to read Prometheus and Jaeger normally
3. Reduce the operator's write and read scope to the minimum set justified by current repo usage.
4. Remove cluster-wide `secrets` authority if the operator does not strictly require it.
5. Make any remaining cluster-scoped permission explicit, narrow, and documented.

## Non-Goals

- Re-architect observability away from the operator
- Combine this work with unrelated monitoring refactors
- Accept silent functionality loss and call it a security win
- Keep broad chart-default privileges just because the upstream chart emits them

## Success Criteria

The work is only complete when all of the following are true:

1. The operator is scoped to the smallest namespace set that supports current behavior.
2. Rendered RBAC no longer grants broad cluster-wide mutation outside the required namespaces.
3. The operator service account cannot read or mutate resources in unrelated namespaces such as
   `infrastructure` unless a specific remaining permission is justified and documented.
4. The observability runtime proof still passes.
5. Any permission we cannot remove is recorded with a concrete reason, not hand-waving.

## Desired End State

The target posture is:

- operator watches only the namespaces that actually contain current relevant CRs
- operator mutates only the resources it owns in `monitoring`
- operator reads only the namespaced monitoring CRs it needs in `default` and `monitoring`
- any remaining cluster-scoped read is limited to resources that are genuinely required for
  reconciliation and cannot be made namespaced
- no cluster-wide secret read or write remains unless live verification proves it is unavoidable

For the current repo shape, the expected namespace set is:

- `monitoring`
- `default`

Anything broader needs proof.

`istiod` scraping does not by itself require the operator to watch `istio-system`, because the
current chart-managed `ServiceMonitor` object lives in `monitoring` and targets `istio-system`
through selector and namespace fields rather than by placing monitoring CRs there.

## Recommended Direction

Use a two-layer reduction strategy:

1. reduce watch scope through chart-supported namespace filters
2. if the chart still renders over-broad RBAC, post-render or overlay the operator RBAC down to a
   repo-owned least-privilege shape

Do not assume layer 1 is enough.

## Phase 1: Baseline And Permission Inventory

Phase 1 is implemented as a repo-owned capture step:

- run `./scripts/ops/capture-prometheus-operator-phase-1-baseline.sh`
- review or refresh
  [docs/research/prometheus-operator-least-privilege-phase-1-baseline.md](/workspace/orchestration/docs/research/prometheus-operator-least-privilege-phase-1-baseline.md:1)
- run `./scripts/smoketest/verify-monitoring-runtime.sh` separately after Tilt
  has brought up the full app stack

### Work

- Render the current `kube-prometheus-stack` manifests with the checked-in values.
- Capture the operator-specific `ClusterRole`, `ClusterRoleBinding`, `Role`, and `RoleBinding`.
- Build a concrete `kubectl auth can-i --as=system:serviceaccount:monitoring:<operator-sa>` matrix
  for the verbs and namespaces that matter.
- Record the live behavior that must not regress:
  - Prometheus targets
  - Kiali `monitoring/prometheus` health
  - Kiali Jaeger integration
  - monitoring runtime verifier

### Required evidence

- Rendered RBAC before changes
- `can-i` before matrix
- current `./scripts/smoketest/verify-monitoring-runtime.sh` result

### Rationale

Without a before-state matrix, "reduced privilege" turns into guessing.

## Phase 2: Chart-Level Namespace Scoping

### Work

Update the chart values to constrain the operator's watch scope first.

The expected starting point is:

- `prometheusOperator.namespaces.releaseNamespace: true`
- `prometheusOperator.namespaces.additional: [default]`
- `prometheusOperator.prometheusInstanceNamespaces: [monitoring]`
- empty or explicit minimal values for the other instance namespace lists

Then re-render and inspect whether the chart actually narrows:

- watched namespaces
- rendered RBAC objects
- cluster-scoped rules

### Acceptance criteria

- the operator no longer watches arbitrary namespaces
- the render clearly narrows the effective watch configuration
- no current monitoring CR becomes orphaned by the new namespace filters

### Notes

This phase is expected to help, but not necessarily to finish the job.
Upstream charts frequently keep broad `ClusterRole` templates even after namespace filters are set.

## Phase 3: Repo-Owned RBAC Reduction

### Work

If the rendered chart RBAC remains broader than required after Phase 2, add a repo-owned reduction
layer.

Preferred implementation order:

1. post-render patch or overlay the chart RBAC
2. replace broad operator `ClusterRole` usage with:
   - a minimal remaining `ClusterRole` only for unavoidable cluster-scoped reads
   - `Role` / `RoleBinding` in `monitoring` for owned writable resources
   - `Role` / `RoleBinding` in `default` for namespaced monitoring CR reads

### Expected RBAC shape

The operator should end up with:

- `monitoring` namespace:
  - write only where it actually owns resources
  - expected candidates: generated config `Secret`, `ConfigMap`, `Service`, `Endpoints` /
    `EndpointSlice`, and the Prometheus-managed `StatefulSet`
- `default` namespace:
  - read-only access to the monitoring CR types it must consume there
  - no reason to mutate app resources
- cluster scope:
  - only the smallest proven set
  - every remaining rule individually justified

### Specific reductions to attempt

- remove cluster-wide `secrets` access first
- remove cluster-wide mutation of namespaced resources outside `monitoring`
- remove `pods delete` outside `monitoring`
- remove unrelated cluster-scoped reads if live tests prove they are unnecessary

### Guardrail

Do not keep a rule just because the upstream chart emits it.
Every retained cluster-scoped rule needs one of:

- a live failing proof without it
- an upstream operator requirement tied to current repo behavior
- a documented reconciliation path that cannot be expressed namespaced

## Phase 4: Verification And Negative Proofs

### Work

Re-run the rendered-manifest and live-runtime proofs after every privilege reduction step.

Minimum verification set:

- render the chart and inspect operator RBAC
- `kubectl auth can-i` negative checks for unrelated namespaces
- `kubectl auth can-i` positive checks for the resources the operator still needs
- `./scripts/smoketest/verify-monitoring-rendered-manifests.sh`
- `./scripts/smoketest/verify-monitoring-runtime.sh`
- `./scripts/ops/triage-kiali-findings.sh --output-dir tmp/kiali-triage`

### Negative checks to require

Representative required denials:

- operator cannot read `Secret` objects in `default`
- operator cannot read or mutate resources in `infrastructure`
- operator cannot create or delete monitoring-owned resources outside `monitoring`

Representative required allows:

- operator can reconcile Prometheus-owned resources in `monitoring`
- operator can read the monitoring CRs it needs in `default`

### Runtime checks that must stay green

- Spring Boot service targets remain `UP`
- Envoy metrics remain available
- `istiod`, Grafana, Prometheus Operator, and `kube-state-metrics` monitoring targets remain `UP`
- Kiali still sees Prometheus and Jaeger correctly

## Phase 5: Documentation And Ongoing Guardrails

### Work

- Update [docs/architecture/observability.md](/workspace/orchestration/docs/architecture/observability.md:477)
  with the final operator privilege model.
- Record the allowed namespace set and the justification for any remaining cluster-scoped rules.
- Extend the local rendered-manifest verifier so future chart upgrades fail fast if the operator RBAC
  broadens again.

### Required guardrails

At minimum, add a render-time assertion that fails if the operator RBAC regresses to:

- cluster-wide `secrets` mutation or read beyond the approved model
- broad namespaced mutation outside `monitoring`
- unexpected watched namespaces

## Explicit Risks

### Risk 1: Chart values narrow watches but not RBAC

This is likely.

Mitigation:

- treat chart-level namespace scoping as an intermediate step
- plan for repo-owned RBAC overlay work, not as a fallback surprise

### Risk 2: Operator needs one or two remaining cluster-scoped reads

This is plausible.

Mitigation:

- prove each one individually
- keep only the smallest cluster-scoped read surface
- document it as a deliberate exception

### Risk 3: "Security win" by silently dropping observability coverage

This is not acceptable.

Mitigation:

- hold the current functionality line
- require runtime verification after every change
- do not remove operator metrics, sidecar metrics, or Spring Boot metrics just to simplify RBAC

## Deliverables

1. Updated `kubernetes/monitoring/prometheus-stack-values.yaml`
2. Repo-owned operator RBAC reduction layer if chart values are insufficient
3. Verification updates that fail on RBAC regression
4. Updated observability architecture documentation
5. Recorded before/after permission matrix for the operator service account

## Completion Standard

This plan is complete only when the repo can say something precise and defensible:

> The Prometheus Operator is retained, but it is no longer treated as an effectively
> cluster-admin-adjacent component. Its namespace watch scope is explicit, its writable surface is
> limited to the resources it owns, unrelated namespace access is denied, and the existing
> observability behavior remains intact.
