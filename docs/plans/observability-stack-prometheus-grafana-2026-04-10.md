# Observability Stack: Prometheus + Grafana Plan

Date: 2026-04-10

## Goal

Add production-grade observability to Budget Analyzer using kube-prometheus-stack,
enabling metrics collection from all Spring Boot services and visualization via
Grafana dashboards.

After this work:

1. Prometheus scrapes `/actuator/prometheus` from all Spring Boot services
2. Grafana provides pre-built dashboards for JVM metrics, Spring Boot, and
   custom application metrics
3. The same configuration works locally (Kind + Tilt) and ports to production
   (OCI ARM instance) with minimal changes
4. Infrastructure metrics (Redis, PostgreSQL, RabbitMQ) are collected via
   exporters or native metrics endpoints

## Non-Goals

- Do not build custom alerting rules yet. Dashboards first, alerts later.
- Do not add distributed tracing (Jaeger) in this plan. That's a separate effort.
- Do not add centralized logging (Loki) in this plan. `kubectl logs` suffices
  for a portfolio demo.
- Do not expose Grafana publicly. Local port-forward or internal Istio route only.
- Do not tune Prometheus retention policies or configure remote storage backends.
  Basic PVC persistence is acceptable for demo purposes.
- Do not add application-specific custom metrics. Focus on out-of-box Spring
  Boot and JVM metrics.

## Prerequisites

**service-common enhancement (complete):**
- `micrometer-registry-prometheus` dependency added to `service-core` (`build.gradle.kts`)
- `PrometheusEndpointPostProcessor` auto-adds `prometheus` to exposed actuator
  endpoints regardless of per-service configuration
- `/actuator/prometheus` endpoint verified via unit tests

No blocking prerequisites remain. All phases can proceed.

## Current State

- Spring Boot services include `spring-boot-starter-actuator` via service-common
- `PrometheusEndpointPostProcessor` in service-core already exposes `/actuator/prometheus`
- No Prometheus or Grafana exists in the cluster
- Istio is installed via Helm using `local_resource()` pattern in Tiltfile
- Infrastructure services (PostgreSQL, Redis, RabbitMQ) run in `infrastructure`
  namespace without metrics exporters
- OCI production target: VM.Standard.A1.Flex (ARM64), 4 OCPU, 24GB RAM

## Design Decisions

### Helm Chart Selection

Use `kube-prometheus-stack` (formerly prometheus-operator) rather than standalone
Prometheus + Grafana installations.

Rationale:
- Industry standard, recognized by interviewers
- Includes Prometheus Operator for declarative ServiceMonitor/PodMonitor CRDs
- Pre-configured Grafana with Prometheus datasource
- Batteries-included alerting infrastructure (even if we defer using it)
- Single Helm release manages the full stack

### Namespace Strategy

Create dedicated `monitoring` namespace, consistent with `infrastructure` pattern.

Rationale:
- Clear separation of concerns
- Allows namespace-scoped RBAC if needed later
- Matches production deployment patterns

### Scrape Configuration

Use ServiceMonitor CRDs rather than static scrape configs.

Rationale:
- Declarative, version-controlled
- Automatically discovers new services matching labels
- Standard Prometheus Operator pattern
- Each service owns its ServiceMonitor definition

### Resource Constraints

Configure explicit resource requests/limits for OCI deployment.

Estimated footprint (with Istio metrics and persistence):
| Component | Memory Request | Memory Limit | Storage |
|-----------|---------------|--------------|---------|
| Prometheus | 512Mi | 1Gi | 10Gi PVC |
| Prometheus Operator | 128Mi | 256Mi | - |
| Grafana | 128Mi | 256Mi | - |
| kube-state-metrics | 64Mi | 128Mi | - |
| node-exporter | 64Mi | 128Mi | - |
| **Total** | ~896Mi | ~1.75Gi | 10Gi |

This fits comfortably in the 24GB OCI instance alongside the application stack.
Istio/Envoy metrics add cardinality; Prometheus memory increased accordingly.

