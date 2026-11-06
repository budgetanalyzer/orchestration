# Application Architecture Security Review: Third Assessment

**Date:** 2026-11-01

**Reviews assessed:**

- Review 1: `application-architecture-security-review-2026-11-01.md`
- Review 2: `application-architecture-security-review-second-opinion-2026-11-01.md`

Sibling-repo paths below start with `../`. Other paths are relative to the
orchestration repository root.

## Bottom line

Keep the architecture. Both reviews are right about that, and most of their
findings hold up against the code. Review 2 is the stronger of the two: its
`KEYS`/`SCAN` finding is real, and so is its re-ranking of Redis `+@all`.

Both reviews missed the two issues I would fix first, and Review 2 is wrong
about one of them:

1. **An ordinary signed-in user can probably reach permission-service's
   internal endpoints from the public edge.** Review 2 looked at this path
   trick and concluded that Spring's firewall stops it. It does not, because
   the sidecar removes the semicolon before Spring sees the request.
2. **ext-authz's fail-closed JSON 503 never reaches a client.** Envoy replaces
   every 5xx from the authorizer with an empty 403. Review 2 blamed the case
   where ext-authz is unreachable; the deliberate 503 is affected too, and its
   proposed fix restores the status but not the documented JSON body.

I also reject or downgrade several of Review 2's items:

- Finding D is about code that nothing calls.
- The PDF "crash" mechanism is not what the configuration suggests.
- The `ISTIO_MUTUAL` egress fix is not the simple change it implies.
- "No HSTS" is probably half wrong.
- Several proposed fixes are redundant with each other.

## How this was checked

| Label | Meaning |
|---|---|
| **Tested** | I ran it, in a disposable container or a local stand-in |
| **Live config** | Read from the running Kind cluster, without changing it |
| **Source** | Read in code or configuration, not executed |
| **Reasoned** | Inferred, not demonstrated |

- **Live cluster:** infrastructure, Istio and policies are running, but the
  application pods are not deployed. Nothing here ran against the deployed
  services.
- **Envoy tests:** `envoyproxy/envoy:v1.38.8`. Both the ingress and a sidecar
  in the cluster report Envoy `1.38.8-dev`.
- **NGINX tests:** the pinned `nginxinc/nginx-unprivileged:1.29.8-alpine`,
  using the same `location` and `rewrite` as `nginx/nginx.k8s.conf:232-235`.
- **Redis tests:** the pinned `redis:7-alpine` (7.4.11) with no network and the
  ACL lines from `start-redis.sh`.
- **Verifier:** `verify-static-security-manifests.sh` passed with the pinned
  interpreter, which confirms that part of Review 1's claim. I did not rerun
  the shared-session checks or the offline production-reference verifier.

## New findings neither review caught

### N1. High priority, Medium-High severity: public edge to internal endpoints

**Status: path behaviour Tested across all hops. The final step into the real
permission-service is Source only.**

Review 2 says Envoy and NGINX do not treat `..;` as "go up one level", and that
only Spring's `StrictHttpFirewall` stops the trick. The first half is wrong for
Envoy, and that makes the second half wrong too.

What each hop does to
`/api/v1/users/..%3b/..%3b/internal/v1/users/<id>/authorization`:

| Hop | Behaviour | Path afterwards |
|---|---|---|
| Ingress Envoy | `%3b` is reserved, so `normalize_path` leaves it. `REJECT_REQUEST` only covers escaped slashes | unchanged |
| ext_authz | Any valid session passes; it does not check paths | unchanged |
| NGINX | Decodes `%3b`, matches `location /api/v1/users`, rewrites | `/permission-service/v1/users/..;/..;/internal/v1/users/<id>/authorization` |
| Sidecar | `normalize_path: true`, and Envoy treats `..;` as a parent segment | `/permission-service/internal/v1/users/<id>/authorization` |
| Spring | Sees a clean path, so the firewall has nothing to reject. The chain is `permitAll` | handler runs |

Test output with an echo server standing in for Tomcat:

