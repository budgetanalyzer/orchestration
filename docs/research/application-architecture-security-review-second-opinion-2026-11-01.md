## Bottom line

Keep the architecture. The foundation is right: server-side opaque sessions, an edge authorizer that fails closed, default-deny NetworkPolicies, strict mutual TLS with per-workload AuthorizationPolicies, digest-pinned images, and Kyverno policies in Enforce mode. I agree with the existing review's overall conclusion and with all eight of its findings in direction. But I'd re-rank several, and it missed the most serious problem I found:

- **Missed, High:** currency-service's Redis user is allowed `KEYS` and `SCAN`. Redis key restrictions don't filter what those commands return, and each session's key name is the raw `BA_SESSION` cookie value. So if currency-service is compromised, it can list every user's live login token, admins included. I reproduced this against the exact pinned Redis image. The credential-isolation verifier only tests `GET`, so it reports this boundary as intact.
- **Over-rated:** Session Gateway's `+@all` Redis permission. The review says High; I'd say Medium. Fix it, but Session Gateway can already create any session it likes. The extra harm is outages and tampering, not forged identity.
- **Under-specified:** the OAuth fix needs a correlation cookie that is `SameSite=Lax` and uses the `__Host-` prefix. For CSRF, checking `Sec-Fetch-Site`/`Origin` in ext-authz should be the main control, not an add-on to CSRF tokens.
- **Missed, Medium:**
  - Istio's ext_authz defaults (403 on failure, 600 s timeout) contradict the documented "fail closed with 503" contract.
  - RabbitMQ 3.13.7 is end-of-life.
  - Anonymous login requests can fill Redis until it is killed for running out of memory.
  - A crafted PDF upload can crash transaction-service the same way.
  - Deleting a user neither revokes their sessions nor stops them signing up again.

In sibling-repo paths below, `…` stands for `src/main/java/org/budgetanalyzer/<service>`.

## Prioritized hardening list

| # | Change | Severity | Owner |
|---|---|---|---|
| 1 | Stop session tokens leaking through Redis key names: remove `KEYS`/`SCAN` from currency-service, store sessions under `SHA-256(token)`, add tests that `KEYS`/`SCAN` are denied | High | orchestration, currency-service, session-gateway, ext-authz |
| 2 | Bind OAuth callbacks to the browser that started login (`__Host-` Lax correlation cookie, one-step consume, cap `returnUrl` when login starts); rename the cookie to `__Host-BA_SESSION`; reject requests carrying two session cookies | Medium–High | session-gateway, ext-authz |
| 3 | Strip `Cookie` and `Authorization` in `nginx/includes/backend-headers.conf` | Medium | orchestration (2 lines) |
| 4 | ext_authz `statusOnError: "503"` and a ~1 s `timeout`; separate liveness and readiness probes; no process exit when Redis is down | Medium | orchestration, ext-authz, service-common |
| 5 | Redis: explicit command list for Session Gateway, `ACL DRYRUN` tests that dangerous commands are denied, `maxmemory` + `noeviction`, shorter OAuth-state lifetime; ideally separate auth data from cache | Medium | orchestration, session-gateway |
| 6 | HTTP body logging and TRACE off by default; structured audit events | Medium (High with real data) | services |
| 7 | Absolute session lifetime, enforced by Session Gateway and re-checked by ext-authz | Medium | session-gateway, ext-authz |
| 8 | Upgrade RabbitMQ off 3.13.7 | Medium | orchestration |
| 9 | Bound PDF parsing, or move it into an isolated worker | Medium | transaction-service |
| 10 | `Sec-Fetch-Site`/`Origin` checks on state-changing requests; HSTS at the ingress | Low–Medium | ext-authz, session-gateway, orchestration |
| 11 | Deleting a user revokes their sessions and blocks re-signup (or documents that re-signup is allowed) | Low–Medium | permission-service |
| 12 | Limit the ingress → Session Gateway policy to the auth paths; reject `;` at the ingress; add a test that pins Spring's `StrictHttpFirewall` | Low (latent) | orchestration, service-common |

## Verdicts on the existing review

