# Security Hardening 02: Session Contract

**Status:** Draft for iteration. Do not run until D1 and D2 are settled.

This is plan 02 of five that together implement every finding from the four 2026-11-01 security
reviews that holds up against the code and that no review disputes, with the decisions in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document applied.
This plan changes the browser session contract across its owning repositories, adding OAuth
callback binding, bounded login input, an absolute session lifetime, hashed session keys, the
`__Host-` cookie, POST permission calls, POST heartbeat and logout, and an exact-Origin ingress
rule, then cuts the local stack over and proves it.
Phase numbers without a plan refer to this plan.

**Order:** 02 of 5

**Depends on:** plan 01: its mesh policy and edge verifier, the edge 503 contract, the CSP and the
Session Gateway Redis allowlist.

**Repositories:** session-gateway, permission-service, ext-authz, budget-analyzer-web,
budget-analyzer-api-tests, orchestration.

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
| D3 | OAuth correlation cookie shape | One `__Host-` cookie per login, named from a hash of `state` and cleared after its callback | This satisfies both R2 (clear the cookie) and R4 (parallel tabs), so it replaces the earlier single reusable cookie. See the contested issues document. | Superseded by contested #4 |
| D4 | `SESSION_COOKIE_DOMAIN_OVERRIDE` | Remove it | `__Host-` forbids a `Domain` attribute. No checked-in deployment sets the override. | Recommendation confirmed by contested #5 |

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
- Phases 1-14 change the session contract one repository at a time, and Tilt builds sibling
  worktrees, so the local stack is inconsistent until Phase 15. Those phases must not rely on a
  running stack.
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
(session-gateway 0.0.15, ext-authz 0.0.16). Phases 14 and 15 and plan 03, Phase 2 therefore
describe behaviour those images lack: the new cookie, hashed keys, the POST sync call and `/livez`.
The mesh policy from Phase 14 would also block the pinned Session Gateway's login call. The offline
checks catch none of this. Plan 05, Phase 3 records the release and pin updates, which are
human-owned. No production environment exists, so no dual-cookie or session migration is needed.

## Contested decisions applied

