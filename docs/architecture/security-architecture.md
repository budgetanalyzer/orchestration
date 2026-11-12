# Financial Application Security Architecture
## Design Document

**Version:** 2.0
**Date:** April 22, 2026
**Status:** Active

---

## Executive Summary

This document outlines the security architecture for a financial data application requiring maximum security to prevent unauthorized data access. The architecture implements defense-in-depth principles with clear separation of concerns across multiple security layers while maintaining identity provider independence.

Repository security posture:
- Ingress, session, and routing follow the topology described here.
- Platform security prerequisites: Kind uses Calico instead of `kindnet`, Kyverno is installed and verifiable, the retained smoke policy proves admission is alive, and the checked-in security guardrail suite enforces namespace PSA labels, workload token/`securityContext` baselines, obvious default-credential rejection, and third-party image-digest pinning with narrow system-workload exceptions.
- Credential isolation: per-service PostgreSQL, RabbitMQ, and Redis credentials with dedicated Kubernetes secrets.
- Known residual risks, including runtime database roles that own their schemas, are listed in [Accepted Risks](#accepted-risks).
- Network policies: `default`, `infrastructure`, `istio-ingress`, `istio-egress`, and `monitoring` namespaces have repo-owned deny-by-default ingress and egress with explicit allowlists. The `monitoring` namespace has its own baseline for Grafana, Prometheus, Kiali-to-Prometheus/Jaeger/Kubernetes API/Istiod-version flows, and OTLP ingress to Jaeger from approved namespaces. Only documented pod callers can reach each service. The egress gateway's TCP 443 egress excludes `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16` and `100.64.0.0/10`, so beneath Envoy's SNI host rules it cannot reach pods, Services, the Kubernetes API, nodes or metadata endpoints on 443. This bounds where the gateway connects, not which caller it serves, and it relies on the CNI enforcing `ipBlock.except` after Service DNAT, as Calico does locally; a hosted CNI must as well. The cluster is IPv4-only, so a dual-stack environment needs a matching IPv6 rule. `verify-static-security-manifests.sh` rejects any `istio-egress` policy that reopens these ranges on 443, and `verify-network-policies.sh` proves the denial live. Kubelet probes and Tilt port-forwards are host-to-pod traffic and still rely on Calico's default host endpoint handling (`defaultEndpointToHostAction=Accept`), not the pod-to-pod allowlists.
- Istio ingress and egress manifests describe the intended topology: Envoy Gateway is replaced by an Istio-managed ingress gateway (inside the mesh with SPIFFE identity). Istio egress routes approved outbound traffic (Auth0, FRED API) with `REGISTRY_ONLY` blocking unapproved hosts. All ingress-facing services use STRICT mTLS and ingress-scoped `AuthorizationPolicy` rules, `default-deny-all` makes mesh deny-by-default explicit, and backend policies admit NGINX only on exact public resource paths (see [Mesh Public/Internal Boundary](#mesh-publicinternal-boundary)). The narrow Session Gateway/permission-service relationship allows Session Gateway only `POST` on the login user sync and `GET` on the heartbeat authorization lookup and allows `permission-service` to call Session Gateway only for `DELETE /internal/v1/sessions/users/{userId}` bulk revocation. Four per-client local rate-limit policies protect login initiation, login completion, session operations, and APIs before `ext_authz`; NGINX no longer owns blanket API limiting.
- Istio CNI runtime hardening: Tilt installs Istio CNI, enables `pilot.cni.enabled=true` for `istiod`, and reinjects existing `default` namespace workloads so new sidecar pods do not require `istio-init`.
- Non-root application workload hardening: `session-gateway`, `currency-service`, `transaction-service`, `permission-service`, and `ext-authz` disable service-account token automount, set pod `seccompProfile.type: RuntimeDefault`, and apply the planned container hardening. The Spring Boot services also mount `/tmp` and run read-only as UID/GID `1001`.
- `ext-authz` service source lives in sibling `../ext-authz`; this repository
  owns the deployed workload hardening, Istio authorization policy, Redis ACL
  wiring, and production image policy for it.
- Gateway workload hardening on the Istio `1.30.6` baseline: the auto-provisioned ingress gateway receives pod `seccompProfile.type: RuntimeDefault`, fixed NodePort ownership, and explicit service-account token retention through Gateway `spec.infrastructure.parametersRef`, and the egress gateway installs directly from the `istio/gateway` chart using checked-in values that keep `service.type=ClusterIP`, preserve the low-port binding sysctl needed by the non-root proxy, and add pod-level seccomp hardening. The ingress gateway intentionally keeps its Kubernetes API token mount for TLS secret watching, while the egress gateway currently keeps the chart-managed token behavior because this repo does not add a separate post-render patch just to remove it.
- `nginx-gateway` runtime hardening: the Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container runs as UID/GID `101` from `nginxinc/nginx-unprivileged:1.29.8-alpine`, `readOnlyRootFilesystem: true` is enabled, and the gateway relies on an explicit writable `/tmp` mount while logging to stdout/stderr.
- Frontend runtime hardening across the orchestration and `budget-analyzer-web` repos: the frontend dev image runs Vite as UID/GID `1001`, the Kubernetes Deployment and ServiceAccount disable service-account token automount, the pod sets `seccompProfile.type: RuntimeDefault`, the container pins `runAsUser`/`runAsGroup` to `1001`, and the container applies the planned non-root baseline without forcing `readOnlyRootFilesystem` before the HMR workflow is proven on explicit writable paths.
- Redis runtime hardening: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs Redis as UID `999` / GID `1000` with a read-only root filesystem, mounts an explicit writable `emptyDir` for ACL bootstrap at `/tmp`, and keeps AOF data on the PVC-backed `/data` volume created from the `redis-data` claim template. Pod replacement and `tilt down` retain that data; recreating the disposable Kind cluster resets it.
- PostgreSQL runtime hardening: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, pins pod and container ownership to UID/GID `70`, hardens the TLS-prep init container to the same ownership with `readOnlyRootFilesystem: true`, and keeps the main container `readOnlyRootFilesystem: true` compatible through explicit writable mounts at `/tmp` and `/var/run/postgresql`.
- PostgreSQL server-side TLS enforcement: the server loads `pg_hba.conf` from the `postgresql-hba` ConfigMap through `-c hba_file=...`, so the rules also govern existing data volumes. It has a `local` SCRAM rule and IPv4 and IPv6 `hostssl` SCRAM rules, and no `host` rules, so a TCP client that does not negotiate TLS gets no `pg_hba.conf` entry, including on loopback and through Tilt's port-forward. Clients still use `sslmode=verify-full` to authenticate the server; the server rule only removes the plaintext fallback. `verify-transport-encryption.sh` proves that `sslmode=disable` is refused and `verify-full` still connects.
- RabbitMQ runtime hardening: the StatefulSet disables service-account token automount, sets pod `seccompProfile.type: RuntimeDefault`, runs the broker as UID/GID `999` with `fsGroup: 999`, and enables `readOnlyRootFilesystem: true` while keeping `/var/lib/rabbitmq` as the explicit PVC-backed writable path and leaving config, definitions, and TLS mounts read-only.
- Pod Security namespace enforcement: the checked-in namespace manifests declare the Pod Security `enforce` labels for `infrastructure`, `istio-ingress`, and `istio-egress`, while Tilt reapplies the `default`, `infrastructure`, and `istio-system` labels during reconciliation.
- Runtime-hardening verifier: `./scripts/smoketest/verify-runtime-hardening.sh --regression-timeout 8m` checks the runtime-hardening baseline, including the frontend UID/GID assertions plus the PostgreSQL init-container baseline assertions. The verifier reruns remain bounded per script so failures surface instead of hanging indefinitely.
- Production-smoke frontend bundle path: Tilt runs the sibling frontend `build:prod-smoke` target, packages the resulting `dist/` bundle into a local static-asset image, and `nginx-gateway` serves that bundle at `/_prod-smoke/` through a non-root init-container copy step while `/` and `/login` remain on the Vite/HMR dev route.
- `/api-docs` security posture: the docs surface stays same-origin, read-only, and isolated behind its own docs-only CSP carve-out instead of weakening the main app or `/api/*` routes. Exact docs-surface behavior and generated outputs live in [../../docs-aggregator/README.md](../../docs-aggregator/README.md).
- Frontend strict-CSP audit: `./scripts/smoketest/audit-frontend-csp.sh` rebuilds the sibling production-smoke bundle and checks the repo-owned strict-CSP prerequisites. The static audit passes after the sibling frontend removed the inline-style and `sonner` blockers. Manual browser-console validation is still required.
- Frontend-owned `/login` boundary: bare `/login`, including query variants, remains a frontend page outside the OAuth-initiation budget. The browser begins the protected protocol flow at `/oauth2/authorization/idp`; `/login/oauth2/*` remains on the Session Gateway callback lane.
- Ingress rate-limit identity: each policy combines its stable policy name with Envoy's trusted downstream `remote_address`. Local in-cluster probes preserve their pod source addresses, while VM-browser traffic may share the address established by the host-to-Kind NodePort boundary. The production NLB path preserves public source addresses through `externalTrafficPolicy: Local`; caller-supplied forwarding headers are not keys. The focused verifier also retains the independent proof that NGINX derives the ingress-appended downstream hop rather than a forged caller header.
- Production frontend route cutover: `nginx/nginx.production.k8s.conf` makes the production cutover explicit by serving the built frontend bundle on `/` and `/login` under the strict CSP, returning `404` for `/_prod-smoke/`, and removing the Vite-only public paths from the production route set instead of relying on a header-only toggle over the dev graph.
- Edge and browser security verifier: `./scripts/smoketest/verify-edge-browser-hardening.sh` combines checked-in dev/strict CSP checks for the real app paths, live header verification for `/` and `/_prod-smoke/`, warning-only `/api-docs` visibility, the focused ingress rate-limit verifier, the frontend CSP audit, and the full runtime-hardening regression cascade. Manual browser-console validation on `/_prod-smoke/` remains required before relying on the edge and browser security proof.
- Local security guardrail umbrella: `./scripts/smoketest/verify-security-guardrails.sh` runs the static manifest/admission suite first and the live-cluster runtime proof second. The dedicated `security-guardrails.yml` workflow remains intentionally static-only, and the narrower `./scripts/smoketest/verify-runtime-security-guardrails.sh` entrypoint remains available for targeted runtime-only reruns.

Operationally, those ingress-facing policies depend on the rendered gateway label `gateway.networking.k8s.io/gateway-name=istio-ingress-gateway` and the rendered principal `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`. The egress `DestinationRule` uses `tls.mode: DISABLE` on the workload-to-egress hop so the original external TLS/SNI reaches the egress gateway's `PASSTHROUGH` listener; external TLS remains end-to-end, but that intra-cluster hop is not additionally wrapped in mesh mTLS. `./scripts/smoketest/verify-security-prereqs.sh` proves the platform security prerequisites. Treat Istio ingress and egress hardening as verified only after `./scripts/smoketest/verify-istio-ingress.sh` and the live validation checklist pass. Treat edge and browser security as verified only after `./scripts/smoketest/verify-edge-browser-hardening.sh` passes and the manual browser-console validation on `/_prod-smoke/` is done; `/api-docs` warnings remain visible but non-blocking.

---

## Component Naming

**Session Gateway** - The component that manages user authentication flows and session lifecycle via session-based edge authorization. This name clearly indicates its purpose: managing user sessions at the gateway boundary between frontend clients and backend services.

---

## Architecture Overview

The detailed browser request flow, route ownership, and shared browser session
contract are owned by
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
This document focuses on the security boundaries that flow creates.

At a security-boundary level, the runtime looks like this:

```
Browser
   │ HTTPS + session cookie
   ▼
Istio Ingress Gateway
   ├─ Auth lane → Session Gateway → Redis session writes
   └─ API lane → ext_authz → NGINX → Backend services
                                   │
                                   ├─ PostgreSQL
                                   ├─ Redis
                                   └─ RabbitMQ
```

Security-critical implications:

- All browser traffic enters through the Istio ingress gateway.
- Session Gateway owns login, logout, and browser session renewal.
- `ext_authz` turns the Redis-backed session into trusted upstream identity
  headers on every browser API request.
- Backend services still own data-level authorization after ingress validation.
- Exact service ports and exposure rules live in
  [port-reference.md](port-reference.md).

---

## Component Responsibilities

### 1. Session Gateway (Auth Layer)

**Purpose:** Authentication boundary for browser-based clients

**Responsibilities:**
- Manage OAuth 2.0/OIDC flows with identity provider
- Bind each OAuth callback to its initiating browser before consuming state;
  the reusable secure binding cookie and single-winner Redis deletion contract
  are defined in the [browser session contract](session-edge-authorization-pattern.md#session-gateway---auth-layer).
- Write session data (userId, roles, permissions, idp_sub, email, display_name) as Redis hashes (`session:{sha256(token)}`) — no Auth0 tokens are stored, and ext_authz reads the same hashes for ingress-layer authorization
- Issue HTTP-only, secure session cookies to browsers
- Provide `POST /auth/v1/session` for the state-extending heartbeat and
  `GET /auth/v1/user` for session inspection; accept logout only through a
  top-level form `POST /logout`, returning `303` to the identity provider
- Session lifecycle management (login/logout)
- Call permission-service during login with a deadline-bounded `POST` user sync to establish initial authorization, and on every heartbeat to refresh account status, roles, and permissions by internal user ID

**Technology:** Spring WebFlux with Spring Security OAuth2 Client

**Why Spring WebFlux:**
- Minimal custom code (primarily configuration)
- Native OAuth 2.0/OIDC support
- Custom Redis hash session management (single hash per session)
- Permission enrichment on login and heartbeat refresh
- Team expertise in Spring ecosystem
- Production-grade for financial applications

**Does NOT:**
- Route between microservices (NGINX responsibility)
- Enforce data-level permissions (service responsibility)
- Validate sessions per-request (ext_authz responsibility)

**Why Session-Based Edge Authorization:**
The Session Gateway implements session-based edge authorization specifically for maximum security in a financial application. For detailed analysis of the security advantages, see [Session Security Benefits](session-security-benefits.md).

---

### 2. ext_authz Service

**Purpose:** Per-request session validation at the Istio ingress layer

**Responsibilities:**
- Validate session tokens by looking up Redis session hash (`session:{sha256(token)}`)
- Inject `X-User-Id`, `X-Roles`, `X-Permissions` headers into authorized requests
- Reject unauthorized requests before they reach NGINX or backend services

**Technology:** Go HTTP service implementing Envoy ext_authz protocol

**Why HTTP mode over gRPC:** Istio's `meshConfig.extensionProviders` with `envoyExtAuthzHttp` provides `headersToUpstreamOnAllow` — an infrastructure-level allowlist that controls which response headers from ext_authz are forwarded to upstream services. This is anti-spoofing at the ingress layer: even if a client sends `X-User-Id` in the original request, the Envoy ext_authz filter overwrites it with the value from ext_authz's response. Only headers listed in `headersToUpstreamOnAllow` are forwarded upstream.

**Integration:** Called by the Istio ingress gateway on `/api/*` requests via `AuthorizationPolicy` with `action: CUSTOM`. Host ownership stays on the Gateway API `HTTPRoute` objects (`app.budgetanalyzer.localhost` locally, with `demo.budgetanalyzer.org` retained only as a non-live production-reference value) so Kiali does not misread the external app hostname as a missing service-registry host.

---

### 3. NGINX API Gateway

**Purpose:** Internal API gateway for resource routing and load balancing

**Responsibilities:**
- Route requests to appropriate microservices
- Load balancing across service instances

**Note:** SSL/TLS termination and per-client auth/API rate limiting are handled by the Istio ingress gateway, not NGINX. Session validation is handled by ext_authz at the Istio ingress layer — NGINX receives admitted, pre-validated API requests with identity headers already injected.

**Technology:** NGINX (industry standard)

**Why NGINX:**
- Industry standard with proven operational maturity
- Extensive operational knowledge and tooling
- High performance and reliability at scale
- Large community and ecosystem
- Easy to hire engineers with NGINX expertise
- Well-understood failure modes and monitoring

**Does NOT:**
- Manage user sessions (Session Gateway responsibility)
- Handle OAuth flows (Session Gateway responsibility)
- Validate sessions or tokens (ext_authz responsibility)
- Enforce data-level permissions (service responsibility)

---

### 4. Backend Microservices

**Purpose:** Business logic and data access

**Responsibilities:**
- Enforce data-level authorization
- Verify user owns requested data
- Scope all queries by authenticated user ID
- Structured audit events for state-changing requests (mapped `POST`, `PUT`, `PATCH` and `DELETE`); reads are not audited (see [Logging Strategy](#logging-strategy))
- Business logic execution

**Critical Security Rule:** Always validate that the authenticated user (from `X-User-Id` header injected by ext_authz) has permission to access the specific data being requested.

**Example:**
```
Request: GET /api/budget/accounts/12345
Headers: X-User-Id: user-abc-123, X-Roles: ROLE_USER, X-Permissions: transactions:read

Service Logic:
1. Extract user ID from X-User-Id header: "user-abc-123"
2. Query: SELECT * FROM accounts WHERE id = 12345 AND user_id = 'user-abc-123'
3. If no rows: return 403 Forbidden
4. Otherwise: return account data
```

---

## Authentication And Session Boundaries

The exact login, API-request, and heartbeat walkthroughs live in
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
From a security perspective, the important boundaries are:

- Browser login and callback traffic stays on the Session Gateway auth lane.
  Access tokens are used only inside Session Gateway and are not persisted or
  exposed to browser JavaScript.
- Every browser `/api/*` request is revalidated by `ext_authz`, which rebuilds
  the trusted identity headers from Redis before NGINX forwards the request.
- Active-session renewal happens on `POST /auth/v1/session`. Session Gateway
  first refreshes account status and grants from permission-service, then
  atomically replaces the Redis snapshot and extends the still-existing
  session. Lookup failures return `503` without extending cached authorization;
  deactivated, deleted, or missing accounts invalidate the current session and
  return `401`. The frontend still decides when to call the heartbeat based on
  user activity.
- Every browser `/api/*` request remains Redis-only at the edge. It does not
  trigger a heartbeat or a permission-service lookup.
- Versioned `/api/*` and `/auth/v1/*` authentication failures use one
  `ApiErrorResponse` wire contract across `ext-authz`, Session Gateway, and
  backend defense-in-depth responses, as do Session Gateway and backend
  temporary-dependency failures. An `ext_authz` failure on `/api/*` is a
  fail-closed `503` with an empty body from the ingress. Producer ownership,
  exact generic `401` fields, the operational `503` distinction, and
  browser-route exclusions are defined in
  [Versioned Machine Error Contract](session-edge-authorization-pattern.md#versioned-machine-error-contract).
- Immediate bulk revocation remains a separate deactivation action through
  `DELETE /internal/v1/sessions/users/{userId}` against the user-session index
  in Redis. Heartbeat refresh is the bounded fallback when an indexed session
  survives that attempt.

Internal services rely on Istio mTLS, path-scoped `AuthorizationPolicy`
rules (see [Mesh Public/Internal Boundary](#mesh-publicinternal-boundary)), and
Kubernetes `NetworkPolicy` allowlists. Browser session cookies are
not reused for east-west service calls. Session Gateway calls
permission-service for login and heartbeat authorization, while
permission-service calls Session Gateway only for bulk session revocation.
Kubelet probes and Tilt port-forwards remain host-to-pod exceptions under
Calico's default host endpoint handling.

---

## Mesh Public/Internal Boundary

`kubernetes/istio/authorization-policies.yaml` owns the east-west path
contract. The rules are:

- `default-deny-all` (`spec: {}`) in `default` makes deny-by-default explicit.
  An empty spec is an ALLOW policy that matches nothing, so each workload is
  reachable only through a rule that selects it. Before this policy, the
  selector-less `envoy-metrics-prometheus-policy` provided that property by
  accident. Every `default` workload has its own policy. The Prometheus
  metrics policies are separate, are unchanged, and admit only Prometheus on
  the Envoy stats port and each service's `actuator/prometheus` path.
- Backend policies admit the NGINX identity only on the exact upstream paths
  that the NGINX API locations rewrite to. Each resource has an exact entry and
  a `/*` entry, for example `/transaction-service/v1/transactions` and
  `/transaction-service/v1/transactions/*`. The OpenAPI routes are exact
  `/<service>/v3/api-docs` paths. A version-wide wildcard such as
  `/<service>/v1/*` is not allowed, so a future non-public `/v1` controller,
  `/internal/...` and `/actuator/...` stay unreachable from NGINX without
  relying on naming. `scripts/repo/generate-unified-api-docs.sh` reads specs
  through `kubectl exec` to loopback and needs no mesh allowance.
- Session Gateway may call permission-service only with `POST` on
  `/permission-service/internal/v1/users/sync` (login) and `GET` on
  `/permission-service/internal/v1/users/{*}/authorization` (heartbeat). Any
  other method or internal path, including a `GET` on the sync path, is denied
  with `403 RBAC: access denied`.
- The ingress identity reaches Session Gateway only on the `auth-route`
  surface: `/oauth2/*`, `/login/oauth2/*`, `/logout`, `/logout/*` and
  `/auth/*`. permission-service keeps its separate rule for
  `DELETE /internal/v1/sessions/users/{userId}`.

The sidecar evaluates these rules on the normalized path, so a dot-segment
traversal that NGINX forwards inside an allowed prefix, such as
`/permission-service/v1/users/..;/..;/actuator/prometheus`, is denied with the
Envoy `403` body `RBAC: access denied` instead of reaching the handler.

Adding a public resource therefore needs its mesh path as well as its NGINX
location in the shared `nginx/includes/api-routes.conf`. Without the mesh path the route fails closed
with `403`. The step-by-step procedure lives in
[`nginx/README.md`](../../nginx/README.md#adding-a-new-resource-route), and
`scripts/guardrails/verify-static-security-manifests.sh` rejects a backend
NGINX rule without a path restriction or with a version-wide wildcard, and a
missing or non-empty `default-deny-all`.

`scripts/smoketest/verify-edge-contract.sh` proves the boundary on the live
chain with an encoded-path traversal matrix on both lanes, including side-effect
checks for the bulk revocation endpoint. Before the 2026-11-06 narrowing, it
reproduced the encoded-semicolon traversal: `..%3b`-style paths on the NGINX
lane read permission-service's internal authorization snapshot and every
backend's Prometheus metrics with any session, and on the direct auth lane an
unauthenticated `%2e%2e;` path read Session Gateway's metrics and revoked
every session of an arbitrary user. After narrowing, all of those probes are
the sidecar's `403` and the seeded session stays intact.
Rejecting `;` is the separate control in
[Ingress Path Hardening](#ingress-path-hardening), and separate internal ports
remain deferred.

---

## Ingress Path Hardening

`kubernetes/istio/ingress-path-hardening.yaml` inserts the
`envoy.filters.http.rbac.ingress_path_hardening` filter on the ingress gateway
immediately before `envoy.filters.http.ext_authz`, apart from the rate-limit
filters in `ingress-rate-limit.yaml`. Its single `DENY` policy matches the
`:path` header against `^[^?]*(;|%(25)*3[bB]).*$`, so a literal `;` or a
`%3b`/`%3B` at any percent-encoding depth (`%253b`, `%25253b` and so on: `%`,
any number of `25`, then `3b` or `3B`) before the query string is answered
with `403` `RBAC: access denied`. Query strings keep `;`. Because the filter runs before
routing to either lane, it covers the NGINX lane and the direct Session Gateway
`/auth/*` lane, and the request reaches neither `ext_authz`, NGINX nor Session
Gateway. The direct lane therefore does not depend on Session Gateway's own
path-parameter handling. The checked-in OpenAPI document declares no path with
`;`; this supports rejecting matrix-parameter syntax but is not a compatibility
proof for every client.

HTTP filters see `:path` after the HCM normalization described in
[Ingress Per-Client Rate Limiting](#ingress-per-client-rate-limiting).
Envoy does not decode `%3b`, which is why the regex covers the encoded forms.
Normalization does treat a literal `..;`, `..;<text>` or `.;` segment as a dot
segment: it resolves the segment and drops the `;<text>`, so the filter never
sees those forms. No `;` from them reaches NGINX or Session Gateway, and the
resolved path is subject to the same routing and mesh rules as any other.
Encoded forms such as `%2e%2e;` and `..%3b` are denied by the filter.

The shared `nginx/includes/api-routes.conf` keeps a server-level
`if ($uri ~ ";") { return 400; }` in both NGINX configs as the second layer on
the NGINX lane. `$uri` is decoded and excludes the query string.

`scripts/guardrails/verify-static-security-manifests.sh` fails if the local
manifest or the production render lacks the filter, if it is not one enforcing
`DENY` RBAC filter inserted before `ext_authz`, or if its regex does not deny a
literal `;` and every encoding of `%3b` from `%3b` to `%2525253b` while
admitting ordinary paths, near misses such as `%2533`, and query strings. The
`Semicolon Rejection` section of `scripts/smoketest/verify-edge-contract.sh`
proves on the live chain that every probe on both lanes is a `403` from this
filter: the ingress `rbac.denied` counter rises by exactly the probe count,
and neither the NGINX nor the Session Gateway sidecar records a request.
`scripts/guardrails/verify-nginx-shared-routes.sh` proves the NGINX `400` in
disposable containers, because the ingress now stops these paths first.

---

## Ingress Per-Client Rate Limiting

`kubernetes/istio/ingress-rate-limit.yaml` is the executable policy. Istio
`1.30.6` supplies an Envoy build whose local-rate-limit API supports
in-filter rate-limit actions, wildcard dynamic descriptors,
`max_dynamic_descriptors`, `always_consume_default_token_bucket`, and draft-03
rate-limit headers and `ExtensionWithMatcher`. Four independently named filter
instances are inserted immediately before `envoy.filters.http.ext_authz`.
Each wrapper skips its filter unless its bounded path matches, keeping `ok` and
`enforced` metrics policy-specific. Hostname admission remains the Gateway API
`HTTPRoute` responsibility; the selected ingress workload applies the path
policy consistently to canonical, case-varied, and explicit-default-port
authorities before routing. Insertion before the router alone is not sufficient
because API limiting must protect the authorization call itself.

The ingress HTTP connection manager canonicalizes RFC 3986 paths and merges
repeated slashes before the limiter and `ext_authz` filters run. It rejects
paths containing percent-encoded slash or backslash characters with HTTP 400
instead of forwarding a path that NGINX could interpret differently. Thus
`//api/v1/transactions` is classified as `/api/v1/transactions`, while
`/api%2fv1/transactions` never reaches policy selection, authorization, or
NGINX. This parser alignment is part of ingress ownership of API limiting.

### Policy Boundaries And Capacity

| Stable policy | Paths and bounded family fallback | Sustained rate | Burst capacity | Rejection marker |
| --- | --- | ---: | ---: | --- |
| `login-initiation` | Intended `/oauth2/authorization/idp`; bare `/oauth2` and any other `/oauth2/*` path use this same bounded fallback | 1 request/second | 25 tokens | `x-local-rate-limit-policy: login-initiation` |
| `login-completion` | Intended `/login/oauth2/code/idp`; bare `/login/oauth2` and any other `/login/oauth2/*` path use this same bounded fallback | 2 requests/second | 50 tokens | `x-local-rate-limit-policy: login-completion` |
| `session-operations` | Intended `/auth/v1/user`, `/auth/v1/session`, and `/logout`; bare `/auth` plus unknown `/auth/*` and `/logout/*` paths share this fallback | 5 requests/second | 250 tokens | `x-local-rate-limit-policy: session-operations` |
| `api-requests` | `/api`, `/api/`, and all `/api/*` paths, including unknown API paths | 10 requests/second | 60 tokens | `x-local-rate-limit-policy: api-requests` |

Every bucket refills incrementally once per second; no policy replenishes a
whole minute at once. Classification is path-based but not authority- or
method-based, so equivalent authority spellings and unsupported methods still
consume the applicable family budget before the existing route or service
returns its normal response. Query strings are included in path matching but
never in the descriptor, so changing a query does not create a fresh bucket.
Segment boundaries prevent lookalikes such as `/oauth2ish`,
`/login/oauth2ish`, `/authentication`, `/logoutish`, `/apiv1`, and `/api-docs`
from matching.

Bare `/login` and its query variants remain frontend pages and do not consume
the initiation budget. The family roots `/oauth2`, `/login/oauth2`, `/auth`,
and `/api` do consume their corresponding fallback budget. This handling
limits malformed or unknown traffic without adding policy classes or changing
the Session Gateway and API response contracts.

The capacity model assumes up to 25 active people behind one shared public IP,
with as many as four active tabs each. Each authenticated tab can make an
initial `/auth/v1/user` request and an immediate `/auth/v1/session` request,
then the current frontend sends an activity-dependent session heartbeat every
two minutes. That is up to 200 startup operations and roughly 0.83 steady
heartbeats per second before retries, user reads, and logout. The
`session-operations` bucket therefore allows a 250-request startup burst but
refills at only 5 requests per second because a successful heartbeat also
refreshes permissions through `permission-service`. Login initiation allows
one simultaneous attempt per assumed person. Login completion has a separate
50-token burst and 2-per-second refill so an initiation burst cannot consume
callback capacity; it remains bounded because callback processing can include
identity-provider and permission lookups.

These limits protect capacity; they do not authenticate the OAuth callback or
replace OAuth state and browser-binding validation. Independent initiation and
completion buckets
prevent one class from spending the other's allowance, but an attacker can
still target the completion allowance itself. Session endpoints intentionally
share one budget, so exhaustion does not promise independent logout
availability.

The API rate preserves the former NGINX 10 requests/second capacity baseline.
The retired NGINX `burst=50 nodelay` setting measured excess requests around a
leaky-bucket rate, while Envoy's `max_tokens` is total immediately available
token capacity. The ingress bucket therefore uses 60 tokens—one second of the
10 requests/second rate plus 50 requests of burst headroom—then refills 10
tokens each second.

### Identity, State, And Diagnostics

Each generated descriptor is `(rate_limit_policy, remote_address)`. The
`remote_address` action uses the downstream address established as trusted by
the ingress HTTP connection manager, not a raw incoming `X-Forwarded-For`
value, cookie, query parameter, user claim, OAuth state, or authorization code.
Local in-cluster probes sent directly to the ingress Service preserve their
pod source addresses. Browser processes entering through VM loopback and the
Kind NodePort can share the address established by that host/container
boundary. A future hosted publication design must preserve a trustworthy
original client address before this per-client policy can be claimed there;
the provider-neutral production reference deliberately does not select a load
balancer or Service publication type. Clients behind one NAT intentionally
share an allowance; this is the unavoidable fairness boundary of IP-based
limiting.

There is no default token bucket and
`always_consume_default_token_bucket: false`, so unmatched traffic cannot
consume an incidental aggregate quota. Each policy keeps at most 4096 dynamic
client descriptors in its own least-recently-used cache. This bounds memory,
but eviction can give a returning client a fresh bucket, and all buckets reset
when that Envoy process restarts. Rotating source addresses can therefore
weaken fairness; the policies are capacity controls, not authentication or a
denial-of-service guarantee.

Because hostname ownership stays on `HTTPRoute`, a path-policy match can spend
the caller's per-address allowance before routing rejects an unowned authority.
It cannot spend another client's allowance, and changing authority spelling
does not select a new descriptor.

The four `stat_prefix` values are `ingress_login_initiation`,
`ingress_login_completion`, `ingress_session_operations`, and
`ingress_api_requests`. Envoy exposes each prefix's
`http_local_rate_limit.ok` accepted counter and `enforced` rejected counter
(with `enabled` and `rate_limited` decision counters for diagnosis). These
metrics deliberately have no client-address label. Rejected responses carry
the non-secret policy marker from the table and Envoy's supported draft-03
`X-RateLimit-*` headers. `X-RateLimit-Reset` describes the active token
bucket's remaining refill interval; there is no invented fixed reset time or
static `Retry-After` value. Logs and metrics must not record cookies,
credentials, OAuth state, or authorization codes.

The local gateway ConfigMap and both existing production gateway renders
(ingress bootstrap and public TLS) include only these four custom prefixes in
the proxy stats matcher. This keeps the `ok`, `enforced`, `enabled`, and
`rate_limited` counters available from the normal Envoy metrics endpoints
without enabling every optional Envoy statistic. The focused offline verifier
renders both production entry points and compares their parsed matcher
structures with the local ConfigMap.

### Replica Semantics And Evolution

Enforcement is local to each ingress Envoy process. Replica additions and
proxy restarts create independent allowances; the configuration does not
promise one cluster-wide budget. NGINX has no blanket `limit_req` zone or API
directives after the verified cutover, so ingress is the sole owner of this
general auth/API capacity control.

If consistent enforcement across replicas becomes a requirement, the planned
evolution is Envoy's global rate-limit filter backed by a shared rate-limit
service and shared storage. That design adds a network hop, a new availability
dependency, and an explicit fail-open versus fail-closed decision. It is a
future option, not missing work in this local per-instance contract. This
policy does not add Redis rate-limit state, per-user quotas, or an aggregate
overload bucket.

### Local Verification Record

On October 15, 2026, the focused local verifier passed against the final
Tilt/Kind configuration. It proved exact filter order before `ext_authz`, two
controlled client identities, forged-forwarding-header resistance, independent
policy buckets, policy markers and counters, unauthenticated API protection,
exact admitted-request-to-`ext_authz` accounting, one-second refill, a real
OAuth callback completion after same-client initiation exhaustion, shared API
enforcement across canonical, uppercase, explicit `:443`, and mixed-case
explicit-`:443` authorities, and deterministic independence across two ingress
instances. It restored the single repo-defined replica and removed all
temporary clients, policy, CA, and session resources. The replica proof kept
both direct port-forward child PIDs and temporary log paths in the parent shell,
then confirmed both processes, every captured loopback listener, and both logs
were gone before restoring the replica count; its EXIT trap retains the same
precise cleanup for failures. The record contains no credentials, cookies,
OAuth state, or authorization codes.

---

## Identity Provider Abstraction Strategy

### Design Goal
Prevent vendor lock-in by abstracting identity provider behind Session Gateway. Clients never directly interact with Auth0 or know which provider is used.

### Implementation

All browser authentication protocol endpoints stay on the Session Gateway auth
lane documented in
[session-edge-authorization-pattern.md](session-edge-authorization-pattern.md).
The browser-facing `/login` page remains frontend-owned. It starts the OAuth2
flow through the separately limited `/oauth2/authorization/idp` endpoint and
stays outside the OAuth-initiation budget itself. It also stays separate from
the versioned Session Gateway JSON endpoints.

**Benefits:**
1. **Provider Independence:** Swap Auth0 → Okta → Keycloak without client changes
2. **Centralized Control:** Per-client auth/API throttling at ingress, resource routing at NGINX, and session lifecycle audit events at your boundary
3. **Versioning:** Evolve authentication APIs independently
4. **Security:** Additional validation layer before external provider
5. **Compliance:** Keep authentication flows within your infrastructure boundary

### Migration Path

**Current:** Auth0
**Future Options:** Okta, Keycloak, Azure AD, custom solution

**Migration Impact:**
- Clients: No changes (still use session cookies)
- Session Gateway: Update OAuth configuration
- ext_authz: No changes (reads from Redis, provider-independent)
- Services: No changes (read identity from headers, provider-independent)

---

## Security Considerations

### Defense in Depth Layers

**Layer 1: Session Gateway**
- Manages user authentication lifecycle
- Prevents token exposure to browser
- HTTP-only, Secure, SameSite cookies
- Sliding session timeout and an absolute session lifetime: heartbeats never extend a session past
  `created_at + SESSION_MAX_LIFETIME_SECONDS` (8 hours), and ext_authz enforces it transitively
  through `expires_at` (see [Absolute Session Lifetime](session-edge-authorization-pattern.md#absolute-session-lifetime))

**Layer 2: ext_authz (Istio Ingress)**
- Path hardening before `ext_authz` denies literal and encoded `;` in the path
- The [exact-Origin rule](session-edge-authorization-pattern.md#exact-origin-ingress-rule) denies unsafe browser-host requests without the exact application `Origin`
- Per-request session validation from Redis
- Header injection (X-User-Id, X-Roles, X-Permissions)
- Rejects unauthorized requests before they reach backend services

**Layer 3: Backend Services**
- Data-level authorization
- Query scoping by authenticated user
- Audit events for state-changing requests, not reads
- Database row-level security (optional)

### Token Configuration

**Opaque Session Token** (browser cookie value):
- Lifetime: 15 minutes by default (sliding expiration only after a successful authorization-refreshing `POST /auth/v1/session` heartbeat; frontend gates calls on user activity — idle users and sessions with repeated failed refreshes expire naturally). Heartbeats never extend it past 8 hours from login (`SESSION_MAX_LIFETIME_SECONDS=28800`); at that point the user must sign in again
- Format: Opaque session ID (no sensitive data encoded)
- Storage: Redis session hash keyed by the lowercase hex SHA-256 of the token (`session:{sha256(token)}`); the raw token never appears in Redis key names, index members, the append-only file or logs
- Validated by: ext_authz service via Redis lookup

**Session Redis Hash** (`session:{sha256(token)}`):
- Fields: user_id, idp_sub, email, display_name, picture, roles (comma-joined), permissions (comma-joined), created_at, expires_at
- TTL: 15 minutes (configurable via `session.ttl-seconds`), never past `created_at` plus `session.max-lifetime-seconds`
- Written by: Session Gateway on login and, after a successful permission-service refresh, session heartbeat
- Read by: ext_authz for per-request validation (reads `user_id`, `roles`, `permissions`, `expires_at`)
- Companion index: `user_sessions:{userId}` — a Redis set of the session token digests for that user, used by `DELETE /internal/v1/sessions/users/{userId}` for bulk revocation

**IDP Access Token** (Auth0):
- Obtained by Session Gateway during the OAuth2 authorization code exchange
- Used only to derive the user identity (sub, email, name) and permissions during login
- Not persisted. Not used for any upstream API call after login.
- Not exposed to the browser.

> **Auth0 tenant settings** that produce these token lifetimes and session behavior are documented in [Recommended Auth0 Settings](https://github.com/budgetanalyzer/session-gateway/blob/main/docs/auth0-settings.md) (authoritative values, tied to SESSION_TTL_SECONDS and heartbeat cadence) and [Auth0 Setup Guide — Security Configuration](../setup/auth0-setup.md#6-security-configuration) (quickstart context).

**Session Cookie:**
- Name: `__Host-BA_SESSION`. The `__Host-` prefix makes browsers reject the
  cookie unless it is `Secure`, has `Path=/` and has no `Domain` attribute, so
  it stays host-only and a sibling subdomain cannot set or shadow it. There is
  no domain override.
- HttpOnly: true (prevents JavaScript access)
- Secure: true (HTTPS only; required by the `__Host-` prefix)
- Path: `/`, with no `Domain` attribute
- SameSite: Strict (blocks cross-site attachment, not same-site requests; see [Threat Mitigation](#threat-mitigation))
- No `Max-Age` or `Expires`: it is a browser-session cookie. The stored
  `expires_at`, checked by ext_authz and Session Gateway, and the Redis key TTL
  enforce expiry. Logout and heartbeat invalidation clear the cookie with
  `Max-Age=0`.

### Threat Mitigation

| Threat | Mitigation |
|--------|-----------|
| XSS token theft | Tokens never in browser; HTTP-only cookies |
| Token replay | Short session expiration; server-side session validation |
| CSRF | The principal control is the [exact-Origin ingress rule](session-edge-authorization-pattern.md#exact-origin-ingress-rule): a native Istio `DENY` on the browser application host rejects every method other than `GET`, `HEAD` and `OPTIONS` unless `Origin` is exactly the application origin, on both lanes. It is CSRF provenance for the cookie credential, not authentication, and covers only that host; a future machine-to-machine API uses its own hostname and a non-cookie credential, outside the rule. The session cookie's configured `SameSite=Strict` default keeps it off cross-site requests but not same-site ones, and does not stop a top-level response from clearing it. No CSRF tokens, Fetch Metadata checks, or Session Gateway or ext_authz Origin checks are implemented; Session Gateway disables Spring Security CSRF |
| Unauthorized data access | Service-layer authorization by user ID |
| Credential stuffing and abusive API bursts | Per-client auth/API rate limiting before `ext_authz` at Istio ingress; Auth0 anomaly detection |
| Session hijacking | Opaque session IDs; Redis-backed validation |
| Man-in-the-middle | HTTPS/TLS everywhere; HSTS headers |
| Session revocation | Deleting a Redis session rejects every later lookup at once, because ext_authz reads Redis without a cache. It cannot undo requests already authorized or stop a concurrent login or heartbeat that fetched authorization earlier; see [Emergency Admin Containment](#emergency-admin-containment) |

### Ingress Header Ownership

Every rule in the app, API and auth HTTPRoutes uses a response `set` filter
for one `Strict-Transport-Security: max-age=31536000` value. This replaces
upstream values, including Spring Security's default on the direct auth lane;
`includeSubDomains` and `preload` are intentionally absent. Ingress-local
replies such as ext_authz denials and rate limits may omit HSTS.

Each rule removes caller-supplied `Forwarded`, `X-Forwarded-Host`,
`X-Forwarded-Port`, `X-Forwarded-Prefix` and `X-Forwarded-Ssl` before routing.
The ingress-appended `X-Forwarded-For` chain and existing HTTPS proto handling
remain intact. `verify-edge-contract.sh` proves the final HSTS value on the
app, authenticated API, session and login-start responses and checks forged
forwarding fields cannot change the OAuth callback origin.

### Content Security Policy Posture

NGINX serves distinct CSP profiles by route. The main application and `/api/*`
routes use the strict production-oriented policy. `/api-docs` keeps a separate
docs-only CSP because stock Swagger UI requires inline styles that the main app
policy intentionally forbids.

All three profiles restrict `form-action` to `'self'` and the environment's
exact HTTPS IdP origin, allowing the top-level form POST logout and its IdP redirect.
The shared offline renderer derives that origin from Tilt's `AUTH0_ISSUER_URI`
or the production reference's `REFERENCE_AUTH0_ISSUER_URI`; it rejects missing,
non-HTTPS, wildcard and malformed issuer input. No profile sends the deprecated
`X-XSS-Protection` header. `form-action` does not stop hostile pages
submitting to the application; the
[exact-Origin ingress rule](session-edge-authorization-pattern.md#exact-origin-ingress-rule)
denies those. Under the strict CSP, Chromium blocked an app-page form to a
foreign origin and a same-origin form answer that redirected to one, and
hostile same-site and cross-site form and `fetch` submissions were denied
without changing the session. Only headless Chromium was exercised; see
[Browser proof](session-edge-authorization-pattern.md#browser-proof).

The route boundaries are:

- the docs relaxation is isolated to `/api-docs`
- the main app and `/api/*` routes do not inherit it
- the docs/download flow stays same-origin by default

Exact `/api-docs` behavior, generated outputs, and read-only UI details live in
[../../docs-aggregator/README.md](../../docs-aggregator/README.md). The
checked-in CSP split is implemented in
`nginx/includes/security-headers-{strict,dev,docs}-csp.conf`; see
[nginx/README.md — CSP Split](../../nginx/README.md#csp-split) for the NGINX
profile comparison.

### Accepted Risks

These gaps are known and accepted while no hosted deployment exists. Revisit
each one before a hosted deployment or an open-signup requirement.

- **Runtime roles own their schemas.** Each service's PostgreSQL role owns its
  database and runs its Flyway migrations at startup, so the runtime
  connection can change the schema. There is no separate migration role. One
  in the same pod would not survive code execution there, because Flyway's
  credential would sit beside the runtime one. Against SQL injection it would
  block only owner-only actions such as DDL, triggers and functions, while the
  runtime role's DML can already read and delete the service's data. An
  out-of-process migrator, such as an init container or Job, would separate
  the credentials but is deferred: it adds an image, Flyway version coupling
  and rollout ordering for little gain.
- **Unbounded upload processing.** transaction-service runs one replica with a
  512Mi memory limit and no explicit heap setting. It accepts 25 MB uploads on
  the preview route, reads each upload into a byte array and parses PDFs from
  that array. A few concurrent maximum-size uploads, or one crafted
  high-expansion PDF, can plausibly exhaust the heap and fail the transaction
  API for every user until the JVM recovers or the pod restarts. This is
  reasoned from source and defaults, not reproduced. It affects availability,
  not confidentiality. No current setting, including the 25 MB limit, is a
  capacity bound. A temp-file stream cache is not a fix, because it moves
  neither the input array nor the parsed document to disk. If revisited,
  prefer configuration before code: an NGINX `limit_conn` cap on the preview
  route (an exception to the
  [NGINX rule](../../nginx/README.md) against backend-specific limits), an
  explicit heap percentage with `-XX:+ExitOnOutOfMemoryError` and a memory
  limit that fits heap plus non-heap memory, a lower upload size in both
  NGINX and Spring, and more than one replica. These bound concurrent upload
  memory but not one crafted document. File-backed input, page or text limits,
  per-user fairness and a killable parsing worker remain later options.
- **Anonymous OAuth-state growth.** `noeviction` keeps sessions and OAuth state
  from being evicted, but it does not stop anonymous login starts from filling
  the budget. About 60 source addresses at the per-client login-initiation
  limit, or fewer if IPv6 addresses are cheap, can fill 128 MB with
  maximum-size OAuth-state records and block new logins for each 600 s state
  lifetime. Existing sessions keep working. Recovery is automatic when the
  records expire; an operator can recover sooner by deleting
  `oauth2:state:*` as `redis-ops`, which also fails logins in progress. See
  [Session Management](#session-management).
- **Session Gateway client address.** Session Gateway's reactive request logs
  omit `clientIp` behind the ingress, because the forwarded remote address
  stays unresolved and the shared logging filter refuses the caller-controlled
  hostname. Omission is preferred to an untrusted value. A trusted path needs
  separate design.
- **Audit retention and access.** `budgetanalyzer.audit` events are emitted,
  but no separate store, retention period or access control exists. That
  belongs to a future deployment's log pipeline; see
  [Logging Strategy](#logging-strategy).
- **Redis key-name visibility.** The currency-service Redis user's `+scan`
  grant is not filtered by ACL key patterns, so it can list session-digest,
  `user_sessions:*` and `oauth2:state:*` key names. That exposes user IDs,
  session counts and in-flight logins, but no replayable token. See
  [ADR 011](../decisions/011-hashed-session-keys-host-cookie-absolute-lifetime.md).
- **Compromised allowed intermediary.** Backends trust `X-User-Id`, `X-Roles`
  and `X-Permissions` from permitted mesh callers without a signature, so a
  compromised NGINX or other allowed intermediary can forge or replay identity
  claims. The edge only guarantees that external forged headers are replaced.
  Signed identity context, separate internal ports and per-caller egress
  identity are deferred in
  [ADR 013](../decisions/013-deferred-mesh-identity-hardening.md).

---

## Technology Stack

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Session Gateway | Spring WebFlux | Team expertise; minimal code; OAuth 2.0 native support |
| ext_authz | Go HTTP service | Lightweight; Envoy-native protocol; low latency |
| API Gateway | NGINX | Industry standard; proven reliability; operational maturity |
| Session Store | Redis | Fast; distributed; single hash per session; shared by Session Gateway and ext_authz |
| Identity Provider | Auth0 (abstracted) | Managed service; swappable via Session Gateway |
| Backend Services | Spring Boot | Existing architecture; team expertise |

---

## Deployment Architecture

### High Availability Configuration

```
┌──────────────────────────────────────────────────────────────┐
│                 Istio Ingress Gateway (443)                     │
│                    • SSL Termination                           │
│                    • ext_authz enforcement                     │
└────────┬────────────────────────────┬──────────────────────────┘
         │                            │
    ┌────▼────┐                  ┌────▼────┐
    │ Session │                  │ Session │
    │ Gateway │◄────────────────►│ Gateway │
    │   (1)   │      Redis       │   (2)   │
    └─────────┘                  └─────────┘
         │                            │
    ┌────▼────────────────────────────▼────┐
    │          NGINX Cluster                │
    │      (with health checks)             │
    └────┬──────────┬──────────┬────────────┘
         │          │          │
    ┌────▼────┐ ┌──▼────┐ ┌───▼────┐
    │ Budget  │ │Currency│ │  ...   │
    │   API   │ │Service │ │Services│
    └─────────┘ └────────┘ └────────┘
```

**Session Gateway:**
- Multiple instances behind load balancer
- Stateless (sessions in Redis)
- Graceful shutdown with connection draining

**Redis:**
- One `redis` StatefulSet replica in `infrastructure`, locally and in the
  production reference; no Sentinel, replication or automatic failover is
  configured
- `/data` is PVC-backed through the `redis-data` claim template, so a pod
  restart keeps sessions, but Redis unavailability fails session validation
  until it returns
- High availability needs a deliberate topology choice: the session Lua
  scripts update the session hash and user-session index together without a
  shared Redis Cluster hash slot, so sharded Redis Cluster is not a drop-in
  replacement for primary/replica failover

**NGINX:**
- Multiple instances
- Health checks to backend services
- Consistent hashing for sticky sessions (if needed)

---

## Operational Considerations

### Monitoring and Observability

The observability stack (Prometheus, Grafana, kube-state-metrics) runs in the
`monitoring` namespace and meets the same security requirements as all other
workloads — no namespace exceptions. All images are digest-pinned, all pods
disable `automountServiceAccountToken`, and workloads that need Kubernetes API
access use explicit projected service-account token volumes. See
[Observability Architecture](observability.md) for full details.

Operator access is internal-only in local Tilt, and the production reference
contains no public observability routes. Keep local observability access
loopback-bound through Kubernetes port-forwards or the repo-owned helper
scripts documented in
[observability.md](observability.md). Grafana authentication remains enabled,
anonymous access stays disabled, and the repo does not expose public
observability hostnames.

**Metrics currently collected:**
- Spring Boot JVM metrics (memory, GC, threads) via `/actuator/prometheus`
- Spring Boot HTTP metrics (request rates, latencies, error rates) via Micrometer
- Istio control plane metrics via istiod ServiceMonitor
- Envoy sidecar metrics (per-service traffic) via PodMonitor on `:15090`
- Kubernetes resource metrics via kube-state-metrics

**Security-relevant metrics to watch:**
- `http_server_requests_seconds_count{status="401"}` — application authorization failures
- `ingress_*.http_local_rate_limit.enforced` — ingress policy rejections
- `ingress_*.http_local_rate_limit.ok` — requests admitted by each ingress policy
- `up{namespace="default", application!=""}` — Spring service availability

**Alerting**: Not yet configured. Dashboards are the current observability
surface; alerting rules are a future follow-up.

### Logging Strategy

**Audit events:** Services emit one compact JSON event at `INFO` on the
dedicated `budgetanalyzer.audit` logger, using service-common's `AuditLogger`.
Coverage is limited to state-changing requests and the browser session
lifecycle. Reads are not audited: no current requirement calls for read
auditing, and it would multiply event volume.

- Servlet services (transaction-service, permission-service and
  currency-service): every mapped `POST`, `PUT`, `PATCH` and `DELETE`, emitted
  once after completion with the actual response status. Unmapped requests
  and every `GET` are not audited. See service-common's
  [structured audit events](../../../service-common/docs/common-patterns.md#4-use-structured-audit-events-for-state-changes).
- Session Gateway: login success, login failure (IdP errors, callback
  transport and unexpected failures, permission-service and session-write
  failures), logout success, logout session-read or deletion failure, and bulk
  revocation. Each terminal path has one owner. A failed final logout response
  write is deliberately not audited. See Session Gateway's
  [session lifecycle audit events](../../../session-gateway/docs/security.md#session-lifecycle-audit-events).
- ext_authz denials (`401` and authorizer `503`) and read-side `403`s are not
  audit events. ext-authz writes ordinary operational logs for missing,
  unknown and expired sessions and lookup failures.

**Event format:** six fields. `actor` is the internal user ID or `anonymous`;
`operation` is the HTTP method and Spring route pattern, or a Session Gateway
lifecycle operation such as `OAUTH2_LOGIN_SUCCESS`; `resourceIdentifier` holds route path-variable values only;
`outcome` is the HTTP status:

```json
{
  "timestamp": "2026-11-07T21:15:30.123Z",
  "actor": "usr_abc123",
  "operation": "DELETE /v1/transactions/{id}",
  "resourceIdentifier": "42",
  "outcome": 204,
  "correlationId": "<correlation-id>"
}
```

Events never contain request or response bodies, query strings, email
addresses, display names, session tokens or digests, or OAuth codes and state.
They carry no client address. Retention, access control and routing of
`budgetanalyzer.audit` to a separately controlled store belong to a future
deployment's log pipeline; no separate audit destination is configured in
local Tilt or the production reference.

### Session Management

**Redis Configuration:**
- Session key pattern: `session:{sha256(token)}`, where the suffix is the lowercase hex SHA-256 of the `__Host-BA_SESSION` cookie value; see the [shared session contract](session-edge-authorization-pattern.md#shared-session-contract)
- User session index pattern: `user_sessions:{userId}` (SET of session token digests for bulk revocation)
- Key names remain visible metadata to Redis operators and to the `currency-service` Redis user, whose `+scan` grant (used for cache eviction) is not filtered by ACL key patterns; hashing keeps the reusable token out of them. That user is denied `KEYS` and cannot read session keys
- TTL: 15 minutes (configurable via `session.ttl-seconds`), capped by the 8-hour absolute lifetime (`session.max-lifetime-seconds`)
- Memory budget: `maxmemory 128mb` with `maxmemory-policy noeviction`, set in `kubernetes/infrastructure/redis/start-redis.sh` below the 256Mi container limit. Sessions, session indexes and OAuth2 state are never evicted. The currency cache shares the budget. At the budget Redis rejects writes instead of being OOM-killed, so new logins and heartbeat extensions fail closed while existing sessions stay readable until they expire. Anonymous OAuth2-state growth can still block logins until those records expire; see [Accepted Risks](#accepted-risks)
- Persistence: AOF for crash recovery

**Redis memory budget derivation:** `maxmemory` bounds `used_memory`, not RSS.
The 2026-11-08 local measurement put the worst observed case at the budget at
134 MB × 1.55 allocator fragmentation (a bulk Lua load; ordinary writes stayed
at 1.08–1.12) + 10 MB empty-process base + 7.5 MB fork copy-on-write during an
AOF rewrite or RDB save, about 226 MB or 84% of the 256Mi limit. Realistic
writes peaked at 145 MB. At 128 MB the budget holds about 37,600
maximum-size OAuth-state records (about 3.5 KB each), 75,000–87,000 sessions
with their indexes, or about 25 all-time exchange-rate cache entries. A fork
during which nearly every page is rewritten would copy up to the whole
dataset and does not fit, but at the budget only deletes and expiry can
rewrite pages. `activedefrag` is off. While full, Redis was never OOM-killed
and every pod stayed Ready, because the Redis health checks are read-only;
login starts failed to `/oops`, heartbeats returned `503` and kept the
existing expiry, session reads and API calls succeeded, and logout still
deleted the session because `DEL` is not OOM-gated. Repeat the measurement
when changing the budget, the container limit or the session and OAuth-state
record shapes.

**Session Cleanup:**
- Expired sessions automatically removed by Redis TTL
- Explicit session invalidation on logout (session hash deleted, entry removed from user session index)
- Bulk session revocation via `DELETE /internal/v1/sessions/users/{userId}` — uses the user session index to delete all sessions without scanning, and the mesh only allows this route from the `permission-service` workload identity
- Heartbeat invalidation when permission-service reports the account deactivated, deleted, or missing; permission-service failure preserves the finite existing expiry and returns `503` instead of extending cached grants

### Emergency Admin Containment

For a compromised application admin, use human operator access to Redis for
emergency session invalidation. This does not require a new application
super-admin role or a dedicated session-management UI. Infrastructure operator
access is a separate authority from application roles; use the existing
`redis-ops` maintenance identity over the internal, TLS-verified connection.
Production access remains human-owned and outside agent sessions, as described
in [autonomous-ai-execution.md](autonomous-ai-execution.md).

The containment procedure is:

1. Identify the account by its internal `userId` and confirm its IdP subject;
   email alone is not a unique identity key.
2. Persist account deactivation in permission-service to prevent subsequent
   logins. Use an uncompromised admin when available; if none is available,
   operator recovery of the account state must not depend on the compromised
   application's admin session. Deletion of Redis sessions alone only logs the
   user out. An IdP block alone does not invalidate existing Redis sessions.
3. Delete **all** of the user's session hashes and their `user_sessions:{userId}`
   index through operator Redis access. Reuse the atomic deletion semantics in
   Session Gateway's [delete-user-sessions.lua](../../../session-gateway/src/main/resources/redis/delete-user-sessions.lua).
   Deleting only the index does not revoke any session. Avoid `FLUSHALL` for
   targeted containment because it removes unrelated users' sessions and data.
4. Verify the account is deactivated and the user's sessions are absent. Check
   for surviving session hashes by `user_id` if index completeness is uncertain.
   Record the operator, target user ID, time, and result without recording
   credentials or session tokens; review the compromised account's recent actions.

Deletion rejects subsequent authorization checks for those sessions; it cannot
undo requests already authorized. A login or heartbeat that fetched
authorization before deactivation can still create or extend a session after
the deletion attempt. Active browsers normally revalidate at their next
heartbeat, currently about every two minutes, and a session without a
successful refresh retains only its remaining TTL, currently 15 minutes by
default. Neither is a strict deadline from the deactivation commit because an
in-flight lookup may finish afterward. If immediate containment cannot tolerate
that race, temporarily interrupt application access and stop session issuance,
including in-flight login and heartbeat processing, before the final deletion
and verification. This is an incident-recovery interruption, not a permanent
deployment change. Do not rely on the ordinary heartbeat bound for emergency
containment.

---

## Migration and Rollout Plan

### Infrastructure Setup
1. Deploy Redis
2. Deploy Session Gateway (Spring WebFlux)
3. Deploy ext_authz HTTP service
4. Configure Istio ingress gateway with ext_authz
5. Set up monitoring and alerting

### Authentication Integration
1. Configure Session Gateway with Auth0
2. Test OAuth flows (authorization code + PKCE)
3. Test token refresh mechanism with session hash update
4. Verify session management

### API Integration
1. Update React app to use Session Gateway
2. Test authenticated API calls through ext_authz
3. Verify header injection and backend service authorization
4. Test session expiration and refresh

### Security Validation
1. Penetration testing
2. Session lifecycle testing
3. Session fixation testing
4. Authorization bypass testing
5. Load testing with realistic user patterns

### Production Rollout
1. Blue-green deployment
2. Gradual traffic migration (10% → 50% → 100%)
3. Monitor error rates and latency
4. 24-hour observation period

---

## Future Enhancements

### Potential Improvements
1. **Step-up Authentication:** Require re-authentication for sensitive operations
2. **Device Fingerprinting:** Track and alert on suspicious device changes
3. **Behavioral Analytics:** Detect anomalous access patterns
4. **Token Binding:** Bind sessions to specific devices/channels
5. **GraphQL Gateway:** Add GraphQL layer for frontend aggregation

### Scalability Considerations
1. **Geo-distributed Redis:** Multi-region session replication
2. **Edge Deployment:** Deploy Session Gateway closer to users
3. **Session Caching:** Cache validated sessions at ext_authz layer to reduce Redis lookups
4. **API Gateway Sharding:** Split NGINX by service domain

---

## Appendix: Key Decision Log

| Decision | Rationale |
|----------|-----------|
| Use session-based edge authorization | Maximum security for browser-based financial application |
| Keep NGINX as API gateway | Industry standard; operational maturity; team familiarity |
| Spring WebFlux for Session Gateway | Team expertise; minimal code; native OAuth support |
| Abstract identity provider | Prevent vendor lock-in; centralized control |
| Opaque session cookies | Server-side revocation: deleting the Redis session rejects later lookups at once, without waiting for a token to expire. Concurrent login or heartbeat races remain; see [Emergency Admin Containment](#emergency-admin-containment) |
| Istio ext_authz for validation | Per-request enforcement at ingress; Envoy-native protocol via meshConfig |
| 15 min session timeout | Favor shorter default session windows for browser sessions |
| Service-layer authorization | Defense in depth; protect against gateway bypass |
| Redis for sessions | Performance; distributed architecture; single hash per session |
| East-west caller authentication | Istio mTLS plus AuthorizationPolicy for service-to-service traffic |

---

## Document Approval

**Prepared by:** Senior Software Architect
**Review Required:** Security Team, DevOps Team, Engineering Leadership
**Next Review Date:** Upon architecture changes or security incidents

---

**End of Document**
