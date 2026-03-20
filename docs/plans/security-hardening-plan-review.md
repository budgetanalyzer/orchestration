# Review: security-hardening-full-remediation.md

## Context

Review of `docs/plans/security-hardening-full-remediation.md` to identify issues — especially where the plan proposes changing explicit, documented architectural decisions without acknowledging the tradeoffs.

---

## Critical Issues

### Finding #1 mischaracterizes the header anti-spoofing design

The plan states: "NGINX forwards identity headers from inbound request headers to backends" and calls this a trust-boundary bypass.

This is wrong for the external attack path. The architecture **deliberately chose HTTP-mode ext_authz** specifically because of the `headersToBackend` allowlist in `kubernetes/gateway/ext-authz-security-policy.yaml:19-21`. The `security-architecture.md` explicitly documents this:

> "even if a client sends X-User-Id in the original request, only headers explicitly listed in headersToBackend (and returned by ext_authz) reach the backend"

Envoy **replaces** client-supplied headers with ext_authz response headers before forwarding to NGINX. The `$http_x_user_id` in `nginx/includes/backend-headers.conf` reads headers that Envoy has already sanitized. This was a deliberate design choice documented in the "Why HTTP mode over gRPC" section of `docs/architecture/security-architecture.md`.

**What IS valid**: A compromised pod calling `nginx-gateway:8080` directly (bypassing Envoy) could spoof headers. But the plan's proposed fix (Istio AuthorizationPolicy on nginx-gateway) can't work — see next issue.

**Assistant response (evidence + pros/cons):**

Evidence:
- `headersToBackend` explicitly allowlists identity headers in `kubernetes/gateway/ext-authz-security-policy.yaml:19-22`.
- The anti-spoofing behavior is explicitly documented in `docs/architecture/security-architecture.md:141`.
- NGINX forwards identity from inbound request headers via `$http_x_user_id`/`$http_x_roles`/`$http_x_permissions` in `nginx/includes/backend-headers.conf:36-38`.
- `api-route` targets `nginx-gateway:8080` (`kubernetes/gateway/api-httproute.yaml:16-18`), and `nginx-gateway` is a `ClusterIP` service (`kubernetes/services/nginx-gateway/service.yaml:9-15`) with no `NetworkPolicy` currently present.

Pros:
- Correct that external client spoofing through Envoy is mitigated by the ext_authz header allowlist design.
- Correctly identifies that the real residual risk is in-cluster direct access to `nginx-gateway`.

Cons:
- "Wrong" is too absolute: the remediation finding is still materially valid for the in-cluster bypass path.
- Current language can be read as if header spoofing concern is mostly theoretical, while the direct path is concrete today.

### Finding #1's Istio AuthorizationPolicy proposal is technically infeasible

The plan recommends: "Add Istio AuthorizationPolicy for ingress-facing services — nginx-gateway, session-gateway, ext-authz — allow only Envoy Gateway principal."

`kubernetes/istio/authorization-policies.yaml:1-13` has a detailed comment explaining why this was intentionally omitted:

> "Ingress-facing services do NOT have AuthorizationPolicies because they receive traffic from the Envoy Gateway proxy, which is outside the Istio mesh and has no mTLS identity."

Envoy Gateway runs in `envoy-gateway-system` and is **not part of the Istio mesh**. It has no SPIFFE identity. You cannot write an AuthorizationPolicy that references a principal that doesn't exist. To make this work, you'd need to either:
- Bring Envoy Gateway into the Istio mesh (significant architectural change, may conflict with Gateway API model)
- Replace Envoy Gateway with an Istio ingress gateway (different product entirely)

The plan proposes this without acknowledging the constraint or the scope of the change.

**Assistant response (evidence + pros/cons):**

Evidence:
- Existing policy file explicitly documents this constraint in `kubernetes/istio/authorization-policies.yaml:5-9`.
- Ingress-facing services are explicitly `PERMISSIVE` due to non-mesh ingress in `kubernetes/istio/peer-authentication.yaml:11-15`.
- Envoy deployment is explicitly configured to disable sidecar injection in `kubernetes/gateway/envoy-proxy-config.yaml:13-15`.

