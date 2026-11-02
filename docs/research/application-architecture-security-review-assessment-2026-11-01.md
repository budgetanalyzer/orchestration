# Assessment of the Architecture Security Reviews

**Date:** 2026-11-01  
**Status:** Research assessment; recommendations, not implementation approval

This assesses the [first review](application-architecture-security-review-2026-11-01.md)
and [second opinion](application-architecture-security-review-second-opinion-2026-11-01.md)
against the checked-in orchestration configuration and current sibling source.

**I agree with keeping the architecture and fixing its trust-boundary defects.**
The second opinion's Redis token-enumeration finding is its most important
addition. The first review is generally more careful about distinguishing
necessary fixes from optional architectural changes. I would combine their
findings, but would not adopt the second review's severity changes or proposed
redesigns wholesale.

The immediate priorities are browser-bound OAuth transactions, Redis credential
isolation, removal of browser credentials from backend requests, and verification
of the public-to-internal routing boundary. Authorization failure handling and
sensitive logging also deserve early fixes. Signed internal assertions, separate
internal listeners, and parsing workers need explicit design decisions; the
reviews do not establish that all three are prerequisites for using real data.

## Assessment of the first review's eight findings

| Finding | Assessment | Qualification |
| --- | --- | --- |
| 1. OAuth callback lacks browser binding | **Agree; high priority.** | PKCE and nonce do not repair a transaction retrieved solely through transferable `state`. The victim noticing a different profile is not a reliable mitigation. |
| 2. Session Gateway has Redis `+@all` | **Agree with the fix.** | The second review correctly identifies the incremental privilege, but Medium versus High depends on the threat model and impact being rated. Full Redis administration remains a significant boundary failure. |
| 3. Backends receive session cookies | **Agree.** | Credential masking in logs reduces one exposure path; it does not justify giving reusable credentials to services that only need claims. |
| 4. No absolute session lifetime | **Agree.** | An absolute cap bounds a session's life. It does not itself guarantee fresh credentials, MFA, or immediate account-wide revocation. |
| 5. SameSite-only CSRF posture and GET mutations | **Agree on the gap; qualify the remedy.** | Tokens are one sound option. A carefully defined Fetch Metadata/origin policy can also work, but must cover both API and direct auth routes. |
| 6. Sensitive body logging | **Agree; correct the scope.** | All four Java services enable some body logging. Session Gateway's Kubernetes profile disables request bodies, but leaves response bodies enabled. |
| 7. Dependency failures trigger restarts | **Agree.** | Separate process health from dependency readiness, and align startup timing with initialization. |
| 8. Shared Redis has no memory policy | **Agree.** | Do not replace this with an unmeasured percentage or assume `noeviction` preserves availability. It changes exhaustion into rejected writes. |

The severity labels in the source reviews are judgments rather than comparable
scores. An issue requiring compromise of a workload differs from one reachable
by a browser or an ordinary user. Both can still have high remediation priority.

## Redis: the strongest additional finding, with two distinct fixes

The [Redis ACL bootstrap](../../kubernetes/infrastructure/redis/start-redis.sh)
grants currency-service `KEYS` and `SCAN` while restricting key access to
`currency-service:*`. Those restrictions do not filter enumeration results.
[SessionWriter](../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionWriter.java)
uses the raw cookie token in the session key, and
[create-session.lua](../../../session-gateway/src/main/resources/redis/create-session.lua)
also puts it in the user's session index.

An isolated check during this review reproduced the issue against the pinned
Redis image, reporting Redis 7.4.11: currency-service could enumerate a synthetic
session key with both commands, while `GET` returned `NOPERM`. This confirms
the second opinion's finding A. Exploitation requires the currency-service
identity and permitted Redis access; it is not an anonymous public enumeration
endpoint. Once that boundary is crossed, however, the key names are reusable
credentials for other accounts.

I would address both properties:

1. Store a hash of the high-entropy session token in **both session keys and
   index members**, with a coordinated change in Session Gateway and ext-authz.
   This removes the bearer value from those persisted structures. It does not
   stop an authorized session writer from fabricating identities.
2. Remove unnecessary key enumeration from the cache identity, or give the
   cache a separate Redis instance and network boundary. Hashing does not make
   the original isolation claim true; it reduces the consequences of disclosure.

Removing `KEYS`/`SCAN` immediately would break the current cache-wide invalidation
contract: [ExchangeRateImportService](../../../currency-service/src/main/java/org/budgetanalyzer/currency/service/ExchangeRateImportService.java)
uses `allEntries = true`. Replace that behavior in the owning repository before
tightening the shared-instance ACL. A versioned prefix is an option, with an
expiration/cleanup policy for obsolete generations. Switching to `SCAN` alone
does not close the leak.

