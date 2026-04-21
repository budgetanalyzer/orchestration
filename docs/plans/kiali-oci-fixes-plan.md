# Plan: Kiali OCI Fixes

Date: 2026-04-21
Updated: 2026-04-21

Related documents:

- [docs/architecture/observability.md](../architecture/observability.md)
- [docs/runbooks/kiali-expected-warnings.md](../runbooks/kiali-expected-warnings.md)
- [kubernetes/production/README.md](../../kubernetes/production/README.md)
- [kubernetes/production/apps/kustomization.yaml](../../kubernetes/production/apps/kustomization.yaml)
- [kubernetes/istio/authorization-policies.yaml](../../kubernetes/istio/authorization-policies.yaml)
- [kubernetes/production/istio/authorization-policies.yaml](../../kubernetes/production/istio/authorization-policies.yaml)
- [deploy/scripts/04-install-istio.sh](../../deploy/scripts/04-install-istio.sh)
- [scripts/ops/triage-kiali-findings.sh](../../scripts/ops/triage-kiali-findings.sh)

## Scope

This plan tracks production OCI fixes driven by Kiali findings and related
observability noise.

It is intentionally cumulative. Add future OCI/Kiali fixes here instead of
creating a new single-use plan each time, unless a later issue is large enough
to justify its own separate plan.

## Problem Statement

Kiali on OCI production currently reports a `KIA0004` warning for
`AuthorizationPolicy/default/budget-analyzer-web-policy`.

That warning is real configuration drift, not a frontend runtime failure:

- OCI production does not run a standalone `Deployment/budget-analyzer-web`
- the production frontend bundle is served from `nginx-gateway`
- the shared Istio authorization policy file still defines
  `budget-analyzer-web-policy`
- the OCI install path reapplies that shared policy file during Istio install

The current result is a selector that matches no workload in production, which
Kiali correctly reports as `KIA0004`.

Kiali also reports missing workload version information for the deployed
services.

That warning is lower risk than the stale policy, but it is still useful to
clean up because it makes the workloads view noisier and prevents Kiali from
showing a clear version dimension for the current rollout.

## Validated Diagnosis

Evidence gathered on 2026-04-21:

- live OCI cluster contains `AuthorizationPolicy/default/budget-analyzer-web-policy`
- that policy selects `app=budget-analyzer-web`
- OCI production serves the frontend from the `nginx-gateway` production
  overlay rather than a standalone frontend workload
- `deploy/scripts/04-install-istio.sh` reapplies
  `kubernetes/istio/authorization-policies.yaml`, so deleting the policy by
  hand would only be temporary

## Goals

1. Remove the stale `budget-analyzer-web-policy` warning from Kiali on OCI.
2. Keep the production architecture honest:
   - no standalone `budget-analyzer-web` workload in OCI production
   - frontend bundle served from `nginx-gateway`
3. Add explicit workload version labels so Kiali can classify workloads cleanly.
4. Make the fixes durable in the repo-owned OCI deployment path.
5. Avoid introducing OCI-only live-cluster drift as the final fix.

## Non-Goals

- Do not add a fake `budget-analyzer-web` workload to production just to make
  Kiali quiet.
- Do not keep the stale policy and classify it as expected noise.
- Do not weaken the current authz posture for actual production workloads.
- Do not fork a second inconsistent authorization-policy source of truth unless
  the production path truly requires it.

## Recommended Direction

Production should stop applying `budget-analyzer-web-policy`.

The repo needs a production-aware authorization-policy path that reflects the
actual OCI workload shape. The production path should not carry local/Tilt-only
frontend policy objects into a cluster where the frontend is served from
`nginx-gateway`.

## Candidate Approaches

### Option 1: Split Istio AuthorizationPolicy Inputs By Runtime Shape

Create a production-specific authorization-policy artifact that excludes
`budget-analyzer-web-policy`, and update the OCI install path to use it.

Why this is the leading option:

- matches the real production workload topology
- prevents the stale policy from being recreated on OCI
- keeps local/Tilt behavior available where the standalone frontend workload
  still exists

Risk:

- the repo must keep dev and production policy artifacts aligned for the shared
  workloads

### Option 2: Keep One Shared File And Patch Out The Frontend Policy In OCI

Keep `kubernetes/istio/authorization-policies.yaml` as the base input and add a
production overlay or render step that removes `budget-analyzer-web-policy`
before apply.

Why this may be acceptable:

- less duplication than a full second file
- still yields a repo-owned durable production result

Risk:

- the removal logic may be less obvious than an explicit production artifact
- render-time mutation can be harder to audit than a reviewed checked-in file

### Rejected Direction: Ignore The Warning Permanently

Do not do this.

`KIA0004` is accurately reporting that the production cluster contains a policy
 selector with no matching workload. That is stale configuration, not expected
