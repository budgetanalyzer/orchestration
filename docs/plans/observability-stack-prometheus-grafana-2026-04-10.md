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
- Do not expose Grafana publicly on OCI in this plan. Local development may use
  port-forward or a local-only Istio route, but production needs private access
  or additional auth in a follow-up.
- Do not tune Prometheus retention policies or configure remote storage backends.
  Basic PVC persistence is acceptable for demo purposes.
- Do not add application-specific custom metrics. Focus on out-of-box Spring
  Boot and JVM metrics.
- Do not create Kyverno or Pod Security Admission exceptions for the `monitoring`
  namespace. The stack must comply with existing guardrails.

## Prerequisites

**service-common enhancement (complete):**
- `micrometer-registry-prometheus` dependency added to `service-core` (`build.gradle.kts`)
- `PrometheusEndpointPostProcessor` auto-adds `prometheus` to exposed actuator
  endpoints regardless of per-service configuration
- `/actuator/prometheus` endpoint verified via unit tests

**Repository guardrails (already enforced):**
- Existing Phase 7 Kyverno policies and namespace Pod Security Admission labels
  remain authoritative
- Monitoring workloads must satisfy digest pinning, `automountServiceAccountToken: false`,
  and explicit pod/container hardening with no namespace carve-outs

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

### Chart Version Pinning

Pin the Helm chart to an explicit version in Tilt.

Rationale:
- This repo already pins infrastructure chart versions elsewhere
- The chart changes generated object names and defaults over time
- Hardening and digest pinning must be reviewed against a fixed render

As of **April 10, 2026**, pin `prometheus-community/kube-prometheus-stack`
to **`83.4.0`**. Any future upgrade requires re-rendering the chart and
re-validating the hardening and image inventory.

### Namespace Strategy

Create dedicated `monitoring` namespace, consistent with `infrastructure` pattern.

Rationale:
- Clear separation of concerns
- Allows namespace-scoped RBAC if needed later
- Matches production deployment patterns

### Security Compliance

Do not exempt `monitoring` from existing repository guardrails.

Rationale:
- This repo explicitly freezes third-party image pinning and workload hardening
- Adding exceptions for a third-party chart would undermine the Phase 7 contract
- A compliant rendered manifest is a better long-term baseline than chart-specific carve-outs

Implementation consequence:
- Every steady-state and hook workload rendered by the chart must use digest-pinned
  images
