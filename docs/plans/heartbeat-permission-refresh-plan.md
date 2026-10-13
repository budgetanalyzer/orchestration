# Refresh Authorization Before Extending Browser Sessions

Implement the agreed ordinary-deactivation fallback: every heartbeat checks
permission-service before extending the Redis session. Keep the existing
deactivation transaction and immediate bulk-revocation attempt. Permission-service
owns account status and grants; Redis contains a refreshable session snapshot.
The `/api/*` path continues to use only Redis through `ext-authz`.

Use the existing session lifetime as the freshness limit: active browsers normally
observe deactivation on their next heartbeat (currently every two minutes).
Sessions without a successful refresh expire after their remaining TTL (currently
15 minutes by default). A login or heartbeat already in flight at deactivation
can complete with its earlier authorization result; this plan accepts that bounded
window and does not promise immediate containment. Emergency admin containment
remains the human operator procedure in
[security-architecture.md](../architecture/security-architecture.md#emergency-admin-containment).

## Agreed behavior and boundaries

| Heartbeat outcome | Redis/session behavior | Browser response |
| --- | --- | --- |
| Account active; lookup succeeds | Atomically replace roles and permissions and extend expiration/TTL, only while the session remains valid | 200 with refreshed roles and the expiration actually stored |
| Account deactivated, deleted, or missing | Delete the current session and clear its cookie | 401 after successful invalidation |
| Permission lookup unavailable, timed out, or invalid | Preserve existing session contents and expiration; never extend from cached permissions | 503; keep the cookie and allow a later retry |
| Session missing or expired, including during lookup | Do not create or resurrect a session; clear the cookie | 401 |
| Redis mutation fails | Do not report success; retain finite expiry as the fallback | Temporary service failure; never fall back to an expiry-only extension |

No per-request permission-service calls, separate permission-expiry timestamp,
authorization versions, background revocation jobs, new admin roles, runtime
grant-management API, or changes to deactivation's role-removal policy. Keep the
heartbeat response shape, activity detection, cadence, and configured session TTL.
Refreshing frontend permission affordances immediately is outside this change;
`/auth/v1/user` must reflect the updated Redis snapshot on its next fetch, and
backend authorization remains authoritative.

Preserve idempotent account deactivation: after the database change commits and
session revocation fails with 503, repeating the same deactivation request must
retry revocation even though the account is already deactivated. Preserve the
original deactivation actor/time and removed grants. Return 200 when revocation
succeeds (including when no sessions remain), or 503 again if it still fails.
This behavior already exists; add an explicit failure-then-retry regression test
rather than a new idempotency mechanism.

## Execution prerequisites

- Execute phases in their declared repositories; sibling service code must not be
  edited from orchestration. Read each workspace's `AGENTS.md` before execution.
- Before launching AI Session Handler, the human operator must complete the
  pre-run gate below from a fresh normal-user VM shell. Do not delegate the live
  user-tool installation to a plan worker and do not weaken or bypass the
  preflight. Each phase must still satisfy its repository's toolchain and
  Docker/Testcontainers prerequisites.
- Live validation is local Kind only. Follow
  [autonomous-ai-execution.md](../architecture/autonomous-ai-execution.md) and
  [getting-started.md](../development/getting-started.md), including the exact
  cluster/API guard before any cluster mutation. Never generate TLS certificates
  or access production. Use disposable fixtures, not human accounts or cookies.
- Preserve existing worktree changes in every execution workspace, including
  frontend edits, generated OpenAPI files, and the emergency-containment
  documentation. Do not commit, push, or manipulate branches.

### Human pre-run gate

The previous Phase 1 attempt made no repository changes and stopped because the
installed workspace-managed `user_tools.py` is stale. After all agent workers,
including the session that prepared this plan, have stopped, refresh only the
normal-user tools using
[workspace's documented focused repair](../../../workspace/docs/native-user-tools.md#install-user-tools-and-environment).
Run these commands from the orchestration repository root:

```bash
cd ../workspace
./scripts/install-agent-vm-user-tools.sh \
  --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
  --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"
. "$HOME/.config/budget-analyzer-native/env.sh"
./scripts/install-agent-vm-user-tools.sh \
  --worktree-parent "$BUDGET_ANALYZER_WORKTREE_PARENT" \
  --bare-parent "$BUDGET_ANALYZER_BARE_PARENT"

cd ../orchestration
./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime
```

Do not start the handler unless the final command succeeds. The stopped attempt
must be resumed with both recovery flags because this plan changed after the
blocked snapshot:

```bash
ai-run heartbeat-permission-refresh-plan --retry-stopped --accept-plan-change
```

## Phase 1: Add a Read-Only Authorization Lookup

### Workspace

../permission-service

### Goal

Give heartbeat a current account-status and permission lookup without invoking
login's user creation/profile synchronization.

### Scope

A narrow internal endpoint, its service implementation, security matcher, tests,
and permission-service documentation.

### Non-goals

Changing login synchronization, deactivation ordering/retries, database schema,
grant policy, or public admin APIs.

### Required context

- `AGENTS.md`, `README.md`, and `docs/authorization-model.md`.
- `InternalPermissionController`, `PermissionService`, `UserSyncService`,
  `UserRepository`, and `PermissionServiceSecurityConfig`.
- Existing internal-controller and deactivation integration tests.
- Shared `service-common` code-quality, testing, and error-handling documents.
- Orchestration's session-edge contract and `docs/agents-md-checkstyle.md`.

### Execution steps

1. Add `GET /internal/v1/users/{userId}/authorization`, keyed by the internal
   `userId` already stored in the Redis session. Return
   `{ userId, status, roles, permissions }` for a non-deleted user. For
   `DEACTIVATED`, return empty role/permission collections regardless of leftover
   assignments. Return 404 for missing or soft-deleted users.
2. Resolve status and effective grants in a read-only service operation. Reuse the
   existing permission resolver for active accounts. Do not call `syncUser`,
   create users, assign defaults, or update profile/audit fields.
3. Extend the claims-header exception to the exact new internal GET route; retain
   the existing login endpoint and deny unrelated internal routes. Document the
   new exception in `AGENTS.md` using the authoring standard. Transport caller
   controls remain orchestration-owned; no `/internal/**` blanket permission.
4. Add integration coverage for active users with changed grants, active users
   with no grants, deactivated users with leftover roles, deleted/missing users,
   absence of persistence side effects, and the narrow security matcher.
5. Add a deactivation integration regression that performs the full sequence on
   the same account: commit deactivation and exhaust revocation retries (503),
   recover the Session Gateway dependency, repeat the deactivation request (200),
   then repeat it again with no sessions remaining (200). Verify each request
   attempts revocation, roles stay removed, retry reports zero additional roles
   removed, and the original deactivation actor/time remain unchanged. Use a
   different authorized actor on retry to prove the audit fields are preserved.
   Keep existing bounded retries and production behavior; fix only a demonstrated
   regression if this test exposes one.
6. Document the lookup and preserve the idempotent deactivation contract. Clarify
   API wording that an already-deactivated account still requires a successful
   revocation attempt for 200; it can return 503 again.

### Implementation notes

An active user with no permissions is still active. Do not infer deactivation
from an empty collection. The existing login endpoint uses an IdP subject and
profile parameters; leave that contract separate from this read-only lookup.

### Validation

Run focused internal API/service integration tests while iterating, then the
required `./gradlew clean spotlessApply` and `./gradlew clean build` in sequence.
Inspect Checkstyle warnings. Run `git diff --check` and verify documentation links.

### Completion criteria

The new internal contract is covered by tests and has no persistence side effects.
Existing login/deactivation tests and the failure-then-retry regression pass.
Session Gateway can consume the contract without any permission-service call
from `ext-authz` or downstream services.

## Phase 2: Refresh Authorization Atomically on Heartbeat

### Workspace

../session-gateway

### Goal

Make successful authoritative refresh a prerequisite for extending a session.

### Scope

`PermissionServiceClient`, heartbeat handling, Redis session writes, focused
integration tests, and session lifecycle documentation.

### Non-goals

Changing the login contract, session cookie/schema namespaces, bulk-revocation
API, heartbeat response shape, or introducing a second expiry clock.

### Required context

- `AGENTS.md`, `README.md`, `docs/session-configuration.md`, and `docs/security.md`.
- Phase 1's internal endpoint and its worktree tests/API annotations.
- `SessionController`, `PermissionServiceClient`, `WebClientConfig`,
  `SessionReader`, `SessionWriter`, and `redis/conditional-update.lua`.
- Existing controller, client, writer, and security-context integration tests.
- Shared Java/testing standards and orchestration's AI-context authoring standard.

### Execution steps

1. Add a client operation for Phase 1's endpoint using the session's `userId`.
   Distinguish inactive/missing accounts from dependency failures. Use one bounded
   lookup per heartbeat with a finite timeout appropriate to this internal call;
   do not add a retry subsystem or change the IdP client.
2. After reading a valid session, obtain its current authorization. On active
   success, write refreshed `roles`, `permissions`, `expires_at`, Redis TTL, and
   user-index membership/TTL in one conditional Redis operation. Extend the
   existing Lua mechanism instead of creating a parallel session store.
3. Ensure that a session deleted or expired during lookup cannot be recreated or
   renewed. Return the refreshed roles and the same expiry value used by the
   successful Redis write, rather than recomputing response expiry separately.
4. On deactivated/deleted/missing account, invalidate only this heartbeat's
   session and clear the cookie with 401. Existing bulk revocation handles the
   immediate all-session attempt; other sessions independently refresh or expire.
5. On lookup timeout, connection failure, upstream service error, or malformed
   response, return 503 without changing the session or cookie. Unexpected upstream
   access errors are dependency failures, not proof the user is deactivated.
   Never route errors through the old expiry-only extension. Redis failures must
   also produce a temporary failure rather than a successful heartbeat.
6. Update heartbeat API annotations and active lifecycle docs, including relevant
   `AGENTS.md` summaries. Replace assertions that heartbeat is Redis-only or
   extends unconditionally. It still never calls Auth0.

### Implementation notes

Use the existing real Redis/Testcontainers and HTTP-stub test patterns. Preserve
atomicity with concurrent deletion. No version protocol is required to eliminate
every concurrent grant-change race: an authorization result obtained before a
change may be used by an in-flight heartbeat, then expires or is refreshed normally.

### Validation

Extend the existing client, controller, and writer integration suites to prove:

- Successful heartbeat replaces stale grants, including replacement with empty
  grants for an active user; the returned expiry matches Redis.
- Inactive/missing/deleted accounts invalidate the session and return 401.
- Timeout, upstream error, and invalid payload leave hash fields and expiry
  unchanged and do not increase either session or index TTL. Use elapsed-time
  tolerances for Redis TTL assertions.
- Repeated failed heartbeats cannot keep a session alive; a short-lived fixture
  expires. A subsequent successful refresh can recover while it remains valid.
- Concurrent deletion/expiry during lookup does not resurrect the hash or index.
- Redis mutation failure never yields 200. `/auth/v1/user` sees refreshed grants
  on its next request, and login and bulk-revocation regressions still pass.

Run focused tests, then `./gradlew clean spotlessApply` and `./gradlew clean build`
in sequence, inspect warnings, and run `git diff --check`.

### Completion criteria

Every successful heartbeat refreshes authorization before extending the session.
Unavailable permission-service can no longer allow indefinite stale access.
The frontend response shape and the Redis contract consumed by `ext-authz` remain
compatible; no `ext-authz` implementation change is required.

## Phase 3: Verify the Shared Contract and Update Architecture Documentation

### Workspace

.

### Goal

Document and verify the bounded deactivation behavior across the local stack.

### Scope

Orchestration documentation, existing focused session verification, a
single-output mode for the canonical OpenAPI generator, and any strictly
necessary deployment-contract corrections in both supported manifests.

### Non-goals

Service source edits, production administration, broad security-policy redesign,
new public routes, or adding permission-service to the API authorization path.

### Required context

- `AGENTS.md`, `docs/OWNERSHIP.md`, and `scripts/README.md`.
- Session-edge, security, autonomous-execution, and port-reference owner docs.
- Local and production Istio authorization policies and network policies.
- `scripts/smoketest/verify-session-architecture.sh` and Phase 1/2 test evidence.
- `docs-aggregator/README.md` and `scripts/repo/generate-unified-api-docs.sh`.

### Execution steps

1. Verify the existing Session Gateway-to-permission-service network/mesh path
   admits the new lookup locally and in production manifests. Confirm the route
   is internal and absent from both public NGINX configurations. Keep policies
   unchanged if they already support the required contract.
2. Update the canonical session-edge document first, then security and relevant
   workflow summaries: permission refresh on heartbeat, 401 versus 503, unchanged
   idle lifetime, approximate two-minute normal observation, remaining-TTL fallback,
   and accepted in-flight races. Preserve the separate emergency-admin procedure.
3. Extend `scripts/repo/generate-unified-api-docs.sh` with a documented,
   opt-in Session-Gateway-only mode that accepts one explicit YAML output path,
   applies the existing `/internal/*` filter, and writes no unified API output or
   frontend file implicitly. Preserve the default multi-service behavior. This
   mode lets a later frontend-owned phase refresh only its own generated file;
   reject ambiguous arguments and avoid creating a second filtering contract.
4. Run the existing static shared-session verifier. Extend its focused checks only
   where a changed orchestration contract requires coverage. Shell changes require
   both `bash -n` and `shellcheck` with all warnings resolved.
5. After local prerequisites pass and the changed services are running, use
   disposable local fixtures to verify updated grants reach API authorization
   after heartbeat, deactivation invalidates a retained session on heartbeat,
   and the next protected API request fails. A retained-session fixture represents
   failed immediate bulk deletion; test actual timeout/error behavior in Phase 2's
   isolated integration tests rather than disrupting shared infrastructure.
6. Verify API calls still rely on Redis alone: read deployment/source wiring and
   demonstrate that a valid session can make an API request without issuing a
   heartbeat or a new permission-service lookup. Record validation results and
   any blocked live checks in a short orchestration-owned execution report.

### Implementation notes

Do not claim a new strict 15-minute deadline measured from deactivation commit:
in-flight authorization lookups can finish afterward. Do not weaken TLS, mesh
policies, or account checks to manufacture a passing smoke test.

The public unified API is unchanged by Phase 1's internal route. Preserve its
existing unrelated generated edits. Do not invoke the generator's default mode
from this single-workspace phase. Validate the new Session-Gateway-only mode
against a disposable path under orchestration and confirm it does not change
unified or frontend outputs. Phase 4 owns the changed Session Gateway API
snapshot in the frontend repository.

### Validation

Run `bash -n` and `shellcheck` for the changed generator and any changed shell
verifier. Run `./scripts/smoketest/verify-session-architecture.sh --static-only`,
then its documented live mode when prerequisites are satisfied, plus the focused
local scenarios above. Run `git diff --check` and check documentation links. If
a live prerequisite is unavailable, report the blocker instead of claiming live
success.

### Completion criteria

Owner documentation describes the implemented behavior accurately. Local proof
shows heartbeat is the refresh boundary and API requests retain their Redis-only
authorization path. Local/production routing remains compatible without exposing
the new internal endpoint publicly.

## Phase 4: Handle Temporary Heartbeat Failures in the Frontend

### Workspace

../budget-analyzer-web

### Goal

Make the existing heartbeat UI handle the new 503 outcome without implying that
the session was renewed or the account was deactivated.

### Scope

`useSessionHeartbeat`, its tests, authentication documentation, and the generated
Session Gateway API snapshot.

### Non-goals

Changing cadence/activity tracking, redesigning permission-state synchronization,
admin deactivation UI, cross-tab coordination, or adding new retry infrastructure.

### Required context

- `AGENTS.md`, `docs/testing-guide.md`, and `docs/authentication.md`.
- `src/hooks/useSessionHeartbeat.ts` and its existing tests.
- `src/api/auth.ts`, auth-state consumers, and `docs/api/session-gateway-api.yaml`.
- Phase 2's 200/401/503 contract and orchestration's canonical session-edge doc.

### Execution steps

1. Recognize heartbeat 503 as a temporary failure alongside the existing 502 and
   network-failure handling. Reuse the existing one-retry behavior and connection
   warning. Do not advance expiry or broadcast renewal when refresh fails.
2. Preserve 401 logout behavior, including 401 returned by the retry. Keep the
   current expiry countdown after a temporary failure and clear the warning on
   a later successful heartbeat.
3. Add focused tests for repeated 503, 503 followed by success, 503 followed by
   401, and retention of the last successful expiry without a renewal broadcast.
4. Update active heartbeat documentation/comments to describe permission-service
   revalidation and dependency failure. Link to the canonical shared contract.
   Document that existing frontend permission state updates on its normal user
   fetch; this change does not promise immediate UI synchronization of grant edits.
5. Refresh `docs/api/session-gateway-api.yaml` from the changed local service's
   generated OpenAPI by invoking Phase 3's Session-Gateway-only generator mode
   with this repository's file as its one explicit output. Confirm the command
   changes no orchestration or unified API output. Do not hand-invent a schema or
   invoke the generator's default cross-repository mode from this phase.

### Implementation notes

No new permission-expiry field or heartbeat payload is needed. The existing
connection warning already explains that the session may expire. Keep API 401
handling and ordinary server-enforced authorization as the security boundary.

### Validation

Format changed files using the repository configuration, run focused heartbeat
Vitest tests, `npm run lint:fix`, and `npm run build` as required by `AGENTS.md`.
Inspect incidental formatter/linter changes and preserve unrelated user work.
Verify the generated snapshot's 503 contract and run `git diff --check`.

### Completion criteria

The browser reports temporary heartbeat failures, preserves the true expiry, and
logs out on authoritative invalidation. Source, API snapshot, and documentation
agree with the implemented backend contract; all required checks pass.
