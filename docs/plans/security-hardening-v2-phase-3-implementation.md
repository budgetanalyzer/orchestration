# Phase 3: Istio Ingress and Egress Unification — Implementation Plan

## Context

The current ingress architecture has a structural security seam: Envoy Gateway operates **outside** the Istio service mesh. It has no SPIFFE identity and cannot participate in mTLS. This means:

- Ingress-facing services (`nginx-gateway`, `ext-authz`, `session-gateway`) must run in PERMISSIVE mTLS mode
- These services cannot have Istio `AuthorizationPolicy` enforcement because Envoy Gateway presents no mesh identity
- Egress to the public internet is controlled only by generic `NetworkPolicy` TCP/443 rules, which are not hostname-aware

Phase 3 eliminates this seam by replacing Envoy Gateway with Istio-managed ingress and egress gateways, bringing the entire traffic path inside the mesh.

**Prerequisite status:** Phase 1 (credentials) and Phase 2 (NetworkPolicy authoring) are implemented. NetworkPolicy manifests are authored but Tilt rollout is deferred to this phase.

---

## Key Architectural Decisions

**1. Gateway API (not VirtualService) for ingress.** Istio v1.24 natively implements the Gateway API specification. The existing HTTPRoute resources (`api-httproute.yaml`, `auth-httproute.yaml`, `app-httproute.yaml`) are controller-agnostic — they reference a parent Gateway by name, not by controller. They can be reused by updating `parentRefs` to point at an Istio-backed Gateway. No VirtualService resources are needed for ingress.

**2. Istio auto-provisioned ingress gateway.** Rather than deploying the `istio/gateway` Helm chart separately, let Istio auto-create the gateway Deployment and Service from the Gateway API resource. This is the standard Istio Gateway API pattern. A `kubectl patch` sets the specific NodePort (30443) to match the existing Kind cluster port mapping (`kind-cluster-config.yaml` line 19-21: `containerPort: 30443` → `hostPort: 443`).

**3. `istio-ingress` namespace.** The ingress gateway deploys in its own namespace with sidecar injection enabled, giving it a SPIFFE identity in that namespace. Session 1 explicitly verifies the rendered ServiceAccount name before Session 3 writes principal-based `AuthorizationPolicy` rules.

**4. ext_authz via meshConfig extensionProviders.** Istio supports external authorization through `meshConfig.extensionProviders` + `AuthorizationPolicy` with `action: CUSTOM`. The ext-authz Go service already speaks the HTTP ext_authz protocol — no code changes required. This replaces the Envoy Gateway `SecurityPolicy`.

**5. Istio networking API for egress routing.** Egress gateway routing uses `ServiceEntry` + Istio networking `Gateway` + `VirtualService` + `DestinationRule` (the mature pattern), not Gateway API.

**6. Egress gateway via Helm.** The egress gateway is deployed via the `istio/gateway` Helm chart in `istio-egress` namespace (ClusterIP, no external exposure).

**7. No explicit `ALLOW_ANY` in the base Istiod values.** Session 1 only moves Istiod configuration into a values file; it does not pin outbound policy. Session 4 updates that same canonical values file to `REGISTRY_ONLY` only after the required `ServiceEntry` and egress-routing resources exist. This avoids a steady-state drift where re-running `istiod` silently reopens outbound internet access.

---

## Session 1: Istio Ingress Gateway Installation and ext_authz Provider Registration

**Goal:** Install the Istio ingress gateway, register ext-authz as an Istio extension provider, and create the Istio Gateway with TLS termination. Both gateways coexist; no traffic cuts over yet, and outbound policy remains unchanged through Session 3.

### Files to Create

**`kubernetes/istio/ingress-namespace.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: istio-ingress
  labels:
    istio-injection: enabled
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.32
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.32
```

**`kubernetes/istio/istiod-values.yaml`** — Helm values file for istiod, replacing inline `--set` flags:
```yaml
pilot:
  resources:
    requests:
      memory: 256Mi
      cpu: 100m
meshConfig:
  # Leave outboundTrafficPolicy unset in Sessions 1-3.
  # Session 4 makes REGISTRY_ONLY the canonical value in this same file.
  extensionProviders:
    - name: ext-authz-http
      envoyExtAuthzHttp:
        service: ext-authz.default.svc.cluster.local
        port: 9002
        headersToUpstreamOnAllow:
          - x-user-id
          - x-roles
          - x-permissions
        includeRequestHeadersInCheck:
          - cookie
        failOpen: false
```

