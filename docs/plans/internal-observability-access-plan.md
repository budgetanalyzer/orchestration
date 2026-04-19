# Plan: Internal-Only Observability Access

**Status:** In progress (`Phases 0-1` complete; `Phase 2` repo changes landed)
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

## Phased Implementation: Identical Local And Production Access

The target model is the same in both supported runtime paths:

- Observability UIs are `ClusterIP` services only.
- Operators use loopback-bound `kubectl port-forward`.
- Production operators reach the OCI host first, then use the same
  loopback-bound Kubernetes port-forward.
- No observability service has a DNS record, Gateway listener, `HTTPRoute`,
  public certificate, demo landing-page link, or anonymous public UI.

Use the same workstation-facing ports everywhere:

| Tool | Namespace | Service | Operator URL | Port-forward |
|------|-----------|---------|--------------|--------------|
| Grafana | `monitoring` | `prometheus-stack-grafana` | `http://localhost:3300` | `3300:80` |
| Prometheus | `monitoring` | `prometheus-stack-kube-prom-prometheus` | `http://localhost:9090` | `9090:9090` |
| Jaeger, if added later | TBD | TBD | `http://localhost:16686` | `16686:<service-port>` |
| Kiali, if added later | TBD | TBD | `http://localhost:20001` | `20001:<service-port>` |

Grafana intentionally uses local port `3300`, not `3000`, because local Tilt
already reserves `localhost:3000` for the frontend Vite dev-server
port-forward. Production could use `3000`, but using a different command in
production would undercut the identical-access goal.

### Phase 0 - Prove The Current Cleanup And Port-Forward Baseline

**Goal:** Confirm the immediate cleanup did not remove observability itself and
prove the current port-forward path before deleting the local ingress
convenience.

**Status, 2026-04-19:** Complete. Repo-owned checks and local `kind-kind`
verification passed. This workspace did not have production kube context or
OCI host access, so the documented OCI-host runtime commands remain
operator-run verification steps when reconciling production.

**Repo checks:**

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
./scripts/smoketest/verify-monitoring-rendered-manifests.sh
```

Confirm the production render still has no public observability route:

```bash
rg -n 'grafana\.budgetanalyzer\.org|kiali\.budgetanalyzer\.org|jaeger\.budgetanalyzer\.org|name: grafana-route' \
  tmp/phase-6 || true
```

Expected result: no matches.

**Local runtime checks after `tilt up`:**

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring prometheus-stack-grafana \
  prometheus-stack-kube-prom-prometheus

# Terminal 1; keep this running while checking Grafana from another shell.
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3300:80 \
  --address 127.0.0.1

# Terminal 2.
curl -fsS http://127.0.0.1:3300/api/health

# Stop the Grafana port-forward, then start Prometheus from Terminal 1.
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 \
  --address 127.0.0.1

# Terminal 2.
curl -fsS http://127.0.0.1:9090/-/ready
```

This phase proves port-forward reachability. If the current Grafana Helm values
still point at the old ingress URL or at `http://localhost:3000`, browser login
through `http://127.0.0.1:3300` may redirect incorrectly. Treat that as input
to Phase 2, not as a reason to keep the ingress route.

If the current values already point at `http://localhost:3300`, run the
browser-side Grafana diagnostic against the port-forwarded URL:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh --url http://127.0.0.1:3300
```

**Production runtime checks on the OCI host (`ubuntu@152.70.145.68`):**

Start by opening an SSH session to the OCI host:

```bash
ssh -i ~/.ssh/oci-budgetanalyzer ubuntu@152.70.145.68
```

```bash
kubectl get httproute -A
kubectl get gateway -n istio-ingress istio-ingress-gateway -o yaml | \
  grep -E 'grafana|kiali|jaeger' || true
kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.spec.type}{"\n"}'

# Keep this running while checking Grafana from another shell.
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3300:80 \
  --address 127.0.0.1

# Separate shell on the OCI host.
curl -fsS http://127.0.0.1:3300/api/health

# Stop the Grafana port-forward, then check Prometheus.
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 \
  --address 127.0.0.1

# Separate shell on the OCI host.
curl -fsS http://127.0.0.1:9090/-/ready
```

If testing from a workstation browser, keep both hops loopback-bound:

```bash
# Terminal 1 on the OCI host.
kubectl port-forward -n monitoring svc/prometheus-stack-grafana 3300:80 \
  --address 127.0.0.1

# Terminal 2 on your workstation.
ssh -i ~/.ssh/oci-budgetanalyzer -N \
  -L 3300:127.0.0.1:3300 \
  ubuntu@152.70.145.68
```

Then open `http://127.0.0.1:3300` on your workstation.

Prometheus uses the same pattern:

