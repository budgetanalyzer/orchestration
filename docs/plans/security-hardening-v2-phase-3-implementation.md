# Phase 3: Istio Ingress and Egress Unification — Implementation Plan

## Context

The current ingress architecture has a structural security seam: Envoy Gateway operates **outside** the Istio service mesh. It has no SPIFFE identity and cannot participate in mTLS. This means:

- Ingress-facing services (`nginx-gateway`, `ext-authz`, `session-gateway`) must run in PERMISSIVE mTLS mode
- These services cannot have Istio `AuthorizationPolicy` enforcement because Envoy Gateway presents no mesh identity
- Egress to the public internet is controlled only by generic `NetworkPolicy` TCP/443 rules, which are not hostname-aware

Phase 3 eliminates this seam by replacing Envoy Gateway with Istio-managed ingress and egress gateways, bringing the entire traffic path inside the mesh.

**Prerequisite status:** Phase 1 (credentials) and Phase 2 (NetworkPolicy authoring) are implemented. NetworkPolicy manifests are authored but Tilt rollout is deferred to this phase.

**Simplification note:** This is a reference architecture with no live users or forks. There is no need for dual-parent cutover strategies, temporary standby NodePorts, or staged migrations. Existing local cluster state still needs a clean replacement step: remove Envoy Gateway completely, then install Istio ingress on the real NodePort (`30443`).

---

## Key Architectural Decisions

**1. Gateway API (not VirtualService) for ingress.** Istio v1.24 natively implements the Gateway API specification. The existing HTTPRoute resources (`api-httproute.yaml`, `auth-httproute.yaml`, `app-httproute.yaml`) are controller-agnostic — they reference a parent Gateway by name, not by controller. They can be reused by updating `parentRefs` to point at an Istio-backed Gateway. No VirtualService resources are needed for ingress.

**2. Istio auto-provisioned ingress gateway.** Rather than deploying the `istio/gateway` Helm chart separately, let Istio auto-create the gateway Deployment and Service from the Gateway API resource. This is the standard Istio Gateway API pattern. A `kubectl patch` sets the specific NodePort (30443) to match the existing Kind cluster port mapping (`kind-cluster-config.yaml` line 19-21: `containerPort: 30443` → `hostPort: 443`) after the old Envoy Gateway resources are removed.

**3. `istio-ingress` namespace.** The ingress gateway deploys in its own namespace with sidecar injection enabled, giving it a SPIFFE identity in that namespace.

**4. ext_authz via meshConfig extensionProviders.** Istio supports external authorization through `meshConfig.extensionProviders` + `AuthorizationPolicy` with `action: CUSTOM`. The ext-authz Go service already speaks the HTTP ext_authz protocol — no code changes required. This replaces the Envoy Gateway `SecurityPolicy`.

**5. Istio networking API for egress routing.** Egress gateway routing uses `ServiceEntry` + Istio networking `Gateway` + `VirtualService` + `DestinationRule` (the mature pattern), not Gateway API.

**6. Egress gateway via checked-in manifest.** The egress gateway is deployed in `istio-egress` namespace from a checked-in manifest rendered from the upstream `istio/gateway` chart `1.24.3` (ClusterIP, no external exposure). The rendered resource names stay `istio-egress-gateway` so the Service DNS name remains `istio-egress-gateway.istio-egress.svc.cluster.local` — the `DestinationRule` and `VirtualService` resources depend on this exact name.

**7. Canonical outbound policy in istiod values.** The `istiod-values.yaml` file is the single source of truth for mesh configuration. `outboundTrafficPolicy` is left unset until Session 3, which adds `REGISTRY_ONLY` only after ServiceEntries and egress routing are verified. This prevents a later `istiod` re-apply from silently reopening internet egress.

**8. GatewayClass.** Istio 1.24 auto-creates the `istio` GatewayClass when istiod starts. A manual `istio-gatewayclass.yaml` is not needed — the Tilt resource just depends on `istiod` directly.