runtime noise.

## Implementation Plan

### Phase 1: Choose The Production AuthorizationPolicy Source

Decide which repo-owned shape is easier to maintain and review:

- explicit production policy artifact
- shared file plus production removal overlay/render step

Decision criteria:

- readable in code review
- durable across reruns of `deploy/scripts/04-install-istio.sh`
- minimal drift between local and production for the workloads they actually
  share

Implementation status:

- Completed on 2026-04-21.
- Option 1 was selected.
- The production-specific source of truth is now
  `kubernetes/production/istio/authorization-policies.yaml`.
- The shared local/Tilt source remains
  `kubernetes/istio/authorization-policies.yaml`.

### Phase 2: Remove `budget-analyzer-web-policy` From The OCI Apply Path

Implement the selected production-aware policy path so OCI no longer applies a
policy targeting `app=budget-analyzer-web`.

Required outcome:

- rerunning the repo-owned OCI Istio install/reconcile path does not recreate
  `AuthorizationPolicy/default/budget-analyzer-web-policy`

Implementation status:

- Completed on 2026-04-21.
- `deploy/scripts/04-install-istio.sh` now applies
  `kubernetes/production/istio/authorization-policies.yaml` for OCI instead of
  the shared local/Tilt file.
- The production manifest intentionally omits
  `AuthorizationPolicy/default/budget-analyzer-web-policy`.

### Phase 3: Keep Verification Honest

Update the nearest verification paths so production expectations match the real
OCI topology.

Likely verification touchpoints:

- any smoke or guardrail script that assumes `budget-analyzer-web-policy` must
  exist everywhere
- any helper that interprets missing standalone frontend workload objects as
  production failure rather than production shape

Minimum requirement:

- the repo should stop treating this stale policy as part of the required OCI
  baseline

Implementation status:

- Completed on 2026-04-21.
- `scripts/guardrails/verify-production-image-overlay.sh` now fails if the
  production authz baseline reintroduces `budget-analyzer-web-policy` or a
  selector for `app=budget-analyzer-web`.
- `scripts/ops/triage-kiali-findings.sh` now supports
  `--runtime-shape production` so OCI triage expects the six-workload
  production topology instead of the seven-workload local/Tilt topology.

### Phase 4: Document The Production Distinction

Update the nearest docs so the difference is explicit:

- local/Tilt keeps a standalone `budget-analyzer-web` workload
- OCI production serves the frontend through `nginx-gateway`
- the production authorization-policy baseline must reflect that difference

Implementation status:

- Completed on 2026-04-21.
- The production distinction is now called out in the production Istio
  manifest, production deployment docs, Kiali troubleshooting docs, and the
  Kiali warnings runbook.

### Phase 5: Add Explicit Workload Version Labels

Add consistent workload version labeling where Kiali expects it.

Working assumption from the current manifests:

- workloads generally carry `app`
- workloads do not consistently carry a pod-template `version` label
- OCI production also does not currently stamp a production version label into
  the rendered workload metadata

Recommended direction:

- add `version: v1` to the shared workload pod-template labels as the baseline
  Kiali grouping key
- evaluate whether to also add `app.kubernetes.io/version` where the repo
  already has a stable release identifier available
- for production overlays, prefer using the reviewed production release version
  when it can be kept aligned with the image inventory cleanly

Constraints:

- keep the local/Tilt and OCI production paths understandable
- do not introduce a brittle manual version-string update path across many
  files unless the release process can keep it aligned
- prefer one repo-owned convention for all app workloads rather than fixing one
  deployment at a time

Success condition for this phase:

- Kiali stops warning that the workloads are missing version information
- workload labels remain consistent across local and OCI paths

Implementation status:

- Completed on 2026-04-21.
- The shared Deployment manifests for the seven app workloads now stamp
  `version: v1` on workload metadata and pod-template labels, so both local
  Tilt applies and the OCI production apps overlay inherit the same Kiali
  grouping key.
- The repo standardizes on `version` as the current Kiali-facing workload
  label. `app.kubernetes.io/version` remains deferred until the release path
  can stamp it automatically without introducing a brittle manual update path.

## Success Criteria

This fix is complete when all of the following are true on OCI:

- Kiali no longer reports `KIA0004` for `budget-analyzer-web-policy`
- `kubectl get authorizationpolicy -n default budget-analyzer-web-policy`
  returns not found after the repo-owned OCI reconcile path runs
- Kiali no longer reports missing workload version information for the tracked
  app workloads
- the production frontend still works through `nginx-gateway`
- local/Tilt authorization policy behavior for the standalone frontend remains
  intact unless intentionally redesigned

## Open Questions

1. Are there other local-only policies or checks that will produce similar OCI
   false mismatches once this one is fixed?