**1. OAuth callback not bound to the browser: Agree.** I'd put it at Medium–High but schedule it as High.

Verified:
- The stored login request is found by `state` alone (`../session-gateway/…/security/RedisAuthorizationRequestRepository.java:155`).
- Consuming it is a read followed by a separate delete (`:168-190`).
- `SecurityConfigIntegrationTest.java:107-130` completes a login callback with no cookie at all.

The root cause is worth stating in a reference architecture. Spring's default implementation ties the login request to the browser through the session cookie; replacing it with a Redis store keyed only by `state` dropped that tie. Real-world impact is a little below High, because the victim has to keep working while the UI shows the attacker's profile. But RFC 9700 makes this protection mandatory, and the fix is small.

What the review leaves open:
- The correlation cookie must be `SameSite=Lax`. The callback from Auth0 is a cross-site navigation, so a `Strict` cookie wouldn't be sent and every login would fail.
- It must be `__Host-` prefixed. Otherwise a sibling subdomain can plant the attacker's own correlation cookie in the victim's browser, and the attack still works.
- Store only a hash of the cookie value in Redis, compare in constant time, and clear the cookie after the callback.
- Consume the request in one atomic step: a Lua script, `MULTI`, or a single string value read with `GETDEL`.
- Validate and cap `returnUrl` when login starts (`../session-gateway/…/config/OAuth2ClientConfig.java:200-215`). Today it is stored unchecked and only validated at the callback (`OAuth2CallbackRedirectResolver.java:64-66`).

**2. Session Gateway `+@all`: Agree with the fix, disagree with High.**

What I reproduced:
- `ACL DRYRUN` shows Session Gateway can run `FLUSHALL`, `CONFIG SET`, `SHUTDOWN` and `REPLICAOF`.
- `ACL SETUSER session-gateway ~*` succeeds, after which it can read `currency-service:*` keys.

Session Gateway can already write a session with any permissions, so `+@all` doesn't change who can forge an identity. What it adds:
- outages, for example `FLUSHALL`, or locking out the `ext-authz` Redis user, which fails every `/api/*` request;
- tampering with other Redis users;
- writing false exchange rates into the currency cache.

Two things keep it below High:
- Redis 7.4.11's defaults refuse `CONFIG SET dir/dbfilename`, which closes the classic file-write attack. I confirmed this in a throwaway container.
- The cache only deserializes a restricted set of types (`CacheConfig.java:73-86`), so a remote-code-execution path through the cache is unlikely.

Missed by the review:
- `scripts/smoketest/verify-session-architecture.sh:562-566` asserts the exact `+@all` line. The guardrail locks the over-privilege in place, and a passing static suite partly confirms the problem. The fix must change it.
- Drop `&*` (pub/sub access) unless it is actually used.
- Build the command list from `ACL LOG` during a test run, because the Redis client sends `HELLO`/`CLIENT` commands of its own.

The bigger ACL hole is finding A below.

**3. Browser cookies forwarded to backends: Agree, but Medium rather than Medium–High.** `nginx/includes/backend-headers.conf:28-38` never clears `Cookie` or `Authorization`. I rate it lower because service-common already masks both in logs, so stealing them requires compromising a backend first. It still matters: combined with finding A, any compromised backend can impersonate everyone who calls it.

The fix is `proxy_set_header Cookie "";` and `proxy_set_header Authorization "";` (NGINX drops headers set to an empty value). ext_authz still sees the cookie, because it runs at the ingress before NGINX.

**4. No absolute session lifetime: Agree, Medium, and the gap is wider than the review says.** ADR 007 says a user blocked at Auth0 but not deactivated locally keeps their session "until Redis TTL expiry". There are no refresh tokens and each heartbeat pushes the expiry forward, so in practice that means forever. Auth0 blocks, password resets and MFA changes never reach a live session; only an absolute cap forces the user back through Auth0.

Enforce the cap when renewing (session creation time + maximum). Also check it in ext-authz, which already reads the whole session record.

**5. CSRF: Partially agree.**

