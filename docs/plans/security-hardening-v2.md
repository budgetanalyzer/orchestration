# Security Hardening Plan v2

## Context

This is the production-grade security hardening plan for the orchestration repository.

It replaces the earlier split between "implement now" and "future work." Material orchestration-layer security controls are not deferred.

Key corrections carried forward from the earlier review:

- External header spoofing through the public ingress path is already mitigated by ext_authz `headersToBackend` allowlisting.
- Istio `AuthorizationPolicy` cannot protect ingress-facing services in the current topology because Envoy Gateway is outside the mesh and has no SPIFFE identity.
- The real current gap is the in-cluster bypass path:

```text
Compromised pod -> nginx-gateway:8080 directly -> spoofed X-User-Id/X-Roles/X-Permissions
```

This plan addresses that gap immediately with Kubernetes `NetworkPolicy`, then removes the topology seam entirely by replacing Envoy Gateway with Istio-managed ingress and egress gateways.

Additional assumptions:

- The application is unreleased. Stateful components may be rebuilt from scratch during hardening.
- This plan covers orchestration-layer controls: topology, network reachability, credential segmentation, transport encryption, pod hardening, edge policy, admission policy, and verification.
- This plan does not solve service/domain authorization logic such as user-to-transaction ownership enforcement inside sibling repositories.

---

## Target Security Model

Target end state:

1. Istio is the only gateway control plane. Envoy Gateway is removed from the architecture.
2. Ingress traffic enters through an Istio-managed ingress gateway that is part of the mesh and has workload identity.
3. External authorization is enforced at ingress through Istio external auth integration, replacing the current Envoy Gateway `SecurityPolicy`.
4. Egress to the public internet is routed through an Istio egress gateway with explicit allowlisting.
5. Mesh workloads use STRICT mTLS wherever possible, including ingress-facing services after ingress migration. Infrastructure services (PostgreSQL, Redis, RabbitMQ) are not mesh workloads and use native TLS instead (Phase 4).
6. Kubernetes `NetworkPolicy` remains in place as L3/L4 defense in depth even after the ingress migration.
7. PostgreSQL, RabbitMQ, and Redis use per-service identities with least privilege.
8. Redis uses ACL users, not one shared password.
9. Pod hardening is enforced both in manifests and at admission time.
10. Production manifests do not rely on default credentials, floating third-party images, or unvalidated policy assumptions.

---

## Phase 0: Platform Preconditions

### 0a. NetworkPolicy-capable CNI

Kind's default CNI (`kindnet`) does not enforce `NetworkPolicy`. Applying NetworkPolicy resources to a kindnet cluster succeeds silently but has no effect — packets flow unrestricted regardless of policy. This must be fixed before any NetworkPolicy work begins.

Required changes:

- `kind-cluster-config.yaml` — add `networking.disableDefaultCNI: true`, pin `kindest/node` image for reproducibility
- `setup.sh` — install Calico after cluster creation, before any other setup steps
- `scripts/dev/check-tilt-prerequisites.sh` — add preflight check that proves default-deny NetworkPolicy actually blocks traffic in the running cluster

Calico is the recommended choice for Kind: lightweight, well-documented for this use case, and sufficient for NetworkPolicy enforcement. Cilium is more capable but heavier and can be problematic in nested container environments (devcontainers).

Production note: managed Kubernetes services (GKE, EKS, AKS) provide NetworkPolicy enforcement through their own CNI or as a cluster-creation option. The NetworkPolicy manifests produced by this plan are portable — the same YAML applies in Kind, GKE, EKS, and AKS. The CNI is an infrastructure provisioning concern, not an application concern.

Add a mandatory preflight verification that proves:

- default-deny `NetworkPolicy` is actually enforced in the local cluster
- Pod Security Admission labels are honored
- Istio sidecar injection and policy resources are functioning before security tests run

### 0b. Admission and namespace policy baseline

Install a policy engine and enable namespace-level Pod Security Admission.

Chosen direction:

- Kyverno for admission policy and policy testing
- Pod Security Admission labels on namespaces as the coarse-grained baseline

Target namespace posture:

- application namespaces: `restricted` once workloads are compliant
- infrastructure and gateway namespaces: `baseline` minimum, `restricted` where validated
- use `warn` and `audit` labels before flipping `enforce`

---

## Phase 1: Credential and Secret Hardening

### 1a. Per-service PostgreSQL users

Create dedicated DB users with grants scoped to their own database only:

