# Security Review Consensus Hardening Plan

**Status:** Draft for iteration. Do not run until the decisions below are settled.

This plan implements only the fixes that all four 2026-11-01 security reviews endorse. It leaves
severity ratings and contested remedies for a follow-up plan.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Inclusion rule

An item is in scope only when all four reviews explicitly endorse the same fix direction. A
disagreement over severity does not exclude an item. A disagreement over the remedy excludes the
contested part.

| # | Consensus fix | R1 | R2 | R3 | R4 | Phases |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Narrow mesh policies to the callers' real paths | Arch | Agree | Agree | Agree | 1 |
| 2 | Strip `Cookie` and `Authorization` before backends | F3 | Agree | Agree | Agree | 2 |
| 3 | Replace Session Gateway `+@all` and its literal verifier | F2 | Agree | Agree | Agree | 3 |
| 4 | Reconcile the five documented mismatches and the communication guide | Table | Agree | Agree | Agree | 4 |
| 5 | Set an explicit Redis memory budget; no `allkeys-lru` on auth data | F8 | Agree | Agree | Agree | 5 |
| 6 | Bind OAuth callbacks to the initiating browser | F1 | Agree | Agree | Agree | 6, 16 |
| 7 | Enforce an absolute session lifetime | F4 | Agree | Agree | Agree | 7, 9, 10, 12 |
| 8 | Adopt the `__Host-` session cookie | F5 ("consider") | Required | Agree | Agree | 8, 9, 11, 12 |
| 9 | Separate liveness from readiness | F7 | Agree | Agree | Agree | 13-18 |
| 10 | Turn body logging and TRACE off by default in all four services | F6 | Agree | Agree | Agree | 14-17 |

Item 8 has the weakest consensus because R1 only says "consider". R2 scoped item 10 to three
services; R3 and R4 corrected that to four, and the code matches them.

All four also agree on what not to do now: keep server-side sessions, keep the topology, do not
treat Redis Cluster as a drop-in replacement, and leave recovery objectives and vulnerability-gating
policy until hosted use is planned.

## Decisions to settle before running

| # | Decision | Recommendation | Why it matters |
| --- | --- | --- | --- |
| D1 | Absolute session lifetime | `SESSION_MAX_LIFETIME_SECONDS=43200` (12 hours) | No review names a value. This is a usability and risk choice. |
| D2 | Should ext-authz re-check the cap? | Yes, as R2, R3 and R4 propose, but it is optional | ext-authz already rejects a passed `expires_at`, so a Session Gateway cap is enforced transitively. The re-check only guards against a Session Gateway renewal bug, at the cost of one more shared setting. |
| D3 | OAuth correlation cookie shape | One browser-scoped `__Host-` binding, reused while valid and expired by `Max-Age` | R2 wants the cookie cleared after the callback; R4 requires parallel login tabs to work. A single cookie cannot satisfy both, so this keeps parallel tabs. Each transaction is still single-use. |
| D4 | `SESSION_COOKIE_DOMAIN_OVERRIDE` | Remove it | `__Host-` forbids a `Domain` attribute. No checked-in deployment sets the override. |
| D5 | Scope of this plan | Promote hash-keyed sessions and ext_authz status/timeout | They are excluded only because R1 predates them. See the next section. |

## Excluded from this plan

**Uncontested, but not endorsed by all four.** These are the first candidates to promote:

- Hash session tokens in session keys and index members (R2, R3, R4; R1 predates the finding). If
  promoted, do it with phases 7-12, which already change the same Session Gateway and ext-authz
  code and contract.
- Set ext_authz `statusOnError: "503"` and a bounded timeout (R2, R3, R4). Whether to change the
  documented JSON 503 body or add a local reply is still open.
