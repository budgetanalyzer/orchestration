# Security Review Consensus Hardening Plan

**Status:** Draft for iteration. Do not run until the decisions below are settled.

This plan implements every finding from the four 2026-11-01 security reviews that holds up against
the code and that no review disputes. Disputed fixes are set out for discussion in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document, and none of
them is in this plan until it is decided.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Inclusion rule

An item is in scope when all three of these hold:

1. At least one review proposes it.
2. No review disputes the fix direction. Silence is not a dispute.
3. It was checked against the code on 2026-11-02.

A disagreement over severity does not exclude an item. A dispute over part of a remedy excludes only
that part.

| # | Fix | Proposed or endorsed by | Phases |
| --- | --- | --- | --- |
| 1 | Narrow mesh policies to the callers' real paths | All four | 1, 17 |
| 2 | Add an explicit mesh deny baseline | R2, R4 | 1 |
| 3 | Prove the public/internal boundary across encoded path forms | R3, R4 | 1, 35 |
| 4 | Strip `Cookie` and `Authorization` before backends | All four | 2 |
| 5 | Send backends the real `X-Forwarded-Proto` | R2, R4 | 2 |
| 6 | Set ext_authz `statusOnError` and a timeout; correct the contract; test real denials | R2, R3, R4 | 3 |
| 7 | Send HSTS from the ingress | R2, R3, R4 | 4 |
| 8 | Stop trusting caller forwarded headers; fix the OAuth redirect URI | R2, R4 | 4, 8, 17 |
| 9 | Add CSP `form-action`; drop `X-XSS-Protection` | R2, R4 | 4 |
| 10 | Replace Session Gateway `+@all` and its literal verifier | All four | 5 |
| 11 | Reconcile the documentation with the code | All four; R2, R3, R4 on additions | 6, 17 |
| 12 | Bind OAuth callbacks to the initiating browser | All four | 7, 18 |
| 13 | Validate and cap `returnUrl` at login start; shorten the OAuth-state lifetime | R2, R3 | 8 |
| 14 | Reject backslashes and control characters in redirect targets | R2 | 8, 15 |
| 15 | Enforce an absolute session lifetime | All four | 9, 14, 15, 17, 18 |
| 16 | Hash session tokens in session keys and index members | R2, R3, R4 | 10, 14, 17, 18 |
| 17 | Adopt the `__Host-` session cookie | R1 ("consider"), R2, R3, R4 | 11, 14-18 |
| 18 | Add a login permission-call deadline; move user sync off GET | R2, R3, R4 | 12, 13, 17 |
| 19 | Separate liveness from readiness | All four | 19, 22, 24-27 |
| 20 | Add ext-authz HTTP server timeouts | R2 | 19 |
| 21 | Use the trusted client address | R1, R2, R4 | 20 |
| 22 | Add structured audit events | R1, R2 | 21, 25 |
| 23 | Turn body logging and TRACE off by default in all four services | All four | 22, 24-26 |
| 24 | Add an endpoint authorization coverage rule | R2, R3, R4 | 22, 24, 26 |
| 25 | Bound PDF parsing, limited to the agreed controls | R2, R3, R4 | 23 |
| 26 | Set a measured Redis memory budget; no `allkeys-lru` on auth data | All four | 28 |
| 27 | Exclude private destinations from the egress gateway | R1, R3 | 29 |
| 28 | Require TLS on the PostgreSQL server side | R2, R3, R4 | 30 |
| 29 | Separate migration roles from runtime roles | R2, R4 | 31 |
| 30 | Move to a supported RabbitMQ series; report runtime support dates | R2, R3, R4; R2 | 32 |
| 31 | Test the edge contract across layers, including forged headers with no permissions | R2, R3, R4 | 1-4, 33 |

Phases broadly follow R4's order, so cross-repository credential fixes are not left to the end. The
session phases stay together because they change the same code and contract. Infrastructure comes
last so the Redis budget can measure the final records.

All four reviews also agree on what not to do now: keep server-side sessions, keep the topology, and
do not treat Redis Cluster as a drop-in replacement.

## Decisions to settle before running

| # | Decision | Recommendation | Why it matters |
| --- | --- | --- | --- |
| D1 | Absolute session lifetime | `SESSION_MAX_LIFETIME_SECONDS=43200` (12 hours) | No review names a value. This is a usability and risk choice. |
| D2 | Should ext-authz re-check the cap? | Yes, as R2, R3 and R4 propose, but it is optional | ext-authz already rejects a passed `expires_at`, so a Session Gateway cap is enforced transitively. The re-check only guards against a Session Gateway renewal bug, at the cost of one more shared setting. |
| D3 | OAuth correlation cookie shape | One `__Host-` cookie per login, named from a hash of `state` and cleared after its callback | This satisfies both R2 (clear the cookie) and R4 (parallel tabs), so it replaces the earlier single reusable cookie. See the contested issues document. |
| D4 | `SESSION_COOKIE_DOMAIN_OVERRIDE` | Remove it | `__Host-` forbids a `Domain` attribute. No checked-in deployment sets the override. |
| D5 | Where the migration credential lives | In the service pod, as a separate credential | This stops DDL through the runtime connection, including SQL injection. It does not stop code execution in the pod, which can read both credentials. An out-of-process migrator would, at much higher cost. |
| D6 | Audit event coverage | State-changing requests and the session lifecycle | The docs claim audit logging of data access. Auditing reads adds volume and no review requires it, so Phase 35 narrows the claim instead. |

## Excluded from this plan

**Contested.** These are in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document:

- The primary CSRF control, missing-header behaviour, and moving heartbeat and logout to POST.
- Removing `KEYS`/`SCAN`, a versioned cache prefix, and splitting Redis.
- Rejecting `;`, and a `StrictHttpFirewall` test.
- Rejecting duplicate session cookies.
- File-backed PDF input or a stream cache, and a parsing worker.
- Signed identity, separate internal ports, and per-caller egress identity.
- The unused `deleteUser` method and re-signup after deletion.
- HSTS `includeSubDomains` and `preload`, and generating the NGINX route files.
- Severity ratings, which this plan deliberately does not settle.

**Deferred by agreement.** All four reviews leave these until hosted use is planned: recovery
objectives and restore tests, secret rotation and storage encryption, exporters and alert delivery,
vulnerability gating, and Redis high availability. R1 and R4 tie two more to requirements that do not exist yet: step-up reauthentication,
and an account generation check for immediate containment.

## Plan-wide rules

- No staging or production access, no certificate generation, and no git write operations unless
  the user asks.
- Each phase works in its declared workspace only. Follow that repository's `AGENTS.md`.
- Treat review claims as leads. Re-check them against the code before relying on them.
- Before any cluster mutation, apply the `kind-kind` checks in the orchestration `AGENTS.md`.
- Phases marked **Live** need a running stack. In orchestration phases, run
  `./scripts/bootstrap/check-local-runtime.sh` and `tilt up`. If the stack cannot be started, stop
  and report; do not substitute static evidence.
