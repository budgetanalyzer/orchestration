# Security Hardening Plan (Full Remediation)

## Context

This repository is currently configured for local development, but it is also a reference architecture intended to be copied. Since the project is unreleased and the goal is to fully address security concerns (not minimize change), this plan favors secure defaults and explicit trust boundaries over convenience.

This is a remediation plan document. It describes issues, recommendations, sequencing, and acceptance criteria.

---

## Goals

1. Eliminate known trust-boundary bypasses.
2. Remove weak/shared/default credentials and enforce least privilege.
3. Add pod and network hardening baselines across workloads.
4. Encrypt sensitive in-cluster traffic where feasible.
5. Tighten edge/browser security headers and route protections.
6. Reduce supply-chain drift from floating versions and ad hoc installers.

## Non-Goals

1. Preserve backward compatibility with existing local environments.
2. Keep current credential names, DB users, or route topology if they conflict with security goals.
3. Implement feature-level authorization/domain ownership in service business logic (out of scope for orchestration).

---

## Findings And Recommendations

### 1) In-cluster auth bypass risk for API traffic (High)

Current state:
- `ext_authz` is enforced only on Gateway `api-route`.
- Ingress-facing services intentionally do not have Istio `AuthorizationPolicy`.
- NGINX forwards identity headers from inbound request headers to backends.
- Any compromised pod with network access to `nginx-gateway` can potentially call `/api` directly and spoof `X-User-Id`/roles/permissions.

Evidence:
- `kubernetes/gateway/ext-authz-security-policy.yaml`
- `kubernetes/istio/authorization-policies.yaml`
- `kubernetes/istio/peer-authentication.yaml`
- `nginx/includes/backend-headers.conf`

Recommendations:
1. Add Istio `AuthorizationPolicy` for ingress-facing services:
   - `nginx-gateway` allow only Envoy Gateway principal.
   - `session-gateway` allow only Envoy Gateway principal.
   - `ext-authz` allow only Envoy Gateway principal.
2. Remove trust in inbound identity headers at NGINX:
   - Do not forward `X-User-Id`, `X-Roles`, `X-Permissions` from arbitrary inbound headers.
   - Forward only headers set by trusted proxy layer (or rename to an internal header contract and strip originals at ingress).
3. Add default-deny `NetworkPolicy` in `default` namespace and explicit allow rules for required service-to-service paths.

Acceptance criteria:
1. A pod in `default` namespace cannot call `http://nginx-gateway:8080/api/...` successfully unless it is the authorized ingress principal/path.
2. Spoofed identity headers sent from an arbitrary pod do not reach backend services as trusted identity.
3. Authorization graph is documented and enforced by policy tests.

---

### 2) Shared/default/weak credentials and broad DB privileges (High)

Current state:
- PostgreSQL uses static credentials (`budget_analyzer` / `budget_analyzer`).
- RabbitMQ uses `guest/guest`.
- Redis default password is predictable in examples.
- One DB user has broad privileges across all service databases.

Evidence:
- `kubernetes/infrastructure/postgresql/statefulset.yaml`
- `kubernetes/infrastructure/postgresql/configmap.yaml`
- `kubernetes/infrastructure/rabbitmq/configmap.yaml`
- `Tiltfile` (secret generation blocks)
- `.env.example`

Recommendations:
1. Introduce per-service DB users:
   - `transaction_service` user with grants only on `budget_analyzer` DB.
   - `currency_service` user with grants only on `currency` DB.
   - `permission_service` user with grants only on `permission` DB.
2. Replace hardcoded infra creds with secrets populated from environment at setup time.
3. Remove `guest/guest`; create dedicated RabbitMQ app users/vhosts with least privileges.
4. Generate strong random defaults in setup/bootstrap (and persist in `.env` or K8s secrets safely).
5. Rotate existing credentials in migration steps and document credential reset process.

Acceptance criteria:
1. No default credentials (`guest`, username=password) remain in manifests or generated secrets.
2. Each service can access only its own database and required queues.
3. Compromise of one service credential does not grant cross-service DB access.

---

### 3) Missing pod/container hardening baseline (Medium)