---

## Session 1: Replace Envoy Gateway with Istio Ingress

**Goal:** Remove Envoy Gateway entirely, including any existing local-cluster Helm state, install the Istio ingress gateway with ext_authz, update HTTPRoutes, and replace ingress-side NetworkPolicies. At the end of this session, all ingress traffic flows through Istio.

**Cluster-state assumption:** This session must succeed both from a fresh Kind cluster and from an already-bootstrapped local dev cluster. There is no coexistence period, but there is an explicit cleanup step so `30443` is actually free before the Istio Gateway is patched onto it.

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
  # outboundTrafficPolicy left unset until Session 3 adds REGISTRY_ONLY
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
apiVersion: gateway.networking.k8s.io/v1
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
      gateway.networking.k8s.io/gateway-name: istio-ingress-gateway  # Verified against the auto-provisioned Istio gateway labels
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
- External ingress → ingress gateway pod TLS target port (`443` on the live auto-provisioned Istio Service)
- Egress to default namespace services: `nginx-gateway:8080`, `ext-authz:9002`, `session-gateway:8081`
- Pod selectors must use the actual rendered ingress-gateway labels; verify with `kubectl get pods -n istio-ingress --show-labels` before writing selectors

### Files to Modify

**`kubernetes/gateway/api-httproute.yaml`** — change parentRef to Istio:
```yaml
  parentRefs:
  - name: istio-ingress-gateway
    namespace: istio-ingress
```

**`kubernetes/gateway/auth-httproute.yaml`** — same parentRef change

