# Observability Architecture

**Date:** 2026-04-10
**Status:** Active

## Overview

Budget Analyzer uses [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
(Prometheus Operator, Prometheus, Grafana, kube-state-metrics) for metrics
collection and visualization. The stack runs in a dedicated `monitoring`
namespace and is installed via Helm through the Tiltfile.

Infrastructure exporters (PostgreSQL, Redis, RabbitMQ) are not deployed.
Spring Boot and Istio metrics alone cover the intended observability story.

## Components

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| Prometheus | Metrics scraping and storage | `monitoring` |
| Prometheus Operator | CRD-based scrape target management | `monitoring` |
| Grafana | Dashboard visualization | `monitoring` |
| kube-state-metrics | Kubernetes resource metrics | `monitoring` |

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
    └── PodMonitor: envoy-stats
        └── All mesh-injected pods  :15090/stats/prometheus
```

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

## Dashboards

Grafana ships with two pre-provisioned dashboards (no manual import):

| Dashboard | Source | UID | Use For |
|-----------|--------|-----|---------|
| JVM (Micrometer) | Grafana ID 4701 | `jvm-micrometer` | Memory pools, GC pauses, threads, classloading |
| Spring Boot 3.x Statistics | Grafana ID 19004 | `spring-boot-3x` | HTTP request rates, latencies, error rates |

Dashboards are provisioned via the Grafana file provider: a ConfigMap
(`grafana-dashboards`) is mounted directly into the Grafana pod. Grafana
rescans the provider path on a polling interval (default 10s), and kubelet
propagates ConfigMap updates (~60s), so dashboard changes take effect
without a pod restart.

The sidecar-based dashboard discovery pattern was evaluated and rejected —
it would add a container and grant Grafana Kubernetes API access solely to
watch a single ConfigMap that is already mounted as a volume. See the
Phase 3 notes in the [observability plan](../plans/observability-stack-prometheus-grafana-2026-04-10.md)
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
2. Find the `spring-boot-services` job
3. If a target shows `DOWN`, check:
   - Pod is running: `kubectl get pods -l app.kubernetes.io/framework=spring-boot`
   - Actuator endpoint responds (use the service's context path):
     - session-gateway: `kubectl exec <pod> -- curl -s localhost:8080/actuator/prometheus | head`
     - transaction-service: `kubectl exec <pod> -- curl -s localhost:8080/transaction-service/actuator/prometheus | head`
     - currency-service: `kubectl exec <pod> -- curl -s localhost:8080/currency-service/actuator/prometheus | head`
     - permission-service: `kubectl exec <pod> -- curl -s localhost:8080/permission-service/actuator/prometheus | head`
   - NetworkPolicy allows Prometheus access: `kubectl get networkpolicy -n default`

**Envoy metrics missing:**
1. Check the `envoy-stats` PodMonitor targets in Prometheus
2. Verify the Prometheus pod has a sidecar: `kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].spec.containers[*].name}'`
3. Verify AuthorizationPolicy allows Prometheus to reach `:15090`

## Access

### Grafana

Exposed via Istio ingress at `https://grafana.budgetanalyzer.localhost`.
No port-forward needed for local development.

Grafana owns its own `/api/*` namespace and is **not** subject to Budget
Analyzer's ext_authz session enforcement. The `ext-authz-at-ingress`
AuthorizationPolicy is scoped to `app.budgetanalyzer.localhost` so it does
not intercept requests to the Grafana host. Grafana manages its own
authentication (admin user with Helm-generated password).

```bash
# Retrieve admin password
kubectl get secret -n monitoring prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
echo
```

Login with username `admin` and the retrieved password. The password is
generated by the Helm chart and stored in `Secret/prometheus-stack-grafana`.
It is not hardcoded in Git.

### Prometheus

Internal only — no ingress route. Use port-forward:

```bash
kubectl port-forward -n monitoring \
  svc/prometheus-stack-kube-prom-prometheus 9090:9090
```

Then open `http://localhost:9090`. Useful first queries:
- `up{job="spring-boot-services"}` — are all four services being scraped?
- `jvm_memory_used_bytes` — JVM memory usage across services
- `jvm_gc_pause_seconds_count` — GC pause frequency

## Security Compliance

The monitoring stack meets the same security requirements as all other
workloads in this repo — no namespace exceptions.

### Image Pinning

Every image is digest-pinned in `kubernetes/monitoring/prometheus-stack-values.yaml`:

| Image | Tag | Digest |
|-------|-----|--------|
| `grafana/grafana` | 12.4.2 | pinned |
| `prometheus/prometheus` | v3.11.1 | pinned |
| `prometheus-operator/prometheus-operator` | v0.90.1 | pinned |
| `prometheus-operator/prometheus-config-reloader` | v0.90.1 | pinned |
| `kube-state-metrics/kube-state-metrics` | v2.18.0 | pinned |

### Workload Hardening

All monitoring pods comply with the Phase 7 contract:
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
digest-pinned, checks that no host-level node-exporter shapes remain, and
runs `kubectl apply --dry-run=server` against the current cluster.

## Helm Chart

- **Chart**: `prometheus-community/kube-prometheus-stack`
- **Version**: `83.4.0` (pinned)
- **Values**: `kubernetes/monitoring/prometheus-stack-values.yaml`

The chart version is pinned. Any upgrade requires re-rendering and
re-validating the hardening and image inventory.

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
