# Security Hardening v2 - Phase 2 Implementation Breakdown

## Goal

Close the current in-cluster bypass path with Kubernetes `NetworkPolicy` allowlists, without crossing repo boundaries or drifting into the Istio ingress/egress migration planned for Phase 3.

This phase is complete when:

1. Unauthorized pods cannot talk directly to `nginx-gateway`, `session-gateway`, `ext-authz`, backend services, or infrastructure services.
2. Only the documented callers can reach each protected service.
3. The policy set is applied and verified through Tilt and a repeatable runtime script.
4. Documentation reflects the new connectivity model and its temporary egress limitation.

## Scope And Constraints

- Write scope stays in this repo.
- Use standard Kubernetes `NetworkPolicy`, not Calico-specific CRDs.
- Keep selectors narrow: namespace plus pod labels wherever possible.
- Do not try to fake hostname-aware egress controls in Phase 2. Generic Kubernetes `NetworkPolicy` cannot do that.
- Do not widen policies for convenience around health probes unless runtime testing proves a real need.

## Preconditions

Phase 2 should not start until these are true:

1. `./scripts/dev/verify-security-prereqs.sh` passes.
2. Phase 1 baseline is deployed, including current per-service PostgreSQL, RabbitMQ, and Redis credentials.
3. A live cluster exists so the Envoy Gateway proxy labels can be verified against the currently pinned chart version.
4. Calico is running with its default `defaultEndpointToHostAction` (Accept). Kubernetes probes and Tilt port-forwards are host-to-pod traffic — they originate from the node IP, not from another pod. Calico's default configuration allows this traffic to bypass `NetworkPolicy`. If this default were ever changed (e.g., to `Drop`), every probe and port-forward would break under default deny. This is a platform-level invariant, not something the policy manifests can control.

Recommended pre-checks:

```bash
./scripts/dev/check-tilt-prerequisites.sh
./scripts/dev/verify-security-prereqs.sh
./scripts/dev/verify-phase-1-credentials.sh
kubectl get pods -A --show-labels
```

## Frozen Traffic Matrix

Implement Phase 2 against the current topology, not the future Istio ingress model.

Session 1 verification notes for March 21, 2026:

- `./scripts/dev/verify-security-prereqs.sh` passed in the active cluster.
- `kubectl get pods -n envoy-gateway-system --show-labels` confirmed the live Envoy Gateway proxy selector set used below.
- `./scripts/dev/verify-phase-1-credentials.sh` currently fails in the active cluster because the application and infrastructure workloads are not deployed yet. That blocks Session 4 rollout work, but it does not block freezing the policy matrix from the checked-in topology plus the live Envoy selector set.

Allowed in-cluster flows to encode:

| Caller | Namespace | Target | Port |
| --- | --- | --- | --- |
| Envoy Gateway proxy pods | `envoy-gateway-system` | `nginx-gateway` | `8080` |
| Envoy Gateway proxy pods | `envoy-gateway-system` | `ext-authz` | `9002` |
| Envoy Gateway proxy pods | `envoy-gateway-system` | `session-gateway` | `8081` |
| `nginx-gateway` | `default` | `transaction-service` | `8082` |
| `nginx-gateway` | `default` | `currency-service` | `8084` |
| `nginx-gateway` | `default` | `budget-analyzer-web` | `3000` |
| `session-gateway` | `default` | `permission-service` | `8086` |
| `session-gateway` | `default` | `redis` | `6379` |
| `ext-authz` | `default` | `redis` | `6379` |
| `transaction-service` | `default` | `postgresql` | `5432` |
| `currency-service` | `default` | `postgresql` | `5432` |
| `currency-service` | `default` | `rabbitmq` | `5672` |
| `currency-service` | `default` | `redis` | `6379` |
| `permission-service` | `default` | `postgresql` | `5432` |
| All sidecar-injected pods | `default` | `istiod` | `15012` |
| All pods that need name resolution | any | `kube-dns` | `53` TCP/UDP |

Temporary Phase 2 external egress:

- `session-gateway` may egress to TCP `443` for the configured IdP.
- `currency-service` may egress to TCP `443` for `api.stlouisfed.org`.