```text
/api/v1/users/..%3b/..%3b/internal/v1/users/u1/authorization     (and %3B, %2e%2e%3b)
  -> /permission-service/internal/v1/users/u1/authorization  [200]
/api/v1/users/..%3b/..%3b/actuator/prometheus
  -> /permission-service/actuator/prometheus                 [200]
/api/v1/users/..;/..;/internal/v1/users/u1/authorization
  -> blocked: the ingress collapses this literal form        [404 from NGINX]
```

The sidecar settings come from a real pod (`normalize_path=true` on its
outbound and inbound HTTP chains, with `pathNormalization` left at the mesh
default). That pod is not permission-service, so its settings are the mesh
default applied to a stand-in.

Nothing behind the sidecar blocks this:

- `permission-service-policy` lets the NGINX identity reach every path
  (`kubernetes/istio/authorization-policies.yaml:60-61`).
- `PermissionServiceSecurityConfig.java` makes both internal GET endpoints
  `permitAll`, and its own comment says caller restriction is left to the mesh.

Impact for any signed-in user, including the default `USER` role:

- `GET .../{idpSub}/permissions?email=&displayName=` runs `syncUser`. That
  overwrites a user's stored email and display name, creates records for
  arbitrary subjects, and returns their internal ID, roles and permissions.
  The caller must know the `idpSub`, and the victim's next login overwrites
  the change. The side effect exists because this lookup is a GET that writes,
  which is Review 2's finding E.
- `GET .../{userId}/authorization` returns any user's status and grants.
- `/actuator/prometheus` is reachable, which breaks the internal-only
  observability rule. `transaction-service` and `currency-service` use the same
  rewrite and an equally unrestricted NGINX rule, so they are very likely
  affected too. I only tested the `users` location.

I found no privilege escalation, because `syncUser` does not grant roles. That
is why this is Medium-High and not High. It is still first on my list: it
crosses the internal boundary from the public edge with an ordinary account,
and the fix is small and sits entirely in this repository.
`nginx/nginx.production.k8s.conf` has the same rewrite.

**Fixes, both Tested against this chain:**

1. Reject decoded semicolons at NGINX, because NGINX is the first hop that sees
   them. `if ($uri ~ ";") { return 400; }` at server level returned 400 for
   every variant above and passed a legitimate path. Rejecting `;` at the
   ingress, as Review 2 proposes, would miss `%3b` unless it matched the
   encoded forms as well.
2. Narrow the NGINX rules in the mesh policies to public prefixes. An RBAC
   filter allowing only `/permission-service/v1/` returned 403 for the
   traversal and passed the legitimate path, because the sidecar normalizes
   before RBAC runs. This is Review 1's "narrow service permissions" item, and
   it deserves to be a real fix. Review 2's caveat that such rules can be
   fooled here is wrong.

Review 2's proposed test pinning `StrictHttpFirewall` would pass while this
path stayed open. It is fine as defence in depth, but it is not a fix.

**Confirm on a live stack.** After `tilt up` and a login, request your own user
ID. This endpoint is read-only:

```bash
curl --path-as-is --cookie "BA_SESSION=$SESSION" \
  "https://app.budgetanalyzer.localhost/api/v1/users/..%3b/..%3b/internal/v1/users/$USER_ID/authorization"
```

A 200 with authorization JSON confirms the finding. A 400, 403 or 404 means
something I could not see stops it, and this finding should be downgraded.

### N2. Medium: the documented fail-closed 503 cannot reach a client

**Status: Tested on Envoy 1.38.8, and confirmed in the Envoy source.**

`docs/architecture/session-edge-authorization-pattern.md:239` promises a JSON
503 for session-store failures, and `../ext-authz/http_server.go` produces one.
Envoy's HTTP client treats any 5xx from the authorizer as an error and discards
the response (`ext_authz_http_impl.cc`, `toResponse`). Results:

| Authorizer behaviour | Client receives |
|---|---|
| 401 with JSON | 401 with JSON, as documented |
| **503 with JSON** | **403, empty body** |
| Unreachable | 403, empty body |

So Review 2's defect is broader than it says. Its fix is still needed, but
`statusOnError: "503"` only fixes the status. The body stays empty because
Envoy sends no JSON on this path, so the documented contract needs either
changing or a local-reply mapping at the ingress. The frontend copes with an
empty 503 (`../budget-analyzer-web/src/api/client.ts:68-72`), so changing the
contract is the cheaper option.

No test covers this. The static "ext-authz denial contract scan" passes because
it only checks that `content-type` is forwarded
(`scripts/guardrails/verify-static-security-manifests.sh:1112-1149`), and no
orchestration verifier mentions `SERVICE_UNAVAILABLE`.

The 600 s timeout is also confirmed as Review 2 describes. Istio's reference
gives that default, and the live ingress has `stream_idle_timeout: 0s`, so
nothing else cuts the wait short. I could not read the ext_authz filter's own
settings live because the provider's service is not deployed.

That also produced a positive result: with the provider unresolved, istiod
installed a deny rule for `/api/` on the ingress. It fails closed even when
misconfigured.

### N3. The verifiers check configuration text, not behaviour

Both new findings and several existing ones pass every current check:

- `verify-session-architecture.sh:565` asserts the exact `+@all` line.
- `verify-credential-isolation.sh:574` tests only `GET`.
- The denial scan never exercises a denial.
- Nothing sends an encoded path through the real chain.

Review 2 calls for one edge contract with cross-layer tests. I agree, and N1
and N2 are the best argument for it: every component here looks correct on its
own. I would rank this above every other structural change.

### N4. Low: smaller items

- **ext-authz startup:** its retry loop can run for about 27.5 s of backoff
  (`../ext-authz/session.go:77`), but its health server only starts after Redis
  connects and the startup probe allows about 10 s. The kubelet kills it before
  the retries finish, which strengthens Review 1's finding 7.
- **Session Gateway logging:** `application-kubernetes.yml` turns off request
  body logging only, under the comment "to isolate POST timeout issue". It looks
  like a leftover debugging change, not a policy.

## Verdicts on Review 1

| # | Finding | Verdict | Severity | Notes |
|---|---|---|---|---|
| 1 | OAuth callback not bound to browser | **Agree** | Medium-High | Review 2's cookie details are right. See below on atomic consume |
| 2 | Session Gateway `+@all` | **Agree on the fix, disagree on High** | Medium | Tested. See below |
| 3 | Cookies forwarded to backends | **Agree** | Medium | No service reads `Cookie` or `Authorization`, and both NGINX configs share the include, so stripping them is low risk |
| 4 | No absolute session lifetime | **Agree** | Medium | ext-authz never reads `created_at`, so it needs a change too |
| 5 | CSRF and GET mutations | **Partly agree** | Low-Medium | Review 2's Fetch Metadata approach is better. Tokens are not needed for this design |
| 6 | Sensitive logging | **Agree, scope is wrong** | Medium, High with real data | Four services, not two. See below |
| 7 | Dependency-driven restarts | **Agree** | Medium | Spring probes all use aggregate health. See N4 |
| 8 | Redis memory | **Agree** | Medium | See Review 2's numbers below |

**Finding 1:** both reviews treat atomic consume as part of the fix. It is good
hygiene but not a security requirement here. The read-then-delete race only
allows a second exchange of the same one-time code, and the identity provider
should reject that. Don't let it delay the browser binding.

