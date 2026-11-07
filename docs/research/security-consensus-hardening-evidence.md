# Security Consensus Hardening Evidence

Measurements and results recorded by the security hardening plans
(`docs/plans/security-hardening-01-edge-mesh-redis-acl.md` and its siblings).
Each section names the plan and phase that produced it. Severity scores are
intentionally not assigned.

## Plan 01, Phase 1: Mesh Public/Internal Boundary

Date: 2026-11-06. Target: local Tilt/Kind (`kind-kind`), Istio 1.30.6,
orchestration `HEAD` `b0e44f2` plus the uncommitted Phase 1 changes, Tilt-built
service images (`*:tilt-<hash>`). Every probe went through the real HTTPS
ingress at `https://app.budgetanalyzer.localhost` with normal TLS verification
and `curl --path-as-is`.

### Method

`./scripts/smoketest/verify-edge-contract.sh --report FILE` (Public/Internal
Boundary section):

- Fixture: one synthetic user `usr_loadtest_1` with session `loadtest_1`, from
  `./scripts/loadtest/seed-loadtest-users.sh --count 1`. It is removed with
  `teardown-loadtest.sh`. This user exists in permission-service, so a `404`
  cannot come from a missing user.
- NGINX lane, with the session cookie attached so `ext_authz` admits the
  request: prefixes `/api/v1/users/`, `/api/v1/transactions/` and
  `/api/v1/currencies/`. Targets `internal/v1/users/usr_loadtest_1/authorization`
  and `actuator/prometheus`. Each traversal form is repeated twice, as in R3's
  path.
- Direct Session Gateway lane, without a cookie:
  `GET /auth/v1/<t>/<t>/actuator/prometheus` and
  `DELETE /auth/v1/<t>/<t>/internal/v1/sessions/users/usr_loadtest_1`.
- Forms: `..%3b`, `..%3B`, `%2e%2e%3b`, `..;`, `%2e%2e`, `..%2f`, `..%5c`,
  `%252e%252e%252f` and `%2e%2e;`.
- Verdicts:
  - `leaked`: the body contains internal handler output, either `"userId"`
    from the authorization response or a Prometheus `# HELP`/`# TYPE` line.
  - `reached`: a 2xx without that output.
  - `frontend-shell`: a 2xx byte-identical to the public `GET /` HTML.
  - `blocked`: any other non-2xx.
  - Side-effect checks: the seeded session's Redis key and `user_sessions`
    index after each `DELETE`, and the seeded permission-service user row
    before and after the NGINX-lane probes, which detects writes such as
    `syncUser`.
- The `.../permissions` endpoint is never probed, because it writes through
  `syncUser`. Rate-limit `429`s are retried and never counted as denials.

### Baseline before narrowing (reproduced)

R3's encoded-semicolon traversal **reproduced on the real chain**. 14 probes
reached an internal handler, and one of them had a persistent side effect.

| Lane | Path pattern | Forms | Status | Result |
| --- | --- | --- | --- | --- |
| NGINX | `/api/v1/users/<t>/<t>/internal/v1/users/{id}/authorization` | `..%3b`, `..%3B`, `%2e%2e%3b` | 200 | Leaked: permission-service internal authorization response for the seeded user |
| NGINX | `/api/v1/{users,transactions,currencies}/<t>/<t>/actuator/prometheus` | `..%3b`, `..%3B`, `%2e%2e%3b` | 200 | Leaked: Prometheus exposition of each of the three backends (9 probes) |
| NGINX | `/api/v1/{transactions,currencies}/<t>/<t>/internal/v1/users/{id}/authorization` | `..%3b`, `..%3B`, `%2e%2e%3b` | 404 | Climbed into a service that has no such handler |
| NGINX | all prefixes and targets | `..;`, `%2e%2e`, `%2e%2e;` | 404 | Blocked |
| NGINX | all prefixes and targets | `..%2f`, `..%5c` | 400 | Blocked |
| NGINX | all prefixes and targets | `%252e%252e%252f` | 401 | Blocked |
| Auth | `GET /auth/v1/<t>/<t>/actuator/prometheus` | `%2e%2e;` | 200 | Leaked: Session Gateway Prometheus exposition, without a session |
| Auth | `DELETE /auth/v1/<t>/<t>/internal/v1/sessions/users/{id}` | `%2e%2e;` | 204 | Reached: the seeded session and its `user_sessions` index were deleted, without a session or credential |
| Auth | both targets | `..%3b`, `..%3B`, `%2e%2e%3b`, `..%2f`, `..%5c`, `%252e%252e%252f` | 400 | Blocked |
| Auth | `DELETE` target | `..;`, `%2e%2e` | 404 | Blocked; session intact |
| Auth | `GET` target | `..;`, `%2e%2e` | 200 | `frontend-shell`; see below |

The seeded permission-service user row was unchanged. All legitimate routes
returned their expected status.

What the leaks mean:

- On the NGINX lane, any authenticated session could read another user's
  internal authorization snapshot by user ID, and every backend's actuator
  metrics. The backend mesh rules admitted the NGINX identity on any path, so
  Spring resolved the `;`-suffixed dot segments that NGINX forwarded inside an
  allowed prefix.
- On the direct auth lane, an unauthenticated client could read Session
  Gateway's actuator metrics and revoke every session of an arbitrary user ID.
  The ingress rule on `session-gateway-policy` admitted every path.

### After narrowing

The policy change is in `kubernetes/istio/authorization-policies.yaml`:

- exact NGINX upstream prefixes on the three backends
- Session Gateway limited to `GET` on the two internal permission-service lookups
- the ingress identity limited to the `auth-route` surface on Session Gateway
- an explicit `default-deny-all`

The verifier was run three times after the change, twice at 06:09 UTC by an
earlier attempt and again at 06:17 UTC. The results were identical each time:
**97 passed, 0 failed**.

| Probe set | Before | After |
| --- | --- | --- |
| NGINX `..%3b`, `..%3B`, `%2e%2e%3b` (18 probes) | 12 × 200 leaked, 6 × 404 | 18 × 403 `RBAC: access denied` |
| Auth `GET` `%2e%2e;` actuator | 200 leaked | 403 |
| Auth `DELETE` `%2e%2e;` revocation | 204, session revoked | 403, session intact |
| All other probes | non-2xx, or `frontend-shell` | unchanged |
| Seeded session after all `DELETE` probes | revoked once | intact |
| Seeded user row after NGINX-lane probes | unchanged | unchanged |

A manual check with a seeded session confirmed the denial layer:
`/api/v1/users/..%3b/..%3b/actuator/prometheus` and
`.../internal/v1/users/usr_loadtest_1/authorization` return `403 text/plain`
with `RBAC: access denied` from the backend sidecar. The sidecar evaluates the
normalized path, so the traversal no longer matches
`/permission-service/v1/users/*`.

Legitimate paths after the change:

- Seeded-session `200` on `/api/v1/currencies`, `/api/v1/transactions`,
  `/api/v1/statement-formats`, `/api/v1/views`,
  `/api/v1/exchange-rates?targetCurrency=THB`, both `/api/<service>/v3/api-docs`
  routes, `/auth/v1/session` and `/auth/v1/user`.
- `/api/v1/users` returns the application's JSON `403 FORBIDDEN`, because the
  seeded `USER` lacks `users:read`. It is not the mesh RBAC body, so the request
  reached the application.
- `/oauth2/authorization/idp` returns `302` to the configured IdP authorize
  endpoint.
- The heartbeat returns `200`. That proves a successful permission-service
  authorization lookup, because a lookup failure returns `503`. The
  permission-service sidecar's `istio_requests_total` showed only `200`
  responses with `source_workload="session-gateway"`.
- `./scripts/smoketest/verify-istio-ingress.sh` (97/97) completed a real browser
  login: original callback, user read, heartbeat and logout.

### Frontend-shell 200s

`GET /auth/v1/..;/..;/actuator/prometheus` and
`GET /auth/v1/%2e%2e/%2e%2e/actuator/prometheus` return `200` before and after.
The ingress resolves both to `/actuator/prometheus`, which leaves the `/auth`
route for the app catch-all, and NGINX serves the public SPA HTML for it,
exactly as it does for any unknown path. A plain `GET /actuator/prometheus`
returns the same `200 text/html`. No Session Gateway handler is reached. The
verifier accepts such a `2xx` only when the body is byte-identical to `GET /`.
This is the one place where "every probe returns non-200" is enforced as
"returns no internal surface". Making these non-200 would mean changing the
SPA fallback, which is outside this phase.

### Limitations

- The `%2e%2e;` auth-lane denial now relies on the Session Gateway sidecar's
  path rule. Literal and encoded `;` rejection at NGINX and the ingress is a
  separate control in Plan 01, Phase 3.
- Measured on local Tilt/Kind only. The production reference shares
  `authorization-policies.yaml` through its overlay and passes
  `verify-production-image-overlay.sh` offline, but no hosted runtime was
  exercised.
- Plan 02.3, Phase 3 replaces the Session Gateway `.../permissions` rule with
  the new sync call.

## Plan 01, Phase 2: NGINX Backend Header Contract

Date: 2026-11-06. Target: the checked-in `nginx/includes/backend-headers.conf`
in a disposable container from the digest-pinned `nginx-gateway` image
(`nginxinc/nginx-unprivileged:1.29.8-alpine@sha256:0c79d56a...`), plus local
Tilt/Kind (`kind-kind`) for the live regression check. Orchestration `HEAD`
`b0e44f2` plus the uncommitted Phase 1 and Phase 2 changes.

### Change

The shared include now sets `proxy_set_header Cookie "";`,
`proxy_set_header Authorization "";` and
`proxy_set_header X-Forwarded-Proto https;` in place of `$scheme`, which is
always `http` behind the ingress. All nine `/api` proxy locations in
`nginx/nginx.k8s.conf` and all nine in `nginx/nginx.production.k8s.conf` use
the include. The static guardrail now enforces both facts.

### Stand-in proof

`./scripts/guardrails/verify-nginx-backend-headers.sh` sends synthetic
`Cookie` (two headers), `Authorization: Bearer`, `X-Forwarded-Proto: http` and
identity headers through a copy of the `/api/v1/transactions` location (a
variable `proxy_pass`, `rewrite` and the include) to an njs echo upstream.
Only header names are recorded.

| Location | Header names the upstream received |
| --- | --- |
| Control, `proxy_pass` only | includes `cookie` and `authorization` (NGINX forwards them by default) |
| Shared include, after | `accept`, `host`, `user-agent`, `x-forwarded-for`, `x-forwarded-host`, `x-forwarded-proto`, `x-permissions`, `x-real-ip`, `x-roles`, `x-user-id` |

After the change, `X-Forwarded-Proto` is `https` even when the client sends
`http`, and `X-User-Id`, `X-Roles` and `X-Permissions` keep their values: 7
passed, 0 failed. Swapping the pre-change include in temporarily gave 3
failures: `cookie` forwarded, `authorization` forwarded, and the proto not
`https`. The identity assertions still passed.

### Live check

The running NGINX did not pick up the include on its own. Tilt updated the
`nginx-gateway-includes` ConfigMap and the kubelet refreshed the mounted file,
but the master process was 1h30 old. After asserting the `kind-kind` target,
`nginx -t && nginx -s reload` loaded the new include. Then
`./scripts/smoketest/verify-edge-contract.sh` passed 97/0. Seeded-session
requests through ext_authz and NGINX returned `200` for `/api/v1/transactions`,
`/api/v1/statement-formats`, `/api/v1/views`, `/api/v1/currencies`,
`/api/v1/exchange-rates` and both OpenAPI routes, and `/api/v1/users` returned
the application's `403`. These results show that identity headers still reach
the services and ext_authz still admits requests. The checked-in production
config parses inside the `nginx-gateway` pod with the new include.

### Limitations

The live check proves the change caused no regression. The proof that the
headers are stripped comes from the stand-in, because no in-cluster backend
echoes request headers. Business services and service-common read none of
`Cookie`, `Authorization` or `X-Forwarded-Proto`, so the proto change corrects
the contract and does not fix a live bug.

