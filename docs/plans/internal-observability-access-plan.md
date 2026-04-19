# Plan: Internal-Only Observability Access

**Status:** In progress
**Date:** 2026-04-19

## Decision

Use port-forwarding as the access model for observability in both local Tilt and
production OCI/k3s.

Grafana, Prometheus, Jaeger, and Kiali should remain cluster-internal services.
Do not publish public DNS records, public TLS certificates, Gateway listeners,
or HTTPRoutes for observability surfaces.

This keeps the portfolio deployment honest: the public demo shows the
application, while operator-only tooling stays behind Kubernetes and host access
controls.

## Rationale

Observability data is operationally sensitive even when a UI is read-only. It can
expose service topology, internal DNS names, request paths, errors, runtime
versions, traffic patterns, trace metadata, and accidental user identifiers.

For this repository, public observability would be harder to defend than a
simple internal-only model. Port-forwarding is not flashy, but it is a standard
operator access pattern for a single-node portfolio deployment and avoids
inventing a public access story that would not match normal production practice.

## Scope

- Keep Prometheus internal-only.
- Keep Grafana internal-only in production.
- Add Jaeger and Kiali to the local Tilt observability bundle first.
- When Jaeger and Kiali are later added to production, expose them as
  ClusterIP/internal services only.
- Use `kubectl port-forward` for direct operator access.
- Use SSH to the OCI host, or SSH local forwarding plus `kubectl port-forward`,
  when accessing production observability from a workstation.

## Non-Goals

- No public `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
  `jaeger.budgetanalyzer.org` route.
- No anonymous, read-only public dashboards.
- No demo landing-page links to live observability UIs.
- No reuse of the application session model as a shortcut for operator access.
- No public GET-only AuthorizationPolicy workaround for observability.

## Immediate Cleanup

Harden the current production Grafana posture before resuming deferred Phase 10
work:

- Remove Grafana from the production public Gateway/HTTPRoute render path.
- Remove the production requirement for `GRAFANA_DOMAIN`.
- Stop rendering `grafana.budgetanalyzer.org` as a production route or root URL.
- Keep Grafana authentication enabled; do not enable anonymous access.
- Keep the Grafana Service as `ClusterIP`.
- Document the production access path as port-forward-only.

### Immediate Cleanup Implementation Plan

This cleanup has two parts:

1. Make the repo-owned production render path stop publishing Grafana.
2. Remove any already-applied Grafana public route or OCI routing residue from
   the live instance.

Do the repo changes first. `kubectl apply` does not prune resources that were
removed from a kustomize render, so the live OCI cleanup still needs explicit
delete/verification commands after the new render is reviewed.

**Repo-side status, 2026-04-19:** Steps 1 through 3 are complete for the
checked-in/rendered repository state. The local baseline render captured the
previous public Grafana route, the production render path now emits app-only
Gateway routes plus a loopback Grafana Helm override, and validation passed
with `bash -n`, `shellcheck`, the phase-6 renderer, the production image/render
verifier, and the no-public-Grafana grep. Live OCI route deletion and
verification remain in steps 4 through 6.

#### 1. Baseline The Current State

From the orchestration repo, capture the checked-in and rendered state:

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
rg -n 'grafana\.budgetanalyzer\.org|GRAFANA_DOMAIN|name: grafana-route' \
  deploy kubernetes scripts docs/plans/internal-observability-access-plan.md
```

From the OCI host or from a workstation with production kubeconfig access,
capture the live route and service shape:

```bash
kubectl get gateway -n istio-ingress istio-ingress-gateway -o yaml
kubectl get httproute -A
kubectl get httproute -n monitoring grafana-route -o yaml || true
kubectl get svc -n monitoring prometheus-stack-grafana -o yaml
helm get values prometheus-stack -n monitoring --all
```

If the host was part of the earlier host-redirect experiment, also inspect the
instance firewall/NAT state before changing anything:

```bash
sudo iptables -S INPUT | grep -E 'dport (80|443|30080|30443)' || true
sudo iptables -t nat -S PREROUTING | grep -E 'dport (80|443).*REDIRECT' || true
```

#### 2. Update The Repo-Owned Production Render Path

Change only orchestration-owned manifests, scripts, and documentation.

- In `kubernetes/production/gateway-routes/kustomization.yaml`, remove
  `../../monitoring/grafana-httproute.yaml` from `resources` and remove the
  patch targeting `HTTPRoute/grafana-route`.
- Leave `kubernetes/monitoring/grafana-httproute.yaml` in place for the current
  local Tilt path until the separate local Grafana ingress decision is made.
- In `deploy/scripts/13-render-phase-6-production-manifests.sh`, remove the
  locked Grafana hostname constant, remove `GRAFANA_DOMAIN` from required
  environment variables, remove the Grafana-domain validation, and update the
  usage/help text so the script renders app routes, ingress policies, the
  production Grafana port-forward override, and egress manifests.