```bash
# Terminal 1 on the OCI host.
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090 \
  --address 127.0.0.1

# Terminal 2 on your workstation.
ssh -i ~/.ssh/oci-budgetanalyzer -N \
  -L 9090:127.0.0.1:9090 \
  ubuntu@152.70.145.68
```

Then open `http://127.0.0.1:9090` on your workstation.

**Completion criteria:**

- Production has no live Grafana, Kiali, or Jaeger `HTTPRoute`.
- Grafana health is reachable through `127.0.0.1:3300`.
- Prometheus remains reachable through `127.0.0.1:9090`.
- Any port-forward failure is fixed before Phase 1 starts.

**2026-04-19 verification notes:**

- `./scripts/guardrails/verify-production-image-overlay.sh` passed.
- `./scripts/smoketest/verify-monitoring-rendered-manifests.sh` passed.
- `./deploy/scripts/13-render-phase-6-production-manifests.sh` rendered cleanly
  with a temporary `INSTANCE_ENV_FILE` that supplied the locked non-secret
  `DEMO_DOMAIN` and `AUTH0_ISSUER_URI` values expected by the renderer.
- `rg -n 'grafana\.budgetanalyzer\.org|kiali\.budgetanalyzer\.org|jaeger\.budgetanalyzer\.org|name: grafana-route' tmp/phase-6`
  returned no matches after the render.
- Added
  `./scripts/smoketest/verify-observability-port-forward-access.sh` as a
  repeatable local Phase 0 proof for loopback-only Grafana and Prometheus
  health checks.
- The new verifier failed fast on the canonical local ports in this AI
  devcontainer because non-repo loopback listeners already occupied
  `127.0.0.1:3300` and `127.0.0.1:9090`, then passed with
  `./scripts/smoketest/verify-observability-port-forward-access.sh --grafana-port 13300 --prometheus-port 19090`.
  The canonical operator contract remains `3300` for Grafana and `9090` for
  Prometheus; the flag overrides exist only to keep the baseline verifiable in
  environments where those loopback ports are already taken.

### Phase 1 - Lock The Shared Operator Access Contract

**Goal:** Make the contract explicit before changing local routing.

**Status, 2026-04-19:** Complete. The active local setup, architecture, deploy,
and operator docs now describe the same loopback-only Grafana and Prometheus
access contract, retire `grafana.budgetanalyzer.localhost` from active setup
guidance, and warn operators not to use `--address 0.0.0.0` for observability
port-forwards.

Document the shared contract in:

- `docs/architecture/observability.md`
- `docs/development/local-environment.md`
- `docs/development/getting-started.md`
- `docs/architecture/port-reference.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/security-architecture.md`
- `README.md`
- `AGENTS.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`

The contract text should say:

- Local and production use port-forward-only observability access.
- Grafana is `http://localhost:3300` through
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80`.
- Prometheus is `http://localhost:9090` through
  `kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090`.
- `grafana.budgetanalyzer.localhost` is retired.
- `grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, and
  `jaeger.budgetanalyzer.org` must not be introduced.
- Grafana authentication stays enabled; anonymous access stays disabled.
- Operators must not use `--address 0.0.0.0` for observability
  port-forwards.

**Completion criteria:**

- No active setup or quick-start doc tells a developer to open
  `https://grafana.budgetanalyzer.localhost`.
- Production docs and local docs show the same port-forward commands.
- Active setup and architecture docs no longer reference the retired hostnames
  except as historical cleanup context.

### Phase 2 - Align Grafana Helm Values To Loopback Access

**Goal:** Make Grafana generate URLs and cookies for the same loopback URL in
local Tilt and production.

**Status, 2026-04-19:** Repo-owned config and guardrail updates are complete.
The shared Helm values now point Grafana at `http://localhost:3300` with
`domain: localhost` and `cookie_secure: false` in both local and production
render paths, and the production overlay verifier now fails if that
loopback-only contract drifts or if anonymous access appears. Live Grafana
login verification through a local port-forward still requires a reachable
cluster runtime.

Update `kubernetes/monitoring/prometheus-stack-values.yaml`:

```yaml
grafana:
  grafana.ini:
    server:
      domain: localhost
      root_url: http://localhost:3300
    security:
      cookie_secure: false
```

Keep the existing datasource, dashboard provisioning, authentication, and
`ClusterIP` service behavior unchanged. Do not enable anonymous access.

Update `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
to the same loopback URL. Keep the production override unless the production
renderer, production verifier, and production README are changed in the same
work; the override is still useful as a render-time assertion that production
does not inherit a public Grafana hostname.

Update `scripts/guardrails/verify-production-image-overlay.sh` so it expects:

- `domain: localhost`
- `root_url: http://localhost:3300`
- `cookie_secure: false`
- no public Grafana hostname
- no anonymous Grafana access

