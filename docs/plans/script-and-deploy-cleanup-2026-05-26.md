# Plan: Script And Deploy Cleanup

Date: 2026-05-26

Related documents:

- `scripts/README.md`
- `deploy/README.md`
- `docs/OWNERSHIP.md`
- `docs/ci-cd.md`
- `docs/runbooks/oci-release-deployment-checklist.md`
- `kubernetes/production/README.md`

## Scope

This plan covers cleanup of the orchestration repository's shell scripts and
`deploy/` operator surface.

The cleanup should remove obsolete one-off scripts, replace legacy phase-based
names with domain names, clarify which deployment scripts are cluster/platform
bootstrap versus continuing deployment operations, and leave the repo with
fewer scripts and clearer entry points.

## Non-Goals

- Preserve old script names through long-lived compatibility wrappers.
- Keep historical experiments as executable scripts.
- Keep one-time repair scripts after the repair has already been completed.
- Rewrite service code in sibling repositories.
- Reorganize unrelated Kubernetes manifests outside the script/deploy naming
  cleanup unless required by a script rename.

## Current Problems

- `deploy/scripts/` uses numeric prefixes that imply one ordered runbook, but
  only the early bootstrap scripts are truly sequential.
- Many script names still reference historical plan phases that no longer exist
  as active planning artifacts.
- Some scripts are explicitly superseded, historical, lower-level, or one-time
  repair paths, but still sit beside normal entry points.
- The repo has many large shell scripts, which makes the script surface feel
  fragile and hard to scan.
- Documentation explains pieces of the model, but the executable directory
  layout does not make lifecycle boundaries obvious.

## Cleanup Principles

1. Delete obsolete scripts instead of moving them into an experiment or legacy
   directory.
2. Retain historical context in docs, not in executable script paths.
3. Rename scripts atomically and update all repo references in the same change.
4. Do not add compatibility wrappers unless an external caller cannot be
   updated in the same change.
5. If a compatibility wrapper is unavoidable, give it a dated removal task in
   this plan and remove it before considering this cleanup complete.
6. Prefer fewer user-facing scripts. If a lower-level script is only used by
   one normal entry point, fold it into that entry point or a sourced library.
7. Keep deploy scripts grouped by lifecycle and mutation boundary, not by
   historical sequence number.

## Proposed Target Shape

Use domain directories for deployment operations:

```text
deploy/scripts/
├── bootstrap/
├── secrets/
├── render/
├── reconcile/
├── release/
├── verify/
└── lib/
```

Use names that describe the current operational contract:

- `phase-4` -> `mesh-bootstrap` or `ingress-bootstrap`
- `phase-5` -> `secret-sync` or `infra-tls`
- `phase-6` -> `production-routes`
- `phase-7` -> `security-guardrails` or `observability`
- `phase-11` -> `public-tls`

The final names should be chosen during implementation based on the closest
source of truth in the script body and `deploy/README.md`.

## Deletion Candidates

Delete these unless implementation discovers an active caller that cannot be
removed safely:

| Path | Reason |
| --- | --- |
| `scripts/repo/generate-release-manifest.sh` | Superseded; it exits with an error and has no active caller. |
| `deploy/scripts/06-configure-host-redirects.sh` | Historical rejected host-redirect experiment; keep the lesson in `deploy/README.md` or an ADR/runbook note, not as an executable. |
| `deploy/scripts/19-migrate-production-redis-statefulset.sh` | One-time Redis Deployment-to-StatefulSet repair has already been run. Retain any useful migration note in docs, then delete the script. |
| `scripts/repo/github/add-repo-topics.sh` | One-off GitHub admin helper; delete unless there is a clear recurring maintenance need. |

Review these for deletion, narrowing, or conversion to read-only docs before
renaming anything around them:

| Path | Concern |
| --- | --- |
| `scripts/repo/checkout-main.sh` | Broad git write helper; conflicts with the repo norm that the user owns git workflow. |
| `scripts/repo/checkout-tag.sh` | Broad git write helper; should not be a normal orchestration entry point. |
| `scripts/repo/validate-repos.sh` | Current implementation has ShellCheck warnings and includes optional git write behavior through `--fix` / `--clean`. |
| `scripts/repo/generate-deployment-manifest.sh` | Lower-level historical workflow; verify whether the current OCI preparation flow still needs it as a direct executable. |
| `deploy/scripts/23-update-production-release-images.sh` | Lower-level renderer used by the preparation flow; consider folding into the normal preparation command or moving implementation into `deploy/scripts/lib/`. |
| `deploy/scripts/25-deploy-oci-release.sh` | Lower-level applier used by the normal OCI-host command; consider folding into `deploy-current-oci-manifest.sh` or moving implementation into `deploy/scripts/lib/`. |

## Work Plan