- [#1, primary CSRF control](../research/security-review-contested-issues-2026-11-02.md#1-primary-csrf-control):
  an exact-Origin ingress `DENY` plus POST heartbeat and form-POST logout, added as Phases 6, 11,
  13 and 16. Phase 10's non-goal is amended. OAuth callback binding stays a separate control.
- [#4, OAuth correlation cookie](../research/security-review-contested-issues-2026-11-02.md#4-oauth-correlation-cookie-and-atomic-consume):
  one reusable binding cookie and validate-then-`DEL == 1`, with no mandatory Lua. Phase 1 is
  amended and D3 is superseded.
- [#5, duplicate session cookies](../research/security-review-contested-issues-2026-11-02.md#5-rejecting-duplicate-session-cookies):
  `__Host-` is the main protection. Duplicate rejection is optional after the cutover and not in
  these plans. D4 is confirmed.
- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing):
  hashing is kept (Phase 4), and key-name visibility is accepted as metadata exposure. The
  currency-service work is in plan 03.
- [#10, `deleteUser`](../research/security-review-contested-issues-2026-11-02.md#10-the-unused-deleteuser-method):
  the method is removed in plan 03, Phase 8.
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

`returnUrl` handling, which is Phase 2, and CSRF policy.

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

The repository's documented build and test commands. Phase 15 proves the live behaviour.

### Completion criteria

All negative tests fail closed, and the normal and parallel-tab flows pass.

## Phase 2: Bound OAuth login input

### Workspace

../session-gateway

### Goal

Validate and cap what an anonymous login can store, shorten how long it stays, and stop building the
callback URL from request headers.

### Scope

`OAuth2ClientConfig`, `RedisAuthorizationRequestRepository`, `RedirectUrlValidator`,
`application.yml`, tests, and `docs/session-configuration.md`.

### Non-goals

Rate limits, and Redis memory settings, which are plan 04, Phase 1.

### Required context

R2 "Validate and cap `returnUrl`" and finding H; R3 on `noeviction`;
`../budget-analyzer-web/src/features/auth/utils/loginRedirect.ts`.

### Execution steps

1. In `addReturnUrlAdditionalParameter`, keep `returnUrl` only if it passes `RedirectUrlValidator`
   and is at most 2048 characters. Otherwise drop it and continue the login.
2. Remove the fallback in `saveAuthorizationRequest` that re-reads `returnUrl` from the request.
3. Tighten `RedirectUrlValidator`: reject backslashes, control characters and whitespace, and require
   a value that parses as a `java.net.URI` with no scheme or authority. Add tests for `/\evil.com`,
   an embedded tab, and a value with spaces.
4. Change the `SESSION_OAUTH2_STATE_TTL_SECONDS` default to 600.
5. Set `redirect-uri` to `${IDP_REDIRECT_URI:{baseUrl}/login/oauth2/code/{registrationId}}`, so a
   deployment can fix the URI and local non-Kubernetes runs keep working.
6. Update the docs.

### Implementation notes

- Without step 2, step 1 does nothing. When the additional parameter is absent, lines 98-109 read
  the raw query parameter and store it unchecked.
- Dropping a bad value is deliberate. The user still signs in and lands on the default page.
- The validator's parse check also closes a failure-path bug: an unparsable value that passes today
  makes `URI.create` throw in the redirect.
- R2 proposes 5-10 minutes for the OAuth state. Hosted logins with MFA can be slow, so this uses the
  upper end.
- A login-start cap does not stop anonymous growth. It only bounds each record. Plan 04, Phase 1 records the
  remaining gap.

### Validation

The repository's documented build and test commands.

### Completion criteria

An oversized or unsafe `returnUrl` is never stored, the validator matches the frontend's rejections,
and the redirect URI can be fixed by configuration.

## Phase 3: Enforce the absolute session lifetime in Session Gateway

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

## Phase 4: Hash session tokens in Session Gateway

### Workspace

../session-gateway

### Goal

Keep the reusable session token out of Redis key names, index members, the append-only file and
logs.

### Scope

`SessionWriter`, `SessionReader`, tests, `docs/security.md`, and `docs/session-configuration.md`.

### Non-goals

The currency-service `KEYS`/`SCAN` grant, and any change to the cookie name, which is Phase 5.

### Required context

R2 finding A; R3 "Three fixes for finding A"; R4 "Redis: the strongest additional finding".

### Execution steps

1. Add one helper that returns the lowercase hex SHA-256 of the cookie value, and use it wherever a
   session key is built.
2. Use that digest for the `session:` key and for the `user_sessions:` member, in both
   `create-session.lua` and `conditional-update.lua` arguments and in `deleteSession`.
3. Return the raw token from `createSession` for the cookie, and never store it.
4. Log the digest prefix instead of `SafeLogger.truncateId(token)`.
5. Add a golden-vector test: a fixed token and its expected key. Phase 9 uses the same vector.
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

## Phase 5: Move Session Gateway to the `__Host-` session cookie

### Workspace

../session-gateway

### Goal

Make `__Host-BA_SESSION` the default name, and remove the configuration that conflicts with it.

### Scope

`application.yml`, `SessionProperties`, `SessionCookieHelper`, tests, and docs.

### Non-goals

Duplicate-cookie rejection (amended per contested #5: optional after the cutover and not in these
plans).

### Required context

R2 CSRF section; R3 and R4 on `__Host-`; `docs/session-configuration.md`.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default.
2. Apply D4 by removing the Domain override, or fail at startup if it is combined with `__Host-`.
3. Fail at startup if the name starts with `__Host-` and `secure` is false.
4. Update tests and docs.

### Implementation notes

Confirm the actual `Set-Cookie` output, because browsers silently reject a malformed `__Host-`
cookie.

### Validation

The repository's documented build and test commands.

### Completion criteria

The cookie is issued with `Secure`, `Path=/` and no `Domain`, including when clearing it.

## Phase 6: Move heartbeat and logout to POST in Session Gateway

### Workspace

../session-gateway

### Goal

(added per contested #1) Stop heartbeat and logout changing state through GET.

### Scope

`SessionController`, `LogoutController`, the security configuration, tests, and docs.

### Non-goals

A CSRF token system or Fetch Metadata check in Session Gateway, and the OAuth callback, which keeps
the Phase 1 browser binding.

### Required context

Contested issue #1; Phases 3 and 5.

### Execution steps

1. Move the heartbeat to POST.
2. Accept logout as a same-origin top-level form POST to `/logout`, then a server-constructed 303
   redirect to the configured IdP logout URL.
3. Reject the old mutating GET and HEAD handlers.
4. Add tests for POST success, GET and HEAD rejection, and the 303 target.

### Implementation notes

- Changing only GET to POST does not stop a hostile form submission. Phase 16 adds the exact-Origin
  ingress check for both lanes, so Session Gateway needs no separate CSRF implementation.
- The form POST keeps navigation in the browser without adding a JSON URL response contract.

### Validation

The repository's documented build and test commands. Phase 15 proves the live behaviour.

### Completion criteria

Heartbeat and logout respond only to POST, and logout ends with a 303 to the IdP logout URL.

## Phase 7: Replace the user-sync GET in permission-service

### Workspace

../permission-service

### Goal

Make the write that happens at login an explicit POST, with personal fields out of the URL.

### Scope

`InternalPermissionController`, `PermissionServiceSecurityConfig`, tests, and docs.

### Non-goals

`deleteUser` (amended per contested #10: removed in plan 03, Phase 8), and
the read-only authorization lookup.

### Required context

R2 finding E; R3 N1 on why a GET that writes matters; R4 "Login permissions (E)".

### Execution steps

1. Add `POST /internal/v1/users/sync` with a JSON body of `idpSub`, `email` and `displayName`,
   returning the existing response.
2. Remove `GET /internal/v1/users/{idpSub}/permissions`.
3. Update `PermissionServiceSecurityConfig` to permit the POST and the authorization GET only.
4. Keep the existing behaviour for deactivated users.
5. Update tests and the controller's OpenAPI annotations.

### Implementation notes

Taking `idpSub` from the body gives the mesh one exact path to allow in Phase 14, and keeps all
three fields out of access logs and traces. The GET is removed rather than kept, because no
production environment needs a transition.

### Validation

The repository's documented build and test commands.

### Completion criteria

User sync happens only through the POST, and no personal field appears in its URL.

## Phase 8: Move the login permission call to POST with a deadline

### Workspace

../session-gateway

### Goal

Stop a slow permission-service from hanging logins, and use the new sync call.

### Scope

`PermissionServiceClient`, `PermissionServiceProperties`, `application.yml`, tests, and docs.

### Non-goals

Transport-pool tuning and the heartbeat lookup, which already has a timeout.

### Required context

R2 finding E; R4 "Login permissions (E)"; Phase 7.

### Execution steps

1. Change `fetchPermissions` to `POST /internal/v1/users/sync` with a JSON body.
2. Add `permission-service.login-timeout` from `PERMISSION_SERVICE_LOGIN_TIMEOUT`, defaulting to 5 s,
   and apply it with `.timeout()`.
3. Map timeouts and transport failures to `PermissionServiceException`, as `fetchAuthorization` does.
4. Add a test with a delayed stub: the callback redirects to `/oops` and creates no session.

### Implementation notes

R4 is right that a bare `WebClient` builder does not prove there is no connect timeout. An
operation deadline bounds the whole call either way. The existing `onErrorResume` in
`handleAuthenticationSuccess` already handles the failure.

### Validation

The repository's documented build and test commands.

### Completion criteria

A hung permission-service fails a login within the deadline, with no session created.

## Phase 9: Update ext-authz for the session contract

### Workspace

../ext-authz

### Goal

Match the new cookie default and hashed keys and, if D2 stands, reject sessions older than the cap.

### Scope

`config.go`, `session.go`, tests, and `README.md`.

### Non-goals

Health endpoints and server timeouts, which are plan 03, Phase 1.

### Required context

`session.go`; Phases 3, 4 and 5.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default to `__Host-BA_SESSION`.
2. Add a small function that builds the Redis key from the lowercase hex SHA-256 of the cookie value,
   and use it in `LookupSession`. Test it with Phase 4's golden vector.
3. If D2 stands, add `SESSION_MAX_LIFETIME_SECONDS` and parse `created_at`.
4. Treat a session past the cap as expired, using the existing 401 path.
5. Treat a missing or invalid `created_at` the same way as an invalid `expires_at`, so it fails
   closed.
6. Add table tests covering below, at and past the cap, and a missing and an invalid field.
7. Note in `README.md` that a 503 from this service reaches clients as an empty 503 from the ingress.

### Implementation notes

The repository has no `session_test.go`, and `LookupSession` needs Redis, so keep the key and
lifetime logic in pure functions that can be tested alone. `scripts/ops/seed-ext-authz-session.sh`
already writes `created_at`.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

The cookie default and key derivation match Session Gateway, and the cap fails closed.

## Phase 10: Align the frontend with the session contract

### Workspace

../budget-analyzer-web

### Goal

Confirm that a user reaching the cap gets a clear re-login, and stop trusting `returnUrl` on the
login page.

### Scope

`useSessionHeartbeat`, `InactivityWarningModal`, `LoginPage`, and `docs/authentication.md`.

### Non-goals

Other session UX changes, and moving heartbeat and logout to POST (amended
per contested #1: Phase 11).

### Required context

`docs/authentication.md`; `src/features/auth/utils/loginRedirect.ts`; Phase 3 behaviour.

### Execution steps

1. Trace what happens when `expiresAt` stops advancing and the heartbeat later returns 401.
2. Add a test for that sequence.
3. Fix the modal only if extending appears to work but does nothing.
4. In `LoginPage.tsx:30`, pass `returnUrl` to `navigate` only if `isSafeReturnUrl` accepts it, and add
   a test.
5. Update the `BA_SESSION` references in `src/api/client.ts` and `docs/authentication.md`.

### Implementation notes

The cap work may be a test and comment change only. The cookie is HttpOnly, so no code reads its
name. R2 notes that `LoginPage` is not exploitable today, because the browser refuses cross-origin
history changes. Step 4 makes that safe by construction, since `login()` already validates the same
value.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

Reaching the cap has a tested, understandable outcome, and an unsafe `returnUrl` falls back to the
default path.

## Phase 11: Move frontend heartbeat and logout callers to POST

### Workspace

../budget-analyzer-web

### Goal

(added per contested #1) Match the POST heartbeat and form-POST logout contract from Phase 6.

### Scope

`src/features/auth/hooks/useAuth.ts`, `src/components/InactivityWarningModal.tsx`,
`src/hooks/useSessionHeartbeat.ts`, a shared logout submission helper, tests, and
`docs/authentication.md`.

### Non-goals

Other session UX changes.

### Required context

Contested issue #1; Phase 6.

### Execution steps

1. Add one helper that submits a same-origin top-level form POST to `/logout`, and share it across
   all four navigation call sites.
2. Move heartbeat calls to POST.
3. Add tests, and update `docs/authentication.md`.

### Implementation notes

Keep the existing `strict-origin-when-cross-origin` referrer policy. A form POST's Origin can become
`null` under `no-referrer`, and the ingress rejects `null`.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

No caller uses GET for heartbeat or logout, and every logout uses the shared form POST helper.

## Phase 12: Update API tests for the new contract

### Workspace

../budget-analyzer-api-tests

### Goal

Keep the API tests aligned with the cookie name, the OAuth binding and the edge error contract.

### Scope

`environments/*.yaml`, unit tests that reference `BA_SESSION`, login helpers, and `AGENTS.md`.

### Non-goals

New API coverage beyond these changes.

### Required context

The repository's `AGENTS.md`; plan 01, Phase 4; Phases 1 and 5.

### Execution steps

1. Update `session_cookie_name` in the environment files and the affected tests.
2. Confirm the login helpers carry the OAuth binding cookie through the callback. Fix them if they
   rebuild requests without it.
3. Find any test that expects a JSON body on an edge 503, and align it with plan 01, Phase 4.

### Implementation notes

Do not run anything against staging or production. Those files are only updated for consistency.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and the login helper preserves the binding cookie.

## Phase 13: Send Origin and use POST heartbeat and logout in the API tests

### Workspace

../budget-analyzer-api-tests

### Goal

(added per contested #1) Keep the API tests working under the exact-Origin ingress rule and the POST
heartbeat and logout contract.

### Scope

`src/api_tests/client.py`, any heartbeat or logout helpers, and unit tests.

### Non-goals

New API coverage, and staging or production runs.

### Required context

The repository's `AGENTS.md`; contested issue #1; Phase 6.

### Execution steps

1. Have the client send the configured browser Origin on requests other than GET, HEAD and OPTIONS.
2. Use POST for heartbeat and logout.
3. Update the affected unit tests.

### Implementation notes

The Origin header is CSRF provenance, not authentication for arbitrary HTTP clients.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and unsafe requests carry the configured Origin.

## Phase 14: Wire the session contract into orchestration

### Workspace

.

### Goal

Update every orchestration consumer of the session contract, ready for the live cutover.

### Scope

`kubernetes/services/ext-authz/deployment.yaml`, `kubernetes/services/session-gateway/`,
`kubernetes/istio/authorization-policies.yaml`, `Tiltfile`, `scripts/lib/`, `scripts/ops/`,
`scripts/loadtest/`, the verifiers that reference `BA_SESSION` or `session:`, and the owner docs.

### Non-goals

Probe changes, which are plan 03, Phases 2 and 12, and `kubernetes/production` image pins.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 1-9.

### Execution steps

1. Set `SESSION_COOKIE_NAME=__Host-BA_SESSION` on ext-authz.
2. Set `SESSION_MAX_LIFETIME_SECONDS` in `configmap.yaml` and in the Tiltfile's
   `session-gateway-config`, because Tilt overrides the checked-in ConfigMap. Set it on ext-authz
   too if D2 stands.
3. Add `IDP_REDIRECT_URI` to `idp-configmap.yaml`, the Tiltfile's `session-gateway-idp-config` and
   the environment-specific list in `kubernetes/production/README.md`.
4. Change `permission-service-policy` so Session Gateway gets `POST` on
   `/permission-service/internal/v1/users/sync` and `GET` on the authorization path only.
5. Add a `session_key_for` helper to `scripts/lib/redis-cli.sh`, and use it in
   `seed-ext-authz-session.sh`, `verify-credential-isolation.sh` and `verify-ingress-rate-limits.sh`.
6. Let `seed-ext-authz-session.sh` accept optional `created_at`, roles and permissions values.
7. Update `seed-loadtest-users.sh` and `teardown-loadtest.sh` for hashed keys and index members.
8. Update `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
   `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh` and `verify-edge-contract.sh`.
   Add static checks that both repositories hash keys the same way and default to the same cookie.
9. Update `session-edge-authorization-pattern.md`, `security-architecture.md` (`:441`, `:462-467`,
   `:636-637`), `SECURITY.md`, `docs/runbooks/tilt-debugging.md`,
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

No orchestration consumer still assumes the old cookie, raw keys or the GET sync path, and the static
checks pass.

## Phase 15: Cut over the local stack and prove the session contract (Live)

### Workspace

.

### Goal

Prove on the running stack that the cookie, hashing, lifetime cap and OAuth binding work together.

### Scope

A new `scripts/smoketest/verify-oauth-browser-binding.py`, the evidence file, and any fixes the
cutover exposes in orchestration.

### Non-goals

Fixing service code. If a sibling repository is wrong, stop and report it.

### Required context

Phases 1-14; `scripts/smoketest/verify-ingress-browser-callback.py`.

### Execution steps

1. Confirm the running images came from the current sibling worktrees.
2. Run login, an API call, a heartbeat and logout. Confirm the `Set-Cookie` attributes in a browser.
3. Compare the session cookie with `KEYS session:*`, and search the Redis append-only file for it,
   recording only whether it was found.
4. Prove the cap. If D2 stands, seed a session past the cap and confirm the API rejects it. If D2 is
   dropped, use a short local maximum and a real login.
5. Add `verify-oauth-browser-binding.py`, following `verify-ingress-browser-callback.py`, which
   already drives a hosted login with separate cookie jars. Stop the browser at the callback URL
   without following it, deliver that unused callback from a second client with no binding cookie,
   and assert the login is rejected with no session. Then complete a normal login.
6. Run the verifiers below.

### Implementation notes

- Old `BA_SESSION` cookies in local browsers become inert. No compatibility path is needed.
- Do not use a seeded session to test the heartbeat cap. The seeded user does not exist in
  permission-service, so the heartbeat returns 401 regardless. Phase 3's integration tests cover it.
- The callback in step 5 must be unused. Replaying a consumed one fails on single use and proves
  nothing about the binding.
- Use disposable local credentials, and never record cookie or token values.

### Validation

Orchestration static gate, `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
`verify-ingress-rate-limits.sh`, `verify-credential-isolation.sh`, `verify-edge-contract.sh` and
`verify-oauth-browser-binding.py`.

### Completion criteria

Session Gateway, ext-authz, verifiers and docs all use one contract, no raw token is in Redis, the
cap holds live, and a callback without its binding is rejected live.

## Phase 16: Require exact Origin on unsafe requests at the ingress (Live)

### Workspace

.

### Goal

(added per contested #1) Deny unsafe browser requests from any origin other than the application's
own, on both ingress lanes.

### Scope

A new ingress AuthorizationPolicy under `kubernetes/istio/`, `verify-edge-contract.sh`, a static
guardrail, orchestration scripts that send unsafe requests through the ingress,
`docs/architecture/security-architecture.md` (CSRF row), and
`docs/architecture/session-edge-authorization-pattern.md`.

### Non-goals

Fetch Metadata, CSRF tokens, and checks in ext-authz or Session Gateway.

### Required context

Contested issue #1; plan 01, Phase 5; Phases 6, 11, 13 and 15.

### Execution steps

1. Add one native ingress `DENY` AuthorizationPolicy covering both lanes and scoped to the HTTP
   application listener. It denies methods other than GET, HEAD and OPTIONS unless Origin equals the
   configured serialized browser origin (scheme, host and effective port).
2. Reject absent, empty, `null`, foreign or multi-valued Origin. Do not accept suffix matches or
   derive the trusted value from caller-controlled forwarding headers. Fetch Metadata must not
   provide an exception.
3. Prove rejection of missing, empty, `null` and foreign Origin in the generated configuration and in
   live local requests, plus success for the configured origin on both lanes. Add these as an
   "Origin" section in `verify-edge-contract.sh`.
4. Verify login, logout, hostile same-site and cross-site submissions, and absence of mutation on
   rejected requests with the final CSP. Check `form-action` redirect enforcement in supported
   browsers.
5. Add a static guardrail for the policy, and update the CSRF row and the edge contract docs.
   (amended per contested A2) In those docs, state the configured `Strict` session-cookie default
   and its same-site limit: it does not stop same-site requests, and top-level cookie deletion
   remains possible. Record the observed browser effects from step 4 in the evidence file.

### Implementation notes

- A permissive `ALLOW` rule is not a substitute, because other ALLOW policies are additive.
- This design depends on the existing mesh restrictions preventing browser access around the
  ingress. Internal workload calls use their own caller and path policy.
- The current OAuth GET callback relies on the Phase 1 browser binding. A future POST callback needs
  an explicit contract change.
- Orchestration verifiers and load-test scripts that send unsafe requests through the ingress must
  supply the configured Origin, as the API-test client does.
- Apply the `kind-kind` checks.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh`,
`./scripts/smoketest/verify-session-architecture.sh`, and a browser login and logout.

### Completion criteria

Every unsafe request without the exact Origin is denied on both lanes with no mutation, the
configured origin succeeds, and login and logout work under the final CSP.
