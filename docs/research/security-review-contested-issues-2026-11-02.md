# Security Review: Contested Issues

**Original date:** 2026-11-02  
**Reassessment:** 2026-11-05  
**KISS reconciliation:** 2026-11-05; incorporates the additional review A1–A13 below.

**Final decisions:** 2026-11-05; currency-service cache eviction moves to `SCAN`, and PDF limits are
deferred as a documented known limitation.

**Status:** Reviewed recommendations. These verdicts replace the original discussion recommendations;
they do not implement fixes. The original hardening plan has since been split into plans [01](../plans/security-hardening-01-edge-mesh-redis-acl.md), 02 (since split into mergeable plans [02.1](../plans/security-hardening-02.1-oauth-callback-binding.md) through [02.8](../plans/security-hardening-02.8-exact-origin-ingress.md)), [03](../plans/security-hardening-03-service-runtime.md), [04](../plans/security-hardening-04-data-network-infrastructure.md) and [05](../plans/security-hardening-05-closeout-release-handoff.md), which apply these decisions.

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
primary sources. Earlier passes ran isolated Redis and Envoy probes, plus static route/OpenAPI
checks; results are [recorded below](#verification-record). The latest pass records its own checks
under [reconciliation verification](#reconciliation-verification). No live application, browser, or
PDF load test was run. No cluster resources or service code were changed. Planned hashing, cookie
renaming, and mesh narrowing are not counted as existing protection. Repository links are relative to this document and resolve
in the supported side-by-side checkout; the reviewed revisions are recorded below.

## Summary

| # | Issue | Verdict on original recommendation | Result |
| --- | --- | --- | --- |
| 1 | [CSRF](#1-primary-csrf-control) | **Modify** | Require exact Origin on unsafe requests at the shared ingress; POST heartbeat and form POST logout. Keep OAuth callback binding separate. |
| 2 | [Redis enumeration](#2-redis-enumeration-after-hashing) | **Modify** | Keep hashing and cache-wide eviction; clear with `SCAN` instead of `KEYS` and grant `+scan` only. Accept key-name visibility as metadata exposure after hashing; a Redis split remains optional. |
| 3 | [Encoded paths](#3-encoded-path-traversal-and-rejecting-) | **Modify** | Keep decoded-semicolon rejection and mesh narrowing; the parser discrepancy is reproduced, full-stack exploitability remains unverified. |
| 4 | [OAuth cookie](#4-oauth-correlation-cookie-and-atomic-consume) | **Modify** | Prefer one reusable browser-binding cookie and read/validate/`DEL == 1` consumption of immutable state; no mandatory Lua or cookie-per-tab scheme. |
| 5 | [Duplicate cookies](#5-rejecting-duplicate-session-cookies) | **Modify** | Prioritize `__Host-`; duplicate rejection is optional hardening after that cutover. |
| 6 | [PDF memory](#6-pdf-memory-handling-and-a-parsing-worker) | **Modify** | Make no limit changes now; record unbounded upload processing as a known availability limitation. Prefer configuration-level controls if revisited. |
| 7 | [Signed identity](#7-signed-identity-context) | **Keep** | Defer pending a concrete threat model; record intermediate forgery and replay as residual risks. |
| 8 | [Internal ports](#8-separate-internal-ports) | **Keep** | Defer separate listeners; first prove restrictions on both public lanes. |
| 9 | [Egress identity](#9-per-caller-egress-identity) | **Keep** | Defer as coordinated design work; discard the one-setting remedy. |
| 10 | [`deleteUser`](#10-the-unused-deleteuser-method) | **Modify** | Remove the unused method; preserve the existing distinction between deletion and deactivation. |
| 11 | [HSTS flags](#11-hsts-includesubdomains-and-preload) | **Modify** | Keep neither flag by default; distinguish automatic whole-domain submission from exceptional subdomain entries. |
| 12 | [Route generation](#12-generating-the-nginx-route-files) | **Modify** | Share API route includes instead of adding a generator or a custom parity parser; retain configuration and behavioral checks. |

The sections on [severity](#severity-disputes), [work order](#work-order), and
[previously settled claims](#settled-by-checking-the-code) also have explicit dispositions.

## 1. Primary CSRF control

| Review | Position |
| --- | --- |
| R1 | Tokens for unsafe requests, exact-origin validation, and Fetch Metadata as a supplement. Move heartbeat and logout to POST. |
| R2 | `Sec-Fetch-Site` in ext-authz as the main control, with `Origin` as the fallback. The POST move is "fine hygiene but low value". |
| R3 | Fetch Metadata is the main control and tokens are not needed. Allow requests that carry neither header. The auth lane needs its own check. |
| R4 | Tokens and Fetch Metadata can both work, and R2's claim that Fetch Metadata is stronger is unqualified. Missing headers must be specified, not waived for test clients. Both lanes need cover. Heartbeat and logout must move to POST. |

**Decision — Modify.** Require exact Origin on unsafe requests at the shared Istio ingress, and
move heartbeat and logout to POST. This is the simplest sufficient CSRF contract for the current
single-origin browser application. A Fetch Metadata fallback, a token system, and two independent
implementations in Go and Java are unnecessary for this topology. Missing Origin fails closed.

**Evidence and corrections.** The [ext-authz provider][provider] explicitly forwards `cookie`, but
not `origin` or `sec-fetch-site`. Its [CUSTOM policy][custom-policy] covers `/api/*`; the
[auth HTTPRoute][auth-route] sends OAuth, auth and logout traffic directly to Session Gateway.
[Session Gateway security][sg-security] disables CSRF. [Heartbeat][heartbeat] refreshes stored
authorization and expiry through GET. [Logout][logout] clears the cookie even when none arrived,
and redirects to the IdP; its scope includes the IdP logout flow, not merely a local UI transition.
The four navigation call sites are in [useAuth][use-auth], [InactivityWarningModal][warning-modal]
and [useSessionHeartbeat][use-heartbeat].

The session cookie already defaults to `SameSite=Strict` in [configuration][sg-application]. In a
conforming browser this excludes it from cross-site requests, including top-level navigations;
same-site cross-origin callers remain relevant. Strict does not stop a top-level response from
clearing the cookie. Thus the unconditional logout response can still disrupt a browser arriving
from another site, without reading its session. This follows from the
[cookie storage rules](https://httpwg.org/http-extensions/draft-ietf-httpbis-rfc6265bis.html#name-storage-model),
not a new browser reproduction. Changing only GET to POST does not stop a hostile form submission.

**Recommended contract.** On the application HTTPS ingress, deny methods other than GET, HEAD
and OPTIONS unless Origin equals the configured serialized browser origin (scheme, host and
effective port). Reject absent, `null`, foreign or multi-valued Origin; do not accept suffix matches
or derive the trusted value from caller-controlled forwarding headers. Fetch Metadata must not
provide an exception to this check. The [Fetch standard](https://fetch.spec.whatwg.org/#origin-header)
sends Origin on these browser mutations. Its form-POST value can become `null` under `no-referrer`;
the current `strict-origin-when-cross-origin` policy preserves it for same-origin HTTPS submission.
The [API-test client][api-client] can supply Origin explicitly; this header is CSRF provenance,
not authentication for arbitrary HTTP clients.

Prefer one native ingress `DENY` AuthorizationPolicy covering both lanes and scoped to the HTTP
application listener. [Istio supports negative header matches](https://istio.io/latest/docs/reference/config/security/authorization-policy/).
Before treating the policy as complete, prove rejection of missing/empty/null/foreign Origin in
the generated configuration and live local requests, plus success for the configured origin on
both lanes. A permissive `ALLOW` rule is not a substitute: other ALLOW policies are additive.
This design depends on the existing mesh restrictions preventing browser access around ingress.
Internal workload calls use their own caller/path policy. The current OAuth GET callback uses
issue 4's browser binding; a future POST callback requires an explicit contract change.

Use a same-origin top-level form POST to `/logout`, then a server-constructed **303** redirect to
the configured IdP logout URL. Share that submission helper across all four callers. This keeps
navigation in the browser without adding a JSON URL response contract. Reject the old mutating
GET **and HEAD** handlers, and move heartbeat callers to POST in the same cutover.

**Plan dependency.** The current CSP has no `form-action`, but [plan 01, Phase 5](../plans/security-hardening-01-edge-mesh-redis-acl.md#phase-5-harden-ingress-headers-and-the-csp-live) already
proposes `form-action 'self'`. [Form-action constrains form navigation](https://w3c.github.io/webappsec-csp/#directive-form-action),
and redirect enforcement must be checked in supported browsers. Reconcile that phase with logout:
permit the configured IdP logout destination alongside self where needed, without a wildcard.
Keep the existing referrer policy. Verify login, logout, hostile same-site/cross-site submissions,
and absence of mutation on rejected requests with the final CSP. Do not defer this compatibility
check on the basis that the directive is absent today.

## 2. Redis enumeration after hashing

| Review | Position |
| --- | --- |
| R1 | No position on enumeration. Prefers separating security state from caches "when deployment requirements justify it". |
| R2 | Do all of it: hash, replace clear-all eviction with a versioned prefix, remove `+keys +scan`, and split Redis as the architectural fix. |
| R3 | These are redundant. Hashing or splitting each stops token theft alone. A versioned prefix is only needed to drop the grant on a shared Redis. Split before hosted use, not first. |
| R4 | Address both properties. Hashing reduces the consequences, but "does not make the original isolation claim true". Also remove enumeration or split. Splitting does not replace hashing or stop anonymous OAuth-state growth. |

**Decision — Modify.** Keep hashing. Keep currency-service's cache-wide `@CacheEvict(allEntries = true)`
eviction and its existing freshness behavior, but clear with `SCAN` instead of `KEYS` and narrow the
grant to `+scan`. This does not remove key-name enumeration; accept it as residual metadata exposure
once session keys are hashed. Discard both the cache-generation and TTL-only alternatives. A separate
auth/cache Redis instance remains an availability-isolation option, not a prerequisite.

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
with a one-hour write TTL. Both sources explicitly accept a read racing an import re-caching a
stale result until that TTL expires. Eviction is service-level, not specific to the manual endpoint:
the [daily scheduler][import-scheduler], optional startup import and manual import endpoint call
`importLatestExchangeRates`, and the [import consumer][import-consumer] calls
`importExchangeRatesForSeries` when a currency is created or re-enabled. The third evicting method,
`importMissingExchangeRates`, has only test callers.

Redis has no delete-by-prefix command, so `allEntries` clears by listing matching key names and
deleting them. `CacheConfig` configures no batch strategy. Spring Boot 4.1.2 manages Spring Data
Redis 4.1.2, whose `RedisCacheWriter` defaults to `BatchStrategies.keys()`. Each eviction therefore
runs `KEYS currency-service:exchangeRates::*` followed by `DEL`; the `+scan` grant is currently
unused. Single-key eviction needs only `DEL`, but cannot cover the arbitrary date-range keys.

**Recommended change.** In currency-service, add a `SCAN` batch strategy
(`BatchStrategies.scan(...)`) to the existing cache-writer configurer alongside `immediateWrites()`,
and choose the batch size there. Then remove `+keys` from the currency-service ACL, retaining
`+scan` and `+del`. Test after-commit eviction under the narrowed grant, and extend the
[credential verifier][credential-verifier] to assert currency-service `KEYS` denial. `SCAN` walks
the keyspace incrementally instead of blocking Redis for one full `KEYS` pass; this matters because
ext-authz reads sessions from the same instance on each request. Like the current `KEYS` clear, it is
not a point-in-time delete; a racing stale write remains the accepted race bounded by the TTL.

**Accepted residual.** Redis ACL key patterns do not filter `SCAN` results, as the isolated probe
showed. After hashing, the currency-service credential can still list session-digest, user-index
and OAuth-state key names. That exposes user identifiers, session counts and in-flight transactions,
but no replayable session token, and issue 4's browser binding prevents a listed state from
completing a login. This accepts R4's metadata point rather than resolving it. Revisit if a Redis
split is adopted for other reasons or that metadata is treated as sensitive.

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

The earlier isolated Envoy 1.38.8 probes with `normalize_path: true` produced:

| Input to Envoy | Path after normalization |
| --- | --- |
| `/api/v1/users/..%3b/..%3b/internal/v1/users/u1/authorization` | Unchanged |
| `/permission-service/v1/users/..;/..;/internal/v1/users/u1/authorization` | `/permission-service/internal/v1/users/u1/authorization` |
| `/a/b/%2e%2e;/c` (additional probe) | `/a/b/..;/c` |

This independently confirms the critical normalization distinction reported by
[R3's reduced-chain test](application-architecture-security-review-third-assessment-2026-11-01.md#n1-high-priority-medium-high-severity-public-edge-to-internal-endpoints).
It does not reproduce the full generated ingress/NGINX/sidecar/Spring chain.
[NGINX documents](https://nginx.org/en/docs/http/ngx_http_core_module.html#location) percent-decoding
before location matching and a normalized `$uri`; [Istio documents](https://istio.io/latest/docs/reference/config/security/normalization/)
that normalization precedes authorization and forwarding. These facts explain why a backend firewall
can receive an already-clean internal path.

**Recommended change.** Narrow the mesh caller/method/path rules now; a complete exploit
reproduction is not a prerequisite for removing known excessive authority. Keep a server-level
`if ($uri ~ ";") { return 400; }` in the shared NGINX include proposed in issue 12, plus mesh
restrictions as the authorization boundary. The
[checked-in OpenAPI document][openapi] now has **29**, not 22, paths; none contains `;`. This supports
rejecting undocumented matrix-parameter syntax, but is not a compatibility proof for every client.

The `%2e%2e;` result also shows that one hop can emit a dot segment that a later hop collapses;
add it explicitly to the regression cases. Test literal, encoded, mixed-case and double-encoded
forms through both the NGINX lane and the direct
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

**Decision — Modify.** Prefer one reusable browser-binding cookie and require exactly one
successful consumer of each state record. Per-transaction cookies and Lua are possible designs,
but neither is necessary for that contract. IdP single-use codes do not replace browser binding.

**Evidence.** [RedisAuthorizationRequestRepository][oauth-repository] stores PKCE/nonce data under
`oauth2:state:<state>` and retrieves it from the callback query alone. Removal performs a read and
then a delete; it returns the request without making successful deletion a single-winner condition.
There is no browser-cookie comparison. [RFC 9700](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1)
requires transaction-specific PKCE/nonce material to be bound to the initiating user agent. IdP
code replay protection does not establish that binding or make the local record single-consumer.

**Recommended design.** On login start, reuse a valid high-entropy random binding cookie, or
generate one if absent. Use Secure, HttpOnly, `__Host-`, `Path=/`, `SameSite=Lax`, no Domain and
browser-session lifetime. Store its hash alongside each transaction's independently random state,
PKCE and nonce. The cookie must not be the session token or be derivable from state. Each state
record retains its short TTL. Lax fits the current top-level GET callback, not cross-site POST.

Keep the binding cookie across callbacks instead of clearing or rotating it for each login; that
preserves pending tabs. Cookie loss invalidates pending callbacks. Simultaneous first starts can
set different bindings: the response that wins cookie storage determines which callback succeeds,
and the other fails closed with a fresh-login retry. Accept that limited UX race rather than
building per-tab cookie naming, counting and eviction. Existing-cookie parallel starts share the
binding and retain independent state. This cookie alone never authenticates an application request.

**Consume rule.** Read the record, validate the browser-binding hash, then delete that exact state
key. Return the authorization request and set callback attributes **only if `DEL` returns 1**;
zero or a Redis error fails closed. Do this before code exchange/session issuance, including the
denial/error callback path. A wrong or missing cookie must never reach deletion.
[DEL returns the number of keys removed](https://redis.io/docs/latest/commands/del/), so this has
one winner provided each random state key is immutable and never reused or recreated. Keep these
records write-once, including their binding. Expiry between read and delete returns zero.
The comparison and deletion are not one atomic operation;
immutability makes that unnecessary. If records can be replaced, use atomic compare-and-delete
instead. A plain read followed by an unchecked delete, as today, does not satisfy this rule.

Test wrong/missing binding without record loss, replay, competing callbacks, expiry between read
and delete, denial/error callbacks and both kinds of parallel start. This establishes the specific
single-consumer contract without introducing scripting or changing the Redis record format solely
to use `GETDEL`. Keep anonymous state TTL/rate/capacity controls: one reusable cookie does not bound
the number of pending Redis records.

## 5. Rejecting duplicate session cookies

| Review | Position |
| --- | --- |
| R1 | No position. |
| R2 | Reject requests carrying two session cookies. A planted `Path=/api` cookie wins today, because browsers send longer paths first. |
| R3 | Skip it. A browser will not accept a planted `__Host-` cookie with `Path=/api` or a `Domain`. |
| R4 | Supports "unambiguous handling". Must not reject unrelated cookies or HTTP/2 header splitting. |

**Decision — Modify.** Adopt `__Host-` as the main protection against the cited cookie-tossing
attack. Make duplicate-name rejection optional hardening after that cutover; it is not a separate
security milestone without an identified remaining attack path.

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

**Recommended change.** Coordinate the rename, remove Domain override, and verify the real browser
prefix contract. Until that ships, do not count its protections as present. If duplicate rejection
is included while touching both consumers, count only the configured session name after parsing;
unrelated cookies and [ordinary HTTP/2 Cookie splitting](https://www.rfc-editor.org/rfc/rfc9113.html#section-8.2.3)
remain valid. A small parameterized test per consumer can cover one match, duplicates in/across
fields, and unrelated names. There is no need for a separate browser/HTTP2 test project for this
optional rule, but a single happy-path assertion would not establish its parsing behavior.

## 6. PDF memory handling and a parsing worker

| Review | Position |
| --- | --- |
| R2 | A crafted PDF can crash the service the way Redis is killed. Use PDFBox's temp-file stream cache, cap pages and text, and limit parses per user. Later, an isolated worker. |
| R3 | The crash is unproven. The default heap is about 128 MiB, so expect `OutOfMemoryError` and GC pressure, not a pod kill. Measure before designing. Defer the worker. |
| R4 | A stream cache does not remove the byte array or cap parsed objects. Use bounded file-backed input, page and output limits, and global plus per-user concurrency. A worker becomes useful when hard termination is required. |

**Decision — Modify; defer all limit changes.** Make no PDF or upload-limit change in this hardening
pass. Record unbounded upload processing as a known availability limitation of the single-replica
transaction-service. Discard an unconditional requirement for application admission control,
page/output limits, file-backed input, per-user limits or a parsing worker now. A temp-file
*stream cache* is not a fix for read-only extraction.

**Evidence.** There are five `Loader.loadPDF(byte[])` sites:
[bank monthly][pdf-bank], [credit monthly][pdf-monthly], [credit yearly][pdf-yearly],
[Bangkok Bank][pdf-bangkok], and [generic PDF text extraction][pdf-text].
[TransactionImportService][transaction-import] and the PDF wizard endpoints in
[StatementFormatController][statement-controller] call `file.getBytes()`.
[Application configuration][transaction-application] allows 25 MB multipart uploads;
[the deployment][transaction-deployment] runs one replica with a 512 MiB container limit, and
[the Docker entrypoint][transaction-docker] sets no explicit heap ceiling. No service manifest or
Dockerfile sets a heap size or an exit-on-OOM flag.

At the edge, only the `/api/v1/transactions/preview` location raises NGINX's body limit to 25M in
both [local][nginx-local] and [production-reference][nginx-prod] configuration. The
`/api/v1/statement-formats` location has no override, so NGINX's 1 MB default applies to the format
wizard uploads. Whether that wizard limit is intentional is not established here. On first login,
[UserSyncService][user-sync] assigns the `USER` role, which the [seed data][permission-seed] grants
transaction and statement-format permissions. Uploads are therefore available to any signed-in user;
who can sign in depends on IdP configuration outside this repository.

[Spring Boot's multipart default](https://docs.spring.io/spring-boot/api/java/org/springframework/boot/servlet/autoconfigure/MultipartProperties.html)
sets `file-size-threshold` to zero. With no override here, servlet upload handling already spools
parts to temporary storage; `getBytes()` then materializes them in the heap. The configured request
limit bounds each upload, not aggregate temporary storage: the pod's `/tmp` is an `emptyDir` without
a size limit. Any application-level admission control would run after servlet multipart handling
and could not cap concurrent spooling. A5 is correct about spooling, but overstates the existing disk
budget.

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

**Known limitation.** A few concurrent maximum-size preview uploads, or one crafted high-expansion
PDF, can plausibly exhaust the default heap. The transaction API would then fail for every user until
the JVM recovers or the pod restarts. This is reasoned from source and defaults, not reproduced. It
affects availability, not data confidentiality. Accept it while there is no hosted deployment or
open-signup requirement. Omit the PDF-bounding phase from [plan 03](../plans/security-hardening-03-service-runtime.md#dropped-phases) rather than executing it, record the limitation in [plan 05, Phase 3](../plans/security-hardening-05-closeout-release-handoff.md#phase-3-full-verification-and-release-handoff-live), and do not present
any current setting as a capacity bound.

**If revisited.** Prefer configuration before application code:

- An NGINX `limit_conn` cap on the 25M preview route, keyed on `$server_name` for one shared counter
  per NGINX replica and returning 503. This needs a carve-out in the
  [NGINX owner documentation][nginx-docs] from its rule against backend-specific limits.
- An explicit heap percentage and `-XX:+ExitOnOutOfMemoryError` in the deployment manifest, with the
  memory limit raised so heap plus non-heap memory fits. Raising only the heap can turn a JVM
  `OutOfMemoryError` into a container OOM kill.
- A lower upload size in both NGINX and Spring if real statements are much smaller than 25 MB.
- More than one replica in a hosted environment.

These bound concurrent upload memory and improve recovery; they do not bound one crafted document
or per-document CPU. Configuration cannot cap extracted text. PDFTextStripper collects a page's
text positions before calling `writeString`, so a later code limit belongs in `processTextPosition`,
not `writeString`. File-backed input, per-user fairness and a killable isolated worker remain later
options; an in-process timeout alone cannot enforce a hard per-document limit.

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
Distinguish the public preload submission rules from what a browser preload list can represent,
and avoid claiming that Spring's default proves the auth lane currently emits HSTS.

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

The [public submission requirements](https://hstspreload.org/#submission-requirements) require the
base domain's HSTS policy with `includeSubDomains`. The
[Chromium checker](https://github.com/chromium/hstspreload/blob/main/domain.go) explicitly rejects
automated subdomain submissions and directs applicants to the registrable domain. Exceptional
subdomain entries do not establish an available self-service path for this project. The earlier
apex correction was therefore misleading as implementation advice; A3 is accepted in that scope.
Adding the `preload` token alone does not put a domain in browsers' lists. Dynamic HSTS does not
protect a first visit before a policy is learned; actual preload membership can.

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

**Decision — Modify.** Keep no generator, and replace the proposed custom parity parser with
a shared NGINX include. Remove duplication before writing tooling to police it.

**Evidence.** A static extraction of the 11 `/api` location blocks in [local NGINX][nginx-local]
and [production-reference NGINX][nginx-prod] found their bodies identical after removing comments
and whitespace. Both include [backend-headers.conf][backend-headers]. Frontend serving deliberately
differs: local Vite/prod-smoke behavior versus the production bundle and rejected development paths.
The [NGINX owner documentation][nginx-docs] describes that routing contract.

**Recommended change.** Put the 11 API location blocks, including both unknown-route rejections,
in one `nginx/includes/api-routes.conf` included by both server blocks. Ship it through the existing
includes ConfigMap in [Tilt][tiltfile] and the [production kustomization][prod-apps-kustomization].
The decoded-semicolon rejection can live at server scope in that include. The five identical
`/api-docs` blocks can likewise share an include; the earlier additional check counted only three
because it missed the two regex locations. Keep the intentional frontend differences in their
existing files.

Validate both complete configurations and their mounted includes. Sharing blocks prevents edits
to those blocks drifting, but inherited server settings and location precedence still affect
behavior. Keep focused probes for routing, query preservation, security headers, unknown API paths
and encoded inputs. There is no reason to implement or maintain a general NGINX parser for this
small route set.

## Severity disputes

**Decision — Modify.** Keep the decision not to invent comparable severity scores from incompatible
reviews. Discard severity labels as substitutes for reachability and impact evidence. The following
is a prioritization assessment, not CVSS scoring.

| Finding | Disposition | Factual basis and limitation |
| --- | --- | --- |
| Session Gateway Redis `+@all` | **Keep the finding; prioritize early.** | [The ACL][redis-acl] grants administration as well as session writes. A compromised session writer already controls sessions, but administration also compromises other ACLs, caches and shared availability. A narrower score does not remove that additional authority. |
| OAuth callback binding | **Keep; prioritize early.** | [State-only lookup][oauth-repository] lacks the initiating-browser check. Single-use IdP codes and PKCE do not cure that missing local binding; see [issue 4](#4-oauth-correlation-cookie-and-atomic-consume). |
| Cookies forwarded to backends | **Keep; prioritize early.** | [The shared NGINX include][backend-headers] does not suppress Cookie/Authorization. [NGINX forwards incoming request headers by default](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass_request_headers), so credential exposure is supported by configuration, although no fresh live capture was taken. |
| CSRF posture | **Keep; qualify exploit scope.** | [Issue 1](#1-primary-csrf-control) establishes missing explicit checks and mutating GETs. The configured Strict cookie blocks cross-site credential attachment, but not same-site cross-origin requests or a top-level response clearing the cookie. Do not label all mutations cross-site exploitable. |
| Encoded-path traversal | **Modify to high verification priority, confirmed parser discrepancy, unverified full-stack impact.** | [Issue 3](#3-encoded-path-traversal-and-rejecting-) reproduces the Envoy behavior. Rank actual severity after valid-session reachability and handler effects are established. |
| `deleteUser` | **Discard as a live endpoint finding; keep latent cleanup.** | [Issue 10](#10-the-unused-deleteuser-method) finds no source caller. Do not assign current remote exploit impact to an unused method. |

## Work order

**Decision — Modify the justification; keep a short initial orchestration block.**
[AGENTS.md](../../AGENTS.md#project-priorities) ranks bug fixes above net-new features, but does not
rank orchestration-owned fixes above service-owned security fixes. Repository boundaries determine
where changes may be made, not their security priority.

Capture the routing baseline when available, but do not delay known mesh overpermission fixes for
exploit reproduction. Start with small edge/ACL/credential-forwarding fixes, then promptly handle
browser binding, session-token exposure and CSRF across their owning repositories. Do not postpone
those behind optional generators, signing, port redesigns or egress redesign. Follow contract
cutover dependencies in the **Merge unit** of each plan 02.x.
The split plans apply the reconciliations: D3 and the binding rule in
[plan 02.1, Phase 1](../plans/security-hardening-02.1-oauth-callback-binding.md#phase-1-bind-oauth-callbacks-to-the-initiating-browser),
the CSP and form logout in
[plan 01, Phase 5](../plans/security-hardening-01-edge-mesh-redis-acl.md#phase-5-harden-ingress-headers-and-the-csp-live),
the ingress Origin/POST cutover in
[plan 02.7](../plans/security-hardening-02.7-post-heartbeat-logout.md) and
[plan 02.8](../plans/security-hardening-02.8-exact-origin-ingress.md), the currency-service `SCAN`
strategy and `+scan`-only grant in
[plan 03, Phases 11 and 13](../plans/security-hardening-03-service-runtime.md#phase-11-clear-the-currency-service-cache-with-scan),
and the PDF deferral in plan 03's dropped phases.

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
| ext-authz Go toolchain mismatch (A4) | **Keep as a separate maintenance finding.** | [Build CI][go-build] selects the 1.24 line from [go.mod][go-mod], while [Docker][go-docker] builds with 1.27. The [Go support policy](https://go.dev/doc/devel/release#policy) excludes 1.24 as of this review. Align supported CI/build toolchains in ext-authz; this is independent of the ingress CSRF design. |
| Redis `maxmemory` at 70–75% | **Discard as a justified value.** | [The StatefulSet][redis-deployment] has a 256 MiB container limit and [startup][redis-acl] supplies no maxmemory budget. Percentages need measured dataset, allocator, persistence and connection overhead. Preserve the measurement requirement in [plan 04, Phase 1](../plans/security-hardening-04-data-network-infrastructure.md#phase-1-set-an-explicit-redis-memory-budget-live). |
| PostgreSQL citation | **Keep the correction; qualify runtime conclusion.** | [The StatefulSet][postgresql] configures SCRAM authentication and `ssl=on`, but neither requires TLS on every accepted connection. [PostgreSQL's HBA rules](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html) distinguish `host` from `hostssl`/`hostnossl`; the checked-in [init configuration][postgresql-init] does not establish a TLS-only HBA policy. Inspect effective HBA rules and test rejection of non-TLS traffic in the eventual local implementation phase. |

## Verification record

The following records are from the earlier 2026-11-05 passes. Their workspace VM boundary check
passed. At the first pass, the hardening plan had pre-existing edits and this document was untracked.
Those working-tree observations describe that pass, not the later reconciliation.

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

## Additional review (2026-11-05)

**Status:** Reconciled into the recommendations above. This table records the disposition of
A1–A13 rather than leaving a second, conflicting set of recommendations. Original wording remains
in Git history. These are review decisions, not implemented controls.

| Note | Disposition | Resolution |
| --- | --- | --- |
| A1: `%2e%2e;` | **Accept.** | Add the multi-hop normalization case to issue 3 and its regression matrix. |
| A2: Strict cookie and logout | **Accept with scope.** | State the configured Strict default and its same-site limit; top-level cookie deletion remains possible. Browser effects remain to be tested. |
| A3: HSTS apex | **Accept for automatic submission.** | Primary Chromium checker source confirms the registrable-domain restriction. Exceptional list entries do not justify the earlier operational advice. |
| A4: Go CI | **Accept.** | Move the toolchain mismatch out of CSRF and into the source-level findings table. |
| A5: upload spooling | **Accept in part.** | Reuse servlet spooling; a per-request limit and cleanup do not establish an aggregate disk budget. |
| A6: shared NGINX include | **Accept.** | Replace the custom parity-parser recommendation with shared blocks plus normal configuration and behavioral checks. Count regex locations too. |
| A7: Origin, ingress and form logout | **Accept with a concrete dependency.** | Prefer one exact-Origin ingress rule and form POST/303 logout. The existing plan already adds `form-action 'self'`; reconcile it now and verify redirect compatibility, rather than treating CSP as a hypothetical future change. |
| A8: reusable cookie and DEL count | **Accept with invariants.** | Reuse one browser-session binding cookie; accept a fail-closed first-start race. Validate before deleting and require `DEL == 1` on immutable, never-reused state. Per-transaction eviction policy is unnecessary with this design. |
| A9: cache parity | **Superseded by the final decision.** | Adopt neither TTL-only expiry nor generation keys. Keep cache-wide eviction, clear with `SCAN`, grant `+scan` only, and accept key-name metadata exposure. |
| A10: PDF controls | **Superseded by the final decision.** | Make no limit change now and record the known limitation. If revisited, prefer the configuration-level controls in issue 6; heap sizing and restart flags still do not bound one document. |
| A11: duplicates | **Accept optionality after `__Host-`.** | A small parameterized test per consumer is enough if the rule is implemented; it still needs both duplicate and legitimate-cookie cases. |
| A12: mesh first | **Accept.** | Fix known excessive caller authority without waiting for a successful full-chain exploit; retain integration tests for the final boundary. |
| A13: caveats | **Accept selectively.** | Keep one overall evidence boundary and distinguish earlier probes from this pass. Retain limitations where they change the design, such as per-upload versus aggregate disk limits. |

### Additional verification

All checks were performed on 2026-11-05. Sibling HEADs matched the [table above](#verification-record).
Orchestration HEAD was `f32eeee`, which differs from the recorded `c8b6176` only by adding this
document and the hardening plan.

| Check | Method | Result and scope |
| --- | --- | --- |
| Envoy normalization | Disposable `--network none` container from the local `envoyproxy/envoy:v1.38.8` image (`9b6dd34943ea`), config passed with `--config-yaml` and no mounts. HTTP connection manager with `normalize_path: true`, escaped-slash rejection and a direct response echoing `%REQ(:PATH)%`. Requests sent over container loopback. | Results below. No Istio-generated config, NGINX or Spring backend was included. |
| NGINX API parity | Earlier extraction covered 11 `/api` and 3 non-regex `/api-docs` blocks, stripped comments and whitespace, then ran `diff` across both files. | Identical for that subset. The reconciliation below also includes the two regex docs locations. |
| Cookie and header policy | Read the Session Gateway config and searched the NGINX includes. | Session cookie `SameSite=Strict` by default. No `form-action` directive; `Referrer-Policy: strict-origin-when-cross-origin`. |
| HSTS preload | Earlier pass used hstspreload.org requirements and community-reported checker output. | Automatic submission targets the registrable domain; primary checker source was verified during reconciliation. |
| Cache invalidation | Read currency-service cache configuration, eviction sites, callers and lookup validation. | Stale-read race explicitly accepted with a one-hour TTL bound; a currency with no data at all throws. Empty date ranges can return cacheable empty lists, as clarified during reconciliation. |

| Input to Envoy | Path after normalization |
| --- | --- |
| `/permission-service/v1/users/..;/..;/internal/v1/users/u1/authorization` | `/permission-service/internal/v1/users/u1/authorization` |
| `/a/b/../c` (control) | `/a/c` |
| `/a/b/..;/c` | `/a/c` |
| `/a/b/..;x/c` | `/a/c` |
| `/a/b/.;/c` | `/a/b/c` |
| `/a/b;p/../c` | `/a/c` |
| `/a/b/..%3b/c` | Unchanged |
| `/a/b/%2e%2e;/c` | `/a/b/..;/c` |

### Reconciliation verification

This pass started from clean orchestration HEAD `3f9685228029fee898e50815d35d2f4cf97f83d3`.
All sibling HEADs still matched the verification table above and were clean. The workspace boundary
check passed. Only this research document was edited; the implementation plan remains a draft.

| Check | Result and scope |
| --- | --- |
| Source and plan review | Rechecked cookie defaults, logout/controller callers, OAuth repository, mesh/ingress routing, cache configuration/import/query logic, PDF input paths and deployment, NGINX includes, and the plan's CSP/cookie decisions. Found the planned form-action dependency and the cacheable empty-range case. |
| Redis consume primitive | Disposable network-isolated container using the same pinned Redis image as the earlier probe, reporting 7.4.11; no mounts or published ports, dummy data only, container removed afterwards. Eight callers all read the same immutable hash before competing to delete it: exactly one returned 1 and seven returned 0. Expiring a hash after reading it made deletion return 0. This tests the primitive, not the future Java binding/callback implementation. |
| NGINX/OpenAPI | Repeated the one-off body comparison including regex locations: 11 API and 5 docs blocks match after comment/whitespace removal. OpenAPI still has 29 paths and no semicolons. No effective-config or live routing claim follows from this comparison. |
| Primary references | Checked Fetch Origin rules, cookie storage rules, Istio authorization semantics, Chromium's preload checker, Spring multipart defaults, PDFBox input behavior and Go's support policy. Links are in the relevant sections. |
| Documentation validation | Checked relative file links, local section anchors, reference definitions and `git diff --check`. |

No new Envoy, live application, browser or PDF resource test was run. Ingress denial semantics,
logout under final CSP, service-level callback races and PDF budgets remain implementation
acceptance work, not reasons to retain the more complicated recommendations.

### Final decision verification

This pass started from orchestration HEAD `bb75b484b5247467aca5bbb72cdcdbe0a1bf8e7b`. All sibling
HEADs still matched the verification table above and were clean. The workspace boundary check
passed. Only this research document was edited.

| Check | Result and scope |
| --- | --- |
| Cache eviction mechanism | Read `CacheConfig` and the eviction callers. Spring Boot 4.1.2's BOM selects Spring Data Redis 4.1.2; bytecode inspection of that jar showed `RedisCacheWriter` defaulting to `BatchStrategies.keys()`, whose clean runs `KEYS` then `DEL`, and a configurer exposing `batchStrategy(...)`. No `SCAN` strategy was run against Redis. |
| Upload exposure | Read the NGINX upload locations, transaction-service multipart and deployment settings, Dockerfiles and manifests for heap flags, and the default role grants. No hosted deployment exists. |
| Runtime | The local cluster had no transaction-service pod, so no heap, resident-memory or non-heap measurement was taken. |

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
[tiltfile]: ../../Tiltfile
[prod-apps-kustomization]: ../../kubernetes/production/apps/kustomization.yaml
[csp-includes]: ../../nginx/includes/security-headers-strict-csp.conf
[import-scheduler]: ../../../currency-service/src/main/java/org/budgetanalyzer/currency/scheduler/ExchangeRateImportScheduler.java
[import-consumer]: ../../../currency-service/src/main/java/org/budgetanalyzer/currency/messaging/consumer/ExchangeRateImportConsumer.java
[permission-seed]: ../../../permission-service/src/main/resources/db/migration/V2__seed_default_data.sql