External egress confirmation:

- `session-gateway` is the only workload in the current topology with an IdP-facing OAuth/OIDC responsibility.
- `currency-service` is the only workload in the current topology with a direct outbound data-provider client (`FredClient` to FRED over HTTPS).

Important limitation:

- Phase 2 can restrict external egress to specific workloads, but not to specific hostnames.
- Do not claim host-level allowlisting until Phase 3 replaces this with Istio egress controls.

Explicit Session 1 non-edges:

- Do not add a Phase 2 allow rule for `rabbitmq:15672`. It is a local management UI path, not an in-cluster application dependency.
- Do not add a Phase 2 allow rule for `ext-authz:8090`. It is a probe/debug port, not a service-to-service dependency.
- Do not add a Phase 2 allow rule for `nginx-gateway:/health` from another pod. It is only used by probes and local debugging.
- Do not add a Phase 2 allow rule for `session-gateway` -> `nginx-gateway:8080`. The Session Gateway Kubernetes profile (`application-kubernetes.yml`) still contains Spring Cloud Gateway fallback routes to `nginx-gateway` for `/api/**` and `/**`, but the current Envoy Gateway routes `/api/*` and `/*` directly to `nginx-gateway`, so that hop is not active in this topology. Blocking this path under NetworkPolicy is intentional — it prevents a compromised pod from using session-gateway as a proxy to reach nginx-gateway. If a future topology change routes non-auth traffic through session-gateway, the policy set must be updated to match.

## Stable Selectors To Use

Do not trust namespace-wide access where a pod selector is available.

Current proxy pod labels observed from the live cluster:

```text
namespace: envoy-gateway-system
app.kubernetes.io/component=proxy
gateway.envoyproxy.io/owning-gateway-name=ingress-gateway
gateway.envoyproxy.io/owning-gateway-namespace=default
```

Re-verify before implementation:

```bash
kubectl get pods -n envoy-gateway-system --show-labels
```

Namespace matching should use the built-in namespace label:

- `kubernetes.io/metadata.name=default`
- `kubernetes.io/metadata.name=infrastructure`
- `kubernetes.io/metadata.name=envoy-gateway-system`
- `kubernetes.io/metadata.name=istio-system`
- `kubernetes.io/metadata.name=kube-system`

Pod matching should use the existing workload labels from the manifests, not service names or ClusterIPs:

| Workload | Namespace selector | Pod selector |
| --- | --- | --- |
| Envoy Gateway proxy | `kubernetes.io/metadata.name=envoy-gateway-system` | `app.kubernetes.io/component=proxy` + `gateway.envoyproxy.io/owning-gateway-name=ingress-gateway` + `gateway.envoyproxy.io/owning-gateway-namespace=default` |
| `nginx-gateway` | `kubernetes.io/metadata.name=default` | `app=nginx-gateway` |
| `ext-authz` | `kubernetes.io/metadata.name=default` | `app=ext-authz` |
| `session-gateway` | `kubernetes.io/metadata.name=default` | `app=session-gateway` |
| `transaction-service` | `kubernetes.io/metadata.name=default` | `app=transaction-service` |
| `currency-service` | `kubernetes.io/metadata.name=default` | `app=currency-service` |
| `permission-service` | `kubernetes.io/metadata.name=default` | `app=permission-service` |
| `budget-analyzer-web` | `kubernetes.io/metadata.name=default` | `app=budget-analyzer-web` |
| `redis` | `kubernetes.io/metadata.name=infrastructure` | `app=redis` |
| `postgresql` | `kubernetes.io/metadata.name=infrastructure` | `app=postgresql` |
| `rabbitmq` | `kubernetes.io/metadata.name=infrastructure` | `app=rabbitmq` |
| `istiod` | `kubernetes.io/metadata.name=istio-system` | `app=istiod` |
| `kube-dns` | `kubernetes.io/metadata.name=kube-system` | `k8s-app=kube-dns` |

## File Plan

Create:

- `kubernetes/network-policies/default-deny.yaml`
- `kubernetes/network-policies/default-allow.yaml`
- `kubernetes/network-policies/infrastructure-deny.yaml`
- `kubernetes/network-policies/infrastructure-allow.yaml`
- `scripts/dev/verify-phase-2-network-policies.sh`

Update:

- `Tiltfile`
- `docs/plans/security-hardening-v2.md`
- `scripts/README.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/port-reference.md`

## Session Breakdown

Each session below is intended to fit in one focused implementation block. Sessions 2 and 3 are safe to do without applying anything to the running cluster; Session 4 is the rollout session.

### Session 1: Freeze The Policy Matrix

Goal:

- Confirm the exact callers, ports, and selectors that the policies will encode.

Tasks:

1. Re-verify Envoy Gateway proxy pod labels from the live cluster.
2. Re-check routing from:
   - `kubernetes/gateway/*.yaml`
   - `nginx/nginx.k8s.conf`
   - service deployment manifests under `kubernetes/services/`
3. Confirm that no workload besides `session-gateway` and `currency-service` needs external internet access.
4. Confirm that no in-cluster caller needs:
   - `rabbitmq:15672`
   - `ext-authz:8090`
   - `nginx-gateway:/health` from another pod
5. Decide the temporary Phase 2 egress posture:
   - recommended: workload-scoped TCP `443` egress for `session-gateway` and `currency-service` only

Outputs:

- Final traffic matrix approved.
- Final selector set approved.
- No unresolved questions about required service-to-service edges.

Done when:

- You can enumerate every allowed edge in one page and nothing in the current cluster contradicts it.

Status for March 21, 2026:

- Session 1 is complete as a design freeze: the traffic matrix and selector set above are the contract for Sessions 2 and 3.
- Session 4 rollout is still gated on a live Phase 1 baseline because the current cluster does not have the application/infrastructure workloads needed by `./scripts/dev/verify-phase-1-credentials.sh`.

### Session 2: Author Default Namespace Policies

Goal:

- Build the `default` namespace policy set without applying it yet.

Files:

- `kubernetes/network-policies/default-deny.yaml`
- `kubernetes/network-policies/default-allow.yaml`

Tasks:

1. Add a namespace-wide default deny policy for `default` with both:
   - `policyTypes: [Ingress, Egress]`
   - `podSelector: {}`
2. Add shared DNS egress for pods in `default`:
   - destination namespace `kube-system`
   - destination pod label `k8s-app=kube-dns`
   - TCP and UDP port `53`
3. Add shared istiod egress for sidecar-injected pods in `default`:
   - destination namespace `istio-system`
   - destination pod label `app=istiod`
   - TCP port `15012`
   - This is required for xDS configuration delivery and mTLS certificate rotation. Without it, sidecars bootstrap successfully but certs expire after ~24 hours and mesh communication breaks.
4. Add ingress allows in `default` for ingress-facing services:
   - Envoy proxy pods -> `nginx-gateway:8080`
   - Envoy proxy pods -> `ext-authz:9002`
   - Envoy proxy pods -> `session-gateway:8081`
5. Add default-namespace east-west ingress allows:
   - `nginx-gateway` -> `transaction-service:8082`
   - `nginx-gateway` -> `currency-service:8084`
   - `nginx-gateway` -> `budget-analyzer-web:3000`
   - `session-gateway` -> `permission-service:8086`
6. Add matching egress allows in `default` for the same internal flows:
   - `nginx-gateway` -> transaction, currency, web
   - `session-gateway` -> permission-service
7. Add default-namespace egress allows from application workloads to infrastructure:
   - `session-gateway` -> `redis:6379`
   - `ext-authz` -> `redis:6379`
   - `transaction-service` -> `postgresql:5432`
   - `currency-service` -> `postgresql:5432`
   - `currency-service` -> `rabbitmq:5672`
   - `currency-service` -> `redis:6379`
   - `permission-service` -> `postgresql:5432`
8. Add temporary external egress:
   - `session-gateway` -> TCP `443`
   - `currency-service` -> TCP `443`
9. Validate manifests without rollout:

```bash
kubectl apply --dry-run=server -f kubernetes/network-policies/default-deny.yaml
kubectl apply --dry-run=server -f kubernetes/network-policies/default-allow.yaml
```