- `transaction_service` -> `budget_analyzer`
- `currency_service` -> `currency`
- `permission_service` -> `permission`

Files to modify:

- `kubernetes/infrastructure/postgresql/configmap.yaml`
- `Tiltfile`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `kubernetes/services/permission-service/deployment.yaml`

### 1b. Per-service RabbitMQ users and permissions

Remove `guest/guest`.

Create one RabbitMQ user per service:

- `transaction-service`
- `currency-service`

Scope permissions by vhost and by `configure` / `write` / `read` rights.

If a shared vhost remains necessary, do not collapse back to a shared credential.

Files to modify:

- `kubernetes/infrastructure/rabbitmq/configmap.yaml`
- `kubernetes/infrastructure/rabbitmq/statefulset.yaml`
- `Tiltfile`
- service deployment manifests for transaction-service and currency-service

### 1c. Redis ACL users

Replace the single shared Redis password with Redis ACL users.

Required Redis users:

- `session-gateway`
- `ext-authz`
- `currency-service`

Required scope:

- `session-gateway`: read/write Spring Session keys and ext_authz session keys
- `ext-authz`: read-only access to ext_authz session keys and only the commands it needs
- `currency-service`: access only its cache namespace and required cache commands

Files to modify:

- new Redis ACL config under `kubernetes/infrastructure/redis/`
- `kubernetes/infrastructure/redis/deployment.yaml`
- `Tiltfile`
- `kubernetes/services/ext-authz/deployment.yaml`
- `kubernetes/services/session-gateway/deployment.yaml`
- `kubernetes/services/currency-service/deployment.yaml`
- `setup.sh`

### 1d. Secret source hardening

Separate development bootstrap from production secret sourcing.

Development model (local Kind):

- bootstrap secrets from `.env` via Tilt — this is the developer setup path and is acceptable for local use

Production seam:

- production deployments must not depend on Tilt-generated inline Kubernetes secrets as the final secret-management pattern
- the manifests should clearly separate the secret-creation mechanism from the secret-consumption mechanism so that a production deployer can substitute their own secret source (External Secrets Operator, CSI driver, Vault, cloud-native secret manager, etc.)
- this plan does not implement a specific secret manager integration — that choice is cloud-provider-dependent and would couple an open-source reference architecture to a vendor
- the goal is to document where the seam is and ensure the manifests are structured so the swap is straightforward

---

## Phase 2: Immediate Network Isolation

Add Kubernetes `NetworkPolicy` now, before the ingress migration, to close the current bypass path.

### 2a. Default namespace policies

New files:

- `kubernetes/network-policies/default-deny.yaml`
- `kubernetes/network-policies/default-allow.yaml`

Allow rules in the current topology:

- `nginx-gateway` <- Envoy Gateway proxy pods only
- `ext-authz` <- Envoy Gateway proxy pods only
- `session-gateway` <- Envoy Gateway proxy pods only
- `nginx-gateway` -> backend services, budget-analyzer-web
- `session-gateway` -> Redis, permission-service
- `ext-authz` -> Redis
- `transaction-service` -> PostgreSQL, RabbitMQ
- `currency-service` -> PostgreSQL, RabbitMQ, Redis
- `permission-service` -> PostgreSQL
- all pods -> DNS only, plus any explicitly approved dependency

Implementation notes:

- Match both namespace and pod labels for ingress callers
- Do not implicitly trust an entire namespace when a narrower pod selector is possible

### 2b. Infrastructure namespace policies

New files:

- `kubernetes/network-policies/infrastructure-deny.yaml`
- `kubernetes/network-policies/infrastructure-allow.yaml`

Allow rules:

- `redis` <- `session-gateway`, `ext-authz`, `currency-service`
- `postgresql` <- `transaction-service`, `currency-service`, `permission-service`
- `rabbitmq` <- `transaction-service`, `currency-service`

### 2c. Egress posture before Istio egress cutover

Until the Istio egress gateway is in place, keep external egress narrow and explicit.

Interim goal:

- `session-gateway` only needs outbound HTTPS to the configured IdP host
- `currency-service` only needs outbound HTTPS to `api.stlouisfed.org`

Important limitation:

- generic Kubernetes `NetworkPolicy` is not hostname-aware
- do not treat a broad TCP/443 allow rule as a production end state

This interim posture exists only until Phase 3 is complete.

---

## Phase 3: Istio Ingress and Egress Unification

This phase removes the current "Envoy Gateway outside the mesh" seam.

### 3a. Replace Envoy Gateway with Istio ingress