## Plan 01, Phase 3: Shared NGINX Routes and Semicolon Rejection

Date: 2026-11-06. Target: local Tilt/Kind (`kind-kind`) and disposable
containers from the digest-pinned `nginx-gateway` image
(`nginxinc/nginx-unprivileged:1.29.8-alpine`). Orchestration `HEAD` `b0e44f2`
plus the uncommitted Phase 1 to 3 changes.

### Change

- `nginx/includes/api-routes.conf` holds the 11 API locations, including the
  `= /api` and `/api/` unknown-route rejections, and the server-level
  `if ($uri ~ ";") { return 400; }`. `nginx/includes/api-docs-routes.conf`
  holds the five `/api-docs` locations with the two regex locations in their
  original order. Both server configs include each file once. Inlining the two
  includes back into each config and removing comments gives the `HEAD` config
  exactly, apart from the new `if`, so route bodies, order and precedence are
  unchanged. Both files ship through the `nginx-gateway-includes` ConfigMap
  lists in the `Tiltfile` and `kubernetes/production/apps/kustomization.yaml`.
- `kubernetes/istio/ingress-path-hardening.yaml` inserts one enforcing RBAC
  `DENY` filter, `envoy.filters.http.rbac.ingress_path_hardening`, before
  `envoy.filters.http.ext_authz`, matching `:path` against
  `^[^?]*(;|%3[bB]|%253[bB]).*$`. Envoy `safe_regex` matches the whole value,
  hence the trailing `.*`. It is applied by the Tilt `istio-ingress-routes`
  resource and rendered by `kubernetes/production/istio-ingress-policies`.
  It sets no `rules_stat_prefix`, because the gateway stats matcher exports
  only RBAC counters ending in `rbac.denied`. Istio's own ingress RBAC filter
  carries only `shadow_rules`, so this filter is the only one that increments
  that counter.
- The static guardrail fails on a missing shared include, a duplicated
  `/api` or `/api-docs` location in either config, a missing `;` rejection,
  or a path-hardening filter that is missing, not `DENY`, not alone, not before
  `ext_authz`, or that fails to deny literal, `%3b`/`%3B` or `%253b`/`%253B`
  forms or denies ordinary paths and query strings. `--self-test` rejects each
  new fixture for its intended reason.

### Normalization finding

HTTP filters see `:path` after HCM `normalize_path`. Normalization treats a
literal `..;`, `..;<text>` or `.;` segment as a dot segment: it resolves the
segment and drops the `;<text>`. The filter therefore never sees those three
forms. Live, `/<m>-dot/..;/<m>-target` and `/<m>-dot/..;x/<m>-target` reached
NGINX as `/<m>-target`, and `/<m>-dot/.;/<m>-target` as `/<m>-dot/<m>-target`,
with no `;` in the logged path. Every other literal `;` (for example
`/api/v1/transactions;x` and `%2e%2e;`) and every encoded form is denied. So no
`;` from these probes reached NGINX or Session Gateway, but the literal `..;`
rows of the Phase 1 matrix are resolved, not denied, and remain covered by the
routing and mesh rules recorded in Phase 1.

### Live results

`./scripts/smoketest/verify-edge-contract.sh` passed **153/0**, in a run by
the earlier attempt and again in this one.

Semicolon Rejection section, five forms (`;`, `%3b`, `%3B`, `%253b`,
`%253B`), each as a direct suffix and inside `%2e%2e<form>` traversal
segments, plus `..<form>` for the four encoded forms:

| Lane | Probes | Result |
| --- | --- | --- |
| NGINX lane, seeded session cookie | 14 `GET` | 14 × `403` `RBAC: access denied` |
| Direct `/auth/*` lane | 14 `GET` and 9 `DELETE` revocation | 23 × `403` `RBAC: access denied`; seeded session and `user_sessions` index intact after every `DELETE` |

- Ingress `rbac.denied` rose by exactly 37, one per probe.
- The NGINX and Session Gateway sidecars recorded no request from the ingress
  during the probes, and NGINX logged no probe.
- The path-hardening filter is the listener's only enforcing RBAC filter and
  sits before `ext_authz`.
- A `;` in the query string still works: `200` for
  `/api/v1/exchange-rates?targetCurrency=THB&probe=a;b` and
  `/auth/v1/user?probe=a;b`.

Rerun Public/Internal Boundary section, compared with the Phase 1 "after"
table:

The boundary section asserts only "not 2xx" per probe. The attribution to the
ingress filter follows from the filter regex and from the Semicolon Rejection
counter proof for the same path forms.

| Probe set | Phase 1 after | Phase 3 |
| --- | --- | --- |
| NGINX `..%3b`, `..%3B`, `%2e%2e%3b` (18 probes) | `403` from the backend sidecar | `403`, now matched by the ingress filter first |
| NGINX `%2e%2e;` | non-2xx | `403`, matched by the ingress filter |
| Auth `GET` and `DELETE` `%2e%2e;` | `403` from the Session Gateway sidecar | `403`, matched by the ingress filter; session intact |
| Auth `..%3b`, `..%3B`, `%2e%2e%3b` | non-2xx | `403`, matched by the ingress filter; session intact |
| Literal `..;` and plain `%2e%2e` | `404`, or the frontend shell for `GET` | unchanged |
| `%2f`, `%5c` and `%252e%252e%252f` | `400` or `401` | unchanged |

Legitimate routes with the seeded session: `200` for `/api/v1/currencies`,
`/api/v1/transactions`, `/api/v1/statement-formats`, `/api/v1/views`,
`/api/v1/exchange-rates?targetCurrency=THB`, both OpenAPI routes,
`/auth/v1/session` and `/auth/v1/user`. `/api/v1/users` returned the
application's `403`, and `/oauth2/authorization/idp` returned `302`.

`./scripts/smoketest/verify-istio-ingress.sh` passed **97/97**. Its nested
`verify-ingress-rate-limits.sh` passed 33 checks. The live listener still has
exactly the four named limiters before `ext_authz`. A real browser login
completed the original OAuth callback, user read, heartbeat and logout.

`./scripts/smoketest/verify-edge-browser-hardening.sh` first failed 8 checks and
raised 10 warnings, all from its text checks that looked for the `/api` fallback
and `/api-docs` locations in each server config. Those blocks now live in the
shared includes. The verifier now asserts that each config includes both
shared files, runs the fallback and `/api-docs` checks once against the
includes, and requires both includes when it stages the production config in
the pod. The rerun passed **82/82 blocking checks with 0 warnings**. That run
covered the in-pod `nginx -t` of `nginx.production.k8s.conf`, the dev and
strict CSP headers on `/`, `/@vite/client` and `/_prod-smoke/`, the
`/api-docs` CSP and its `404` fallback, the direct-NGINX `/api` and unknown-API
`404 text/plain` fallbacks, a second real browser login and the
runtime-hardening cascade (176/176).

The live pod's `nginx.conf` and mounted includes are byte-identical to the
checked-in files, and `nginx -t` passes. Because `nginx.conf` is a subPath
mount, the earlier attempt restarted `nginx-gateway` after asserting the
`kind-kind` target, so the pod loaded the new main config.

### NGINX layer proof

The ingress now stops these paths before NGINX, so
`./scripts/guardrails/verify-nginx-shared-routes.sh` exercises the NGINX layer
in one disposable, network-less container per complete config. It passed
**26/0** with these results for both `nginx.k8s.conf` and
`nginx.production.k8s.conf`:

- `nginx -t` passes with the mounted includes.
- `;x`, `%3bx`, `%3Bx`, `..;` traversal, `/api-docs;x` and `/;x` return `400`
  with the security headers.
- `/api` and `/api/v1/unknown-route`, also with `?x=a;b`, return the shared
  `404 Not Found`.
- Query strings with `;` reach the proxy locations (`502`, because the
  container has no upstreams).
- The `/api-docs/` fallback keeps the docs CSP.

`%253bx` decodes once to `%3bx` and is not rejected at NGINX, so that form is
covered only by the ingress. The earlier attempt removed the `if` from a
temporary copy of the include as a negative control, and the `;` probes then no
longer returned `400`.

### Limitations

- Literal `..;`, `..;<text>` and `.;` segments are resolved by ingress
  normalization rather than denied. See the normalization finding above.
- Measured on local Tilt/Kind only. The production reference renders the same
  filter and includes and passes `verify-production-image-overlay.sh` offline,
  but no hosted runtime was exercised.
- The OpenAPI document declares no path with `;`. This supports rejecting
  matrix-parameter syntax, but it is not a compatibility proof for every
  client.

## Plan 01, Phase 4 — Bounded authorizer failures

Validated on 2026-11-06 in the local development VM and `kind-kind` cluster.
The workspace pre-agent boundary check and
`./scripts/bootstrap/check-local-runtime.sh` passed. The existing Tilt process
was healthy; invoking `tilt up --stream` refused its already-occupied loopback
port. The running instance was retained, and `tilt trigger istiod` successfully
reapplied the checked-in values after the latency measurement. Its update
completed at 08:45:59 UTC. Exact local-target guards precede cluster mutations.

### Latency and timeout choice

With one disposable fixture from `seed-loadtest-users.sh --count 1`, send 200
sequential requests to the normal TLS-verified
`https://app.budgetanalyzer.localhost/api/v1/currencies`, pausing 125 ms between
requests. Every fourth request has no cookie; the other 150 use the synthetic
session. All returned the expected `200` or `401`. Teardown removed the fixture.

Measure authorization separately by differencing ext-authz's sidecar
`istio_request_duration_milliseconds_bucket` metrics before and after the
sample, selecting `reporter="destination"` and
`source_workload_namespace="istio-ingress"`. Read them with:

```bash
kubectl exec deployment/ext-authz -c istio-proxy -- \
  pilot-agent request GET stats/prometheus
```

The first sample's snapshot, taken only two seconds after traffic stopped,
contained 187 of 200 checks because histogram export lags. The final sample
waited for exported counts to reach exactly 150 authorizations and 50 denials
before calculating these cumulative bucket deltas:

| Authorizer response | Checks | ≤0.5 ms | ≤1 ms | ≤5 ms | ≤10 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| `200` | 150 | 141 | 149 | 149 | 150 |
| `401` | 50 | 48 | 50 | 50 | 50 |

Client timings from curl `%{time_total}` include TLS, the authorization hop
and (for successful requests) NGINX and currency-service:

| Client response | Mean | Median | p95 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| `200` | 24.621 ms | 23.973 ms | 28.571 ms | 35.802 ms |
| `401` | 17.559 ms | 16.924 ms | 21.211 ms | 25.562 ms |

Retain **1 second** as the provider timeout: 100 times the highest populated
authorizer bucket's upper bound, with room for local scheduling and connection
setup, while bounding an outage promptly. This is a quiet local baseline,
not a load-capacity or hosted-environment latency guarantee. Repeat the sample
when changing the timeout. Machine-readable snapshots and client aggregates
are in the disposable `.cache/security-hardening-phase4/latency.json`; this
section is the durable measurement record.

### Configuration and observed contract

`kubernetes/istio/istiod-values.yaml` now sets `timeout: 1s` and
`statusOnError: "503"`, retaining `failOpen: false`. The live verifier reads
each ingress gateway's Envoy config dump and confirmed `http_service.server_uri.timeout`
of `1s`, `status_on_error.code` of `ServiceUnavailable`, and effective
`failure_mode_allow: false` (the protobuf default when omitted).