**`kubernetes/gateway/app-httproute.yaml`** — same parentRef change

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
1. Modify the `istiod` resource to use `--values kubernetes/istio/istiod-values.yaml` instead of inline `--set` flags
2. Remove entirely from the steady-state graph: `envoy-gateway` Helm resource, `envoy-proxy-config`, `gateway-class` (Envoy's), old `ingress-gateway`
3. Remove `envoy-gateway` from `istio-injection` resource_deps
4. Remove `envoy-gateway-system` namespace labeling from `istio-injection`
5. Do **not** add `istio-ingress` namespace labeling to `istio-injection`; `ingress-namespace.yaml` is the source of truth and must create the namespace with labels before the gateway exists
6. Add a one-time `envoy-gateway-cleanup` resource that:
   - Runs before `istio-ingress-config` when upgrading an existing local cluster, and is a no-op on a fresh cluster
   - Uninstalls the existing Helm release: `helm uninstall envoy-gateway -n envoy-gateway-system --ignore-not-found || true`
   - Explicitly deletes the old Envoy-specific resources (`gateway.yaml`, `client-traffic-policy.yaml`, `ext-authz-security-policy.yaml`, `envoy-proxy-gatewayclass.yaml`, `envoy-proxy-config.yaml`) so removing Tilt resources does not leave old objects behind
7. Add `istio-ingress-config` resource that:
   - Applies `ingress-namespace.yaml`, `tls-reference-grant.yaml`, `istio-gateway.yaml`
   - Waits for the auto-provisioned Service: `kubectl wait --for=condition=Programmed gateway/istio-ingress-gateway -n istio-ingress --timeout=120s`
   - Patches NodePort to 30443: `kubectl patch svc -n istio-ingress istio-ingress-gateway-istio --type=json -p='[{"op":"replace","path":"/spec/ports/1/nodePort","value":30443}]'` (Note: Istio auto-provisions the Service as `<gateway-name>-istio`, and the HTTPS port is at index 1 — index 0 is status-port/15021)
   - Depends: `envoy-gateway-cleanup`, `istiod`, `gateway-api-crds`, `mkcert-tls-secret`
8. Replace old `ingress-gateway` resource with `istio-ingress-routes` that applies HTTPRoutes + `ext-authz-policy.yaml` (depends: `istio-ingress-config`, `istio-ingress-network-policies`, `ext-authz`, `nginx-gateway`)
9. Split the existing `network-policies` resource into:
   - `network-policies-core` — applies `default-deny.yaml`, `default-allow.yaml`, `infrastructure-deny.yaml`, `infrastructure-allow.yaml`
   - `istio-ingress-network-policies` — applies `istio-ingress-deny.yaml`, `istio-ingress-allow.yaml` (depends: `istio-ingress-config`)

### Files to Delete

- `kubernetes/gateway/envoy-proxy-config.yaml`
- `kubernetes/gateway/envoy-proxy-gatewayclass.yaml`
- `kubernetes/gateway/client-traffic-policy.yaml`
- `kubernetes/gateway/ext-authz-security-policy.yaml`
- `kubernetes/gateway/gateway.yaml`

### Files to Keep

The three HTTPRoute files stay in `kubernetes/gateway/` — they are controller-agnostic Gateway API resources.

### Verification

1. `kubectl get pods -n istio-ingress` — gateway pod Running
2. `kubectl get gateway -n istio-ingress istio-ingress-gateway` — `Programmed=True`
3. `kubectl get cm istio -n istio-system -o yaml | grep ext-authz-http` — extension provider registered
4. `kubectl get deploy,pods,sa -n istio-ingress --show-labels` — note the exact ServiceAccount name and rendered pod labels (needed in Session 2)
5. `curl -k https://app.budgetanalyzer.localhost/` — returns React app
6. `curl -k https://app.budgetanalyzer.localhost/api/v1/transactions` — returns 401/403 (ext-authz denies unauthenticated)
7. `curl -k https://app.budgetanalyzer.localhost/login` — returns 302 redirect to Auth0
8. `kubectl get networkpolicy -n istio-ingress` — deny-all + allow policies exist
9. `kubectl get ns envoy-gateway-system` — NotFound or present but empty
10. Full login flow works end-to-end

---

## Session 2: STRICT mTLS and Ingress-Facing AuthorizationPolicies

**Goal:** Remove PERMISSIVE PeerAuthentication exceptions. Add AuthorizationPolicies for ingress-facing services restricting them to the Istio ingress gateway identity only.

### Files to Modify

**`kubernetes/istio/peer-authentication.yaml`** — remove the three PERMISSIVE resources (`nginx-gateway-permissive`, `ext-authz-permissive`, `session-gateway-permissive`). Only `default-strict` remains:
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
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio"]
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
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio"]
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
            principals: ["cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio"]
```

**Important:** The principal must match the actual ingress gateway ServiceAccount. In the current auto-provisioned deployment that identity is `cluster.local/ns/istio-ingress/sa/istio-ingress-gateway-istio`; verify with `kubectl get deploy,sa -n istio-ingress -o yaml` before applying after Istio upgrades.

**`Tiltfile`** — update the `istio-security-policies` resource to explicitly delete the removed PERMISSIVE resources before applying:
```
kubectl delete peerauthentication nginx-gateway-permissive ext-authz-permissive session-gateway-permissive -n default --ignore-not-found
kubectl apply -f kubernetes/istio/peer-authentication.yaml
kubectl apply -f kubernetes/istio/authorization-policies.yaml
```

This is necessary because `kubectl apply` does not delete resources removed from a multi-document YAML file.

### Verification

1. `kubectl get peerauthentication -n default` — only `default-strict`
2. `kubectl get authorizationpolicy -n default` — now 7 policies (4 existing backend + 3 new ingress-facing)
3. `curl -k https://app.budgetanalyzer.localhost/` — still works
4. Login flow works end-to-end

---

## Session 3: Egress Gateway and REGISTRY_ONLY — IMPLEMENTED

**Goal:** Deploy an Istio egress gateway, create ServiceEntries for Auth0 and FRED API, route outbound through the egress gateway, add egress NetworkPolicies, then flip mesh outbound to `REGISTRY_ONLY`.

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

**`kubernetes/istio/egress-gateway.yaml`** — checked-in render of the upstream `istio/gateway` chart `1.24.3` for the `istio-egress-gateway` `ServiceAccount`, RBAC, `Service`, `Deployment`, and `HorizontalPodAutoscaler`. Keep the resource name `istio-egress-gateway` and the workload labels `app: istio-egress-gateway` / `istio: egress-gateway`.

**`kubernetes/istio/egress-gateway.provenance.md`** — the render command and rationale for vendoring the manifest instead of using `helm upgrade --install` at runtime.

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
    istio: egress-gateway  # Must match the vendored egress-gateway workload labels
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
# DestinationRule: disable auto-mTLS so the original TLS passes through to the
# egress gateway's PASSTHROUGH listener, which needs to see the external-host SNI.
# ISTIO_MUTUAL wraps the connection in mesh TLS, hiding the original SNI and causing
# connection resets. The original TLS (e.g., Auth0's certificate) still provides
# end-to-end encryption; only the intra-cluster hop is not double-encrypted.
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: egress-gateway-dr
  namespace: default
spec:
  host: istio-egress-gateway.istio-egress.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
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

**`kubernetes/network-policies/istio-egress-deny.yaml`** — deny-all for `istio-egress` namespace

**`kubernetes/network-policies/istio-egress-allow.yaml`** — allows for the egress gateway pod:
- DNS egress → kube-dns
- istiod egress → port 15012
- Ingress from approved default-namespace workloads → the egress gateway pod TLS target port (verify the rendered Service `targetPort`; do not assume it is `443`)
- Egress to external internet → port 443 (only this pod gets external access)

### Files to Modify

**`kubernetes/network-policies/default-allow.yaml`:**
1. **Modify** `allow-session-gateway-egress` — replace open `port: 443` with egress to the rendered `istio-egress-gateway` pods in the `istio-egress` namespace (`app: istio-egress-gateway`, `istio: egress-gateway`). The sidecar intercepts the original `auth0:443` connection and redirects it to the egress gateway pod, so the policy should target that workload directly instead of trusting the whole namespace.
2. **Modify** `allow-currency-service-egress` — replace open `port: 443` with egress to the rendered `istio-egress-gateway` pods in the `istio-egress` namespace

**`kubernetes/istio/istiod-values.yaml`** — add the canonical outbound policy:
```yaml
meshConfig:
  outboundTrafficPolicy:
    mode: REGISTRY_ONLY
```

**`Tiltfile`:**
1. Add `istio-egress-namespace` resource that applies `egress-namespace.yaml` (depends: `istiod`)
2. Add `istio-egress-gateway` resource that uninstalls any old Helm release with `--wait`, applies `kubernetes/istio/egress-gateway.yaml`, and waits for `deployment/istio-egress-gateway` rollout (depends: `istio-egress-namespace`). The checked-in manifest is rendered from `istio/gateway` `1.24.3` because Helm `v3.20.1` reproduces a chart-schema failure for the required `service.type=ClusterIP` override.
3. Do **not** add `istio-egress` namespace labeling to `istio-injection`; `egress-namespace.yaml` is the canonical source of labels
4. Add `istio-egress-config` resource to apply ServiceEntries and egress routing (depends: `istio-egress-gateway`, `istiod`)
5. Add `istio-egress-network-policies` resource to apply `istio-egress-deny.yaml` and `istio-egress-allow.yaml` (depends: `istio-egress-config`)
6. After `istio-egress-config` is verified, the updated `istiod-values.yaml` (with `REGISTRY_ONLY`) takes effect on the next `istiod` resource run

### Note on Auth0 hostname

The Auth0 hostname (`dev-gcz1r8453xzz0317.us.auth0.com`) is derived from `AUTH0_ISSUER_URI` in `.env`. It appears in 6 places across 3 files (ServiceEntry, Gateway servers, two VirtualServices). If the tenant changes, all must be updated. Consider templating via a Tilt `local()` that reads from `.env` and generates the YAML.

### Verification

1. `kubectl get pods -n istio-egress` — egress gateway Running
2. `kubectl get serviceentry -n default` — `auth0-idp` and `fred-api`
3. Login flow works (session-gateway reaches Auth0 through egress gateway)
4. From a `currency-service` pod: `curl -I -sS https://api.stlouisfed.org` — succeeds (200/301/404 acceptable; connectivity is the proof)
5. From the same `currency-service` pod: `curl -I -sS https://example.com` — fails (not registered, `REGISTRY_ONLY`)
6. `kubectl logs -n istio-egress -l istio=egress-gateway -c istio-proxy --tail=20` — shows TLS passthrough traffic for approved hosts only
7. `kubectl get networkpolicy -n istio-egress` — deny-all + allows exist
8. `kubectl get networkpolicy -n default` — `session-gateway` and `currency-service` no longer have open `port: 443` egress

---

## Session 4: Verification Script and Documentation

**Goal:** Create a comprehensive verification script and update all documentation references from Envoy Gateway to Istio, including runtime proof for header sanitization, auth-path rate limiting, and forwarded-header preservation.

### Files to Create

**`scripts/dev/verify-phase-3-istio-ingress.sh`** — runtime verification script covering:
1. Ingress path: `curl` returns 200 for app, 401 for unauthenticated API, 302 for login
2. Header sanitization: with a valid seeded session plus forged `X-User-Id` / `X-Roles` / `X-Permissions`, a temporary echo backend sees only the ext-authz-issued identity headers
3. mTLS enforcement: a temporary in-mesh echo service returns 200 from a sidecar-injected probe and fails from a no-sidecar probe (`sidecar.istio.io/inject: "false"`)
4. AuthorizationPolicy: a pod in `istio-ingress` with a non-gateway ServiceAccount cannot reach `nginx-gateway:8080`
5. Egress control: an approved host is reachable from `session-gateway` / `currency-service`, and an unapproved host is blocked from the same workloads
6. Auth endpoint rate limiting: repeated requests to `/login`, `/auth/*`, `/oauth2/*`, `/logout`, and `/user` hit the ingress-layer throttle as designed; do not silently drop this check just because the ingress controller changed
7. Client IP: NGINX still sees the expected X-Forwarded-For chain for both frontend and authenticated API requests after Envoy Gateway removal
8. Envoy Gateway absent: no pods in `envoy-gateway-system`
9. Gateway inventory: required Istio Gateway API and Istio networking resources exist, and Envoy-era gateway resources are absent

### Files to Modify

**`Tiltfile`** — verify final dependency graph is clean:
```
gateway-api-crds
istio-base → istiod
  ├── istio-injection (namespace labeling for default, infrastructure)
  │   ├── [all workloads]
  │   ├── network-policies-core
  │   └── istio-security-policies
  ├── envoy-gateway-cleanup → istio-ingress-config
  │                           ├── istio-ingress-network-policies
  │                           └── istio-ingress-routes
  └── istio-egress-namespace → istio-egress-gateway → istio-egress-config
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

### Verification

Run `scripts/dev/verify-phase-3-istio-ingress.sh` after Phase 3 resources are deployed. Treat it as the runtime completion gate for Session 4 and the final documentation closure. Do not describe Phase 3 as complete until that verifier and the live validation checklist pass.

---

## Complete File Change Inventory

### New Files (16)
| File | Session |
|------|---------|
| `kubernetes/istio/ingress-namespace.yaml` | 1 |
| `kubernetes/istio/istiod-values.yaml` | 1, 3 |
| `kubernetes/istio/istio-gateway.yaml` | 1 |
| `kubernetes/istio/tls-reference-grant.yaml` | 1 |
| `kubernetes/istio/ext-authz-policy.yaml` | 1 |
| `kubernetes/istio/ingress-rate-limit.yaml` | 4 |
| `kubernetes/network-policies/istio-ingress-deny.yaml` | 1 |
| `kubernetes/network-policies/istio-ingress-allow.yaml` | 1 |
| `kubernetes/istio/egress-namespace.yaml` | 3 |
| `kubernetes/istio/egress-gateway.yaml` | 3 |
| `kubernetes/istio/egress-gateway.provenance.md` | 3 |
| `kubernetes/istio/egress-service-entries.yaml` | 3 |
| `kubernetes/istio/egress-routing.yaml` | 3 |
| `kubernetes/network-policies/istio-egress-deny.yaml` | 3 |
| `kubernetes/network-policies/istio-egress-allow.yaml` | 3 |
| `scripts/dev/verify-phase-3-istio-ingress.sh` | 4 |

### Modified Files (21)
| File | Session | Change |
|------|---------|--------|
| `AGENTS.md` | 1, 6 | Pin the supported Helm line for this repo and align the ingress/auth-throttling versus NGINX API-throttling story |
| `README.md` | 6 | Clarify the ingress/NGINX rate-limiting split and the Phase 3 runtime completion gate |
| `Tiltfile` | 1, 2, 3, 4 | Remove 4 Envoy resources, add ~8 Istio/policy resources, restructure dependency graph, switch istiod to values file |
| `scripts/dev/check-tilt-prerequisites.sh` | 1 | Reject unsupported Helm versions and point users at the tested Helm install path |
| `kubernetes/gateway/api-httproute.yaml` | 1 | parentRef → `istio-ingress-gateway` |
| `kubernetes/gateway/auth-httproute.yaml` | 1 | parentRef → `istio-ingress-gateway` |
| `kubernetes/gateway/app-httproute.yaml` | 1 | parentRef → `istio-ingress-gateway` |
| `kubernetes/network-policies/default-allow.yaml` | 1, 3 | Replace Envoy ingress refs → Istio ingress; constrain TCP/443 egress → egress gateway only |
| `kubernetes/istio/peer-authentication.yaml` | 2 | Remove 3 PERMISSIVE exceptions |
| `kubernetes/istio/authorization-policies.yaml` | 2 | Add 3 ingress-facing policies |
| `docs/development/devcontainer-installed-software.md` | 1 | Correct the installed/tested Helm version and document the vendored egress-gateway manifest |
| `docs/development/local-environment.md` | 1, 4 | Update the supported Helm version, egress-gateway install path, topology, and verification commands |
| `docs/tilt-kind-setup-guide.md` | 1 | Pin the tested Helm install path and explain the vendored egress-gateway path |
| `nginx/nginx.k8s.conf` | 4 | Emit forwarded-header details in the access log for Phase 3 verification |
| `nginx/README.md` | 4 | Replace Envoy Gateway references and troubleshooting |
| `docs/architecture/system-overview.md` | 4 | Update ingress/egress component narrative |
| `docs/architecture/security-architecture.md` | 4 | Update edge authorization and outbound-control |
| `docs/architecture/port-reference.md` | 4 | Update gateway port ownership |
| `docs/architecture/bff-api-gateway-pattern.md` | 4 | Update request flow to Istio ingress |
| `docs/plans/security-hardening-v2.md` | 6 | Record the final Phase 3 runtime gate and the PASSTHROUGH/DISABLE egress TLS rationale |
| `docs/plans/security-hardening-v2-phase-3-implementation.md` | 1, 6 | Record the vendored egress-gateway install path and final Phase 3 completion-gate wording |
| `docs/plans/security-hardening-v2-phase-3-remediation.md` | 1, 6 | Record the reproduced Helm v3.20.1 schema failure and the documentation-closure status note |

### Deleted Files (5)
| File | Session |
|------|---------|
| `kubernetes/gateway/envoy-proxy-config.yaml` | 1 |
| `kubernetes/gateway/envoy-proxy-gatewayclass.yaml` | 1 |
| `kubernetes/gateway/client-traffic-policy.yaml` | 1 |
| `kubernetes/gateway/ext-authz-security-policy.yaml` | 1 |
| `kubernetes/gateway/gateway.yaml` | 1 |

---

## Risk Mitigations

1. **ServiceAccount naming** — Verify the exact SA name with `kubectl get sa -n istio-ingress` after the gateway auto-provisions in Session 1. If Istio names it differently than `istio-ingress-gateway-istio`, adjust all AuthorizationPolicy principals in Session 2.

2. **Canonical outbound policy state** — Do not keep `ALLOW_ANY` in the base values file. ServiceEntries and egress routing are applied first; then Session 3 updates `istiod-values.yaml` to `REGISTRY_ONLY` and re-runs `istiod`. This prevents a later re-apply from silently reopening internet egress.

3. **Auth0 hostname** — The ServiceEntry hostname must match the `AUTH0_ISSUER_URI` environment variable. Hardcoded in 6 places across 3 files for the current dev tenant.

4. **Gateway label selectors** — Both the ingress `AuthorizationPolicy` selector and the ingress/egress `NetworkPolicy` pod selectors must use rendered labels from the actual gateway pods. Verify with `kubectl get pods -n istio-ingress --show-labels` and `kubectl get pods -n istio-egress --show-labels` before writing selectors.

5. **Deleted PERMISSIVE resources** — The three PERMISSIVE PeerAuthentication resources must be explicitly deleted from the cluster via `kubectl delete`, not just removed from the YAML file. This is handled in Session 2's Tiltfile changes.

6. **Gateway route attachment scope** — The Istio Gateway restricts `allowedRoutes` to the `default` namespace only via label selector.

7. **Client IP and auth rate limiting after Envoy removal** — Removing Envoy's `ClientTrafficPolicy` removes the only explicit X-Forwarded-For handling, and switching ingress controllers does not remove the parent plan's auth-throttling requirement. Session 4's verification script must confirm NGINX still sees the expected client IP / forwarded chain for app and API traffic, and auth-sensitive paths are still rate limited at the ingress layer.

8. **Egress gateway target port** — `NetworkPolicy` must match the egress gateway pod's rendered TLS target port, not an assumed Service port. Verify the generated Service/Deployment before writing the allowlist.

9. **NodePort patch timing** — The Istio ingress auto-provisioned Service is created asynchronously. The `istio-ingress-config` resource must `kubectl wait --for=condition=Programmed` on the Gateway before patching the NodePort.

10. **Egress gateway naming** — The checked-in egress gateway manifest must keep the resource name `istio-egress-gateway` so the Service DNS name matches the `DestinationRule` host (`istio-egress-gateway.istio-egress.svc.cluster.local`).

---

## End-to-End Verification

After all sessions, verify:

1. `kubectl get ns envoy-gateway-system` — NotFound (or empty)
2. `kubectl get gatewayclass istio -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}'` — `True`
3. `kubectl get gatewayclass envoy-proxy` — NotFound
4. `kubectl get gateway.gateway.networking.k8s.io istio-ingress-gateway -n istio-ingress` — present and `Programmed=True`
5. `kubectl get gateway.networking.istio.io istio-egress-gateway -n default` — present
6. `kubectl get peerauthentication -n default` — only `default-strict`
7. `kubectl get authorizationpolicy -n default` — named backend and ingress-facing policies exist
8. `kubectl get authorizationpolicy -n istio-ingress` — `ext-authz-at-ingress`
9. `kubectl get serviceentry -n default` — `auth0-idp`, `fred-api`
10. `tilt up` succeeds from clean rebuild
11. Full browser flow: login → API calls → logout
12. Spoofed identity headers do not survive the trusted ingress path
13. Auth-sensitive ingress paths return throttled responses under repeated requests
14. Run `scripts/dev/verify-phase-3-istio-ingress.sh` — all checks pass
