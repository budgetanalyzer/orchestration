# Security Review: Contested Issues

**Original date:** 2026-11-02  
**Reassessment:** 2026-11-05  
**Status:** Reviewed recommendations. These verdicts replace the original discussion recommendations;
they do not implement fixes or amend the [hardening plan](../plans/security-review-consensus-hardening-plan.md).

This review decides whether to **keep**, **discard**, or **modify** each original recommendation.
“Keep” can retain a deferral; it does not mean the proposed control already exists. “Discard” rejects
a claim or requirement, not necessarily the entire underlying concern. Factual findings and design
judgments are distinguished below. The original reviewers' positions remain for context.

| Label | Review |
| --- | --- |
| R1 | [First review](application-architecture-security-review-2026-11-01.md) |
| R2 | [Second opinion](application-architecture-security-review-second-opinion-2026-11-01.md) |
| R3 | [Third assessment](application-architecture-security-review-third-assessment-2026-11-01.md) |
| R4 | [Assessment](application-architecture-security-review-assessment-2026-11-01.md) |

R1 predates the later findings. R3 and R4 assessed R1 and R2, not each other. Silence is not agreement.

**Evidence boundary.** Rechecked the orchestration and sibling working trees and consulted the linked
primary sources. Ran isolated Redis and Envoy probes, plus static route/OpenAPI checks; results are
[recorded below](#verification-record). No live application, browser, or PDF load test was run. No
cluster resources or service code were changed. Planned hashing, cookie renaming, and mesh narrowing
are not counted as existing protection. Repository links are relative to this document and resolve
in the supported side-by-side checkout; the reviewed revisions are recorded below.

## Summary

| # | Issue | Verdict on original recommendation | Result |
| --- | --- | --- | --- |
| 1 | [CSRF](#1-primary-csrf-control) | **Modify** | Keep Fetch Metadata/exact Origin and POST mutations; reject missing provenance on unsafe browser-session requests. |
| 2 | [Redis enumeration](#2-redis-enumeration-after-hashing) | **Modify** | Keep hashing plus removal of enumeration; require a concurrency-safe cache invalidation design, with a later instance split. |
| 3 | [Encoded paths](#3-encoded-path-traversal-and-rejecting-) | **Modify** | Keep decoded-semicolon rejection and mesh narrowing; the parser discrepancy is reproduced, full-stack exploitability remains unverified. |
| 4 | [OAuth cookie](#4-oauth-correlation-cookie-and-atomic-consume) | **Modify** | Keep transaction cookies and atomic validation/consume; replace the unsupported cookie-size estimate and destructive cap rule. |
| 5 | [Duplicate cookies](#5-rejecting-duplicate-session-cookies) | **Modify** | Keep `__Host-`; reject duplicate session-name values as modest hardening, without claiming a demonstrated browser exploit. |
| 6 | [PDF memory](#6-pdf-memory-handling-and-a-parsing-worker) | **Modify** | Prefer bounded file-backed input, early concurrency admission, and parsing limits; measure budgets and defer a worker. |
| 7 | [Signed identity](#7-signed-identity-context) | **Keep** | Defer pending a concrete threat model; record intermediate forgery and replay as residual risks. |
| 8 | [Internal ports](#8-separate-internal-ports) | **Keep** | Defer separate listeners; first prove restrictions on both public lanes. |
| 9 | [Egress identity](#9-per-caller-egress-identity) | **Keep** | Defer as coordinated design work; discard the one-setting remedy. |
| 10 | [`deleteUser`](#10-the-unused-deleteuser-method) | **Modify** | Remove the unused method; preserve the existing distinction between deletion and deactivation. |
| 11 | [HSTS flags](#11-hsts-includesubdomains-and-preload) | **Modify** | Keep neither flag by default; correct the apex-only preload claim and conditional Spring-header evidence. |
| 12 | [Route generation](#12-generating-the-nginx-route-files) | **Modify** | Keep no generator; compare routing behavior and shared security policy, not just location names. |

The sections on [severity](#severity-disputes), [work order](#work-order), and
[previously settled claims](#settled-by-checking-the-code) also have explicit dispositions.

## 1. Primary CSRF control

| Review | Position |
| --- | --- |
| R1 | Tokens for unsafe requests, exact-origin validation, and Fetch Metadata as a supplement. Move heartbeat and logout to POST. |
| R2 | `Sec-Fetch-Site` in ext-authz as the main control, with `Origin` as the fallback. The POST move is "fine hygiene but low value". |
| R3 | Fetch Metadata is the main control and tokens are not needed. Allow requests that carry neither header. The auth lane needs its own check. |
| R4 | Tokens and Fetch Metadata can both work, and R2's claim that Fetch Metadata is stronger is unqualified. Missing headers must be specified, not waived for test clients. Both lanes need cover. Heartbeat and logout must move to POST. |

**Decision — Modify.** Keep a header-based primary defense on both browser lanes, move heartbeat
and logout to POST, and change the original allow-on-missing-headers recommendation to rejection for
protected unsafe requests. A token system is not required for this single-origin SPA if that
contract is implemented and tested; “tokens add nothing” is too broad a general claim.

**Evidence and corrections.** The [ext-authz provider][provider] explicitly forwards `cookie`, but
not `origin` or `sec-fetch-site`. Its [CUSTOM policy][custom-policy] covers `/api/*`; the
[auth HTTPRoute][auth-route] sends OAuth, auth and logout traffic directly to Session Gateway.
[Session Gateway security][sg-security] disables CSRF. [Heartbeat][heartbeat] refreshes stored
authorization and expiry through GET. [Logout][logout] clears the cookie even when none arrived,
and redirects to the IdP; its scope includes the IdP logout flow, not merely a local UI transition.
The four navigation call sites are in [useAuth][use-auth], [InactivityWarningModal][warning-modal]
and [useSessionHeartbeat][use-heartbeat].

[Go's implementation](https://go.dev/src/net/http/csrf.go) explicitly permits requests missing both
headers. That is an intentional compatibility policy, not proof that such requests must be
non-browser traffic. [OWASP's guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html#use-fetch-metadata-headers-to-verify-nature-of-the-request)
recognizes older clients and header-stripping intermediaries and recommends a fail-safe policy for
sensitive endpoints. The existing [httpx client][api-client] can send the configured Origin; its
current omission is not a reason to weaken the browser contract.

The Go version claim also needs correction: [go.mod][go-mod] declares a 1.24 minimum, while the
[Docker build][go-docker] already selects 1.27 and [build CI][go-build] reads the module version.
Adopting `CrossOriginProtection` requires aligning the supported minimum and CI, not necessarily a
Docker toolchain upgrade. Its default missing-header and Host-comparison behavior is not this
application's proposed exact-origin policy.

**Recommended contract.** For unsafe requests, reject `cross-site` and `same-site`; allow
`same-origin` only without a conflicting Origin. If Fetch Metadata is absent, require an exact
configured Origin including scheme and port. Reject missing, `null`, malformed or contradictory
provenance; other metadata values do not authorize an unsafe request. Do not derive the trusted
origin from arbitrary forwarded headers. Cover both lanes.
Keep intentional OAuth callbacks outside this unsafe-request rule and protect them with issue 4.

Use a same-origin logout fetch that returns a server-constructed, validated IdP navigation URL in
JSON, then navigate to it. Simply fetching the existing 302 endpoint would follow the redirect
inside fetch. Update all callers and reject the old mutating GETs. Test hostile same-site requests,
missing/null/conflicting headers, both lanes, and real browser login/logout. These are implementation
acceptance checks, not evidence already obtained.

## 2. Redis enumeration after hashing

| Review | Position |
| --- | --- |
| R1 | No position on enumeration. Prefers separating security state from caches "when deployment requirements justify it". |
| R2 | Do all of it: hash, replace clear-all eviction with a versioned prefix, remove `+keys +scan`, and split Redis as the architectural fix. |
| R3 | These are redundant. Hashing or splitting each stops token theft alone. A versioned prefix is only needed to drop the grant on a shared Redis. Split before hosted use, not first. |
| R4 | Address both properties. Hashing reduces the consequences, but "does not make the original isolation claim true". Also remove enumeration or split. Splitting does not replace hashing or stop anonymous OAuth-state growth. |

**Decision — Modify.** Keep hashing and removal of `KEYS`/`SCAN` from currency-service. Retain
separate auth/cache Redis instances as the preferred hosted direction. Modify the claim that a
versioned prefix is a trivial fix costing exactly one extra read.

**Evidence.** The [Redis ACL bootstrap][redis-acl] grants currency-service both enumeration commands
alongside `~currency-service:*`. An isolated test of the pinned Redis 7.4.11 image confirmed that
`GET session:dummy-digest` is denied while `KEYS *` and `SCAN 0` reveal that key and
`user_sessions:dummy-user`. This is a demonstrated metadata leak, not just an interpretation of
ACL syntax. The [credential verifier][credential-verifier] tests cross-prefix GET denial, which
does not establish namespace invisibility.

Current [session writing][session-writer] and [ext-authz lookup][session-lookup] concatenate raw
session IDs into keys. Hashing high-entropy tokens on both sides prevents enumerated key suffixes
from being replayed as bearer cookies; it does not hide user IDs or activity metadata. An enumerated
OAuth state still identifies an in-flight transaction. It must not authorize completion without
the independent browser binding in issue 4. Do not describe state as wholly non-sensitive.

The three [all-entry eviction sites][exchange-import] rely on a [transaction-aware Redis cache][cache-config]
with a one-hour write TTL. Old generations can expire naturally, but rapid invalidation can retain
several generations simultaneously. TTL bounds lifetime, not peak memory or write rate.

**Recommended change.** Replace clear-all enumeration in currency-service, then remove the grants
and test both denial and normal cache invalidation. A generation scheme is reasonable if it
preserves after-commit invalidation and binds each cache read/fill to one generation: a query begun
before an import must not publish stale results into the new generation. Specify concurrent import,
replica, generation-loss/reuse, rollback, and Redis-failure behavior. The exact extra I/O depends on
that implementation; do not promise a single read in advance.

A separate instance also isolates memory/eviction policy and administrative blast radius. Separate
logical Redis database numbers do not provide that process boundary. A new service DNS name must
be covered by human-supplied TLS material; the existing [certificate preparation source][infra-tls]
only names the current services. Instance separation does not replace token hashing, OAuth binding,
or auth-state capacity limits. No sibling service change is made in this review.

## 3. Encoded-path traversal and rejecting `;`

| Review | Position |
| --- | --- |
| R1 | No position. Recommends narrowing mesh permissions. |
| R2 | Proxies do not treat `..;` as a parent segment, Tomcat does, and `StrictHttpFirewall` stops it today. Rate it Low. Reject `;` at the ingress and pin the firewall with a test. |
| R3 | R2 is wrong. The sidecar collapses `..;` before Spring sees it, so the firewall never fires. Reachable by any signed-in user, on stand-ins. Fix first. Reject decoded `;` at NGINX. A firewall test is not a fix. |
| R4 | Accept neither claim without testing the whole chain. Did not reproduce it. A literal `;` filter or a firewall unit test is not sufficient proof. |

**Decision — Modify.** Keep mesh caller/path restrictions and reject decoded semicolons at
NGINX. Discard both “Spring necessarily stops it” and “failure to reproduce makes it Low.” The
isolated parser behavior is confirmed; actual application reachability and severity still require
a full-chain test with a valid disposable session.

**Evidence.** Both [local NGINX][nginx-local] and [production-reference NGINX][nginx-prod] rewrite
`/api/v1/users/...` into `/permission-service/v1/...`; neither currently rejects semicolons.
[Mesh policy][mesh-policy] permits the NGINX principal without path restrictions, while the
[permission-service internal chain][permission-security] permits its two internal GET routes and
relies on mesh caller enforcement.

The new isolated Envoy 1.38.8 probe with `normalize_path: true` produced:

| Input to Envoy | Path after normalization |
| --- | --- |
| `/api/v1/users/..%3b/..%3b/internal/v1/users/u1/authorization` | Unchanged |
| `/permission-service/v1/users/..;/..;/internal/v1/users/u1/authorization` | `/permission-service/internal/v1/users/u1/authorization` |

This independently confirms the critical normalization distinction reported by
[R3's reduced-chain test](application-architecture-security-review-third-assessment-2026-11-01.md#n1-high-priority-medium-high-severity-public-edge-to-internal-endpoints).
It does not reproduce the full generated ingress/NGINX/sidecar/Spring chain.
[NGINX documents](https://nginx.org/en/docs/http/ngx_http_core_module.html#location) percent-decoding
before location matching and a normalized `$uri`; [Istio documents](https://istio.io/latest/docs/reference/config/security/normalization/)
that normalization precedes authorization and forwarding. These facts explain why a backend firewall
can receive an already-clean internal path.

**Recommended change.** Keep the server-level `if ($uri ~ ";") { return 400; }` candidate in both
NGINX files, plus mesh path restrictions as the authorization boundary. The
[checked-in OpenAPI document][openapi] now has **29**, not 22, paths; none contains `;`. This supports
rejecting undocumented matrix-parameter syntax, but is not a compatibility proof for every client.

Test literal, encoded, mixed-case and double-encoded forms through both the NGINX lane and the direct
Session Gateway lane. NGINX does not protect the latter. Assert absence of internal handler side
effects, not just a non-200 response. A firewall test remains useful defense in depth, not proof of
this boundary. An inconclusive baseline stays “not reproduced”; it must not become a claim of safety
or an automatic severity downgrade.

## 4. OAuth correlation cookie and atomic consume

| Review | Position |
| --- | --- |
| R1 | Short-lived correlation cookie, consumed atomically. |
| R2 | `__Host-`, `SameSite=Lax`, stored as a hash, cleared after the callback, consumed atomically. |
| R3 | Agrees on the cookie. Atomic consume is hygiene, because the identity provider should reject a second use of the code. It must not delay the binding. |
| R4 | Test parallel login tabs. Consume atomically; plain `MULTI` around an earlier read is not atomic. |

**Decision — Modify.** Keep one short-lived correlation cookie per transaction as a reasonable
parallel-tab design, and keep atomic validation/consume. Discard the fixed 77-byte estimate,
“clear all five” as a harmless cap, and the suggestion that single-use IdP codes make local consume
unimportant.

**Evidence.** [RedisAuthorizationRequestRepository][oauth-repository] stores PKCE/nonce data under
`oauth2:state:<state>` and retrieves it from the callback query alone. Removal performs a read and
then a delete; it returns the request without making successful deletion a single-winner condition.
There is no browser-cookie comparison. [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1)
requires transaction-specific PKCE/nonce material to be bound to the initiating user agent. IdP
code replay protection does not establish that binding or make the local record single-consumer.

**Recommended design.** Give each transaction an independent random secret; store its hash with
state, and put the secret in a Secure, HttpOnly, `__Host-`, `Path=/`, `SameSite=Lax` cookie selected
by a bounded hash-derived state suffix. A value derived only from state is not an independent
browser proof. Lax suits the current top-level GET callback; do not generalize it to cross-site
POST response modes. Clear only the matching cookie after a terminal callback.

Atomically compare the binding and consume the record before code exchange/session issuance, using
Lua or an equivalent compare-and-delete primitive. A wrong/missing cookie must not delete somebody
else's transaction. [Redis guarantees atomic script execution](https://redis.io/docs/latest/develop/programmability/eval-intro/),
but a read performed before `MULTI` is outside that atomic section. Test replay, concurrent callbacks,
expiry, denial/error callbacks and parallel starts. Binding is the immediate security priority;
any staged delivery must explicitly retain atomic consumption as unfinished work.

**Cookie limit correction.** Request overhead is `name + '=' + value + separator`, so it depends on
chosen encodings; no current code establishes 77 bytes. Cookie-count checks see only the request's
snapshot: parallel starts can all see fewer than five and each add a cookie. Clearing all pending
cookies also invalidates legitimate tabs and permits login disruption. Define a count/byte budget,
reject excess starts without silently cancelling existing transactions, and test simultaneous
starts plus the actual ingress header limit. A request-count check alone is a soft limit. A reusable
browser-binding cookie remains a valid simpler alternative if its concurrent initialization and
lifetime behavior are explicit; this is a design choice, not a requirement of OAuth.

## 5. Rejecting duplicate session cookies

| Review | Position |
| --- | --- |
| R1 | No position. |
| R2 | Reject requests carrying two session cookies. A planted `Path=/api` cookie wins today, because browsers send longer paths first. |
| R3 | Skip it. A browser will not accept a planted `__Host-` cookie with `Path=/api` or a `Domain`. |
| R4 | Supports "unambiguous handling". Must not reject unrelated cookies or HTTP/2 header splitting. |

**Decision — Modify.** Adopt `__Host-` as the main protection against the cited cookie-tossing
attack, and add consistent duplicate-name rejection as modest input hardening. Discard the claim
that duplicate input is impossible to exercise or that it demonstrates a vulnerability by itself.

**Evidence.** [SessionCookieHelper][cookie-helper] uses `getFirst(cookieName)`;
[ext-authz][auth-handler] uses `r.Cookie`, also selecting a match. Current defaults remain
`BA_SESSION` in [Session Gateway][sg-application] and [ext-authz][auth-config]; the prefix protection
has not shipped. The [HTTP cookie specification (work in progress)](https://httpwg.org/http-extensions/draft-ietf-httpbis-rfc6265bis.html#name-the-host-prefix)
requires Secure, `Path=/`, and no Domain for `__Host-`. Consequently, R2's longer-path or Domain
cookie cannot be stored with that name by a conforming browser. This is a sound reason to lower the
priority of duplicate rejection after the rename.

However, the prefix is a browser storage rule, not server-side syntax validation. Arbitrary HTTP
clients can submit duplicates, and both services can test them. That alone gives an attacker no
victim credential and does not prove an exploit. The prefix also does not isolate ports on the same
host; duplicate rejection does not repair a compromised trusted origin or same-host service.

**Recommended change.** Reject more than one parsed cookie with the configured session name,
regardless of order or equal values, in both consumers. Continue accepting unrelated cookies and
ordinary splitting of Cookie fields: [HTTP/2 explicitly permits that splitting](https://www.rfc-editor.org/rfc/rfc9113.html#section-8.2.3).
Test duplicate values in one field and across fields, one session cookie plus unrelated cookies,
and the real browser prefix contract. Coordinate the rename, removal of Domain override, and any
legacy-cookie cleanup. Treat this as a small hardening addition, not a release blocker or a
substitute for `__Host-`.

## 6. PDF memory handling and a parsing worker

| Review | Position |
| --- | --- |
| R2 | A crafted PDF can crash the service the way Redis is killed. Use PDFBox's temp-file stream cache, cap pages and text, and limit parses per user. Later, an isolated worker. |
| R3 | The crash is unproven. The default heap is about 128 MiB, so expect `OutOfMemoryError` and GC pressure, not a pod kill. Measure before designing. Defer the worker. |
| R4 | A stream cache does not remove the byte array or cap parsed objects. Use bounded file-backed input, page and output limits, and global plus per-user concurrency. A worker becomes useful when hard termination is required. |

**Decision — Modify.** Keep measurement and global/per-user concurrency limits, but choose
bounded file-backed input as the preferred direction now. Discard a temp-file *stream cache* as the
primary fix for read-only PDF extraction. Defer a separate worker unless hard termination or stronger
resource isolation becomes a requirement.

**Evidence.** There are five `Loader.loadPDF(byte[])` sites:
[bank monthly][pdf-bank], [credit monthly][pdf-monthly], [credit yearly][pdf-yearly],
[Bangkok Bank][pdf-bangkok], and [generic PDF text extraction][pdf-text].
[TransactionImportService][transaction-import] and the PDF wizard endpoints in
[StatementFormatController][statement-controller] call `file.getBytes()`.
[Application configuration][transaction-application] allows 25 MB multipart uploads;
[the deployment][transaction-deployment] limits container memory to 512 MiB, and
[the Docker entrypoint][transaction-docker] sets no explicit heap ceiling.

[PDFBox 3's migration guide](https://pdfbox.apache.org/3.0/migration.html) separates the input reader
from the stream cache used for writing: byte-array input remains in memory, while
`RandomAccessReadBufferedFile` reads from a file with a bounded reader cache. A stream-cache setting
does not move the existing upload array to disk or bound the document object graph.

The roughly 128 MiB heap is an estimate based on the
[JVM's default 25% MaxRAMPercentage](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html),
not a measurement of this process. Five simultaneous 25 MiB arrays would consume about 125 MiB before
parsed data, but that is a capacity illustration, not proof that five requests reach that point
concurrently. Neither JVM `OutOfMemoryError` nor container OOM/restart behavior has been demonstrated.
Native memory, threads and other allocations mean a smaller Java heap does not rule out a container
kill.

**Recommended change.** Admit work before `getBytes()`/parsing, bound the waiting queue, spool with
an explicit byte/disk budget and cleanup, and load through a file-backed reader. Apply page and
output limits while extracting, not after allocating all text/chunks. Cover import and wizard paths.
Measure real heap, resident memory, elapsed CPU time and disk use with worst-case fixtures and
concurrency; choose numerical budgets from those results. File backing is an input-memory reduction,
not a hard bound on PDF complexity. If a parser cannot reliably stop within required CPU/memory
limits, move it to a killable isolated process; a timeout around an in-process task does not itself
terminate that task.

## 7. Signed identity context

| Review | Position |
| --- | --- |
| R1 | No position. |
| R2 | Adopt ext-authz-signed tokens before handling real data. |
| R3 | Defer. The mesh already limits who reaches backends, and the current failure is routing, not forgery. A valid decision for a hosted threat model. |
| R4 | Disagrees with an unconditional prerequisite. Needs a threat model. Only ext-authz may hold the private key, and a compromised intermediary can still replay or alter requests. |

**Decision — Keep the deferral.** Discard an unconditional requirement to add signed identity
before any real data, and also discard the implication that mesh narrowing solves intermediary
forgery. Those address different threats.

**Evidence.** [ClaimsHeaderSecurityConfig][claims-security] installs claims-header authentication;
[the filter][claims-filter] constructs authentication from the supplied claims rather than verifying
a signature. [NGINX's shared headers][backend-headers] forward the values it received. The
[mesh policy][mesh-policy] authenticates permitted workload callers, not the origin of every claim
inside their HTTP requests. The [existing options document][claims-options] already identifies
intermediate tampering and direct exposure as residual cases.

**Recommended disposition.** Retain the current topology while narrowing routes and proving ingress
header replacement, including empty permissions. Record that a compromised allowed intermediary can
forge claims. If protecting against that intermediary becomes a requirement, use ext-authz-only
signing authority and backend validation of issuer, audience, expiry and key rotation; shared signing
keys in NGINX would defeat that objective.

A signed identity alone is still replayable by an intermediary that sees it, and it does not bind
request method/body without additional design. Nor does it protect internal endpoints that remain
outside the validating chain. Decide in the [service-common options document][claims-options] when
hosted planning, direct backend access, or a changed compromise model justifies the cost. This is a
scoping judgment supported by the trust flow, not a factual claim that signing is unnecessary in all
deployments.

## 8. Separate internal ports

| Review | Position |
| --- | --- |
| R1 | No position. |
| R2 | Serve internal APIs on separate ports, because port rules cannot be fooled by path tricks. |
| R3 | Disagrees for now. Mesh path rules and the NGINX rejection close the finding with far less work. |
| R4 | Defer a blanket requirement. It helps only if internal routes are absent from the public listener and policy enforces that. |

**Decision — Keep the deferral.** Discard a blanket requirement for separate ports and the
claim that a port change alone establishes isolation.

**Evidence.** Session Gateway's [Service][sg-service] and [Deployment][sg-deployment] expose 8081;
both the [public controller][heartbeat] and [internal revocation controller][internal-session]
use the same application. [Its security chain][sg-security] permits the internal revocation path,
so the [mesh caller policy][mesh-policy] is material. Permission-service similarly relies on
[mesh enforcement for its internal routes][permission-security]. The current broad NGINX and ingress
allow rules need correction regardless of listener design.

**Recommended disposition.** First narrow caller/method/path access and prove the actual path
normalization behavior on both public lanes. If separate listeners are introduced later, internal
handlers must be absent from the public listener, and Service, mesh and network policies must limit
who reaches the internal listener. Adding another port while leaving the handler reachable on the
original one achieves no separation.

Revisit if full-chain tests expose an unresolved path ambiguity, or if an independently enforceable
listener boundary becomes a threat-model requirement. A successful finite probe set supports the
current configuration; it does not prove that every future parser or route change is safe. No
service listener redesign is warranted by the evidence gathered here alone.

## 9. Per-caller egress identity

| Review | Position |
| --- | --- |
| R1 | Consider per-caller destination restrictions. Treat egress as layered containment. |
| R2 | Low. Switch to `ISTIO_MUTUAL` and add a policy keyed on caller identity and host. |
| R3 | Not a mode change. The current listener needs a redesign. Before hosted use. |
| R4 | Agrees with the identity goal and rejects a one-setting fix. Coordinated listener, routing and authorization changes are needed. |

**Decision — Keep the deferral as coordinated design work.** Discard switching only the
DestinationRule to `ISTIO_MUTUAL` as a complete fix.

**Evidence.** [egress-routing.yaml][egress-routing] combines a PASSTHROUGH TLS listener, external
SNI routing, and `tls.mode: DISABLE` on the workload-to-gateway DestinationRule. That configuration
carries the application's TLS without authenticating the caller to the gateway through mesh mTLS.
The reset explanation in the file is historical evidence, not a failure reproduced during this
review. [NetworkPolicy][egress-network] already admits Session Gateway and currency-service, so
“no caller restriction at all” would also be wrong; it does not pair each identity with its permitted
external destination.

[Istio's nested-TLS example](https://istio.io/latest/blog/2023/egress-sni/) demonstrates that end-to-end
application TLS can coexist with mesh mTLS: terminate the outer mesh connection and route the inner
TLS stream. Thus the goal is feasible, but the existing passthrough listener cannot be assumed to
work after a client-side mode change alone.

**Recommended disposition.** At hosted design time, coordinate listener termination, routing, peer
authentication and authorization. Bind authenticated callers to the intended destination, and
reject plaintext/unidentified clients and unauthorized caller/destination pairs. Preserve external
certificate validation and test the actual generated configuration. An HTTP host rule is not a
substitute for a destination check on encrypted passthrough traffic. Separate listeners/gateways
are another possible design for the two fixed destinations; the wildcard example is evidence of
feasibility, not a requirement to copy its complexity.

Keep private-address exclusions and auth/cache availability controls independent of this deferral.
The current [egress network policy][egress-network] permits TCP 443 without destination CIDR limits,
which supports that separate containment work.

## 10. The unused `deleteUser` method

| Review | Position |
| --- | --- |
| R1 | No position. |
| R2 | Low-Medium finding. Deleting a user neither revokes sessions nor stops re-signup. Fix both, or document that re-signup is allowed. |
| R3 | Not a live issue. Nothing calls it, and re-signup is deliberate. Remove the method. |
| R4 | A latent defect. Fix or remove it before exposing it. A permanent ban is a product decision. |

**Decision — Modify.** Keep removal of the unused `deleteUser` method. Discard treating it as
a currently reachable deletion endpoint, and qualify “allow re-signup” so it does not weaken the
existing deactivation rule.

**Evidence.** A search of permission-service `src` finds `deleteUser` only at its declaration in
[UserService][user-service]. It soft-deletes the row and removes roles but does not revoke sessions.
The exposed [UserController][user-controller] instead invokes deactivation. That implementation
commits deactivation before attempting session revocation and reports failure if revocation fails;
it is not an atomic database/Redis operation.

The [schema's partial unique index][permission-schema] permits `idp_sub` reuse after soft deletion.
But [UserSyncService][user-sync] first rejects a subject with any `DEACTIVATED` record, and
[UserRepository][user-repository] intentionally performs that check irrespective of soft deletion.
Therefore a soft-deleted active subject can be recreated, whereas deleting a previously deactivated
record does not currently erase the login block. The earlier document omitted this distinction.

**Recommended change.** Remove the unused method in the permission-service context and retain the
existing synchronization checks. Do not introduce a deletion endpoint or change account lifecycle
policy as part of this hardening review. If deletion is later exposed, specify revocation, concurrent
login handling and re-registration semantics first. No service code is changed from orchestration.

## 11. HSTS `includeSubDomains` and `preload`

| Review | Position |
| --- | --- |
| R2 | Use `includeSubDomains`, plus `preload` in production. HSTS also stops a network attacker planting cookies. |
| R3 | No position on the flags. Agrees with setting HSTS at the ingress. |
| R4 | `includeSubDomains` needs an intentional domain policy. Preload is not a default prerequisite. HSTS does not protect a first contact. |

**Decision — Modify the rationale; keep neither flag by default.** Keep ingress-owned HSTS.
Discard the claim that preload inherently requires serving the registrable apex, and avoid claiming
that Spring's default proves the auth lane currently emits HSTS.

**Evidence.** The [auth route][auth-route] and [application route][app-route] serve
`app.budgetanalyzer.localhost`. Under [RFC 6797](https://www.rfc-editor.org/rfc/rfc6797.html#section-8.2),
`includeSubDomains` on that host extends to descendants, not siblings such as
`other.budgetanalyzer.localhost`. It therefore does not solve sibling-domain cookie injection;
issue 5's host-only cookie constraint addresses that storage risk.

[Session Gateway security][sg-security] leaves default response headers enabled.
[Spring's reactive HSTS writer](https://github.com/spring-projects/spring-security/blob/7.1.2/web/src/main/java/org/springframework/security/web/server/header/StrictTransportSecurityServerHttpHeadersWriter.java)
defaults to one year, includeSubDomains, and no preload, but writes only when the application sees
an HTTPS scheme. That is source evidence, not observation of the effective forwarded scheme or
client-visible response. Verify the final header on both lanes and ensure ingress ownership does
not leave duplicate, conflicting values.

[Google's explanation](https://security.googleblog.com/2017/09/broadening-hsts-to-secure-more-of-web.html)
explicitly allows individual subdomains in the preload list. The relevant scope is the submitted
hostname and its descendants, not necessarily the registrable apex. The
[submission requirements](https://hstspreload.org/#submission-requirements) still entail a valid
certificate, HTTPS commitments and list submission; adding the `preload` token alone does not put
a domain in browsers' preload lists. Dynamic HSTS does not protect a first visit before a policy
is learned; actual preload membership can.

**Recommended disposition.** Use the planned plain HSTS policy for the current local endpoint.
Revisit includeSubDomains/preload only with an owned hosted domain, its descendant inventory and
an explicit long-term HTTPS commitment. That is an operational choice, not a security prerequisite
established by these reviews.

## 12. Generating the NGINX route files

| Review | Position |
| --- | --- |
| R1 | Consolidate route declarations and reduce duplicated policy. |
| R2 | Generate both NGINX route files from a single source. |
| R3 | No position on generation. Puts the edge contract first. |
| R4 | Generating them is optional. The objective is reducing inconsistent ownership. |

**Decision — Modify.** Keep the decision not to introduce a generator. Strengthen the proposed
parity check to compare route behavior; matching location names alone misses security-relevant drift.

**Evidence.** A static extraction of the 11 `/api` location blocks in [local NGINX][nginx-local]
and [production-reference NGINX][nginx-prod] found their bodies identical after removing comments
and whitespace. Both include [backend-headers.conf][backend-headers]. Frontend serving deliberately
differs: local Vite/prod-smoke behavior versus the production bundle and rejected development paths.
The [NGINX owner documentation][nginx-docs] describes that routing contract.

**Recommended change.** Compare location match type and precedence, backend assignment, rewrites,
`proxy_pass`, query preservation, body-size/timeout overrides and required security includes.
Require both `/api` and `/api/` unknown-route rejections. Check shared security behavior even when
it moves to a server-level include. Allowlist intentional frontend differences explicitly.

A normalized comparison of the currently identical API blocks is a useful initial guardrail, but
a simplistic regex that extracts names is insufficient. Use a parser or an extractor that rejects
unsupported syntax instead of silently skipping it. Keep behavioral probes for representative
routes, unknown API paths and encoded inputs: two equally wrong files still pass parity. Reconsider
generation only if route complexity makes the independent files costly to maintain. This review
confirms current parity; it does not add a permanent verifier.

## Severity disputes

**Decision — Modify.** Keep the decision not to invent comparable severity scores from incompatible
reviews. Discard severity labels as substitutes for reachability and impact evidence. The following
is a prioritization assessment, not CVSS scoring.

| Finding | Disposition | Factual basis and limitation |
| --- | --- | --- |
| Session Gateway Redis `+@all` | **Keep the finding; prioritize early.** | [The ACL][redis-acl] grants administration as well as session writes. A compromised session writer already controls sessions, but administration also compromises other ACLs, caches and shared availability. A narrower score does not remove that additional authority. |
| OAuth callback binding | **Keep; prioritize early.** | [State-only lookup][oauth-repository] lacks the initiating-browser check. Single-use IdP codes and PKCE do not cure that missing local binding; see [issue 4](#4-oauth-correlation-cookie-and-atomic-consume). |
| Cookies forwarded to backends | **Keep; prioritize early.** | [The shared NGINX include][backend-headers] does not suppress Cookie/Authorization. [NGINX forwards incoming request headers by default](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass_request_headers), so credential exposure is supported by configuration, although no fresh live capture was taken. |
| CSRF posture | **Keep; qualify exploit scope.** | [Issue 1](#1-primary-csrf-control) establishes missing explicit checks and mutating GETs. CORS, SameSite and endpoint content types affect individual attack paths; neither “all mutations exploitable” nor “SameSite solves it” is established. |
| Encoded-path traversal | **Modify to high verification priority, confirmed parser discrepancy, unverified full-stack impact.** | [Issue 3](#3-encoded-path-traversal-and-rejecting-) reproduces the Envoy behavior. Rank actual severity after valid-session reachability and handler effects are established. |
| `deleteUser` | **Discard as a live endpoint finding; keep latent cleanup.** | [Issue 10](#10-the-unused-deleteuser-method) finds no source caller. Do not assign current remote exploit impact to an unused method. |

## Work order

**Decision — Modify the justification; keep a short initial orchestration block.**
[AGENTS.md](../../AGENTS.md#project-priorities) ranks bug fixes above net-new features, but does not
rank orchestration-owned fixes above service-owned security fixes. Repository boundaries determine
where changes may be made, not their security priority.

Start with the routing baseline and small edge/ACL/credential-forwarding fixes, then promptly handle
browser binding, session-token exposure and CSRF across their owning repositories. Do not postpone
those behind optional generators, signing, port redesigns or egress redesign. Follow contract
cutover dependencies in the [hardening plan](../plans/security-review-consensus-hardening-plan.md#plan-wide-rules).
The plan remains unchanged by this review; its exclusions and decisions need a separate reconciliation
before execution. Its phase numbers below describe the currently reviewed draft, not a durable API.

## Settled by checking the code

**Decision — Keep the verified corrections, with the following qualifications.** Every row from the
original table is reassessed here; “settled” refers to the stated source-level fact, not a live proof.

| Original claim or dispute | Verdict | Supported finding |
| --- | --- | --- |
| How many services log bodies | **Modify wording; keep count of four.** | Request-body logging is enabled in [transaction-service][transaction-application], [currency-service][currency-application], [permission-service][permission-application] and [Session Gateway][sg-application]. Currency disables response-body logging. These are defaults in configuration, not observations of every deployed log stream. |
| How many `loadPDF` sites | **Keep five.** | The five linked production-source call sites are listed in [issue 6](#6-pdf-memory-handling-and-a-parsing-worker). |
| “Nothing enforces `@PreAuthorize`” | **Discard.** | [ClaimsHeaderSecurityConfig][claims-security] enables method security. That supports annotation enforcement when this configuration is active; it does not prove every endpoint has adequate permissions/ownership checks. |
| Sessions last “forever” | **Modify.** | [SessionWriter][session-writer] extends expiry without an absolute-age setting; [heartbeat][heartbeat] requires a successful account/grant refresh, and [ext-authz][session-lookup] rejects expired records. Continued successful renewal is unbounded by age; an unattended session still expires. |
| ADR 007 wording | **Keep the correction.** | [ADR 007](../decisions/007-browser-only-session-gateway.md) says “revoked at Auth0.” It does not establish that IdP revocation immediately terminates local sessions. The ADR is context and was not edited. |
| “Instant revocation” contradicts the race | **Modify to precise timing.** | [ext-authz][session-lookup] reads Redis per authorization check. A completed deletion rejects a subsequent lookup while the record remains absent; it does not cancel an already-authorized request, cover a concurrent new session, or guarantee account-wide revocation atomicity. [SessionWriter][session-writer] and the [session contract](../architecture/session-edge-authorization-pattern.md) are the relevant implementation/contract. |
| `statusOnError: "503"` fixes the contract | **Discard as a complete fix.** | The [provider][provider] currently lacks it. [Envoy's HTTP authorizer client](https://github.com/envoyproxy/envoy/blob/release/v1.38/source/extensions/filters/common/ext_authz/ext_authz_http_impl.cc) maps authorizer 5xx responses to an error result, and [status_on_error](https://www.envoyproxy.io/docs/envoy/latest/api-v3/extensions/filters/http/ext_authz/v3/ext_authz.proto.html#envoy-v3-api-field-extensions-filters-http-ext-authz-v3-extauthz-status-on-error) selects a status. Setting it does not preserve the authorizer's JSON body; prove or revise that client-visible contract separately. |
| RabbitMQ 3.13 is end-of-life | **Modify to community-support ended.** | [The manifest][rabbitmq] selects 3.13. The vendor's [release table](https://www.rabbitmq.com/release-information) gives community EOL as 2024-09-30 and an indicative commercial end of 2029-12-31. Commercial coverage requires a license; it is not implied by this image. Keep the upgrade direction and verify the target's support at implementation time. |
| The quarterly review “missed” RabbitMQ | **Discard as an established event.** | [R2](application-architecture-security-review-second-opinion-2026-11-01.md) infers process failure from the version. The manifest proves selection of an out-of-community-support series, not that a particular review ran or missed it. |
| No timeout on the login call | **Keep only the narrower claim.** | [fetchPermissions][permission-client] lacks the explicit operation timeout used by `fetchAuthorization`; [WebClientConfig][webclient-config] sets only the base URL. This proves no application-level deadline here, not the absence of all transport defaults. |
| Redis `maxmemory` at 70–75% | **Discard as a justified value.** | [The StatefulSet][redis-deployment] has a 256 MiB container limit and [startup][redis-acl] supplies no maxmemory budget. Percentages need measured dataset, allocator, persistence and connection overhead. Preserve Phase 28's measurement requirement. |
| PostgreSQL citation | **Keep the correction; qualify runtime conclusion.** | [The StatefulSet][postgresql] configures SCRAM authentication and `ssl=on`, but neither requires TLS on every accepted connection. [PostgreSQL's HBA rules](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html) distinguish `host` from `hostssl`/`hostnossl`; the checked-in [init configuration][postgresql-init] does not establish a TLS-only HBA policy. Inspect effective HBA rules and test rejection of non-TLS traffic in the eventual local implementation phase. |

## Verification record

All checks below were performed on 2026-11-05. The workspace VM boundary check passed. The existing
modified hardening plan was not changed, and the research document was already untracked when this
review began.

| Check | Method | Result and scope |
| --- | --- | --- |
| Redis key enumeration | Disposable `--network none` container from the manifest's pinned `redis:7-alpine@sha256:858f009f9709ce576febc734aa78b8f6d624b82571f9ddb6bda4377c833b3499`; Redis reported 7.4.11. Used dummy data and a Unix socket, no published ports or host mounts. | A `~currency-service:* +get +keys +scan` test user received `NOPERM` for `GET session:dummy-digest`, but both enumeration commands returned the session and user-index key names. This tests the relevant ACL subset; it is not a live application credential test. |
| Envoy normalization | Disposable `--network none` Envoy 1.38.8 container; build `d098c69f64497010931e92fb6f580ee67638fa51`. Minimal HTTP connection manager with `normalize_path: true`, escaped-slash rejection, a direct-response route and `%REQ(:PATH)%` response header. | The two inputs/results in issue 3 were observed. No Istio-generated config, real NGINX or Spring backend was included in this new probe. |
| NGINX API parity | Extracted `/api` location blocks; compared their declarations and bodies after dropping comments/whitespace. | 11 blocks in each file, all equal. This is a one-off check of the current simple blocks, not a general NGINX parser. |
| OpenAPI paths | Parsed [openapi.json][openapi] and inspected its `paths` keys. | 29 paths, zero containing `;`. |
| PDF entry points | Searched transaction-service production source for `Loader.loadPDF`. | Five calls; no runtime memory/CPU measurement. |
| Deletion reachability | Searched permission-service `src` for `deleteUser`. | Only its declaration; no production or test caller found. |

Sibling worktrees were clean. These revisions identify the code read, while orchestration also had
the pre-existing documentation edits described above:

| Repository | Reviewed HEAD |
| --- | --- |
| orchestration | `c8b6176a5b83489e619fa84d32cafe31e2255a77` |
| session-gateway | `ee113ac3963e8d57e5e41c0d70d5d4b4e7f7b5cc` |
| ext-authz | `d66f31784ccb67cb51b759a9f8e1692b5925dc4c` |
| permission-service | `aa10c12cc1880c5d497b71ce0dffd1bcff1e76ba` |
| currency-service | `55f8b1170bfdf05971f4a39aded13704b585ed08` |
| transaction-service | `b6fc0d352b666dd2f0ae3322c5036228e304420e` |
| service-common | `88041e3fd9e6374c93e39b38ea5a4b29f7ec6fcc` |
| budget-analyzer-web | `24dca0e202a647b2baf33b97bc7f6421b9023283` |
| budget-analyzer-api-tests | `6abbbc19822cbe2624c38be979135c65c639fafb` |

[provider]: ../../kubernetes/istio/istiod-values.yaml
[custom-policy]: ../../kubernetes/istio/ext-authz-policy.yaml
[auth-route]: ../../kubernetes/gateway/auth-httproute.yaml
[app-route]: ../../kubernetes/gateway/app-httproute.yaml
[sg-security]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/SecurityConfig.java
[heartbeat]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/api/SessionController.java
[logout]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/api/LogoutController.java
[use-auth]: ../../../budget-analyzer-web/src/features/auth/hooks/useAuth.ts
[warning-modal]: ../../../budget-analyzer-web/src/components/InactivityWarningModal.tsx
[use-heartbeat]: ../../../budget-analyzer-web/src/hooks/useSessionHeartbeat.ts
[api-client]: ../../../budget-analyzer-api-tests/src/api_tests/client.py
[go-mod]: ../../../ext-authz/go.mod
[go-docker]: ../../../ext-authz/Dockerfile
[go-build]: ../../../ext-authz/.github/workflows/build.yml
[redis-acl]: ../../kubernetes/infrastructure/redis/start-redis.sh
[credential-verifier]: ../../scripts/smoketest/verify-credential-isolation.sh
[session-writer]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionWriter.java
[session-lookup]: ../../../ext-authz/session.go
[exchange-import]: ../../../currency-service/src/main/java/org/budgetanalyzer/currency/service/ExchangeRateImportService.java
[cache-config]: ../../../currency-service/src/main/java/org/budgetanalyzer/currency/config/CacheConfig.java
[infra-tls]: ../../scripts/bootstrap/setup-infra-tls.sh
[nginx-local]: ../../nginx/nginx.k8s.conf
[nginx-prod]: ../../nginx/nginx.production.k8s.conf
[mesh-policy]: ../../kubernetes/istio/authorization-policies.yaml
[permission-security]: ../../../permission-service/src/main/java/org/budgetanalyzer/permission/config/PermissionServiceSecurityConfig.java
[openapi]: ../../docs-aggregator/openapi.json
[oauth-repository]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java
[cookie-helper]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionCookieHelper.java
[auth-handler]: ../../../ext-authz/http_server.go
[sg-application]: ../../../session-gateway/src/main/resources/application.yml
[auth-config]: ../../../ext-authz/config.go
[pdf-bank]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/extractor/CapitalOneBankMonthlyStatementExtractor.java
[pdf-monthly]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/extractor/CapitalOneCreditMonthlyStatementExtractor.java
[pdf-yearly]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/extractor/CapitalOneCreditYearlySummaryExtractor.java
[pdf-bangkok]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/extractor/BangkokBankStatementPdfExtractor.java
[pdf-text]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/extractor/pdf/PdfTextExtractionService.java
[transaction-import]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/TransactionImportService.java
[statement-controller]: ../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/api/StatementFormatController.java
[transaction-application]: ../../../transaction-service/src/main/resources/application.yml
[transaction-deployment]: ../../kubernetes/services/transaction-service/deployment.yaml
[transaction-docker]: ../../../transaction-service/Dockerfile
[claims-security]: ../../../service-common/service-web/src/main/java/org/budgetanalyzer/service/security/ClaimsHeaderSecurityConfig.java
[claims-filter]: ../../../service-common/service-web/src/main/java/org/budgetanalyzer/service/security/ClaimsHeaderAuthenticationFilter.java
[backend-headers]: ../../nginx/includes/backend-headers.conf
[claims-options]: ../../../service-common/docs/plans/claims-header-trust-hardening-options.md
[sg-service]: ../../kubernetes/services/session-gateway/service.yaml
[sg-deployment]: ../../kubernetes/services/session-gateway/deployment.yaml
[internal-session]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/api/InternalSessionController.java
[egress-routing]: ../../kubernetes/istio/egress-routing.yaml
[egress-network]: ../../kubernetes/network-policies/istio-egress-allow.yaml
[user-service]: ../../../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserService.java
[user-controller]: ../../../permission-service/src/main/java/org/budgetanalyzer/permission/api/UserController.java
[permission-schema]: ../../../permission-service/src/main/resources/db/migration/V1__initial_schema.sql
[user-sync]: ../../../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserSyncService.java
[user-repository]: ../../../permission-service/src/main/java/org/budgetanalyzer/permission/repository/UserRepository.java
[nginx-docs]: ../../nginx/README.md
[currency-application]: ../../../currency-service/src/main/resources/application.yml
[permission-application]: ../../../permission-service/src/main/resources/application.yml
[permission-client]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/service/PermissionServiceClient.java
[webclient-config]: ../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/WebClientConfig.java
[redis-deployment]: ../../kubernetes/infrastructure/redis/statefulset.yaml
[rabbitmq]: ../../kubernetes/infrastructure/rabbitmq/statefulset.yaml
[postgresql]: ../../kubernetes/infrastructure/postgresql/statefulset.yaml
[postgresql-init]: ../../kubernetes/infrastructure/postgresql/configmap.yaml
