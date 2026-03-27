# Security Hardening v2 Phase 7 Remediation Plan

## Goal

Close the follow-up gaps found during the March 27, 2026 review of the full
Phase 7 implementation so the shipped repo matches the Phase 7 contract,
especially around Session 7 runtime verification and Session 8 completion
criteria.

This is a remediation plan, not a new hardening phase. The current static and
runtime gates are already green on the reviewed cluster. The remaining work is
about closing verification gaps and repairing the audit trail.

## Review Inputs

The review found three concrete issues to fix:

1. Session 7 RabbitMQ verification currently proves denial from inside the
   broker pod via `kubectl exec ... rabbitmqadmin`, not from a workload-like
   client path.
2. Phase 7 still lacks the single final completion command required by the
   Session 8 plan and definition of done.
3. Phase 7 documentation drift remains around the workspace installer
   hardening story and dependency/version reporting.

## Scope

In scope:

- orchestration scripts and docs
- sibling configuration/docs only where the Phase 7 contract explicitly spans
  the workspace, especially `../workspace/ai-agent-sandbox/Dockerfile`
- verification, documentation, and inventory alignment

Out of scope:

- sibling service business logic
- new Phase 7 policy categories
- moving certificate generation into automation
- reopening the stale DinD suites as Phase 7 gates

## Constraints

- Keep the existing Phase 7 contract freeze intact: only the documented seven
  local Tilt `:latest` images remain allowed, and certificate generation stays
  host-only.
- Do not weaken runtime checks just to simplify the verifier. Session 7 should
  become more workload-realistic, not more synthetic.
- Keep temporary probe pods, temporary `NetworkPolicy` objects, and temporary
  RabbitMQ resources self-cleaning and time-bounded.
- Preserve repo boundaries: sibling config and documentation updates are
  allowed, sibling service code changes are not.

## Workstream 1: Fix Session 7 RabbitMQ Runtime Proof

### Objective

Make the RabbitMQ portion of Session 7 prove least-privilege denial on the same
live client path used by workloads, instead of only proving denial from inside
the broker container.

### Implementation Tasks

- Replace the current broker-local denial checks with probe-pod AMQPS checks
  against `rabbitmq.infrastructure:5671`.
- Keep broker-local admin access only for setup/cleanup that cannot be done by
  the limited service user, such as creating and deleting a temporary forbidden
  vhost for the denial test.
- Stop hardcoding RabbitMQ usernames in the verifier. Read both the admin and
  workload usernames from the same secrets or bootstrap material the existing
  Phase 1 credential verifier already trusts.
- Add one positive workload-equivalent AMQPS smoke step before the negative
  checks so the script can distinguish "authz denied" from "cannot connect" or
  "TLS trust failed".
- Reuse a pinned probe image and policy-compliant probe pod. Prefer reusing the
  existing Python/TLS probe pattern from Phase 4 rather than introducing a new
  floating toolchain.
- Keep the explicit cleanup proof:
  - no leftover `verify-phase7-temp=true` pods or `NetworkPolicy` resources
  - no leftover temporary RabbitMQ vhost after success or failure

### Likely Files

- `scripts/dev/verify-phase-7-runtime-guardrails.sh`
- optional shared helpers under `scripts/dev/lib/`
- `scripts/README.md`

### Verification

- `bash -n scripts/dev/verify-phase-7-runtime-guardrails.sh`
- `./scripts/dev/verify-phase-7-runtime-guardrails.sh`
- `kubectl get pod,networkpolicy -A -l verify-phase7-temp=true`
- `kubectl exec -n infrastructure rabbitmq-0 -- rabbitmqctl list_vhosts name`

### Done When

- Session 7 RabbitMQ denials are proven over AMQPS from a probe pod in-cluster.
- The verifier no longer depends on hardcoded RabbitMQ usernames.
- Cleanup is still reliable after both pass and fail paths.

## Workstream 2: Add The Missing Final Phase 7 Completion Gate

### Objective

Implement the single local completion command that the Phase 7 implementation
plan and definition of done already require.

### Implementation Tasks

- Add `scripts/dev/verify-phase-7-security-guardrails.sh` as the local final
  Phase 7 gate.
- Make the final gate run, in order:
  1. `./scripts/dev/verify-phase-7-static-manifests.sh`
  2. `./scripts/dev/verify-phase-7-runtime-guardrails.sh`
- Keep the CI workflow static-only. Do not try to force the live-cluster
  runtime proof into GitHub Actions.