**`kubernetes/istio/istio-gatewayclass.yaml`**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: istio
spec:
  controllerName: istio.io/gateway-controller
```

**`kubernetes/istio/istio-gateway.yaml`** — Istio auto-provisions the Deployment/Service from this:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: istio-ingress-gateway
  namespace: istio-ingress
  annotations:
    networking.istio.io/service-type: NodePort
spec:
  gatewayClassName: istio
  listeners:
    - name: https
      hostname: "*.budgetanalyzer.localhost"
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: budgetanalyzer-localhost-wildcard-tls
            namespace: default
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              kubernetes.io/metadata.name: default
```

**`kubernetes/istio/tls-reference-grant.yaml`** — Required because the TLS secret is in `default` but the Gateway is in `istio-ingress`:
```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-istio-ingress-tls-secret
  namespace: default
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: istio-ingress
  to:
    - group: ""
      kind: Secret
      name: budgetanalyzer-localhost-wildcard-tls
```

### Files to Modify

**`Tiltfile`** — Restructure the Istio and Gateway sections:

1. Modify the `istiod` resource to use `--values kubernetes/istio/istiod-values.yaml` instead of inline `--set` flags
2. Add new resources (after `istiod`):
   - `istio-gateway-class` — applies `istio-gatewayclass.yaml` (depends: `istiod`, `gateway-api-crds`)
   - `istio-ingress-config` — applies namespace, ReferenceGrant, Gateway, then patches NodePort to 30444 (temporary, avoids conflict with Envoy on 30443). Depends: `istio-gateway-class`, `mkcert-tls-secret`

### Verification

1. `kubectl get pods -n istio-ingress` — gateway pod Running
2. `kubectl get gateway -n istio-ingress istio-ingress-gateway` — `Programmed=True`
3. `kubectl get cm istio -n istio-system -o yaml | grep ext-authz-http` — extension provider registered
4. `kubectl get deploy,pods,sa -n istio-ingress --show-labels` — note the exact gateway ServiceAccount name and rendered pod labels (needed in Sessions 2 and 3)
5. Envoy Gateway still serves traffic at `https://app.budgetanalyzer.localhost` — no disruption

---

## Session 2: Ingress Cutover — HTTPRoutes, ext_authz Policy, and Envoy Gateway Removal

**Goal:** Create the Istio ext_authz `AuthorizationPolicy`, stage Istio routes and ingress-side `NetworkPolicy` changes, then cut over NodePort 30443 only after Envoy Gateway is removed.

### Files to Create

**`kubernetes/istio/ext-authz-policy.yaml`** — CUSTOM action AuthorizationPolicy targeting the Istio ingress gateway for `/api/*` paths:
```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ext-authz-at-ingress
  namespace: istio-ingress
spec:
  selector:
    matchLabels:
      istio.io/gateway-name: istio-ingress-gateway  # Verify against Session 1 labels before apply
  action: CUSTOM
  provider:
    name: ext-authz-http
  rules:
    - to:
        - operation:
            paths: ["/api/*"]
```

**`kubernetes/network-policies/istio-ingress-deny.yaml`** — deny-all for `istio-ingress` namespace

**`kubernetes/network-policies/istio-ingress-allow.yaml`** — allows for the ingress gateway pod:
- DNS egress → kube-dns
- istiod egress → port 15012
- External ingress → ingress gateway pod TLS target port (verify the rendered target port; for Istio this is typically 8443)
- Egress to default namespace services: `nginx-gateway:8080`, `ext-authz:9002`, `session-gateway:8081`
- Pod selectors must use the actual rendered ingress-gateway labels captured in Session 1; do not guess

### Files to Modify

**`kubernetes/gateway/api-httproute.yaml`** — use a temporary dual-parent cutover, then finalize to Istio-only:
```yaml
  parentRefs:
  - name: ingress-gateway
  - name: istio-ingress-gateway
    namespace: istio-ingress
```

After `istio-ingress-cutover` succeeds, remove the legacy `ingress-gateway` parentRef so the final file points only at `istio-ingress-gateway`.

**`kubernetes/gateway/auth-httproute.yaml`** — same temporary dual-parent cutover, then final Istio-only parentRef