- Phases 7-17 change the session contract one repository at a time, and Tilt builds sibling
  worktrees, so the local stack is inconsistent until Phase 18. Those phases must not rely on a
  running stack.
- Do not edit `docs/decisions/` or `docs/archive/`.
- Do not edit this plan during a run, because the runner stops launching phases when it changes.
- Record measurements and results in `docs/research/security-consensus-hardening-evidence.md`. A
  phase in a sibling repository records them in that repository's `docs/` folder, and Phase 35
  collects the links.

**Orchestration static gate**, for every orchestration phase:

```bash
bash -n <changed-script> && shellcheck <changed-script>
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/guardrails/verify-static-security-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Cutover rule:** `kubernetes/production` shares these manifests but pins older images
(session-gateway 0.0.15, ext-authz 0.0.16). Phases 17, 18 and 27 therefore describe behaviour those
images lack: the new cookie, hashed keys, the POST sync call and `/livez`. The mesh policy from
Phase 17 would also block the pinned Session Gateway's login call. The offline checks catch none of
this. Phase 35 records the release and pin updates, which are human-owned. No production environment
exists, so no dual-cookie or session migration is needed.

## Phase 1: Narrow mesh policies and prove the public/internal boundary (Live)

### Workspace

.

### Goal

Limit each mesh caller to the paths it needs, make deny-by-default explicit, and settle R3's
encoded-path finding with evidence from the real chain.

### Scope

`kubernetes/istio/authorization-policies.yaml`, a new `scripts/smoketest/verify-edge-contract.sh`,
`scripts/smoketest/verify-istio-ingress.sh`, a static guardrail, `scripts/README.md`, and the
nearest architecture docs.

### Non-goals

No `;` rejection at NGINX or the ingress, no separate ports, and no service code.

### Required context

R3 finding N1; R2 "Narrow mesh permissions" and finding H; R4 "Authorization errors and routing need
integration evidence"; `docs/architecture/security-architecture.md`;
`docs/architecture/session-edge-authorization-pattern.md`.

### Execution steps

1. Create `verify-edge-contract.sh`. It is the single home for cross-layer edge tests, and later
   phases add sections to it. Add a "Public/Internal Boundary" section that sends each probe below
   through the real ingress with `curl --path-as-is`.
2. Seed a real user and session with `./scripts/loadtest/seed-loadtest-users.sh --count 1`, and
   remove them with `teardown-loadtest.sh` when the section ends.
3. Build the NGINX-lane matrix from these parts, repeating the traversal as R3's path does:
   - prefixes: `/api/v1/users/`, `/api/v1/transactions/`, `/api/v1/currencies/`
   - targets: `internal/v1/users/<id>/authorization`, `actuator/prometheus`
   - forms: `..%3b`, `..%3B`, `%2e%2e%3b`, `..;`, `%2e%2e`, `..%2f`, `..%5c`, `%252e%252e%252f`
4. Add the direct auth lane, using the same forms:
   - `GET /auth/v1/<traversal>/<traversal>/actuator/prometheus`
   - `DELETE /auth/v1/<traversal>/<traversal>/internal/v1/sessions/users/<id>`, asserting that the
     seeded session still works afterwards
5. Run the section before changing any policy, and record the baseline in the evidence file. R3
   tested only the `users` chain against a stand-in, and R4 did not reproduce it, so this is the
   first real measurement.
6. Add `to.operation` limits to the NGINX rules:
   - transaction-service: `/transaction-service/v1/*`, `/transaction-service/v3/api-docs`
   - currency-service: `/currency-service/v1/*`, `/currency-service/v3/api-docs`
   - permission-service: `/permission-service/v1/*`
7. Split `permission-service-policy` so Session Gateway gets `GET` on only
   `/permission-service/internal/v1/users/{*}/permissions` and
   `/permission-service/internal/v1/users/{*}/authorization`.
8. Limit the ingress rule on `session-gateway-policy` to the `auth-route` surface: `/oauth2/*`,
   `/login/oauth2/*`, `/logout`, `/logout/*`, `/auth/*`. Keep the existing permission-service rule.
9. Add an explicit `default-deny-all` policy (`spec: {}`) in the `default` namespace, and add it to
   the resources `verify-istio-ingress.sh` requires.
10. Extend the boundary section so it also asserts that a legitimate public route and login start
    still work.
11. Add a static guardrail that fails if a backend policy's NGINX rule has no `to` restriction, or
    if `default-deny-all` is missing or has rules.

### Implementation notes

- Do not probe with `seed-ext-authz-session.sh`'s user. It does not exist in permission-service, and
  a missing user returns 404 from the service itself, so the probe would pass while the path stayed
  open.
- Never use the `.../permissions` endpoint as a probe. It is a GET that writes through `syncUser`.
- An empty ALLOW policy matches nothing, so a workload is reachable only through its own rules.
  Confirm every workload in `default` has one before adding it. Today the selector-less
  `envoy-metrics-prometheus-policy` provides this property by accident (R2).
- `/v1/*` matches today's public surface: the only `/v1` controllers in these three services are
  the ones NGINX exposes. A future non-public `/v1` route would need a narrower rule.
- `scripts/repo/generate-unified-api-docs.sh` reaches specs through `kubectl exec` to loopback, so
  the api-docs allowances are only for the NGINX routes.
- Assert "not 200" rather than a specific denial, so a later `;` rejection does not break the test.
- The Prometheus policy is separate and must remain unchanged.
- If the baseline shows the traversal is already blocked, record that and continue. Narrowing is
  independently agreed.
- Phase 17 replaces the `.../permissions` rule from step 7 with the new sync call.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh`,
`./scripts/smoketest/verify-istio-ingress.sh`, and `./scripts/smoketest/verify-session-architecture.sh`.
Confirm login, a heartbeat and a permission lookup work end to end.

### Completion criteria

Every probe returns non-200, the seeded session survives the `DELETE` probes, every legitimate path
still works, and before and after results are in the evidence file.

## Phase 2: Correct the NGINX backend header contract

### Workspace

.

### Goal

Stop forwarding the reusable session cookie and unused authorization headers to business services,
and tell backends the real scheme.

### Scope

`nginx/includes/backend-headers.conf`, its verification, and the nearest docs.

### Non-goals

Frontend lanes that do not use this include, and the direct Session Gateway auth lane.

### Required context

R1 finding 3; R2 finding H; `nginx/README.md`;
`docs/architecture/session-edge-authorization-pattern.md`.

### Execution steps

1. Add `proxy_set_header Cookie "";` and `proxy_set_header Authorization "";` to the include, with
   a short comment explaining that ext_authz has already consumed the cookie at the ingress.
2. Change `proxy_set_header X-Forwarded-Proto $scheme;` to `https`. NGINX listens on HTTP behind the
   ingress, so `$scheme` is always `http`. The frontend lanes already send `https`.
3. Confirm every API location in both NGINX configs still uses the include.
4. Prove stripping with a disposable pinned NGINX container, the shared include and an echo
   upstream. Record header names only.
5. Add a static assertion for all three directives.

### Implementation notes

- The `p3-header-echo` fixture in `verify-istio-ingress.sh` routes straight from an `HTTPRoute`, so
  it bypasses NGINX and cannot prove this change.
- A search of the three business services and service-common found no reads of `Cookie`,
  `Authorization` or `X-Forwarded-Proto`. Step 2 corrects the contract; it does not fix a live bug.
- The planned M2M lane validates bearer tokens at the ingress, so this does not conflict with it.

### Validation

Orchestration static gate, `kubectl exec deployment/nginx-gateway -- nginx -t`, and the stand-in
test from step 4. If the stack is running, also confirm an authenticated `/api/v1/transactions`
request still succeeds.

### Completion criteria

The echo upstream receives neither credential header and sees `https`, identity headers still
arrive, and ext_authz still authorizes requests.

## Phase 3: Bound ext_authz failures and correct the contract (Live)

### Workspace

.

### Goal

Make every authorizer failure a fast 503, and make the documented contract match what clients can
receive.

### Scope

`kubernetes/istio/istiod-values.yaml`, `docs/architecture/session-edge-authorization-pattern.md`,
`scripts/guardrails/verify-static-security-manifests.sh`, and `verify-edge-contract.sh`.

### Non-goals

Changes to ext-authz itself, and any local-reply mapping at the ingress.

### Required context

R2 finding on Istio defaults; R3 finding N2; R4 "Authorization errors and routing need integration
evidence".

### Execution steps

1. Measure normal authorization latency on the running stack and record it. Choose the timeout from
   that measurement. About 1 s is a candidate (R4), not a requirement.
2. Add `statusOnError: "503"` and the `timeout` to the provider. Keep `failOpen: false`.
3. Apply the change and confirm both values in the ingress Envoy config dump, not just the values
   file. R3 could not read them because the provider's service was not deployed.
4. Change the row at `session-edge-authorization-pattern.md:239` to a fail-closed 503 with an empty
   body. State why: Envoy treats an authorizer 5xx as an error and discards its body, so ext-authz's
   JSON never reaches a client. R3 and R4 both accept this option, and it is the cheaper one.
5. Add an "Authorization Failure" section to `verify-edge-contract.sh` that exercises real
   denials through the ingress:
   - no session, which must stay a 401 with JSON
   - ext-authz scaled to zero
   - a hang, using a temporary NetworkPolicy that blocks the ingress from ext-authz
   - Redis stopped
6. Extend the denial contract scan so it fails without `statusOnError`, a `timeout` and
   `failOpen: false`.

### Implementation notes

- Apply the `kind-kind` checks, and restore every scaled workload and temporary policy.
- Until Phase 27, a Redis outage also fails ext-authz's probes, so the Redis case may surface as a
  connection failure rather than the authorizer's own 503. Either must reach the client as a 503.
- The frontend does not depend on the JSON body. `client.ts` handles an unstructured error, and
  `useUsers.ts:29` checks only the status.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-edge-contract.sh`.

### Completion criteria

Every failure path returns a 503 within the timeout and never reaches NGINX, a missing session still
returns JSON 401, and the contract row matches the observed responses.

## Phase 4: Harden ingress headers and the CSP (Live)

### Workspace

.

### Goal

Send HSTS on every lane, stop caller-supplied forwarded headers reaching services, and close the
small CSP gaps.

### Scope

`kubernetes/gateway/*.yaml`, `nginx/includes/security-headers-*.conf`,
`scripts/smoketest/verify-edge-browser-hardening.sh`, `verify-edge-contract.sh`, `nginx/README.md`,
and the security architecture doc.

### Non-goals

`includeSubDomains`, `preload`, and the fixed redirect URI, which is Phase 8.

### Required context

R2 findings G and H; R3 "HSTS details"; R4 "HSTS (G)"; `nginx/README.md`.

### Execution steps

1. Add a `ResponseHeaderModifier` filter to every rule of `auth-route`, `api-route` and `app-route`
   that sets `Strict-Transport-Security: max-age=31536000`.
2. Add a `RequestHeaderModifier` filter to every rule that removes `Forwarded`, `X-Forwarded-Host`,
   `X-Forwarded-Port`, `X-Forwarded-Prefix` and `X-Forwarded-Ssl`. Leave `X-Forwarded-For`, which
   the ingress appends to, and the existing `X-Forwarded-Proto` handling.
3. Add `form-action 'self'` to the three CSP includes, and remove `X-XSS-Protection` from them.
4. Add a "Response Headers" section to `verify-edge-contract.sh`:
   - HSTS appears on `/`, an authenticated `/api/*` request, `/auth/v1/session` and
     `/oauth2/authorization/idp`, with one value on each
   - login start with a forged `X-Forwarded-Host` still builds `redirect_uri` from the real host
5. Add the new headers to `verify-edge-browser-hardening.sh`, and update `nginx/README.md` and the
   CSP posture section.

### Implementation notes

- Use `set`, not `add`. Spring Security's default writer already sends
  `max-age=31536000 ; includeSubDomains` on the auth lane, because `X-Forwarded-Proto` makes the
  scheme `https`. `set` leaves one value, and drops `includeSubDomains` until that is decided.
- Local replies such as ext_authz denials and 429s may not carry the header. That is fine as long as
  ordinary responses do.
- Session Gateway is the only consumer of the removed headers today. Removing them on every route
  keeps a future consumer safe.
- No SPA form posts natively; each uses `onSubmit`, so `form-action 'self'` breaks nothing today.
- `kubernetes/production/gateway-routes` reuses these routes, so the production reference inherits
  the change.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh`,
`./scripts/smoketest/verify-edge-browser-hardening.sh`, and a browser login.

### Completion criteria

All four paths send one HSTS value, a forged forwarded host has no effect on `redirect_uri`, and the
app runs with no CSP violations.

## Phase 5: Replace the Session Gateway Redis `+@all` grant (Live)

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

1. Start from the commands in the code: `hset`, `hmset`, `hget`, `hgetall`, `expire`, `del`,
   `unlink`, `sadd`, `srem`, `smembers`, `type`, `evalsha`, `eval`, plus connection and health
   commands such as `hello`, `client`, `auth`, `ping` and `info`.
2. Derive the final list from `ACL LOG` across a cold start, script load, health probes, login,
   heartbeat refresh, logout, bulk revocation, and OAuth failure and expiry paths. One successful
   login is not enough.
3. Replace `+@all`. Drop `&*` if the final list has no pub/sub commands.
4. Replace the literal assertion at `verify-session-architecture.sh:565` with a check that the
   Session Gateway line has no `+@all`.
5. Add negative `ACL DRYRUN` checks to `verify-credential-isolation.sh` for `FLUSHALL`, `FLUSHDB`,
   `CONFIG`, `SHUTDOWN`, `REPLICAOF`, `ACL`, `KEYS` and `SCAN`, and positive checks for the allowed
   commands.

### Implementation notes

- ACLs apply to commands issued inside Lua, so script contents count.
- The ACL is generated at Redis startup, and `disableNameSuffixHash: true` means nothing restarts
  Redis when the script changes. Run `kubectl rollout restart statefulset/redis -n infrastructure`,
  then confirm with `ACL GETUSER` that the new ACL is live. A green run against a stale ACL proves
  nothing.
- `ACL DRYRUN` checks permission, not capability, so use it only for deny assertions (R3).

### Validation

Orchestration static gate, then `verify-session-architecture.sh` and
`verify-credential-isolation.sh` against a restarted Redis. Run the login-to-logout flow and
confirm `ACL LOG` has no unexpected denials.

### Completion criteria

Session Gateway works through its full lifecycle with no admin commands, and the verifiers fail if
`+@all` returns.

## Phase 6: Reconcile documentation with current behaviour

### Workspace

.

### Goal

Correct the documented claims the reviews found wrong, describing what the code does today.

### Scope

`docs/architecture/security-architecture.md`, `docs/architecture/service-communication.md`,
`docs/architecture/system-overview.md`, `docs/architecture/session-edge-authorization-pattern.md`,
and R1's links. Check `docs/OWNERSHIP.md` first.

### Non-goals

ADRs. Rows changed by later phases are left to those phases: absolute expiry and session key format
(Phase 17), audit logging (Phase 35), and eviction policy (Phase 28).

### Required context

R1's reconciliation table; R2 "Documentation corrections"; R3 on `expires_at` and revocation; R4
"Documentation and work order"; `docs/OWNERSHIP.md`.

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
6. Qualify revocation at `security-architecture.md:494` and `:754`. Deleting a session rejects later
   lookups at once. It cannot undo authorized requests or stop a concurrent login or refresh.
7. Remove the WAF and circuit-breaking claims (`:145-146`), and merge the duplicate bullet (`:94-95`).
8. Remove the Spring Boot major version at `system-overview.md:203`. Versions live in the service
   repositories.
9. In `session-edge-authorization-pattern.md`, state what ADR 007's "until Redis TTL expiry" means:
   the sliding TTL, which keeps moving while heartbeats continue. Do not edit the ADR.
10. Replace the absolute `/srv/...` links in R1 with relative links.

### Implementation notes

Link to owner docs rather than copying detail. Use relative links. R3 and R4 both say R2 overstates
the revocation contradiction, so correct the wording rather than describing a defect.

### Validation

Check that the edited claims match the code, and that no link broke. Confirm
`rg -n '/srv/' docs/research/application-architecture-security-review-2026-11-01.md` finds nothing.

### Completion criteria

None of the corrected statements remain in these files, apart from the rows deferred above.

## Phase 7: Bind OAuth callbacks to the initiating browser

### Workspace

../session-gateway

### Goal

Ensure a callback can only complete in the browser that started the login.

### Scope

`RedisAuthorizationRequestRepository`, its tests, and `docs/security.md`.

### Non-goals

`returnUrl` handling, which is Phase 8, and CSRF policy.

### Required context

R1 finding 1; R2's cookie requirements; R4's test list; [RFC 9700 section 2.1.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1).

### Execution steps

1. Confirm the callback is a top-level GET (`response_mode` is not `form_post`).
2. On login start, create a random binding and set it per D3 as a `__Host-` cookie with `Secure`,
   `HttpOnly`, `Path=/`, `SameSite=Lax`, no `Domain`, and a `Max-Age` equal to the OAuth-state
   lifetime.
3. Store only a hash of the binding in the Redis transaction.
4. On callback, consume the transaction in one Redis step, then compare in constant time and reject
   before issuing a session.
5. Clear that login's cookie after its callback.
6. Change the test at `SecurityConfigIntegrationTest.java:107`, which completes a callback with no
   cookie, and add tests for missing cookie, wrong cookie, browser B completing browser A's login,
   replay, expiry and parallel tabs.

### Implementation notes

- `Strict` would fail every login, because the callback is a cross-site navigation.
- `__Host-` is required, or a sibling subdomain could plant its own binding.
- A plain `MULTI` around an earlier read is not atomic (R4). Use a Lua script.
- Consuming before comparing means a failed attempt cannot be retried.
- An abandoned login leaves its cookie until `Max-Age`. If a login start already carries five
  binding cookies, clear them, so request headers stay bounded.
- R3 treats atomic consume as hygiene. If it proves hard, finish the binding first and report it.
- Any new Lua command must be in the Phase 5 allowlist.

### Validation

The repository's documented build and test commands. Phase 18 proves the live behaviour.

### Completion criteria

All negative tests fail closed, and the normal and parallel-tab flows pass.

## Phase 8: Bound OAuth login input

### Workspace

../session-gateway

### Goal

Validate and cap what an anonymous login can store, shorten how long it stays, and stop building the
callback URL from request headers.

### Scope

`OAuth2ClientConfig`, `RedisAuthorizationRequestRepository`, `RedirectUrlValidator`,
`application.yml`, tests, and `docs/session-configuration.md`.

### Non-goals

Rate limits, and Redis memory settings, which are Phase 28.

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
- A login-start cap does not stop anonymous growth. It only bounds each record. Phase 28 records the
  remaining gap.

### Validation

The repository's documented build and test commands.

### Completion criteria

An oversized or unsafe `returnUrl` is never stored, the validator matches the frontend's rejections,
and the redirect URI can be fixed by configuration.

## Phase 9: Enforce the absolute session lifetime in Session Gateway

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

## Phase 10: Hash session tokens in Session Gateway

### Workspace

../session-gateway

### Goal

Keep the reusable session token out of Redis key names, index members, the append-only file and
logs.

### Scope

`SessionWriter`, `SessionReader`, tests, `docs/security.md`, and `docs/session-configuration.md`.

### Non-goals

The currency-service `KEYS`/`SCAN` grant, and any change to the cookie name, which is Phase 11.

### Required context

R2 finding A; R3 "Three fixes for finding A"; R4 "Redis: the strongest additional finding".

### Execution steps

1. Add one helper that returns the lowercase hex SHA-256 of the cookie value, and use it wherever a
   session key is built.
2. Use that digest for the `session:` key and for the `user_sessions:` member, in both
   `create-session.lua` and `conditional-update.lua` arguments and in `deleteSession`.
3. Return the raw token from `createSession` for the cookie, and never store it.
4. Log the digest prefix instead of `SafeLogger.truncateId(token)`.
5. Add a golden-vector test: a fixed token and its expected key. Phase 14 uses the same vector.
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

## Phase 11: Move Session Gateway to the `__Host-` session cookie

### Workspace

../session-gateway

### Goal

Make `__Host-BA_SESSION` the default name, and remove the configuration that conflicts with it.

### Scope

`application.yml`, `SessionProperties`, `SessionCookieHelper`, tests, and docs.

### Non-goals

Duplicate-cookie rejection, which is contested.

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

## Phase 12: Replace the user-sync GET in permission-service

### Workspace

../permission-service

### Goal

Make the write that happens at login an explicit POST, with personal fields out of the URL.

### Scope

`InternalPermissionController`, `PermissionServiceSecurityConfig`, tests, and docs.

### Non-goals

`deleteUser`, which is contested, and the read-only authorization lookup.

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

Taking `idpSub` from the body gives the mesh one exact path to allow in Phase 17, and keeps all
three fields out of access logs and traces. The GET is removed rather than kept, because no
production environment needs a transition.

### Validation

The repository's documented build and test commands.

### Completion criteria

User sync happens only through the POST, and no personal field appears in its URL.

## Phase 13: Move the login permission call to POST with a deadline

### Workspace

../session-gateway

### Goal

Stop a slow permission-service from hanging logins, and use the new sync call.

### Scope

`PermissionServiceClient`, `PermissionServiceProperties`, `application.yml`, tests, and docs.

### Non-goals

Transport-pool tuning and the heartbeat lookup, which already has a timeout.

### Required context

R2 finding E; R4 "Login permissions (E)"; Phase 12.

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

## Phase 14: Update ext-authz for the session contract

### Workspace

../ext-authz

### Goal

Match the new cookie default and hashed keys and, if D2 stands, reject sessions older than the cap.

### Scope

`config.go`, `session.go`, tests, and `README.md`.

### Non-goals

Health endpoints and server timeouts, which are Phase 19.

### Required context

`session.go`; Phases 9, 10 and 11.

### Execution steps

1. Change the `SESSION_COOKIE_NAME` default to `__Host-BA_SESSION`.
2. Add a small function that builds the Redis key from the lowercase hex SHA-256 of the cookie value,
   and use it in `LookupSession`. Test it with Phase 10's golden vector.
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

## Phase 15: Align the frontend with the session contract

### Workspace

../budget-analyzer-web

### Goal

Confirm that a user reaching the cap gets a clear re-login, and stop trusting `returnUrl` on the
login page.

### Scope

`useSessionHeartbeat`, `InactivityWarningModal`, `LoginPage`, and `docs/authentication.md`.

### Non-goals

Other session UX changes, and moving logout to POST, which is contested.

### Required context

`docs/authentication.md`; `src/features/auth/utils/loginRedirect.ts`; Phase 9 behaviour.

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

## Phase 16: Update API tests for the new contract

### Workspace

../budget-analyzer-api-tests

### Goal

Keep the API tests aligned with the cookie name, the OAuth binding and the edge error contract.

### Scope

`environments/*.yaml`, unit tests that reference `BA_SESSION`, login helpers, and `AGENTS.md`.

### Non-goals

New API coverage beyond these changes.

### Required context

The repository's `AGENTS.md`; Phases 3, 7 and 11.

### Execution steps

1. Update `session_cookie_name` in the environment files and the affected tests.
2. Confirm the login helpers carry the OAuth binding cookie through the callback. Fix them if they
   rebuild requests without it.
3. Find any test that expects a JSON body on an edge 503, and align it with Phase 3.

### Implementation notes

Do not run anything against staging or production. Those files are only updated for consistency.

### Validation

The repository's documented unit test command.

### Completion criteria

The unit suite passes, and the login helper preserves the binding cookie.

## Phase 17: Wire the session contract into orchestration

### Workspace

.

### Goal

Update every orchestration consumer of the session contract, ready for the live cutover.

### Scope

`kubernetes/services/ext-authz/deployment.yaml`, `kubernetes/services/session-gateway/`,
`kubernetes/istio/authorization-policies.yaml`, `Tiltfile`, `scripts/lib/`, `scripts/ops/`,
`scripts/loadtest/`, the verifiers that reference `BA_SESSION` or `session:`, and the owner docs.

### Non-goals

Probe changes, which are Phase 27, and `kubernetes/production` image pins.

### Required context

`docs/architecture/session-edge-authorization-pattern.md`; Phases 7-14.

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

## Phase 18: Cut over the local stack and prove the session contract (Live)

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

Phases 7-17; `scripts/smoketest/verify-ingress-browser-callback.py`.

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
  permission-service, so the heartbeat returns 401 regardless. Phase 9's integration tests cover it.
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

## Phase 19: Separate ext-authz liveness from readiness and add server timeouts

### Workspace

../ext-authz

### Goal

Keep the authorizer process alive through a Redis outage without serving as ready, and bound its
HTTP servers.

### Scope

`main.go`, `session.go`, tests, and `README.md`.

### Non-goals

Orchestration manifests, which are Phase 27.

### Required context

R1 finding 7; R2 on process exit and server timeouts; R3 N4.

### Execution steps

1. Add `/livez`, which reports process health with no Redis dependency.
2. Add `/readyz`, which pings Redis. Remove `/healthz`.
3. Start the health server before connecting to Redis.
4. Replace the exit after 10 failed connection attempts with continued background retries.
5. While Redis is unavailable, keep returning the existing fail-closed response.
6. Set `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout` and `IdleTimeout` on both HTTP servers.

### Implementation notes

- R3 found the retry loop can back off for about 27.5 seconds, while the startup probe allows about
  10 seconds and the health server only starts after Redis connects. Set a startup probe target for
  Phase 27.
- Keep `WriteTimeout` above the Redis call budget, and `IdleTimeout` long enough that closing an idle
  connection does not surface as an authorization failure.

### Validation

`go test ./...`, including a test that `/livez` stays healthy and `/readyz` fails while Redis is
unavailable.

### Completion criteria

A Redis outage cannot cause a liveness failure or a process exit, authorization stays fail-closed,
and neither server can hold a connection open indefinitely.

## Phase 20: Use the trusted client address in service-common

### Workspace

../service-common

### Goal

Stop logging a client address the caller controls.

### Scope

`ContentLoggingUtil`, `ContentLoggingUtilTest`, and the shared docs.

### Non-goals

Changing how NGINX or the ingress derive the address.

### Required context

R1 finding 6; R2 on client IPs; `nginx/nginx.k8s.conf` in orchestration.

### Execution steps

1. Change `getClientIpAddress` to read `X-Real-IP`, falling back to `request.getRemoteAddr()`.
2. Remove the rest of the header list, because a caller can set every entry on it.
3. Replace the test at `ContentLoggingUtilTest.java:93`, which asserts the first `X-Forwarded-For`
   entry, and add a test that a forged `X-Forwarded-For` is ignored.
4. Confirm what `ReactiveHttpLoggingFilter` logs behind the ingress, and record it.
5. Publish to Maven Local so later phases build against the change.

### Implementation notes

- NGINX overwrites `X-Real-IP` with its derived address, so it is trustworthy on the NGINX lane. The
  mesh limits who else can reach these services.
- `ForwardedHeaderTransformer` replaces the reactive remote address with an unresolved one, so
  `getAddress()` should return null and Session Gateway should log no client address. That is a
  missing value, not a forged one. Record the gap, and do not switch to `getHostString()`, which
  would log a caller-controlled value.

### Validation

The repository's documented build and test commands.

### Completion criteria

A forged `X-Forwarded-For` cannot change the logged client address.

## Phase 21: Add structured audit events to service-common

### Workspace

../service-common

### Goal

Give every service one safe way to record who changed what, now that body logging is going away.

### Scope

A new audit event type and logger, servlet auto-configuration, tests, and the shared docs.

### Non-goals

Retention and access control, which need a hosted log store, and reads, per D6.

### Required context

R1 finding 6; R2 item 6; `CorrelationIdFilter`; `SecurityContextUtil`; `HttpLoggingConfig`.

### Execution steps

1. Add an event with timestamp, actor, operation, resource identifier, outcome and correlation ID,
   written to a dedicated `budgetanalyzer.audit` logger at INFO.
2. Auto-configure a servlet component that emits one event for each POST, PUT, PATCH and DELETE that
   maps to a handler. Use the route pattern for the operation, path variables for the resource
   identifier, and the response status for the outcome.
3. Expose the logger so Session Gateway can emit the same shape from reactive code.
4. Add tests that no event contains a body, query string, email or display name.
5. Publish to Maven Local so later phases build against the change.

### Implementation notes

Auto-configuration means the three servlet services need no code change, and a new endpoint cannot
be forgotten. Phase 35 updates the audit claims in the orchestration docs.

### Validation

The repository's documented build and test commands.

### Completion criteria

A state-changing request produces exactly one event, and the event holds no payload or personal
data.

## Phase 22: Safe logging, readiness and authorization coverage in transaction-service

### Workspace

../transaction-service

### Goal

Stop logging bodies by default, make readiness reflect the service's own dependencies, and guarantee
every new endpoint declares an authorization policy.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

PDF bounds, which are Phase 23, and service logic.

### Required context

R3 finding 6 table; R2 finding F; R4 "Method authorization (F)"; `HttpLoggingProperties` in
service-common, where both body flags default to `false`.

### Execution steps

1. Remove `include-request-body` and `include-response-body`.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add an opt-in `debug-logging` profile for synthetic-data debugging only.
4. Set `management.endpoint.health.probes.enabled` to `true`, so the probe groups also exist in
   tests and outside Kubernetes.
5. Set `management.endpoint.health.group.readiness.include` to `readinessState` plus the data stores
   the service needs in order to serve requests.
6. Add a test that reads `RequestMappingHandlerMapping`, lists every `org.budgetanalyzer` handler,
   and fails unless the method or its class has `@PreAuthorize`, with an explicit exception list.

### Implementation notes

- This trap is not in any review. Spring's default readiness group holds only `readinessState`, so
  switching the probes without step 5 would stop a database outage from removing the pod.
- Keep `/actuator/health/liveness` free of dependencies. Do not add downstream services to
  readiness. Exclude RabbitMQ unless request serving depends on it.
- `@PreAuthorize` is already enforced (R4 corrects R2's heading), and 31 of 31 handlers have it. The
  rule stops a new endpoint falling back to `authenticated()`. It says nothing about ownership
  checks.

### Validation

The repository's documented build and test commands. Confirm the effective `kubernetes` profile has
no body logging, and that a state-changing request emits one audit event.

### Completion criteria

Default configuration logs no bodies and no TRACE, readiness fails when the database is down, and an
unannotated handler fails the build.

## Phase 23: Bound PDF parsing in transaction-service

### Workspace

../transaction-service

### Goal

Stop one upload, or a few at once, from taking the API down for every user.

### Scope

The five `Loader.loadPDF` call sites, a shared loader, the import and wizard paths, tests, and docs.

### Non-goals

Choosing file-backed input or a stream cache, and a parsing worker. Both are contested, and step 1's
measurements inform them.

### Required context

R2 finding C; R3 "PDF details"; R4 "PDF parsing"; [PDFBox 3 migration guide](https://pdfbox.apache.org/3.0/migration.html).

### Execution steps

1. Measure before changing anything. Run the service under the 512Mi limit with synthetic PDFs: many
   pages, large streams and deep object trees, one at a time and concurrently. Record heap, RSS, CPU
   time and the failure mode, in `docs/`.
2. Route the five sites through one loader: `PdfTextExtractionService:47`,
   `CapitalOneBankMonthlyStatementExtractor:120`, `CapitalOneCreditYearlySummaryExtractor:137`,
   `CapitalOneCreditMonthlyStatementExtractor:160` and `BangkokBankStatementPdfExtractor:110`.
3. Cap the page count before extracting text, and cap the extracted text size.
4. Add a global concurrency limit and a per-user limit on parses. Fail fast with a clear business
   error instead of queueing.
5. Repeat step 1 and record the difference.

### Implementation notes

- No deployment or Dockerfile heap flag is set, so the JVM should default to about 128 MiB. R3 expects
  GC pressure and failing requests rather than a kill. Measure this.
- If the JVM stays up degraded, add `-XX:+ExitOnOutOfMemoryError` to the Dockerfile. Report any heap
  setting the measurements call for, because that belongs in an orchestration manifest.
- Use synthetic files only.
- The limits are per pod, which matches today's single replica.

### Validation

The repository's documented build and test commands, plus the recorded measurements.

### Completion criteria

Oversized and concurrent parses fail fast, other requests keep working during them, and the numbers
are recorded.

## Phase 24: Safe logging, readiness and authorization coverage in permission-service

### Workspace

../permission-service

### Goal

Apply the Phase 22 changes to permission-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

`deleteUser`, which is contested.

### Required context

Phase 22 notes.

### Execution steps

1. Remove both body-logging settings.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Enable the probe groups, and set the readiness group to `readinessState` plus the database.
5. Add the coverage test, listing the two `InternalPermissionController` handlers as exceptions.

### Implementation notes

This service returns user and permission data, so response bodies are the main exposure here.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as Phase 22.

## Phase 25: Safe logging, readiness and session audit events in session-gateway

### Workspace

../session-gateway

### Goal

Apply the Phase 22 logging and readiness changes, and record session lifecycle events.

### Scope

`application.yml`, `application-kubernetes.yml`, `SecurityConfig`, `LogoutController`,
`InternalSessionController`, and tests.

### Non-goals

Client-address changes, which Phase 20 records as a gap.

### Required context

Phase 22 notes; Phase 21; R3 N4 on the leftover override.

### Execution steps

1. Remove both body-logging settings from `application.yml`.
2. Remove the override and the "isolate POST timeout issue" comment from
   `application-kubernetes.yml`.
3. Change `org.budgetanalyzer` from TRACE to INFO, and add the `debug-logging` profile.
4. Set the readiness group to `readinessState` plus Redis. `probes.enabled` is already set.
5. Emit audit events for login success, login failure, logout and bulk revocation.

### Implementation notes

Do not add permission-service to readiness. It is a downstream dependency, and including it would
take the auth lane down with it. Never log session tokens or their digests in audit events; use the
internal user ID.

### Validation

The repository's documented build and test commands.

### Completion criteria

Logging matches Phase 22, and each session lifecycle event produces one audit event.

## Phase 26: Safe logging, readiness and authorization coverage in currency-service

### Workspace

../currency-service

### Goal

Apply the Phase 22 changes to currency-service.

### Scope

`src/main/resources/application*.yml` and related tests.

### Non-goals

Cache eviction and `KEYS`/`SCAN` changes, which are contested.

### Required context

Phase 22 notes.

### Execution steps

1. Remove `include-request-body`. Response bodies are already off, so remove that setting too.
2. Change `org.budgetanalyzer` from TRACE to INFO.
3. Add the `debug-logging` profile.
4. Enable the probe groups, and set the readiness group to `readinessState` plus the stores needed to
   serve requests.
5. Add the coverage test.

### Implementation notes

Decide deliberately whether Redis belongs in readiness. If a cache miss can fall back to the
database, a Redis outage should not make this service unready.

### Validation

The repository's documented build and test commands.

### Completion criteria

Same as Phase 22.

## Phase 27: Switch probes and run the outage drill (Live)

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

Phases 19-26; `docs/runbooks/tilt-debugging.md`.

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

## Phase 28: Set an explicit Redis memory budget (Live)

### Workspace

.

### Goal

Replace unbounded Redis memory with a measured budget that keeps auth data out of eviction.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, the pod limit only if measurement requires it, and
`docs/architecture/security-architecture.md:639`.

### Non-goals

Splitting Redis.

### Required context

R1 finding 8; R2's capacity estimate; R4's qualifications on `maxmemory` and `noeviction`.

### Execution steps

1. Measure session, index and maximum-size OAuth-state record sizes, base RSS, and AOF rewrite
   overhead on the pinned Redis image. This phase follows the cutover so it measures the final
   records: hashed keys, the `returnUrl` cap and the binding field.
2. Set `--maxmemory` from that data, leaving headroom below the 256Mi limit. Do not adopt R2's
   70-75% unless the measurements support it.
3. Set `--maxmemory-policy noeviction`.
4. In a disposable environment, fill Redis and record login, heartbeat and API behaviour under
   rejected writes, and recovery afterwards.
5. Replace the `allkeys-lru` claim. Put the measurements and the limits of the budget in the
   evidence file.

### Implementation notes

- `noeviction` turns a crash into failed writes, so anonymous OAuth-state growth can still block
  logins. The Phase 8 lifetime lowers the ceiling per address to about 625 live records, but this
  remains a known gap.
- `maxmemory` is not an RSS limit (R4).
- The shared cache is capped along with auth data. If its growth threatens the budget, report it
  rather than changing the policy.
- Restart Redis to apply the change, as in Phase 5.

### Validation

Orchestration static gate, and `CONFIG GET maxmemory*` as `redis-ops` after a restart. Run
`verify-credential-isolation.sh`.

### Completion criteria

The budget is backed by recorded measurements, and failure behaviour under exhaustion is documented.

## Phase 29: Exclude private destinations from the egress gateway (Live)

### Workspace

.

### Goal

Stop the egress gateway's NetworkPolicy allowing any destination on port 443, as a layer beneath the
Envoy host rules.

### Scope

`kubernetes/network-policies/istio-egress-allow.yaml`, `scripts/smoketest/verify-network-policies.sh`,
and the nearest docs.

### Non-goals

Per-caller egress identity and any `ISTIO_MUTUAL` change, which are contested.

### Required context

R1 "Treat egress controls as layered containment"; `kubernetes/istio/egress-routing.yaml`.

### Execution steps

1. In `allow-istio-egress-external-egress`, replace the port-only rule with an `ipBlock` of
   `0.0.0.0/0` that excepts `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16` and
   `100.64.0.0/10`. Keep port 443.
2. Cover IPv6 the same way if the cluster has it.
3. Add a static check for the exclusions.
4. Prove from the gateway pod that the Kubernetes API service is unreachable on 443.
5. Confirm a real login reaches Auth0 and a currency import reaches FRED.

### Implementation notes

R1 qualifies this with "where the hosting environment supports them". Calico enforces `except`
locally. Record that a hosted CNI must too. This limits where the gateway can connect; it does not
tell the gateway which service is calling.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-network-policies.sh`, and
`./scripts/smoketest/verify-istio-ingress.sh`.

### Completion criteria

The gateway cannot reach private ranges on 443, and both external integrations still work.

## Phase 30: Require TLS on the PostgreSQL server side (Live)

### Workspace

.

### Goal

Make PostgreSQL refuse plaintext connections, instead of relying on clients to request TLS.

### Scope

`kubernetes/infrastructure/postgresql/`, `scripts/smoketest/verify-transport-encryption.sh`, and the
nearest docs.

### Non-goals

Client configuration, which already uses `sslmode=verify-full`, and certificate generation.

### Required context

R2 finding H; R3 "Postgres `hostssl`"; `docs/architecture/security-architecture.md`.

### Execution steps

1. Add a ConfigMap holding a `pg_hba.conf` with a `local` scram rule and `hostssl` scram rules for
   IPv4 and IPv6, and no `host` rules.
2. Mount it read-only, and pass `-c hba_file=<path>` in the container args.
3. Confirm the probes and `scripts/ops/reset-databases.sh` still work.
4. Add a negative check to `verify-transport-encryption.sh`: `sslmode=disable` must fail with no
   `pg_hba.conf` entry, and `verify-full` must still connect.

### Implementation notes

- Use `hba_file` because `PGDATA/pg_hba.conf` is written only on an empty volume, so changing it
  would not reach an existing cluster.
- Keep this file out of the `postgresql-init` ConfigMap. That one is mounted whole into
  `/docker-entrypoint-initdb.d`.
- The `-h 127.0.0.1` probes use the default `sslmode=prefer`, so they keep working over TLS.
- `statefulset.yaml:71` only sets the auth method (R3 corrects R2's citation). The actual `host` rule
  comes from the image's default.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-transport-encryption.sh`. Confirm all three
services start and serve requests.

### Completion criteria

A plaintext connection is refused by the server, and every service still connects.

## Phase 31: Separate migration roles from runtime roles (Live)

### Workspace

.

### Goal

Stop each service's runtime database role from owning its database or changing its schema.

### Scope

`kubernetes/infrastructure/postgresql/configmap.yaml`, the three service deployments, `Tiltfile`,
`scripts/lib/secrets-only-expected-keys.txt`, `scripts/ops/`, a runtime check, and the nearest docs.

### Non-goals

An out-of-process migrator, per D5, and service code.

### Required context

R2 finding H; `scripts/ops/reset-databases.sh`; `kubernetes/production/README.md`.

### Execution steps

1. For each database, add a `<service>_migrator` role that owns the database and schema. Reduce the
   runtime role to `SELECT`, `INSERT`, `UPDATE` and `DELETE` on tables and `USAGE, SELECT` on
   sequences, with `ALTER DEFAULT PRIVILEGES` so new tables stay reachable.
2. Update `01-init-databases.sh` and `scripts/ops/reset-databases.sh`.
3. Add an idempotent ops script for existing volumes that reassigns ownership and applies the grants.
4. Add the migrator credentials to the Tiltfile, the bootstrap secret and
   `secrets-only-expected-keys.txt`.
5. Set `SPRING_FLYWAY_USER` and `SPRING_FLYWAY_PASSWORD` on the three deployments.
6. Add a runtime check that each runtime role is refused `CREATE TABLE`, `ALTER TABLE` and
   `DROP TABLE`, and that normal reads and writes work.
7. Update the production secrets contract in `kubernetes/production/README.md`.

### Implementation notes

- Init scripts run only on an empty data directory, which is why step 3 is needed.
- All three services set `ddl-auto: validate`, and their schemas come from Flyway, so the runtime
  role needs no DDL. Confirm that the Spring Modulith tables in currency-service came from Flyway.
- Spring Boot binds the two environment variables, so no service change should be needed. Confirm
  that Flyway connects as the migrator.
- Record D5's limit in the evidence file.

### Validation

Orchestration static gate, the new runtime check, and a clean `scripts/ops/reset-databases.sh` run
after which all three services migrate and serve requests.

### Completion criteria

No runtime role owns a database or can change a schema, and migrations still run at startup.

## Phase 32: Move to a supported RabbitMQ series and report support dates (Live)

### Workspace

.

### Goal

Get off a series with no community support, and make support dates visible before they pass.

### Scope

`kubernetes/infrastructure/rabbitmq/`, the image inventories, a support-date report,
`docs/dependency-automation.md`, and the nearest docs.

### Non-goals

Gating releases on support dates, because vulnerability gating is deferred by agreement.

### Required context

R2 finding B; R3 and R4 on support status; `docs/dependency-automation.md`, which must be read before
changing this area; the upstream upgrade guide for the selected series.

### Execution steps

1. Record the version inside the pinned digest. R3 and R4 could not confirm it is 3.13.7.
2. Select the newest community-supported series that has a `linux/arm64` image and a documented path
   from 3.13. If it needs an intermediate step, follow that step.
3. On an existing volume, enable all stable feature flags on 3.13 before changing the image.
4. Confirm no definition uses classic mirrored queues.
5. Update the digest pin and any configuration the new series requires.
6. Add `scripts/lib/runtime-support-windows.txt`, listing each runtime line from the quarterly review
   with its support end date and source, and a report script that prints anything past or within 90
   days of its end date.
7. Name the report in the quarterly review in `docs/dependency-automation.md`.

### Implementation notes

R3 is right that commercial support continues, and R3 and R4 are right that nothing shows a quarterly
review ran. The conclusion holds anyway: no commercial contract exists, so this series is unsupported
here. The report needs no network and turns a calendar task into a check, but a person still keeps
the dates current.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-transport-encryption.sh`, and a currency import
that publishes and consumes an event.

### Completion criteria

The broker runs a supported series over TLS only, messaging works, and the report flags a past date.

## Phase 33: Complete the edge contract verifier (Live)

### Workspace

.

### Goal

Finish the single cross-layer verifier, so the seams between components stay tested.

### Scope

`verify-edge-contract.sh`, `scripts/smoketest/verify-security-guardrails.sh`, and `scripts/README.md`.

### Non-goals

Tests for contested behaviour, such as two-cookie requests and `KEYS`/`SCAN` denial. Add those if the
contested items are decided that way.

### Required context

R2 "Define the edge contract once"; R3 N3; R4 "Define and test one edge contract"; Phases 1-4.

### Execution steps

1. Add a "Forged Identity" section. Seed a session with empty roles and permissions, send forged
   `X-User-Id`, `X-Roles` and `X-Permissions: users:read` headers to `/api/v1/users`, and assert 403.
2. Add a positive control: a seeded session that really holds `users:read` gets past the gate.
3. Confirm the verifier covers the boundary, failure statuses, response headers and forged identity.
4. Wire it into `verify-security-guardrails.sh` and update `scripts/README.md`.

### Implementation notes

- This goes through the real chain, unlike `p3-header-echo`, which bypasses NGINX. It relies on a
  real permission check instead of an echo backend. R3 tested the forged-header case at Envoy and
  found a coverage gap, not an exposure.
- Cookie stripping keeps its Phase 2 stand-in test, because NGINX has no route to an echo backend.
  Say so in the verifier's header comment.

### Validation

Orchestration static gate, and `./scripts/smoketest/verify-edge-contract.sh` through the aggregate
wrapper.

### Completion criteria

The aggregate gate fails if any section of the edge contract regresses.

## Phase 34: Run the disposable local API tests (Live)

### Workspace

../budget-analyzer-api-tests

### Goal

Prove the application works end to end after every change.

### Scope

The local API test run, using disposable local credentials.

### Non-goals

Staging, production, and new coverage.

### Required context

The repository's `AGENTS.md`.

### Execution steps

1. Confirm the stack left by earlier phases is running. If it is not, stop and report.
2. Run the local suite through `./run-tests`.
3. Record the result in this repository's `docs/` folder, with no credentials.

### Implementation notes

A failure in a service is a finding for that repository. Do not weaken a test to pass it.

### Validation

`./run-tests` against the local environment.

### Completion criteria

The local suite passes, or every failure is reported with its owner.

## Phase 35: Full verification and release handoff (Live)

### Workspace

.

### Goal

Prove the combined change and record the human-owned release steps.

### Scope

Full verification suites, the evidence file, and remaining docs.

### Non-goals

Releasing images, changing production pins, or starting work on contested items.

### Required context

`scripts/README.md`; the evidence file; the sibling evidence from Phases 23 and 34.

### Execution steps

1. Run the aggregate smoketest.
2. Confirm the Phase 1 probes still fail after every later change.
3. Update the audit claims at `security-architecture.md:176` and `:451` to describe Phase 21's events
   and D6's scope.
4. Confirm no doc in the scope table still contradicts the code.
5. Record the human-owned handoff: release service-common, then session-gateway, ext-authz, the three
   services and the frontend, and update `kubernetes/production/apps/deployment-manifest.yaml` and
   `image-inventory.yaml`. Release them together, because the Phase 17 policy blocks the pinned
   Session Gateway's login call.
6. Note the production secrets and configuration added by Phases 17 and 31.
7. Summarize evidence per scope item, and note every remaining gap: Session Gateway client address,
   audit retention and access, anonymous OAuth-state growth, and the migrator credential's location.

### Implementation notes

Passing offline checks prove the production reference renders. They do not prove the pinned images
support the new probes or cookie contract, so do not claim parity.

### Validation

```bash
INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python \
  ./scripts/smoketest/smoketest.sh
```

### Completion criteria

All 31 scope items have recorded evidence, and the release handoff is explicit.
