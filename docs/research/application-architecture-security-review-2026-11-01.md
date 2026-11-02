I would keep the core architecture, but address several concrete security gaps before trusting it with sensitive financial data. The most significant are **OAuth login state without browser binding, excessive Redis privileges, and unnecessary propagation of session cookies into backend services**.

I reviewed the architecture documents, deployment manifests, routing, security policies, and relevant sibling-service implementations. The application and Tilt were stopped, so findings below are based on configuration and source inspection—not an end-to-end penetration test.

The existing foundation is substantial: fail-closed authorization, server-side sessions, PKCE, workload identities, STRICT mesh mTLS, default-deny network policies, separate database credentials, hardened containers, digest pinning, and internal-only observability. Transaction and saved-view implementations also contain ownership checks; I found no basis for claiming user isolation is universally missing.

The findings below are ordered roughly by remediation priority.

1. **High: OAuth callbacks are not bound to the browser that initiated login.**

   The [authorization-request repository](/srv/budget-analyzer/worktrees/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/security/RedisAuthorizationRequestRepository.java:155) retrieves the stored login transaction using only the callback’s `state` parameter. It does not check a browser-specific correlation cookie or session. The existing [integration test](/srv/budget-analyzer/worktrees/session-gateway/src/test/java/org/budgetanalyzer/sessiongateway/config/SecurityConfigIntegrationTest.java:107) explicitly completes login without sending such a cookie.

   This creates a login-CSRF risk: an attacker can initiate authentication for their own account and induce another browser to complete that transaction. The victim could then import financial data into the attacker’s account. PKCE and OIDC nonce validation do not supply the missing browser binding here because the server retrieves those values from the same transferable transaction.

   Bind each authorization transaction to a short-lived browser correlation secret, validate it on callback, and consume the transaction atomically. A dedicated Secure, HttpOnly correlation cookie with appropriate callback-compatible SameSite behavior is a conventional approach. Add a negative test where browser B attempts to complete browser A’s login.

   Owner: `session-gateway`, with orchestration documenting and verifying the contract.

2. **High: the Session Gateway Redis identity has administrative privileges.**

   [Redis ACL bootstrap](/srv/budget-analyzer/worktrees/orchestration/kubernetes/infrastructure/redis/start-redis.sh:9) grants `session-gateway` `+@all`.

   Key-prefix restrictions do not constrain commands that operate on the Redis server or its ACLs. This grants capabilities such as ACL administration and database-wide flushing, undermining the intended separation between application identities and `redis-ops`.

   Replace `+@all` with an explicit command allowlist covering the actual session, index, OAuth-state, and Lua operations. Keep administrative commands exclusive to the operator identity.

   The current credential-isolation verifier checks cross-prefix `GET` denial, but that does not establish administrative isolation. Add negative checks for privileged commands, preferably using Redis ACL dry-run facilities rather than executing destructive operations.

   Owner: orchestration.

3. **Medium–high: backend services unnecessarily receive browser session credentials.**

   The shared [backend header configuration](/srv/budget-analyzer/worktrees/orchestration/nginx/includes/backend-headers.conf:28) forwards identity claims but does not remove `Cookie` or `Authorization`. NGINX retains its default forwarding of original request headers.

   Consequently, backend services receive the reusable `BA_SESSION` credential even though they authenticate through trusted claims. A backend compromise could expose sessions belonging to its callers and increase the impact beyond that service’s own data.

   `headersToUpstreamOnAllow` only limits which authorization-response headers Envoy copies; it does not remove original browser headers.

   Strip browser cookies and unused authorization headers before API requests reach business services. Keep cookies on the Session Gateway auth lane. Verify the boundary with a backend that records header names without recording credential values.

   Owner: orchestration.

4. **Medium: sessions have sliding expiration but no enforced absolute lifetime.**

   [Session renewal](/srv/budget-analyzer/worktrees/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/session/SessionWriter.java:118) sets expiration to the current time plus the TTL. It does not cap renewal against `created_at`.

   A stolen session can therefore be renewed repeatedly while the account remains active. Frontend activity detection is a usability mechanism; a client holding the cookie can call the heartbeat directly.

   Introduce a server-enforced absolute lifetime, with shorter limits or reauthentication for privileged operations. Choose the duration according to the application’s risk and usability requirements. Preserve permission refresh on heartbeat—it is a useful existing control.

   Separately, the documented revocation race is real and already acknowledged in the [session contract](/srv/budget-analyzer/worktrees/orchestration/docs/architecture/session-edge-authorization-pattern.md:199). If immediate account-wide containment becomes a requirement, use an authoritative account/session generation checked during authorization and session issuance. Periodic refresh alone cannot provide that guarantee.

   Owner: `session-gateway` and potentially `ext-authz`/`permission-service`.

