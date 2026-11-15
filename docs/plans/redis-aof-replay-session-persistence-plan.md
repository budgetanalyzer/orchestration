# Restore Redis Session Persistence Across AOF Replay

Address [Redis AOF replay drops scripted session writes](../issues/medium-redis-aof-replay-drops-scripted-session-writes.md).
Preserve session creation, heartbeat updates, OAuth state, and bulk revocation
across Redis restarts without opening a client authentication path through
`default`.

Use `user default reset off ~* &* +@all` for `redis-session`: the internal AOF
loader needs replay permissions, while clients must be unable to authenticate
as that user. Introduce a dedicated password-authenticated `redis-health` user
with only `+ping`, no key/channel access, and explicit probe usernames. Keep
the current pinned Redis image; an upstream upgrade is a separate dependency
decision. Prove this approach against that image before relying on it.

All phases execute in orchestration. Read Session Gateway scripts as contract
inputs; do not modify sibling service code. Preserve application ACLs,
`redis-cache` behavior, TLS verification, PVC persistence, memory budgets, and
ARM64 image support. Do not modify existing ADRs, archives, certificates, or
Git state; Phase 5 adds one new ADR. Production validation is offline only.

Before execution, follow the workspace pre-agent procedure and repository
prerequisites. Before any local cluster mutation, enforce
[the exact local target contract](../architecture/autonomous-ai-execution.md#exact-local-kubernetes-target)
using the existing helpers. Missing prerequisites block the affected work.
This plan's creation performs no reset or rollout. Its execution includes a
one-time local session/OAuth-state reset under
[ADR 015](../decisions/015-reset-local-state-instead-of-migrating.md).

Safety rule: no Redis start with the fixed configuration may load AOF history
written before the Phase 3 flush. That history contains writes that earlier
starts skipped, and replaying them could restore revoked sessions. Writes made
after the flush were applied in memory and replay correctly under the fix.
Session writers therefore keep running through the cutover; do not scale them
down.

Cutover sequence:

1. Before Phase 2, the human stops `tilt up` with Ctrl-C and leaves it
   stopped until the human gate. Ctrl-C leaves the old Redis pod and its PVC
   running. Do not use `tilt down`: it deletes the pod but keeps the PVC, so
   the next `tilt up` would load the old history under the fix. Phase 1 needs
   neither Tilt nor the cluster.
2. Phases 1–2 change files only.
3. Phase 3 flushes the still-running old instance and records the pod UID
   and restart count on the issue.
4. **Human gate.** Confirm the pod has not restarted since the flush, then
   start Tilt:

   ```bash
   kubectl get pod redis-session-0 -n infrastructure \
     -o jsonpath='{.metadata.uid} {.status.containerStatuses[0].restartCount}{"\n"}'
   tilt up
   ```

   If the UID or restart count differs from the recorded values, the old
   configuration reloaded the AOF. Rerun `./scripts/ops/flush-redis.sh session`
   before `tilt up`. The fresh `tilt up` applies the new ConfigMap, Secret and
   StatefulSet. The pod template changes, so Redis restarts with the fix.
5. Phase 4 verifies the live fix, and Phase 5 records the ADR.

Run the first invocation with `--max-phases 3`, complete the human gate, then
run the plan again to execute Phases 4–5. Keep phase evidence in the affected
documentation or issue, not by editing this plan during a Session Handler
invocation.

## Phase 1: Establish an isolated AOF replay regression harness

### Workspace

.

### Goal

Reproduce the current replay defect and prove the proposed ACL/probe behavior
in disposable Redis instances before changing deployment inputs.

### Scope

Add `scripts/guardrails/verify-redis-session-aof-replay.sh` and any focused
fixtures it needs; document its interface in `scripts/README.md`.

### Non-goals

No live Redis mutation, deployment changes, service changes, image upgrades,
or fixes for the separate large-index bulk-revocation issue.

### Required context

- The linked issue, including all three bulk-revocation index states.
- `kubernetes/infrastructure/redis-session/start-redis.sh` and `statefulset.yaml`.
- `scripts/README.md` and existing disposable Docker verifier patterns.
- `../session-gateway/src/main/resources/redis/create-session.lua`,
  `conditional-update.lua`, and `delete-user-sessions.lua`.
- `../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java`.
- `docs/architecture/session-edge-authorization-pattern.md` and
  `docs/development/secrets-only-handling.md`.

### Execution steps

1. Implement a harness using the image digest selected by the StatefulSet,
   synthetic credentials, unique owned resources, bounded waits, and cleanup
   traps. Use guest Docker with `--network none`, no published ports, and a
   private persistent data directory or volume reused across each restart.
   Exercise Redis via container exec. An explicitly documented isolated test
   configuration may use internal loopback without TLS; it must not change
   deployment transport settings or generate certificates.
2. Read the actual sibling Lua files as inputs, fail clearly if unavailable,
   and record their paths/hashes. For the Java-embedded OAuth script, use a
   narrowly checked fixture or extraction that fails on source drift instead
   of silently testing an obsolete copy. Run application writes as the actual
   application identity with its existing command/key restrictions.
3. Implement a legacy-control mode and a candidate-ACL mode. The former must
   assert the known data-loss/revival outcome and loader ACL denials, rather
   than treating an arbitrary Redis failure as a successful reproduction.
   The latter must satisfy the intended persistence and authentication
   contract. Keep the legacy ACL fixture explicitly historical/test-only.
4. Test creation after a completed base rewrite, heartbeat permission/expiry
   changes after a completed base rewrite, and OAuth state creation. Check
   hash fields, index membership, and absolute expiration before and after
   restart, with bounded timing tolerance. Confirm the affected effects are
   in the incremental AOF, not accidentally folded into a new base snapshot.
5. Test bulk revocation in three independent runs: all members live; one
   expired key still physically present; and one member whose key is already
   gone. Put the live session and index in the base RDB with `BGREWRITEAOF`
   before revocation. Only the isolated lazy-expiry case may enable `DEBUG`
   and use `DEBUG SET-ACTIVE-EXPIRE 0`. Avoid reads that lazily expire the
   target before the deletion script. Verify the expected single-command or
   `MULTI`/`EXEC` AOF representation so the rare case cannot pass vacuously.
6. Restart each instance on the same data without rewriting after the tested
   operation. Verify revoked sessions/indexes stay absent, restored fields
   and expirations are correct, and candidate runs have no AOF-loader
   `default` ACL denials. Check new connections reject unauthenticated
   commands, password-only AUTH, and explicit AUTH as `default`; verify
   `redis-health` authenticates, returns `PONG`, and cannot read/write data or
   administer Redis. Distinguish deliberately induced client denials from
   internal loader denials.
   Exercise the planned probe command form, `redis-cli -e --user redis-health
   ping` with `REDISCLI_AUTH`. It must exit 0 only with the health password.
   It must exit non-zero with no credentials, a wrong password, or
   password-only AUTH. Show that the same command without `-e` exits 0 in those
   failure cases on the pinned image.
7. Document commands, fixture ownership, cleanup, and the local-only debug
   boundary. Record concise reproduction and candidate results on the issue,
   keeping its status open.

### Implementation notes

Wait for successful AOF rewrites and persistence of tested writes. Disable
automatic rewrites in the harness so they cannot mask incremental replay.
Use graceful restarts for the primary oracle; this proves replay semantics,
not immunity to the configured fsync crash-loss window. Redis CLI exit status
alone is insufficient: assert replies and final state. Candidate ACL testing
must not grant more permissions to application users to make scripts pass.

### Validation

- Run legacy-control and candidate modes against the checked-in image.
- Validate every added/changed shell file with `bash -n` and `shellcheck`.
- Confirm no leftover containers/volumes and no live-cluster access.

### Completion criteria

A repeatable harness demonstrates the specific existing failure and passes
the proposed fix for creation, refresh, OAuth state, all three revocation
cases, and authentication isolation. Its assertions detect incorrect AOF
setup rather than merely observing a successful Redis start.

## Phase 2: Change the session ACL, probes, and credential contract together

### Workspace

.

### Goal

Make the fixed replay policy the shared local/production-reference deployment
configuration, with least-privilege health probes and executable guardrails.

### Scope

Session Redis startup/manifests, Tilt secret wiring, the environment example,
secret inventory, credential/static verifiers, the Phase 1 harness, and their
nearest documentation owners. Keep runtime reconciliation paused.

### Non-goals

No live apply/reset yet, cache ACL changes, broadened application grants,
compatibility aliases for the retired session default password, or hosted
deployment work.

### Required context

- Phase 1 harness, results recorded on the issue, and `scripts/README.md`.
- `Tiltfile`, `.env.example`, and `kubernetes/infrastructure/redis-session/`.
- `scripts/lib/secrets-only-expected-keys.txt` and
  `scripts/guardrails/check-secrets-only-handling.sh`.
- `scripts/smoketest/verify-credential-isolation.sh` and
  `scripts/guardrails/verify-static-security-manifests.sh`.
- `docs/OWNERSHIP.md`, `docs/development/secrets-only-handling.md`,
  `docs/development/local-environment.md`, and `docs/architecture/security-architecture.md`.
- `docs/ci-cd.md#security-guardrailsyml`, `deploy/README.md`,
  `kubernetes/production/README.md`, and `archive/oci/README.md`.

### Execution steps

1. Before editing, confirm `tilt get uiresources` cannot reach a Tilt server.
   Also confirm, read-only, that the `redis-session-0` pod is still running.
   If Tilt is reachable, or the pod is gone because of a `tilt down`, stop
   without editing and report it. Change the session startup ACL to `user default reset off ~* &* +@all`; add
   `redis-health` with a password and only `+ping`. Keep the existing
   application and operator ACLs intact. Explain the internal replay reason
   next to the unusual disabled-user permissions.
2. Replace `REDIS_SESSION_DEFAULT_PASSWORD`/`default-password` with
   `REDIS_SESSION_HEALTH_PASSWORD`/`health-password` for session Redis only.
   Update Tilt's generated bootstrap Secret, StatefulSet environment,
   `.env.example`, secret-key inventory and canonical secret documentation
   atomically. Point `REDISCLI_AUTH` at the health password and add
   `-e --user redis-health` to both TLS-verified probes. Without `-e`, the
   pinned `redis-cli` exits 0 after `NOAUTH`/`WRONGPASS`, so a broken probe
   credential would still pass. Remove active dependencies on the old session
   password; do not alter cache password wiring or ADRs.
3. Update credential isolation checks: session `default` is disabled and
   cannot authenticate; the dedicated health user returns exactly `PONG`
   but cannot read/write keys or execute administrative commands; both probe
   definitions select that user. Run each probe's exact command in the live
   pod with a wrong `REDISCLI_AUTH` and require a non-zero exit, so a probe
   that ignores authentication failures cannot pass. Preserve
   cache-default authentication and
   existing cross-instance/application/operator isolation checks. Prove the
   health identity is absent from the cache and credentials do not cross over.
4. Add focused static checks for the ACL, probe username/password references,
   and matching Secret contract. Make them reject a reenabled `default`, a
   missing explicit probe username, a session probe without `-e`, and
   excessive health grants. Extend the
   harness so its normal acceptance mode consumes the checked-in session ACL
   generation, avoiding a candidate fixture that can drift from deployment.
5. Update the security owner documentation first, then local-environment and
   script documentation: explain disabled-user replay authority, health
   credentials, expected persistence, and the still-required cutover proof.
   Document the cutover sequence from this plan's preamble: Ctrl-C rather than
   `tilt down`, a flush on the running old instance, the pod-restart check,
   then `tilt up`. Also document the forced logout and pending-login loss, and
   failure recovery. Keep the issue open and distinguish
   isolated success from live validation. Do not claim unlimited crash
   durability or production runtime validation.
6. Render local infrastructure and the production reference. Confirm both
   consume the same fixed ACL and probes, with no new production-only patch
   or cloud/cluster prerequisite. Record concise offline results on the issue.

### Implementation notes

The old session secret key is retired, not a password for the disabled user.
Negative login tests can use synthetic invalid passwords and the health
password, without retaining a working `default` credential. Existing ignored
environment files may contain the obsolete variable; document its removal
and the new override without printing unrelated local configuration.

### Validation

- Run the normal Phase 1 regression harness and focused negative static cases.
- Run `bash -n` and `shellcheck` for every changed shell script.
- Run `./scripts/guardrails/check-secrets-only-handling.sh`.
- Run `kubectl kustomize kubernetes/infrastructure` and
  `./deploy/scripts/render/production-infrastructure.sh` client-side.
- With the hash-verified interpreter prepared as documented in `docs/ci-cd.md`,
  run:

  ```bash
  INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
    ./scripts/guardrails/verify-static-security-manifests.sh
  INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
    ./scripts/guardrails/verify-production-image-overlay.sh
  ```

### Completion criteria

Shared configuration, secret inventory, verifiers, and documentation agree on
the new contract. Isolated persistence and offline checks pass. The original
live Redis data has not been loaded by a fixed configuration, and the next
worker has a documented reset/apply sequence.

## Phase 3: Add the live verifier and reset the old history

### Workspace

.

### Goal

Add the live persistence verifier, then clear the old Redis history on the
still-running old instance so the first start with the fix cannot replay it.

### Scope

A repeatable live persistence verifier, written and statically validated but
not run. The one-time `redis-session` flush. Flush evidence recorded on the
issue.

### Non-goals

No Tilt start, rollout, apply, or restart. No replica scaling. No hosted
deployment, production credentials, live `DEBUG` commands, certificate
writes, migrations of old sessions, or resets of other data stores. No PVC
deletion.

### Required context

- Phase 1/2 artifacts and evidence recorded on the issue.
- `docs/architecture/autonomous-ai-execution.md`,
  `scripts/lib/local-kubernetes-target.sh`, and `scripts/ops/flush-redis.sh`.
- The Phase 2 cutover procedure in `docs/development/local-environment.md`.
- `docs/development/getting-started.md`, `scripts/lib/redis-cli.sh`,
  `scripts/ops/seed-ext-authz-session.sh`, and
  `scripts/smoketest/verify-edge-contract.sh` for approved synthetic identities
  and session/ingress test conventions.

### Execution steps

1. Add `scripts/smoketest/verify-redis-session-persistence.sh` with explicit
   opt-in for StatefulSet restarts. Reuse exact-target and TLS helpers;
   use uniquely owned synthetic sessions/users, bounded readiness/rewrite
   waits, cleanup traps, and explicit reply/state assertions. Do not run a
   disruptive restart or whole-database flush implicitly in aggregate smoke
   tests. Document the interface in `scripts/README.md`. Do not run it in
   this phase; the fix is not live yet.
2. Run the VM/runtime prerequisites and exact local target checks. Confirm
   `tilt get uiresources` still cannot reach a Tilt server and that
   `redis-session-0` is running. If Tilt is reachable, stop and report it. If
   the pod is gone, stop and report that the human must choose a reset path.
   Never start Redis, apply manifests, or delete the PVC from this phase.
3. Run `./scripts/ops/flush-redis.sh session` through its existing confirmation
   interface against the running old instance. Require its success output.
   Then confirm, as `redis-ops`, `aof_last_bgrewrite_status:ok` with no
   rewrite in progress or scheduled. If any step fails, stop and report it.
4. Record on the issue the flush time, the `redis-session-0` pod UID, and the
   container restart count, using the preamble's `kubectl get pod` command.
   Report that the human gate is next: check the pod has not restarted, then
   run `tilt up`.

### Implementation notes

The flush logs everyone out and drops pending logins; that is the intended
one-time ADR 015 reset. Session Gateway and `ext-authz` keep running. Writes
made after the flush replay correctly under the fix, so keys reappearing
after the flush are expected and are not a failure.

### Validation

- `bash -n` and `shellcheck` for the new verifier and any changed script.
- The flush script's success output and the post-flush persistence fields.
- `git diff --check`.

### Completion criteria

The live verifier exists and passes static checks. The old instance's history
was flushed and rewritten while it was running the old configuration, and no
start with the fix has happened. The issue records the pod UID and restart
count for the human gate.

## Phase 4: Prove the live restart contract

### Workspace

.

### Goal

After the human gate's `tilt up`, prove persistence and authentication on
local Kind through real StatefulSet restarts. Record the complete acceptance
evidence on the issue for Phase 5.

### Scope

Live verification of the fix, owner-documentation updates to the verified
contract, and acceptance evidence recorded on the issue.

### Non-goals

No hosted deployment, production credentials, live `DEBUG` commands,
certificate writes, replica scaling, or resets of any data store.

### Required context

- Phase 1–3 artifacts and the evidence recorded on the issue.
- `docs/architecture/autonomous-ai-execution.md` and
  `scripts/lib/local-kubernetes-target.sh`.
- `scripts/smoketest/verify-redis-session-persistence.sh` and its
  documentation in `scripts/README.md`.
- `scripts/smoketest/verify-runtime-hardening.sh`,
  `scripts/smoketest/verify-credential-isolation.sh`, and
  `scripts/smoketest/verify-transport-encryption.sh`.

### Execution steps

1. Run the VM/runtime prerequisites and exact local target checks. Confirm
   Tilt is running and `redis-session` is Ready. Confirm the `redis-session-0`
   pod UID differs from the value Phase 3 recorded, which proves Tilt rolled
   the pod. As `redis-ops`, confirm the live `ACL GETUSER default` shows the
   `off` flag. If the UID is unchanged or the old ACL is live, stop and
   report it. Do not restart Redis or revert to the broken ACL as a recovery
   shortcut.
2. Before any intentional negative-login check, read `ACL LOG` and assert
   that it has no `default` entries from the AOF loader client.
3. Run the credential-isolation verifier. Prove disabled-default rejection
   and both health probes' success. Also prove that each probe command fails
   with a wrong password. Retain the existing TLS, application,
   operator and cache isolation checks. Inspect actual ACL flags/grants,
   not just authentication failures that could result from a wrong password.
4. Run the new persistence verifier. After a completed baseline rewrite,
   create a synthetic valid session through the real create Lua script;
   verify it authorizes an appropriate existing protected ingress request.
   Exercise refresh and OAuth-state writes. Execute
   `kubectl rollout restart statefulset/redis-session -n infrastructure`,
   await rollout and readiness, and verify fields, indexes, remaining TTLs,
   OAuth state and session authorization survive. Use verified HTTPS and
   disposable test credentials only; do not use a human browser session.
5. Prove bulk revocation after a base rewrite persists through another
   restart for the all-live and already-gone-member cases. Check sessions
   and index remain absent and revoked synthetic credentials are denied at
   ingress. Keep the expired-but-present case solely in the isolated
   harness. After each restart, assert no `default` AOF-loader ACL denials;
   collect that evidence before intentional negative-login checks or filter
   by loader identity/context. Never clear ACL logs to manufacture a pass.
6. Run focused runtime hardening and transport checks, and remove owned
   fixtures. Update the
   security owner document's known-loss statements to the verified contract,
   retain fsync/expiry limits, and update summaries/cross-links. Record all
   acceptance results on the issue: image digest, harness cases, live restart
   proof, auth/probe proof, reset completion, and offline reference
   validation. Leave the issue in place for Phase 5. Record blocked checks
   honestly; a blocked or failed acceptance check blocks Phase 5.

### Implementation notes

Live verification must create its own short-lived fixture data and never
flush the session database. A test must fail if an unexpected rewrite masks
the incremental AOF behavior. Check that the PVC is unchanged across restarts
and distinguish normal expiry from replay loss. Keep tokens and credentials
out of committed evidence.

### Validation

- Validate new/changed shell scripts with `bash -n` and `shellcheck`.
- Run the isolated harness, including deterministic lazy expiry, against the
  final checked-in configuration.
- Run `./scripts/smoketest/verify-credential-isolation.sh`, the new live
  persistence verifier with its documented restart opt-in,
  `./scripts/smoketest/verify-runtime-hardening.sh`, and
  `./scripts/smoketest/verify-transport-encryption.sh` on guarded local Kind.
- Repeat relevant Phase 2 static/offline checks if their inputs changed.
- Check document links and `git diff --check`; review fixture cleanup and
  workload readiness.

### Completion criteria

Redis is running the fixed configuration, rolled out after the Phase 3 flush.
Creation, refresh, OAuth state and revocation survive the applicable restart
tests; no AOF-loader denials remain. Default logins fail. Health probes pass
with the health credential and fail with a wrong one. Application isolation
remains intact, and the deterministic rare revocation
case passes in isolation. Documentation and the issue's recorded evidence
reflect measured local evidence and the production reference's offline-only
scope.

## Phase 5: Record the decision in an ADR and retire the issue

### Workspace

.

### Goal

Replace the resolved issue with an accepted ADR that records the decision,
alternatives, consequences and measured evidence. Then delete the issue and
remove every link to it.

### Scope

One new ADR in `docs/decisions/`. Deletion of
`docs/issues/medium-redis-aof-replay-drops-scripted-session-writes.md`.
Reference updates in active orchestration documentation, scripts and
configuration comments.

### Non-goals

No runtime, manifest, verifier-behavior, or credential changes. No edits to
existing ADRs. That includes ADR 016's session credential list, which the new
ADR amends by reference. No edits to `docs/archive/` or `archive/oci/`. Do not
edit or delete this plan file: the runner rechecks the plan bytes before
reporting completion, and the user removes the plan after the run. No
sibling-repository edits in this phase.

### Required context

- The issue, including the Phase 1–4 evidence recorded on it.
- `docs/decisions/template.md`,
  `docs/decisions/015-reset-local-state-instead-of-migrating.md`, and
  `docs/decisions/016-separate-session-and-cache-redis.md` for format,
  tone, and the credential contract being amended.
- `docs/OWNERSHIP.md`.
- The documents Phases 1–4 changed, especially
  `docs/architecture/security-architecture.md`,
  `docs/development/local-environment.md`,
  `docs/development/secrets-only-handling.md`, and `scripts/README.md`.

### Execution steps

1. Confirm the issue records passing results for every Phase 4 acceptance
   item. If any item is blocked, failed, or missing, stop without creating
   the ADR or deleting the issue, and report the gap.
2. Create `docs/decisions/NNN-<slug>.md` from the template. Use the next free
   sequential number; it is 018 when this plan was written, but list the
   directory first. Use status `Accepted` and the execution date. Cover:
   - **Context:** the replay mechanism and upstream redis/redis#14156, and the
     observed loss and revival impact.
   - **Decision:** the disabled `default` user with replay-only `+@all`
     authority, the `redis-health` user and explicit probe usernames, and the
     retired `REDIS_SESSION_DEFAULT_PASSWORD`/`default-password`. Say that
     this amends ADR 016's session credential list. Also record the one-time
     cutover reset under ADR 015 and the rule that no fixed start may consume
     pre-reset history.
   - **Alternatives:** an upstream Redis upgrade, probes as `redis-ops`, and
     keeping `default` enabled with narrow grants.
   - **Consequences:** the fsync crash-loss window, the lazy-expiry
     revocation case proven only in isolation, and the production reference's
     offline-only validation. Note that a Redis image change must rerun the
     isolated harness.
3. Move the durable evidence summary from the issue into the ADR: image
   digest, harness cases, live restart results, authentication and probe
   proof, reset completion, and offline render results. Leave out tokens,
   passwords and session identifiers. Do not link the issue or this plan from
   the ADR.
4. Delete the issue file.
5. Find every remaining reference to the issue or this plan:

   ```bash
   rg -n 'medium-redis-aof-replay-drops-scripted-session-writes|redis-aof-replay-session-persistence-plan' \
     --glob '!docs/plans/redis-aof-replay-session-persistence-plan.md' .
   ```

   Also search for prose references such as "the open issue" near Redis
   persistence text. Where the reference still explains rationale, point it
   at the new ADR. Otherwise remove it. Update the owner document first, then
   summaries and cross-links, following `docs/OWNERSHIP.md`.
6. Run the same search read-only against `../session-gateway`,
   `../ext-authz`, and `../workspace`. If a sibling references the issue or
   plan, do not edit it here. Report it as follow-up work for a separate
   sibling-workspace phase.

### Implementation notes

The ADR is the durable record once the issue is gone. It must stand alone
without the deleted issue or the plan. Keep it concise, like ADR 015, and
state limits honestly. Do not claim unlimited crash durability or
production runtime validation.

### Validation

- The step 5 search returns no matches in this repository.
- Every relative Markdown link in the new ADR and in each changed document
  resolves to an existing file and heading.
- `git status --short docs/decisions` lists only the new ADR. Existing ADRs,
  `docs/archive/`, and `archive/oci/` are unchanged.
- `git diff --check` passes.
- If any shell script comment changed, run `bash -n` and `shellcheck` on it.

### Completion criteria

An accepted ADR records the decision, alternatives, consequences and measured
evidence without depending on the issue or plan. The issue file is deleted,
and no active orchestration document, script or configuration references it or
this plan. Any sibling references are reported, not edited. Existing ADRs and
archives are untouched.