The facts are right:
- CSRF protection is disabled (`../session-gateway/…/config/SecurityConfig.java:122`).
- ext_authz is only given the `cookie` header (`kubernetes/istio/istiod-values.yaml:25-26`).
- SameSite does not stop requests from sibling subdomains of the same site.

I disagree with leading on CSRF tokens. This is a same-origin single-page app behind one authorizer, so the cheaper and stronger control is in ext-authz:
- For state-changing requests, require `Sec-Fetch-Site: same-origin`.
- If the browser doesn't send it, fall back to an exact `Origin` match.
- This means adding `origin` and `sec-fetch-site` to `includeRequestHeadersInCheck`.

Today's exposure is narrow anyway. JSON requests from another origin need a CORS preflight, which fails; only form, multipart and plain-text bodies (such as statement upload) avoid it.

The concrete risk the review doesn't describe is cookie planting:
- A sibling subdomain, or a network attacker before the victim's first login (possible because there's no HSTS), sets `BA_SESSION=<attacker session>; Path=/api`.
- Browsers send cookies with longer paths first, and both ext-authz and Session Gateway use the first `BA_SESSION` they see (`SessionCookieHelper.java:48`).
- The victim's API writes then land in the attacker's account, while `/auth/v1/session` still shows the victim's own name.

So `__Host-BA_SESSION` should be required, not just "considered", and requests carrying two session cookies should be rejected. Switching logout and heartbeat from GET to POST is fine hygiene but low value: a forged request only logs the user out or extends their session.

**6. Sensitive logging: Agree on bodies (Medium, High with real data). The client-IP issue is Low.**

Body logging affects three services, not two:
- transaction-service `application.yml:9,58-62`
- permission-service `:9,52-56`
- session-gateway `:14,105-109`

All three set `org.budgetanalyzer: TRACE` and log request and response bodies, and the `kubernetes` profile doesn't turn this off. The log sanitizer only masks credential-like field names, so financial data and personal details go straight into the logs. Make "off" the default and use a debug profile to switch it on.

On client IPs, NGINX's `real_ip` setup (`nginx/nginx.k8s.conf:53-55`) makes `X-Real-IP` trustworthy. But `ContentLoggingUtil.java:182-208` logs the first `X-Forwarded-For` entry, which the client controls. `verify-istio-ingress.sh:812` even shows a forged first entry surviving. Use `X-Real-IP`.

**7. Health probes: Agree, Medium, and there's a related config defect the review missed.**

Agree with the fix:
- Use Spring's separate liveness and readiness health groups.
- Give ext-authz separate `/livez` and `/readyz` endpoints.
- Stop ext-authz exiting after 10 failed Redis retries at startup.

The missed defect: the Istio ext_authz provider only sets `failOpen: false` (`kubernetes/istio/istiod-values.yaml:27`). Istio's defaults for the rest are `statusOnError: 403` and `timeout: 600s`. As a result:
- When ext-authz is unreachable, browsers get an empty 403. The documented contract (`docs/architecture/session-edge-authorization-pattern.md:239`) says fail closed with a JSON 503, and the frontend treats a 403 as an ordinary error, not an outage.
- When ext-authz hangs, ingress requests can wait up to 10 minutes.

Set `statusOnError: "503"` and a timeout of about 1 s. Add read/write timeouts to ext-authz's Go HTTP server while you're there.

**8. Redis memory: Agree, Medium, and an anonymous user can trigger it.** The pod's memory limit is 256Mi (`kubernetes/infrastructure/redis/statefulset.yaml:93`) and Redis has no `maxmemory` or eviction policy (`start-redis.sh:16-25`).

How an anonymous user fills it:
- Each login start stores an OAuth-state record for 900 s.
- `returnUrl` is not length-capped, so each record can be about 4 KB.
- The rate limit (1/s with a burst of 25, per source address) still allows about 925 live records, roughly 4 MB, per address.
- Around 50–60 addresses could get Redis killed for exceeding its memory limit; it then replays its append-only log on restart and may get killed again in a loop. Fewer addresses would be needed if the edge is reachable over IPv6, since the limiter keys on the full address.