Current state:
- Workloads do not define container security hardening (`runAsNonRoot`, `allowPrivilegeEscalation`, dropped capabilities, seccomp, read-only rootfs where possible).
- Service accounts do not explicitly disable token automount where not needed.

Evidence:
- All deployment/statefulset manifests under `kubernetes/services/*` and `kubernetes/infrastructure/*`.

Recommendations:
1. Apply a common securityContext baseline to all compatible workloads:
   - `runAsNonRoot: true`
   - `allowPrivilegeEscalation: false`
   - `capabilities.drop: ["ALL"]`
   - `seccompProfile.type: RuntimeDefault`
2. Enable `readOnlyRootFilesystem: true` for workloads that can run read-only.
3. Set `automountServiceAccountToken: false` for pods that do not need Kubernetes API access.
4. Add explicit exceptions for infra workloads if image/runtime constraints require write access.

Acceptance criteria:
1. Every workload has an explicit, reviewed securityContext.
2. No workload runs with unnecessary Linux capabilities.
3. Service account tokens are not mounted by default.

---

### 4) Network isolation gaps (Medium)

Current state:
- No Kubernetes NetworkPolicies are defined.
- Any pod can reach infra services (PostgreSQL, Redis, RabbitMQ) and app services by default.

Evidence:
- No `NetworkPolicy` manifests in `kubernetes/`.

Recommendations:
1. Add namespace default-deny ingress (and egress where practical) for `default` and `infrastructure`.
2. Add explicit allow policies:
   - Redis: only session-gateway + ext-authz (+ explicitly approved consumers).
   - PostgreSQL: only transaction/currency/permission services.
   - RabbitMQ: only transaction/currency services.
   - App service edges: only expected upstream callers.
3. Include DNS and control-plane egress exceptions needed for function.

Acceptance criteria:
1. Unauthorized pod-to-service traffic is blocked by policy.
2. Authorized service paths remain functional.
3. Network policy tests are automated in CI/local verification scripts.

---

### 5) In-cluster transport encryption not enforced for critical paths (Medium)

Current state:
- Redis TLS is disabled (`REDIS_TLS=false`).
- Ingress-facing services are in `PERMISSIVE` mTLS mode for mesh traffic.
- Infra services run plaintext protocols internally by default.

Evidence:
- `kubernetes/services/ext-authz/deployment.yaml`
- `kubernetes/infrastructure/redis/deployment.yaml`
- `kubernetes/istio/peer-authentication.yaml`

Recommendations:
1. Enable Redis TLS and move clients to TLS mode.
2. For ingress-facing services, keep gateway compatibility but enforce strict source identity via AuthorizationPolicy.
3. Evaluate native TLS for PostgreSQL and RabbitMQ in local stack (or explicitly document compensating controls if deferred).
4. Ensure secrets/cert material are provisioned from host-safe flows (no container-generated browser cert authority for user trust).

Acceptance criteria:
1. Session/identity data to Redis is encrypted in transit.
2. Ingress-facing services enforce caller identity even when mTLS is permissive for edge compatibility.
3. TLS posture and exceptions are documented per service.

---

### 6) Browser and edge hardening weaknesses (Low/Medium)

Current state:
- CSP allows `'unsafe-inline'` and `'unsafe-eval'`.
- API docs asset route serves with `Access-Control-Allow-Origin: *`.
- Auth route rate limiting is not clearly enforced at edge for all auth-sensitive paths.

Evidence:
- `nginx/nginx.k8s.conf`
- `kubernetes/gateway/auth-httproute.yaml`

Recommendations:
1. Tighten CSP:
   - Remove `'unsafe-eval'` and inline script/style where possible.
   - Use nonce/hash strategy for required inline scripts.
2. Scope CORS headers for docs assets to required origins only.
3. Add explicit rate limiting/bot protection at gateway for auth endpoints (`/login`, `/oauth2`, `/auth`, `/logout`).

Acceptance criteria:
1. CSP no longer requires unsafe directives in standard flows.
2. Docs endpoints do not expose wildcard CORS without justification.
3. Brute-force attempts on auth endpoints are rate limited.

---

### 7) Supply-chain and reproducibility risks (Low/Medium)

