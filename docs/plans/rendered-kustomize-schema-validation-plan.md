# Plan: Rendered Kustomize Schema Validation

Date: 2026-05-20
Status: Implemented

Related documents:

- `scripts/guardrails/verify-phase-7-static-manifests.sh`
- `scripts/guardrails/verify-production-image-overlay.sh`
- `scripts/README.md`
- `docs/ci-cd.md`
- `kubernetes/production/apps/kustomization.yaml`
- `kubernetes/production/apps/patches/runtime-release-metadata.yaml`

## Context

The phase 7 static manifest guardrail runs kubeconform against checked-in
Kubernetes YAML files. That is useful for complete manifests, but it is the
wrong validation target for Kustomize patch files. Strategic-merge patches can
intentionally omit fields that are required on a complete resource, such as
`Deployment.spec.selector`.

The production runtime release metadata document is a Kustomize patch. It
should remain outside standalone manifest validation and should instead be
validated through the rendered production overlay.

## Scope

Add rendered Kustomize schema validation to the static guardrail path.

This plan covers:

- Keeping raw `*/patches/*` files excluded from standalone kubeconform
  validation.
- Rendering selected Kustomize overlays into temporary files.
- Running kubeconform against the rendered output.
- Reporting rendered-output validation failures distinctly from raw manifest
  validation failures.

This plan does not change production manifests, image refs, Kyverno policies,
or deployment behavior.

## Target Outcome

The static guardrail should prove both contracts:

1. Complete checked-in Kubernetes manifests are valid as standalone resources.
2. Kustomize overlays that include partial patches render to valid Kubernetes
   resources.

The original failure mode should not return: kubeconform should not validate a
raw Kustomize strategic-merge patch as if it were a complete `Deployment`.

## Implementation Plan

1. Add a rendered-overlay list to
   `scripts/guardrails/verify-phase-7-static-manifests.sh`.

   Initial target:

   - `kubernetes/production/apps`

   Consider adding `kubernetes/production/infrastructure` at the same time if
   the extra render cost is negligible.

2. Add a helper that renders each overlay with:

   ```bash
   kubectl kustomize <overlay> --load-restrictor=LoadRestrictionsNone
   ```

   Write the output to a temporary directory and remove it on exit.

3. Run the existing kubeconform validation logic against each rendered temp
   file.

   Reuse the current missing-schema exception handling so CRD-backed resources
   continue to be handled consistently.

4. Keep raw patch files excluded from `collect_schema_manifest_files`.

   The exclusion is correct because a patch is not a complete Kubernetes
   resource. The rendered overlay is the validation surface.

5. Update script documentation after the guardrail behavior changes.

   Likely surfaces:

   - `scripts/README.md`
   - `docs/ci-cd.md`, if it describes the static workflow details

## Validation

Run:

```bash
bash -n scripts/guardrails/verify-phase-7-static-manifests.sh
shellcheck scripts/guardrails/verify-phase-7-static-manifests.sh
kubectl kustomize kubernetes/production/apps --load-restrictor=LoadRestrictionsNone
./scripts/guardrails/verify-phase-7-static-manifests.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh --self-test
```

If `kubernetes/production/infrastructure` is added to the rendered-overlay
list, also run:

```bash
kubectl kustomize kubernetes/production/infrastructure --load-restrictor=LoadRestrictionsNone
```

## Acceptance Criteria

- Raw Kustomize patch files under `*/patches/*` are not passed to standalone
  kubeconform validation.
- `kubernetes/production/apps` is rendered and schema-validated during
  `verify-phase-7-static-manifests.sh`.
- A malformed rendered Deployment fails the static guardrail.
- The existing phase 7 static guardrail and self-test pass.
- Documentation describes that Kustomize patches are validated through rendered
  overlays, not as standalone manifests.

## Risks And Notes

- The static workflow needs `kubectl` available. If the GitHub Actions job does
  not already provide it, use the repo-pinned installer rather than relying on
  runner defaults.
- Rendered overlays may include CRD-backed resources. Keep the existing
  allowed missing-schema behavior centralized so raw and rendered validation do
  not drift.
- Avoid duplicating checks already owned by
  `scripts/guardrails/verify-production-image-overlay.sh`; this plan is only
  about schema validity of rendered resources.
