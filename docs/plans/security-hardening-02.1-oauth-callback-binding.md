# Security Hardening 02.1: OAuth Callback Binding

**Status:** Draft for iteration.

Plan 02 is split into plans 02.1-02.8. Each one is a unit you can merge on its own and leaves Tilt
and the architecture working. Together they apply plan 02's share of the four 2026-11-01 security
reviews, with the [contested issues](../research/security-review-contested-issues-2026-11-02.md)
decisions applied. This plan binds each OAuth callback to the browser that started the login,
keeps the API-test login helpers working, and proves the binding live.
Phase numbers without a plan refer to this plan.

**Order:** 02.1 of 02.1-02.8. Run the 02.x plans in numeric order unless a plan says otherwise.

**Depends on:** plan 01: its mesh policy and edge verifier, the edge 503 contract, the CSP and the
Session Gateway Redis allowlist.

**Repositories:** session-gateway, budget-analyzer-api-tests, orchestration.

**Merge unit:** Ordered. Each PR is safe on its own if merged in this order:
1. budget-analyzer-api-tests, if Phase 2 changes it. Carrying an extra cookie is harmless to
   today's gateway.
2. session-gateway.
3. orchestration. Its new verifier fails against the old gateway.

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
| D3 | OAuth correlation cookie shape | One `__Host-` cookie per login, named from a hash of `state` and cleared after its callback | This satisfies both R2 (clear the cookie) and R4 (parallel tabs), so it replaces the earlier single reusable cookie. See the contested issues document. | Superseded by contested #4 |

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

## Contested decisions applied

