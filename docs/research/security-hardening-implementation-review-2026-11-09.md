# Security hardening implementation review

Date: 2026-11-09. Scope: the completed `security-hardening-*` plans, their
remediation plans, and the implementation in the adjacent repositories.

The main controls are implemented coherently. I found no confirmed external
authentication or authorization bypass in the reviewed implementation. There
are four actionable findings below: one previously documented availability
issue, a new verifier fixture-ownership bug, an inherited bulk-revocation
failure, and a gap in the new static mesh checks. The most useful next work is
to fix those specific problems, rather than add more security layers.

The runtime design is generally proportionate. The main excess complexity is
in verification and cleanup orchestration, especially repeated setup and
independent representations of the same contracts.

## Scope and evidence boundary

- Reviewed source, manifests, relevant diffs, existing tests, the plans,
  [contested decisions](security-review-contested-issues-2026-11-02.md), and
  the [implementation evidence](security-consensus-hardening-evidence.md).
- Accepted the user's report that smoketests and API tests pass. **No
  smoketest, API test suite, live application request, service build, or
  aggregate static suite was run during this review.**
- Ran the required read-only workspace VM boundary check; it passed.
- Performed two isolated checks: the existing session-revocation Lua script
  against disposable Redis, and the existing mesh checker against temporary
  manifest mutations. These are described below. Neither touched the Kind
  cluster or application data.
- No service, manifest, script, plan, or existing evidence file was changed.
  This report is the only repository change.
- This is a source review with focused reproductions, not a new runtime
  certification. The production reference remains offline and has the
  explicitly pending image-release handoff.

All reviewed worktrees were clean at the start:

| Repository | Reviewed HEAD |
| --- | --- |
| orchestration | `d7fc2d3747a6baa1012856bd2db8145c537382f3` |
| session-gateway | `71b487aa8079225e85a98ef00ada71d4a0d20cd0` |
| ext-authz | `7f994b1bc3ef7b1d7a5389ed00496f59c56b357c` |
| service-common | `e14c9c77cf6240704ed3442900b1713be233e0af` |
| permission-service | `0bae3daffcc6d9aa8db6e15977734667ce972c6d` |
| transaction-service | `5475d0e6869e3c4ed462c5679cd798e35e55cdf4` |
| currency-service | `bad9de0c8c1d558b361e4b007fcc94043864e69f` |
| budget-analyzer-web | `3d8569e370f56661293657dbac705098eca7e326` |
| budget-analyzer-api-tests | `312dd875905c669919c3251c27a75321227114ff` |

## Findings

Priority means remediation order: P1 is a substantial availability problem;
P2 is a correctness or verification defect that should receive a focused fix.
It is not a CVSS score.

### F1 — P1: Currency cache growth can still deny login and heartbeat

**Disposition:** previously reproduced and explicitly left open, not a new
discovery and not an accepted risk in the closeout plan. Owners:
currency-service, with orchestration coordination only if storage is separated.
Plans 03 P11/P13 and 04 P1.

[ExchangeRateService.java](../../../currency-service/src/main/java/org/budgetanalyzer/currency/service/ExchangeRateService.java),
lines 90–95, caches each distinct currency/start/end tuple.
[CacheConfig.java](../../../currency-service/src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java),
lines 56–57 and 140–150, applies a one-hour TTL without an entry-count or
aggregate-size bound. These values share the
[128 MiB Redis budget](../../kubernetes/infrastructure/redis/start-redis.sh)
with sessions and OAuth state.

