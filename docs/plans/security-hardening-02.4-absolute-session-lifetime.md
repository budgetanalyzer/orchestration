# Security Hardening 02.4: Absolute Session Lifetime

**Status:** Ready to run. D1 and D2 are settled.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan stops heartbeats renewing a session past a fixed maximum lifetime,
confirms that users at the cap get a clear re-login, and proves the cap live. ext-authz does not
re-check the cap (D2).
Phase numbers without a plan refer to this plan.

**Order:** 02.4 of 02.1-02.8.

**Depends on:** plan 01.

**Repositories:** session-gateway, budget-analyzer-web, orchestration.

**Merge unit:** Ordered.
- The session-gateway and budget-analyzer-web PRs are each safe on their own and may merge first:
  - The gateway's default cap applies without configuration. Phase 1 confirms the default is not
    below orchestration's `SESSION_TTL_SECONDS`.
  - The frontend change is a test, a comment or a modal fix.
- The orchestration PR is safe on its own after the gateway.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Decisions

| # | Decision | Outcome | Why | Status |
| --- | --- | --- | --- | --- |
| D1 | Absolute session lifetime | `SESSION_MAX_LIFETIME_SECONDS=28800` (8 hours), also the Session Gateway default | No review names a value. 8 hours matches the Auth0 tenant's Maximum Session Lifetime (480 minutes, non-persistent default policy), so the gateway does not allow more than the tenant config states. The Auth0 idle lifetime is 15 minutes, and nothing after login renews it, because heartbeats and API calls never reach Auth0. A user at the cap therefore always gets a real Auth0 login prompt, without `max_age` or `prompt=login`. | Settled 2026-11-07 |
| D2 | Should ext-authz re-check the cap? | No. R2, R3 and R4 proposed it. | ext-authz already rejects a passed `expires_at`, so the Session Gateway cap is enforced transitively. A re-check only guards against a Session Gateway renewal bug, which Phase 1's tests cover, and it would add a shared setting, a coupled ext-authz and orchestration merge, and a fail-closed `created_at` contract for every session seeder. | Settled 2026-11-07 |

## Plan-wide rules

- No staging or production access, no certificate generation, and no git write operations unless
  the user asks.
- (added per user direction) No production environment or production data exists. Discarding
  local state is acceptable: sessions, Redis keys, OAuth state, database contents and broker
  volumes. Do not write migration, dual-format or backward-compatibility code. Reset instead,
  with `./scripts/ops/flush-redis.sh`, `scripts/ops/reset-databases.sh` or by recreating the
  volume, and document any reset an existing local cluster needs.
- Each phase works in its declared workspace only. Follow that repository's `AGENTS.md`.
- Treat review claims as leads. Re-check them against the code before relying on them.
- Before any cluster mutation, apply the `kind-kind` checks in the orchestration `AGENTS.md`.
- Phases marked **Live** need a running stack. In orchestration phases, run
  `./scripts/bootstrap/check-local-runtime.sh` and `tilt up`. If the stack cannot be started, stop
  and report; do not substitute static evidence.
- Tilt builds sibling worktrees, so the local stack may be inconsistent until every phase before
  the Live phase is complete. Those phases must not rely on a running stack.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Do not edit this plan during a run, because the runner stops launching phases when it changes.
- Record measurements and results in `docs/research/security-consensus-hardening-evidence.md`. A
  phase in a sibling repository records them in that repository's `docs/` folder, and plan 05,
  Phase 3 collects the links.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

## Phase 1: Enforce the absolute session lifetime in Session Gateway

### Workspace

../session-gateway

### Goal

Stop heartbeats from renewing a session past its creation time plus D1.

### Scope

`SessionProperties`, `SessionWriter`, `SessionController`, `conditional-update.lua`, tests, and
`docs/session-configuration.md`.

### Non-goals

Reauthentication or step-up policy, and account-wide revocation changes.

### Required context

R1 finding 4; R4 on what a cap does not guarantee; `../session-gateway/src/main/resources/redis/`.

### Execution steps