**Validation:**

```bash
bash -n scripts/guardrails/verify-production-image-overlay.sh
shellcheck scripts/guardrails/verify-production-image-overlay.sh
./scripts/smoketest/verify-monitoring-rendered-manifests.sh
./deploy/scripts/13-render-phase-6-production-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Completion criteria:**

- Local and production Helm values agree on `http://localhost:3300`.
- Grafana login works through the local port-forward.
- No rendered production output contains a public observability hostname.

### Phase 3 - Remove The Local Grafana Ingress Path

**Goal:** Stop applying any local Gateway route to Grafana so local development
matches production.

Edit local runtime inputs:

- Remove the `grafana-ingress-route` `local_resource` from `Tiltfile`.
- Delete `kubernetes/monitoring/grafana-httproute.yaml`, or leave only a
  clearly non-applied historical note in this plan. Prefer deletion to avoid a
  dormant route being reapplied later.
- Remove `grafana.budgetanalyzer.localhost` from local setup guidance, hosts
  examples, and troubleshooting docs.

Edit network policy inputs:

- Remove `allow-istio-ingress-egress-to-grafana` from
  `kubernetes/network-policies/istio-ingress-allow.yaml`.
- Update `deploy/scripts/08-verify-network-policy-enforcement.sh` so the
  Istio ingress gateway no longer has a positive egress expectation to
  Grafana. If the script keeps a temporary Grafana listener pod, use it for a
  negative assertion instead.
- Re-check any phase-3 or phase-5 smoke scripts that mention Grafana ingress;
  keep internal Grafana health checks only if they do not imply ingress access.

**Validation:**

```bash
bash -n deploy/scripts/08-verify-network-policy-enforcement.sh
shellcheck deploy/scripts/08-verify-network-policy-enforcement.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh
```

After `tilt up`:

```bash
kubectl get httproute -A | grep -Ei 'grafana|kiali|jaeger' || true
kubectl get networkpolicy -n istio-ingress
./scripts/smoketest/verify-phase-3-istio-ingress.sh
./scripts/smoketest/verify-phase-5-runtime-hardening.sh
```

Expected result: no observability `HTTPRoute` exists in local or production.

**Completion criteria:**

- Local Tilt no longer creates or updates a Grafana `HTTPRoute`.
- Istio ingress gateway no longer needs egress to Grafana.
- The app ingress path still works.
- Grafana and Prometheus still work through loopback port-forward.

### Phase 4 - Add A Repeatable Port-Forward Smoke Check

**Goal:** Make the access model testable without relying on a manual browser
check as the only proof.

**Status, 2026-04-19:** The base smoke script landed during Phase 0 to capture
the current cleanup baseline. Remaining Phase 4 work is wiring it into the
aggregate smoke pass, adding the anonymous-access assertion, and aligning the
Playwright helper with the same URL contract.

Extend `scripts/smoketest/verify-observability-port-forward-access.sh` so that
it:

- starts loopback-bound `kubectl port-forward` processes for Grafana and
  Prometheus on the canonical ports
- waits until `http://127.0.0.1:3300/api/health` returns success
- waits until `http://127.0.0.1:9090/-/ready` returns success
- confirms Grafana anonymous access is not enabled, either by checking Helm
  values or by verifying unauthenticated dashboard access is rejected
- cleans up child port-forward processes on exit
- fails if the local port is already occupied, with a message that names the
  expected process owner

Wire it into `scripts/smoketest/smoketest.sh` after the monitoring runtime
check. Keep it usable against whichever Kubernetes context the operator has
selected; do not hardcode `/workspace` or a cluster name.

Update `scripts/ops/grafana-ui-playwright-debug.sh`:

- default `GRAFANA_URL` to `http://127.0.0.1:3300`
- keep `--url` override support
- update help text and docs to say a Grafana port-forward must already be
  running, unless the script is explicitly enhanced to manage one

**Validation:**

```bash
bash -n scripts/smoketest/verify-observability-port-forward-access.sh
shellcheck scripts/smoketest/verify-observability-port-forward-access.sh
bash -n scripts/ops/grafana-ui-playwright-debug.sh
shellcheck scripts/ops/grafana-ui-playwright-debug.sh
./scripts/smoketest/verify-observability-port-forward-access.sh
./scripts/ops/grafana-ui-playwright-debug.sh
./scripts/smoketest/smoketest.sh
```

**Completion criteria:**

- A local operator can prove Grafana and Prometheus port-forward access with
  one smoke script.
- The aggregate smoke pass covers the access model.
- The browser diagnostic uses the same URL contract.

### Phase 5 - Add Static Guardrails Against Observability Ingress Drift