- [#4, OAuth correlation cookie](../research/security-review-contested-issues-2026-11-02.md#4-oauth-correlation-cookie-and-atomic-consume):
  one reusable binding cookie and validate-then-`DEL == 1`, with no mandatory Lua. Phase 1 is
  amended and D3 is superseded.
- [#1, primary CSRF control](../research/security-review-contested-issues-2026-11-02.md#1-primary-csrf-control):
  OAuth callback binding stays a separate control from the CSRF work in plans 02.7 and 02.8.
- [Work order](../research/security-review-contested-issues-2026-11-02.md#work-order): handle
  browser binding, token exposure and CSRF promptly across their owning repositories.

## Phase 1: Bind OAuth callbacks to the initiating browser

### Workspace

../session-gateway

### Goal

Ensure a callback can only complete in the browser that started the login.

### Scope

`RedisAuthorizationRequestRepository`, its tests, and `docs/security.md`.

### Non-goals

`returnUrl` handling, which is plan 02.2, and CSRF policy.

### Required context

R1 finding 1; R2's cookie requirements; R4's test list; [RFC 9700 section 2.1.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1).

### Execution steps

1. Confirm the callback is a top-level GET (`response_mode` is not `form_post`).
2. (amended per contested #4) On login start, reuse a valid high-entropy random binding cookie, or
   generate one if absent. Set it as a `__Host-` cookie with `Secure`, `HttpOnly`, `Path=/`,
   `SameSite=Lax`, no `Domain`, and browser-session lifetime. It must not be the session token or
   be derivable from state.
3. Store only a hash of the binding in the Redis transaction.
4. (amended per contested #4) On callback, read the record, validate the browser-binding hash in
   constant time, then delete that exact state key. Return the authorization request and set
   callback attributes only if `DEL` returns 1; zero or a Redis error fails closed. Do this before
   code exchange or session issuance, including the denial/error callback path. A wrong or missing
   cookie must never reach deletion.
5. (amended per contested #4) Keep the binding cookie across
   callbacks instead of clearing or rotating it for each login; that preserves pending tabs.
6. Change the test at `SecurityConfigIntegrationTest.java:107`, which completes a callback with no
   cookie, and add tests for missing cookie, wrong cookie, browser B completing browser A's login,
   replay, expiry and parallel tabs. (amended per contested #4) Also cover wrong or missing binding
   without record loss, competing callbacks, expiry between read and delete, denial/error callbacks,
   and both kinds of parallel start: tabs sharing an existing cookie, and simultaneous first starts.

### Implementation notes

- `Strict` would fail every login, because the callback is a cross-site navigation.
- `__Host-` is required, or a sibling subdomain could plant its own binding.
- A plain `MULTI` around an earlier read is not atomic (R4). (amended per contested
  #4) No Lua is required. `DEL` returns the number of keys removed, so validate-then-`DEL == 1` has
  one winner provided each random state key is immutable and never reused or recreated. Keep these
  records write-once, including their binding. If records can be replaced, use atomic
  compare-and-delete instead.
- (amended per contested #4) Validating before deleting means a wrong or missing cookie leaves the
  record intact; only a successful `DEL` consumes it.
- (amended per contested #4) One reusable cookie needs no per-tab naming, counting or eviction.
  Cookie loss invalidates pending callbacks. Simultaneous first starts can set different bindings;
  the one that wins cookie storage succeeds and the other fails closed with a fresh-login retry.
  Accept that race. One cookie does not bound pending Redis records, so keep the state TTL, rate
  and capacity controls. This cookie alone never authenticates an application request.
- (amended per contested #4) Single-consumer deletion is required, not optional hygiene. IdP
  single-use codes do not replace browser binding.
- Any new Lua command must be in the plan 01, Phase 6 allowlist.

### Validation

The repository's documented build and test commands. Phase 3 proves the live behaviour.

### Completion criteria

All negative tests fail closed, and the normal and parallel-tab flows pass.

## Phase 2: Carry the binding cookie in the API-test login helpers

### Workspace

../budget-analyzer-api-tests

### Goal

Keep API-test logins working once the callback requires the browser binding cookie.

### Scope

Login helpers and their unit tests.

### Non-goals

The session cookie name and the edge 503 contract (plan 02.6), POST heartbeat and logout (plan
02.7), the Origin header (plan 02.8), and new API coverage.

### Required context

The repository's `AGENTS.md`; Phase 1.

### Execution steps

1. Confirm the login helpers carry the OAuth binding cookie through the callback. Fix them if they
   rebuild requests without it.
2. Add or update a unit test showing the helper keeps cookies set at login start for the callback.

### Implementation notes

Do not run anything against staging or production. If the helpers already preserve cookies, this
phase changes only tests and there may be no PR.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and the login helper preserves the binding cookie.

## Phase 3: Prove OAuth callback binding live (Live)

### Workspace

.

### Goal

Prove on the running stack that a callback without its binding is rejected and that existing login
flows still work.

### Scope

A new `scripts/smoketest/verify-oauth-browser-binding.py`, its `scripts/README.md` entry, the
OAuth callback description in `docs/architecture/session-edge-authorization-pattern.md` and
`docs/architecture/security-architecture.md`, the evidence file, and any fixes the cutover exposes
in orchestration.

### Non-goals

Fixing service code. If a sibling repository is wrong, stop and report it.

### Required context

Phases 1 and 2; `scripts/smoketest/verify-ingress-browser-callback.py`.

### Execution steps

1. Confirm the running Session Gateway image came from the current sibling worktree.
2. Add `verify-oauth-browser-binding.py`, following `verify-ingress-browser-callback.py`, which
   already drives a hosted login with separate cookie jars. Stop the browser at the callback URL
   without following it, deliver that unused callback from a second client with no binding cookie,
   and assert the login is rejected with no session. Then complete a normal login.
3. (added in the split) Confirm the existing login-driving verifiers still pass with the binding in
   place.
4. Update the docs in scope and record the results.

### Implementation notes

- The callback in step 2 must be unused. Replaying a consumed one fails on single use and proves
  nothing about the binding.
- Use disposable local credentials, and never record cookie or token values.

### Validation

Orchestration static gate, `verify-oauth-browser-binding.py`,
`verify-ingress-browser-callback.py` and `./scripts/smoketest/verify-session-architecture.sh`.

### Completion criteria

A callback without its binding is rejected live with no session, a normal login succeeds, and the
existing login verifiers pass.