Implementation notes:

- Use numeric ports in policies.
- Match destination pods, not service ClusterIPs.
- For external TCP `443`, keep the rule scoped to the two workloads above. Do not add a namespace-wide `443` exception.

Done when:

- The `default` namespace manifests are schema-valid and encode the full intended graph.

Status for March 21, 2026:

- Session 2 is complete in authoring scope.
- Added `kubernetes/network-policies/default-deny.yaml` with namespace-wide ingress and egress default deny for `default`.
- Added `kubernetes/network-policies/default-allow.yaml` with:
  - shared DNS egress to `kube-dns`
  - shared `istiod:15012` egress for the current sidecar-injected application workloads
  - Envoy Gateway proxy ingress allowlists for `nginx-gateway`, `ext-authz`, and `session-gateway`
  - east-west ingress and matching egress allows for `nginx-gateway` and `session-gateway`
  - infrastructure egress allows for Redis, PostgreSQL, and RabbitMQ
  - workload-scoped temporary external TCP `443` egress for `session-gateway` and `currency-service`
- Validation passed with:

```bash
kubectl apply --dry-run=server -f kubernetes/network-policies/default-deny.yaml
kubectl apply --dry-run=server -f kubernetes/network-policies/default-allow.yaml
```

- Rollout remains deferred to Session 4, after Session 3 adds the matching `infrastructure` namespace ingress policies.

### Session 3: Author Infrastructure Namespace Policies

Goal:

- Build the `infrastructure` namespace policy set without applying it yet.

Files:

- `kubernetes/network-policies/infrastructure-deny.yaml`
- `kubernetes/network-policies/infrastructure-allow.yaml`

Tasks:

1. Add a namespace-wide default deny policy for `infrastructure` with both:
   - `policyTypes: [Ingress, Egress]`
   - `podSelector: {}`
2. Do not add DNS egress for `infrastructure`. PostgreSQL, Redis, and RabbitMQ are pure servers — they accept connections but do not initiate outbound DNS lookups. Omitting DNS egress produces a tighter policy. If runtime testing in Session 4 reveals a DNS dependency (unlikely), add it then.
3. Add ingress allows to infrastructure services:
   - `session-gateway`, `ext-authz`, `currency-service` -> `redis:6379`
   - `transaction-service`, `currency-service`, `permission-service` -> `postgresql:5432`
   - `currency-service` -> `rabbitmq:5672`
4. Do not add ingress allows for:
   - `rabbitmq:15672`
   - any caller to Redis/PostgreSQL/RabbitMQ outside the approved set
5. Validate manifests without rollout:

```bash
kubectl apply --dry-run=server -f kubernetes/network-policies/infrastructure-deny.yaml
kubectl apply --dry-run=server -f kubernetes/network-policies/infrastructure-allow.yaml
```

Implementation notes:

- Use `namespaceSelector` plus `podSelector` for every allowed caller from `default`.
- Keep the infrastructure namespace closed to lateral traffic by default; only explicit approved callers should remain.

Done when:

- Redis, PostgreSQL, and RabbitMQ each have an explicit ingress allowlist and no accidental management-port exposure.

Status for March 21, 2026:

- Session 3 is complete in authoring scope.
- Added `kubernetes/network-policies/infrastructure-deny.yaml` with namespace-wide ingress and egress default deny for `infrastructure`.
- Added `kubernetes/network-policies/infrastructure-allow.yaml` with:
  - `redis:6379` ingress restricted to `session-gateway`, `ext-authz`, and `currency-service`
  - `postgresql:5432` ingress restricted to `transaction-service`, `currency-service`, and `permission-service`
  - `rabbitmq:5672` ingress restricted to `currency-service`
- No DNS egress or RabbitMQ management-port exception was added for `infrastructure`.
- Validation passed with:

```bash
kubectl apply --dry-run=server -f kubernetes/network-policies/infrastructure-deny.yaml
kubectl apply --dry-run=server -f kubernetes/network-policies/infrastructure-allow.yaml
```

- Rollout remains deferred to Session 4 so Tilt can apply the `default` and `infrastructure` policy sets together.