- Add cross-layer edge-contract tests (R2, R3, R4). Phases 1-3 add the first slices.
- Add a login permission-call deadline and move user sync off GET (R2, R3, R4).
- Move to a supported RabbitMQ series (R2, R3, R4).
- Add a coverage rule for endpoint authorization (R2, R3, R4).
- Add a forged-header test for zero-permission users (R2, R3, R4).
- Use the trusted client address, not the first `X-Forwarded-For` entry (R1, R2, R4).
- Add structured audit events (R1, R2).
- Cap `returnUrl` and shorten the OAuth-state lifetime (R2, R3).
- Bound PDF parsing (R2, R3, R4; the mechanism is disputed).
- Add HSTS at the ingress (R2, R3, R4; `includeSubDomains` and preload are disputed).

**Contested, to untangle next:**

- Primary CSRF control, missing-header behaviour, and the value of moving heartbeat and logout to
  POST.
- Whether and where to reject `;` (R2 at the ingress, R3 at NGINX, R4 says a literal match is not
  enough proof).
- Removing `KEYS`/`SCAN`, using a versioned cache prefix, or splitting Redis, and in what order.
- Rejecting duplicate session cookies after the `__Host-` rename.
- Signed identity, separate internal ports, a PDF worker, and `ISTIO_MUTUAL` egress.
- Severity ratings, which this plan deliberately does not settle.

## Plan-wide rules

- No staging or production access, no certificate generation, and no git write operations unless
  the user asks.
- Each phase works in its declared workspace only. Follow that repository's `AGENTS.md`.
- Treat review claims as leads. Re-check them against the code before relying on them.
- Before any cluster mutation, apply the `kind-kind` checks in the orchestration `AGENTS.md`.
- Phases marked **Live** need a running stack. Run `./scripts/bootstrap/check-local-runtime.sh` and
  `tilt up`. If the stack cannot be started, stop and report; do not substitute static evidence.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Do not edit this plan during a run, because the runner stops launching phases when it changes.
  Record measurements and results in `docs/research/security-consensus-hardening-evidence.md`.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16). Phases 12 and 18 can therefore describe behaviour those
images lack, such as `/livez`, and the offline checks will not catch it. Phase 19 records the
release and pin updates, which are human-owned. No production environment exists, so no
dual-cookie or session migration is needed.

## Phase 1: Narrow mesh policies and prove the public/internal boundary (Live)

### Workspace

.

### Goal

Limit each mesh caller to the paths it needs, and settle R3's encoded-path finding with evidence
from the real chain.

### Scope

`kubernetes/istio/authorization-policies.yaml`, `scripts/smoketest/verify-istio-ingress.sh`, a
static guardrail, and the nearest architecture docs.

### Non-goals

No `;` rejection at NGINX or the ingress, no separate ports, and no service code.

### Required context

R3 finding N1; R2 "Narrow mesh permissions"; `docs/architecture/security-architecture.md`;
`docs/architecture/session-edge-authorization-pattern.md`.

### Execution steps

1. Capture a baseline before changing anything. Seed a session with
   `scripts/ops/seed-ext-authz-session.sh` and request each traversal below with
   `curl --path-as-is`, using the `%3b`, `%3B` and `%2e%2e%3b` forms:
   - `/api/v1/users/..%3b/..%3b/internal/v1/users/<id>/authorization`
   - `/api/v1/users/..%3b/..%3b/actuator/prometheus`
   - `/api/v1/transactions/..%3b/..%3b/actuator/prometheus`
   - `/api/v1/currencies/..%3b/..%3b/actuator/prometheus`
2. Record the baseline in the evidence file. R3 tested only the `users` chain against a stand-in,
   and R4 did not reproduce it, so this is the first real measurement.
3. Add `to.operation` limits to the NGINX rules:
   - transaction-service: `/transaction-service/v1/*`, `/transaction-service/v3/api-docs`
   - currency-service: `/currency-service/v1/*`, `/currency-service/v3/api-docs`
   - permission-service: `/permission-service/v1/*`