The [canonical contract](../architecture/session-edge-authorization-pattern.md#authorizer-failures)
now describes empty ingress-generated `503` responses with no `content-type`.
Envoy treats authorizer `5xx` responses as errors and discards their bodies;
the service's JSON does not survive that path. No local-reply mapping or
service change was introduced. Ordinary missing-session denials retain JSON.

`./scripts/smoketest/verify-edge-contract.sh --report
.cache/security-hardening-phase4/edge-report.tsv` passed **175 checks, 0
failures**, including the existing public/internal and semicolon sections.
The Authorization Failure section observed:

| Case | Client responses | Client elapsed time |
| --- | --- | --- |
| No cookie / unknown session | `401 application/json`, `{"type":"UNAUTHORIZED","message":"Authentication required"}` | 17.900 / 16.466 ms |
| ext-authz scaled to zero, with / without cookie | Empty `503`, no `content-type` | 15.066 / 14.878 ms |
| Ingress-to-authorizer packets dropped, with / without cookie | Empty `503`, no `content-type` | 1.017723 / 1.018214 s |
| Redis stopped, two seeded-session requests | Empty `503`, no `content-type` | 99.369 / 132.399 ms |

Each case produced zero additional ingress-origin requests at the NGINX
sidecar and no probe marker in NGINX access logs. The hang also produced zero
additional checks at the ext-authz sidecar. Both Redis probes were recorded
there as authorizer `503` responses, directly exercising the body-discard
path before Redis-dependent readiness removed the endpoint. Future runs may
instead observe an unavailable endpoint, as allowed by the phase contract.

The verifier allows 500 ms of client/TLS overhead above the provider's
one-second deadline, and requires hang responses to take at least one second.
The observed hang overhead was approximately 18 ms. Authorized requests
returned `200` again after policy removal and after Redis recovery.

### Failure injection, recovery and guardrails

Namespaced Kubernetes NetworkPolicies are additive allows; another such
policy cannot override the existing ingress-to-authorizer allow. The hang
therefore uses a temporary, uniquely named Admin-tier `ClusterNetworkPolicy`
from the CRD shipped by the pinned Calico installation. It denies only
istio-ingress pods reaching default-namespace ext-authz pods. It is installed
while ext-authz is at zero replicas, avoiding preexisting conntrack sessions.
There is no permanent network-policy change.

The verifier records and restores replica counts, deletes the temporary
policy, and tears down synthetic fixtures on normal completion, errors,
`INT` and `TERM`. Failed restoration retains cleanup intent for the EXIT
retry and returns nonzero. A Redis-induced ext-authz CrashLoopBackOff may need
one guarded pod replacement to reset backoff; this is test recovery, not a
service probe fix. Forced process killing or VM failure cannot run shell traps
and still needs operator recovery.

After the run, ext-authz and Redis were both **1/1**, every default-namespace
deployment and infrastructure StatefulSet was ready, no
`ClusterNetworkPolicy` remained, and `.loadtest/session-pool.txt` was absent.
Redis retained its PVC; no logical reset or migration was required.

Validation passed:

- `bash -n` and `shellcheck` for `verify-edge-contract.sh` and
  `verify-static-security-manifests.sh`.
- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python
  ./scripts/guardrails/verify-static-security-manifests.sh` and its
  `--self-test`. The three new fixtures fail for missing `statusOnError`,
  missing timeout and `failOpen: true`, respectively.
- `./scripts/guardrails/verify-production-image-overlay.sh` (offline).
- Focused shell-function fault injection proved flag retention after failed
  policy deletion/scaling, mutation refusal after a target-guard failure,
  cleanup failure producing a nonzero exit, preservation of an earlier
  failure, and TERM-triggered cleanup.
- `git diff --check`.

These are local live and offline production-reference results only. No hosted
deployment was exercised. The Redis-dependent ext-authz probe behavior stays
deferred to plan 03, Phase 2. No later phase was implemented.

## Plan 01, Phase 5 — configuration clarification required

The 2026-11-06 attempt inspected the existing Phase 1–4 changes and the
header/CSP sources before editing implementation files. The workspace
pre-agent boundary check and `./scripts/bootstrap/check-local-runtime.sh`
passed. `tilt up --stream` could not start a second instance because port
10350 was occupied; `tilt get uiresources` and process inspection confirmed
the existing `tilt up` instance and its application resources. No runtime
change was made by this attempt.

The required exact IdP logout allowance cannot be supplied consistently by
editing the three static CSP includes alone:

- `Tiltfile` supplies Session Gateway's `AUTH0_ISSUER_URI` from the local
  environment, but copies `nginx/includes/security-headers-*-csp.conf`
  verbatim into `nginx-gateway-includes`.
- `kubernetes/production/apps/kustomization.yaml` copies the same docs and
  strict includes verbatim. The offline route/egress renderer uses the
  separate reference issuer `https://auth.budgetanalyzer.org/`, documented
  in `deploy/README.md`.
- NGINX has no existing issuer variable or CSP rendering mechanism. A
  checked-in local tenant would couple both environments to one instance;
  permitting both tenants would grant an unnecessary form destination.

Proposed resolution for user decision: expand Phase 5's configuration scope
to render the exact HTTPS IdP logout allowance from `AUTH0_ISSUER_URI` for
local Tilt and from the offline reference issuer for production, including
the necessary Tilt, production ConfigMap/render wiring and focused checks.
Keep rendering offline-capable and reject wildcard or malformed CSP sources.
Do not substitute a wildcard or omit the required IdP allowance. The worker
protocol requires clarification before this unplanned configuration change.

Only this evidence section was added. No route, CSP or verifier changes were
made, and no later phase or Git write operation was performed. `git diff
--check` passed before and after this documentation update. The phase's
static gate, live edge verifiers and browser login/CSP validation remain
unrun; this attempt does not establish Phase 5 completion. Resume with the
existing Phase 4 recovery/validation record above after the configuration
scope is resolved.

## Plan 01, Phase 5 — ingress headers and environment-specific CSP

On 2026-11-06 the clarified Phase 5 scope was implemented in orchestration.
The workspace boundary and `check-local-runtime.sh` passed. `tilt up` found
the existing workspace instance on loopback port 10350; its active resources
were used, and it loaded the changed Tiltfile and applied the route/ConfigMap
updates. No certificate operations, Git writes or runner-state edits occurred.

### Implementation and render contract

- Every rule of `auth-route`, `api-route` and `app-route` sets (not adds)
  `Strict-Transport-Security: max-age=31536000`. The final value has neither
  `includeSubDomains` nor `preload`, including on the Spring auth lane.
- Every rule removes `Forwarded`, `X-Forwarded-Host`, `X-Forwarded-Port`,
  `X-Forwarded-Prefix` and `X-Forwarded-Ssl`. Existing proto handling and
  ingress-appended XFF remain intact.
- All three NGINX CSP templates omit `X-XSS-Protection` and declare one
  `form-action 'self' __IDP_LOGOUT_ORIGIN__` directive. The shared
  `deploy/scripts/render/render-csp.py` derives a validated HTTPS origin from
  the configured issuer, never a wildcard or combined tenant list.
- Tilt renders its includes from `AUTH0_ISSUER_URI`. The offline
  `production-routes.sh` now also emits `apps.yaml`, resolving the same
  templates with its `REFERENCE_AUTH0_ISSUER_URI`. Raw production apps
  kustomize output is an intermediate containing placeholders; use the
  production renderer for resolved configuration.
- `verify-edge-headers.py`, called by both static gates, checks every rule,
  all three profiles, origin normalization, malformed-issuer rejection with
  no partial stdout, and the two resolved production CSP profiles.
- The two live verifiers check final headers; the edge contract tests each
  forged forwarding field separately and together. The browser-hardening
  verifier's pre-existing `curl -k` flags were removed so all its HTTPS
  probes verify TLS normally.

The running NGINX retained its old headers after the ConfigMap and mounted
includes updated. Following the existing `nginx/README.md` reload procedure,
`check-local-runtime.sh` was repeated and `nginx -t && nginx -s reload`
loaded the repo-owned configuration. A fresh pod reads the rendered includes
on startup; an existing pod needs that documented reload after an include
change. No live-only configuration patch was used.

### Validation

- `bash -n` and `shellcheck`: passed for the changed shell scripts
  (`production-routes.sh`, both static gate scripts, and both edge verifiers).
- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python
  ./scripts/guardrails/verify-static-security-manifests.sh`: passed.
- `./scripts/guardrails/verify-production-image-overlay.sh`: passed, including
  rendered CSP checks. A separate production render with `KUBECONFIG` pointing
  to a nonexistent file also passed, proving no cluster configuration is
  required.
- `./scripts/smoketest/verify-edge-contract.sh`: **185 passed, 0 failed**.
  All authorization-failure workloads were restored and fixtures removed.
- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python
  ./scripts/smoketest/verify-edge-browser-hardening.sh`: **91 passed, 0 failed,
  0 warnings**. Its full runtime-hardening cascade passed **176/176**, including
  ingress **97/97**, credential isolation **47/47**, network-policy checks,
  transport encryption **18/18**, the frontend strict-CSP build/audit and a
  real browser callback after initiation-rate exhaustion. Both built-in
  network-policy passes completed; no regression section was skipped beyond
  the script's existing reuse of the already-run ingress rate-limit verifier.
- `git diff --check`: passed. The accepted plan SHA-256 remains
  `dd7fc8ecd74de2402271091ed6ff179d5204b766766fdb2b94db714116f3c6e1`.

| Final HTTPS response | Status | HSTS values |
| --- | --- | --- |
| `/` | 200 | One: `max-age=31536000` |
| Authenticated `/api/v1/currencies` | 200 | One: `max-age=31536000` |
| Authenticated `/auth/v1/session` | 200 | One: `max-age=31536000` |
| `/oauth2/authorization/idp` | 302 | One: `max-age=31536000` |

All six forged-header probes retained exactly
`https://app.budgetanalyzer.localhost/login/oauth2/code/idp` as `redirect_uri`.
Live development, strict smoke and docs responses each permit only `'self'`
and the local `AUTH0_ISSUER_URI` origin in `form-action`; the production
strict/docs render permits only `'self'` and `https://auth.budgetanalyzer.org`.

A separate headless Chromium check completed a real IdP login using the
existing disposable local API-test identity and default TLS verification,
verified `/auth/v1/user` returned 200, and rendered `/`, `/_prod-smoke/` and
`/api-docs`. Document-level `securitypolicyviolation` listeners recorded zero
local CSP violations, and Playwright recorded zero JavaScript page errors.
The test logged out and closed its isolated browser context without printing
or persisting credentials or cookies. The diagnostic script and logs are
under ignored `tmp/phase5-edge-headers/`; these results are the durable record.

### Handoff and limits

The owner docs are `docs/architecture/security-architecture.md` (ingress
header ownership and CSP posture), `nginx/README.md` (rendered include wiring
and reload), and `deploy/README.md` (resolved offline apps render).
Ingress-local authorization denials and 429s remain outside the ordinary
response HSTS requirement. No hosted production runtime was exercised.
Native form POST/303 logout is not implemented by this phase: plan 02.7
implements it and plan 02.8, Phase 2 must still verify its final redirect and hostile-form behavior in
the supported browsers. This phase's browser observation covers Chromium and
the current login/application flows, not that future logout contract.

## Plan 01, Phase 6 — Session Gateway Redis ACL

Session Gateway's Redis user no longer has `&* +@all`. It keeps the
`~session:* ~user_sessions:* ~oauth2:state:*` key patterns and now gets only:

```text
+hello +auth +client|setinfo +ping +info +hset +hmset +hget +hgetall +expire
+del +unlink +sadd +srem +smembers +type +evalsha +eval
```

The list is in `kubernetes/infrastructure/redis/start-redis.sh`.
`docs/development/local-environment.md#backend-services-spring-boot` documents
the command allowlist and the Redis restart that an ACL change requires.

### Derivation

The baseline was captured under the old `+@all` grant with `redis-ops`
`MONITOR`. The run included `SCRIPT FLUSH`, a Session Gateway cold restart with
probes, and a lifecycle driver run in headless Chromium with the disposable
local API-test identity. The driver covered:

- Login, user read, two heartbeat refreshes, logout, and a `401` heartbeat
  after logout.
- Two concurrent sessions, then bulk revocation through
  `DELETE /internal/v1/sessions/users/{userId}`. The request was sent from the
  permission-service pod, so it used that pod's mesh identity, and both
  sessions then returned `401`.
- An OAuth IdP-error callback with a saved state, an unknown-state callback,
  and an expired-state callback.
- A session whose `expires_at` was in the past (`401`), logout of that expired
  session, and a heartbeat with an unknown cookie.

Session Gateway issued:

- Top level: `hello` (with AUTH), `client setinfo` (lib-name and lib-ver),
  `info server` (health), `hgetall`, `hmset`, `hget`, `expire`, `del`,
  `unlink`, `srem`, `evalsha`, and `eval` (the NOSCRIPT fallback after the
  script cache was flushed).
- Inside Lua: `type`, `hset`, `sadd`, `expire`, `smembers`, `del`.

It issued no pub/sub, `SCRIPT`, `KEYS`, `SCAN` or administration commands, so
`&*` was dropped. `client` is granted only as `client|setinfo`. `ping` and
`auth` are kept as connection fallbacks, matching the ext-authz user.

`eval` lets Session Gateway run any script it sends, but Redis checks each
command inside the script against the same command and key rules, so it grants
no further authority.

### Live results

- The repo-rendered `redis-acl-bootstrap` ConfigMap was applied because the
  running Tilt session had not reloaded after the edit. Redis was then
  restarted with `kubectl rollout restart statefulset/redis -n infrastructure`,
  and `ACL GETUSER session-gateway` returned `-@all` plus the list above, with
  no channels.
- After a Session Gateway cold restart, the same lifecycle passed.
  `MONITOR` showed the NOSCRIPT-to-`EVAL` load path for all three scripts.
  `/actuator/health` reported Redis `UP`, Session Gateway logs contained no
  `NOPERM`, and `ACL LOG` had no `session-gateway` entries.
- After a further Redis restart, the lifecycle,
  `verify-session-architecture.sh` (58 passed) and
  `verify-credential-isolation.sh` (76 passed) all passed. The only
  `session-gateway` `ACL LOG` entry was the verifier's intentional
  `currency-service:*` key denial.
- `verify-credential-isolation.sh` runs the allowed commands for real,
  including `EVAL`/`EVALSHA` with `TYPE` inside Lua. `ACL DRYRUN` is used only
  for denials: `FLUSHALL`, `FLUSHDB`, `CONFIG GET`/`SET`, `SHUTDOWN`,
  `REPLICAOF`, `ACL LIST`/`SETUSER`, `KEYS`, `SCAN`, `CLIENT KILL`,
  `SCRIPT FLUSH` and `PUBLISH`. Its cross-namespace denial now uses `HGETALL`,
  so the denial comes from the key pattern and not from a missing command.
- Regression proof (diagnostic only): with `+@all` appended to the checked-in
  line, the `--static-only` session architecture check failed. With a runtime
  `ACL SETUSER session-gateway +@all`, the live session architecture check
  failed and 13 credential-isolation denials failed. Redis was then restarted
  from the checked-in script and the narrowed ACL confirmed.

### Limitations

- The existing `ext-authz` and `currency-service` clients send
  `CLIENT SETINFO`, which their users deny. This appears in `ACL LOG` but does
  not break either client. It was left unchanged because those grants are
  outside this phase, and the currency-service grant is narrowed in plan 03.
- Heartbeat invalidation for a deactivated account uses the same commands as
  logout and was not driven separately. The
  "session disappeared during heartbeat" race was not reproduced, but its Lua
  commands (`type`) are covered by the grant and the positive checks.
- An existing local cluster needs only the Redis restart above. No Redis data
  reset is required.

## Plan 01, Phase 7 — Documentation reconciliation

Documentation-only phase. Each corrected claim was checked against the source
it describes:

- CSRF: `SecurityConfig.java` in Session Gateway disables Spring Security CSRF.
  The cookie's `SameSite` defaults to `Strict` (`SESSION_COOKIE_SAME_SITE`).
- Cookie lifetime: `SessionCookieHelper` sets no `Max-Age` or `Expires`, and
  sets `Max-Age=0` only when clearing. `expires_at` is checked by ext-authz
  (`session.go`) and Session Gateway (`SessionReader`), alongside the Redis key TTL.
- Redis topology: `kubernetes/infrastructure/redis/statefulset.yaml` has
  `replicas: 1`, and the production overlay patches only storage. The session
  Lua scripts take two `KEYS` (session hash and user-session index).
- Outbox: currency-service's `MessagingEventListener` states that failed or
  interrupted publications are not resubmitted and that the startup and daily
  imports reconcile instead. No `republish-outstanding-events-on-restart`
  setting is configured. currency-service is the only Spring Modulith listener.
- Revocation: ext-authz reads Redis on each request with no session cache.
- NGINX: no `upstream`, `max_fails` or `proxy_next_upstream` configuration
  exists, so the WAF and circuit-breaking/retry claims were removed.
- Permission lookup: the heartbeat `fetchAuthorization` call has a timeout. The
  login `fetchPermissions` call has none, so the service-communication guide
  claims a timeout only for the heartbeat.

A local link and anchor check of the five edited files found no broken targets,
and `rg -n '/srv/'` on R1 finds nothing. R1's line references became `#L<n>`
anchors. They point at the reviewed revision and may drift as files change.

Deferred as planned: the "absolute expiration" claim (plan 02.4, Phase 3), the
audit-logging claims (plan 05, Phase 3) and the eviction policy (plan 04, Phase 1).

## Follow-up 2026-11-06 — `verify-edge-contract.sh` failure injection is opt-in

`verify-edge-contract.sh` now changes no Kubernetes object without
`--inject-failures`. The Authorization Failure injection cases (ext-authz
scaled to zero, the `ClusterNetworkPolicy` hang and Redis stopped), their
recovery and the guarded ext-authz pod replacement run only with that flag,
and each mutating function calls `require_inject_failures` first. The
`verify-edge-contract.sh` runs recorded above for Plan 01, Phases 4 and 5
match today's `--inject-failures` run. The earlier runs predate the
Authorization Failure section. The recorded commands are left as they were
run.

- Default run: **170 passed, 0 failed, 3 skipped**, one `[SKIP]` line per
  injection case. A snapshot of deployment and StatefulSet replicas, pod UIDs
  and restart counts, and `ClusterNetworkPolicy` objects (none) was identical
  before and after. The pool file and every `usr_loadtest_%` row in the
  `permission` database were gone afterwards.
- Negative control: a scratch copy that called `scale_ext_authz 0` from the
  default path exited 1 at `require_inject_failures`. A logging `kubectl`
  shim recorded only the target checks and no `scale`.
- `--inject-failures` run: **185 passed, 0 failed, 0 skipped**, the same count
  as the Phase 5 full run. Replicas matched before and after, no
  `ClusterNetworkPolicy` remained, and every pod was Running.

## Follow-up 2026-11-06 — `;` denied at any encoding depth

Target: local Tilt/Kind (`kind-kind`). Orchestration `HEAD` `59cdc24` plus
the uncommitted Plan 01 and review follow-up changes.

The ingress path-hardening regex changed from `^[^?]*(;|%3[bB]|%253[bB]).*$`
to `^[^?]*(;|%(25)*3[bB]).*$`, so `%25253b` and deeper forms are denied as
well. The Plan 01, Phase 3 section above records the earlier regex and its
37-probe run and is left as it was run.

- Static guardrail: the scan now also requires denial of `%25253b`,
  `%25253B` and `%2525253b` and admission of `/api/v1/transactions%2533` and
  `/api/v1/transactions%25`. The new
  `ingress-path-hardening-double-encoded-only.yaml` fixture carries the old
  regex and is rejected only for the three deeper forms. The allow-action,
  literal-only and missing fixtures still fail for their own reasons. The
  static suite, `--self-test` and `verify-production-image-overlay.sh` pass.
- Config dump: after Tilt reapplied `istio-ingress-routes`, the live ingress
  listener's `envoy.filters.http.rbac.ingress_path_hardening` filter carries
  `^[^?]*(;|%(25)*3[bB]).*$` and still sits before `ext_authz`.
- Default `./scripts/smoketest/verify-edge-contract.sh`: **190 passed, 0
  failed, 3 skipped**. The 20 extra passes over the previous default run's
  170 are the 16 probes and the four session-survival checks for the
  `%25253b` and `%25253B` forms. The Semicolon Rejection section sent **53**
  probes (20 NGINX-lane `GET`; 20 `GET` and 13 `DELETE` on the direct `/auth/*`
  lane), each a `403` `RBAC: access denied`. Ingress `rbac.denied` rose by
  exactly 53. Neither sidecar recorded a request from the ingress, NGINX
  logged no probe, the seeded session survived every `DELETE`, and a query
  string `;` still returned `200` on both lanes.
- Mixed encodings: HCM `normalize_path` decodes percent-encoded unreserved
  characters before the filter runs. One-off probes of `%253%62`, `%25%33b`,
  `%25%33%62` and `%2%35%33b` were each a `403` `RBAC: access denied`, and
  NGINX logged none of them. The near miss `%2533b`, which decodes to `3b`,
  reached the frontend shell as expected.

## Plan 02.1, Phase 3: OAuth Callback Browser Binding

Date: 2026-11-07, approximately 08:34–08:37 UTC. Target: local Tilt/Kind
`kind-kind`, exact origin `https://app.budgetanalyzer.localhost`, disposable
primary API-test credentials. No hosted production runtime was exercised.

### Runtime provenance and prerequisites

- Workspace pre-agent boundary check passed with the configured worktree and
  bare-repository parents. `./scripts/bootstrap/check-local-runtime.sh` passed
  the local Docker, exact loopback Kubernetes authority and Ready Kind checks.
- `tilt up --stream` refused a second listener on port 10350. Inspection of the
  existing Tilt API confirmed it already owned this checkout's `Tiltfile`;
  Session Gateway and its compile resource were ready/up-to-date without
  pending work. The running stack was reused, with no second Tilt instance.
- Running image: `session-gateway:tilt-546b072f6662a879`. Tilt's latest Gateway
  update completed at 08:32:12 UTC, after Phase 1. The running `/app/app.jar`
  and current sibling `build/libs/session-gateway-0.0.1-SNAPSHOT.jar` had the
  identical SHA-256
  `e6820dc5db8c808cf9d379b2fa370a954cece8eb3aeead6f98a970acb1bf7477`.
  This checks the actual live-updated artifact, not merely the image tag.
- Phase 1's implementation/test evidence is in
  [Session Gateway's evidence file](../../../session-gateway/docs/research/security-consensus-hardening-evidence.md).
  Phase 2's cookie-preserving helper regressions are in
  [API tests' evidence file](../../../budget-analyzer-api-tests/docs/research/security-consensus-hardening-evidence.md).

### Unused callback proof

Added `scripts/smoketest/verify-oauth-browser-binding.py`. It verifies the
host-only binding cookie's Secure, HttpOnly, SameSite=Lax and Path=/ metadata,
then drives the hosted login in a fresh Chromium context. Chromium's Fetch
request-stage interception pauses the callback before it reaches the Gateway.
An independent HTTP client with no copied cookies or browser headers delivers
that unused code/state first. Only after checking its rejection does the
verifier resume the original cross-site browser request.

| Probe | Live result |
| --- | --- |
| Unused callback without binding | `302` to local `/login?error=auth_failed`; no session cookie issued |
| Unbound client's `/auth/v1/user` and `/auth/v1/session` | Both `401` |
| Same callback resumed in the initiating browser | Login succeeded and issued the session cookie |
| Authenticated user read and heartbeat | Both `200` |
| Authenticated logout | `302` or `303`, as required by the verifier |

The positive use of the **same** callback proves the unbound rejection was not
caused by a stale/consumed code or state and did not consume the legitimate
transaction. Resuming the original navigation also proves real cross-site
SameSite=Lax delivery; the binding is never manually injected into Chromium.
No cookie, state, authorization-code or credential values were recorded.

An initial harness attempt used Playwright routing, which did not intercept
the redirect hop and correctly failed its interception-count assertion. That
run is not binding evidence. The final verifier uses Chromium Fetch instead;
no service fix or orchestration deployment workaround was needed.

### Validation

All required gates passed:

- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python ./scripts/guardrails/verify-static-security-manifests.sh`
- `./scripts/guardrails/verify-production-image-overlay.sh` (offline reference)
- `../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-oauth-browser-binding.py`
- `../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-ingress-browser-callback.py`:
  initiation exhausted; original callback, user read, heartbeat and logout
  still completed in a fresh browser login.
- `./scripts/smoketest/verify-session-architecture.sh`: **58 passed, 0 failed**;
  live session keys observed.
- API-test `.venv/bin/ruff check --extend-select E402` and `ruff format --check`
  on the new verifier; `git diff --check`.

No shell scripts changed, so `bash -n` and ShellCheck had no changed-script
inputs. Updated the canonical browser session contract, security summary and
script catalog. Existing unbound in-flight OAuth transactions require fresh
login; no Redis reset was needed for these fresh transactions. The live proof
covers missing binding and successful login in Chromium; malformed/mismatched
bindings, duplicate cookies, races and parallel-tab behavior retain Phase 1's
service-test evidence. It makes no claim about other browser engines or a
hosted environment. No sibling files, runner-owned records, plan snapshot,
TLS material or Git history were changed.

## Plan 02.2, Phase 3: Configured IdP Redirect URI and Live Login Input

Date: 2026-11-07, approximately 09:21–09:40 UTC. Target: local Tilt/Kind
`kind-kind`, exact origin `https://app.budgetanalyzer.localhost`, disposable
primary API-test credentials (role `USER`). No hosted production runtime was
exercised.

### Change

- `IDP_REDIRECT_URI` is now part of `ConfigMap/session-gateway-idp-config`:
  checked in at `kubernetes/services/session-gateway/idp-configmap.yaml`,
  rendered by the Tiltfile from `.env` (optional, default
  `https://app.budgetanalyzer.localhost/login/oauth2/code/idp`) and listed as a
  required environment-specific key in `kubernetes/production/README.md`. The
  value equals the Auth0 Allowed Callback URL and what `{baseUrl}` produced
  through ingress before the change.
- Updated the session-edge owner doc, Auth0 setup, config inventories and
  `.env.example`.

### Runtime provenance

- `./scripts/bootstrap/check-local-runtime.sh` passed. The existing Tilt
  session for this checkout reloaded the Tiltfile at 09:21:44 UTC and applied
  the ConfigMap with the new key.
- Session Gateway image `session-gateway:tilt-43399c500c4104eb`. The running
  `/app/app.jar` and the sibling `build/libs/session-gateway-0.0.1-SNAPSHOT.jar`
  had the identical SHA-256
  `d50359eb74c0de5312b7538208ab9901bc5cb14462670d56ef28c50a1b93b323`. That jar
  was built at 09:11:17 UTC; no Session Gateway source was modified after
  09:10:30 UTC. Its `application.yml` contains the
  `${IDP_REDIRECT_URI:{baseUrl}/...}` default and the 600-second OAuth state TTL.
- The frontend Vite pod's synced `LoginPage.tsx` and `loginRedirect.ts` had the
  same SHA-256 as the `budget-analyzer-web` worktree files.
- **Existing-cluster step:** `envFrom` is read only at container start, and
  Tilt does not restart Session Gateway when this ConfigMap changes. The pod
  running at 09:21 lacked `IDP_REDIRECT_URI`. After the `kind-kind` checks,
  `kubectl rollout restart deployment/session-gateway` produced a pod that
  reports the configured value. A fresh `tilt up` needs no restart. No Redis or
  database reset was needed.

### Live results

| Probe | Result |
| --- | --- |
| Deep link `/analytics?probe=deep-link` via the SPA's authenticated route, then hosted login | Returned to `/analytics?probe=deep-link` (the page then appends its own `year` default); user read `200`; logout ok |
| `/oauth2/authorization/idp?returnUrl=%2F%5Cevil.com`, then hosted login | Landed on `https://app.budgetanalyzer.localhost/`; user read `200` |
| Authenticated SPA `/login?returnUrl=%2F%5Cevil.com` | Stayed on the app origin at `/`, the `USER` default page |
| Control: authenticated SPA `/login?returnUrl=%2Fanalytics` | Followed to `/analytics` |
| `redirect_uri` on every observed IdP `/authorize` request | Exactly `https://app.budgetanalyzer.localhost/login/oauth2/code/idp` |
| Direct pod request with `Host` and `X-Forwarded-Host: spoofed.example`, `X-Forwarded-Proto: http` | `302` to the IdP with `redirect_uri=https://app.budgetanalyzer.localhost/login/oauth2/code/idp` |

The spoofed-header probe discriminates: request-derived `{baseUrl}` would have
produced `http://spoofed.example/...`, so the callback now comes from
configuration. The browser probes used a one-off Playwright script outside the
repository, built on the API-test helpers. It printed no cookie, state, code or
credential values.

### Validation

- Orchestration static gate:
  `verify-static-security-manifests.sh` (pinned PyYAML interpreter) and
  `verify-production-image-overlay.sh` passed. No shell scripts changed, so
  `bash -n` and ShellCheck had no inputs.
- `./scripts/smoketest/verify-session-architecture.sh`: **58 passed, 0 failed**.
- `../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-ingress-browser-callback.py`:
  passed; initiation was exhausted and the original callback, user read,
  heartbeat and logout still completed.

### Limitations

- No `ADMIN` credential was exercised live. The `/admin` default for an unsafe
  `returnUrl` rests on the frontend unit test.
- The 2048-character cap and the other rejected `returnUrl` forms rest on
  Session Gateway's service tests; see
  [its evidence](../../../session-gateway/docs/research/security-consensus-hardening-evidence.md),
  section "Plan 02.2, Phase 1".
- No claim about a hosted environment. A deployment must set
  `IDP_REDIRECT_URI` to its own registered callback URL.

## Plan 02.3, Phase 3: Login Permission Sync Mesh Rule and Live Login

Date: 2026-11-07, approximately 10:05–10:12 UTC. Target: local Tilt/Kind
`kind-kind`, exact origin `https://app.budgetanalyzer.localhost`, disposable
API-test identities. No hosted production runtime was exercised.

### Change

- `permission-service-policy` in `kubernetes/istio/authorization-policies.yaml`
  now admits the Session Gateway identity with exactly two operations:
  `POST /permission-service/internal/v1/users/sync` and
  `GET /permission-service/internal/v1/users/{*}/authorization`. The old
  `GET .../users/{*}/permissions` entry is gone.
- `scripts/smoketest/verify-session-architecture.sh` now requires
  Session Gateway's `PermissionServiceClient` to use `/internal/v1/users/sync`
  and no `/permissions` path. It also requires the Session Gateway rule's `to`
  block to equal those two operations exactly. Extracting the rule from the
  previous policy produces a different block, so the old policy would fail.
- Step 2's search found no other active consumer of the old path. The
  `verify-edge-contract.sh` and `verify-nginx-shared-routes.sh` references are
  traversal targets on the still-valid `/authorization` path. The other scripts
  named in the plan refer only to the `permission-service-policy` name. None of
  them needed to change.
- Owner docs updated: `security-architecture.md` (mesh boundary and Session
  Gateway responsibilities), `session-edge-authorization-pattern.md` (new login
  user sync paragraph and mesh sentence) and `service-communication.md` (the
  bounded synchronous call example). The service contracts live in
  session-gateway `docs/session-configuration.md#login-user-sync` and
  permission-service `docs/authorization-model.md#internal-authorization-lookups`.

### Runtime provenance

- `./scripts/bootstrap/check-local-runtime.sh` passed, and so did the
  `kind-kind` context, loopback API, `kind` cluster and Ready node checks. The
  existing Tilt session for this checkout applied the new policy at 10:05:33
  UTC; the live object shows only the two operations.
- `session-gateway:tilt-eb722a1d6389d416`: the running `/app/app.jar` and the
  sibling `build/libs/session-gateway-0.0.1-SNAPSHOT.jar` have the same SHA-256
  `6f4c9212…f16916`. The jar was built at 10:03:45 UTC, and the newest main
  source was written at 10:02:20 UTC.
- `permission-service:tilt-76090031780c2eea`: the running jar and the sibling
  build have the same SHA-256 `f3577d07…0141d`. The jar was built at 09:59:03
  UTC, and the newest main source was written at 09:58:05 UTC.

### Mesh probes from the Session Gateway identity

These requests were sent with `wget` from the `session-gateway` container
through its sidecar. The counters are the permission-service sidecar's
`inbound_0.0.0.0_8086` RBAC counters.

| Request | Status | RBAC counter |
| --- | --- | --- |
| `GET .../internal/v1/users/usr_probe/permissions` (old login path) | `403` | `denied` +1 |
| `GET .../internal/v1/users/sync` (wrong method) | `403` | `denied` +1 |
| `POST .../internal/v1/users/usr_probe/authorization` (wrong method) | `403` | `denied` +1 |
| `POST .../internal/v1/users/sync` with body `{}` | `400` (application validation) | `allowed` +1 |
| `GET .../internal/v1/users/usr_probe/authorization` | `404` (unknown user) | `allowed` +1 |

### Live logins

The logins used real hosted login through Chromium. The driver was a one-off
Playwright script outside the repository, built on the API-test helpers. It
printed no cookie, state, code or credential values.

| Identity | Result |
| --- | --- |
| Existing primary (`USER`) | Callback `302` to `/`. `BA_SESSION` is HttpOnly and Secure. `/auth/v1/user` `200` with roles `USER` and 9 permissions. Heartbeat `200` |
| Existing admin | Callback `302` to `/admin`. Roles `USER, ADMIN` and 18 permissions, including `users:*` and `*:any`. Heartbeat `200` |
| Consumed, still-`DEACTIVATED` disposable identity (`…20261107T093518Z_D5CB4416…`) | Ended on `/oops` with no `BA_SESSION`. Session Gateway logged `PermissionServiceException` after the sync call |
| Same identity after its local row was hard-deleted (new user) | Callback `302` to `/`. A new row `usr_34cb…` was created as `ACTIVE` with default role `USER`. The session has the 9 `USER` permissions. Heartbeat `200` |
| Same identity logged in again (now existing) | Same row reused; no duplicate. Session has the same grants |

**Local data reset:** the new-user case hard-deleted one consumed deactivation
identity's `permission.users` row; it had no `user_roles`. The sync rejects any
`idp_sub` that has a `DEACTIVATED` row, even a soft-deleted one, so a
soft-delete would not work. That identity is now an `ACTIVE` `USER`. Existing
clusters need no other reset for this phase.

### Validation

- `bash -n` and ShellCheck on `verify-session-architecture.sh`: clean.
- `verify-static-security-manifests.sh` (pinned PyYAML interpreter): passed.
- `verify-production-image-overlay.sh`: passed.
- `./scripts/smoketest/verify-session-architecture.sh`: **61 passed, 0 failed**
  (live).
- `./scripts/smoketest/verify-istio-ingress.sh`: **97 passed (out of 97)**.
- `./scripts/smoketest/verify-edge-contract.sh`: passed, 0 failed, 3 skipped.
  The skipped cases are the opt-in `--inject-failures` cases, which were not
  run.

### Limitations

- `kubernetes/production` still pins Session Gateway 0.0.15, which calls the
  removed `GET .../permissions` path. This shared policy denies it. The release
  and pin update is human-owned and is recorded in plan 05, Phase 3; see the
  plan's cutover rule.
- No checked-in verifier sends live requests to test this internal rule. The
  table above comes from a one-off probe. `verify-network-policies.sh` proves
  only TCP reachability.
- No claim about a hosted environment.

## Plan 02.4, Phase 3: Absolute Session Lifetime Configured and Proven Live

Date: 2026-11-07. Target: local Tilt/Kind (`kind-kind`) only. No hosted
environment was touched.

### Change

- `kubernetes/services/session-gateway/configmap.yaml` and the Tiltfile's
  `session-gateway-config` set `SESSION_MAX_LIFETIME_SECONDS="28800"` (D1). Tilt
  applied the ConfigMap, and the production reference render
  (`kubectl kustomize --load-restrictor LoadRestrictionsNone kubernetes/production/apps`)
  carries the same key from the shared base.
- `docs/architecture/session-edge-authorization-pattern.md` has a new
  "Absolute Session Lifetime" section, a heartbeat table row and a corrected
  ADR 007 paragraph. `docs/architecture/security-architecture.md` replaces the
  unbacked "absolute expiration" claim (deferred from plan 01, Phase 7) and
  states the cap in the token and Redis descriptions.
  `docs/development/local-environment.md` lists the new ConfigMap value.
- ext-authz is unchanged (D2). `kubernetes/production` still pins Session
  Gateway 0.0.15, which ignores this setting until the human-owned release and
  pin update (plan 05, Phase 3).

### Runtime provenance

- `./scripts/bootstrap/check-local-runtime.sh` passed, and so did the
  `kind-kind` context, loopback API, `kind` cluster and Ready node checks, before
  each mutation. The Tilt session runs this checkout's Tiltfile.
- `session-gateway:tilt-131bcdb23ba37830`: the running `/app/app.jar` and the
  sibling `build/libs/session-gateway-0.0.1-SNAPSHOT.jar` have the same SHA-256
  `acafb1c8…03d55b`. The jar was built at 11:08:11 UTC, and no source is newer.
  Its `application.yml` reads `${SESSION_MAX_LIFETIME_SECONDS:28800}`.
- `budget-analyzer-web` (Vite dev server): `useSessionHeartbeat.ts` and
  `InactivityWarningModal.tsx` in the pod match the sibling worktree by SHA-256,
  and the served module contains the capped-session copy.

### Live cap proof

Diagnostic only: `kubectl set env` temporarily set `SESSION_TTL_SECONDS=120`
and `SESSION_MAX_LIFETIME_SECONDS=1080` on the Session Gateway deployment.
Session Gateway refuses a maximum below the TTL, so both were shortened. The
scaled cap (18 minutes) exceeds Auth0's 15-minute idle lifetime, as 8 hours
does. The overrides were removed afterwards. The deployment has no explicit
`SESSION_*` env entries, and the pod reads `900` and `28800` from the
ConfigMap. No checked-in file held the short values.

The driver was a one-off Playwright script outside the repository, built on the
API-test helpers. It logged in the existing primary (`USER`) identity through
real hosted login in Chromium, left the SPA so its heartbeat hook could not log
out, and sent a heartbeat and `GET /api/v1/transactions` every 60 seconds. It
printed no cookie, state, code or credential values. Times are seconds after
the callback returned (`t0`).

| t | Heartbeat | `expiresAt - t0` | Sliding `t + TTL` | API |
| --- | --- | --- | --- | --- |
| 0 | `200` | 120 | 120 | `200` |
| 60-901 (15 samples) | `200` | `t + 120` | `t + 120` | `200` |
| 961 | `200` | **1080** (clamped) | 1081 | `200` |
| 1021 | `200` | **1080** (58 s left) | 1141 | `200` |
| 1081 | `401`, cookie cleared with `Max-Age=0` | - | 1201 | `401`; `/auth/v1/user` `401` |

- The heartbeat stopped advancing `expiresAt` at the cap, and ext-authz
  rejected the API at the cap without reading `created_at` (D2).
- The Redis key expired at the cap, so the `401` at 1081 s was the
  missing-session path. Phase 1's integration tests cover the "no lifetime
  remaining" branch.
- Re-login at 1081 s in the same browser context, which still held Auth0's
  cookies from the first login, landed on the hosted Auth0 page with a
  password prompt. Heartbeats did not renew Auth0's idle lifetime. Completing it
  created a different session; its heartbeat returned `200`, and logout `302`.

### Validation

- No shell script changed.
- `verify-static-security-manifests.sh` (pinned PyYAML interpreter): passed.
- `verify-production-image-overlay.sh`: passed.
- `./scripts/smoketest/verify-session-architecture.sh`: **61 passed, 0 failed**.
- `./scripts/smoketest/verify-edge-contract.sh`: **190 passed, 0 failed, 3
  skipped**. The skipped cases are the opt-in `--inject-failures` cases.
- All Tilt resources were `ok` afterwards. `git diff --check` was clean.

### Limitations

- The full 8-hour value was not exercised live; the proof used a scaled cap
  through the same code path.
- The frontend's capped modal was not driven in a browser. TTL 120 equals the
  default 120-second warning window, so the scaled run cannot show it; the
  frontend unit tests cover it.
- No existing local cluster needs a reset. Sessions created before this change
  get the cap at their next heartbeat.
- No claim about a hosted environment.

## Plan 02.5, Phase 3: Hashed Session Keys Wired Into Orchestration

Date: 2026-11-07. Static work only: no stack was running for this phase, and no
cluster was touched. The live cutover proof belongs to the plan's Live phase.

### Change

- `scripts/lib/redis-cli.sh` adds `session_digest_for` (lowercase hex SHA-256
  of the token through `sha256sum`, or `shasum -a 256`) and `session_key_for`
  (`session:` plus that digest). `scripts/lib/loadtest-common.sh` sources it.
- `seed-ext-authz-session.sh` writes `session:<digest>` for its cookie-value
  argument. `seed-loadtest-users.sh` writes `session:<digest>` hashes and bare
  digest `user_sessions:` members; the pool file keeps the raw cookie tokens.
- `teardown-loadtest.sh` no longer scans `session:loadtest_*`, which cannot
  match hashed keys. It reads the members of the synthetic
  `user_sessions:usr_loadtest_*` indexes, unlinks `session:<member>` and
  reports the number Redis actually deleted.
- `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh` and
  `verify-edge-contract.sh` build and inspect digest keys and members.
  `verify-istio-ingress.sh` needed no change: it seeds through
  `seed-ext-authz-session.sh` and sends the raw cookie.
- `verify-session-architecture.sh` statically checks that Session Gateway
  (`SessionTokenDigest`, `SessionReader`, `SessionWriter` and the digest test),
  ext-authz (`session.go` and `session_test.go`) and orchestration's
  `session_key_for` use the same derivation and golden vector
  (`3f2504e0-4f89-41d3-9a0c-0305e82c3301` to
  `session:16362f566387b3cf5a6e92fb0a986c76ca20eb3a0c12cbdfbd0b29501e0c18df`).
  Its live checks now fail on any `session:*` key that is not a 64-character
  hex digest key and point to `./scripts/ops/flush-redis.sh`.
- The session key descriptions and cookie-value lookup commands in the
  session-edge pattern, security architecture, `SECURITY.md`, Tilt debugging
  runbook, local environment, GCP history and session benefits docs now use
  `session:{sha256(token)}`.

### Validation

- `bash -n` and `shellcheck` (with and without `-x`) on the ten changed
  scripts: clean.
- `verify-static-security-manifests.sh` (pinned PyYAML interpreter): passed.
- `verify-production-image-overlay.sh`: passed.
- `./scripts/smoketest/verify-session-architecture.sh --static-only`:
  **60 passed, 0 failed**.

### Limitations

- No live run in this phase. The seeders, teardown and verifiers were checked
  offline only, until the Live phase brings up the stack.
- An existing local cluster must run `./scripts/ops/flush-redis.sh` after
  cutover. Raw-key sessions become unreachable, and the new live check fails
  until they are gone.
- `kubernetes/production` still pins Session Gateway 0.0.15 and ext-authz
  0.0.16, which use raw keys. The release and pin update is human-owned under
  plan 05, Phase 3.

## Plan 02.5, Phase 4: Hashed Session Keys Cut Over and Proven Live

Date: 2026-11-07. Live phase against the running Tilt/Kind stack (`kind-kind`,
loopback HTTPS API server, no kubeconfig proxy, `kind-control-plane` Ready;
`check-local-runtime.sh` passed). Disposable local API-test identity only. No
cookie, token or credential value was printed or recorded; every Redis, AOF and
log check below reports a boolean or a count.

### Runtime provenance

- Session Gateway: the pod's `/app/app.jar` has the same SHA-256 as
  `../session-gateway/build/libs/session-gateway-0.0.1-SNAPSHOT.jar`, built
  after the last source change and containing `SessionTokenDigest`.
- ext-authz: the running `ext-authz:tilt-16b7bc67308afe25` image was built
  after the last `../ext-authz/session.go` change, and its binary exports
  `main.sessionKey` and `crypto/sha256.Sum256`.

### Cutover finding and fix

Before the flush, the live keyspace held no `session:*` keys, but the
append-only file on the `redis-data-redis-0` PVC held 265 distinct raw-UUID
`session:<token>` key names from before the cutover. Its incremental file had
never been rewritten. Running the original `./scripts/ops/flush-redis.sh`
(`FLUSHALL` only) left all 265 on disk, because `FLUSHALL` only appends to the
AOF.

`scripts/ops/flush-redis.sh` now follows `FLUSHALL` with `BGREWRITEAOF`. It
waits until `INFO persistence` reports no rewrite in progress or scheduled and
`aof_last_bgrewrite_status:ok`, and otherwise exits non-zero. After the
rewrite, the AOF manifest moved to sequence 2 with an empty base and an empty
incremental file, and 0 raw-UUID session keys remained on disk. The owner line
in `docs/development/local-environment.md` and the cutover note in
`docs/runbooks/tilt-debugging.md` describe the rewrite.

### Live session proof

The flow ran through the public ingress with the harness's primary disposable
identity: hosted browser login, `GET /api/v1/transactions`, the
`GET /auth/v1/session` heartbeat and `GET /logout`. The script stayed outside
the repositories. The digest is the lowercase hex SHA-256 of the cookie value.

| Stage | Result |
| --- | --- |
| Login | `BA_SESSION` issued; exactly one `session:*` key, equal to `session:<digest>`; digest is the `user_sessions:` member |
| After login | raw token in key names, index members or hash values: no; raw token in AOF or RDB: no; digest key in AOF: yes (positive control) |
| API call | `GET /api/v1/transactions` -> 200 (ext-authz resolved the hashed key; it was the only session key) |
| Heartbeat | `GET /auth/v1/session` -> 200; same absence results as after login |
| Logout | `GET /logout` -> 302; digest key and index member removed; raw token still absent from AOF and RDB |
| After logout | API -> 401, heartbeat -> 401 |
| Logs | raw token in the last 10 minutes of `session-gateway` or `ext-authz` logs: no |

After all the verifiers below had run, the AOF written since the rewrite held
11 distinct digest session keys, 0 non-digest `session:` keys and 0 raw-UUID
keys. The only live sessions left were two `test-user-001` fixtures from
`seed-ext-authz-session.sh`. Both are digest-keyed and expire after 900 seconds.

### Validation

- `bash -n` and `shellcheck` (with and without `-x`) on
  `scripts/ops/flush-redis.sh`: clean.
- `verify-static-security-manifests.sh` (pinned PyYAML interpreter): passed.
- `verify-production-image-overlay.sh`: passed.
- `verify-session-architecture.sh`: **81 passed, 0 failed**, including the
  cross-repo derivation and golden-vector checks and "every live session:* key
  is a SHA-256 digest key".
- `verify-istio-ingress.sh`: **97 passed (out of 97)**, including the nested
  focused rate-limit verifier (33 checks).
- `verify-ingress-rate-limits.sh`: the first standalone run passed every
  section up to the browser callback proof. There, the hosted-login navigation
  timed out after 30 seconds waiting for `networkidle` on the app origin. A
  rerun 20 seconds later passed all **33 checks**, including the real browser
  callback, user read, heartbeat and logout. The same proof had also passed
  inside `verify-istio-ingress.sh`. Treated as transient, not a hashed-key
  defect.
- `verify-credential-isolation.sh`: **76 passed (out of 76)**.
- `verify-edge-contract.sh --inject-failures`: **205 passed, 0 failed,
  0 skipped**. The seeded `loadtest_1` digest session reached
  currency-service (200). The ext-authz-zero, ext-authz-hang (1.01 s) and
  Redis-stopped cases returned an empty 503 against the new ext-authz session
  lookup. `teardown-loadtest.sh` removed the fixture, and ext-authz and Redis
  were restored to 1/1 Ready.

### Limitations

- Key names remain visible metadata to Redis operators (contested decision 2).
  Session digests remain in AOF history until the next rewrite, as accepted
  metadata.
- `kubernetes/production` still pins Session Gateway 0.0.15 and ext-authz
  0.0.16, which use raw keys. The release and pin update is human-owned under
  plan 05, Phase 3. No production environment exists.

## Plan 02.6, Phase 5: `__Host-BA_SESSION` Wired Into Orchestration

Date: 2026-11-07. Static work only: no stack was running for this phase, and no
cluster was touched. The live cutover proof belongs to the plan's Live phase.

### Change

- `kubernetes/services/ext-authz/deployment.yaml` sets
  `SESSION_COOKIE_NAME=__Host-BA_SESSION`. No orchestration session-gateway
  manifest or Tiltfile entry set the cookie name or
  `SESSION_COOKIE_DOMAIN_OVERRIDE`, so none needed a change (D4).
- Scripts that build a `Cookie` header from a seeded token now send
  `__Host-BA_SESSION`: `verify-edge-contract.sh`,
  `verify-credential-isolation.sh`, `verify-ingress-rate-limits.sh`,
  `verify-istio-ingress.sh` and `verify-nginx-backend-headers.sh`. The
  `seed-ext-authz-session.sh` comment and `scripts/README.md` name the new
  cookie. The Python browser verifiers read `session_cookie_name` from the
  api-tests environment, which plan 02.6 Phase 4 already updated.
- `verify-session-architecture.sh` already compared the Session Gateway and
  ext-authz defaults with each other; it now expects `__Host-BA_SESSION` for
  both defaults and the deployment (static and live). It also fails if Session
  Gateway `application.yml`, `kubernetes/` or the `Tiltfile` mention
  `SESSION_COOKIE_DOMAIN_OVERRIDE`.
- The session-edge pattern, security architecture, `SECURITY.md`, Tilt
  debugging runbook, local environment and GCP history docs use the new name.
  The session-edge pattern and security architecture describe the `__Host-`
  attributes (`Secure`, `Path=/`, no `Domain`) and the HTTPS requirement.

### Validation

- `bash -n`, `shellcheck` and `shellcheck -x` on the seven changed scripts:
  clean.
- `verify-static-security-manifests.sh` (pinned PyYAML interpreter): passed.
- `verify-production-image-overlay.sh`: passed.
- `verify-nginx-backend-headers.sh`: 7 passed, 0 failed.
- `./scripts/smoketest/verify-session-architecture.sh --static-only`:
  **62 passed, 0 failed**.

### Limitations

- No live run in this phase.
- An existing local cluster needs no migration. Browsers holding the old
  `BA_SESSION` cookie get `401` and sign in again; `./scripts/ops/flush-redis.sh`
  discards the orphaned sessions instead of waiting for their TTL.
- `kubernetes/production` still pins Session Gateway 0.0.15 and ext-authz
  0.0.16, which use `BA_SESSION`, while the shared ext-authz manifest now sets
  `__Host-BA_SESSION`. The release and pin update is human-owned under plan 05,
  Phase 3. No production environment exists.

## Plan 02.6, Phase 6: `__Host-BA_SESSION` Cut Over and Proven Live

Date: 2026-11-07. Live phase against the local Tilt/Kind stack. The
`kind-kind` checks passed: current context `kind-kind`, loopback HTTPS API
authority with no proxy override, the `kind` cluster, and a Ready
`kind-control-plane`. `./scripts/bootstrap/check-local-runtime.sh` passed. No
cookie, token, authorization-code or state value was printed or recorded.

### Runtime provenance

- Session Gateway: `session-gateway:tilt-30f9df2288c3e7ad`. The `/app/app.jar`
  in the pod has the same SHA-256 as the sibling worktree's
  `build/libs/session-gateway-0.0.1-SNAPSHOT.jar`. That jar was built at
  14:44:38, after the last Session Gateway `src/main` edit at 14:43:18. The
  running process logged
  `Public session cookie contract configured: name=__Host-BA_SESSION`.
- ext-authz: `ext-authz:tilt-d047f1678c9a17e9`. Tilt fully rebuilt it at
  14:47:14, after the last sibling source edit at 14:47:01. It was redeployed
  at 14:51:45 with the Phase 5 manifest, and the live deployment sets
  `SESSION_COOKIE_NAME=__Host-BA_SESSION`.
- budget-analyzer-web: `budget-analyzer-web:tilt-f883c6771846cc73`, rebuilt at
  14:48:05 after its comment-only change.

### Live browser proof

`../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-oauth-browser-binding.py`
passed. Headless Chromium completed a hosted login with the disposable primary
credentials. The verifier then read the browser's cookie by the api-tests
`session_cookie_name` (`__Host-BA_SESSION`), and the user read, heartbeat and
logout passed.

A one-off probe used the api-tests venv and helpers and lived in a temporary
directory outside the repositories. It printed only cookie names and
attributes:

| Step | Result |
| --- | --- |
| api-tests `session_cookie_name` | `__Host-BA_SESSION` |
| OAuth callback `302` `Set-Cookie` | `__Host-BA_SESSION=<value>; Path=/; Secure; HTTPOnly; SameSite=Strict`. No `Domain`, no `Max-Age` or `Expires` |
| Stored in Chromium | domain `app.budgetanalyzer.localhost` (host-only, no leading dot), path `/`, `secure=True`, `httpOnly=True`, `sameSite=Strict`, session cookie |
| `document.cookie` | does not expose the session cookie |
| Browser `GET /api/v1/currencies` | `200` |
| Browser heartbeat `GET /auth/v1/session` | `200` |
| `/logout` `302` `Set-Cookie` | `__Host-BA_SESSION=; Max-Age=0; Expires=<past>; Path=/; Secure; HTTPOnly; SameSite=Strict` |
| Browser cookies after logout | no `__Host-BA_SESSION`, `BA_SESSION` or `SESSION` |
| Browser `GET /auth/v1/user`, `GET /api/v1/currencies` after logout | `401`, `401` |

Chromium stores a `__Host-` cookie only when it has `Secure`, `Path=/` and no
`Domain`, so the stored cookie is a second proof of the prefix requirements. No
`BA_SESSION` or `SESSION` cookie appeared at any step.

The old name is inert. A session seeded with
`./scripts/ops/seed-ext-authz-session.sh` and sent through the HTTPS ingress
with normal TLS verification returned `401` as `BA_SESSION=<id>` and `200` as
`__Host-BA_SESSION=<id>`. The probe key was deleted afterwards.

Observation, not a cutover defect: the `/logout` `302` points to the
configured Auth0 tenant. Headless Chromium reports `net::ERR_ABORTED` on that
cross-site hop and stays on the application origin. The application-side
logout contract held: the cookie was cleared and later reads returned `401`.

### Validation

- Orchestration static gate: `bash -n` and `shellcheck -x` on the seven
  scripts changed in Phase 5 are clean.
  `verify-static-security-manifests.sh` (pinned PyYAML interpreter) and
  `verify-production-image-overlay.sh` passed.
- `./scripts/smoketest/verify-session-architecture.sh` (static and live):
  **83 passed, 0 failed**. This includes the matching Session Gateway and
  ext-authz `__Host-BA_SESSION` defaults, the live ext-authz deployment value
  and the absence of `SESSION_COOKIE_DOMAIN_OVERRIDE`.
- `./scripts/smoketest/verify-istio-ingress.sh`: **97 passed (out of 97)**,
  including the nested focused rate-limit proof.
- `./scripts/smoketest/verify-ingress-rate-limits.sh` (standalone): **33
  checks passed**.
- `./scripts/smoketest/verify-credential-isolation.sh`: **76 passed (out of
  76)**.
- `./scripts/smoketest/verify-edge-contract.sh` (no flags): **190 passed, 0
  failed, 3 skipped**. The NGINX-lane cases send the seeded
  `__Host-BA_SESSION` cookie through `ext_authz`.

### Limitations

- `verify-edge-contract.sh` ran without `--inject-failures`. The three
  plan 01 failure cases were skipped: ext-authz scaled to zero, ext-authz
  unreachable, and Redis stopped. This run is not full edge-contract coverage.
- The api-tests live suite was not run from this repository. The api-tests
  configuration was exercised through the browser verifier and the probe.
- Existing local browsers that hold `BA_SESSION` get `401` and sign in again.
  `./scripts/ops/flush-redis.sh` discards orphaned sessions sooner than their
  TTL. No other reset is needed.
- `kubernetes/production` still pins Session Gateway 0.0.15 and ext-authz
  0.0.16, which use `BA_SESSION`. The release and pin update is human-owned
  under plan 05, Phase 3. No production environment exists.

## Plan 02.7, Phase 4: POST Heartbeat And Logout Proven Live

Date: 2026-11-07. Live phase against the local Tilt/Kind stack. The
`kind-kind` checks passed before every cluster mutation, and
`./scripts/bootstrap/check-local-runtime.sh` passed. No cookie, token,
authorization-code or state value was printed or recorded. Sibling evidence:
Session Gateway
[Plan 02.7, Phase 1](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/research/security-consensus-hardening-evidence.md),
the frontend's
[authentication guide](https://github.com/budgetanalyzer/budget-analyzer-web/blob/main/docs/authentication.md)
and api-tests
[Plan 02.7, Phase 3](https://github.com/budgetanalyzer/budget-analyzer-api-tests/blob/main/docs/research/security-consensus-hardening-evidence.md).

### Caller changes

- `verify-edge-contract.sh`: the legitimate heartbeat, the auth-lane semicolon
  denial and the heartbeat HSTS probe use `POST /auth/v1/session`.
- `verify-istio-ingress.sh`: `require_json_denial` takes a method. The
  unauthenticated heartbeat denial is `POST /auth/v1/session`.
- `verify-ingress-rate-limits.sh`: new `probe_response_with_method`. The
  session operation after callback exhaustion is `POST /auth/v1/session`.
- `verify-ingress-rate-limit-config.sh`: the session-operations matcher cases
  use `POST` for the heartbeat and `/logout`.
- `verify-oauth-browser-binding.py`: unbound and bound heartbeats use `POST`.
  Logout is `POST /logout`, which must return `303` and pass the api-tests
  `assert_logout_redirect` contract.
- `verify-ingress-browser-callback.py`: waits for the frontend's own
  `POST /auth/v1/session` `200`, requires `405` for `GET` and `HEAD` on both
  endpoints followed by a working heartbeat and user read, then clicks the
  frontend's Logout menu item. That must send a browser `POST /logout` that
  passes `assert_logout_redirect` and leaves no session cookie.
- No change was needed in `verify-session-architecture.sh`,
  `verify-edge-browser-hardening.sh`, `verify-static-security-manifests.sh` or
  `verify-production-image-overlay.sh`. They match `/logout` and
  `/auth/v1/session` only as route paths or path-normalization fixtures, not
  by method.
- Ingress configuration: the `session-operations` rate-limit matcher in
  `kubernetes/istio/ingress-rate-limit.yaml` is a path regex with no method,
  and the ingress-to-Session Gateway `AuthorizationPolicy` lists paths
  without methods. NGINX does not route these paths. No configuration change
  was needed.

### Runtime provenance

- Session Gateway: `session-gateway:tilt-4c34223298c45e77`. The pod's
  `/app/app.jar` SHA-256 (`b6804c75…`) equals the sibling worktree's
  `build/libs/session-gateway-0.0.1-SNAPSHOT.jar`, built at 16:03:28, after
  the last `src/main` edit at 16:01:23.
- budget-analyzer-web: `budget-analyzer-web:tilt-0d03c5b1b3d47878` (16:24:30
  build). The served prod-smoke image
  `budget-analyzer-web-prod-smoke:tilt-0626734db8227818` in `nginx-gateway`
  was built at 16:09:53, after the last frontend `src` edit at 16:09:42.

### Live browser proof

`verify-ingress-browser-callback.py` passed through the real frontend and its
live CSP. A one-off probe in a temporary directory outside the repositories
repeated the flow and recorded only methods, statuses, hosts and paths:

| Step | Result |
| --- | --- |
| Frontend heartbeat | `POST /auth/v1/session` -> `200` |
| Logout menu item | form `POST /logout` -> `303` |
| Redirect hop | `GET https://<auth0-tenant>/v2/logout` -> `302` |
| Final page | `https://app.budgetanalyzer.localhost/peace` |
| CSP console violations, failed logout requests | none |
| Session cookie after logout | absent |

The current `form-action` allows the form POST and Chromium follows its
cross-site `303` to the IdP and back. Under the old GET logout, plan 02.6,
Phase 6 recorded `net::ERR_ABORTED` on the IdP hop.

### GET and HEAD rejection

A second one-off probe seeded a disposable session (300 s TTL) with
`./scripts/ops/seed-ext-authz-session.sh` and sent requests through the HTTPS
ingress with normal TLS verification:

| Request | Result |
| --- | --- |
| `GET`/`HEAD` `/auth/v1/session`, `GET`/`HEAD` `/logout` | `405` each |
| Redis key after those requests | present, `expires_at` unchanged, TTL 300 s -> 297 s |
| Form `POST /logout` | `303`, Redis key deleted |

### Validation

- Orchestration static gate: `bash -n` and `shellcheck` on the four changed
  shell scripts are clean. `verify-static-security-manifests.sh` (pinned
  PyYAML interpreter), `verify-production-image-overlay.sh` and
  `verify-ingress-rate-limit-config.sh` passed.
- `verify-session-architecture.sh`: **83 passed, 0 failed**.
- `verify-istio-ingress.sh`: **97 passed (out of 97)**, including the nested
  focused rate-limit proof (**33 checks passed**) with the POST heartbeat after
  callback exhaustion.
- `verify-edge-contract.sh` (no flags): **190 passed, 0 failed, 3 skipped**.
- `verify-edge-browser-hardening.sh`: **91 passed, 0 warnings**, including the
  nested rate-limit verifier and the runtime-hardening regression cascade
  (176 of 176).
- `../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-oauth-browser-binding.py`
  and `../budget-analyzer-api-tests/.venv/bin/python scripts/smoketest/verify-ingress-browser-callback.py`:
  passed.

### Run interruption and cleanup

An earlier attempt at this phase was interrupted inside the
runtime-hardening cascade, so its traps never ran. It left behind
`verify-network-policies.sh` `np2-*` probe pods and Services,
`verify-transport-encryption.sh` `phase4-*` client pods and the namespace
`ba-phase5-psa-1794068876`. `np2-istio-ingress` carries the ingress gateway
label, so it joined the ingress Service. That made the first
`verify-edge-contract.sh` rerun fail with status `000` on some requests. The
leftovers were deleted the same way those verifiers clean up, and every
verifier above ran after the cleanup.

### Limitations

- `verify-edge-contract.sh` ran without `--inject-failures`. Its three
  fault-injection cases were skipped, so this run is not full coverage.
- Exact-Origin ingress enforcement, hostile same-site and cross-site form
  checks, and `form-action` redirect enforcement in other browsers remain
  plan 02.8, Phase 2. Only headless Chromium was exercised.
- Local reset: browsers with a pre-change frontend bundle send GET heartbeats,
  which now return `405`. Reload the page. No Redis or database reset is
  needed.
- A namespace `ba-phase5-psa-1792397007`, 19 days old, predates this plan. It
  was left in place.

## Plan 02.8, Phase 2: Exact-Origin Ingress Rule Proven Live

Date: 2026-11-07. Live phase against the local Tilt/Kind stack (Tilt running
from this worktree, 45 resources healthy, Istio proxy `1.30.6`). The
`kind-kind` checks passed before cluster mutations, and
`./scripts/bootstrap/check-local-runtime.sh` passed. No cookie, token,
authorization-code or state value was printed or recorded. Sibling evidence:
api-tests
[Plan 02.8, Phase 1](https://github.com/budgetanalyzer/budget-analyzer-api-tests/blob/main/docs/research/security-consensus-hardening-evidence.md).
The contract is documented in
[Exact-Origin Ingress Rule](../architecture/session-edge-authorization-pattern.md#exact-origin-ingress-rule).

### Change

- `kubernetes/istio/ingress-exact-origin.yaml`: one native `DENY`
  AuthorizationPolicy on the ingress gateway. Hosts
  `app.budgetanalyzer.localhost` and `app.budgetanalyzer.localhost:*`,
  `notMethods` `GET`/`HEAD`/`OPTIONS`, condition
  `request.headers[origin]` `notValues` `https://app.budgetanalyzer.localhost`.
  Applied by Tilt's `istio-ingress-routes` resource; the production reference
  includes it and patches host and origin to `demo.budgetanalyzer.org` in
  `kubernetes/production/istio-ingress-policies`.
- Host-port finding: `Host: app.budgetanalyzer.localhost:443` is routed to the
  application (`GET /` -> `200`). Istio matches `hosts` against the whole
  `:authority`, so without the `:*` entry that form would skip the rule. The
  live matrix includes it.
- `verify-static-security-manifests.sh`: new exact-Origin contract scan on
  the local manifest and the production render. The host must equal the one
  hostname of the app, API and auth HTTPRoutes. Eight failing fixtures
  (`ingress-exact-origin-*.yaml`) cover a missing policy, `ALLOW` action, no
  hosts, wildcard hosts, a missing `:*` host, an exempted `POST`, a prefix
  origin and a Fetch Metadata exception.
- `verify-production-image-overlay.sh`: requires `ingress-exact-origin` in the
  rendered ingress policies; only that policy may carry the public hostname.
- `verify-edge-contract.sh`: new `Origin` section. The filter-chain check now
  expects Istio's RBAC filter carrying only `ingress-exact-origin` next to the
  path-hardening filter. Unsafe probes that test other controls send the
  configured Origin.
- Callers updated to send the configured Origin on unsafe methods:
  `verify-istio-ingress.sh` (`require_json_denial`),
  `verify-ingress-rate-limits.sh` (`probe_response_with_method`),
  `verify-oauth-browser-binding.py` and `verify-ingress-browser-callback.py`
  (httpx clients). The load-test seed and teardown scripts write Postgres and
  Redis directly and send no ingress requests.

### Generated configuration and live requests

`verify-edge-contract.sh` evaluated the ingress Envoy RBAC config dump with
Envoy's header semantics: it denies missing, empty, `null`, foreign, same-site,
suffixed, `http://`, `:443`, trailing-slash, repeated, Fetch-Metadata-only,
forwarded-header, `:443` Host, upper-case Host, `PUT`, `PATCH` and `DELETE`
cases, and admits the exact origin, `GET`, `HEAD`, `OPTIONS` and other hosts.

With a seeded session attached (so ext_authz admits `/api/*`), every case
below was the ingress `403` `RBAC: access denied`:

| Lane | Requests | Result |
| --- | --- | --- |
| NGINX | `POST /api/v1/transactions` x 13 cases | `403` each |
| Session Gateway | `POST /auth/v1/session` x 13 cases | `403` each |
| Session Gateway | form `POST /logout`: missing, `null`, foreign, same-site | `403` each |
| Both | `PUT`, `PATCH`, `DELETE` without Origin | `403` each |
| Both | totals | `rbac.denied` +36 for 36 probes; no NGINX or Session Gateway sidecar request; no NGINX log line |
| State | session hash, expiry, index; transaction rows | unchanged |

With the configured Origin: `POST /api/v1/transactions` -> `201`; `DELETE` of
that transaction without or with a foreign Origin -> `403`, row unchanged;
configured `DELETE` -> `204` (soft-deleted); heartbeat -> `200` (session
refreshed); form `POST /logout` -> `303`, session removed.

### Browser proof

`verify-oauth-browser-binding.py` and `verify-ingress-browser-callback.py`
passed: a real hosted login, the frontend's own `POST /auth/v1/session`
(`200`) and a click on the frontend's form-POST Logout (`303`, IdP redirect,
cookie cleared) under the live strict CSP.

A one-off headless Chromium `156.0.8078.4` probe in a temporary directory
outside the repositories logged in through the hosted IdP, stopped the
frontend tab so its heartbeats could not change the session, then loaded
hostile pages at a same-site origin (`https://attacker.budgetanalyzer.localhost`)
and a cross-site origin (`https://attacker.example`) by request interception.
Each page auto-submitted a form `POST /logout`, a form `POST /auth/v1/session`,
a `text/plain` form `POST /api/v1/transactions` carrying a JSON body, and three
`mode: "no-cors"`, `credentials: "include"` `fetch` `POST`s. Chromium's Local
Network Access check blocks those `fetch` calls before sending, because the
intercepted page counts as public and the application resolves to loopback.
That is an artifact of the local target, so the probe disabled it to exercise
the ingress rule.

| Origin | Session cookie sent | Requests | Result |
| --- | --- | --- | --- |
| Same-site | yes | form `/logout`, form heartbeat, form API, 3 `fetch` | `403` ingress denial each, no `Set-Cookie` |
| Cross-site | no (`Strict`) | form `/logout`, form heartbeat, 2 `fetch` (`/logout`, heartbeat) | `403` ingress denial each, no `Set-Cookie` |
| Cross-site | no (`Strict`) | form API, `fetch` API | `401` from ext_authz, which runs before the `DENY` |
| Both | after all submissions | Redis session fingerprint, browser cookie, `GET /auth/v1/user`, transaction list | unchanged, present, `200`, unchanged |

The same-site row shows the `Strict` limit: the cookie was attached and only
the Origin rule stopped the request. Under the cookie storage rules, a hostile
top-level `POST /logout` response could clear the cookie even when Strict
withheld it (contested issue A2; not reproduced before this change). That
response is now the ingress `403` with no `Set-Cookie`, and the cookie
survived. No
remaining safe-method response checked clears the session cookie: `GET`/`HEAD`
`/logout` and `GET /auth/v1/session` (`405`), `GET /oauth2/authorization/idp`
(`302`, sets only the binding cookie), failed callbacks (`302`), and
unauthenticated `GET /auth/v1/user`, `GET /api/v1/currencies` (`401`) and
`GET /` (`200`) send none.

`form-action` on the app page under the live CSP: a form `POST` to
`https://attacker.example` was blocked with a CSP `form-action` violation, and
a same-origin form `POST` whose (intercepted) answer was a `303` to
`https://attacker.example` was also blocked on the redirect. The frontend
logout afterwards sent `Origin: https://app.budgetanalyzer.localhost`, got
`303`, ended on `/peace`, removed the cookie and the Redis session, and
produced no CSP console violation. One probe assertion failed: its check of
the ext_authz `401` body format was wrong. The `401` status itself was
confirmed.

### Validation

- Orchestration static gate: `bash -n` and `shellcheck` clean on
  `verify-edge-contract.sh`, `verify-istio-ingress.sh`,
  `verify-ingress-rate-limits.sh`, `verify-static-security-manifests.sh` and
  `verify-production-image-overlay.sh`. `verify-static-security-manifests.sh`
  (pinned PyYAML interpreter) passed, including both exact-Origin scans, and
  its `--self-test` rejected all eight new fixtures.
  `verify-production-image-overlay.sh` passed.
- `verify-edge-contract.sh` (no flags): **244 passed, 0 failed, 3 skipped**.
- `verify-session-architecture.sh`: **83 passed, 0 failed**.
- `verify-istio-ingress.sh`: **97 passed (out of 97)**.
- `verify-ingress-rate-limits.sh`: **33 checks passed**.
- `verify-oauth-browser-binding.py` and `verify-ingress-browser-callback.py`
  (api-tests interpreter): passed.

### Limitations

- Only headless Chromium was exercised. `form-action` redirect enforcement
  and Origin sending in Firefox and WebKit were not tested; neither browser is
  installed in the development VM.
- The hostile `fetch` cases ran with Chromium's Local Network Access check
  disabled, as described above.
- `verify-edge-contract.sh` ran without `--inject-failures`; its three
  fault-injection cases were skipped.
- The production reference is checked offline only; no hosted environment
  exists.
- Local reset: none required. A browser tab with an old frontend bundle still
  sends `Origin` on its POSTs.