5. **Medium: CSRF protection relies primarily on SameSite, and state-changing endpoints use GET.**

   [Session Gateway disables CSRF](/srv/budget-analyzer/worktrees/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/config/SecurityConfig.java:122), and the edge authorization service does not validate a CSRF token or request origin. Both [session renewal](/srv/budget-analyzer/worktrees/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/api/SessionController.java:109) and [logout](/srv/budget-analyzer/worktrees/session-gateway/src/main/java/org/budgetanalyzer/sessiongateway/api/LogoutController.java:84) use GET.

   `SameSite=Strict` provides meaningful protection, so this is not a claim that arbitrary cross-site requests currently work. However, SameSite is not an origin boundary: a compromised sibling origin can still be same-site.

   Establish an explicit browser CSRF policy at the edge/auth boundary: tokens for unsafe requests, exact-origin validation where applicable, and Fetch Metadata as supplementary protection. Move session renewal and logout mutations to POST. Consider a `__Host-` session-cookie name to enforce host-only cookie constraints.

   Backend CSRF middleware need not be enabled independently if the browser boundary reliably owns this control.

6. **Medium–high for real financial data: application logging captures sensitive payloads.**

   [Transaction-service configuration](/srv/budget-analyzer/worktrees/transaction-service/src/main/resources/application.yml:58) enables request and response body logging, with application logging at TRACE. Permission-service has similar settings.

   The shared [body sanitizer](/srv/budget-analyzer/worktrees/service-common/service-core/src/main/java/org/budgetanalyzer/core/logging/HttpBodyLogSanitizer.java:30) masks credential-like fields, but financial amounts, descriptions, account identifiers, names, and emails are not covered by that list. Sensitive payloads can become a second data store in operational logs.

   Disable body logging by default outside explicitly selected synthetic-data debugging. Emit structured audit events containing the actor, operation, resource identifier, outcome, and correlation ID, with controlled retention and access.

   There is also an attribution inconsistency: NGINX derives a trusted client address, but the [backend logging helper](/srv/budget-analyzer/worktrees/service-common/service-web/src/main/java/org/budgetanalyzer/service/servlet/http/ContentLoggingUtil.java:197) selects the first `X-Forwarded-For` value, which can be caller-supplied. Normalize the downstream forwarding contract and consume only the trusted value. This affects audit accuracy, not the ingress limiter’s address selection.

7. **Medium: dependency failures can trigger unnecessary application restarts.**

   Spring workloads use aggregate `/actuator/health` endpoints for liveness and readiness. More conclusively, `ext-authz` [uses `/healthz` for both probes](/srv/budget-analyzer/worktrees/orchestration/kubernetes/services/ext-authz/deployment.yaml:81), while that endpoint [fails when Redis cannot be pinged](/srv/budget-analyzer/worktrees/ext-authz/main.go:36).

   A Redis outage therefore causes healthy authorization processes to restart. Across the stack, dependency-related restarts can amplify an outage through connection churn and repeated initialization.

   Separate the contracts:

   - Liveness checks whether the process can make progress.
   - Readiness checks whether it can serve its intended traffic.
   - Startup allows initialization to finish.

   Use Spring’s dedicated health groups and a separate process-liveness endpoint for `ext-authz`. Validate by interrupting a dependency in a disposable environment and confirming that callers become unavailable without repeatedly restarting.

8. **Medium: Redis combines authentication and cache workloads without an explicit memory policy.**

   Session data, OAuth transactions, session indexes, and currency caches share one Redis instance. Its [container memory limit is 256 MiB](/srv/budget-analyzer/worktrees/orchestration/kubernetes/infrastructure/redis/statefulset.yaml:92), while the [startup command](/srv/budget-analyzer/worktrees/orchestration/kubernetes/infrastructure/redis/start-redis.sh:16) sets neither `maxmemory` nor an eviction policy.

   Cache growth or accumulated state can exhaust memory and interrupt authentication. AOF persistence does not prevent that failure.

   Define a memory budget with headroom for Redis overhead and persistence work. Prefer separating security state from disposable caches when deployment requirements justify it; logical Redis databases do not isolate memory or failures.

   Do not adopt the documented `allkeys-lru` suggestion blindly for session state: independently evicting session indexes and hashes can weaken indexed bulk revocation.

Beyond those fixes, I would adjust several architectural and operational choices.