### Session 4: Wire Policies Into Tilt And Roll Out Safely

Goal:

- Apply the complete policy set without a deny-only intermediate state.

Files:

- `Tiltfile`

Tasks:

1. Add all four policy files to Tilt as a dedicated resource.
2. Keep the policy resource visible in the Tilt UI, not buried inside another resource.
3. Make the resource depend on `istio-injection`. This single dependency is sufficient because `istio-injection` already transitively depends on `envoy-gateway` (via its `resource_deps` in the Tiltfile). No need to list `envoy-gateway` separately.
4. Load all policy files in one resource so deny and allow manifests are applied together.
5. Roll out through Tilt, not ad hoc `kubectl apply`, so the steady-state workflow remains reproducible.
6. After rollout, verify every app deployment stays healthy:

```bash
kubectl get networkpolicy -A
kubectl get pods -A
kubectl rollout status deployment/nginx-gateway
kubectl rollout status deployment/ext-authz
kubectl rollout status deployment/session-gateway
kubectl rollout status deployment/transaction-service
kubectl rollout status deployment/currency-service
kubectl rollout status deployment/permission-service
kubectl rollout status deployment/budget-analyzer-web
kubectl rollout status deployment/redis -n infrastructure
kubectl rollout status statefulset/postgresql -n infrastructure
kubectl rollout status statefulset/rabbitmq -n infrastructure

# Verify Istio sidecar connectivity to istiod survives the new egress policy
kubectl exec deployment/ext-authz -c istio-proxy -- pilot-agent request GET /clusters | head -5
```

Rollout rule:

- Do not apply `default-deny` or `infrastructure-deny` alone to a shared dev cluster.

Done when:

- The policy resource is managed by Tilt and the full stack remains healthy after rollout.

### Session 5: Add Runtime Proof For Phase 2

Goal:

- Add a deterministic verifier that proves the policies are enforced, not just present.

Files:

- `scripts/dev/verify-phase-2-network-policies.sh`
- `scripts/README.md`

Tasks:

1. Create a verifier script modeled after the existing Phase 0 and Phase 1 verifiers.
2. Use disposable probe pods with `sidecar.istio.io/inject: "false"` so Istio does not contaminate results.
3. Prefer `busybox:1.36.1` probes to keep the verifier lightweight and consistent with existing scripts.
4. Test positive cases:
   - Envoy-labeled probe in `envoy-gateway-system` can reach `nginx-gateway:8080`
   - Envoy-labeled probe in `envoy-gateway-system` can reach `ext-authz:9002`
   - Envoy-labeled probe in `envoy-gateway-system` can reach `session-gateway:8081`
   - `nginx-gateway`-labeled probe in `default` can reach `transaction-service:8082`
   - `nginx-gateway`-labeled probe in `default` can reach `currency-service:8084`
   - `nginx-gateway`-labeled probe in `default` can reach `budget-analyzer-web:3000`
   - `session-gateway`-labeled probe in `default` can reach `permission-service:8086`
   - `session-gateway`-labeled probe in `default` can reach `redis:6379`
   - `ext-authz`-labeled probe in `default` can reach `redis:6379`
   - `transaction-service`-labeled probe in `default` can reach `postgresql:5432`
   - `currency-service`-labeled probe in `default` can reach `postgresql:5432`, `rabbitmq:5672`, and `redis:6379`
   - `permission-service`-labeled probe in `default` can reach `postgresql:5432`
   - any sidecar-injected probe in `default` can reach `istiod.istio-system:15012`
5. Test negative cases:
   - unlabeled probe in `default` cannot reach `nginx-gateway`, `session-gateway`, `ext-authz`, backend services, or `budget-analyzer-web`
   - unlabeled probe in `default` cannot reach Redis, PostgreSQL, or RabbitMQ
   - `transaction-service`-labeled probe cannot reach Redis or RabbitMQ
   - `ext-authz`-labeled probe cannot reach PostgreSQL or RabbitMQ
   - `session-gateway`-labeled probe cannot reach transaction-service or currency-service
   - any default-namespace probe cannot reach `rabbitmq:15672`
