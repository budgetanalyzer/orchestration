# Observability Architecture

**Date:** 2026-04-10
**Status:** Active

## Overview

Budget Analyzer uses [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
(Prometheus Operator, Prometheus, Grafana, kube-state-metrics) for metrics
collection and visualization. The stack runs in a dedicated `monitoring`
namespace and is installed via Helm through the Tiltfile.

Infrastructure exporters (PostgreSQL, Redis, RabbitMQ) are not deployed.
Spring Boot, Istio, and kube-state-metrics cover the intended observability
story. The default kube-prometheus-stack API server, kubelet, CoreDNS, and
kube-proxy ServiceMonitors are disabled so the monitoring NetworkPolicy
baseline does not need broad kube-system or node egress.
The chart-level least-privilege baseline also constrains the Prometheus
Operator watch scope to the two namespaces that currently carry relevant
monitoring CRs: `monitoring` and `default`. Prometheus, Alertmanager instance,
Alertmanager config, and ThanosRuler instance discovery is pinned to
`monitoring`. A repo-owned Helm post-renderer then replaces the upstream broad
operator `ClusterRole`/`ClusterRoleBinding` pair with a narrower split:
- one cluster-scoped read-only binding for `namespaces`, `nodes`,
  `ingresses.networking.k8s.io`, and `storageclasses.storage.k8s.io`
- one `Role`/`RoleBinding` in `monitoring` for Prometheus-owned writes and
  namespaced config/Service reconciliation
- one read-only `Role`/`RoleBinding` in `default` for the monitoring CRs the
  operator consumes there, plus namespaced `events` writes for operator
  diagnostics
Jaeger and Kiali use the same internal-only contract: both run in
`monitoring`, both stay `ClusterIP` only, and operator access uses
loopback-bound `kubectl port-forward` instead of any public observability
hostname.

## Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| Prometheus | Metrics scraping and storage | `monitoring` |
| Prometheus Operator | CRD-based scrape target management | `monitoring` |
| Grafana | Dashboard visualization | `monitoring` |
| kube-state-metrics | Kubernetes resource metrics | `monitoring` |
| Jaeger | Distributed trace ingestion and query backend | `monitoring` |
| Kiali | Istio mesh graph and workload inspection | `monitoring` |

**Disabled components** (with rationale):
- **Alertmanager** - dashboards first; alerting deferred
- **node-exporter** - requires host namespaces and `hostPath` mounts that
  conflict with the repo's no-exceptions security stance
- **kubeEtcd, kubeControllerManager, kubeScheduler** - not accessible in Kind

## Scrape Topology

```
Prometheus (monitoring namespace, mesh-injected)
    │
    ├── ServiceMonitor: spring-boot-services
    │   ├── currency-service     /currency-service/actuator/prometheus
    │   ├── transaction-service  /transaction-service/actuator/prometheus
    │   ├── permission-service   /permission-service/actuator/prometheus
    │   └── session-gateway      /actuator/prometheus
    │
    ├── ServiceMonitor: istio-mesh
    │   └── istiod               :http-monitoring (istio-system)
    │
    ├── ServiceMonitor: chart-managed monitoring services
    │   ├── prometheus-stack-grafana             /metrics
    │   ├── prometheus-stack-kube-prom-operator  /metrics
    │   └── prometheus-stack-kube-state-metrics  /metrics
    │
    └── PodMonitor: envoy-stats
        └── All mesh-injected pods  :15090/stats/prometheus
```

For meshed Prometheus, the monitored `ServiceMonitor` jobs that stay on
cluster Services must scrape the stable Service DNS name and service port, not
the discovered endpoint pod IP. In this repo that contract applies to the four
Spring Boot services plus `istiod`, Grafana, Prometheus Operator, and
kube-state-metrics.

### Spring Boot Services

The four Spring Boot services in `default` carry the label
`app.kubernetes.io/framework: spring-boot`. A single `ServiceMonitor`
selects services matching that label and scrapes their Prometheus actuator
endpoints. Three services use servlet context paths, so the monitored paths
differ per service.

The `/actuator/prometheus` endpoint is exposed by service-common's
`PrometheusEndpointPostProcessor` — no per-service configuration needed.
New Spring Boot services require a new `endpoints` entry in
`kubernetes/monitoring/servicemonitor-spring-boot.yaml` with the correct
servlet context path and a `relabelings` keep-regex for the service name.

For Kiali, the repo's shared app workload convention is `app` plus
`version: v1` on Deployment metadata and pod-template labels. That same base
manifests path feeds both Tilt and the OCI production apps overlay, so Kiali
can group the deployed app workloads consistently without a second
production-only version-label scheme.

#### Dashboard Label Contract

The JVM (Micrometer) and Spring Boot 3.x dashboards select a workload via
the `application` template variable, populated from
`label_values(jvm_info, application)`. For a new endpoint to show up in
those dropdowns, its `relabelings` block must:

1. Rewrite `__address__` to the stable service DNS name so scrapes land on
   the sidecar-accepting Service VIP instead of a pod IP (required under
   STRICT mTLS).
2. Copy `__meta_kubernetes_service_name` to the `application` target label.

```yaml
relabelings:
  - sourceLabels: [__meta_kubernetes_service_name]
    action: keep
    regex: new-service
  - targetLabel: __address__
    replacement: new-service.default.svc.cluster.local:8080
  - sourceLabels: [__meta_kubernetes_service_name]
    targetLabel: application
```

The `namespace` target label comes for free from the Prometheus Operator
and is used by the Spring Boot 3.x dashboard's `Namespace` variable.

### Istio Metrics

- **istiod**: scraped via `ServiceMonitor` on the `http-monitoring` port in
  `istio-system`
- **Envoy sidecars**: scraped via `PodMonitor` on port `15090` for all pods
  with `security.istio.io/tlsMode` label (i.e., mesh-injected pods)

The Prometheus server pod is itself mesh-injected (`sidecar.istio.io/inject:
"true"`) so it can reach Envoy metrics ports under STRICT mTLS without
bypassing the repo's `AuthorizationPolicy` or `NetworkPolicy` posture.
That same mesh posture means the `istiod`, Grafana, Prometheus Operator, and
kube-state-metrics `ServiceMonitor` jobs are rewritten to their stable Service
DNS addresses instead of scraping endpoint pod IPs directly.

## Dashboards

Grafana ships with two pre-provisioned dashboards (no manual import):

| Dashboard | Source | UID | Use For |
|-----------|--------|-----|---------|
| JVM (Micrometer) | Grafana ID 4701, locally modernized | `jvm-micrometer` | Memory pools, GC pauses, threads, classloading |
| Spring Boot 3.x Statistics | Grafana ID 19004 | `spring-boot-3x` | HTTP request rates, latencies, error rates |

The provisioned ConfigMap,
`kubernetes/monitoring/grafana-dashboards-configmap.yaml`, is the canonical
deployment artifact. It embeds locally adapted dashboard JSON with import
metadata removed, the Prometheus datasource rewired to `uid: prometheus`, and
stable local dashboard UIDs assigned. The JVM dashboard entry is locally
modernized from Grafana 4701 rev10: it removes legacy top-level `rows`,
replaces the old Quick Facts `singlestat` panels with native `stat` panels,
and scopes the workload variables to `jvm_info`.

Reference dashboard exports live under
`kubernetes/monitoring/dashboards-src/` for provenance and comparison only.
Tilt does not consume those source files directly.

Dashboards are provisioned via the Grafana file provider: a ConfigMap
(`grafana-dashboards`) is mounted directly into the Grafana pod. Grafana
rescans the provider path on a polling interval (default 10s), and kubelet
propagates ConfigMap updates (~60s), so dashboard changes take effect
without a pod restart.

The sidecar-based dashboard discovery pattern was evaluated and rejected —
it would add a container and grant Grafana Kubernetes API access solely to
watch a single ConfigMap that is already mounted as a volume. See the
implementation notes in the [observability plan](../plans/observability-stack-prometheus-grafana-2026-04-10.md)
for the full evaluation.

### Common Debugging Scenarios

**Service not responding / high latency:**
1. Open the **Spring Boot 3.x Statistics** dashboard
2. Select the service in the `application` dropdown
3. Check HTTP request rate, error rate, and latency percentiles
4. Cross-reference with the **JVM (Micrometer)** dashboard for GC pressure
   or memory exhaustion

**JVM memory issues:**
1. Open the **JVM (Micrometer)** dashboard
2. Select the service in the `application` dropdown
3. Check heap vs. non-heap usage, GC pause duration and frequency
4. Look for steadily increasing heap usage (potential leak) or frequent
   long GC pauses

**Service target down in Prometheus:**
1. Open `http://localhost:9090/targets` (after port-forward)
2. Find the Spring Boot targets for `currency-service`, `transaction-service`,
   `permission-service`, and `session-gateway`. The `ServiceMonitor` is named
   `spring-boot-services`, but the Prometheus `job` label is the service name.
3. If a target shows `DOWN`, check:
   - Pod is running: `kubectl get pods -l app.kubernetes.io/framework=spring-boot`
   - Actuator endpoint responds (use the service's context path):
     - session-gateway: `kubectl exec <pod> -- curl -s localhost:8081/actuator/prometheus | head`
     - transaction-service: `kubectl exec <pod> -- curl -s localhost:8082/transaction-service/actuator/prometheus | head`
     - currency-service: `kubectl exec <pod> -- curl -s localhost:8084/currency-service/actuator/prometheus | head`
     - permission-service: `kubectl exec <pod> -- curl -s localhost:8086/permission-service/actuator/prometheus | head`
   - NetworkPolicy allows Prometheus access: `kubectl get networkpolicy -n default`

**Grafana, Prometheus Operator, kube-state-metrics, or istiod target down from meshed Prometheus:**
1. Open `http://localhost:9090/targets` and inspect the `scrapeUrl`.
2. The host should be the Service DNS name, not a pod IP:
   - `istiod.istio-system.svc.cluster.local:15014`
   - `prometheus-stack-grafana.monitoring.svc.cluster.local:80`
   - `prometheus-stack-kube-prom-operator.monitoring.svc.cluster.local:8080`
   - `prometheus-stack-kube-state-metrics.monitoring.svc.cluster.local:8080`
3. If one of those jobs resolves to a pod IP again, fix the checked-in
   `relabelings` in `kubernetes/monitoring/prometheus-stack-values.yaml`
   instead of treating pod-IP scrapes as acceptable.

**Envoy metrics missing:**
1. Check the `envoy-stats` PodMonitor targets in Prometheus
2. Verify the Prometheus pod has a sidecar: `kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.containers[*].name}'`
3. Verify AuthorizationPolicy allows Prometheus to reach `:15090`

**Kiali shows many warnings or errors and it is unclear what is real:**
1. Confirm the app stack is actually up: `kubectl get deploy -n default` and,
   after `tilt up`, `./scripts/smoketest/verify-clean-tilt-deployment-admission.sh`
2. Run `./scripts/ops/triage-kiali-findings.sh` locally, or
   `./scripts/ops/triage-kiali-findings.sh --runtime-shape production` on OCI
3. Treat `default` namespace findings as runtime-state findings first, not as
   Kiali bugs, if the namespace currently has no pods, no app services, or only
   the default service account
4. On OCI, remember that `nginx-gateway` serves the frontend bundle. A missing
   standalone `budget-analyzer-web` Deployment is normal there, while
   `AuthorizationPolicy/default/budget-analyzer-web-policy` is stale drift and
   should be removed from the production baseline.
5. Treat unhealthy external integrations from Kiali's `Istio Status` page,
   such as tracing `Unreachable`, as real dependency gaps until the backing
   service exists and is reachable
6. Treat only the documented expected-noise warnings as ignorable. See
   [Kiali Expected Warnings](../runbooks/kiali-expected-warnings.md) for the
   current allowlist and rationale.
7. Persist the raw JSON and log snapshot with
   `./scripts/ops/triage-kiali-findings.sh --output-dir tmp/kiali-triage`
   when you want to walk the findings one by one or compare before and after a
   cluster change

## Access

### Grafana

Local Tilt and production OCI/k3s use the same internal-only access contract
for Grafana. There is no supported observability hostname. Keep Grafana behind
Kubernetes and use a loopback-bound port-forward instead. `tilt up` installs
the observability workloads, but it does not own or keep localhost tunnels
open for Grafana, Prometheus, Jaeger, or Kiali:

```bash
kubectl port-forward --address 127.0.0.1 -n monitoring \
  svc/prometheus-stack-grafana 3300:80
```

Then open `http://localhost:3300`.

To prove the supported access path without leaving manual `kubectl port-forward`
processes behind, run:

```bash
./scripts/smoketest/verify-observability-port-forward-access.sh
```

The smoke script starts and cleans up any missing loopback-bound Grafana,
Prometheus, Jaeger, and Kiali port-forwards, waits for the expected local
health endpoints on the canonical `3300`, `9090`, `16686`, and `20001` ports
by default, and verifies that unauthenticated Grafana dashboard access and
unauthenticated Kiali API access are both rejected. If one of those loopback
ports is already occupied by the expected observability `kubectl port-forward`
listener, the verifier reuses it instead of failing. Use explicit port
overrides only when some other intentional listener owns one of the canonical
ports.

For persistent operator access to all four observability UIs, use the repo-
owned helper:

```bash
./scripts/ops/start-observability-port-forwards.sh
```

That helper keeps the canonical Grafana, Prometheus, Jaeger, and Kiali
forwards bound to `127.0.0.1` in one foreground process, prints the local
URLs plus the Grafana password and Kiali token commands, and tears down all
child forwards on `Ctrl+C`. Raw `kubectl port-forward --address 127.0.0.1 ...`
commands remain the underlying supported access model in both local Tilt and
production OCI/k3s.

For workstation access to production OCI/k3s, keep the Kubernetes
port-forwards running on the OCI host first, then open the matching
workstation-side SSH tunnels:

```bash
./scripts/ops/start-observability-ssh-tunnels.sh 152.70.145.68
```

The SSH helper assumes `ubuntu` and `~/.ssh/oci-budgetanalyzer`, binds only to
workstation loopback, and forwards the same canonical `3300`, `9090`, `16686`,
and `20001` ports to the OCI host's loopback listeners. Operators can also set
`OCI_INSTANCE_IP` in their shell profile and run the helper without an
argument.

`grafana.budgetanalyzer.localhost` is retired. Do not introduce
`grafana.budgetanalyzer.org`, `kiali.budgetanalyzer.org`, or
`jaeger.budgetanalyzer.org` as public observability entry points.

Grafana owns its own `/api/*` namespace and is **not** subject to Budget
Analyzer's ext_authz session enforcement because observability access does not
use the application ingress path. Grafana manages its own authentication
(admin user with Helm-generated password), and anonymous access stays disabled.

```bash
# Retrieve admin password
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
echo
```

Login with username `admin` and the retrieved password. The password is
generated by the Helm chart and stored in `Secret/prometheus-stack-grafana`.
It is not hardcoded in Git.

For browser-side dashboard debugging, run the isolated Playwright probe from
the orchestration repo:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh
```

The helper fetches the Grafana admin password from Kubernetes unless
`GRAFANA_ADMIN_PASSWORD` is already set, passes it to Playwright through the
environment only, and writes transient screenshots, API responses, console
errors, request failures, and panel-state summaries under
`tmp/grafana-ui-debug/`. It defaults `GRAFANA_URL` to
`http://127.0.0.1:3300`, so start the Grafana port-forward first, keep it bound
to `127.0.0.1`, and do not switch observability forwarding to `0.0.0.0`.

### Prometheus

Internal only — no ingress route. Use port-forward:

```bash
kubectl port-forward --address 127.0.0.1 -n monitoring \
  svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

Then open `http://localhost:9090`. Useful first queries:
- `up{namespace="default", application!=""}` — are all four Spring services being scraped?
- `jvm_memory_used_bytes` — JVM memory usage across services
- `jvm_gc_pause_seconds_count` — GC pause frequency

### Jaeger

Jaeger uses repo-managed v2 manifests, not the Helm chart. The locked backend
lives under `kubernetes/monitoring/jaeger/`. The runtime contract is:

- namespace: `monitoring`
- service exposure: `ClusterIP` only
- storage: single-node PVC-backed Badger
- image: Jaeger `2.17.0`, pinned by digest
- collector service: `jaeger-collector` on OTLP `4317` and `4318`, with
  Istio-classified Service port names `grpc-otlp` and `http-otlp`
- query service: `jaeger-query` on `16685` and `16686`
- operator access:

```bash
kubectl port-forward --address 127.0.0.1 -n monitoring \
  svc/jaeger-query 16686:16686
```

Then open `http://localhost:16686/jaeger`. Istio tracing is wired through the
repo-owned `jaeger` OpenTelemetry extension provider in
`kubernetes/istio/istiod-values.yaml` and the mesh-default
`kubernetes/istio/tracing-telemetry.yaml` resource. Sampling stays on Istio
defaults, so generate several requests through `https://app.budgetanalyzer.localhost`
before checking the Jaeger services and traces views.

Validate the tracing control-plane wiring with:

```bash
./scripts/smoketest/verify-istio-tracing-config.sh
```

### Kiali

Kiali uses the standalone `kiali-server` Helm chart, not the Kiali operator.
The locked runtime contract is:

- namespace: `monitoring`
- service exposure: `ClusterIP` only
- auth mode: `token`
- UI posture: `view_only_mode: true`
- RBAC posture: non-cluster-wide, limited to `default`, `monitoring`,
  `istio-system`, `istio-ingress`, and `istio-egress`
- image: Kiali `2.24.0`, pinned by digest
- integrations:
  internal Prometheus URL, Jaeger query gRPC URL on `16685`, and Jaeger HTTP
  health URL on `16686`
- Jaeger version probe: explicitly disabled because Kiali `2.24.0` falls back
  to `http://<host>/jaeger` on port `80` when `use_grpc: true`, which does not
  match this repo's Jaeger query service contract
- operator access:

```bash
kubectl port-forward --address 127.0.0.1 -n monitoring \
  svc/kiali 20001:20001
```

Then create a short-lived login token:

```bash
kubectl -n monitoring create token kiali
```

Open `http://localhost:20001/kiali` and paste the token.

The repo-owned Jaeger/Kiali wiring is intentionally split by protocol:

- `internal_url: http://jaeger-query.monitoring:16685/jaeger`
  keeps Kiali trace queries on Jaeger's gRPC API.
- `health_check_url: http://jaeger-query.monitoring:16686/jaeger`
  keeps the component-health probe on Jaeger's HTTP query/UI endpoint.
- `disable_version_check: true`
  suppresses Kiali's broken Jaeger version probe for this topology. Upstream
  Kiali `2.24.0` strips the gRPC port and retries the version fetch over plain
  HTTP on the default port, which would otherwise generate repeated timeout
  noise against `http://jaeger-query.monitoring/jaeger`.

## Security Compliance

The monitoring stack meets the same security requirements as all other
workloads in this repo.

`monitoring` is a first-class enforced namespace, not an implicit allow-all
side case. The repo-owned baseline is deny-by-default ingress and
egress plus explicit allowlists for:

- DNS from `monitoring`
- Grafana to Prometheus
- Prometheus service discovery and scrape traffic to Grafana,
  kube-state-metrics, the Prometheus Operator, Spring Boot services, Istio
  sidecars, and Istiod
- Kiali access to Prometheus, Jaeger query, the Kubernetes API, and Istiod's
  control-plane version endpoint on `15014`
- OTLP ingress to `jaeger-collector` only from approved mesh workloads

The Kubernetes API allowance includes the Kind/k3s service CIDRs on `443` and
private RFC1918 apiserver endpoints on `6443` because Calico evaluates the
connection after service DNAT in the local runtime.
Other monitoring flows stay destination-scoped through namespace/pod selector
allowlists. The verifier scripts exercise those paths through temporary
`ClusterIP` Services so the repo does not need destinationless egress rules for
Grafana, Prometheus, Kiali, Jaeger, or the Spring Boot metrics targets.
Prometheus also needs egress to injected workload pods on Istio's mTLS tunnel
port `15008` for service-based Spring Boot scrapes, plus `istiod` on `15012`
for xDS/CA traffic and `15014` for Istio control-plane metrics scraping.

The `monitoring` namespace manifest does not opt into Gateway route attachment,
so observability stays off the public ingress surface by default.

### Image Pinning

Every image is digest-pinned in the monitoring inputs. Prometheus/Grafana image
pins live in `kubernetes/monitoring/prometheus-stack-values.yaml`; Jaeger is
pinned in `kubernetes/monitoring/jaeger/deployment.yaml`; Kiali is pinned in
`kubernetes/monitoring/kiali-values.yaml` and normalized by the Helm
post-renderer before apply.

| Image | Tag | Digest |
|-------|-----|--------|
| `grafana/grafana` | 12.4.2 | pinned |
| `prometheus/prometheus` | v3.11.1 | pinned |
| `prometheus-operator/prometheus-operator` | v0.90.1 | pinned |
| `prometheus-operator/prometheus-config-reloader` | v0.90.1 | pinned |
| `kube-state-metrics/kube-state-metrics` | v2.18.0 | pinned |
| `quay.io/kiali/kiali` | v2.24.0 | pinned |

### Workload Hardening

All monitoring pods comply with the current security guardrail contract:
- `automountServiceAccountToken: false` on all pods
- `runAsNonRoot: true`, `allowPrivilegeEscalation: false`,
  `capabilities.drop: [ALL]` on all containers
- `seccompProfile.type: RuntimeDefault` where applicable

### Kubernetes API Access

Prometheus, Prometheus Operator, and kube-state-metrics need Kubernetes API
access for service discovery. Instead of relying on implicit token automount,
each uses an explicit projected service-account token volume mounted at the
standard in-cluster path:

```yaml
volumes:
  - name: k8s-api-access
    projected:
      sources:
        - serviceAccountToken:
            path: token
            expirationSeconds: 3600
        - configMap:
            name: kube-root-ca.crt
            items:
              - key: ca.crt
                path: ca.crt
        - downwardAPI:
            items:
              - path: namespace
                fieldRef:
                  fieldPath: metadata.namespace
```

Grafana does **not** need Kubernetes API access. Datasources are statically
provisioned and dashboards use the file provider, so no sidecar or API
watcher is needed.

### Admission Verification

```bash
# Re-render and verify the monitoring stack against current admission policies
./scripts/smoketest/verify-monitoring-rendered-manifests.sh
```

This script re-renders the pinned chart, verifies every image is
digest-pinned, checks that no host-level node-exporter shapes remain, asserts
the Prometheus Operator namespace watch flags stay narrowed to the documented
`monitoring` and `default` scope, asserts that the repo-owned reduced operator
RBAC is still what Helm renders, and runs `kubectl apply --dry-run=server`
against the current cluster.

## Helm Chart

- **Chart**: `prometheus-community/kube-prometheus-stack`
- **Version**: `83.4.0` (pinned)
- **Values**: `kubernetes/monitoring/prometheus-stack-values.yaml`
- **Post-renderer**: `scripts/ops/post-render-prometheus-stack.sh`

The chart version is pinned. Any upgrade requires re-rendering and
re-validating the hardening, operator RBAC reduction, and image inventory.

## Storage

Prometheus uses a 10Gi PersistentVolumeClaim for metrics retention.
Metrics survive pod restarts. Kind's default storage class provides
dynamic provisioning.

## Resource Footprint

| Component | Memory Request | Memory Limit |
|-----------|---------------|--------------|
| Prometheus | 512Mi | 1Gi |
| Prometheus Operator | 128Mi | 256Mi |
| Grafana | 128Mi | 256Mi |
| kube-state-metrics | 64Mi | 128Mi |
| **Total** | **832Mi** | **~1.6Gi** |

This fits comfortably in the 24GB OCI ARM instance alongside the
application stack.

## Discovery Commands

```bash
# List monitoring pods
kubectl get pods -n monitoring

# List monitoring services
kubectl get svc -n monitoring

# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus-stack-kube-prom-prometheus 9090:9090
# Then open http://localhost:9090/targets

# Check ServiceMonitor and PodMonitor CRDs
kubectl get servicemonitors -n monitoring
kubectl get servicemonitors -n default
kubectl get podmonitors -n monitoring

# Grafana admin password
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo

# Verify rendered manifests against admission policies
./scripts/smoketest/verify-monitoring-rendered-manifests.sh
```