Fix:
- Set `maxmemory` to about 70–75% of the pod limit, with `noeviction` for auth data.
- Cap `returnUrl`.
- Cut the OAuth-state lifetime to 5–10 minutes.
- Give the cache its own Redis instance with `allkeys-lru`.

I strongly agree with the review's warning against `allkeys-lru` for sessions: evicting the `user_sessions:*` index would silently break "log out all sessions" for that user.

### Architecture and operations points

- **Keep server-side sessions: Agree.** With hashed keys it becomes a textbook opaque-token design.
- **Cost of the multi-hop topology: Partially agree.** The cost isn't the number of hops; it's the seams between them. Most of these findings sit between components that each look correct on their own:
  - Istio's error status vs the ext-authz contract;
  - NGINX forwarding a cookie only ext_authz needs;
  - both auth components picking the first of two cookies;
  - service-common trusting a client IP header that the ingress only appends to;
  - Session Gateway trusting `X-Forwarded-Host`, which nothing strips.

  Treat the edge contract as one specification with tests that cross these layers, and generate both NGINX route files from a single source. Agree that a rewrite isn't warranted.
- **Narrow mesh permissions: Agree, with two caveats.**
  - The review holds up the narrow permission-service → Session Gateway rule as the model. But the same policy's first rule lets the ingress reach every path and method on Session Gateway's single port, 8081 (`kubernetes/istio/authorization-policies.yaml:189-199`). So at the mesh layer, the internet-facing ingress can reach `DELETE /internal/v1/sessions/users/{userId}`, which Spring allows without login (`SecurityConfig.java:85-86`). Only the ingress route prefixes keep it out. Restrict that rule to the auth paths.
  - Path-based rules don't catch every path trick. Envoy and NGINX don't treat `..;` as "go up one level", but Tomcat does. So a path that looks like a public permission-service route to the proxies can land on its internal endpoints, which also require no login. Today the only thing stopping this is Spring's default `StrictHttpFirewall`, and no test pins that default. Add the test in service-common and reject `;` at the ingress.
- **Egress: Agree, Low.** The root cause is `tls.mode: DISABLE` on the hop to the egress gateway (`kubernetes/istio/egress-routing.yaml:43`). The gateway can't tell which service is calling, so either service can reach either external host. Switch to mesh mTLS (`ISTIO_MUTUAL`) and add an egress policy keyed on caller identity and destination host.
- **Vulnerability scans don't block releases: Partially agree.** Collecting evidence without gating is a reasonable, documented choice for a repo with no production, and "gate before hosted use" is right. But the quarterly end-of-life review (`docs/dependency-automation.md:537-540`) lists RabbitMQ and still missed that 3.13 lost community support in September 2024. Automate end-of-life detection.
- **Deployment scope, disaster recovery, observability: Agree.** `deploy/README.md:83-93` honestly states its scope; that isn't a defect. I'd add alerts for Redis memory and rejected writes, and for ext_authz error rate and latency.
- **Redis high availability: Agree.** More precisely, `delete-user-sessions.lua:9` builds key names inside the script instead of declaring them up front, which Redis Cluster forbids. Use Sentinel or a managed primary/replica; session data doesn't need sharding.
- **Communication guide: Agree, and it's worse than the review says.** `docs/architecture/service-communication.md:199-222` tells readers to "read from shared database or Redis", which contradicts the per-service databases and Redis permissions the platform enforces.
- **Documentation table: Agree with all five rows.** My additions are under "Documentation corrections".

## New findings (not in the review)

**A. High: currency-service can list every live session token.**
- Session keys are `session:{cookie value}` (`../ext-authz/session.go:101`, `../session-gateway/…/session/SessionWriter.java:76`).
- currency-service has `+keys +scan` (`kubernetes/infrastructure/redis/start-redis.sh:11`). It needs them because Spring's "clear the whole cache" eviction (`ExchangeRateImportService.java:92,125,245`) uses `KEYS` by default.
- Repro: as `currency-service`, `KEYS session:*` and `SCAN 0 MATCH session:*` both returned the session key, while `GET` on that key returned `NOPERM`.
- So the lowest-trust Redis user can collect everyone's tokens and send them out through its own API responses.
- The same tokens sit in Redis's append-only file, its persistent volume and any backups. Operators see them too: `scripts/ops/redis-browse.sh:37` uses `KEYS`.
- `verify-credential-isolation.sh:574` only tests `GET`.