- Decide whether the final gate needs minimal flag passthrough for runtime
  timeouts. Keep the interface narrow if added.
- Update the docs that currently point to separate Session 6 and Session 7
  commands so contributors can find one clear local Phase 7 completion command.
- Record the exact command and exact pass date once the new final gate succeeds.

### Likely Files

- new `scripts/dev/verify-phase-7-security-guardrails.sh`
- `README.md`
- `AGENTS.md`
- `scripts/README.md`
- `docs/development/local-environment.md`
- `docs/development/getting-started.md`
- `docs/ci-cd.md`
- `docs/architecture/security-architecture.md`
- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-7-implementation.md`

### Verification

- `bash -n scripts/dev/verify-phase-7-security-guardrails.sh`
- `./scripts/dev/verify-phase-7-security-guardrails.sh`
- `rg -n "verify-phase-7-(static-manifests|runtime-guardrails|security-guardrails)" README.md AGENTS.md docs scripts`

### Done When

- The repo has one clear local Phase 7 completion command.
- The docs point to that command instead of making the contributor stitch
  Session 6 and Session 7 together manually.
- The master plan records the exact pass date for the final gate.

## Workstream 3: Reconcile Phase 7 Documentation And Inventory Drift

### Objective

Bring the written Phase 7 story back in line with the current workspace and
installer reality.

### Implementation Tasks

- Update the Phase 7 docs that still describe workspace installer hardening as
  pending/manual if the sibling `../workspace/ai-agent-sandbox/Dockerfile` is
  already on the hardened path.
- Reconcile the Phase 7 inventory docs carefully:
  - preserve the Session 1 freeze as historical context
  - add current-state clarification where the docs now read like live status
  - do not rewrite the original contract in a way that hides what was fixed
- Update `docs/dependency-notifications.md` so workspace tooling versions match
  the current checked-in Dockerfile and installer guidance.
- Re-evaluate `tmp/ai-agent-sandbox.Dockerfile.phase7-session4`:
  - remove it if the sibling workspace Dockerfile has already absorbed the
    intended hardening
  - otherwise document exactly why it still exists and what action is pending
- Run a final stale-doc scan for outdated "latest", "unpinned", or "manual
  follow-up" claims tied to the Phase 7 workspace hardening story.

### Likely Files

- `docs/plans/security-hardening-v2.md`
- `docs/plans/security-hardening-v2-phase-7-implementation.md`
- `docs/plans/security-hardening-v2-phase-7-session-1-contract.md`
- `docs/dependency-notifications.md`
- optional removal of `tmp/ai-agent-sandbox.Dockerfile.phase7-session4`
- sibling documentation/config only if alignment there is needed

### Verification

- `rg -n "latest|unpinned|pending|manual copy|follow-up remains pending" docs/plans docs/dependency-notifications.md README.md docs`
- manual comparison against `../workspace/ai-agent-sandbox/Dockerfile`

### Done When

- The docs no longer claim the workspace installer hardening is still pending if
  it has already landed.
- Dependency/version tables reflect the current checked-in workspace toolchain.
- The Phase 7 audit trail is accurate without erasing the historical Session 1
  freeze.

## Recommended Order

1. Fix the Session 7 RabbitMQ verifier first. The final gate should wrap the
   correct runtime proof, not the current weaker one.
2. Re-run the targeted Session 7 runtime verifier and confirm cleanup behavior.
3. Add the final Phase 7 completion command.
4. Update the affected docs and inventory files around the new final gate and
   the workspace hardening status.
5. Run the final Phase 7 completion command and record the exact pass date in
   the master plan.

## Acceptance Criteria

This remediation effort is complete only when all of the following are true:

- Session 7 RabbitMQ checks exercise a workload-like AMQPS path and no longer
  rely on hardcoded usernames.
- `scripts/dev/verify-phase-7-security-guardrails.sh` exists and passes.
- the README and supporting docs point to one clear local Phase 7 completion
  command.
- the Phase 7 plan documents record the actual pass date for that final gate.
- the workspace installer hardening story and dependency notifications match the
  current checked-in files.

## Execution Notes

- The final Phase 7 command still depends on the existing Phase 6 assumptions.
  In particular, the manual browser-console validation on `/_prod-smoke/`
  remains a prerequisite outside this remediation plan.
- The stale DinD suites remain stale, non-gating assets unless they are
  explicitly realigned in separate work.