### ARM64 Compatibility

All kube-prometheus-stack images support `linux/arm64`. No special configuration
needed, but values file should not pin to amd64-only image variants.

## Work Plan

### Phase 1: Stack Installation

Install kube-prometheus-stack via Helm in Tilt, following the Istio pattern.

**Files to create:**
- `kubernetes/monitoring/namespace.yaml`
- `kubernetes/monitoring/prometheus-stack-values.yaml`

**Files to modify:**
- `setup.sh` - add prometheus-community Helm repo
- `Tiltfile` - add `local_resource()` for Helm installation

**Required outcomes:**
- `monitoring` namespace exists with appropriate labels
- Prometheus, Grafana, and supporting components deploy successfully
- Prometheus UI accessible via `kubectl port-forward svc/prometheus-stack-kube-prometheus-prometheus 9090:9090 -n monitoring`
- Istio metrics (istiod, envoy sidecars) appearing in Prometheus targets
- Stack appears in Tilt UI with proper resource dependencies
- PersistentVolumeClaim created and bound for Prometheus storage

### Phase 2: Spring Boot Labels and ServiceMonitors

Add common label to Spring Boot deployments and configure Prometheus scraping.

**Files to create:**
- `kubernetes/monitoring/servicemonitor-spring-boot.yaml`

**Files to modify (add `app.kubernetes.io/framework: spring-boot` label):**
- `kubernetes/services/currency-service/deployment.yaml` (deployment + pod template)
- `kubernetes/services/currency-service/service.yaml`
- `kubernetes/services/transaction-service/deployment.yaml`
- `kubernetes/services/transaction-service/service.yaml`
- `kubernetes/services/permission-service/deployment.yaml`
- `kubernetes/services/permission-service/service.yaml`
- `kubernetes/services/session-gateway/deployment.yaml`
- `kubernetes/services/session-gateway/service.yaml`

**Required outcomes:**
- All four Spring Boot deployments and services have label
  `app.kubernetes.io/framework: spring-boot`
- ServiceMonitor selects services matching that label
- Prometheus scrapes `/actuator/prometheus` on the service port
- All four Spring Boot services appear as targets in Prometheus UI
- JVM metrics (`jvm_memory_used_bytes`, `jvm_gc_*`, etc.) visible in Prometheus

**Note:** The `/actuator/prometheus` endpoint is already exposed by service-common's
`PrometheusEndpointPostProcessor`. No service-side changes needed.

### Phase 3: Grafana Dashboards

Import or configure useful dashboards for Spring Boot and JVM monitoring.

**Files to create:**
- `kubernetes/monitoring/grafana-dashboards-configmap.yaml` (optional, if
  embedding dashboards as code)

**Required outcomes:**
- JVM dashboard showing memory, GC, threads per service
- Spring Boot dashboard showing HTTP request rates, latencies, error rates
- Dashboard provisioning is declarative (survives pod restart)
- Dashboards work without manual import steps

**Dashboard sources:**
- JVM Micrometer: Grafana dashboard ID 4701
- Spring Boot 3.x Statistics: Grafana dashboard ID 19004 (use 19004 over 12464,
  which targets older Spring Boot versions and may not work with Micrometer 2.x)

### Phase 4: Grafana Ingress Route

Expose Grafana via Istio ingress at `grafana.budgetanalyzer.localhost`.

**Files to create:**
- `kubernetes/monitoring/grafana-httproute.yaml`

**Files to modify:**
- `kubernetes/istio/istio-gateway.yaml` - change `allowedRoutes` from
  `matchLabels: kubernetes.io/metadata.name: default` to a label-based selector:
  `matchLabels: budgetanalyzer.io/ingress-routes: "true"`. This allows any
  namespace with that label to attach routes, without editing the Gateway each time.
- `kubernetes/monitoring/namespace.yaml` - add `budgetanalyzer.io/ingress-routes: "true"` label
- DNS/hosts configuration for local development