Fix:
- Store sessions under a hash of the token. This is the root-cause fix.
- Replace the clear-everything eviction with a versioned cache key prefix, then remove `+keys +scan`. Switching the eviction to `SCAN` doesn't help, because `SCAN` leaks the same names.
- Add tests that `KEYS` and `SCAN` are denied.

**B. Medium: RabbitMQ 3.13.7 is end-of-life.**
- The pinned `3.13-management` image runs 3.13.7.
- Community support ended in September 2024, and later 3.13 patches are only available commercially.
- It's internal-only (TLS on port 5671, locked down by NetworkPolicy), hence Medium.
- Before upgrading to 4.x, enable all stable feature flags on 3.13 and check queue types, because 4.x dropped classic mirrored queues.

**C. Medium: a PDF upload can crash transaction-service (requires login).**
- Three extractors load the whole PDF into memory with `Loader.loadPDF(byte[])`: `PdfTextExtractionService.java:47`, `CapitalOneCreditMonthlyStatementExtractor.java:160` and `BangkokBankStatementPdfExtractor.java:110`.
- Uploads can be 25 MB, read fully via `getBytes()`, and the pod limit is 512Mi.
- One crafted PDF, or a few uploads at once, can take the transaction API down for every user.

Fix:
- Use PDFBox's temp-file stream cache.
- Cap page count and extracted text size.
- Limit concurrent parses per user.
- Longer term, parse in an isolated worker.

**D. Low–Medium: deleting a user is weaker than deactivating them.**
- `UserService.deleteUser` (`../permission-service/…/service/UserService.java:164-171`) doesn't revoke sessions, unlike deactivation. The user's cached permissions keep working until the next heartbeat refresh comes back "not found" (`PermissionService.java:58-62`).
- `UserSyncService.syncUser` (`:62-70`) only blocks deactivated users, so a deleted user who logs in again gets a brand-new account.

**E. Low–Medium: the login-time permission call has no timeout.**
- The HTTP client in `WebClientConfig.java:17` has no connect or response timeouts.
- `fetchPermissions` (`PermissionServiceClient.java:47-59`) has no `.timeout()`. Only `fetchAuthorization` has one (`:125`). A slow permission-service therefore hangs logins.
- The same call is a GET that creates or updates the user and puts their email and display name in the query string, where they can end up in access logs and traces. Make it a POST.

**F. Low–Medium (latent): nothing enforces `@PreAuthorize`.**
- The shared security config only requires `authenticated()`, so a new endpoint without an annotation is open to any signed-in user.
- Every endpoint is covered today: 31/31 in transaction-service, 6/6 in currency-service, and the 3 public ones in permission-service.
- Add an ArchUnit or reflection test so it stays that way.

**G. Low–Medium: no HSTS, although the docs say there is.** Set it at the ingress so the Session Gateway path, which bypasses NGINX, is covered too. Use `includeSubDomains`, plus `preload` in production. HSTS is also what stops a network attacker from planting cookies (point 5).

**H. Low: smaller items.**
- Session Gateway trusts `Forwarded`/`X-Forwarded-Host` (`../session-gateway/src/main/resources/application.yml:8`) when building the OAuth `redirect_uri`. Auth0's list of allowed callback URLs is the only safeguard. Configure a fixed redirect URI and strip those headers at the ingress.
- No test covers forged identity headers for a user with no permissions. ext-authz sends `X-Permissions` even when it's empty (`../ext-authz/http_server.go:117`), and NGINX drops empty headers. `verify-istio-ingress.sh:1033-1083` only covers a user who has permissions.
- PostgreSQL only requires TLS on the client side: `statefulset.yaml:71` produces `host` rules, not `hostssl`. Each service's runtime database role also owns its database and can change the schema; use a separate migration role.
- `X-Forwarded-Proto` tells backends the request was `http` (`backend-headers.conf:33`).
- `RedirectUrlValidator.java:49-82` doesn't reject `\` or control characters; only an exception elsewhere hides this. Align it with the frontend's `isSafeReturnUrl`.
- The Content-Security-Policy has no `form-action`, and `X-XSS-Protection` is deprecated.
- `LoginPage.tsx:30` doesn't validate `returnUrl`. It's not exploitable, because the browser refuses cross-origin history changes.
- Workloads in the `default` namespace are deny-by-default only because of the selector-less `envoy-metrics-prometheus-policy` (`kubernetes/istio/authorization-policies.yaml:120-133`). Add an explicit deny-all baseline policy so removing that metrics rule can't open a workload.