6. Add conditional external egress checks:
   - `transaction-service`-labeled probe cannot reach external TCP `443`
   - `permission-service`-labeled probe cannot reach external TCP `443`
   - `session-gateway`-labeled probe may attempt external TCP `443`
   - `currency-service`-labeled probe may attempt external TCP `443`
7. Keep the verifier honest:
   - do not assert hostname-specific blocking for `session-gateway` or `currency-service` in Phase 2
   - skip Auth0/FRED-specific checks if the related configuration is absent in secrets

Recommended command:

```bash
./scripts/dev/verify-phase-2-network-policies.sh
```

Done when:

- The script fails on unauthorized paths and passes on authorized paths in a repeatable way.

### Session 6: Update Architecture And Operator Docs

Goal:

- Remove stale wording that says application/infrastructure allowlists are only future work.

Files:

- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/port-reference.md`

Tasks:

1. Add the new Phase 2 verifier to setup and troubleshooting docs.
2. Update security architecture docs to reflect that:
   - default and infrastructure namespace allowlists are now enforced
   - the remaining egress gap is hostname awareness, not absence of egress control
3. Update port/reference docs so protected paths show their approved callers.
4. Add troubleshooting notes for the most likely breakages:
   - missing DNS egress (random service outages)
   - missing Envoy proxy selector match (ingress 503s)
   - missing istiod egress (sidecars work initially, then mTLS cert rotation fails after ~24 hours)
   - Calico `defaultEndpointToHostAction` changed from default (all probes and port-forwards fail)

Done when:

- The docs describe the deployed policy model, not the pre-Phase-2 model.

## Policy Shape

The final manifests should roughly have this structure:

- `default-deny.yaml`
  - one namespace-wide deny for all pods in `default`
- `default-allow.yaml`
  - one shared DNS egress policy
  - one shared istiod egress policy (xDS and cert rotation for sidecar-injected pods)
  - targeted ingress policies for ingress-facing services
  - targeted ingress policies for backend/web services
  - targeted egress policies for service-to-service and service-to-infrastructure traffic
  - temporary workload-scoped TCP `443` egress for `session-gateway` and `currency-service`
- `infrastructure-deny.yaml`
  - one namespace-wide deny for all pods in `infrastructure`
- `infrastructure-allow.yaml`
  - targeted ingress policies for Redis, PostgreSQL, and RabbitMQ
  - no DNS egress (infrastructure services are pure servers with no outbound dependencies)

Keep the manifests split this way so the namespace deny baseline is obvious and the exception set stays readable.

## Risks To Watch

1. Envoy proxy labels are chart-managed, not repo-managed. Re-verify them before rollout.
2. Missing DNS egress will look like random service outages. Test DNS first.
3. Missing istiod egress will not fail immediately — sidecars bootstrap at pod creation — but certs expire after ~24 hours with default Istio settings. Verify sidecar-to-istiod connectivity after rollout, not just at startup.
4. Temporary TCP `443` egress for `session-gateway` and `currency-service` is a controlled compromise, not the end state.
5. Do not use IP-based external allowlists unless they are derived and documented; brittle hand-maintained IPs will rot quickly.
6. The `session-gateway` Spring Cloud Gateway fallback routes to `nginx-gateway:8080` (`application-kubernetes.yml`) are intentionally blocked by the policy set. If a future topology change needs that path, the NetworkPolicy must be updated to match.

## Phase 2 Definition Of Done

Phase 2 is done when all of the following are true:

1. `default` namespace has a deny-by-default ingress and egress posture with explicit allowlists.
2. `infrastructure` namespace has a deny-by-default ingress and egress posture with explicit allowlists.
3. The only pods allowed to reach ingress-facing services are the Envoy Gateway proxy pods.
4. Backend services only accept traffic from their documented in-cluster callers.
5. Infrastructure services only accept traffic from their documented application callers.
6. Only `session-gateway` and `currency-service` retain temporary external TCP `443` egress.
7. Tilt manages the policy set as a first-class resource.
8. `./scripts/dev/verify-phase-2-network-policies.sh` passes.
9. Updated docs reflect the new policy posture and the remaining Phase 3 egress limitation.