**Existing namespace update:**
The `default` namespace must also be labeled `budgetanalyzer.io/ingress-routes: "true"`
to preserve existing HTTPRoute attachment. Add a `kubectl label` step to the Tiltfile
or to `kubernetes/monitoring/namespace.yaml` setup sequence.

**Required outcomes:**
- Grafana accessible at `https://grafana.budgetanalyzer.localhost`
- TLS termination at Istio ingress (reuse existing wildcard cert -- Gateway already
  listens on `*.budgetanalyzer.localhost`)
- No authentication required for local dev (Grafana has its own login)
- Route does NOT go through ext-authz (monitoring is independent of app auth)
- HTTPRoute in `monitoring` namespace is accepted by the Gateway via label selector

**Security note:**
For OCI production, consider whether Grafana should be publicly accessible or
restricted to VPN/bastion access. Local dev exposes it freely.

### Phase 5: Infrastructure Exporters (Optional)

Add metrics collection for PostgreSQL, Redis, and RabbitMQ.

**Files to create:**
- `kubernetes/infrastructure/postgresql/exporter.yaml` (sidecar or standalone)
- `kubernetes/infrastructure/redis/exporter.yaml`
- `kubernetes/monitoring/servicemonitor-infrastructure.yaml`

**Required outcomes:**
- PostgreSQL metrics visible (connections, query stats, replication lag)
- Redis metrics visible (memory, keys, commands/sec)
- RabbitMQ metrics visible (queue depth, message rates) - note: RabbitMQ 3.8+
  has built-in Prometheus endpoint at `:15692/metrics`

**Complexity note:**
This phase adds operational complexity. Defer if time-constrained. Spring Boot
metrics alone demonstrate observability competence for portfolio purposes.

### Phase 6: Documentation

Update documentation to reflect the observability stack.

**Files to modify:**
- `AGENTS.md` - add monitoring namespace to service architecture, discovery commands
- `docs/development/local-environment.md` - add Grafana/Prometheus access instructions
- `docs/architecture/` - consider adding `observability.md` if architecture
  documentation warrants it

**Required outcomes:**
- Discovery commands for monitoring resources documented
- Grafana access URL (`https://grafana.budgetanalyzer.localhost`) documented
- Prometheus port-forward command documented (internal access only)
- Dashboard navigation guidance for common debugging scenarios
- Default Grafana credentials documented

## Execution Order

Implement in phases that allow incremental verification:

1. **Phase 1** - Stack installation and Gateway `allowedRoutes` update. Can
   proceed immediately. Includes Istio metrics scraping configuration and the
   label-based `allowedRoutes` selector change on the Gateway (required for Phase 4).
2. **Phase 2** - Labels and ServiceMonitors. No external blockers (service-common
   already exposes `/actuator/prometheus`). Add `app.kubernetes.io/framework:
   spring-boot` labels to deployment and service manifests, then verify scraping.
3. **Phase 3** - Dashboards. Depends on Phase 2 producing metrics.
4. **Phase 4** - Grafana ingress route. Can proceed after Phase 1 (needs the
   `allowedRoutes` update), independent of Phase 2/3. Exposes Grafana at
   `grafana.budgetanalyzer.localhost`.
5. **Phase 5** - Infrastructure exporters. Optional, defer if time-constrained.
6. **Phase 6** - Documentation. Update incrementally as each phase completes.

**Parallelization opportunity:** Phases 2-3 (Spring Boot metrics path) and
Phase 4 (Grafana ingress) can proceed in parallel after Phase 1 completes.

## Tiltfile Integration Pattern

Following the established Istio pattern:

```python
# Monitoring namespace
k8s_yaml('kubernetes/monitoring/namespace.yaml')

# kube-prometheus-stack
local_resource(
    'prometheus-stack',
    cmd='''
        helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --values kubernetes/monitoring/prometheus-stack-values.yaml \
            --wait
    ''',
    deps=['kubernetes/monitoring/prometheus-stack-values.yaml'],
    resource_deps=['monitoring-namespace'],
    labels=['monitoring'],
)

# ServiceMonitors (after stack is ready)
k8s_yaml('kubernetes/monitoring/servicemonitor-spring-boot.yaml')
k8s_resource(
    objects=['spring-boot-services:servicemonitor'],
    new_name='servicemonitor-spring-boot',
    resource_deps=['prometheus-stack'],
    labels=['monitoring'],
)
```

## Values File Considerations

Key configurations for `prometheus-stack-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    # Scrape all ServiceMonitors regardless of namespace
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    # Persistent storage for metrics retention
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    # Resource limits for OCI
    resources:
      requests:
        memory: 512Mi
      limits:
        memory: 1Gi
  # Istio/Envoy metrics scraping (merged under same prometheus: key)
  additionalServiceMonitors:
    - name: istio-mesh
      selector:
        matchLabels:
          app: istiod
      namespaceSelector:
        matchNames:
          - istio-system
      endpoints:
        - port: http-monitoring
          interval: 15s
    - name: envoy-stats
      selector:
        matchExpressions:
          - key: security.istio.io/tlsMode
            operator: Exists
      namespaceSelector:
        any: true
      endpoints:
        - path: /stats/prometheus
          targetPort: 15090  # Istio sidecar metrics port
          interval: 15s

grafana:
  # Disable default password prompt, set admin password
  adminPassword: admin  # Change for production
  resources:
    requests:
      memory: 128Mi
    limits:
      memory: 256Mi
  # Service type for Istio ingress integration
  service:
    type: ClusterIP

# Disable components not needed for portfolio demo
alertmanager:
  enabled: false  # Re-enable when adding alerting

kubeEtcd:
  enabled: false  # Not accessible in Kind

kubeControllerManager:
  enabled: false  # Not accessible in Kind

kubeScheduler:
  enabled: false  # Not accessible in Kind
```

**Note on Istio metrics**: The Envoy sidecar metrics significantly increase
cardinality. If Prometheus memory usage becomes a concern, reduce scrape interval
or add metric relabeling to drop high-cardinality labels.

**Note on Envoy port**: The envoy-stats ServiceMonitor uses `targetPort: 15090`
(Istio's standard sidecar metrics port) rather than a named port. Verify this
against Istio 1.29.1's actual sidecar configuration and `meshConfig.enablePrometheusMerge`
setting, as port conventions can vary between Istio versions.

## Decisions

1. **Istio integration**: YES - Include Istio/Envoy sidecar metrics. Adds
   request-level visibility (latency, error rates, traffic volume per service
   pair). Higher cardinality but valuable for understanding service mesh behavior.

2. **Grafana ingress**: YES - Expose via Istio ingress route at
   `grafana.budgetanalyzer.localhost`. Industry standard for production setups.
   Will require HTTPRoute configuration similar to existing app routes.

3. **Persistence**: YES - Use PersistentVolumeClaim for Prometheus. Metrics
   survive pod restarts, important for OCI deployment where we want historical
   data. Local Kind cluster supports dynamic provisioning via standard storage class.

4. **ServiceMonitor label strategy**: Add `app.kubernetes.io/framework: spring-boot`
   label to all Spring Boot deployments and services. This is semantic (describes
   what the service is) and follows Kubernetes labeling conventions. New services
   automatically discovered when they include this label.

## References

- [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Spring Boot Actuator Prometheus endpoint](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html#actuator.metrics.export.prometheus)
- [Micrometer Prometheus registry](https://micrometer.io/docs/registry/prometheus)
- [Grafana JVM dashboard 4701](https://grafana.com/grafana/dashboards/4701)
- [Grafana Spring Boot 3.x dashboard 19004](https://grafana.com/grafana/dashboards/19004)
- AGENTS.md Production Deployment Target section (OCI instance specs)