Current state:
- Several images use floating tags (`latest`, `alpine`).
- Prerequisite scripts recommend `curl | bash` installers.

Evidence:
- `kubernetes/services/*/deployment.yaml`
- `kubernetes/infrastructure/*`
- `scripts/dev/check-tilt-prerequisites.sh`

Recommendations:
1. Pin container images to immutable tags/digests.
2. Replace direct pipe-to-shell install guidance with checksum-verified download instructions.
3. Add dependency/version inventory section in docs for reproducibility.

Acceptance criteria:
1. Runtime images are pinned to explicit versions/digests.
2. Tool install guidance includes integrity verification.
3. Build/run behavior is reproducible across environments.

---

## Execution Roadmap

### Phase 0: Design and Preconditions
1. Finalize desired trust model for ingress-facing services.
2. Define per-service credential matrix (DB users, RabbitMQ users/vhosts, Redis consumers).
3. Define migration order to avoid breaking startup dependencies.

Deliverables:
1. Approved architecture notes in `docs/architecture/` (if needed).
2. Migration checklist with rollback steps.

### Phase 1: Credential Segmentation and Rotation
1. Refactor PostgreSQL init scripts and secrets to create per-service users.
2. Refactor RabbitMQ config/secrets to remove guest defaults and define least-privileged users.
3. Strengthen Redis/password generation defaults in setup.
4. Update dependent service env wiring in orchestration manifests.

### Phase 2: Policy Enforcement
1. Add ingress-facing Istio AuthorizationPolicies.
2. Add namespace default-deny NetworkPolicies + explicit allowlists.
3. Remove/replace trust in inbound identity headers at NGINX boundary.

### Phase 3: Runtime Hardening
1. Add workload securityContext baselines.
2. Set `automountServiceAccountToken: false` wherever possible.
3. Add PodDisruption and availability hardening as needed.

### Phase 4: Transport and Edge Hardening
1. Enable Redis TLS end-to-end.
2. Tighten CSP and CORS behavior.
3. Add auth endpoint rate limiting.

### Phase 5: Supply Chain and Verification
1. Pin image versions/digests.
2. Harden prerequisite install scripts/docs.
3. Add repeatable verification tests.

---

## Verification Strategy

1. Policy tests:
   - Negative tests from a temporary unauthorized pod for each protected service.
   - Confirm expected deny responses.
2. Auth bypass tests:
   - Attempt direct calls to NGINX `/api` from in-cluster pod with spoofed identity headers.
   - Verify deny/stripping behavior.
3. Credential isolation tests:
   - Validate each service credential cannot access other service DB/schema/queues.
4. TLS verification:
   - Verify Redis client connections are TLS-enabled.
5. Hardening checks:
   - Lint manifests for required securityContext fields.
6. Regression checks:
   - `tilt up` green path, login flow, core API flows, and docs routes.

---

## Cross-Repo Dependencies

This orchestration repo can implement policy, infra, and deployment hardening directly. Some items require sibling repo changes and should be tracked explicitly:

1. Service-level connection config updates for new DB/RabbitMQ users.
2. Potential identity header contract changes if services currently consume specific header names.
3. Application-level handling of stricter CSP expectations in frontend/service gateways.

For required sibling code changes, open coordinated tasks per service repo and link them from this plan before enforcement cutover.

---

## Risks and Mitigations

1. Risk: Locking down policies causes startup/runtime outages.
   Mitigation: Introduce deny policies with staged dry-run validation and explicit allowlist tests.
2. Risk: Credential rotation breaks service boot.
   Mitigation: Dual-secret rollout window and ordered cutover.
3. Risk: CSP tightening breaks frontend dev tooling.
   Mitigation: Separate dev/prod CSP profiles with documented rationale, then converge.

---

## Definition of Done

1. No known auth bypass from in-cluster callers to protected APIs.
2. No default/shared high-privilege credentials in manifests or generated secrets.
3. Least-privilege DB and broker credentials per service.
4. NetworkPolicies enforce only required traffic paths.
5. Pod hardening baseline applied and documented exceptions reviewed.
6. Critical in-cluster identity/session traffic encrypted or explicitly risk-accepted with documented compensating controls.
7. Image/tool supply chain controls documented and enforced.
