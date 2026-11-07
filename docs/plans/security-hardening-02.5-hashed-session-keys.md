# Security Hardening 02.5: Hashed Session Keys

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan keeps the reusable session token out of Redis key names, index
members, the append-only file and logs. Session Gateway, ext-authz and every orchestration consumer
switch to SHA-256 keys together.
Phase numbers without a plan refer to this plan.

**Order:** 02.5 of 02.1-02.8.

**Depends on:** plan 01: its Session Gateway Redis allowlist and edge verifier.

**Repositories:** session-gateway, ext-authz, orchestration.

**Merge unit:** Synchronized. Merge all three PRs together:
- The gateway writes hashed keys that only the new ext-authz can read.
- The orchestration seeders, load-test scripts and verifiers must use the same keys.

After merging, run `./scripts/ops/flush-redis.sh`. Existing raw-key sessions become unreachable.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

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
- Tilt builds sibling worktrees, so the local stack is inconsistent until every phase before the
  Live phase is complete. Those phases must not rely on a running stack.
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

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16) that lack hashed keys. The offline checks do not catch
this. Plan 05, Phase 3 records the release and pin updates, which are human-owned. No production
environment exists, so no session migration is needed.

## Contested decisions applied

- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing):
  hashing is kept (Phase 1), and key-name visibility is accepted as metadata exposure. The
  currency-service work is in plan 03.

## Phase 1: Hash session tokens in Session Gateway

### Workspace

../session-gateway

### Goal

Keep the reusable session token out of Redis key names, index members, the append-only file and
logs.

### Scope

`SessionWriter`, `SessionReader`, tests, `docs/security.md`, and `docs/session-configuration.md`.

### Non-goals

The currency-service `KEYS`/`SCAN` grant, and any change to the cookie name, which is plan 02.6.

### Required context

R2 finding A; R3 "Three fixes for finding A"; R4 "Redis: the strongest additional finding".

### Execution steps

1. Add one helper that returns the lowercase hex SHA-256 of the cookie value, and use it wherever a
   session key is built.
2. Use that digest for the `session:` key and for the `user_sessions:` member, in both
   `create-session.lua` and `conditional-update.lua` arguments and in `deleteSession`.
3. Return the raw token from `createSession` for the cookie, and never store it.
4. Log the digest prefix instead of `SafeLogger.truncateId(token)`.
5. Add a golden-vector test: a fixed token and its expected key. Phase 2 uses the same vector.
6. Add tests that the raw token appears in no Redis key or member, and that logout and bulk
   revocation still work.

### Implementation notes

- `delete-user-sessions.lua` needs no change. It builds keys from index members, which are now
  digests.
- Tokens are random UUIDs, so plain SHA-256 is right. No salt or HMAC is needed (R2, R4).
- Hashing removes the bearer value, not the enumeration. R4's point that it does not restore the ACL
  isolation claim is in the contested issues document.
- Old sessions become unreachable at cutover. That is acceptable because no production environment
  exists.

### Validation

The repository's documented build and test commands, including the Redis-backed integration tests.

### Completion criteria

Redis holds no raw token, the golden vector passes, and logout and bulk revocation work.

## Phase 2: Look up hashed session keys in ext-authz

### Workspace

../ext-authz

### Goal

Derive the Redis session key the same way Session Gateway does.

### Scope

`session.go`, tests, and `README.md`.

### Non-goals

The cookie default (plan 02.6), the lifetime cap (plan 02.4), and health endpoints and server
timeouts, which are plan 03, Phase 1.

### Required context

`session.go`; Phase 1.

### Execution steps

1. Add a small function that builds the Redis key from the lowercase hex SHA-256 of the cookie value,
   and use it in `LookupSession`. Test it with Phase 1's golden vector.
2. Note in `README.md` that a 503 from this service reaches clients as an empty 503 from the ingress.

### Implementation notes

The repository has no `session_test.go`, and `LookupSession` needs Redis, so keep the key logic in a
pure function that can be tested alone.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

The key derivation matches Session Gateway's golden vector.

## Phase 3: Wire hashed keys into orchestration

### Workspace

.

### Goal

Update every orchestration consumer of the session key, ready for the live cutover.

### Scope

`scripts/lib/`, `scripts/ops/`, `scripts/loadtest/`, the verifiers that build `session:` keys, and
the owner docs.

### Non-goals

The cookie name (plan 02.6), and `kubernetes/production` image pins.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1 and 2.

### Execution steps

1. Add a `session_key_for` helper to `scripts/lib/redis-cli.sh`, and use it in
   `seed-ext-authz-session.sh`, `verify-credential-isolation.sh` and `verify-ingress-rate-limits.sh`.
2. Update `seed-loadtest-users.sh` and `teardown-loadtest.sh` for hashed keys and index members.
3. Update `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
   `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh` and `verify-edge-contract.sh`
   where they build or inspect session keys. Add a static check that both repositories hash keys the
   same way.
4. Update the session key descriptions in `docs/architecture/session-edge-authorization-pattern.md`,
   `docs/architecture/security-architecture.md`, `SECURITY.md`, `docs/runbooks/tilt-debugging.md`,
   `docs/development/local-environment.md` and `docs/architecture/deployment-architecture-gcp.md`.

### Implementation notes

- `teardown-loadtest.sh` finds sessions with `--scan --pattern "session:loadtest_*"`, which cannot
  match hashed keys and would silently leave them behind. Compute the keys from the ID range, or
  read them from the `user_sessions:` members.
- Commands that read a session by cookie value, such as `tilt-debugging.md:276` and
  `session-edge-authorization-pattern.md:346`, need the hash step.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-session-architecture.sh --static-only`.

### Completion criteria

No orchestration consumer still assumes raw session keys, and the static checks pass.

## Phase 4: Cut over to hashed keys and prove them live (Live)

### Workspace

.

### Goal

Prove on the running stack that sessions work end to end and no raw token is in Redis.

### Scope

The evidence file, and any fixes the cutover exposes in orchestration.

### Non-goals

Fixing service code. If a sibling repository is wrong, stop and report it.

### Required context

Phases 1-3.

### Execution steps

1. Confirm the running images came from the current sibling worktrees.
2. Run `./scripts/ops/flush-redis.sh` to drop raw-key sessions.
3. Run login, an API call, a heartbeat and logout.
4. Compare the session cookie with `KEYS session:*`, and search the Redis append-only file for it,
   recording only whether it was found.
5. Run the verifiers below.

### Implementation notes

Use disposable local credentials, and never record cookie or token values.

### Validation

Orchestration static gate, `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
`verify-ingress-rate-limits.sh`, `verify-credential-isolation.sh` and
`verify-edge-contract.sh --inject-failures`. The flag runs the authorizer-down, hang and
Redis-stopped cases against the new ext-authz session lookup.

### Completion criteria

Session Gateway, ext-authz and the verifiers use one key derivation, no raw token is in Redis, and
the verifiers pass.