Pros:
- Accurate criticism for the remediation plan's specific recommendation ("allow only Envoy Gateway principal"): that principal does not exist in mesh identity terms today.
- Correctly calls out hidden architectural scope if mesh identity is required.

Cons:
- "Technically infeasible" is broader than necessary. It is infeasible as currently proposed, but not impossible if architecture changes or non-principal controls are used.
- The review should explicitly separate "not feasible in current topology" from "not feasible in general."

---

## Architectural Tradeoffs

### NetworkPolicy vs. Istio AuthorizationPolicy for ingress-facing services

| Approach | Pros | Cons |
|----------|------|------|
| **Current**: No policy on ingress-facing services; Envoy Gateway is the trust boundary | Simple; works with non-mesh ingress; documented | Compromised pod in default namespace could call nginx-gateway directly |
| **Plan's proposal**: Istio AuthorizationPolicy on ingress-facing services | Would be ideal if feasible | Technically infeasible — Envoy Gateway has no mesh identity |
| **Alternative**: Kubernetes NetworkPolicy restricting nginx-gateway ingress to Envoy Gateway pod CIDR | Works without mesh identity; L3/L4 enforcement | Less granular than mTLS identity; CIDR-based, not identity-based |

**Recommendation**: NetworkPolicies (which the plan also proposes in Finding #4) are the correct tool here. The plan should drop the Istio AuthorizationPolicy recommendation for ingress-facing services and rely on NetworkPolicy instead.

**Assistant response (evidence + pros/cons):**

Evidence:
- No `NetworkPolicy` manifests currently exist under `kubernetes/` (repository search result).
- `nginx-gateway` is reachable on in-cluster `ClusterIP` (`kubernetes/services/nginx-gateway/service.yaml:9-15`).

Pros:
- Strongest short-term control for closing pod-to-nginx bypass in current architecture.
- Compatible with Envoy Gateway running outside the Istio mesh.

Cons:
- L3/L4 policy is less expressive than authenticated workload identity policy.
- Requires careful allowlist maintenance and testing to avoid accidental outages.

### Per-service DB credentials (Finding #2)

| Approach | Pros | Cons |
|----------|------|------|
| **Current**: Single `budget_analyzer` user across all DBs | Simple local dev; fewer secrets to manage; easy to debug | Compromised service can access all DBs |
| **Plan**: Per-service users (`transaction_service`, `currency_service`, `permission_service`) | Blast-radius reduction; least privilege | More secrets, more init scripts, cross-repo config changes in every service's `application.yml`, harder local debugging |

Legitimate improvement, but the plan underestimates cross-repo impact. Every Spring Boot service has datasource credentials in its config — this touches 3+ sibling repos, not just orchestration.

**Assistant response (evidence + pros/cons):**

Evidence:
- Shared static DB credentials: `POSTGRES_USER/PASSWORD=budget_analyzer` in `kubernetes/infrastructure/postgresql/statefulset.yaml:26-29`.
- Broad grants across all DBs in `kubernetes/infrastructure/postgresql/configmap.yaml:15-23`.
- Single shared `username/password` keys generated in `Tiltfile:110-131` and consumed by all three services in:
  - `kubernetes/services/transaction-service/deployment.yaml:35-44`
  - `kubernetes/services/currency-service/deployment.yaml:35-44`
  - `kubernetes/services/permission-service/deployment.yaml:35-44`

Pros:
- Review correctly identifies this as a legitimate least-privilege improvement.
- Blast radius reduction is material if one service credential is compromised.

Cons:
- "Must touch each service `application.yml`" is overstated for Kubernetes runtime: current deployments already inject `SPRING_DATASOURCE_*` env vars, so many changes can be orchestrator-only.
- There is still cross-repo impact for local defaults and consistency, but not necessarily immediate code changes in all sibling repos.

### Redis TLS (Finding #5)

| Approach | Pros | Cons |
|----------|------|------|
| **Current**: Redis plaintext, cluster-internal only | Simple; no cert management; Redis is behind K8s service boundary | Session data unencrypted within cluster |
| **Plan**: Redis TLS end-to-end | Encrypted session data in transit | Certificate provisioning/rotation complexity; every Redis client needs TLS config; performance overhead; cert management conflicts with SSL constraint (mkcert CA mismatch between container and host) |

For a local dev reference architecture, Redis TLS adds significant operational burden. The compensating control (network isolation + auth password) is standard practice for cluster-internal Redis.

**Assistant response (evidence + pros/cons):**

Evidence:
- TLS currently disabled in ext_authz (`REDIS_TLS=false`) at `kubernetes/services/ext-authz/deployment.yaml:36-37`.
- Redis runs plaintext internal protocol with password auth in `kubernetes/infrastructure/redis/deployment.yaml:27`.
- ext_authz client supports TLS toggle and TLS config in code (`ext-authz/config.go:22`, `ext-authz/session.go:44-46`).
- Certificate constraints for this environment are documented in `AGENTS.md:314-329`.

Pros:
- Review correctly calls out real operational burden and certificate lifecycle complexity.
- Deferring Redis TLS is pragmatic in local-only setups if strong network isolation is implemented first.

Cons:
- Without network isolation currently in place, plaintext session transport remains a real risk.
- "Standard practice" should not be the sole justification when the remediation plan explicitly targets secure defaults for copyable architecture.

### CSP `unsafe-inline` / `unsafe-eval` (Finding #6)

| Approach | Pros | Cons |
|----------|------|------|
| **Current**: CSP allows `unsafe-inline` and `unsafe-eval` | Works with React dev server (hot reload, webpack); single CSP for dev/prod | Weaker XSS protection |
| **Plan**: Nonce/hash strategy, remove unsafe directives | Stronger CSP | Requires build-time nonce injection or SSR; breaks React dev tooling; needs separate dev/prod CSP (plan acknowledges this in risks) |

The current CSP is appropriate for a dev-focused reference architecture. The plan acknowledges the dev tooling risk but still recommends the change without weighing it against the project's scope.

**Assistant response (evidence + pros/cons):**

Evidence:
- Current CSP includes `unsafe-inline` and `unsafe-eval` at `nginx/nginx.k8s.conf:72`.
- NGINX is proxying Vite/HMR dev paths in `nginx/nginx.k8s.conf:190-248`.
- Remediation plan already records CSP regression risk in `docs/plans/security-hardening-full-remediation.md:293-295`.

Pros:
- Review correctly highlights dev-tooling friction and the need for explicit dev/prod policy split.
- Prevents accidental breakage of local developer workflows.

Cons:
- Keeping permissive CSP as the default in a reference architecture can propagate weaker browser security patterns.
- The review should recommend staged tightening (prod-first, dev exception) instead of mostly rejecting change.

### CORS wildcard on docs endpoint (Finding #6)

The `Access-Control-Allow-Origin: *` at `nginx/nginx.k8s.conf:103` applies only to `/api/docs/openapi.json` — static OpenAPI spec files. This is standard practice for API documentation (Swagger UI needs cross-origin fetch of spec files). Not a security issue for public documentation assets. Low value change.

**Assistant response (evidence + pros/cons):**

Evidence:
- Wildcard CORS exists only on the docs spec route: `nginx/nginx.k8s.conf:100-104`.
- The architecture documents same-origin as a core benefit (`AGENTS.md:118-120`), so cross-origin may not be necessary for primary flow.

Pros:
- Risk is lower than exposing wildcard CORS on authenticated or mutating API routes.
- The route appears to serve static spec artifacts, not sensitive user data.

Cons:
- "Swagger needs cross-origin" is not proven by current same-origin design; wildcard may be unnecessary permissiveness.
- Low effort to scope CORS to intended origins if desired, so value is not zero.

---

## Legitimate Findings (no architectural conflict)

These are straightforward improvements with minimal tradeoffs:

- **RabbitMQ `guest/guest`** (Finding #2): Genuinely should be changed. Default guest user has special localhost-only restrictions that behave differently in containers. See `kubernetes/infrastructure/rabbitmq/configmap.yaml`.
- **Pod securityContext hardening** (Finding #3): Purely additive, no architectural conflict. `runAsNonRoot`, `allowPrivilegeEscalation: false`, dropped capabilities — all standard practice.
- **NetworkPolicies** (Finding #4): The most impactful item. This is the correct solution for the ingress-facing service gap identified in Finding #1 (not Istio AuthorizationPolicy). Should be elevated in priority.
- **Image version pinning** (Finding #7): `postgres:16-alpine`, `redis:7-alpine`, `rabbitmq:3.13-management` should be pinned to patch versions. Digests are overkill for a reference architecture; version tags suffice.

**Assistant response (evidence + pros/cons per item):**

RabbitMQ `guest/guest`:
- Evidence: `kubernetes/infrastructure/rabbitmq/configmap.yaml:10-12`; `Tiltfile:170-189`.
- Pros: High-impact hardening with clear credential risk reduction.
- Cons: Requires coordinated credential rotation and service restart ordering.

Pod securityContext hardening:
- Evidence: No `runAsNonRoot`, `allowPrivilegeEscalation`, `seccompProfile`, `readOnlyRootFilesystem`, or `automountServiceAccountToken` found in current manifests (repository search results); example in `kubernetes/services/nginx-gateway/deployment.yaml:17-64`.
- Pros: Strong baseline hardening, broadly compatible with least privilege.
- Cons: Some workloads may need explicit exceptions and verification.

NetworkPolicies:
- Evidence: No `NetworkPolicy` resources currently defined; ingress-facing services are mesh-permissive (`kubernetes/istio/peer-authentication.yaml:11-50`).
- Pros: Most direct control for current lateral movement and bypass gap.
- Cons: Needs policy tests to avoid breakage during rollout.

Image pinning:
- Evidence: Floating tags are present (`kubernetes/services/ext-authz/deployment.yaml:21`, `kubernetes/services/nginx-gateway/deployment.yaml:21`, `kubernetes/infrastructure/postgresql/statefulset.yaml:21`, `kubernetes/infrastructure/redis/deployment.yaml:20`, `kubernetes/infrastructure/rabbitmq/statefulset.yaml:21`).
- Pros: Better reproducibility and supply-chain stability.
- Cons: Full digest pinning may be heavy for local dev loops; patch-level tags can be a practical midpoint.

---

## Scope Concern

The project is a **completed reference architecture** with priorities limited to documentation, architectural discussions, and bug fixes. This plan proposes substantial infrastructure changes. Items should be explicitly categorized as:
- **Bug fixes**: RabbitMQ guest/guest, image pinning
- **Reference architecture improvements**: NetworkPolicies, pod hardening, per-service DB users
- **Overreach for current scope**: Redis TLS, Istio AuthorizationPolicy restructuring, CSP nonce/hash strategy

**Assistant response (evidence + pros/cons):**

Evidence:
- Project scope and priorities are documented as reference architecture complete with focus on docs/discussion/bug-fixes in `AGENTS.md:33-36` and `docs/ROADMAP.md:9-17`.
- The remediation plan explicitly chooses full security remediation over compatibility in `docs/plans/security-hardening-full-remediation.md:5-6` and `:22-23`.

Pros:
- Review is correct to ask for explicit scoping and prioritization labels so the plan aligns with repository mission.
- Separating "bug fix" vs "architectural uplift" helps execution realism and stakeholder agreement.

Cons:
- Dismissing high-value controls as "overreach" can understate concrete security gaps currently present.
- Better framing is phased prioritization with explicit risk acceptance where deferring controls.
