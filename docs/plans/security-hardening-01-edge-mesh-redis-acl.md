# Security Hardening 01: Edge, Mesh and Redis ACL

**Status:** Draft for iteration. None of D1–D6 applies.

This is plan 01 of five that together implement every finding from the four 2026-11-01 security
reviews that holds up against the code and that no review disputes, with the decisions in the
[contested issues](../research/security-review-contested-issues-2026-11-02.md) document applied.
This plan narrows the mesh policies, proves the public/internal boundary, corrects the NGINX
backend header and ext_authz failure contracts, hardens ingress headers and the CSP, replaces the
Session Gateway Redis `+@all` grant, and reconciles the documentation with current behaviour.
Phase numbers without a plan refer to this plan.

**Order:** 01 of 5

**Depends on:** nothing.

**Repositories:** orchestration.

| Label | Review |
| --- | --- |
| R1 | [First review](../research/application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](../research/application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](../research/application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](../research/application-architecture-security-review-assessment-2026-11-01.md) |

R3 and R4 each assessed R1 and R2, but neither assessed the other. R1 predates every later finding,
so its silence on those findings is not agreement or disagreement.

## Decisions

None applies.

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

- [#3, encoded-path traversal](../research/security-review-contested-issues-2026-11-02.md#3-encoded-path-traversal-and-rejecting-):
  narrow the mesh rules now without waiting for an exploit reproduction, and reject decoded `;` at
  NGINX in Phase 3. Phase 1 adds `%2e%2e;` and side-effect assertions, and records an inconclusive
  baseline as "not reproduced".
- [#12, NGINX route files](../research/security-review-contested-issues-2026-11-02.md#12-generating-the-nginx-route-files):
  no route generator or parity parser. Phase 3 shares the API routes through one include.
- [#1, primary CSRF control](../research/security-review-contested-issues-2026-11-02.md#1-primary-csrf-control):
  Phase 5's `form-action` also permits the IdP logout destination. The Origin and POST cutover is
  in plan 02.
- [#11, HSTS flags](../research/security-review-contested-issues-2026-11-02.md#11-hsts-includesubdomains-and-preload):
  neither `includeSubDomains` nor `preload` by default. Spring's default writer is not proof of the
  client-visible header, so Phase 5 verifies the final header.
- [#8, separate internal ports](../research/security-review-contested-issues-2026-11-02.md#8-separate-internal-ports):
  separate internal ports stay deferred.
- [#2, Redis enumeration](../research/security-review-contested-issues-2026-11-02.md#2-redis-enumeration-after-hashing):
  Phase 6 covers only Session Gateway. The currency-service grant is narrowed in plan 03.
- [Severity disputes](../research/security-review-contested-issues-2026-11-02.md#severity-disputes):
  these plans assign no comparable severity scores.
- [Work order](../research/security-review-contested-issues-2026-11-02.md#work-order): this plan is
  the short initial edge, ACL and credential-forwarding block.

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

No `;` rejection at NGINX or the ingress, no separate ports, and no service code. (amended per
contested #3: NGINX rejects decoded `;` in Phase 3.)

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
   - forms: `..%3b`, `..%3B`, `%2e%2e%3b`, `..;`, `%2e%2e`, `..%2f`, `..%5c`, `%252e%252e%252f`, and
     `%2e%2e;` (amended per contested #3)
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
  (amended per contested #3) Also assert absence of internal handler side effects, not just a
  non-200 response.
- The Prometheus policy is separate and must remain unchanged.
- If the baseline shows the traversal is already blocked, record that and continue. Narrowing is
  independently agreed. (amended per contested #3) An inconclusive baseline stays
  "not reproduced"; it must not become a claim of safety or an automatic severity downgrade.
- Plan 02, Phase 14 replaces the `.../permissions` rule from step 7 with the new sync call.

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

## Phase 3: Share the NGINX API routes and reject decoded semicolons (Live)

### Workspace

.

### Goal

(added per contested #3 and #12) Remove the duplicated API route blocks before writing tooling to
police them, and reject decoded semicolons at NGINX.

### Scope

`nginx/nginx.k8s.conf`, `nginx/nginx.production.k8s.conf`, a new `nginx/includes/api-routes.conf`,
the includes ConfigMap in `Tiltfile` and `kubernetes/production/apps/kustomization.yaml`,
`nginx/README.md`, and the nearest docs.

### Non-goals

A route generator or custom parity parser, and the intentional frontend differences between the
two files.

### Required context

Contested issues #3 and #12; `nginx/README.md`.

### Execution steps

1. Put the 11 API location blocks, including both unknown-route rejections, in one
   `nginx/includes/api-routes.conf` included by both server blocks.
2. Add a server-level `if ($uri ~ ";") { return 400; }` to that include.
3. The five identical `/api-docs` blocks, including the two regex locations, can likewise share an
   include.
4. Ship the includes through the existing includes ConfigMap in Tilt and the production
   kustomization.
5. Keep the intentional frontend differences in their existing files.
6. Rerun the Phase 1 boundary section and record the `;` results in the evidence file.

### Implementation notes

- Sharing blocks prevents edits to those blocks drifting, but inherited server settings and
  location precedence still affect behaviour.
- NGINX does not protect the direct Session Gateway lane; Phase 1's mesh rules cover it.
- The checked-in OpenAPI document has 29 paths and none contains `;`. This supports rejecting
  matrix-parameter syntax, but it is not a compatibility proof for every client.

### Validation

Orchestration static gate, `nginx -t` on both complete configurations with their mounted includes,
and focused probes for routing, query preservation, security headers, unknown API paths and encoded
inputs. Run `./scripts/smoketest/verify-edge-contract.sh`.

### Completion criteria

Both configurations use one copy of the API routes, a decoded `;` returns 400 on the NGINX lane, and
routing probes pass.

## Phase 4: Bound ext_authz failures and correct the contract (Live)

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
- Until plan 03, Phase 11, a Redis outage also fails ext-authz's probes, so the Redis case may surface as a
  connection failure rather than the authorizer's own 503. Either must reach the client as a 503.
- The frontend does not depend on the JSON body. `client.ts` handles an unstructured error, and
  `useUsers.ts:29` checks only the status.

### Validation

Orchestration static gate and `./scripts/smoketest/verify-edge-contract.sh`.

### Completion criteria

Every failure path returns a 503 within the timeout and never reaches NGINX, a missing session still
returns JSON 401, and the contract row matches the observed responses.

## Phase 5: Harden ingress headers and the CSP (Live)

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

`includeSubDomains`, `preload`, and the fixed redirect URI, which is plan 02, Phase 2.

### Required context

R2 findings G and H; R3 "HSTS details"; R4 "HSTS (G)"; `nginx/README.md`.

### Execution steps

1. Add a `ResponseHeaderModifier` filter to every rule of `auth-route`, `api-route` and `app-route`
   that sets `Strict-Transport-Security: max-age=31536000`.
2. Add a `RequestHeaderModifier` filter to every rule that removes `Forwarded`, `X-Forwarded-Host`,
   `X-Forwarded-Port`, `X-Forwarded-Prefix` and `X-Forwarded-Ssl`. Leave `X-Forwarded-For`, which
   the ingress appends to, and the existing `X-Forwarded-Proto` handling.
3. Add `form-action 'self'` to the three CSP includes, and remove `X-XSS-Protection` from them.
   (amended per contested #1) Permit the configured IdP logout destination alongside `'self'`
   where needed, without a wildcard, because logout becomes a form POST with a 303 redirect to the
   IdP in plan 02, Phase 6.
4. Add a "Response Headers" section to `verify-edge-contract.sh`:
   - HSTS appears on `/`, an authenticated `/api/*` request, `/auth/v1/session` and
     `/oauth2/authorization/idp`, with one value on each
   - login start with a forged `X-Forwarded-Host` still builds `redirect_uri` from the real host
5. Add the new headers to `verify-edge-browser-hardening.sh`, and update `nginx/README.md` and the
   CSP posture section.

### Implementation notes

- Use `set`, not `add`. (amended per contested #11) Spring Security's default writer sends
  `max-age=31536000 ; includeSubDomains` only when the application sees an HTTPS scheme. That is
  source evidence, not an observation of the client-visible response, so verify the final header on
  both lanes and ensure ingress ownership leaves no duplicate or conflicting value. Keep neither
  `includeSubDomains` nor `preload` by default.
- Local replies such as ext_authz denials and 429s may not carry the header. That is fine as long as
  ordinary responses do.
- Session Gateway is the only consumer of the removed headers today. Removing them on every route
  keeps a future consumer safe.
- No SPA form posts natively; each uses `onSubmit`, so `form-action 'self'` breaks nothing today.
  (amended per contested #1) Logout becomes a native form POST in plan 02. Redirect enforcement
  must be checked in supported browsers; plan 02, Phase 16 verifies login, logout and hostile
  submissions with the final CSP. Do not defer this compatibility check on the basis that the
  directive is absent today.
- `kubernetes/production/gateway-routes` reuses these routes, so the production reference inherits
  the change.

### Validation

Orchestration static gate, `./scripts/smoketest/verify-edge-contract.sh`,
`./scripts/smoketest/verify-edge-browser-hardening.sh`, and a browser login.

### Completion criteria

All four paths send one HSTS value, a forged forwarded host has no effect on `redirect_uri`, and the
app runs with no CSP violations.

## Phase 6: Replace the Session Gateway Redis `+@all` grant (Live)

### Workspace

.

### Goal

Give Session Gateway only the Redis commands it uses, and replace the verifier that locks in the
over-grant.

### Scope

`kubernetes/infrastructure/redis/start-redis.sh`, `scripts/smoketest/verify-session-architecture.sh`,
`scripts/smoketest/verify-credential-isolation.sh`, and the nearest docs.

### Non-goals

The currency-service `+keys +scan` grant (amended per contested #2: narrowed to
`+scan` in plan 03, Phases 10 and 12), and any Redis split.

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

## Phase 7: Reconcile documentation with current behaviour

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
(plan 02, Phase 14), audit logging (plan 05, Phase 3), and eviction policy (plan 04, Phase 1).

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