The same isolated check confirmed that `ACL DRYRUN` permits Session Gateway to
request `FLUSHALL` and ACL changes. I agree that this writer already controls
session identities; I disagree that this makes the wider administrative grant
unimportant. It also controls other users, cache integrity, and shared
availability. Fix it alongside enumeration. Replace the verifier's assertion of
the exact `+@all` line in
[verify-session-architecture.sh](../../scripts/smoketest/verify-session-architecture.sh)
with behavioral allow/deny checks. An allowlist must cover cold starts, script
loading, renewal, revocation, and OAuth failure paths; a command trace from one
successful login is insufficient.

I also agree with avoiding `allkeys-lru` for the current auth data model:
evicting the session index independently of session hashes undermines indexed
revocation. Separate auth/cache instances are a sensible deployment option,
but do not prevent anonymous OAuth-state growth within the auth instance.

## OAuth and session controls: agree on binding, avoid universal prescriptions

[RedisAuthorizationRequestRepository](../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java)
loads the authorization request using `state` alone and consumes it through a
read followed by a delete. The corresponding
[integration test](../../../session-gateway/src/test/java/org/budgetanalyzer/sessiongateway/config/SecurityConfigIntegrationTest.java)
completes a callback without a browser correlation cookie. Both reviews identify
a real missing binding. RFC 9700 requires transaction-specific PKCE/nonce values
to remain bound to the initiating user agent; merely storing those values under
the supplied state does not supply that binding.
[RFC 9700, section 2.1.1](https://www.rfc-editor.org/rfc/rfc9700.html#section-2.1.1)

For the current top-level GET callback, a short-lived Secure, HttpOnly,
`__Host-` correlation cookie with `SameSite=Lax` is a good choice. I would not
describe Lax as mandatory for every OAuth response mode: a cross-site POST
callback would require a different design. Validate the binding before issuing
a session, consume the transaction atomically, and test missing/wrong cookies,
replayed callbacks, expiry, and parallel login tabs. Plain `MULTI` around an
already-completed read does not make that read-and-consume sequence atomic.

I support a `__Host-` application-session cookie and unambiguous handling of
duplicate session-cookie names. The prefix requires Secure, `Path=/`, and no
Domain attribute; it is more than a naming change. Coordinate configuration,
parsers, tests, and removal of the old cookie. Duplicate-name rejection must not
reject unrelated cookies or ordinary HTTP/2 splitting of Cookie headers.
[HTTP cookie specification, work in progress](https://httpwg.org/http-extensions/draft-ietf-httpbis-rfc6265bis.html#name-the-host-prefix)

Both reviews correctly identify sliding renewal without an absolute cap in
`SessionWriter`. Enforce the cap on renewal and authorization, preserving the
existing permission refresh. A fresh OAuth roundtrip can still reuse an IdP
SSO session; requirements for fresh credentials or MFA need their own
reauthentication/step-up policy. Absolute expiry also does not repair the
concurrent grant-change race already documented in the
[session contract](../architecture/session-edge-authorization-pattern.md).

## CSRF: cover both routes and define missing-header behavior

I disagree with the second review's unqualified claim that Fetch Metadata is
stronger than CSRF tokens. It can be an appropriate primary control for a
same-origin browser application, but its strength depends on enforcement and
fallback behavior. OWASP supports a Fetch Metadata policy with suitable
fallbacks; it does not make token-based defenses obsolete.
[OWASP CSRF prevention guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)

The implementation decision must include:

- Reject untrusted cross-origin/same-site unsafe requests, using a configured
  exact target origin rather than trusting arbitrary forwarded-host headers.
- Define treatment of missing metadata and missing or `null` Origin. Do not
  silently waive the browser-session policy to accommodate test clients;
  explicitly specify the supported fallback or separate client contract.
- Enforce the policy on the direct Session Gateway lane as well as `/api/*`.
  [Auth routing](../../kubernetes/gateway/auth-httproute.yaml) bypasses ext-authz.
- Move heartbeat/logout mutations to POST and update callers. An unsafe-method
  filter will not protect mutations that remain GET. Keep the intentional
  OAuth redirect flow separately protected by transaction binding.

CORS/preflight restrictions narrow today's attack surface, but do not establish
a complete CSRF contract for multipart uploads, navigations, and auth endpoints.

## Authorization errors and routing need integration evidence

The second opinion is correct about the omitted ext-authz timeout and error
status. [istiod-values.yaml](../../kubernetes/istio/istiod-values.yaml) specifies
neither. The selected Istio release's implementation supplies **600 seconds**;
this is not a confusion with Envoy's own default.
[Istio implementation](https://github.com/istio/istio/blob/1.30.6/pilot/pkg/security/authz/builder/extauthz.go#L400-L403)

There is a further qualification: Envoy's HTTP authorization client treats an
authorizer's own 5xx response as an error and discards its response payload.
Thus the Go service returning JSON 503 does not by itself satisfy the browser
contract. Configuring `statusOnError: "503"` fixes the status for this error
path, but does not restore the JSON body. Choose and verify either a deliberate
edge error representation or a revised client contract; do not claim that the
two configuration settings alone complete the fix.
[Envoy HTTP authorization implementation](https://github.com/envoyproxy/envoy/blob/v1.38.8/source/extensions/filters/common/ext_authz/ext_authz_http_impl.cc#L391-L399)

Set a bounded deadline based on the authorization latency budget; approximately
one second is a candidate, not a measured requirement. Test authorizer 401,
authorizer 503, connection failure, and timeout through ingress. Preserve
fail-closed behavior in every case.

I strongly agree with narrowing mesh permissions. The
[authorization policies](../../kubernetes/istio/authorization-policies.yaml)
admit NGINX and Session Gateway to all permission-service paths, and admit
ingress to all Session Gateway paths. The
[permission-service internal chain](../../../permission-service/src/main/java/org/budgetanalyzer/permission/config/PermissionServiceSecurityConfig.java)
deliberately delegates caller restriction to the mesh. These policies should
enforce public/internal separation directly.

I would not accept the second opinion's assurance that Spring's default
firewall is the remaining protection against path tricks without testing the
whole chain. Normalization can happen before Spring sees a request. For example,
Envoy's path implementation includes parameter stripping from dot segments
before canonicalization, so its behavior is version/configuration dependent.
[Envoy path handling](https://github.com/envoyproxy/envoy/blob/v1.38.8/source/common/http/path_utility.cc#L29-L55)
The [NGINX users route](../../nginx/nginx.k8s.conf) also rewrites a public prefix
to a service context path. Exercise encoded separators, dot segments, semicolons,
and their decoding across ingress, NGINX, sidecar, and application. A firewall
unit test or a filter matching only literal `;` is not sufficient proof. This
review did not reproduce a public-to-internal request against the live stack.

## Corrections to the second opinion's other findings

**Logging: agree with the risk, disagree with the configuration summary.**
The effective checked-in Kubernetes profile configuration is:

| Service | Request bodies | Response bodies | Evidence |
| --- | --- | --- | --- |
| transaction-service | Enabled | Enabled | [application.yml](../../../transaction-service/src/main/resources/application.yml) |
| permission-service | Enabled | Enabled | [application.yml](../../../permission-service/src/main/resources/application.yml) |
| session-gateway | Disabled | Enabled | [base](../../../session-gateway/src/main/resources/application.yml), [Kubernetes override](../../../session-gateway/src/main/resources/application-kubernetes.yml) |
| currency-service | Enabled | Disabled | [application.yml](../../../currency-service/src/main/resources/application.yml) |

Disable sensitive body logging by default and use synthetic-data debugging
profiles. Credential-field masking does not sanitize financial or personal
data. I also agree with consuming the trusted client-address contract rather
than the caller-controlled first X-Forwarded-For entry.

**Redis exhaustion: credible failure class, unproven capacity estimate.** The
256Mi limit, absent `maxmemory`, 900-second OAuth-state lifetime, and uncapped
application return URL support the concern. They do not establish that 50–60
addresses will crash Redis or that 70–75% is a safe memory budget. Measure RSS,
record sizes, concurrency, persistence overhead, and recovery behavior.
`maxmemory` is not a hard RSS limit; persistence/replication buffers and other
overhead need headroom. Test rejected writes under `noeviction`, including
login and heartbeat failure behavior.
[Redis memory guidance](https://redis.io/docs/latest/develop/reference/eviction/)

**PDF parsing: agree with resource bounds, qualify the demonstrated impact and
fix.** Uploads become byte arrays, the default upload limit is 25MB, and the
transaction pod limit is 512Mi. There are five `Loader.loadPDF(fileContent)`
sites, not three. This supports a resource-exhaustion concern, not a reproduced
single-file crash. PDFBox 3 distinguishes input readers from stream caches:
adding a temporary-file stream cache does not remove the existing byte array
or cap parsed objects and extracted text. Use bounded file-backed input,
page/output limits, global concurrency limits plus per-user fairness, and
measure memory/CPU. A worker/process boundary becomes useful when hard resource
termination and API availability require it.
[Import service](../../../transaction-service/src/main/java/org/budgetanalyzer/transaction/service/TransactionImportService.java),
[PDFBox 3 migration guide](https://pdfbox.apache.org/3.0/migration.html)

**User deletion (D): latent code defect, not an exposed deletion workflow.**
[UserService.deleteUser](../../../permission-service/src/main/java/org/budgetanalyzer/permission/service/UserService.java)
does omit revocation, but no production caller was found.
[UserController](../../../permission-service/src/main/java/org/budgetanalyzer/permission/api/UserController.java)
exposes deactivation instead, which does revoke sessions. The
[schema](../../../permission-service/src/main/resources/db/migration/V1__initial_schema.sql)
explicitly permits subject reuse after soft deletion. Fix or remove the unused
method before exposing it; do not assume account deletion must mean a permanent
ban. That is a product/security policy decision.

**Login permissions (E): agree, with more precise timeout wording.**
[fetchPermissions](../../../session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/service/PermissionServiceClient.java)
lacks an application response deadline, unlike the heartbeat lookup. A bare
WebClient builder does not prove that the underlying transport has no connect
timeout. Bound the operation and change the user-sync GET into an explicit
mutation with personal fields outside the URL, coordinating both services.

**Method authorization (F): the heading is misleading.**
[ClaimsHeaderSecurityConfig](../../../service-common/service-web/src/main/java/org/budgetanalyzer/service/security/ClaimsHeaderSecurityConfig.java)
enables `@EnableMethodSecurity`; annotations are enforced. The missing control
is a guarantee that every new business endpoint declares an authorization
policy. A coverage rule with explicit infrastructure/internal exceptions is
useful; an annotation count alone is not proof of data ownership enforcement.

**HSTS (G): agree with consistent edge coverage, not categorical absence or
automatic preload.** Session Gateway leaves Spring Security's default response
headers enabled, and the auth route sets forwarded HTTPS, so HSTS on that lane
is expected but was not observed live here. NGINX/static/error paths still need
a consistent policy. `includeSubDomains` requires an intentional domain policy;
preloading is not a default prerequisite and does not happen merely by adding
the directive. Ordinary HSTS also does not protect a first contact before the
browser has learned the policy.
[Spring WebFlux headers](https://docs.spring.io/spring-security/reference/reactive/exploits/headers.html),
[HSTS deployment guidance](https://hstspreload.org/)

**RabbitMQ (B): agree on community support expiry.** The checked-in image is on
3.13; the vendor records community support ending on 30 September 2024 while
listing separate commercial support. This is maintenance debt, not proof of a
particular exploitable CVE. I did not independently identify the pinned image's
patch version. Select a supported target and its documented upgrade path,
including data/queue compatibility and ARM64 support. The existence of a
quarterly-review instruction does not prove a review actually ran and missed it.
[RabbitMQ release information](https://www.rabbitmq.com/release-information)

The smaller forwarded-header, database-role/TLS, CSP, zero-permission spoofing
test, and explicit mesh-deny suggestions are reasonable hardening work. They
should retain their individual evidence and prerequisites; a missing regression
test is not itself proof of an exploitable bypass.

## Architectural recommendations I would retain or change

| Recommendation | My assessment |
| --- | --- |
| Retain opaque server-side sessions | **Agree.** Moving bearer tokens into browser JavaScript would not solve these findings. |
| Keep the topology for this educational project | **Agree.** Both hop costs and configuration boundaries matter. Neither review establishes a need for a rewrite. |
| Define and test one edge contract | **Strongly agree.** Test boundaries through the actual request chain, including errors and empty claims. Generating route files is optional; reducing inconsistent ownership is the objective. |
| Separate Redis auth state from caches | **Support as a deliberate deployment choice.** It improves memory/failure and trust isolation. It does not replace token hashing, auth admission limits, or least privilege. |
| Adopt signed identity before real data | **Disagree with the unconditional prerequisite.** It can reduce trust in intermediate proxies, but needs a threat model and a coordinated design. |
| Move all internal APIs to separate ports | **Defer a blanket requirement.** A separate listener helps only if internal routes are absent from the public listener and policy enforces that separation. First constrain callers/paths and prove normalization behavior. |
| Move PDF parsing to a worker | **Conditional.** Start with resource budgets and measurements; use isolation when required to protect API availability. |
| Switch egress to `ISTIO_MUTUAL` | **Agree with the identity goal; reject a one-setting fix.** The current passthrough listener relies on external SNI. Mesh TLS requires coordinated listener/routing and authorization changes. |
| Add hosted recovery, alerting, and vulnerability response | **Agree before hosted use.** These are explicit future deployment prerequisites, not evidence of a currently failing production deployment. |

For signed identity, only ext-authz should hold the signing private key if
backends are to be unable to mint assertions. Shared verification secrets would
not establish that property. Include audience, short lifetime, key rotation,
and replay considerations. A compromised intermediary can still replay
assertions it sees or alter requests, and Session Gateway remains an identity
authority through its Redis writes. The existing
[claims-header options document](../../../service-common/docs/plans/claims-header-trust-hardening-options.md)
correctly leaves this as a decision with costs and explicit residual threats.

The egress qualification is already documented in
[egress-routing.yaml](../../kubernetes/istio/egress-routing.yaml): wrapping the
current passthrough connection hides the external SNI and causes connection
resets. Preserve external TLS validation while redesigning the mesh wrapper;
do not treat the existing encrypted passthrough as plaintext transport.

Both reviews are right that Redis Cluster is not a drop-in HA replacement for
the multi-key session/index scripts. Nonsharded failover is a simpler candidate,
but recovery must also address stale sessions and restored revocations.

## Documentation and work order

I agree with reconciling the first review's five documentation discrepancies:
absolute expiry, CSRF tokens, cookie Max-Age, Redis topology/eviction, and
guaranteed outbox delivery. I also agree with removing the communication guide's
blanket rejection of synchronous calls and its recommendation to read another
service's storage. The currency service explicitly uses import reconciliation
after failed publication; durable recorded intent is not guaranteed delivery.
[Messaging recovery contract](../../../currency-service/src/main/java/org/budgetanalyzer/currency/messaging/listener/MessagingEventListener.java)

Qualify revocation language precisely: deleting an existing session prevents
later lookups from finding it, but does not undo already-authorized requests or
guarantee account-wide containment across concurrent issuance/refresh. Update
canonical owners according to [OWNERSHIP.md](../OWNERSHIP.md), leave ADRs intact,
and use portable links. This research document does not change those contracts.

I would organize the work in this order, without letting repository ownership
push the most important cross-repository fixes to the end:

1. **Close credential and routing boundaries:** OAuth browser binding, Redis
   token persistence/enumeration, Redis administrative privilege, backend cookie
   stripping, and public/internal route policies plus encoded-path verification.
2. **Make failure behavior and data handling reliable:** bounded authorization
   and login deadlines, ingress error semantics, probe separation, safe logging,
   Redis memory/admission policy, and supported RabbitMQ inputs.
3. **Complete browser/session hardening:** absolute lifetime, auth/API CSRF
   policy, cookie migration, consistent response/forwarded headers, and measured
   PDF limits. Include duplicate-cookie and zero-permission identity tests.
4. **Choose hosted operating requirements:** recovery objectives, restore and
   failover tests, alert delivery, vulnerability response policy, and the
   justified Redis, signing, listener, egress, and parser-isolation designs.

For each implementation, require focused evidence of the changed behavior.
Static manifests and offline renders remain useful, but cannot prove browser
binding, normalized routing, credential stripping, or resource exhaustion
handling. Service implementation changes belong in their owning repository
contexts; orchestration should not compensate for service-owned defects.

## Evidence and limits

- Read both requested reviews, canonical architecture/ownership documents,
  relevant manifests/routing/verifiers, and sibling implementation/configuration.
- Used delegated read-only exploration and one disposable Redis reproduction
  with networking disabled, no mounts, and synthetic credentials/data. No real
  sessions were accessed and no cluster resources were changed.
- Consulted primary upstream documentation/source for protocol behavior,
  dependency defaults, PDFBox memory behavior, and RabbitMQ support status.
- Did not run live application flows, malicious PDFs, exhaustion tests, or the
  repository's static/shared-session/production-reference suites. Earlier
  reviews' passing results are not independent verification by this assessment.
- Current sibling source is not proof of the contents of historical pinned
  production-reference images. No hosted production environment is configured.
- The separately present
  [third assessment](application-architecture-security-review-third-assessment-2026-11-01.md)
  appeared while this session was paused and was preserved. Its reported runtime
  tests are not counted as tests performed for this document.