The existing [plan 04 measurements](security-consensus-hardening-evidence.md#shared-cache-growth-reported-not-changed)
record one ordinary user filling that budget with about 100 exchange-rate
reads. Uncached queries then fail, heartbeats return 503, and login initiation
fails intermittently. The exposure can persist for the cache TTL. Current
source retains the mechanism. I did not repeat the fill experiment.

`noeviction` is the right choice for authentication data, but it does not
reserve memory for authentication. Switching cache eviction from KEYS to SCAN
also does not address capacity. Passing normal request tests cannot establish
a bound on distinct ranges or retained cache bytes.

**Smallest useful fix:** decide whether this query cache earns its complexity.
Removing caching for arbitrary ranges is a simpler initial remedy than adding
a second Redis deployment. If retaining it, bound the total retained cache
working set; an individual entry-size limit or a shorter TTL alone is not a
total bound. Separately, a cache write failure should not turn a successful
database read into a 500. Keep the auth Redis `noeviction` policy.

**Focused acceptance:** a normal read-capable account varying date ranges
cannot consume the auth budget; cache write rejection has the intended query
behavior. This needs currency-service work, not an orchestration compensation.

### F2 — P2: The edge verifier can delete a load-test fixture it refused to own

**Disposition:** newly identified implementation defect. Owner: orchestration.
Plans 01 and 05.

In [verify-edge-contract.sh](../../scripts/smoketest/verify-edge-contract.sh),
the first five sections check for `.loadtest/session-pool.txt` and report that
an existing fixture must be left alone. For example, lines 439–441 call
`fail` and then a bare `return`. `fail` updates the counter successfully, so
the section returns success and `main` continues.

The last section, `verify_response_headers`, calls `seed_fixture` at line 1590
without that check. `seed_fixture` itself has no fixture-ownership check
(lines 361–365). The section eventually invokes the shared teardown; the EXIT
trap does so as well if it fails after seeding.

The resulting sequence is:

1. A user already has a load-test pool and synthetic data.
2. The verifier warns five times and skips those sections.
3. The response-header section overwrites the pool with its one-user fixture.
4. [teardown-loadtest.sh](../../scripts/loadtest/teardown-loadtest.sh) removes
   **all** matching load-test sessions, users, roles and transaction rows,
   including the pre-existing fixture.
5. The verifier exits with failure only after the destructive cleanup.

This conclusion follows directly from control flow; no live fixture was
created or deleted to test it. The passing happy path starts without an
existing pool and therefore does not cover this branch.

**Smallest fix:** perform one mandatory ownership preflight before any section
and exit immediately on an existing pool. Enforce ownership in the shared
fixture helper, not six independent copies of a conditional. If concurrent
verifiers/load tests are supported, use one mutually respected lock around
fixture acquisition and cleanup; a file-existence check alone has a race.

**Focused acceptance:** with a pre-existing pool, a stubbed seeder and teardown
are never called, the pool contents remain identical, and the verifier fails
before issuing requests. Also cover a seed failure after partial creation so
cleanup ownership is explicit.

### F3 — P2: A large session index prevents bulk revocation

**Disposition:** newly confirmed during this review, but the failing algorithm
predates hardening (`55719f2` in session-gateway). The hashing and lifetime
changes preserve it. Owner: session-gateway. Related plans 02.4 and 02.5.

[delete-user-sessions.lua](../../../session-gateway/src/main/resources/redis/delete-user-sessions.lua),
lines 5–14, loads the complete user index, constructs a second array, and
passes every session key plus the index to one `unpack` call. Redis's Lua
argument stack is finite.

I ran that **unchanged script** on the manifest-pinned Redis image
`redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499`
(Redis 7.4.11). Each case had a synthetic index and one existing session hash;
the other index members represented expired sessions.

| Index members | Script result | Existing session and index afterward |
| --- | --- | --- |
| 100 | `2` keys deleted | Both absent |
| 8,000 | `ERR ... too many results to unpack ... @user_script:14` | Both remain |
| 10,000 | Same error | Both remain |

The container used `--network none`, a Unix socket, tmpfs storage, no mounts or
published ports, and no credentials. It was removed afterward. These counts
demonstrate failure; 8,000 is not a claim about the exact smallest failing size.

This is not restricted to thousands of simultaneously active sessions.
[create-session.lua](../../../session-gateway/src/main/resources/redis/create-session.lua)
adds members and extends the index TTL, and
[conditional-update.lua](../../../session-gateway/src/main/resources/redis/conditional-update.lua)
keeps extending it while sessions remain active. Expiry of an individual hash
does not remove its set member. Continued logins without logout can accumulate
stale members across successive eight-hour sessions while the user index never
expires. The absolute lifetime does not bound that index.

Bulk deactivation still commits the database state first in
[UserService.java](../../../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserService.java).
Thus this does not reactivate a disabled account. It does prevent immediate
session revocation and makes retries fail on the same index. Existing tokens
remain usable until their current expiry unless their heartbeat checks account
status first. No full browser/deactivation sequence was run here.

**Smallest fix:** delete in bounded argument batches within the existing Lua
execution, then delete the index and return the accumulated count. This keeps
the existing atomicity with concurrent session creation without introducing a
worker, scan service or distributed revocation protocol. Separately consider
pruning stale members or bounding per-user sessions to control memory and Lua
execution time; chunking arguments alone does not bound total work.

**Focused acceptance:** an index with at least 10,000 members, mostly stale,
revokes all live sessions and removes the index without an argument-stack
failure. Retain the existing concurrency and two-session lifetime tests.

### F4 — P2: The static mesh guard misses additive access and auth-lane regressions

**Disposition:** newly demonstrated verification gap, not a claim that the
checked-in policies currently grant this access. Owner: orchestration.
Plan 01 P1.

[verify-static-security-manifests.sh](../../scripts/guardrails/verify-static-security-manifests.sh),
lines 1241–1351, checks that a resource named `default-deny-all` has an empty
spec, then examines only rules whose selector has one of three backend `app`
values and whose principal list explicitly includes nginx-gateway.

This misses both broader additive ALLOW policies and the Session Gateway
public/internal boundary. An empty ALLOW baseline does not override a later
ALLOW; matching ALLOW rules are additive.

Using the repository PyYAML venv, I extracted and executed the exact
`AUTHZ_PY` checker body against temporary copies of the policy documents:

| Input | Checker exit |
| --- | --- |
| Unmodified checked-in policy set | `0` |
| Same set plus `default` namespace ALLOW, no selector, `rules: [{}]` | `0` |
| Same set with `to` removed from the ingress rule of `session-gateway-policy` | `0` |

The second mutation grants broad mesh access despite retaining the baseline.
The third restores unrestricted ingress-identity access to Session Gateway.
Other defenses, including ingress path hardening, still exist; these mutations
are not proof of a current external exploit. They show that the checker does
not protect two central plan 01 invariants. The full static suite was not run.

**Smallest fix:** extend the focused checker to cover all ALLOW policies that
can select the protected workloads, including selectorless and broad-principal
rules, and explicitly check the Session Gateway and internal permission-service
caller/method/path restrictions. Include both mutations as negative fixtures.
Use one declared supported policy shape if necessary; do not build a general
Istio policy simulator. Make its documented scope match what it checks.

## Over-engineering and maintenance observations

### O1 — Run the static suite once per aggregate invocation

[smoketest.sh](../../scripts/smoketest/smoketest.sh), lines 115–138, runs the
static suite near the beginning and later invokes
[verify-security-guardrails.sh](../../scripts/smoketest/verify-security-guardrails.sh),
which runs the same suite again before runtime and edge verification. The
suite performs schema/linter/admission checks and Helm/Kustomize rendering;
this is more than a cheap assertion.

Keep the standalone security wrapper self-contained, but let the aggregate
dispatcher compose static, runtime and edge steps once each. This is a small
composition change; it needs neither another execution framework nor a general
cache of security-test results. The duplication predates some of these plans,
but the new checks make its cost larger.

### O2 — Simplify verifier lifecycle before adding more sections

The current static verifier is 2,300 lines, the edge verifier 1,676, and the
adjacent residue-cleanup script 653. Size alone is not a defect: traversal,
Origin and outage coverage justify substantial tests. The concrete problem is
repeated lifecycle ownership and embedded configuration interpreters with
different coverage, illustrated by F2 and F4.

Keep the existing command-line entry points. Extract the larger Python checks
into focused files that their fixtures can invoke directly. Centralize fixture
ownership and cleanup. Keep behavioral probes separate from effective-config
inspection so each can report exactly what it proves. Avoid another generic
test framework or a second source of truth for routes.

The residue-cleanup script's active-run protection is a process-command regex
([lines 575–577](../../scripts/smoketest/cleanup-smoketest-residue.sh)). It
recognizes the documented root-relative invocation, but not equivalent forms
such as `bash -x scripts/smoketest/verify-edge-contract.sh` or running
`./verify-edge-contract.sh` from its own directory. It also cannot exclude a
new run starting after the process scan. This was source-reviewed, not tested
against live processes. A shared lock/run ownership contract is simpler and
stronger than extending command-line heuristics. This cleanup script is
adjacent follow-up work, not an additional unmet hardening-plan requirement.

### O3 — Prefer explicit expiry state to increasingly clever frontend inference

[useSessionHeartbeat.ts](../../../budget-analyzer-web/src/hooks/useSessionHeartbeat.ts)
infers an unextendable session from whether a fresh expiry falls inside the
warning window. With the current 15-minute TTL and two-minute warning this is
a reasonable limited heuristic, but it is not an explicit server indication of
the absolute cap. The warning timer itself changes only `showWarning`, so an
inactive user whose last capped response arrived before that window can still
see the inactivity/Continue wording until another heartbeat.

There is also an inherited edge case in
[InactivityWarningModal.tsx](../../../budget-analyzer-web/src/components/InactivityWarningModal.tsx),
lines 35–46: automatic logout requires the countdown to have first been
positive. If a suspended tab resumes after expiry and the modal first opens at
zero, that guard never becomes true. Server expiry remains enforced. These
are source-derived UX issues, not authentication bypasses or browser-tested
failures in this review.

If this UI is revised, make the countdown initialization explicit and either
keep the copy neutral or return a small explicit cap/extension field from the
server. Do not add a client-side session state machine to infer the server's
policy from timer timing. These are lower priority than F1–F4.

## Controls worth retaining as implemented

- **One reusable browser-binding cookie:** the OAuth repository checks the
  binding before deleting immutable state and requires a successful deletion
  before callback completion. The documented first-login race fails closed.
  Per-login cookies and eviction machinery are unnecessary here.
- **One session format:** raw random tokens stay in cookies, while SHA-256
  digests identify Redis hashes and index members. There is no unnecessary
  dual-format migration path.
- **Absolute lifetime at the writer:** validation requires the maximum to be
  at least the sliding TTL; heartbeat caps `expires_at`; both readers check
  expiry. The `EXPIRE GT` distinction for an existing versus newly recreated
  index is necessary. A second independently configured cap in ext-authz
  would add coordination without fixing F3.
- **Shared route includes and narrow mesh paths:** these remove local versus
  production-reference route duplication and protect service-owned internal
  paths. The semicolon layers address real multi-hop normalization behavior;
  they are not gratuitous duplicate filtering.
- **One exact-Origin rule on both browser lanes:** POST heartbeat/logout,
  form POST followed by 303, and the rendered IdP `form-action` origin form a
  consistent design. A second Fetch Metadata or CSRF-token system is not
  needed to complete the agreed contract.
- **Small audit adapters:** the shared event/logger plus MVC interceptor and
  local reactive lifecycle helper fit the chosen coverage. Logout recovery
  is confined to session read/deletion, and post-deletion redirect handling
  respects the documented commit point. An external audit persistence
  framework is outside this work.
- **Separate liveness and readiness:** dependency outages remove readiness
  without deliberately restarting healthy processes. ext-authz has finite
  HTTP server timeouts; the ingress authorizer has a separate one-second
  fail-closed timeout and 503 failure contract.
- **Incremental currency cache clearing:** SCAN with bounded DEL batches is a
  sensible replacement for KEYS. The accepted key-name exposure and stale-read
  race remain accurately distinguished from F1's unresolved capacity problem.
- **Infrastructure controls:** PostgreSQL's separately mounted `hba_file`
  applies TLS-only TCP rules to existing volumes; egress private-range
  exclusions are beneath the host-routing layer; Redis has a measured memory
  budget. These are useful controls despite their documented limits.

## Plan coverage cross-check

Numbers below refer to the 38-item scope table in
[plan 05](../plans/security-hardening-05-closeout-release-handoff.md#final-scope).
“Reviewed” means source and recorded evidence were inspected, not that tests
were rerun or every possible behavior was proved.

| Plan / scope items | Implementation reviewed | Assessment |
| --- | --- | --- |
| 01: 1–3 | Mesh caller/path restrictions, default baseline, traversal verifier | Current restrictions coherent; F4 leaves regression gaps |
| 01: 4–5, 32–33 | Shared NGINX headers/routes and decoded-semicolon rejection | Credentials stripped on business-backend routes; HTTPS forwarding and shared includes consistent |
| 01: 6 | Istio provider settings and ext-authz denial behavior | Timeout, fail-closed and 401/503 distinction consistent |
| 01 and 02.2/02.8: 7–9 | HTTPRoute headers, fixed callback configuration, CSP renderer | Intended host/redirect ownership present; existing duplicate X-Frame-Options issue remains below |
| 01: 10–11 | Redis ACL, owner documentation and follow-up work | Explicit command grant follows current calls; no need to restore broad ACLs |
| 02.1: 12 | OAuth browser binding, state creation and consumption | Binding-before-delete and one successful consumer preserved |
| 02.2: 13–14 | Login input cap, repository fallback removal, redirect validators and LoginPage | Unsafe stored return targets bounded; authenticated login-page navigation now validates |
| 02.3: 18 | Permission sync POST, request body, client deadline, mesh route | Caller/server/policy contracts agree |
| 02.4: 15 | Cap arithmetic, configuration validation, index TTL and frontend warning | Server enforcement coherent; O3 covers UI limitations |
| 02.5–02.6: 16–17 | Hashed keys, cookie consumers, seed/teardown tooling, cookie attributes | One format and cookie contract; F3 is an inherited revocation limit |
| 02.7–02.8: 34–35 | POST endpoints/clients, logout form/303, Origin policy and CSP | Both ingress lanes covered by the agreed contract |
| 03: 19–20, 36 | ext-authz health/retry/server settings and Go build inputs; Spring readiness and probes | Separation and toolchain alignment present |
| 03 and remediation: 21–23 | Trusted address logging, audit emission and callback/logout failure paths, logging defaults | Scoped audit design implemented; accepted reactive-address and retention limits retained |
| 03: 24, 37–38 | Controller authorization coverage rules, deleteUser removal, cache writer and ACL | Changes present; F1 is separate from SCAN behavior |
| 04: 26 | Redis memory/persistence measurements and noeviction configuration | Measured budget, but F1 remains an unresolved practical availability issue |
| 04: 27–28 | Egress policies/additive-policy guard, PostgreSQL HBA and startup/probes | Intended exclusions and server-side TLS enforcement present |
| 04: 30 | RabbitMQ image change and support-window inventory/report | Upgrade recorded; existing runtime-support follow-ups remain |
| 05: 31 | Forged identity negative/positive controls and wrapper composition | Behavioral coverage present; F2 concerns fixture safety, O1 duplicate work |
| Deferred: 25, 29 | PDF bounds and database migration/runtime role separation | Explicitly deferred/accepted; not counted as implementation failures |

The [closeout evidence](security-consensus-hardening-evidence.md#plan-05-phase-2-evidence-record-and-release-handoff)
also distinguishes passing human-run tests from direct edge-verifier results
and records the human-owned release sequence. Several source plans still have
draft/ready headers because the execution workflow kept plan inputs stable.
Those labels are documentation cleanup, not evidence that their code is absent.

## Existing open items and accepted boundaries

These should remain visible without being relabeled as newly discovered bugs:

| Item | Disposition |
| --- | --- |
| Currency cache exhaustion | F1; existing open finding, not accepted |
| Runtime support | The checked-in support inventory and closeout flag NGINX 1.29 as past support and Istio 1.30 as approaching its recorded estimated end date. Upstream dates were not independently revalidated in this review |
| Duplicate `X-Frame-Options` | Closeout observed `DENY` plus `SAMEORIGIN` on a backend response. Spring security headers and NGINX `add_header` ownership should be reconciled; this is lower priority than the availability and verifier defects |
| Production image compatibility | Old pins do not implement the new cookie, hashed-session, POST sync and probe contracts. Explicit human release/pin handoff remains necessary; offline rendering is not runtime compatibility proof |
| Anonymous OAuth-state growth | Accepted residual availability exposure; distinct from the unaccepted authenticated-cache issue |
| Reactive client address / audit retention | Accepted and documented limitations; no new trusted-address or logging infrastructure proposed here |
| Compromised intermediary / Redis key-name visibility | Accepted trust and metadata boundaries; no signed-claims system or Redis split required solely to reopen those decisions |
| Upload capacity / database-owner runtime roles / per-caller egress identity | Deferred or accepted as recorded in the plans and contested decisions |

## Recommended order

1. Resolve F1 in currency-service; it has the largest demonstrated user impact.
2. Fix F2 before relying on the edge verifier alongside load-test work.
3. Fix F3 with bounded Lua arguments and a large-index regression test.
4. Close F4 with targeted negative policy fixtures.
5. Remove duplicate aggregate static execution and consolidate verifier
   ownership while touching those scripts. Treat broader file extraction and
   the frontend warning refinements as maintenance, not blockers to declaring
   the implemented security controls useful.