Target changes:

- remove Envoy Gateway controller and its `SecurityPolicy`-based ext_authz integration
- add Istio ingress gateway as the sole ingress entrypoint
- re-home external authorization to Istio-managed ingress

Auth enforcement target:

- define ext_authz as an Istio external auth provider
- enforce at ingress using Istio authorization/ext-auth mechanisms rather than Envoy Gateway `SecurityPolicy`

### 3b. Move ingress-facing services to STRICT mTLS

After ingress is in the mesh:

- remove PERMISSIVE exceptions for `nginx-gateway`, `ext-authz`, and `session-gateway`
- enforce STRICT mTLS for ingress-facing services
- add `AuthorizationPolicy` for:
  - `nginx-gateway` <- ingress gateway principal only
  - `session-gateway` <- ingress gateway principal only
  - `ext-authz` <- ingress gateway principal only

### 3c. Controlled outbound internet access

Use Istio for hostname-aware egress control.

Required controls:

- configure mesh outbound traffic policy to `REGISTRY_ONLY`
- create `ServiceEntry` resources for:
  - the Auth0 issuer host derived from `AUTH0_ISSUER_URI`
  - `api.stlouisfed.org`
- route outbound traffic through an Istio egress gateway

Final goal:

- application workloads do not egress directly to the internet
- application workloads egress only to the Istio egress gateway at the Kubernetes network layer
- the egress gateway is the only workload allowed to talk to approved external hosts

### 3d. NetworkPolicy alignment after cutover

After Istio ingress and egress gateways are live:

- update application namespace `NetworkPolicy` so workloads only talk to the ingress/egress gateways and their approved in-cluster dependencies
- remove Envoy Gateway-specific allowances

---

## Phase 4: In-cluster Transport Encryption

Apply this after the topology and egress model are settled.

Infrastructure services (PostgreSQL, Redis, RabbitMQ) are not Istio mesh workloads — sidecar injection is disabled in the infrastructure namespace. Istio mTLS does not apply to them. Transport encryption for these services requires native TLS configuration on each service.

Certificate rules:

- local Kind: generate internal service certs from a host-side process, not inside the container sandbox (the sandbox CA is not trusted by the host or browser)
- production: use cert-manager or an equivalent automated certificate lifecycle tool with a self-signed or internal CA for in-cluster service certificates — do not rely on manually generated certificates in production
- keep internal service trust material separate from the browser-facing wildcard cert

### 4a. Redis TLS

Highest-value target because it carries session and identity data.

Required updates:

- TLS listener on Redis
- ACL users carried forward from Phase 1
- trusted CA material mounted into `ext-authz`, `session-gateway`, and `currency-service`

### 4b. RabbitMQ TLS

Required updates:

- TLS listener on RabbitMQ
- trusted CA material mounted into `transaction-service` and `currency-service`

### 4c. PostgreSQL TLS

Required updates:

- PostgreSQL SSL enabled
- certs match the service hostname used by clients
- clients use certificate verification with hostname validation

Security requirement:

- do not describe `sslmode=require` as full server authentication
- if authenticated TLS is the goal, use hostname-validated verification semantics

---

## Phase 5: Runtime Hardening and Pod Security

### 5a. Manifest-level workload hardening

Apply a baseline to all compatible workloads:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

Apply `readOnlyRootFilesystem: true` where validated.

Do not assume PostgreSQL, RabbitMQ, Redis, and NGINX can all be made read-only without explicit testing.

### 5b. Service account token hardening

Set `automountServiceAccountToken: false` everywhere it is not explicitly required.

Target scope:

- all application workloads
- infrastructure workloads
- gateway workloads, unless a concrete Kubernetes API dependency exists

### 5c. Pod Security Admission

Add namespace labels for Pod Security Admission:

- `pod-security.kubernetes.io/enforce`
- `pod-security.kubernetes.io/audit`
- `pod-security.kubernetes.io/warn`

Execution model:

- start with `warn` and `audit`
- fix violations
- flip `enforce` to the target profile per namespace

---

## Phase 6: Edge and Browser Hardening

### 6a. CSP split for dev and production

Keep a development CSP for Vite/HMR, but define a strict production CSP that removes `unsafe-inline` and `unsafe-eval`.

### 6b. Remove wildcard CORS on docs assets

Do not keep `Access-Control-Allow-Origin: *` unless a concrete cross-origin use case remains.

### 6c. Auth endpoint rate limiting at ingress