- In `deploy/instance.env.template`, remove `GRAFANA_DOMAIN`. Keep
  `KIALI_DOMAIN` and `JAEGER_DOMAIN` absent or blank; do not introduce future
  public observability hostnames as placeholders.
- Change `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
  from a public-host override to a port-forward override:

  ```yaml
  grafana:
    grafana.ini:
      server:
        domain: localhost
        root_url: http://localhost:3000
      security:
        cookie_secure: false
  ```

  Keep Grafana authentication enabled. Do not set
  `grafana.grafana.ini.auth.anonymous.enabled=true`, do not add anonymous
  Helm values, and do not change the Grafana Service away from `ClusterIP`.
  The `cookie_secure: false` production override is acceptable only because the
  intended access path is loopback-bound `kubectl port-forward`; it prevents
  browser login failures over `http://localhost:3000`.
- Update `scripts/guardrails/verify-production-image-overlay.sh` so the
  production verifier expects the new contract:
  - no `GRAFANA_DOMAIN` in the temporary instance env
  - no `grafana-route` in `tmp/phase-6/gateway-routes.yaml`
  - no `grafana.budgetanalyzer.org` in any phase-6 render output
  - `tmp/phase-6/prometheus-stack-values.override.yaml` contains the
    loopback `root_url`
  - the production Grafana Service remains represented only through the Helm
    stack, not through a Gateway `HTTPRoute`
- Update affected docs in the same change:
  - `deploy/README.md`: production route render no longer includes Grafana;
    live cleanup requires explicit deletion of stale `grafana-route`
  - `kubernetes/production/README.md`: production routing inputs are app-only;
    monitoring override is for loopback port-forward access
  - `docs/architecture/observability.md`: production Grafana access is
    port-forward-only; local ingress remains a temporary local-development
    convenience until the deferred local cleanup
  - `README.md` and `AGENTS.md` only if their quick-start or entry-point text
    still describes production Grafana as public

Do not remove `allow-istio-ingress-egress-to-grafana` from
`kubernetes/network-policies/istio-ingress-allow.yaml` in this immediate
routing cleanup unless you also split local and production NetworkPolicy
application and update `deploy/scripts/08-verify-network-policy-enforcement.sh`.
That allow rule is not a public route by itself; the public exposure is the
Gateway/HTTPRoute plus DNS path. Removing it globally would break the current
local Grafana ingress path before the deferred local cleanup is designed.

#### 3. Validate The Repo Change Before Touching OCI

Run the normal static checks for the edited files:

```bash
bash -n deploy/scripts/13-render-phase-6-production-manifests.sh
shellcheck deploy/scripts/13-render-phase-6-production-manifests.sh
./deploy/scripts/13-render-phase-6-production-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

Then assert the production render no longer contains a public observability
surface:

```bash
rg -n 'grafana\.budgetanalyzer\.org|name: grafana-route|GRAFANA_DOMAIN' \
  tmp/phase-6 deploy kubernetes/production scripts/guardrails/verify-production-image-overlay.sh
```

The only acceptable remaining matches after the cleanup should be historical
mentions in this plan or in local-only Tilt documentation. Production render
output under `tmp/phase-6/` must have no matches.

#### 4. Apply The App-Only Route Render On OCI

On the OCI host, make the reviewed repo state available through the normal
operator-controlled workflow, then render and review the production output
again:

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
sed -n '1,260p' tmp/phase-6/gateway-routes.yaml
sed -n '1,120p' tmp/phase-6/prometheus-stack-values.override.yaml
```

Apply the app route render and explicitly delete the stale Grafana route:

```bash
kubectl apply -f tmp/phase-6/gateway-routes.yaml
kubectl delete httproute -n monitoring grafana-route --ignore-not-found
```

If the production Grafana Helm release was previously installed with the public
root URL override, reconcile it with the loopback override:

```bash
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --version 83.4.0 \
  --values kubernetes/monitoring/prometheus-stack-values.yaml \
  --values tmp/phase-6/prometheus-stack-values.override.yaml \
  --wait --timeout 10m
```

Do not delete the `monitoring` namespace, the `prometheus-stack` release, the
Prometheus resources, Grafana dashboards, or the Grafana Service. The cleanup
removes public routing, not observability itself.

#### 5. Clean Up OCI Public Routing Residue

If `grafana.budgetanalyzer.org` has a public DNS record, remove it or leave it
unpublished before considering the cleanup complete. If DNS is managed outside
this repo, record the provider-side change in the deployment notes rather than
encoding provider state in Kubernetes.