### 1. Build The Active Caller Inventory

**Status:** Complete. The inventory lives in
`docs/plans/script-and-deploy-cleanup-active-caller-inventory-2026-05-26.md`.

- Generate a complete script list for `scripts/` and `deploy/scripts/`.
- For each script, record:
  - active repo references from `rg`
  - whether it is directly documented as a canonical entry point
  - whether it mutates local files, git state, cluster state, host state, OCI,
    or GitHub
  - whether it is cluster/platform bootstrap, continuing deployment,
    verification, local ops, or one-time repair
- Ignore `docs/archive/` as an active caller.

### 2. Delete Confirmed Obsolete Scripts

- Delete `scripts/repo/generate-release-manifest.sh`.
- Delete `deploy/scripts/06-configure-host-redirects.sh` after preserving the
  rejected-host-redirect lesson in active docs.
- Delete `deploy/scripts/19-migrate-production-redis-statefulset.sh` after
  preserving any still-useful Redis migration context in active docs.
- Delete `scripts/repo/github/add-repo-topics.sh` unless a recurring ownership
  need is identified.
- Remove every reference to deleted scripts from active docs and executable
  code.

### 3. Normalize Deploy Script Layout

- Move current normal deployment scripts into lifecycle directories.
- Remove numeric prefixes where the script is not part of a strictly ordered
  cluster/platform bootstrap sequence.
- Move the early k3s, namespace/Gateway API, Istio, controller, and baseline
  NetworkPolicy scripts under `deploy/scripts/bootstrap/`.
- Decide whether bootstrap scripts should remain numbered inside
  `deploy/scripts/bootstrap/` or be renamed with explicit verbs and documented
  ordering.
- Update `deploy/README.md` so it clearly separates:
  - cluster/platform bootstrap
  - secret synchronization and secret bootstrap operations
  - continuing production deployments
  - production reconciliation
  - verification
  - lower-level internal helpers, if any remain executable

### 4. Replace Legacy Phase Names

- Rename deploy manifest directories:
  - `deploy/manifests/phase-4/`
  - `deploy/manifests/phase-5/`
  - `deploy/manifests/phase-11/`
- Rename phase-labeled deploy scripts and temp output paths where practical.
- Rename phase-labeled guardrail and smoketest scripts only after updating the
  umbrella verifiers that call them.
- Rename phase-labeled helper variables only when doing so does not create a
  noisy, high-risk mechanical change. Prefer external filenames and docs first;
  internal function prefixes can be handled in a later focused cleanup if
  needed.

### 5. Reduce Executable Surface

- Convert single-caller lower-level executables into sourced functions or
  internal implementation blocks where it reduces confusion.
- Keep `scripts/lib/` and `deploy/scripts/lib/` for shared logic only.
- Make sourced libraries non-executable.
- Require every remaining executable script to have discoverable usage:
  `--help`, a usage function, or a clear README entry when it is not intended
  for direct human invocation.

### 6. Update Documentation Ownership

- Update `scripts/README.md` as the canonical script catalog.
- Update `deploy/README.md` as the canonical OCI/deploy operator surface.
- Update `docs/OWNERSHIP.md` only if the cleanup changes the canonical owner
  for script catalog or deployment operating-model detail.
- Update `docs/ci-cd.md`, `docs/runbooks/oci-release-deployment-checklist.md`,
  and `kubernetes/production/README.md` for renamed release/deployment entry
  points.
- Do not update `docs/archive/`.

### 7. Validate The Cleanup

Run at minimum:

```bash
rg -n "phase-|phase_|PHASE|06-configure-host-redirects|19-migrate-production-redis-statefulset|generate-release-manifest" \
  scripts deploy docs kubernetes nginx .github Tiltfile

find scripts deploy/scripts -type f -name "*.sh" -print0 |
  xargs -0 -n1 bash -n

shellcheck -x $(find scripts deploy/scripts -type f -name "*.sh" | sort)

./deploy/scripts/verify/oci-upgrade-lockstep.sh
./scripts/guardrails/verify-static-security-manifests.sh
```

Adjust verifier paths above to the final renamed locations. If a live cluster
is available, also run the relevant live verifier for any touched runtime path.

## Completion Criteria

- No obsolete one-off, historical experiment, or completed repair script remains
  executable in `scripts/` or `deploy/scripts/`.
- `deploy/scripts/` no longer presents continuing operations as a misleading
  numbered sequence.
- Active docs reference only current script paths.
- The Redis StatefulSet migration script is deleted.
- The superseded release-manifest script is deleted.
- Any retained lower-level executable is documented as either a normal entry
  point or an intentional internal helper.
- `bash -n` passes for all remaining shell scripts.
- ShellCheck warnings are fixed or justified with in-file suppression comments.
- Relevant static guardrails pass with the renamed paths.