- Every pod must set `automountServiceAccountToken: false`
- Every container and init container must explicitly set `runAsNonRoot: true`,
  `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, and
  `seccompProfile.type: RuntimeDefault`

### Kubernetes API Access Under Phase 7

Some monitoring components legitimately need Kubernetes API access:
- Prometheus for ServiceMonitor/PodMonitor discovery
- Prometheus Operator for CRD reconciliation
- kube-state-metrics for resource listing
- Grafana sidecars if they watch ConfigMaps/Secrets dynamically

Rationale:
- `automountServiceAccountToken: false` alone is not sufficient for these workloads
- The compliant pattern is an explicit projected service-account token volume at
  the standard in-cluster path, or disabling the API-watching subfeature

Implementation consequence:
- If a workload needs Kubernetes API access, mount a projected token volume
  intentionally rather than relying on implicit automount
- If a subfeature cannot be made compliant cleanly, disable that subfeature
  rather than adding a namespace exception
- Phase 1 should use static Grafana datasource provisioning and keep Grafana's
  API-watching sidecars disabled until Phase 3 dashboards need them (Phase 3
  evaluated this and chose the file provider instead — see Phase 3 notes)
- Phase 1 should also disable Prometheus Operator admission-webhook jobs rather
  than carrying extra hook-time token plumbing just to validate rule objects

### Minimal Monitoring Footprint

Disable `nodeExporter`.

Rationale:
- The chart's node-exporter DaemonSet uses host namespaces and `hostPath` mounts
- That pattern conflicts with the repo's no-exceptions stance and does not
  materially improve the portfolio-demo observability story
- Spring Boot, Istio, Prometheus, Grafana, and optional infrastructure exporters
  already cover the intended learning goals

### Scrape Configuration

Use ServiceMonitor CRDs for service-backed targets and PodMonitor CRDs for pod-only
targets such as Envoy sidecars.

Rationale:
- Declarative, version-controlled
- Automatically discovers new services matching labels
- Standard Prometheus Operator pattern
- Each service owns its ServiceMonitor definition
- Envoy sidecar metrics are exposed from pods, not Services, so they require a PodMonitor
- The Prometheus server must be mesh-participating and explicitly allowed to
  reach `:15090`, otherwise STRICT mTLS plus the repo's `AuthorizationPolicy`
  and `NetworkPolicy` posture will leave the Envoy PodMonitor down

### Resource Constraints

Configure explicit resource requests/limits for OCI deployment.

Estimated steady-state footprint (with Istio metrics and persistence):
| Component | Memory Request | Memory Limit | Storage |
|-----------|---------------|--------------|---------|
| Prometheus | 512Mi | 1Gi | 10Gi PVC |
| Prometheus Operator | 128Mi | 256Mi | - |
| Grafana | 128Mi | 256Mi | - |
| kube-state-metrics | 64Mi | 128Mi | - |
| **Total (steady-state)** | ~832Mi | ~1.625Gi | 10Gi |

This fits comfortably in the 24GB OCI instance alongside the application stack.
Istio/Envoy metrics add cardinality; Prometheus memory increased accordingly.
Phase 1 disables Prometheus Operator admission-webhook jobs, so they do not
contribute to the steady-state total.

### ARM64 Compatibility

All kube-prometheus-stack images support `linux/arm64`. No special configuration
needed, but values file should not pin to amd64-only image variants.

## Work Plan

### Phase 1: Security-Compliant Stack Installation

Install kube-prometheus-stack via Helm in Tilt, following the Istio pattern and
meeting the repo's current admission requirements.

**Files to create:**
- `kubernetes/monitoring/namespace.yaml`
- `kubernetes/monitoring/prometheus-stack-values.yaml`
- `scripts/dev/verify-monitoring-rendered-manifests.sh`

**Files to modify:**
- `setup.sh` - add prometheus-community Helm repo
- `Tiltfile` - add `local_resource()` for Helm installation, pin chart version,
  and make the monitoring install depend on `kyverno-policies`

**Required outcomes:**
- `monitoring` namespace exists with baseline Pod Security labels
- Helm installs `prometheus-community/kube-prometheus-stack` at pinned version
  `83.4.0`
- Every rendered third-party image is digest-pinned
- Rendered Deployments, StatefulSets, DaemonSets, and Jobs pass
  `kubectl apply --dry-run=server` against the current cluster with no namespace
  exceptions
- Every rendered pod sets `automountServiceAccountToken: false`
- Any workload that still needs Kubernetes API access uses an explicit projected
  service-account token volume or disables the API-watching subfeature
- `nodeExporter.enabled: false`; no host-namespace or `hostPath` monitoring
  workload remains in the final chart render
- The Prometheus server pod joins the mesh and default-namespace workloads
  explicitly allow Prometheus scrapes to `:15090`
- Prometheus, Grafana, Prometheus Operator, and kube-state-metrics deploy successfully
- Prometheus UI accessible via `kubectl port-forward svc/prometheus-stack-kube-prom-prometheus 9090:9090 -n monitoring`
- Istio metrics wiring is present: `istiod` via ServiceMonitor and Envoy via PodMonitor
- Stack appears in Tilt UI with proper resource dependencies
- PersistentVolumeClaim created and bound for Prometheus storage

**Scope note:**
Phase 1 does **not** change the Istio Gateway `allowedRoutes` selector. That is
Phase 4 work because it changes ingress attachment policy rather than monitoring
installation.

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

### Phase 3: Grafana Dashboards (complete)

Import or configure useful dashboards for Spring Boot and JVM monitoring.

**Files created:**
- `kubernetes/monitoring/grafana-dashboards-configmap.yaml`

**Files modified:**
- `kubernetes/monitoring/prometheus-stack-values.yaml` - added `dashboardProviders`
  and `extraConfigmapMounts`
- `Tiltfile` - apply ConfigMap before Helm install, added as dependency
- `docs/development/local-environment.md` - documented pre-provisioned dashboards

**Required outcomes:**
- JVM dashboard showing memory, GC, threads per service
- Spring Boot dashboard showing HTTP request rates, latencies, error rates
- Dashboard provisioning is declarative (survives pod restart)
- Dashboards work without manual import steps
- Grafana admin credentials come from a Helm-generated Secret or an
  `existingSecret`; do not hardcode `adminPassword: admin` in Git

**Dashboard sources:**
- JVM Micrometer: Grafana dashboard ID 4701 (uid: `jvm-micrometer`)
- Spring Boot 3.x Statistics: Grafana dashboard ID 19004 (uid: `spring-boot-3x`);
  use 19004 over 12464, which targets older Spring Boot versions and may not work
  with Micrometer 2.x

**Provisioning approach — file provider, not sidecar:**

Phase 1 deferred the sidecar decision: "keep Grafana's API-watching sidecars
disabled until Phase 3 dashboards need them." Phase 3 evaluated and chose the
Grafana file provider (`dashboardProviders` + `extraConfigmapMounts`) over the
sidecar (`sidecar.dashboards.enabled: true`).

The sidecar watches the Kubernetes API for labeled ConfigMaps and auto-discovers
dashboards from any namespace. That solves a coordination problem —
decentralized dashboard ownership across teams — that this repo does not have.
Enabling it would add a container and grant Grafana k8s API access (projected
token volume) solely to watch a single ConfigMap that is already mounted as a
volume. That conflicts with the Phase 7 stance of not granting API access
unless a workload genuinely needs it.

The file provider mounts the ConfigMap directly. Grafana rescans the provider
path on a polling interval (default 10s), and kubelet propagates ConfigMap
updates to mounted volumes (~60s), so dashboard changes take effect without a
pod restart. No k8s API access, no extra container, no security exception.

If this repo later moves to multi-team dashboard ownership, re-evaluate in
favor of the sidecar at that point.

### Phase 4: Grafana Ingress Route

Expose Grafana via Istio ingress at `grafana.budgetanalyzer.localhost` for local
development only.

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

Update documentation continuously as each phase lands, then do a final sweep.

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
- Grafana credential retrieval or `existingSecret` workflow documented

## Execution Order

Implement in phases that allow incremental verification:

1. **Phase 1** - Stack installation. Can proceed immediately. Pin the chart
   version, harden the rendered workloads, pin all third-party images by digest,
   and verify the rendered manifests against current admission policies.
   Includes Istio metrics scraping configuration, but **not** the Gateway
   `allowedRoutes` change.
2. **Phase 2** - Labels and ServiceMonitors. No external blockers (service-common
   already exposes `/actuator/prometheus`). Add `app.kubernetes.io/framework:
   spring-boot` labels to deployment and service manifests, then verify scraping.
3. **Phase 3** - Dashboards. Depends on Phase 2 producing metrics.
4. **Phase 4** - Grafana ingress route. Can proceed after Phase 1,
   independent of Phase 2/3. Applies the Gateway `allowedRoutes` update and
   exposes Grafana at `grafana.budgetanalyzer.localhost` for local development.
5. **Phase 5** - Infrastructure exporters. Optional, defer if time-constrained.
6. **Phase 6** - Documentation final sweep. Documentation still updates incrementally
   in each earlier phase to satisfy repo workflow.

**Parallelization opportunity:** Phases 2-3 (Spring Boot metrics path) and
Phase 4 (Grafana ingress) can proceed in parallel after Phase 1 completes.

## Tiltfile Integration Pattern

Following the established Istio pattern:

```python
# Monitoring namespace
local_resource(
    'monitoring-namespace',
    cmd='kubectl apply -f kubernetes/monitoring/namespace.yaml',
    deps=['kubernetes/monitoring/namespace.yaml'],
    labels=['monitoring'],
)

