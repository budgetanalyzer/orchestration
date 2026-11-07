# Security Hardening 02.4: Absolute Session Lifetime

**Status:** Draft for iteration. Do not run until D1 and D2 are settled.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan stops heartbeats renewing a session past a fixed maximum lifetime.
Depending on D2, ext-authz also enforces the cap. The plan confirms that users at the cap get a clear
re-login, and proves the cap live.
Phase numbers without a plan refer to this plan.

**Order:** 02.4 of 02.1-02.8.

**Depends on:** plan 01.

**Repositories:** session-gateway, budget-analyzer-web, ext-authz (only if D2 stands),
orchestration.

**Merge unit:** Ordered.
- The session-gateway and budget-analyzer-web PRs are each safe on their own and may merge first:
  - The gateway's default cap applies without configuration. Phase 1 confirms the default is not
    below orchestration's `SESSION_TTL_SECONDS`.
  - The frontend change is a test, a comment or a modal fix.
- The ext-authz and orchestration PRs merge together. With D2, ext-authz rejects sessions that
  lack `created_at`, and orchestration supplies the setting and the seeders.
- If D2 is dropped, the orchestration PR is safe on its own after the gateway.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Decisions

| # | Decision | Recommendation | Why it matters | Status |
| --- | --- | --- | --- | --- |
| D1 | Absolute session lifetime | `SESSION_MAX_LIFETIME_SECONDS=43200` (12 hours) | No review names a value. This is a usability and risk choice. | Open |
| D2 | Should ext-authz re-check the cap? | Yes, as R2, R3 and R4 propose, but it is optional | ext-authz already rejects a passed `expires_at`, so a Session Gateway cap is enforced transitively. The re-check only guards against a Session Gateway renewal bug, at the cost of one more shared setting. | Open |

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

1. Add `session.max-lifetime-seconds` from `SESSION_MAX_LIFETIME_SECONDS`, and fail at startup if it
   is less than `session.ttl-seconds`.
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

The cap work may be a test and comment change only.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

Reaching the cap has a tested, understandable outcome.

## Phase 3: Re-check the cap in ext-authz

### Workspace

../ext-authz

### Goal

If D2 stands, reject sessions older than the cap.

### Scope

`config.go`, `session.go`, tests, and `README.md`.

### Non-goals

The cookie default (plan 02.6), hashed keys (plan 02.5), and health endpoints and server timeouts,
which are plan 03, Phase 1.

### Required context

`session.go`; Phase 1.

### Execution steps

1. If D2 was dropped, make no change, report that, and stop.
2. Add `SESSION_MAX_LIFETIME_SECONDS` and parse `created_at`.
3. Treat a session past the cap as expired, using the existing 401 path.
4. Treat a missing or invalid `created_at` the same way as an invalid `expires_at`, so it fails
   closed.
5. Add table tests covering below, at and past the cap, and a missing and an invalid field.
6. Document the setting in `README.md`.

### Implementation notes

The repository has no `session_test.go`, and `LookupSession` needs Redis, so keep the lifetime
logic in pure functions that can be tested alone. `scripts/ops/seed-ext-authz-session.sh` in
orchestration already writes `created_at`.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

If D2 stands, the cap fails closed, including for a missing or invalid `created_at`.

## Phase 4: Configure the cap and prove it live (Live)

### Workspace

.

### Goal

Set the lifetime in every orchestration consumer and prove the cap holds on the running stack.

### Scope

`kubernetes/services/session-gateway/configmap.yaml`, the Tiltfile's `session-gateway-config`,
`kubernetes/services/ext-authz/deployment.yaml` if D2 stands, `scripts/ops/`, the owner docs, and the
evidence file.

### Non-goals

`kubernetes/production` image pins, and fixing service code. If a sibling repository is wrong, stop
and report it.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1-3.

### Execution steps

1. Set `SESSION_MAX_LIFETIME_SECONDS` in `configmap.yaml` and in the Tiltfile's
   `session-gateway-config`, because Tilt overrides the checked-in ConfigMap. Set it on ext-authz
   too if D2 stands.
2. Let `seed-ext-authz-session.sh` accept optional `created_at`, roles and permissions values.
3. (added in the split) If D2 stands, confirm every orchestration script that seeds sessions,
   including `seed-loadtest-users.sh`, writes a valid `created_at`.
4. Confirm the running images came from the current sibling worktrees.
5. Prove the cap. If D2 stands, seed a session past the cap and confirm the API rejects it. If D2 is
   dropped, use a short local maximum and a real login.
6. Update the absolute-expiration description in `docs/architecture/security-architecture.md` and
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