Rate limiting for `/auth/*`, `/login/*`, `/oauth2/*`, `/logout`, and `/user` belongs at the ingress gateway.

Target:

- rate limit auth-sensitive paths at Istio ingress
- prefer local rate limiting first if the deployment stays single-replica
- move to distributed/global rate limiting if ingress scales horizontally

### 6d. API rate-limiting identity correctness

Ensure API rate limiting keys on the real client identity, not the proxy hop.

Options:

- trusted forwarded-header handling where required
- or move edge-facing rate limiting entirely to ingress

---

## Phase 7: Supply Chain, Admission Policy, and Verification Guardrails

### 7a. Pin third-party images and base images

Pin:

- PostgreSQL
- Redis
- RabbitMQ
- NGINX
- all third-party base images used by Dockerfiles or inline Tilt builds

Local service images tagged `:latest` by Tilt are acceptable as local build outputs, but their base images must be pinned.

### 7b. Installer and bootstrap hardening

Replace pipe-to-shell installer guidance with integrity-checked install guidance wherever possible.

### 7c. Kyverno admission policies

Add cluster admission policies for:

- required `securityContext`
- `automountServiceAccountToken: false`
- rejection of default credentials in manifests
- required image pinning for third-party dependencies
- required `NetworkPolicy` coverage for protected workloads
- namespace Pod Security labels

### 7d. Static manifest validation

Add repeatable static checks in CI and local verification:

- `kubeconform` for schema validation
- `kube-linter` or equivalent config linting
- Kyverno CLI policy tests against manifests

### 7e. Runtime security verification

Add repeatable runtime checks:

- unauthorized pod cannot reach `nginx-gateway:8080`
- unauthorized pod cannot reach Redis/PostgreSQL/RabbitMQ
- Redis ACL users are denied outside their allowed key patterns and commands
- PostgreSQL users cannot access other service databases
- RabbitMQ users cannot access unauthorized queues/exchanges/vhosts
- plaintext connections fail where TLS is required
- spoofed identity headers do not survive the trusted ingress path
- approved external hosts are reachable through the egress gateway
- non-approved external hosts are blocked
- auth endpoints are rate limited

---

## Cross-Repo Dependencies

Most work remains orchestration-only. Coordinated sibling-repo changes may still be needed for:

- local configuration defaults that currently assume shared credentials
- mounted trust material and TLS property wiring
- frontend behavior if the production CSP becomes strict

This plan does not require sibling service business-logic changes.

---

## Verification Strategy

The verification story must prove both configuration correctness and enforcement.

### Static checks

1. schema validation for all manifests
2. linting for security anti-patterns
3. policy tests for admission rules before cluster apply

### Admission checks

1. intentionally insecure manifests are rejected by Kyverno
2. namespace Pod Security labels produce the expected warnings and enforcement behavior

### Runtime enforcement checks

1. default-deny `NetworkPolicy` blocks traffic in the local cluster
2. ingress-only callers can reach ingress-facing services
3. service-to-service paths are limited to the documented graph
4. egress is blocked except through approved Istio-controlled paths
5. TLS-only services reject plaintext clients
6. per-service credentials fail outside their allowed scope

### Regression checks

1. `tilt up` succeeds from a clean rebuild
2. login flow works
3. core API flows work
4. docs routes work
5. startup/readiness/liveness checks remain green

---

## Definition of Done

This plan is complete only when:

1. Envoy Gateway is removed and Istio is the sole gateway control plane.
2. Ingress-facing services are no longer mesh exceptions.
3. Public internet egress is explicitly allowlisted through Istio, not broadly open.
4. PostgreSQL, RabbitMQ, and Redis all use per-service identities with least privilege.
5. Redis ACLs enforce both command and key-scope separation.
6. Kubernetes `NetworkPolicy` blocks unauthorized east-west traffic.
7. Pod hardening is enforced in manifests and at admission time.
8. Pod Security Admission labels are enforced at the namespace level.
9. Third-party images and base images are pinned.
10. Verification automation proves the policies work, not just that manifests exist.

---

## Residual Risk Outside Orchestration

After this plan is complete, the major remaining risks are service/domain-layer concerns rather than infrastructure concerns.

Examples:

- whether `transaction-service` scopes queries to the authenticated user
- whether service endpoints ever return another user's data after receiving a valid identity header
- how organization-level isolation and multi-tenancy are enforced

If a backend service receives a correct authenticated identity and still leaks another user's data, that is a service/domain authorization defect, not an orchestration defect.