## Architectural changes I'd make

1. **Split Redis by trust level.**
   - A `redis-auth` instance holds sessions, the session index and OAuth state, with `noeviction`. Only Session Gateway writes to it; ext-authz only reads.
   - A `redis-cache` instance holds the currency cache, with `allkeys-lru`, and currency-service has no network path to `redis-auth`.
   - Redis holds authorization state: ext-authz forwards whatever permissions the session record contains. That deserves its own trust and failure boundary.
   - This one move removes finding A, the shared memory budget and most of the ACL complexity.
2. **Store session tokens hashed**, both in session keys and in the `user_sessions:*` index.
3. **Adopt service-common's signed identity context** (`../service-common/docs/plans/claims-header-trust-hardening-options.md`, currently "Decision pending") before handling real data. Today anything between the ingress and a backend that can set headers can impersonate any user, and NGINX is the obvious candidate. Short-lived signed tokens issued by ext-authz would mean only ext-authz can vouch for identity.
4. **Serve internal APIs on separate ports, not under path prefixes.** Port-based policies can't be fooled by path tricks like `..;`.
5. **Define the edge contract once and test it across layers.** Cover two-cookie requests, cookie stripping, error status, forwarded headers, forged headers for users with no permissions, and `KEYS`/`SCAN` denial.
6. **Run untrusted file parsing outside the transaction API.**

## Documentation corrections

Beyond the review's table:
- `docs/architecture/security-architecture.md:493` claims HSTS.
- `security-architecture.md:494` and `:754` claim instant revocation, which contradicts the race documented at `session-edge-authorization-pattern.md:199-205`.
- `security-architecture.md:145-146` (web application firewall integration, circuit breaking/retry) and `:176`, `:451` (audit logging): I found no implementation of any of these.
- `security-architecture.md:94-95` is a duplicated bullet.
- `docs/architecture/system-overview.md:203` says Spring Boot 3.x; the services use 4.1.2.
- `system-overview.md:248` repeats the claim that the transactional outbox guarantees delivery.
- ADR 007's TTL statement needs qualifying in the owning architecture doc. I did not edit the ADR.

The review document's own links are absolute `/srv/budget-analyzer/worktrees/...` paths. They break for anyone else and violate this repo's path-portability rule.

## Scope and limits

- This was a source and configuration review across orchestration and the sibling repos, plus two throwaway Redis containers run from the pinned image with networking disabled. I ran no tests against the live cluster and no penetration test.
- I did not re-run the static verifiers, so the review's "verification passed" claims are unchecked.
- Cookie planting, Redis memory exhaustion, the PDF crash and the `..;` path trick are reasoned from code and specifications, not demonstrated end to end.
- I changed no repository files.

Sources:
- [Redis ACL documentation](https://redis.io/docs/latest/operate/oss_and_stack/management/security/acl/)
- [redis-db: ACL key patterns and KEYS/SCAN](https://groups.google.com/g/redis-db/c/h6lg3qgBy7s)
- [RabbitMQ release information](https://www.rabbitmq.com/release-information)
- [RabbitMQ community support policy](https://www.rabbitmq.com/blog/2024/05/31/new-community-support-policy)
- [RabbitMQ 3.13.8 release (commercial)](https://www.rabbitmq.com/blog/2025/02/07/rabbitmq-3.13.8-is-released)
- [Istio MeshConfig reference (envoyExtAuthzHttp defaults)](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/)