The current app NLB listener/backend path is shared by host-based HTTP routing,
so do not delete the app listener or app backend set just because Grafana used
the same ingress gateway. Only remove Grafana-specific DNS, certificates,
listeners, backend sets, NSG rules, or manual redirects if any were created.

If stale Step 15 host redirects or debug-only direct-instance rules are still
present, remove them on the OCI host:

```bash
while sudo iptables -C INPUT -p tcp --dport 30080 -j ACCEPT 2>/dev/null; do
  sudo iptables -D INPUT -p tcp --dport 30080 -j ACCEPT
done
while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT 2>/dev/null; do
  sudo iptables -D INPUT -m state --state NEW -p tcp --dport 80 -j ACCEPT
done
while sudo iptables -C INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT 2>/dev/null; do
  sudo iptables -D INPUT -m state --state NEW -p tcp --dport 443 -j ACCEPT
done
while IFS= read -r rule; do
  sudo iptables -t nat ${rule}
done < <(
  sudo iptables -t nat -S PREROUTING | awk '
    $1 == "-A" && $2 == "PREROUTING" &&
    ($0 ~ /--dport 80 / || $0 ~ /--dport 443 /) &&
    $0 ~ /-j REDIRECT/ {
      sub(/^-A /, "-D ")
      print
    }
  '
)
sudo netfilter-persistent save
```

After cleanup, direct public traffic should enter through the OCI NLB only.
Keep the app's required NLB rules for `80 -> 30080` and, after public TLS
cutover, `443 -> 30443`.

#### 6. Verify The Live Result

Cluster checks:

```bash
kubectl get httproute -A
kubectl get httproute -n monitoring grafana-route -o yaml || true
kubectl get gateway -n istio-ingress istio-ingress-gateway -o yaml | \
  grep -E 'grafana|kiali|jaeger' || true
kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.spec.type}{"\n"}'
```

Expected results:

- `HTTPRoute/monitoring/grafana-route` is absent.
- No Gateway listener or route references Grafana, Kiali, or Jaeger.
- `svc/prometheus-stack-grafana` remains `ClusterIP`.

Operator access check:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 \
  --address 127.0.0.1
```

Open `http://localhost:3000`, log in with the Grafana admin credentials from
`Secret/monitoring/prometheus-stack-grafana`, and confirm the provisioned
dashboards still load. For workstation access through the OCI host, keep both
the SSH tunnel and the Kubernetes port-forward bound to loopback.

Public reachability checks from a machine outside OCI:

```bash
curl -I http://demo.budgetanalyzer.org
curl -I http://grafana.budgetanalyzer.org || true
curl -k -I https://grafana.budgetanalyzer.org || true
```

The app host should continue to respond through the reviewed app route.
`grafana.budgetanalyzer.org` should fail DNS, fail connection, fail TLS, or
return no matching route. It must not return the Grafana login page, Grafana
health response, or a Grafana redirect.

#### 7. Rollback Boundary

If the app route breaks, rollback by restoring the app `HTTPRoute` render or
the app NLB/NSG path. Do not rollback by republishing Grafana. Observability
access during incident recovery remains:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 \
  --address 127.0.0.1
```

If Grafana login fails after the public route is removed, inspect the Helm
values and browser cookie behavior first; the likely fix is the production
loopback `root_url`/`cookie_secure` override, not a public route.

## Local Tilt Direction

Local Tilt should install the observability tools needed to debug and explain
the system, but access should remain operator-oriented:

- Grafana: port-forward preferred; local ingress can be removed or treated as a
  temporary developer convenience until the internal-only model is aligned.
- Prometheus: continue port-forward-only.
- Jaeger: add as a local observability resource with no public ingress.
- Kiali: add as a local observability resource with no public ingress.

Example local access pattern:

```bash
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

Jaeger and Kiali commands should be added after their namespaces, release names,
and service names are finalized.

## Production Direction

Production observability access should require operator access to the OCI host
or to the cluster credentials.

Baseline pattern:

```bash
ssh <oci-host>
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3000:80 --address 127.0.0.1
```

If workstation browser access is needed, use SSH local forwarding to the OCI
host and keep the Kubernetes port-forward bound to loopback.

## Deferred Work

- Decide whether local Grafana ingress should be removed entirely.
- Add Jaeger local Tilt manifests/Helm values.
- Add Kiali local Tilt manifests/Helm values.
- Decide whether production should include Jaeger/Kiali at all, or whether they
  remain local-only observability tools.
- Update Phase 10 documentation after the implementation path is chosen.
- Add smoke checks proving observability has no public Gateway/HTTPRoute in
  production.

## Success Criteria

- Public production TLS remains app-only.
- No production render output contains public Grafana, Kiali, or Jaeger routes.
- Observability UIs are reachable by port-forward for an operator.
- Observability UIs are not reachable from the public internet.
- Local Tilt can still provide the observability tools needed for debugging and
  architecture review.
