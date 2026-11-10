# Security hardening implementation review: correctness and over-engineering

Date: 2026-11-09. Orchestration HEAD `d7fc2d3`. Diff sizes are measured from
`97fbb5d`, the commit before the hardening work. Sibling repositories were read
at their current checkouts.

This is an independent source review of the completed `security-hardening-*`
plans. A separate review of the same work,
[security-hardening-implementation-review-2026-11-09.md](security-hardening-implementation-review-2026-11-09.md),
was already in the working tree, untracked, when this one was written. It was
not changed. Where its findings overlap with mine, I checked them against the
source; the [last section](#relation-to-the-other-review) lists where we agree
and differ.

Code references use `path:line`. Sibling paths such as `../session-gateway/...`
are relative to the orchestration repository root.

## Evidence boundary

- **Read:** the plans, the
  [evidence record](security-consensus-hardening-evidence.md), the changed
  manifests, NGINX includes, render scripts, verifiers and fixtures, and the
  changed code in session-gateway, ext-authz, service-common,
  permission-service, currency-service and budget-analyzer-api-tests.
- **Not run:** smoketests, API tests, `verify-security-guardrails.sh`,
  `verify-edge-contract.sh`, the static guardrail suite, Docker reproductions
  and live requests. The user reported that the smoketests and API tests pass.
  This review relies on that report.
- Every finding comes from reading code and recorded evidence. None was
  reproduced in this review. The one runtime result cited, for C3, is the
  other review's reproduction.

## Verdict

The runtime changes are correct and mostly proportionate. I found no
authentication or authorization bypass. The following do what the plans say:

- Session hashing, the absolute lifetime and the OAuth browser binding.
- The Redis ACLs, ext_authz failure handling, exact Origin and ingress path
  hardening.
- The NGINX credential stripping, egress exclusions and PostgreSQL TLS.

The weak part is the verification layer, not the controls:

| Area | Lines added since `97fbb5d` |
| --- | --- |
| Runtime config (`kubernetes`, `nginx`, `deploy`, `Tiltfile`) | 724 in 36 files |
| Scripts | 5,136 in 33 files |
| Static guardrail fail fixtures | 842 in 30 files |
| Docs | 10,365 in 37 files |

Much of the new verification asserts the exact shape of today's configuration,
not the security property. As a result it breaks on harmless changes (C5)
while still missing real regressions (C2). One verifier can destroy the local
data it promises to protect (C4).

The most important open item is not new. One ordinary user can still fill the
shared Redis budget through the currency cache, which blocks login and
heartbeat for everyone (C1).

## Correctness findings

Severity reflects user or security impact in this local reference
architecture. It is not a CVSS score.

### C1 — High: the currency cache can exhaust the shared Redis budget (open, not new)

**Owner:** currency-service. Orchestration gets involved only if storage is
split.

- Every distinct `(currency, start, end)` range is a separate cache entry with
  a 1-hour TTL and no size or count bound.
- These entries share the `--maxmemory 128mb --maxmemory-policy noeviction`
  budget with sessions and OAuth state (`kubernetes/infrastructure/redis/start-redis.sh`).
- The [plan 04 measurement](security-consensus-hardening-evidence.md#shared-cache-growth-reported-not-changed)
  shows that one user with the default `currencies:read` permission filled the
  budget in about 100 reads. After that:
  - heartbeats returned `503`;
  - login starts redirected to `/oops`;
  - uncached exchange-rate reads returned `500`.
- This lasts for up to one hour.

`noeviction` is correct for authentication data. The real problem is that a
Redis ACL limits commands and keys, not memory. Any credential that can write
unbounded data therefore controls availability for every other tenant of the
instance. Switching cache eviction from `KEYS` to `SCAN` (plan 03 P11/P13) does
nothing for capacity.

Separately, currency-service returns `500` when a cache write is rejected,
even though the database read succeeded. Cache writes should fail open.

**Recommendation:**

- Stop caching arbitrary date ranges, or cache only fixed, bounded keys.
- Make cache-write failure non-fatal.
- Use a separate cache Redis only if a real cache is still needed after that.
- Do not weaken `noeviction` on the auth instance.

### C2 — Medium: the static mesh guard ignores additive ALLOW policies and Session Gateway

Owner: orchestration. Plan 01 P1. This confirms F4 in the other review.

`scan_istio_authorization_policy_contract`
(`scripts/guardrails/verify-static-security-manifests.sh:1241`) runs two
checks:

1. `default/default-deny-all` exists and has an empty spec (`:1296–1305`).
2. Rules that admit the nginx-gateway principal on three hardcoded apps
   (`BACKEND_APPS`, `:1252`) restrict paths (`:1308–1335`).

Everything else passes unchecked:

- A namespace-wide or selectorless `ALLOW` policy. `app` is `None` at `:1310`,
  so `:1311` skips it.
- An `ALLOW` rule with no `from`, or with principals other than nginx-gateway
  (`:1320`).
- The Session Gateway, ext-authz and nginx-gateway policies, which hold the
  ingress-to-auth-lane path restriction.
- Any new backend service. `BACKEND_APPS` is hardcoded.

Istio ALLOW policies are additive. An empty-spec deny-all baseline does not
stop a later broad ALLOW from opening access. The other review ran the checker
against both kinds of mutation, and it passed both. I did not repeat that.

**Recommendation:** extend the same Python block. Do not write a policy
simulator.

- Fail on any `ALLOW` policy in a mesh namespace other than `default-deny-all`
  that has no selector.
- Fail on any rule on a protected workload without `from.source.principals`.
- Require a `to.operation.paths` restriction on Session Gateway's ingress rule.
- Derive the backend list from `kubernetes/services/` instead of a constant.
- Add the two mutations as fail fixtures.

### C3 — Low-Medium: bulk session revocation fails on a large session index

Owner: session-gateway. This confirms F3 in the other review, but I rate it
lower.

- `../session-gateway/src/main/resources/redis/delete-user-sessions.lua:5–14`
  passes every index member to one `DEL` through `unpack`. Redis's embedded
  Lua caps that at about 8,000 values. The other review reproduced the failure
  at 8,000 members on the pinned Redis 7.4 image.
- Index members are removed only on logout (`SessionWriter.deleteSession`).
  Sessions that simply expire leave stale members behind.
- `create-session.lua` and `conditional-update.lua` keep extending the index
  TTL while any session is active, so stale members can accumulate.

Why the impact is bounded:

- Reaching about 8,000 members takes about 8,000 completed IdP logins for one
  user, without the index ever expiring. Login initiation is limited per client
  address to a burst of 25 and 1 per second
  (`kubernetes/istio/ingress-rate-limit.yaml:74–76`), so that takes at least
  about 2.2 hours of sustained, deliberate activity.
- On failure, permission-service has already committed the deactivation. It
  returns `503` with "retry is safe"
  (`../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserService.java:177–181`).
  The message
  is wrong, because every retry fails the same way.
- Heartbeat rechecks account status, so existing sessions die within the
  900-second sliding TTL. The realistic harm is an insider who expects to be
  disabled keeping one more session window of access, plus a permanently
  failing admin action.

**Recommendation:** delete in batches of about 1,000 inside the same script,
then delete the index. Optionally, `SREM` members whose hash no longer exists
during `create-session` so the index stays small. Add a regression test with
10,000 members.

### C4 — Medium-Low: the edge verifier destroys a load-test fixture it says it protects

Owner: orchestration. Plans 01 and 05. This confirms F2 in the other review.

Five sections refuse to run when `.loadtest/session-pool.txt` exists, because
teardown "would remove it". Each one calls `fail` and returns
(`scripts/smoketest/verify-edge-contract.sh:439–441`, `:664–666`, `:970–972`,
`:1147–1149`, `:1449–1451`). `main` then keeps going.

The last section, `verify_response_headers` (`:1588–1590`), calls
`seed_fixture` (`:361–365`) with no such check. What follows:

1. The seeder overwrites the pool file (`scripts/loadtest/seed-loadtest-users.sh:188`).
2. The teardown removes the fixture by pattern: every `usr_loadtest_%` user,
   role and transaction, and every indexed session
   (`scripts/loadtest/teardown-loadtest.sh:99–112`, `:139–152`).
3. If the section fails partway, the EXIT trap (`:269–276`) runs the same
   teardown.

So a run that reports "the fixture is active, leaving it alone" five times
deletes it anyway. The data is local and synthetic, which limits the impact,
but the guard is directly contradicted.

**Recommendation:** run one ownership check in `main` before any section,
exit on failure, and delete the five copies. If the check lives in
`seed_fixture`, no new section can forget it.

### C5 — Medium-Low: edge-verifier counter checks are flaky under concurrent traffic

Several assertions compare global counters before and after a probe window:

- `rbac.denied` must rise by exactly the probe count (`:726`, `:1032`).
- The NGINX and Session Gateway sidecars must record no requests from the
  ingress (`:731`, `:736`, `:1037`, `:1042`, `:1315`).

`sidecar_requests_from_ingress` (`:620–634`) sums every `istio_requests_total`
series from the ingress workload, with no filter on path or request. An open
SPA tab in the window adds requests to these counters and fails the run
spuriously. So does a sidecar restart that resets them.

The marker-based NGINX log checks that follow (for example `:740`) already
prove that the probes did not reach NGINX. They are robust to concurrent
traffic.

**Recommendation:**

- Drop the NGINX sidecar equality checks wherever a marker check exists.
- Relax `rbac.denied` to "rose by at least N", or read the path-hardening
  filter's own stat.
- State in the verifier header that the Session Gateway counter check needs a
  quiet stack.

### C6 — Medium-Low: exact-inventory assertions break on legitimate changes

- **Live check** (`verify-edge-contract.sh:573–617`): the enforcing RBAC
  filters must be exactly `{path-hardening, envoy.filters.http.rbac}`, and
  Istio's RBAC filter must carry only `ingress-exact-origin` (`:609`, `:611`).
  Any new ingress `AuthorizationPolicy`, even an unrelated DENY, fails the
  semicolon section with a message that blames path hardening.
- **Static check** (`verify-static-security-manifests.sh:1691`): the
  path-hardening `typed_config` keys must be exactly `{"@type", "rules"}`.
  Adding `stat_prefix` or `shadow_rules` fails it. The exact-origin scan
  (`:1768–1907`) also pins exact key sets.

These checks protect attribution: they ensure that the 403 came from the
intended filter. Attribution can be checked directly with that filter's own
stat or response body.

**Recommendation:** assert the properties, not the full inventory:

- the path-hardening filter is present;
- it sits ahead of `ext_authz`;
- it denies the must-deny vectors and allows the must-allow vectors.

### C7 — Low: the conflicting `X-Frame-Options` comes from NGINX plus Spring

The evidence record lists this as "not investigated". The cause:

- The backends' Spring Security defaults send `X-Frame-Options: DENY`.
- NGINX adds `add_header X-Frame-Options "SAMEORIGIN" always;`
  (`nginx/includes/security-headers-{strict,dev,docs}-csp.conf:2`, included at
  server level at `nginx/nginx.k8s.conf:88`).
- NGINX `add_header` does not replace upstream headers, so responses carry
  both values.

Browsers ignore conflicting XFO values. However, the same includes send CSP
`frame-ancestors 'self'`, which takes precedence in current browsers, and these
are JSON responses. There is no practical exposure.

**Recommendation:** add `proxy_hide_header X-Frame-Options;` to the shared
backend include, so the edge owns frame policy in one place.

### C8 — Low: smaller items

- **Unused Redis grant.** The Session Gateway ACL grants `+hmset`
  (`kubernetes/infrastructure/redis/start-redis.sh:9`). No Session Gateway code
  issues it: writes are `HSET` inside Lua and reads are `HGET`/`HGETALL`.
  `scripts/smoketest/verify-credential-isolation.sh:551` asserts that `HMSET`
  succeeds, which entrenches the grant. Remove both.
- **CSP and logout URL coupling.** CSP `form-action` allows only the issuer
  origin. Session Gateway's logout URL can be overridden with
  `IDP_LOGOUT_URL_TEMPLATE` (`../session-gateway/src/main/resources/application.yml:92`).
  An override to a different origin would break logout under CSP, with no
  check linking the two. Document the constraint next to the override.
- **Path-hardening anchor.** `kubernetes/istio/ingress-path-hardening.yaml`
  inserts before `envoy.filters.http.ext_authz`. If that filter is ever absent,
  the patch silently does not apply. The live verifier catches this; the static
  suite does not. This is acceptable, because losing `ext_authz` is the larger
  failure.
- **Tilt fails to load without an issuer.** Tilt now refuses to load when
  `AUTH0_ISSUER_URI` is missing or invalid (`Tiltfile:694–700`). That fails
  closed, which is reasonable, but it is a new first-run failure mode. Make sure
  the getting-started docs mention it.
- **Audit scope.** `AuditRequestInterceptor` is an MVC interceptor. Requests
  rejected in the Spring Security filter chain never reach it, so they are not
  audited. This matches the documented scope (state-changing requests that
  reach a handler), but say so explicitly in `security-architecture.md` if it
  is not already there.
- **Interpreter isolation.** `deploy/scripts/render/production-routes.sh:77`
  and `scripts/smoketest/verify-edge-browser-hardening.sh:624` call `python3`
  without `-I`. The Tiltfile and the other new call sites use `-I`.

## Over-engineering findings

### O1 — An Envoy RBAC matcher reimplemented in embedded Python

`ingress_origin_config_problem` (`scripts/smoketest/verify-edge-contract.sh:800–933`)
takes about 130 lines. It parses the live config dump and re-evaluates the
generated RBAC policy with a hand-written model of Envoy's string and header
matching, against must-deny and must-allow vectors. The section then sends the
same Origin cases to the real Envoy.

The simulator proves nothing the live probes do not, and it is the code most
likely to disagree with Envoy after an upgrade (it reports "unmodelled
matcher").

**Recommendation:** replace it with "the policy is present on every ingress
pod", and rely on the live probes.

### O2 — Two YAML parsing styles in one guardrail

`scan_istio_ext_authz_denial_contract` (`verify-static-security-manifests.sh:1149–1235`)
parses `istiod-values.yaml` with `grep -c` and `awk` at fixed indentation. The
other new Istio checks in the same script use PyYAML. Re-indenting the file, or
moving the provider block, produces a confusing failure.

**Recommendation:** port it to the PyYAML pattern used everywhere else. That
takes about 30 lines.

### O3 — CIDR set arithmetic for an egress invariant

The egress check (`:1909–2078`, with `uncovered_private` at `:1971` and
`check_external_policy` at `:2023`) computes whether any combination of
additive NetworkPolicies re-allows private ranges.

The invariant could be stated more simply, and more strictly: in
`istio-egress`, only the named external policy may carry egress `ipBlock`
rules, and it must match the expected `except` list exactly.

This is a judgment call. The current check is correct, but it is about three
times larger than the rule it enforces.

### O4 — CSP issuer validation beyond what is emitted

`issuer_origin` (`deploy/scripts/render/render-csp.py:17–44`) validates the
issuer's path, percent escapes and IPv6 zone identifiers, even though only
`scheme://host[:port]` is emitted. The input is operator configuration, not
attacker input. The test carries 19 invalid-issuer cases
(`scripts/guardrails/verify-edge-headers.py:41–45`), several of which exercise
those irrelevant branches.

**Recommendation:** keep the HTTPS, hostname and port checks and the
rejection of characters that are unsafe in a header. Drop the path checks and
their cases.

### O5 — Duplicated Docker NGINX harnesses

`scripts/guardrails/verify-nginx-backend-headers.sh` (256 lines) and
`scripts/guardrails/verify-nginx-shared-routes.sh` (259 lines) each carry their
own image selection, network-less container start, cleanup trap and pass/fail
reporting. Both purposes are justified. In particular, NGINX-layer `;`
rejection cannot be observed live, because the ingress rejects first.

**Recommendation:** merge them into one script, or move the shared code into
`scripts/lib/`.

### O6 — Cross-repo import of private test internals

`scripts/smoketest/verify-oauth-browser-binding.py` inserts
`../budget-analyzer-api-tests/src` into `sys.path` and imports private
`api_tests.*` modules. A refactor in api-tests can therefore break an
orchestration smoketest without either repo's own checks noticing.

**Recommendation:** move this test into api-tests, which owns that client, or
make it self-contained.

### O7 — The static suite runs twice per aggregate smoketest

`scripts/smoketest/smoketest.sh:115–116` runs the static suite, then
`verify-security-guardrails.sh` runs it again. This agrees with the other
review's O1. Let the aggregate run skip the wrapper's static step.

### O8 — Documentation volume

The 10,365 doc lines include a 2,867-line evidence record. As a one-time audit
record, that is acceptable. Keep it closed. Future changes should update the
architecture docs and verifiers, not append more evidence prose. The
exact-Origin control is described in three places, which is reasonable for its
importance.

## Verified correct

These were read and found consistent with the plans. Each is one line; details
are in the evidence record.

- **Redis.** The Lua scripts touch only granted commands, and ACLs apply to
  commands inside Lua. Each credential's key patterns match its code paths. The
  currency-service `+keys` grant was removed in favor of `SCAN` with batched
  `DEL`.
- **OAuth binding.** The `__Host-BA_OAUTH_BINDING` cookie is compared in
  constant time before an atomic `DEL == 1`. A lost race fails closed.
- **Absolute lifetime.** `min(sliding, createdAt + max)` is applied at the
  writer, configuration validation requires `max >= ttl`, both readers check
  `expires_at`, and `EXPIRE GT` is applied only to an existing index.
- **Session keys.** Both services use SHA-256 session keys and the
  `__Host-BA_SESSION` cookie (SameSite Strict). There is no dual-format path.
- **ext_authz.** The authorizer has a 1-second timeout, `statusOnError: 503`
  and `failOpen: false`, and only `content-type` reaches the client on deny.
  The ext-authz server has finite timeouts. `/livez` is static and `/readyz`
  pings Redis.
- **Logout and heartbeat.** Both use POST. Logout returns `303` to the IdP,
  and an exact-Origin DENY covers both browser lanes.
- **Forwarded headers.** HTTPRoutes strip caller-supplied forwarded headers
  and set HSTS. NGINX sets `X-Forwarded-Proto https` and clears `Cookie` and
  `Authorization` before backends.
- **Path hardening.** The regex `^[^?]*(;|%(25)*3[bB]).*$` runs after HCM path
  normalization and before `ext_authz`.
- **Forged identity.** The verifier sends forged identity headers with an
  empty-permission session and gets `403`, gets `401` with no session, and has
  a `200` positive control.
- **Egress.** The ipBlock excepts cover RFC 1918, link-local and CGNAT ranges.
  Calico enforces `except`.
- **PostgreSQL.** A separately mounted `hba_file` allows `hostssl` only.
- **Production host drift.** The static exact-origin scan derives the host
  from the HTTPRoutes, so the production patch cannot drift silently.
- **Audit and authorization coverage.** Audit events are scoped to mapped
  state-changing requests, with sensitive headers masked. The `@PreAuthorize`
  coverage test has two named internal exceptions.

## Relation to the other review

- **Agree, confirmed in source:** F1 (C1), F2 (C4), F3 (C3), F4 (C2) and O1
  (O7).
- **Differ on severity:** F3 is P2 there and Low-Medium here, because of the
  rate-limited trigger and the exposure that heartbeat bounds to one TTL (see
  C3).
- **Not covered there:** C5 (flaky counter deltas), C6 (inventory
  brittleness), the C7 root cause, the C8 items and O1–O6 above.
- **Not reviewed here:** its O3 (frontend expiry heuristics) and its
  cleanup-script process-regex observation. I have no opinion on either.

## Suggested order of work

1. **C1:** stop caching arbitrary ranges in currency-service and make cache
   writes fail open. This is service-owned.
2. **C2:** close the mesh guard gaps with the two fail fixtures.
3. **C4 and C5:** fix the verifier's fixture ownership with one preflight, and
   drop or relax the global counter checks. Both are small edits to the same
   file.
4. **C3:** batch the deletes in the session-gateway Lua script and add the
   large-index test.
5. **C6 and O1:** while in the same verifiers, replace the inventory checks
   with property checks and delete the RBAC simulator.
6. **C7 and C8, then O2–O7:** these are opportunistic. None blocks treating
   the hardening as complete.