**`kubernetes/gateway/app-httproute.yaml`** — same temporary dual-parent cutover, then final Istio-only parentRef

**`kubernetes/network-policies/default-allow.yaml`**:
1. Delete three policies referencing `envoy-gateway-system`:
   - `allow-nginx-gateway-ingress-from-envoy`
   - `allow-ext-authz-ingress-from-envoy`
   - `allow-session-gateway-ingress-from-envoy`
2. Add three replacement policies referencing `istio-ingress` namespace and the rendered ingress-gateway pod labels:
   - `allow-nginx-gateway-ingress-from-istio-ingress` — port 8080
   - `allow-ext-authz-ingress-from-istio-ingress` — port 9002
   - `allow-session-gateway-ingress-from-istio-ingress` — port 8081

**`Tiltfile`:**
1. Keep `istio-ingress-config` on temporary NodePort `30444` until cutover is ready. Do not patch `30443` while Envoy still owns it.
2. Split the existing `network-policies` resource into:
   - `network-policies-core` — applies `default` + `infrastructure` namespace policies
   - `istio-ingress-network-policies` — applies `istio-ingress` namespace policies and depends on `istio-ingress-config`
   - `istio-egress-network-policies` — reserved for Session 5 and depends on `istio-egress-gateway`
3. Replace the old `ingress-gateway` resource with `istio-ingress-routes` (applies temporary dual-parent HTTPRoutes + `ext-authz-policy`, depends: `istio-ingress-config`, `istio-ingress-network-policies`, `ext-authz`, `nginx-gateway`)
4. Add required `envoy-gateway-cleanup` resource that uninstalls Envoy Gateway Helm state and deletes stale Envoy-specific CRs/resources
5. Add `istio-ingress-cutover` resource that depends on `envoy-gateway-cleanup`, patches the Istio ingress Service to NodePort `30443`, and reapplies the HTTPRoutes in their final Istio-only form
6. Remove: `envoy-gateway` Helm resource, `envoy-proxy-config`, `gateway-class` (Envoy's), old `ingress-gateway`
7. Remove `envoy-gateway` from `istio-injection` resource_deps
8. Remove `envoy-gateway-system` namespace labeling from `istio-injection`

### Files to Delete

- `kubernetes/gateway/envoy-proxy-config.yaml`
- `kubernetes/gateway/envoy-proxy-gatewayclass.yaml`
- `kubernetes/gateway/client-traffic-policy.yaml`
- `kubernetes/gateway/ext-authz-security-policy.yaml`
- `kubernetes/gateway/gateway.yaml`

### Files to Keep

The three HTTPRoute files stay in `kubernetes/gateway/` — they are controller-agnostic Gateway API resources.

### Verification

1. `curl -k https://app.budgetanalyzer.localhost/` — returns React app (catch-all via nginx-gateway)
2. `curl -k https://app.budgetanalyzer.localhost/api/v1/transactions` — returns 401/403 (ext-authz denies unauthenticated)
3. `curl -k https://app.budgetanalyzer.localhost/login` — returns 302 redirect to Auth0
4. `kubectl get networkpolicy -n istio-ingress` — deny-all + allow policies exist
5. `kubectl get httproute -n default -o wide` — all routes show `istio-ingress-gateway` as an accepted parent during staging, and only `istio-ingress-gateway` after `istio-ingress-cutover`
6. `kubectl get pods -n envoy-gateway-system` — empty (after cleanup)
7. Full login flow works end-to-end

---

## Session 3: STRICT mTLS and Ingress-Facing AuthorizationPolicies (Phase 3b)

**Goal:** Remove PERMISSIVE PeerAuthentication exceptions. Add AuthorizationPolicies for ingress-facing services restricting them to the Istio ingress gateway identity only.

### Files to Modify

**`kubernetes/istio/peer-authentication.yaml`** — delete the three PERMISSIVE resources (`nginx-gateway-permissive`, `ext-authz-permissive`, `session-gateway-permissive`). Only `default-strict` remains:
```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default-strict
  namespace: default
spec:
  mtls:
    mode: STRICT
```

**`kubernetes/istio/authorization-policies.yaml`** — append three new policies:
```yaml
---
# nginx-gateway: accepts from istio ingress gateway only
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: nginx-gateway-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: nginx-gateway
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway"]
---
# ext-authz: accepts from istio ingress gateway only
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ext-authz-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: ext-authz
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway"]
---
# session-gateway: accepts from istio ingress gateway only
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: session-gateway-policy
  namespace: default
spec:
  selector:
    matchLabels:
      app: session-gateway
  action: ALLOW
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway"]
```

**Important:** The principal `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway` must match the actual ServiceAccount name verified in Session 1. If Istio names it differently, adjust before applying.

### Verification

1. `kubectl get peerauthentication -n default` — only `default-strict`
2. `kubectl get authorizationpolicy -n default` — now 7 policies (4 existing backend + 3 new ingress-facing)
3. `curl -k https://app.budgetanalyzer.localhost/` — still works
4. Probe test: a pod in `istio-ingress` with the ingress-gateway pod labels but a non-gateway ServiceAccount cannot reach `nginx-gateway:8080` — `AuthorizationPolicy` denied
5. Login flow works end-to-end

---

## Session 4: Egress Gateway and REGISTRY_ONLY (Phase 3c)

**Goal:** Deploy an Istio egress gateway, create ServiceEntries for Auth0 and FRED API, route outbound through the egress gateway, then flip mesh outbound to `REGISTRY_ONLY`.

### Files to Create

**`kubernetes/istio/egress-namespace.yaml`**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: istio-egress
  labels:
    istio-injection: enabled
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: v1.32
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: v1.32
```

**`kubernetes/istio/egress-service-entries.yaml`**
```yaml
# Auth0 IdP (used by session-gateway)
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: auth0-idp
  namespace: default
spec:
  hosts:
    - "dev-gcz1r8453xzz0317.us.auth0.com"  # Must match AUTH0_ISSUER_URI hostname
  location: MESH_EXTERNAL
  ports:
    - number: 443
      name: https
      protocol: TLS
  resolution: DNS
---
# FRED API (used by currency-service)
apiVersion: networking.istio.io/v1
kind: ServiceEntry
metadata:
  name: fred-api
  namespace: default
spec:
  hosts:
    - "api.stlouisfed.org"
  location: MESH_EXTERNAL
  ports:
    - number: 443
      name: https
      protocol: TLS
  resolution: DNS
```

**`kubernetes/istio/egress-routing.yaml`** — Istio networking Gateway + VirtualService + DestinationRule for egress routing:
```yaml
# Egress Gateway listener
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: istio-egress-gateway
  namespace: default
spec:
  selector:
    istio: istio-egress-gateway  # Must match egress pod labels
  servers:
    - port:
        number: 443
        name: tls-auth0
        protocol: TLS
      hosts:
        - "dev-gcz1r8453xzz0317.us.auth0.com"
      tls:
        mode: PASSTHROUGH
    - port:
        number: 443
        name: tls-fred
        protocol: TLS
      hosts:
        - "api.stlouisfed.org"
      tls:
        mode: PASSTHROUGH
---
# DestinationRule: mTLS to egress gateway
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egress-gateway-dr
  namespace: default
spec:
  host: istio-egress-gateway.istio-egress.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
---
# VirtualService: Auth0 via egress gateway
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: auth0-via-egress
  namespace: default
spec:
  hosts:
    - "dev-gcz1r8453xzz0317.us.auth0.com"
  gateways:
    - mesh
    - istio-egress-gateway
  tls:
    - match:
        - gateways: ["mesh"]
          port: 443
          sniHosts: ["dev-gcz1r8453xzz0317.us.auth0.com"]
      route:
        - destination:
            host: istio-egress-gateway.istio-egress.svc.cluster.local
            port:
              number: 443
    - match:
        - gateways: ["istio-egress-gateway"]
          port: 443
          sniHosts: ["dev-gcz1r8453xzz0317.us.auth0.com"]
      route:
        - destination:
            host: "dev-gcz1r8453xzz0317.us.auth0.com"
            port:
              number: 443
---
# VirtualService: FRED API via egress gateway
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: fred-api-via-egress
  namespace: default
spec:
  hosts:
    - "api.stlouisfed.org"
  gateways:
    - mesh
    - istio-egress-gateway
  tls:
    - match:
        - gateways: ["mesh"]
          port: 443
          sniHosts: ["api.stlouisfed.org"]
      route:
        - destination:
            host: istio-egress-gateway.istio-egress.svc.cluster.local
            port:
              number: 443
    - match:
        - gateways: ["istio-egress-gateway"]
          port: 443
          sniHosts: ["api.stlouisfed.org"]
      route:
        - destination:
            host: "api.stlouisfed.org"
            port:
              number: 443
```

### Files to Modify

**`Tiltfile`:**
1. Add `istio-egress-gateway` Helm resource (ClusterIP, depends: `istiod`)
2. Add `istio-egress-config` resource to apply ServiceEntries + egress routing (depends: `istio-egress-gateway`, `istiod`)
3. Do **not** add a persistent `istio-registry-only` override resource. After `istio-egress-config` is ready, update the canonical `istiod` values file to `REGISTRY_ONLY` and re-run the existing `istiod` resource.
4. Add `istio-ingress` and `istio-egress` namespace labeling to `istio-injection` resource

**`kubernetes/istio/istiod-values.yaml`** — in Session 4, add the canonical outbound policy:
```yaml
meshConfig:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
```

This change happens only after the `ServiceEntry` and egress-routing resources are applied and verified.

### Verification

1. `kubectl get pods -n istio-egress` — egress gateway Running
2. `kubectl get serviceentry -n default` — `auth0-idp` and `fred-api`
3. Login flow works (session-gateway reaches Auth0 through egress gateway)
4. From a `currency-service` pod: `curl -I -sS https://api.stlouisfed.org` — succeeds (200/301/404 acceptable; connectivity is the proof)
5. From the same `currency-service` pod: `curl -I -sS https://example.com` — fails (not registered, `REGISTRY_ONLY`)
6. `kubectl logs -n istio-egress -l istio=istio-egress-gateway -c istio-proxy --tail=20` — shows TLS passthrough traffic for approved hosts only

### Note on Auth0 hostname

The Auth0 hostname (`dev-gcz1r8453xzz0317.us.auth0.com`) is derived from `AUTH0_ISSUER_URI` in `.env`. If the tenant changes, the ServiceEntry, Gateway servers, and VirtualService hosts must all be updated. Consider a future improvement to template this from the environment.

---

## Session 5: Egress NetworkPolicy Alignment (Phase 3d)

**Goal:** Add deny-all + allow policies for the `istio-egress` namespace and constrain approved application egress to the egress gateway only. Ingress-side policy alignment already happened in Session 2 so the cutover can work.

### Files to Create

**`kubernetes/network-policies/istio-egress-deny.yaml`** — deny-all for `istio-egress` namespace

**`kubernetes/network-policies/istio-egress-allow.yaml`** — allows for the egress gateway pod:
- DNS egress → kube-dns
- istiod egress → port 15012
- Ingress from approved default-namespace workloads → the egress gateway pod TLS target port (verify the rendered Service `targetPort`; do not assume it is `443`)
- Egress to external internet → port 443 (only this pod gets external access)

### Files to Modify

**`kubernetes/network-policies/default-allow.yaml`:**
1. **Modify** `allow-session-gateway-egress` — replace open `port: 443` with egress to `istio-egress` namespace only
2. **Modify** `allow-currency-service-egress` — replace open `port: 443` with egress to `istio-egress` namespace only

**`Tiltfile`:**
- Extend `istio-egress-network-policies` to apply the new `istio-egress` namespace files and depend on `istio-egress-gateway`
- Keep `network-policies-core` focused on `default` + `infrastructure` namespace files only; do not rely on one directory-wide apply for namespace-scoped resources that may not exist yet

### Verification

1. `kubectl get networkpolicy -n istio-egress` — deny-all + allows exist
2. `kubectl get networkpolicy -n default` — `session-gateway` and `currency-service` no longer have open `port: 443` egress
3. Full app flow works (login, API calls, logout)
4. From a transaction-service pod: `curl https://example.com` — fails (no egress path)
5. From a session-gateway pod: Auth0 reachable (routed through egress gateway)

---

## Session 6: Verification Script and Final Cleanup

**Goal:** Create a comprehensive verification script, remove any remaining Envoy Gateway artifacts, update documentation references.

### Files to Create

**`scripts/dev/verify-phase-3-istio-ingress.sh`** — runtime verification script covering:
1. Ingress path: `curl` returns 200 for app, 401 for unauthenticated API, 302 for login
2. Header sanitization: with a valid seeded session plus forged `X-User-Id` / `X-Roles` / `X-Permissions`, a temporary echo backend sees only the ext-authz-issued identity headers
3. mTLS enforcement: direct pod-to-service calls from unlabeled pods fail
4. AuthorizationPolicy: a pod in `istio-ingress` with ingress-gateway labels but the wrong ServiceAccount cannot reach `nginx-gateway`
5. Egress control: an approved host is reachable from `session-gateway` / `currency-service`, and an unapproved host is blocked from the same workloads
6. Edge behavior after Envoy removal: auth endpoints still rate limit correctly and NGINX still sees the expected client IP / forwarded chain
7. Envoy Gateway absent: no pods in `envoy-gateway-system`
8. Gateway inventory: only the expected Istio Gateway API and Istio networking resources exist

### Files to Modify

**`Tiltfile`:**
- Remove the one-time `envoy-gateway-cleanup` resource (cleanup already ran in Session 2)
- Verify final dependency graph is clean:
  ```
  gateway-api-crds
  istio-base → istiod
    ├── istio-injection (namespace labeling)
    │   ├── [all workloads]
    │   ├── network-policies-core
    │   └── istio-security-policies
    ├── istio-gateway-class → istio-ingress-config
    │                           ├── istio-ingress-network-policies
    │                           └── istio-ingress-routes → istio-ingress-cutover
    └── istio-egress-gateway → istio-egress-config
                                └── istio-egress-network-policies
  mkcert-tls-secret → istio-ingress-config
  ```

**Documentation updates required in the same implementation work:**
- `nginx/README.md` — replace Envoy Gateway references with Istio ingress terminology and troubleshooting
- `docs/development/local-environment.md` — update entrypoint, topology, and verification commands
- `docs/architecture/system-overview.md` — update ingress/egress component inventory
- `docs/architecture/security-architecture.md` — update edge authn/authz and egress-control narrative
- `docs/architecture/port-reference.md` — update ingress and egress gateway port ownership
- `docs/architecture/bff-api-gateway-pattern.md` — update the browser request flow from Envoy Gateway to Istio ingress

---

## Complete File Change Inventory

### New Files (14)
| File | Session |
|------|---------|
| `kubernetes/istio/ingress-namespace.yaml` | 1 |
| `kubernetes/istio/istiod-values.yaml` | 1, 4 |
| `kubernetes/istio/istio-gatewayclass.yaml` | 1 |
| `kubernetes/istio/istio-gateway.yaml` | 1 |
| `kubernetes/istio/tls-reference-grant.yaml` | 1 |
| `kubernetes/istio/ext-authz-policy.yaml` | 2 |
| `kubernetes/network-policies/istio-ingress-deny.yaml` | 2 |
| `kubernetes/network-policies/istio-ingress-allow.yaml` | 2 |
| `kubernetes/istio/egress-namespace.yaml` | 4 |
| `kubernetes/istio/egress-service-entries.yaml` | 4 |
| `kubernetes/istio/egress-routing.yaml` | 4 |
| `kubernetes/network-policies/istio-egress-deny.yaml` | 5 |
| `kubernetes/network-policies/istio-egress-allow.yaml` | 5 |
| `scripts/dev/verify-phase-3-istio-ingress.sh` | 6 |

### Modified Files (12)
| File | Session | Change |
|------|---------|--------|
| `kubernetes/gateway/api-httproute.yaml` | 2 | Temporary dual parentRefs during cutover, final state → `istio-ingress-gateway` only |
| `kubernetes/gateway/auth-httproute.yaml` | 2 | Temporary dual parentRefs during cutover, final state → `istio-ingress-gateway` only |
| `kubernetes/gateway/app-httproute.yaml` | 2 | Temporary dual parentRefs during cutover, final state → `istio-ingress-gateway` only |
| `kubernetes/istio/peer-authentication.yaml` | 3 | Remove 3 PERMISSIVE exceptions |
| `kubernetes/istio/authorization-policies.yaml` | 3 | Add 3 ingress-facing policies |
| `kubernetes/network-policies/default-allow.yaml` | 2, 5 | Replace Envoy ingress refs → Istio ingress; later constrain TCP/443 egress → egress gateway only |
| `nginx/README.md` | 6 | Replace Envoy Gateway references and troubleshooting guidance |
| `docs/development/local-environment.md` | 6 | Update entrypoint, topology, and verification commands |
| `docs/architecture/system-overview.md` | 6 | Update ingress and egress component narrative |
| `docs/architecture/security-architecture.md` | 6 | Update edge authorization and outbound-control description |
| `docs/architecture/port-reference.md` | 6 | Update gateway port ownership |
| `docs/architecture/bff-api-gateway-pattern.md` | 6 | Update request flow to Istio ingress |

### Deleted Files (5)
| File | Session |
|------|---------|
| `kubernetes/gateway/envoy-proxy-config.yaml` | 2 |
| `kubernetes/gateway/envoy-proxy-gatewayclass.yaml` | 2 |
| `kubernetes/gateway/client-traffic-policy.yaml` | 2 |
| `kubernetes/gateway/ext-authz-security-policy.yaml` | 2 |
| `kubernetes/gateway/gateway.yaml` | 2 |

### Tiltfile (modified across all sessions)
Major changes: remove 4 Envoy Gateway resources, add ~9 Istio and policy resources, restructure the dependency graph, and switch `istiod` to a canonical values file.

---

## Risk Mitigations

1. **ServiceAccount naming** — Verify the exact SA name with `kubectl get sa -n istio-ingress` in Session 1 before writing AuthorizationPolicy principals in Session 3. If Istio names it differently than `istio-ingress-gateway`, adjust all principals.

2. **NodePort conflict** — Keep the standby Istio ingress Service on NodePort `30444` until `envoy-gateway-cleanup` completes. Only then patch to `30443`. The Kind port mapping (`kind-cluster-config.yaml:19-21`) already maps `30443` → host `443`.

3. **Canonical outbound policy state** — Do not keep `ALLOW_ANY` in the base values file. ServiceEntries and egress routing are applied first; then Session 4 updates the canonical `istiod-values.yaml` to `REGISTRY_ONLY` and re-runs `istiod`. This prevents a later `istiod` re-apply from silently reopening internet egress.

4. **Auth0 hostname** — The ServiceEntry hostname must match the `AUTH0_ISSUER_URI` environment variable. Hardcoded for the current dev tenant; document the need to update if the tenant changes.

5. **Gateway label selectors** — Both the ingress `AuthorizationPolicy` selector and the ingress/egress `NetworkPolicy` pod selectors must use rendered labels from the actual gateway pods. Verify with `kubectl get deploy,pods -n istio-ingress --show-labels` and `kubectl get pods -n istio-egress --show-labels` before writing selectors.

6. **Deleted PERMISSIVE resources** — The three PERMISSIVE PeerAuthentication resources must be explicitly deleted from the cluster (not just removed from the YAML file) since `kubectl apply` doesn't delete removed documents. Add `kubectl delete peerauthentication nginx-gateway-permissive ext-authz-permissive session-gateway-permissive -n default --ignore-not-found` to the istio-security-policies resource command.

7. **Gateway route attachment scope** — The Istio Gateway should not allow routes from arbitrary namespaces. Restrict `allowedRoutes` to the `default` namespace only.

8. **Client IP and rate limiting after Envoy removal** — Removing Envoy's `ClientTrafficPolicy` also removes the only explicit client IP handling configuration. Session 6 must prove that NGINX still sees the expected client IP / forwarded chain and that auth endpoints still rate limit as intended.

9. **Egress gateway target port** — `NetworkPolicy` must match the egress gateway pod's rendered TLS target port, not an assumed Service port. Verify the generated Service/Deployment before writing the allowlist.

---

## End-to-End Verification

After all sessions, verify:

1. `kubectl get ns envoy-gateway-system` — NotFound
2. `kubectl get gatewayclasses.gateway.networking.k8s.io` — only `istio`
3. `kubectl get gateways.gateway.networking.k8s.io -A` — only `istio-ingress-gateway` in `istio-ingress`
4. `kubectl get gateways.networking.istio.io -A` — only `istio-egress-gateway` in `default`
5. `kubectl get peerauthentication -n default` — only `default-strict`
6. `kubectl get authorizationpolicy -n default` — 7 policies (4 backend + 3 ingress-facing)
7. `kubectl get authorizationpolicy -n istio-ingress` — `ext-authz-at-ingress`
8. `kubectl get serviceentry -n default` — `auth0-idp`, `fred-api`
9. `tilt up` succeeds from clean rebuild
10. Full browser flow: login → API calls → logout
11. Spoofed identity headers do not survive the trusted ingress path
12. Run `scripts/dev/verify-phase-3-istio-ingress.sh` — all checks pass