- **Retain the server-side session model.** It is appropriate for this browser application. Moving tokens into browser JavaScript would not resolve these findings. HttpOnly cookies reduce credential theft through JavaScript, but XSS can still perform actions as the user; CSP and frontend security remain essential.

- **Keep the multi-service topology for its educational purpose, while recognizing its operating cost.** Istio ingress, Session Gateway, `ext-authz`, NGINX, and Redis create several independently configured parts of the authorization path. For a small commercial application, a conventional backend-for-frontend and fewer services could deliver similar browser security with less operational work. Within this project, the useful simplification would be consolidating route declarations and reducing duplicated policy—not an immediate rewrite.

- **Narrow service permissions beyond workload identity where practical.** The [permission-service mesh policy](/srv/budget-analyzer/worktrees/orchestration/kubernetes/istio/authorization-policies.yaml:45) admits both NGINX and Session Gateway to all paths. Restrict Session Gateway to its internal lookup methods and paths, and NGINX to its public API surface. The narrow permission-service-to-session-revocation rule already demonstrates this pattern.

- **Treat egress controls as layered containment.** The egress gateway’s [network policy allows any destination on TCP 443](/srv/budget-analyzer/worktrees/orchestration/kubernetes/network-policies/istio-egress-allow.yaml:85). Host restrictions depend on Envoy routing, and both permitted callers can reach the shared gateway. Consider per-caller destination restrictions and exclusions for private/control-plane destinations where the hosting environment supports them. The existing TLS passthrough still encrypts traffic; the missing mesh wrapper is principally a workload-identity limitation.

- **Make vulnerability response an explicit release policy.** Digest pinning and exact-image evidence are strong controls, but [vulnerability findings are deliberately non-gating](/srv/budget-analyzer/worktrees/orchestration/docs/dependency-automation.md:347). Before hosted use, define remediation deadlines, expiring exceptions, and release-blocking criteria for exploitable findings. A passing scan workflow currently means evidence was collected successfully, not that the artifact is acceptable to deploy.

A future hosted deployment also needs availability and recovery requirements before choosing infrastructure. The reference currently uses single replicas and explicitly leaves backups, secrets, TLS lifecycle, and deployment recovery unresolved in [the deployment boundary](/srv/budget-analyzer/worktrees/orchestration/deploy/README.md:83). That is honest scope management, but it means the reference is not yet a production operating model.

For sensitive hosted use, require tested database restoration, defined recovery objectives, secret rotation, appropriate storage encryption, and alert delivery. [Infrastructure exporters are absent](/srv/budget-analyzer/worktrees/orchestration/docs/architecture/observability.md:11), and Alertmanager is disabled. Add visibility into Redis memory, database capacity, queue/dead-letter backlog, authorization failures, and certificate expiration. Decide explicitly whether disaster recovery invalidates all restored sessions.

Redis HA also needs a deliberate topology choice: the session implementation uses multi-key Lua operations without a shared Redis Cluster hash slot. A sharded Redis Cluster is not a drop-in replacement; primary/replica failover and sharding are different designs.

Finally, the architecture documentation needs reconciliation with implementation:

| Documented statement | What the inspected implementation supports |
|---|---|
| Absolute session expiration | Sliding renewal without an absolute cap |
| CSRF tokens on state changes | CSRF disabled; SameSite is the principal browser protection |
| Cookie `Max-Age` of 15 minutes | Session cookie issued without `Max-Age`; Redis enforces expiration |
| Redis cluster/Sentinel and `allkeys-lru` | Single Redis replica; neither topology nor eviction policy configured |
| Guaranteed outbox delivery | Currency-service explicitly leaves failed publications unreplayed and relies on later import reconciliation |

These claims appear in the [security architecture](/srv/budget-analyzer/worktrees/orchestration/docs/architecture/security-architecture.md:441) and [communication guide](/srv/budget-analyzer/worktrees/orchestration/docs/architecture/service-communication.md:72). The currency service’s [actual recovery contract](/srv/budget-analyzer/worktrees/currency-service/src/main/java/org/budgetanalyzer/currency/messaging/listener/MessagingEventListener.java:43) is reasonable for reconstructible exchange-rate imports, but must not be generalized to irreplaceable financial events.

I would also revise the communication guide’s blanket rejection of synchronous service calls and recommendation to read shared databases/caches. Bounded synchronous calls are sometimes appropriate; reaching into another service’s storage creates stronger coupling. Your permission lookup already illustrates a justified synchronous dependency.

Verification completed: the static security suite, all 36 static shared-session checks, and the offline production-reference verifier passed. Those results establish the existing checks’ contracts, not the absence of the issues above. Historical pinned production images were not independently audited against current sibling source. No tracked files or cluster resources were changed.