1. Add `session.max-lifetime-seconds` from `SESSION_MAX_LIFETIME_SECONDS`, defaulting to `28800`
   (D1), and fail at startup if it is less than `session.ttl-seconds`.
2. In `updateSession`, compute the new expiry as the earlier of now plus TTL and `created_at` plus
   the maximum. Write the remaining seconds as the TTL.
3. When no lifetime remains, delete the session and return the existing 401 with a cleared cookie.
4. Preserve the permission refresh on every heartbeat.
5. In `conditional-update.lua`, stop a capped refresh from shortening the shared index. Use
   `EXPIRE ... GT` when the index exists, and plain `EXPIRE` when `index_type` was `none`.
6. Add a regression test. A user has sessions A and B, A refreshes near its cap, and the index
   outlives B, so bulk revocation still deletes B.
7. (added in the split) Confirm the default maximum is not below the `SESSION_TTL_SECONDS` that
   `../orchestration/kubernetes/services/session-gateway/configmap.yaml` and the orchestration
   Tiltfile set, so this change starts in Tilt without new configuration.

### Implementation notes

- This trap is not in any review. Today every refresh passes the same TTL, so the index expiry only
  moves forward. A capped TTL would shorten the shared index, leaving a live session outside bulk
  revocation.
- `GT` alone is also wrong. Redis treats a key with no TTL as infinite, so `GT` would not set a TTL
  on an index that `SADD` has just recreated. That key would never expire.

### Validation

The repository's documented build and test commands, including the Redis-backed integration tests.

### Completion criteria

Renewal cannot pass the cap, the two-session regression test passes, and heartbeat refresh is
unchanged below the cap.

## Phase 2: Give users at the cap a clear re-login

### Workspace

../budget-analyzer-web

### Goal

Confirm that a user reaching the cap gets a clear re-login.

### Scope

`useSessionHeartbeat`, `InactivityWarningModal`, and `docs/authentication.md`.

### Non-goals

Other session UX changes, `returnUrl` handling (plan 02.2), cookie-name references (plan 02.6), and
moving heartbeat and logout to POST (plan 02.7).

### Required context

`docs/authentication.md`; Phase 1 behaviour.

### Execution steps

1. Trace what happens when `expiresAt` stops advancing and the heartbeat later returns 401.
2. Add a test for that sequence.
3. Fix the modal only if extending appears to work but does nothing.
4. Update the docs.

### Implementation notes

- The cap work may be a test and comment change only.
- Re-login needs no forced re-authentication. With the D1 Auth0 settings, the Auth0 session has
  expired by the time a user reaches the cap, so the login redirect prompts for credentials.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

Reaching the cap has a tested, understandable outcome.

## Phase 3: Configure the cap and prove it live (Live)

### Workspace

.

### Goal

Set the lifetime in every orchestration consumer and prove the cap holds on the running stack.

### Scope

`kubernetes/services/session-gateway/configmap.yaml`, the Tiltfile's `session-gateway-config`, the
owner docs, and the evidence file.

### Non-goals

`kubernetes/production` image pins, ext-authz changes (D2), and fixing service code. If a sibling
repository is wrong, stop and report it.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1-2.

### Execution steps

1. Set `SESSION_MAX_LIFETIME_SECONDS` to `"28800"` (D1) in `configmap.yaml` and in the Tiltfile's
   `session-gateway-config`, because Tilt overrides the checked-in ConfigMap.
2. Confirm the running images came from the current sibling worktrees.
3. Prove the cap with a temporarily short local maximum and a real login. Restore `28800`
   afterwards, and do not leave the short value in any checked-in file.
4. Update the absolute-expiration description in `docs/architecture/security-architecture.md` and
   the session lifetime description in `docs/architecture/session-edge-authorization-pattern.md`,
   and record the results.

### Implementation notes

- Do not use a seeded session to test the heartbeat cap. The seeded user does not exist in
  permission-service, so the heartbeat returns 401 regardless. Phase 1's integration tests cover it.
- Use disposable local credentials, and never record cookie or token values.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-session-architecture.sh` and
`./scripts/smoketest/verify-edge-contract.sh`.

### Completion criteria

The cap is configured in every consumer and holds live, and the docs describe it.