# kube-prometheus-stack
local_resource(
    'prometheus-stack',
    cmd='''
        ./scripts/dev/verify-monitoring-rendered-manifests.sh
        helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --version 83.4.0 \
            --values kubernetes/monitoring/prometheus-stack-values.yaml \
            --wait
    ''',
    deps=[
        'kubernetes/monitoring/prometheus-stack-values.yaml',
        'scripts/dev/verify-monitoring-rendered-manifests.sh',
    ],
    resource_deps=['monitoring-namespace', 'istiod', 'kyverno-policies'],
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
nodeExporter:
  enabled: false

prometheus:
  prometheusSpec:
    # Scrape all ServiceMonitors regardless of namespace
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    # Phase 7 requires explicit API-access intent; do not rely on implicit token mounts
    automountServiceAccountToken: false
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
    # If Prometheus still needs Kubernetes API discovery, mount an explicit
    # projected service-account token bundle at the standard path
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
    volumeMounts:
      - name: k8s-api-access
        mountPath: /var/run/secrets/kubernetes.io/serviceaccount
        readOnly: true
    image:
      registry: quay.io
      repository: prometheus/prometheus
      tag: v3.11.1
      sha: <resolved-prometheus-digest>

  serviceAccount:
    automountServiceAccountToken: false

  # Istio service-backed metrics scraping
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

  # Istio sidecar metrics scraping
  additionalPodMonitors:
    - name: envoy-stats
      selector:
        matchExpressions:
          - key: security.istio.io/tlsMode
            operator: Exists
      namespaceSelector:
        any: true
      podMetricsEndpoints:
        - path: /stats/prometheus
          targetPort: 15090  # Istio sidecar metrics port
          interval: 15s

grafana:
  # Do not hardcode adminPassword in Git. Use an existing Secret or the
  # Helm-generated Secret and document how to retrieve it.
  automountServiceAccountToken: false
  defaultDashboardsEnabled: false
  serviceAccount:
    autoMount: false
    automountServiceAccountToken: false
  containerSecurityContext:
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    privileged: false
    capabilities:
      drop: [ALL]
    seccompProfile:
      type: RuntimeDefault
  image:
    repository: grafana/grafana
    sha: <resolved-grafana-digest>
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Prometheus
          uid: prometheus
          type: prometheus
          access: proxy
          url: http://prometheus-stack-kube-prom-prometheus.monitoring.svc:9090
          isDefault: true
          editable: false
  sidecar:
    dashboards:
      enabled: false
    datasources:
      enabled: false
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

prometheusOperator:
  automountServiceAccountToken: false
  tls:
    enabled: false
  image:
    repository: prometheus-operator/prometheus-operator
    sha: <resolved-prometheus-operator-digest>
  containerSecurityContext:
    runAsNonRoot: true
  resources:
    requests:
      memory: 128Mi
    limits:
      memory: 256Mi
  prometheusConfigReloader:
    image:
      repository: prometheus-operator/prometheus-config-reloader
      sha: <resolved-config-reloader-digest>
  admissionWebhooks:
    enabled: false

kube-state-metrics:
  automountServiceAccountToken: false
  serviceAccount:
    automountServiceAccountToken: false
  image:
    repository: kube-state-metrics/kube-state-metrics
    sha: <resolved-kube-state-metrics-digest>
  containerSecurityContext:
    runAsNonRoot: true
  resources:
    requests:
      memory: 64Mi
    limits:
      memory: 128Mi
```

**Note on Istio metrics**: The Envoy sidecar metrics significantly increase
cardinality. If Prometheus memory usage becomes a concern, reduce scrape interval
or add metric relabeling to drop high-cardinality labels.

**Note on API access**: Prometheus, Prometheus Operator, and kube-state-metrics
need Kubernetes API access. Grafana does not — Phase 1 used static datasource
provisioning with sidecars disabled, and Phase 3 chose the file provider for
dashboards (see Phase 3 notes), so Grafana never needs k8s API access. Under
the repo's current policies, the acceptable patterns are:
- explicit projected service-account token volumes with pod automount disabled
- disabling the API-watching subfeature if it is not required

**Note on Envoy port**: The envoy-stats PodMonitor uses `targetPort: 15090`
(Istio's standard sidecar metrics port). In this repo that path only works if
Prometheus is injected into the mesh and default-namespace workloads explicitly
allow the Prometheus service account to reach `:15090`. Verify the port itself
against Istio 1.29.1's actual sidecar configuration and
`meshConfig.enablePrometheusMerge` setting, as port conventions can vary between
Istio versions.

## Decisions

1. **Istio integration**: YES - Include Istio/Envoy sidecar metrics. Adds
   request-level visibility (latency, error rates, traffic volume per service
   pair). Higher cardinality but valuable for understanding service mesh behavior.
   Use ServiceMonitor for `istiod` and PodMonitor for Envoy sidecars.

2. **Chart pinning**: YES - Pin `kube-prometheus-stack` to `83.4.0` as of
   April 10, 2026. Do not install an unversioned chart in Tilt.

3. **Security compliance**: YES - No `monitoring` namespace exceptions. Meet the
   current Kyverno and PSA requirements through values-file hardening and digest pinning.

4. **Persistence**: YES - Use PersistentVolumeClaim for Prometheus. Metrics
   survive pod restarts, important for OCI deployment where we want historical
   data. Local Kind cluster supports dynamic provisioning via standard storage class.

5. **node-exporter**: NO - Disable it in this repo. Its host-level DaemonSet
   shape is not worth the exception pressure for this demo environment.

6. **Grafana ingress**: YES - Expose via Istio ingress route at
   `grafana.budgetanalyzer.localhost` for local development only. Do not treat
   that as approval for public OCI exposure.

7. **ServiceMonitor label strategy**: Add `app.kubernetes.io/framework: spring-boot`
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