**Finding 2:** my tests match Review 2. `CONFIG SET dir`, `CONFIG SET
dbfilename`, `DEBUG` and `MODULE LOAD` are all refused on 7.4.11. The worst
outcomes are outages and tampering with other Redis users:
`ACL SETUSER redis-ops >pwned` and `ACL SETUSER ext-authz off` both succeeded.
One caution for Review 1's test design: `ACL DRYRUN` reported OK for `MODULE
LOAD` and `DEBUG`, which the server then refused. It checks ACL permission, not
capability. It suits negative tests, but it does not prove what an identity can
actually do.

**Finding 6:** actual body logging under the `kubernetes` profile:

| Service | Request bodies | Response bodies |
|---|---|---|
| transaction-service | on | on |
| permission-service | on | on |
| session-gateway | off | on |
| currency-service | on | off |

Nothing in `kubernetes/` or `deploy/` overrides these settings. Review 1 lists
two services and Review 2 lists three. Review 2's statement that the profile
does not turn this off is wrong for Session Gateway request bodies.

**Architecture and operations points**

| Point | Verdict |
|---|---|
| Keep server-side sessions | Agree |
| Keep the topology for its educational purpose | Agree |
| Narrow mesh permissions | **Agree, and it should rank much higher.** It is half of the N1 fix |
| Egress as layered containment | Agree, low priority |
| Make vulnerability response a release policy | Agree, before hosted use only |
| Recovery and operational gaps | Agree. Honest scope statement, not a defect |
| Redis HA topology | Agree |
| Documentation table | Agree with all five rows. One detail: `expires_at` is also checked by ext-authz and Session Gateway, not only by Redis |
| Communication guide | Agree |

I also confirmed Review 1's claim that it found ownership checks. All 31
transaction-service handlers have `@PreAuthorize`, and every transaction and
saved-view path is owner-scoped or requires an explicit `:any` permission. This
was a Source review, and it assumes trusted claims, so it says nothing about
paths like N1.

## Verdicts on Review 2

### Where it is right and adds real value

- **Finding A (`KEYS`/`SCAN`): Agree, High.** Tested. `KEYS session:*` and
  `SCAN` as `currency-service` both returned the token while `GET` returned
  `NOPERM`. `KEYS *` also returned `user_sessions:*` and `oauth2:state:*` keys.
  Bytecode for Spring Data Redis 4.1.2 confirms `RedisCacheWriter` defaults to
  `BatchStrategies.keys()`, and `immediateWrites()` does not change that. The
  rating assumes currency-service is already compromised, which is why I put
  N1 first: N1 needs only a login.
- **Re-rating `+@all` to Medium:** Agree.
- **OAuth cookie details (`SameSite=Lax`, `__Host-`):** Agree. These are the
  details that make the fix work.
- **Finding E (no timeout on the login permission call):** Agree. Confirmed in
  `../session-gateway/.../service/PermissionServiceClient.java`.
- **Finding F (`@PreAuthorize` not enforced by default):** Agree. The counts are
  right: 31/31, 6/6 and 3/3, plus 2 internal handlers.
- **Redis memory numbers:** Agree. 1/s, burst 25 and a 900 s TTL give about 925
  records. One addition: `noeviction` turns a crash into failed logins, so the
  `returnUrl` cap and shorter TTL are still needed.
- **ingress to Session Gateway has no path limit:** Agree. Confirmed at
  `authorization-policies.yaml:189-199`.

### Where I disagree

| Review 2 claim | My position | Evidence |
|---|---|---|
| Envoy doesn't treat `..;` as a parent segment, and only `StrictHttpFirewall` stops the trick | **Wrong.** See N1 | Tested |
| Path-based mesh rules can be fooled by this trick | **Wrong for this path.** The sidecar normalizes first | Tested |
| Status 503 fixes the contract | **Incomplete.** The body stays empty. See N2 | Tested |
| Finding D: deleting a user is weaker than deactivating them | **Not a live issue.** `UserService.deleteUser` has no caller, in production code or tests. Remove it, or fix it if an endpoint is ever added | Source |
| Finding D: re-signup after deletion is a defect | **Deliberate.** `V1__initial_schema.sql:26` says the index allows `idp_sub` reuse after soft delete | Source |
| Finding C: a PDF "crashes" the service "the same way" as Redis OOM | **Mechanism unproven, and probably different.** See below | Source, Reasoned |
| Finding C: three `loadPDF` call sites | **Five.** It misses the two CapitalOne extractors at `:120` and `:137` | Source |
| "No HSTS" (finding G) | **Probably half wrong.** See below | Source |
| Switch egress to `ISTIO_MUTUAL` | **Not a mode change.** `egress-routing.yaml:29-33` records resets with the current PASSTHROUGH listener. It needs a listener redesign | Source |
| Sessions last "forever" | **Overstated.** Only while heartbeats continue and the account stays active locally. The ADR says "revoked", not "blocked". The underlying gap is real | Source |
| "Instant revocation" contradicts the documented race | **Overstated.** Deleting a session takes effect immediately, because ext-authz reads Redis with no cache. The race concerns grant refresh. "No expiry window" at `security-architecture.md:754` is still too strong | Source |
| RabbitMQ 3.13 is end-of-life | **True for community support only.** Commercial support runs to 31 Dec 2029. With no commercial contract the practical conclusion stands, and 4.4 is current. I did not independently tie the pinned digest to 3.13.7 | Vendor page |
| The quarterly review "missed" RabbitMQ | **Inference.** Nothing shows a review ran | Source |

**PDF details:** the deployment sets no heap flags, so the JVM should use its
default of about 25% of the 512Mi limit, roughly 128 MiB. Heap exhaustion should
therefore raise `OutOfMemoryError` inside the JVM long before the pod reaches
its limit, and no `ExitOnOutOfMemoryError` is set. The likely failure is GC
pressure and failing requests, or a degraded JVM that stays up without
restarting, not a kill and restart. That may be worse, and Medium still stands,
because the `USER` role has `statementformats:write`. Measure it before
designing the fix. A heap that small against 25 MB uploads read with
`getBytes()` deserves a look on its own.

**HSTS details:** the string appears nowhere in the NGINX, Kubernetes or Session
Gateway configuration, and the live ingress config has none. But `SecurityConfig`
leaves Spring Security's default headers on, and those send HSTS on https-scheme
requests, so the auth lane very likely sends it. I have not seen the header
live. The gap is the NGINX lane, which serves the first page. Review 2's fix of
setting it at the ingress is still right.

### Where its fixes are redundant

- **Three fixes for finding A.** Hashing session keys or splitting Redis each
  stops token theft alone. A versioned cache prefix is only needed if you want
  to remove `+keys +scan` while keeping one shared Redis. Hash first: it needs
  coordinated changes in Session Gateway and ext-authz, but no new
  infrastructure. A new Redis host probably needs new TLS material, and agents
  may not generate that.
- **Reject requests carrying two session cookies.** Once the cookie is
  `__Host-BA_SESSION`, a browser will not accept a planted copy with
  `Path=/api` or a `Domain`, so this check protects against almost nothing.
  Rename the cookie and skip the check.

### Fetch Metadata needs one more decision

I agree with making `Sec-Fetch-Site` and `Origin` the main CSRF control, but
Review 2 does not say what happens when both headers are absent. Allow those
requests: browsers send at least one on state-changing requests, and
non-browser clients such as `budget-analyzer-api-tests` send neither. Go 1.25's
`http.CrossOriginProtection` uses the same model. Remember too that ext_authz
covers only `/api/*`, so the auth lane needs its own check.

### Architectural recommendations

| Recommendation | Verdict |
|---|---|
| Define the edge contract once, with cross-layer tests | **Agree, top priority.** See N3 |
| Hash session tokens | **Agree.** Do this first for finding A |
| Split Redis by trust level | **Agree as the destination, not the first move.** Do it before hosted use |
| Signed identity context | **Defer.** See below |
| Internal APIs on separate ports | **Disagree for now.** Mesh path rules plus the NGINX rejection close N1 with far less work |
| Parse files in a separate worker | **Defer.** Add caps first and measure |

**Signed identity:** the mesh already limits who can reach backends, so this
mainly protects against a compromised NGINX, and N1 shows that the current
boundary failure is routing, not header forgery. The `permitAll` internal
endpoints would not benefit at all. It is a valid decision for a hosted threat
model, and `claims-header-trust-hardening-options.md` is the right place to make
it, but it does not need to come before real data as Review 2 says.

### Other checks

- **Forged headers for a user with no permissions (finding H):** Tested at
  Envoy. A forged `X-Permissions` is overwritten with an empty value and `X-Roles`
  likewise, so the missing test is a coverage gap and not an exposure. Add the
  test anyway.
- **Postgres `hostssl`:** the conclusion stands, but `statefulset.yaml:71` only
  sets the auth method, so that citation is imprecise.
- **Review 1's absolute links:** Review 2 is right that they break the
  path-portability rule.

## Priorities

`AGENTS.md` puts bug fixes above new features, and no production environment
exists. Neither review reflects that, so I would split the work this way.

**Now: bug fixes, mostly in this repository**

| # | Change | Owner |
|---|---|---|
| 1 | Reject `;` in NGINX in both configs, narrow NGINX and ingress mesh rules, and add live encoded-path tests (N1) | orchestration |
| 2 | Set `statusOnError: "503"` and a ~1 s timeout, correct the contract doc, and test a real denial (N2) | orchestration |
| 3 | Strip `Cookie` and `Authorization` at NGINX | orchestration |
| 4 | Replace `+@all` with an allowlist, change the verifier that asserts it, and add `maxmemory` | orchestration |
| 5 | Correct the documentation drift both reviews list | orchestration |

**Next: changes that need sibling repositories**

| # | Change | Owner |
|---|---|---|
| 6 | Hash session keys, then remove `+keys +scan` or split Redis (finding A) | session-gateway, ext-authz, then currency-service or orchestration |
| 7 | Bind OAuth callbacks to the browser, and move to `__Host-` cookies | session-gateway, ext-authz |
| 8 | Turn body logging and TRACE off by default in all four services | services |
| 9 | Separate liveness from readiness | ext-authz, service-common |
| 10 | Add an absolute session lifetime | session-gateway, ext-authz |
| 11 | Add `Sec-Fetch-Site`/`Origin` checks, and HSTS at the ingress | ext-authz, orchestration |
| 12 | Add a login-path timeout and make the sync call a POST | session-gateway, permission-service |
| 13 | Add PDF caps, measured against real heap behaviour | transaction-service |
| 14 | Upgrade RabbitMQ to a supported 4.x series | orchestration |

Under this repository's rules, the service-code items belong to their own
repositories. They need to be handled in those contexts, not worked around here.

**Before any hosted use**

Redis split, vulnerability gating, recovery objectives and restore tests, the
signed-identity decision, and egress redesign.

**Drop or defer**

- Finding D as a security item: remove the dead method.
- Rejecting duplicate session cookies, once the rename ships.
- Internal APIs on separate ports, and a parsing worker for now.
- Atomic consume as a blocker for the OAuth fix.
- `StrictHttpFirewall` tests as a mitigation for path tricks.

## Limits of this assessment

- Nothing ran against deployed application services. N1's last step, from a
  clean path into the real permission-service, is from source. The `curl` above
  settles it.
- Endpoint counts and ownership checks are static. The ownership review covered
  transaction-service only; permission-service role logic got no equivalent
  review.
- The Envoy and NGINX chains are reduced stand-ins, not the full generated
  ingress configuration.
- JVM heap behaviour, Session Gateway HSTS, and Redis exhaustion are reasoned,
  not measured.
- This is not a penetration test, and I would not treat the N1 path as the only
  case of its kind. Decoding differences between hops are worth a dedicated
  test pass.
- I changed no tracked files, no cluster resources, and no sibling repositories.

## Sources

- [Envoy `ext_authz_http_impl.cc`, release/v1.38](https://github.com/envoyproxy/envoy/blob/release/v1.38/source/extensions/filters/common/ext_authz/ext_authz_http_impl.cc)
- [Istio MeshConfig reference](https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/)
- [RabbitMQ release information](https://www.rabbitmq.com/release-information)
