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

Deferred as planned: the "absolute expiration" claim (plan 02.4, Phase 4), the
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