4. Split `permission-service-policy` so Session Gateway gets `GET` on only
   `/permission-service/internal/v1/users/{*}/permissions` and
   `/permission-service/internal/v1/users/{*}/authorization`.
5. Limit the ingress rule on `session-gateway-policy` to the `auth-route` surface: `/oauth2/*`,
   `/login/oauth2/*`, `/logout`, `/logout/*`, `/auth/*`. Keep the existing permission-service rule.
6. Add a "Public/Internal Boundary" section to `verify-istio-ingress.sh` that repeats step 1 and
   also asserts that a legitimate public route and login start still work.
7. Add a static guardrail that fails if a backend policy's NGINX rule has no `to` restriction.

### Implementation notes

- Never use the `.../permissions` endpoint as a probe. It is a GET that writes through `syncUser`.
- `/v1/*` matches today's public surface: the only `/v1` controllers in these three services are
  the ones NGINX exposes. A future non-public `/v1` route would need a narrower rule.
- `scripts/repo/generate-unified-api-docs.sh` reaches specs through `kubectl exec` to loopback, so
  the api-docs allowances are only for the NGINX routes.
- Assert "not 200" rather than a specific denial, so a later `;` rejection does not break the test.
- The Prometheus policy is separate and must remain unchanged.
- If the baseline shows the traversal is already blocked, record that and continue. Narrowing is
  independently agreed.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-istio-ingress.sh`, and
`./scripts/smoketest/verify-session-architecture.sh`. Confirm login, a heartbeat and a permission
lookup work end to end.

### Completion criteria

Every traversal returns non-200, every legitimate path still works, and before and after results
are in the evidence file.

## Phase 2: Strip browser credentials at NGINX

### Workspace

.

### Goal

Stop forwarding the reusable session cookie and unused authorization headers to business services.

### Scope

`nginx/includes/backend-headers.conf`, its verification, and the nearest docs.

### Non-goals

Frontend lanes that do not use this include, and the direct Session Gateway auth lane.

### Required context

R1 finding 3; `nginx/README.md`; `docs/architecture/session-edge-authorization-pattern.md`.

### Execution steps

1. Add `proxy_set_header Cookie "";` and `proxy_set_header Authorization "";` to the include, with
   a short comment explaining that ext_authz has already consumed the cookie at the ingress.
2. Confirm every API location in both NGINX configs still uses the include.
3. Prove stripping with a disposable pinned NGINX container, the shared include and an echo
   upstream. Record header names only.
4. Add a static assertion for both directives.

### Implementation notes

- The `p3-header-echo` fixture in `verify-istio-ingress.sh` routes straight from an `HTTPRoute`, so
  it bypasses NGINX and cannot prove this change.
- A search of the three business services and service-common found no reads of either header.
- The planned M2M lane validates bearer tokens at the ingress, so this does not conflict with it.

### Validation

Orchestration static gate, `kubectl exec deployment/nginx-gateway -- nginx -t`, and the stand-in
test from step 3. If the stack is running, also confirm an authenticated `/api/v1/transactions`
request still succeeds.

### Completion criteria

The echo upstream receives neither header, identity headers still arrive, and ext_authz still
authorizes requests.

## Phase 3: Replace the Session Gateway Redis `+@all` grant (Live)

### Workspace

.

### Goal

Give Session Gateway only the Redis commands it uses, and replace the verifier that locks in the
over-grant.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, `scripts/smoketest/verify-session-architecture.sh`,
`scripts/smoketest/verify-credential-isolation.sh`, and the nearest docs.

### Non-goals

The currency-service `+keys +scan` grant, which is contested, and any Redis split.

### Required context

R1 finding 2; R3 and R4 on `ACL DRYRUN`; `../session-gateway/src/main/resources/redis/`.

### Execution steps

1. Start from the commands in the code: `hset`, `hgetall`, `expire`, `del`, `sadd`, `smembers`,
   `type`, `evalsha`, `eval`, plus connection commands.
2. Derive the final list from `ACL LOG` across a cold start, script load, login, heartbeat refresh,
   logout, bulk revocation, and OAuth failure and expiry paths. One successful login is not enough.
3. Replace `+@all`. Drop `&*` if the final list has no pub/sub commands.
4. Replace the literal assertion at `verify-session-architecture.sh:565` with a check that the
   Session Gateway line has no `+@all`.
5. Add negative `ACL DRYRUN` checks to `verify-credential-isolation.sh` for `FLUSHALL`, `FLUSHDB`,
   `CONFIG`, `SHUTDOWN`, `REPLICAOF` and `ACL`, and positive checks for the allowed commands.

### Implementation notes

- ACLs apply to commands issued inside Lua, so script contents count.
- The ACL is generated at Redis startup, and the StatefulSet has no rollout trigger on the
  ConfigMap. Run `kubectl rollout restart statefulset/redis -n infrastructure`, then confirm with
  `ACL GETUSER` that the new ACL is live. A green run against a stale ACL proves nothing.
- `ACL DRYRUN` checks permission, not capability, so use it only for deny assertions (R3).

### Validation

Orchestration static gate, then `verify-session-architecture.sh` and
`verify-credential-isolation.sh` against a restarted Redis. Run the login-to-logout flow and
confirm `ACL LOG` has no unexpected denials.

### Completion criteria

Session Gateway works through its full lifecycle with no admin commands, and the verifiers fail if
`+@all` returns.

## Phase 4: Reconcile documentation with current behaviour

### Workspace

.

### Goal

Correct the documented claims all four reviews agree are wrong, describing what the code does today.

### Scope

`docs/architecture/security-architecture.md`, `docs/architecture/service-communication.md`, and
`docs/architecture/system-overview.md`. Check `docs/OWNERSHIP.md` first.

### Non-goals

ADRs. Rows changed by later phases are left to those phases: absolute expiry (phase 12) and eviction
policy (phase 5). R2's additional corrections are not in the four-way consensus.

### Required context

R1's reconciliation table; R3's note that `expires_at` is also checked by ext-authz and Session
Gateway; `docs/OWNERSHIP.md`.

### Execution steps

1. Correct the CSRF row (`security-architecture.md:489`). SameSite is the principal protection and
   CSRF tokens are not implemented.
2. Correct the cookie line (`:481`). No `Max-Age` is issued; `expires_at` and the Redis TTL enforce
   expiry.
3. Correct the Redis topology claim (`:565`) to the single replica in use.
4. Replace "guaranteed delivery" (`service-communication.md:72`, `:125`; `system-overview.md:248`)
   with the actual recovery contract. Do not generalize it to irreplaceable financial events.
5. In `service-communication.md`, remove the blanket ban on synchronous calls and the advice to
   read a shared database or Redis (`:199-222`), citing the permission lookup as a justified call.

### Implementation notes

Link to owner docs rather than copying detail. Use relative links.

### Validation

Check that the edited claims match the code, and that no link broke.

### Completion criteria

None of the corrected statements remain in these files, apart from the rows deferred above.

## Phase 5: Set an explicit Redis memory budget (Live)

### Workspace

.

### Goal

Replace unbounded Redis memory with a measured budget that keeps auth data out of eviction.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, the pod limit only if measurement requires it, and
`docs/architecture/security-architecture.md:639`.

### Non-goals

Splitting Redis, capping `returnUrl`, or shortening the OAuth-state lifetime.

### Required context

R1 finding 8; R2's capacity estimate; R4's qualifications on `maxmemory` and `noeviction`.

### Execution steps

1. Measure session, index and maximum-size OAuth-state record sizes, base RSS, and AOF rewrite
   overhead on the pinned Redis image.
2. Set `--maxmemory` from that data, leaving headroom below the 256Mi limit. Do not adopt R2's
   70-75% unless the measurements support it.
3. Set `--maxmemory-policy noeviction`.
4. In a disposable environment, fill Redis and record login, heartbeat and API behaviour under
   rejected writes, and recovery afterwards.
5. Replace the `allkeys-lru` claim. Put the measurements and the limits of the budget in the
   evidence file.

### Implementation notes

- `noeviction` turns a crash into failed writes, so anonymous OAuth-state growth can still block
  logins. Record this as a known gap.
- `maxmemory` is not an RSS limit (R4).
- The shared cache is capped along with auth data. If its growth threatens the budget, report it
  rather than changing the policy.

### Validation

Orchestration static gate, and `CONFIG GET maxmemory*` as `redis-ops` after a restart. Run
`verify-credential-isolation.sh`.

### Completion criteria

The budget is backed by recorded measurements, and failure behaviour under exhaustion is documented.

## Phase 6: Bind OAuth callbacks to the initiating browser

### Workspace

../session-gateway

### Goal

Ensure a callback can only complete in the browser that started the login.

### Scope

`RedisAuthorizationRequestRepository`, its tests, and `docs/security.md`.

### Non-goals

`returnUrl` capping and CSRF policy.

### Required context

R1 finding 1; R2's cookie requirements; R4's test list; [RFC 9700 section 2.1.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1).

### Execution steps

1. Confirm the callback is a top-level GET (`response_mode` is not `form_post`).
2. On login start, read or create the binding from D3 and set it as a `__Host-` cookie with
   `Secure`, `HttpOnly`, `Path=/`, `SameSite=Lax`, no `Domain`, and a `Max-Age` equal to the
   OAuth-state lifetime.
3. Store only a hash of the binding in the Redis transaction.
4. On callback, compare in constant time and reject before issuing a session.
5. Consume the transaction in one Redis step.
6. Change the test at `SecurityConfigIntegrationTest.java:107`, which completes a callback with no
   cookie, and add tests for missing cookie, wrong cookie, browser B completing browser A's login,
   replay, expiry and parallel tabs.

### Implementation notes

- `Strict` would fail every login, because the callback is a cross-site navigation.
- `__Host-` is required, or a sibling subdomain could plant its own binding.
- A plain `MULTI` around an earlier read is not atomic (R4). Use a Lua script.
- R3 treats atomic consume as hygiene. If it proves hard, finish the binding first and report it.
- Any new Lua command must be in the phase 3 allowlist.

### Validation

The repository's documented build and test commands. Phase 16 proves the live behaviour.

### Completion criteria

All negative tests fail closed, and the normal and parallel-tab flows pass.

## Phase 7: Enforce the absolute session lifetime in Session Gateway

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

1. Add `session.max-lifetime-seconds` from `SESSION_MAX_LIFETIME_SECONDS`.
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

## Phase 8: Move Session Gateway to the `__Host-` session cookie

### Workspace

../session-gateway

### Goal

Make `__Host-BA_SESSION` the default name, and remove the configuration that conflicts with it.

### Scope

`application.yml`, `SessionProperties`, `SessionCookieHelper`, tests, and docs.

### Non-goals

Duplicate-cookie rejection and session-key hashing.

### Required context

R2 CSRF section; R3 and R4 on `__Host-`; `docs/session-configuration.md`.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default.
2. Apply D4 by removing the Domain override, or fail at startup if it is combined with `__Host-`.
3. Fail at startup if the name starts with `__Host-` and `secure` is false.
4. Update tests and docs.

### Implementation notes

Confirm the actual `Set-Cookie` output, because browsers silently reject a malformed `__Host-`
cookie. The live stack and `verify-session-architecture.sh` stay inconsistent until phase 12.

### Validation

The repository's documented build and test commands.

### Completion criteria

The cookie is issued with `Secure`, `Path=/` and no `Domain`, including when clearing it.

## Phase 9: Update ext-authz for the session contract

### Workspace

../ext-authz

### Goal

Match the new cookie default and, if D2 stands, reject sessions older than the cap.

### Scope

`config.go`, `session.go`, tests, and `README.md`.

### Non-goals

Health endpoints, which are phase 13.

### Required context

`../ext-authz/session.go`; phase 7 semantics.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default to `__Host-BA_SESSION`.
2. If D2 stands, add `SESSION_MAX_LIFETIME_SECONDS` and parse `created_at`.
3. Treat a session past the cap as expired, using the existing 401 path.
4. Treat a missing or invalid `created_at` the same way as an invalid `expires_at`, so it fails
   closed.
5. Add table tests covering below, at and past the cap, and a missing and an invalid field.

### Implementation notes

`scripts/ops/seed-ext-authz-session.sh` already writes `created_at`, so seeded sessions keep working.

### Validation

`go test ./...` and the repository's other documented checks.

### Completion criteria

The cookie default matches Session Gateway, and the cap fails closed.

## Phase 10: Check the frontend at the session cap

### Workspace

../budget-analyzer-web

### Goal

Confirm that a user reaching the cap gets a clear re-login, not a broken "stay signed in" prompt.

### Scope

`useSessionHeartbeat`, `InactivityWarningModal`, and `docs/authentication.md`.

### Non-goals

Other session UX changes.

### Required context

`docs/authentication.md`; phase 7 behaviour.

### Execution steps

1. Trace what happens when `expiresAt` stops advancing and the heartbeat later returns 401.
2. Add a test for that sequence.
3. Fix the modal only if extending appears to work but does nothing.
4. Update the `BA_SESSION` references in `src/api/client.ts` and `docs/authentication.md`.

### Implementation notes

This may be a test and comment change only. The cookie is HttpOnly, so no code reads its name.

### Validation

The repository's documented test, lint and type-check commands.

### Completion criteria

Reaching the cap has a tested, understandable outcome.

## Phase 11: Update API tests for the new contract

### Workspace

../budget-analyzer-api-tests

### Goal

Keep the API tests aligned with the cookie name and the OAuth binding.

### Scope

`environments/*.yaml`, unit tests that reference `BA_SESSION`, and `AGENTS.md`.

### Non-goals

New API coverage beyond these changes.

### Required context

The repository's `AGENTS.md`; phases 6 and 8.

### Execution steps

1. Update `session_cookie_name` in the environment files and the affected tests.
2. Confirm the login helpers carry the OAuth binding cookie through the callback. Fix them if they
   rebuild requests without it.

### Implementation notes

Do not run anything against staging or production. Those files are only updated for consistency.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and the login helper preserves the binding cookie.

## Phase 12: Wire the session contract into orchestration (Live)

### Workspace

.

### Goal

Cut the running stack over to the new cookie and lifetime, and prove both.

### Scope

`kubernetes/services/ext-authz/deployment.yaml`, `kubernetes/services/session-gateway/configmap.yaml`,
`Tiltfile`, the verifiers that reference `BA_SESSION`, and the owner docs.

### Non-goals

Probe changes, which are phase 18, and `kubernetes/production` image pins.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; phases 7-9.

### Execution steps

1. Set `SESSION_COOKIE_NAME=__Host-BA_SESSION` on ext-authz.
2. Set `SESSION_MAX_LIFETIME_SECONDS` in `configmap.yaml` and in the Tiltfile's
   `session-gateway-config`, because Tilt overrides the checked-in ConfigMap. Set it on ext-authz
   too if D2 stands.
3. Update `verify-session-architecture.sh`, `verify-istio-ingress.sh`,
   `verify-credential-isolation.sh` and `verify-ingress-rate-limits.sh`.
4. Prove the cap live. If D2 stands, let `seed-ext-authz-session.sh` accept an optional `created_at`
   and confirm the API rejects a seeded session past the cap. If D2 is dropped, use a short local
   maximum and a real login.
5. Update `session-edge-authorization-pattern.md`, `security-architecture.md:441`, `SECURITY.md`,
   `docs/runbooks/tilt-debugging.md`, and `docs/architecture/deployment-architecture-gcp.md`.

### Implementation notes

- Old `BA_SESSION` cookies in local browsers become inert. No compatibility path is needed.
- Do not use a seeded session to test the heartbeat cap. The seeded user does not exist in
  permission-service, so the heartbeat returns 401 regardless. Phase 7's integration tests cover it.

### Validation

Orchestration static gate, then `verify-session-architecture.sh`, `verify-istio-ingress.sh` and
`verify-ingress-rate-limits.sh`.

### Completion criteria

Session Gateway, ext-authz, verifiers and docs all use one cookie name, and the cap holds live.

## Phase 13: Separate ext-authz liveness from readiness

### Workspace

../ext-authz

### Goal

Keep the authorizer process alive through a Redis outage, without serving as ready.

### Scope

`main.go`, `session.go`, tests, and `README.md`.

### Non-goals

Orchestration manifests, which are phase 18.

### Required context

R1 finding 7; R2 on process exit; R3 N4.

### Execution steps

1. Add `/livez`, which reports process health with no Redis dependency.
2. Add `/readyz`, which pings Redis. Remove `/healthz`.
3. Start the health server before connecting to Redis.
4. Replace the exit after 10 failed connection attempts with continued background retries.
5. While Redis is unavailable, keep returning the existing fail-closed response.

### Implementation notes

R3 found the retry loop can back off for about 27.5 seconds, while the startup probe allows about
10 seconds and the health server only starts after Redis connects. Set a startup probe target for
phase 18.

### Validation

`go test ./...`, including a test that `/livez` stays healthy and `/readyz` fails while Redis is
unavailable.

### Completion criteria

A Redis outage cannot cause a liveness failure or a process exit, and authorization stays fail-closed.

## Phase 14: Safe logging and readiness in transaction-service

### Workspace

../transaction-service

### Goal

Stop logging bodies by default, and make readiness reflect the service's own dependencies.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

Audit events, PDF bounds, and service logic.

### Required context

R3 finding 6 table; `HttpLoggingProperties` in service-common, where both body flags default to
`false`.

### Execution steps

1. Remove `include-request-body` and `include-response-body`.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add an opt-in `debug-logging` profile for synthetic-data debugging only.
4. Set `management.endpoint.health.group.readiness.include` to `readinessState` plus the data
   stores the service needs in order to serve requests.

### Implementation notes

- This trap is not in any review. Spring's default readiness group holds only `readinessState`, so
  switching the probes without this step would stop a database outage from removing the pod.
- Keep `/actuator/health/liveness` free of dependencies. Do not add downstream services to
  readiness. Exclude RabbitMQ unless request serving depends on it.

### Validation

The repository's documented build and test commands. Confirm the effective `kubernetes` profile has
no body logging.

### Completion criteria

Default configuration logs no bodies and no TRACE, and readiness fails when the database is down.

## Phase 15: Safe logging and readiness in permission-service

### Workspace

../permission-service

### Goal

Apply the phase 14 changes to permission-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

`deleteUser` and the user-sync endpoint.

### Required context

Phase 14 notes.

### Execution steps

1. Remove both body-logging settings.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Set the readiness group to `readinessState` plus the database.

### Implementation notes

This service returns user and permission data, so response bodies are the main exposure here.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as phase 14.

## Phase 16: Safe logging, readiness and live OAuth proof in session-gateway (Live)

### Workspace

../session-gateway

### Goal

Apply the phase 14 changes, and prove OAuth binding on the real stack.

### Scope

`application.yml`, `application-kubernetes.yml`, tests, and live OAuth checks.

### Non-goals

Audit events.

### Required context

Phase 14 notes; phase 6; R3 N4 on the leftover override.

### Execution steps

1. Remove both body-logging settings from `application.yml`.
2. Remove the override and the "isolate POST timeout issue" comment from
   `application-kubernetes.yml`.
3. Change `org.budgetanalyzer` from TRACE to INFO, and add the `debug-logging` profile.
4. Set the readiness group to `readinessState` plus Redis. `probes.enabled` is already set.
5. On the running stack, using disposable local credentials, start a login in one cookie jar and
   stop at the callback URL without following it. Deliver that unused callback from a second jar
   with no binding cookie, and record that it is rejected. Then complete a normal login.

### Implementation notes

Do not add permission-service to readiness. It is a downstream dependency, and including it would
take the auth lane down with it. Never record real cookie or token values. The callback in step 5
must be unused, because replaying a consumed one fails on single use and proves nothing about the
binding.

### Validation

The repository's documented build and test commands, plus the live rejected callback and normal
login.

### Completion criteria

Logging matches phase 14, and a callback without the binding is rejected live.

## Phase 17: Safe logging and readiness in currency-service

### Workspace

../currency-service

### Goal

Apply the phase 14 changes to currency-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

Cache eviction and `KEYS`/`SCAN` changes.

### Required context

Phase 14 notes.

### Execution steps

1. Remove `include-request-body`. Response bodies are already off, so remove that setting too.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Set the readiness group to `readinessState` plus the stores needed to serve requests.

### Implementation notes

Decide deliberately whether Redis belongs in readiness. If a cache miss can fall back to the
database, a Redis outage should not make this service unready.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as phase 14.

## Phase 18: Switch probes and run the outage drill (Live)

### Workspace

.

### Goal

Point every probe at the right contract, and prove a dependency outage causes no restarts.

### Scope

Deployment manifests in `kubernetes/services/`, `scripts/smoketest/verify-credential-isolation.sh`,
and the docs that reference `/healthz`.

### Non-goals

Alerting and service code.

### Required context

Phases 13-17; `docs/runbooks/tilt-debugging.md`.

### Execution steps

1. Point ext-authz startup and liveness probes at `/livez`, and readiness at `/readyz`.
2. Point Spring startup and liveness probes at `.../actuator/health/liveness`, and readiness at
   `.../actuator/health/readiness`, keeping each service's context path.
3. Update `verify-credential-isolation.sh:624`, `docs/runbooks/tilt-debugging.md:222,492,652`, and
   `docs/architecture/session-edge-authorization-pattern.md:90`.
4. Interrupt Redis on local Kind, then repeat for PostgreSQL. Record readiness, restart counts and
   client errors, then confirm recovery.

### Implementation notes

Apply the `kind-kind` checks before the drill. Redis data is on a PVC and survives a pod replacement.
Report a failing drill as a finding rather than loosening probes to make it pass.

### Validation

Orchestration static gate, and `scripts/smoketest/verify-credential-isolation.sh`. Compare
`restartCount` before and after each interruption.

### Completion criteria

During each outage affected pods become unready with no restarts, authorization stays fail-closed,
and service recovers without intervention.

## Phase 19: Full verification and release handoff (Live)

### Workspace

.

### Goal

Prove the combined change and record the human-owned release steps.

### Scope

Full verification suites, the evidence file, and remaining docs.

### Non-goals

Releasing images, changing production pins, or starting the follow-up plan.

### Required context

`scripts/README.md`; the evidence file.

### Execution steps

1. Run the aggregate smoketest and the disposable local API tests.
2. Confirm Phase 1 traversals still fail after every later change.
3. Confirm no doc in the consensus table still contradicts the code.
4. Record the human-owned handoff: release session-gateway, ext-authz and the four services'
   updated images, then update `kubernetes/production/apps/deployment-manifest.yaml` and
   `image-inventory.yaml`.
5. Summarize evidence per consensus item, and note every remaining gap.

### Implementation notes

Passing offline checks prove the production reference renders. They do not prove the pinned images
support the new probes or cookie contract, so do not claim parity.

### Validation

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/smoketest.sh
```

### Completion criteria

All ten consensus items have recorded evidence, and the release handoff is explicit.