**Goal:** Prevent future work from accidentally republishing observability.

Extend the static guardrail suite so it fails on:

- `HTTPRoute` manifests for Grafana, Prometheus, Kiali, or Jaeger
- Gateway hostnames matching `grafana.*`, `prometheus.*`, `kiali.*`, or
  `jaeger.*`
- `GRAFANA_DOMAIN`, `KIALI_DOMAIN`, or `JAEGER_DOMAIN` production inputs
- Grafana Helm values containing `grafana.budgetanalyzer.localhost` or
  `grafana.budgetanalyzer.org`
- Grafana anonymous access being enabled
- Istio ingress network policy allowances to observability services unless a
  future plan explicitly reintroduces an internal-only gateway

The implementation can live in `scripts/guardrails/verify-phase-7-static-manifests.sh`
or in a smaller helper sourced by it. Keep production-specific assertions in
`scripts/guardrails/verify-production-image-overlay.sh` as well.

**Validation:**

```bash
bash -n scripts/guardrails/verify-phase-7-static-manifests.sh
bash -n scripts/guardrails/verify-production-image-overlay.sh
shellcheck scripts/guardrails/verify-phase-7-static-manifests.sh
shellcheck scripts/guardrails/verify-production-image-overlay.sh
./scripts/guardrails/verify-phase-7-static-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
```

**Completion criteria:**

- CI/static local checks reject a new observability ingress route.
- The production renderer still proves app-only public routing.
- Exceptions, if any, are explicit and documented in this plan.

### Phase 6 - Validate Local/Production Parity End To End

**Goal:** Prove the two runtime paths now use the same operator model.

**Local parity checklist:**

```bash
tilt up
kubectl get httproute -A | grep -Ei 'grafana|prometheus|kiali|jaeger' || true
./scripts/smoketest/verify-monitoring-runtime.sh
./scripts/smoketest/verify-observability-port-forward-access.sh
./scripts/ops/grafana-ui-playwright-debug.sh
```

**Production parity checklist on the OCI host:**

```bash
./deploy/scripts/13-render-phase-6-production-manifests.sh
./scripts/guardrails/verify-production-image-overlay.sh
kubectl get httproute -A | grep -Ei 'grafana|prometheus|kiali|jaeger' || true
kubectl get svc -n monitoring prometheus-stack-grafana \
  -o jsonpath='{.spec.type}{"\n"}'
kubectl get svc -n monitoring prometheus-stack-kube-prom-prometheus \
  -o jsonpath='{.spec.type}{"\n"}'
./scripts/smoketest/verify-observability-port-forward-access.sh
```

**Public negative checks from outside OCI:**

```bash
curl -I http://demo.budgetanalyzer.org
curl -I http://grafana.budgetanalyzer.org || true
curl -k -I https://grafana.budgetanalyzer.org || true
curl -I http://kiali.budgetanalyzer.org || true
curl -I http://jaeger.budgetanalyzer.org || true
```

Expected result: the app host still works, and observability hostnames fail DNS,
fail connection, fail TLS, or return no matching route. They must not return a
Grafana, Kiali, Jaeger, or Prometheus UI response.

**Completion criteria:**

- The same documented port-forward commands work in local and production.
- The same smoke script works against local and production kube contexts.
- The public internet cannot reach observability UIs.

### Phase 7 - Add Jaeger And Kiali Only After Access Parity Is Stable

**Goal:** Avoid mixing tool rollout with access-model cleanup.

Do not add Jaeger or Kiali until Phases 0 through 6 are complete.

When adding either tool:

- Add the service as `ClusterIP`.
- Do not add Gateway, `HTTPRoute`, public DNS, public TLS, or demo-page links.
- Add a canonical port-forward command to this plan and to
  `docs/architecture/observability.md`.
- Add the tool to `scripts/smoketest/verify-observability-port-forward-access.sh`
  only after its release name, namespace, service, and health endpoint are
  stable.
- Add static guardrail coverage before merging the tool rollout.

**Completion criteria:**

- Jaeger/Kiali, if present, follow the same internal-only operator access
  contract as Grafana and Prometheus.
- No observability tool gets a one-off public exception.

## Final Success Criteria

- Public production TLS remains app-only.
- Local Tilt and production OCI/k3s expose observability UIs only through
  loopback-bound port-forwards.
- No local or production render output contains public Grafana, Prometheus,
  Kiali, or Jaeger routes.
- Grafana, Prometheus, and any later Jaeger/Kiali services remain `ClusterIP`.
- Grafana authentication remains enabled, and anonymous access remains disabled.
- A repeatable smoke check proves Grafana and Prometheus port-forward access.
- Local Tilt still provides the observability tools needed for debugging and
  architecture review.
