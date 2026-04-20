# Plan: Phase 7 Jaeger And Kiali Rollout

**Status:** Proposed
**Date:** 2026-04-19
**Supersedes:** the placeholder `Phase 7` section in
`docs/plans/internal-observability-access-plan.md`

## Goal

Add Jaeger and Kiali to the existing internal-only observability stack without
reopening any public observability path and without weakening the current
security baseline.

This plan assumes the Phase 0-6 access-parity work from
`docs/plans/internal-observability-access-plan.md` stays intact:

- observability remains internal-only
- operator access remains loopback-bound `kubectl port-forward`
- no Gateway listeners, `HTTPRoute`s, public DNS, or public TLS for
  observability

## Current Handoff State, 2026-04-20

Phase 7.1 and Phase 7.2 are implemented in the working tree. The current work
has not been committed.

Important implementation reasoning captured during runtime validation:

- Jaeger NetworkPolicies now target the shared Jaeger pod label
  `app.kubernetes.io/name: jaeger`; `jaeger-query` and `jaeger-collector` are
  Services over the same single-binary Jaeger pod, and NetworkPolicy selects
  pods, not Services. Query and collector access are separated by ports.
- The monitoring Helm values now disable the default kube-prometheus-stack API
  server, kubelet, CoreDNS, and kube-proxy ServiceMonitors. This keeps the
  observed surface aligned with the documented Budget Analyzer story: Spring
  Boot metrics, Istio metrics, Grafana, Prometheus, Prometheus Operator, and
  kube-state-metrics.
- The `monitoring` namespace deny-all needed more than podSelector egress:
  - Kubernetes API calls need the Kind/k3s service CIDRs on `443` plus RFC1918
    apiserver endpoints on `6443`, because Calico evaluates the path after
    service DNAT in the local runtime.
  - Prometheus Spring Boot scrapes also need egress to injected workloads on
    Istio mTLS tunnel port `15008`; without it, `/actuator/prometheus` targets
    time out even when app ports are allowed.
- The local and deploy NetworkPolicy verifiers now hit temporary `ClusterIP`
  Services for the monitoring flows and Spring Boot metrics flows, so the
  checked-in policies stay destination-scoped instead of relying on
  destinationless port-only egress.
- `scripts/smoketest/verify-monitoring-runtime.sh` now warms the same
  `/actuator/prometheus` paths used by the ServiceMonitor instead of unrelated
  health paths. Warmup failures are advisory; the script fails on Prometheus
  target, metric, and dashboard-label evidence.
- `scripts/guardrails/verify-phase-7-static-manifests.sh` now keeps rejecting
  observability ingress allowances except for the single reviewed
  `istio-ingress -> Jaeger OTLP` policy shape.

Validation already completed in this session:

- `bash -n` and `shellcheck` passed for the modified shell scripts after the
  final script edits.
- `kubectl apply --dry-run=server -f kubernetes/network-policies` passed after
  the final NetworkPolicy shape.
- `./scripts/smoketest/verify-monitoring-rendered-manifests.sh` passed after
  the monitoring Helm value changes.
- `./scripts/guardrails/verify-phase-7-static-manifests.sh` passed after the
  final guardrail and policy changes.
- `./scripts/smoketest/verify-monitoring-runtime.sh` passed after the final
  monitoring NetworkPolicy changes: `13 passed, 0 failed`.
- `./scripts/smoketest/verify-phase-2-network-policies.sh` passed once at
  `61 passed (out of 61)` before the final verifier service-path tightening and
  `15008` additions.
- `./deploy/scripts/08-verify-network-policy-enforcement.sh` passed once at
  `65 passed (out of 65)` before the final verifier service-path tightening and
  `15008` additions.

Current blocker discovered after a fresh `tilt down` / `tilt up` on
2026-04-20:

- `infrastructure/rabbitmq-0` is in `CrashLoopBackOff` because the broker needs
  about `193s` to complete startup, while the current exec probes in
  `kubernetes/infrastructure/rabbitmq/statefulset.yaml` only give it about
  `120s` of liveness budget after the initial delay.
- The broker does eventually reach `Server startup complete`, but kubelet sends
  `SIGTERM` shortly afterward because repeated `rabbitmq-diagnostics -q ping`
  probe attempts time out during the long management-plugin startup window.
- The most suspicious startup drag is the management deprecation path in
  `kubernetes/infrastructure/rabbitmq/configmap.yaml`:
  `deprecated_features.permit.management_metrics_collection = false`. RabbitMQ
  3.13.7 logs that the deprecated feature is not permitted, then takes roughly
  another two minutes before the management and Prometheus listeners come up.
- That config line predates Phase 7 work, so the likely regression is an
  existing RabbitMQ startup/probe fragility now exposed by current runtime
  conditions, not a brand-new Jaeger/Kiali-specific RabbitMQ manifest change.

Planned follow-up before Phase 7.3 proceeds:

- confirm the minimum safe RabbitMQ startup strategy in-repo by testing the
  least-invasive fix first: introduce a `startupProbe` or otherwise extend the
  startup budget so kubelet stops killing a broker that eventually becomes
  healthy
- if startup remains unreasonably slow after probe-budget correction, test
  whether the deprecated management metrics setting should be revised or removed
  for RabbitMQ `3.13.x`
- rerun the affected local validation after the fix: RabbitMQ pod stability,
  `tilt up` health, and the relevant smoke/guardrail checks before resuming
  Jaeger/Kiali rollout work

2026-04-20 implementation update:

- Added a minimal probe-budget fix in
  `kubernetes/infrastructure/rabbitmq/statefulset.yaml`: a `startupProbe`
  using `rabbitmq-diagnostics -q ping` with a `20s` initial delay and a
  `240s` total failure window (`periodSeconds: 10`, `failureThreshold: 24`).
  This keeps liveness disabled until the broker proves it can answer the same
  health command used by the existing readiness and liveness probes.
- Follow-up measurement on the live pod showed the same probe command succeeds
  but is slow even after startup: inside the container,
  `rabbitmq-diagnostics -q ping` returned in roughly `24s` to `37s`, while
  `kubectl exec` runs took about `57s`. The RabbitMQ probes therefore also need
  a larger `timeoutSeconds` budget on this local path; the manifest now uses
  `timeoutSeconds: 45` for startup, readiness, and liveness while keeping the
  existing command and cadence.
- Live-cluster evidence from `kubectl logs -n infrastructure rabbitmq-0` still
  shows RabbitMQ `3.13.7` spending most of its cold-start time in the
  management-plugin path after the deprecated-feature warning. In the observed
  run, the broker logged the deprecated
  `management_metrics_collection` warning at `2026-04-20 11:44:42Z`, the
  management HTTP listener came up at `11:45:50Z`, and `Server startup
  complete` arrived at `11:45:56Z`.
- Investigation result: the deprecated setting in
  `kubernetes/infrastructure/rabbitmq/configmap.yaml`,
  `deprecated_features.permit.management_metrics_collection = false`, is still
  a plausible contributor to slow startup, but it is a separate behavior change
  from the minimal probe fix. Official RabbitMQ documentation points to the
  supported `management_agent.disable_metrics_collector = true` setting when
  Prometheus is the intended metrics source, so that config should be evaluated
  in a follow-up measurement after the probe-budget correction is proven stable.
- Follow-up implementation on `2026-04-20`: the deprecated setting was replaced
  with the supported `management_agent.disable_metrics_collector = true`
  configuration in `kubernetes/infrastructure/rabbitmq/configmap.yaml` so the
  broker no longer goes through the deprecated-feature path at startup.
- Measurement after the config change showed a material improvement on the live
  pod:
  - the deprecated `management_metrics_collection` warning disappeared
  - the management-agent log now reports only `Metrics collection disabled in
    management agent, management only interface started`
  - in the observed restart at `2026-04-20 12:20:43Z`, the management HTTP
    listener came up at `12:20:46Z`, `Server startup complete` arrived at
    `12:20:47Z`, and RabbitMQ reported `Time to start RabbitMQ: 9704 ms`
  - the pod reached `1/1 Running` with `restartCount=0`, and a steady-state
    `rabbitmq-diagnostics -q ping` sample returned in about `2s`
- Validation after the probe changes:
  - `kubectl apply --dry-run=server -f kubernetes/infrastructure/rabbitmq`
    passed.
  - A live StatefulSet rollout on `2026-04-20` reached `rabbitmq-0`
    `1/1 Running` with `restartCount=0` on revision `rabbitmq-bb9d959d8`.
  - `kubectl exec -n infrastructure rabbitmq-0 -- sh -lc 'date +%s;
    rabbitmq-diagnostics -q ping; date +%s'` returned successfully once the pod
    was Ready (observed `8s` in the final steady-state sample).
  - `./scripts/guardrails/verify-phase-7-static-manifests.sh` passed.
  - `./scripts/smoketest/verify-phase-5-runtime-hardening.sh` did not complete
    cleanly because unrelated application pods in `default` were already not
    Ready (`currency-service`, `permission-service`, and missing
    `session-gateway`), so it was not a clean RabbitMQ-only gate for this work.

Interrupted state:

- A final rerun of `./scripts/smoketest/verify-phase-2-network-policies.sh` was
  started after the final policy additions, then interrupted by the user during
  context handoff. The running verifier process was killed, and its `np2-*`
  disposable pods were deleted.
- The next session should rerun these final-state checks:
  - `./scripts/smoketest/verify-phase-2-network-policies.sh`
  - `./deploy/scripts/08-verify-network-policy-enforcement.sh`
  - optionally `./scripts/smoketest/smoketest.sh` if a full aggregate local
    pass is desired.

## Version Decisions

### Selected Versions

- **Jaeger:** `2.17.0`
  - Pin the multi-arch image index digest:
    `cr.jaegertracing.io/jaegertracing/jaeger:2.17.0@sha256:6266573208d665ce5c17483bce0a75d0806480d92c84766d288d0aee885ce708`
- **Kiali:** `2.24.0`
  - Pin the `kiali/kiali-server` Helm chart to `2.24.0`
  - Pin the multi-arch image index digest through Helm values:
    `quay.io/kiali/kiali:v2.24.0@sha256:744439cbdbbc23c7a5d70544911abf8fe0b32c88c082e9a41ae6b50748bf736e`

### Why These Versions

- Jaeger `2.17.0` is the current stable v2 release. Jaeger v1 component images
  are deprecated and only published up to `1.76`, so starting a new rollout on
  v1 would knowingly adopt the archived line.
- Kiali `2.24.0` is the current stable Kiali release.
- Kiali documents that, starting with `v2.4`, each Kiali release is tested
  against the currently supported Istio releases. Istio `1.29` is currently
  supported, so Kiali `2.24.0` is the correct current target for this repo's
  `Istio 1.29.1` baseline. This is an inference from the upstream compatibility
  policy plus Istio's current support table.
- Both selected images publish `linux/amd64` and `linux/arm64` manifests, so
  they fit the repo's local x86/amd64 path and OCI Free Tier `linux/arm64`
  target.

## Deployment Decisions

### Jaeger

Use **repo-managed Kubernetes manifests** for Jaeger v2, not the Helm chart, in
the first implementation pass.

Reason:

- the official Jaeger Helm charts are still marked beta
- the chart defaults to Elasticsearch-oriented storage, which would introduce a
  new backend dependency that this repo does not currently run
- the repo only needs a single-node, pinned, internal-only Jaeger deployment
  with explicit ports and explicit security settings

Target shape:

- namespace: `monitoring`
- one Jaeger v2 Deployment, `replicas: 1`
- two Services pointing at the same pod:
  - `jaeger-collector` for OTLP ingress (`4317`, optionally `4318`)
  - `jaeger-query` for UI + query APIs (`16686`, `16685`)
- explicit config file mounted from ConfigMap
- `base_path: /jaeger` on the query extension so Kiali can use the expected
  `/jaeger` path
- PVC-backed Badger storage for both local and OCI parity

### Kiali

Use the **standalone `kiali-server` Helm chart** instead of the Kiali operator.

Reason:

- the operator is Kiali's general recommendation, but this repo does not need a
  second controller/CRD management surface for a single Kiali instance
- the standalone server chart is maintained, versioned in lockstep with Kiali,
  and fits the repo's existing "pin third-party runtime inputs in-repo" pattern
- avoiding the operator reduces controller sprawl and lowers the blast radius
  of the rollout

Target shape:

- namespace: `monitoring`
- Helm release name: `kiali`
- chart: `kiali/kiali-server` `2.24.0`
- auth strategy: `token` (the Kubernetes default, explicitly set for clarity)
- `view_only_mode: true`
- `deployment.cluster_wide_access: false`
- explicit discovery selectors / namespace access limited to the namespaces this
  repo actually uses
- no Kiali ingress, no Kiali LoadBalancer, no public route

## Hard Constraints

- Do not add `grafana.*`, `prometheus.*`, `kiali.*`, or `jaeger.*` public
  hostnames.
- Do not add ingress/Gateway/`HTTPRoute` resources for Jaeger or Kiali.
- Do not add a new storage backend such as Elasticsearch/OpenSearch just to get
  Jaeger working.
- Do not reuse the application session model or Session Gateway for Kiali auth.
- Do not hide Jaeger/Kiali integration problems with orchestration-only
  workarounds if the root cause belongs in Istio or another owning repo.

## Implementation Phases

### Phase 7.1 - Lock The Runtime Contract

**Goal:** Make the repo-owned decisions explicit before adding manifests.

**Status, 2026-04-19:** Complete. The docs now encode one install strategy per
tool, the shared `monitoring` namespace, and the loopback-only operator
port-forward contract for local Tilt and OCI/k3s.

**Decisions to encode:**

- Jaeger lives in `monitoring`.
- Kiali lives in `monitoring`.
- Both remain `ClusterIP` only.
- Jaeger uses single-node PVC-backed Badger storage.
- Kiali uses `token` auth, `view_only_mode: true`, and non-cluster-wide RBAC.
- Access contract:
  - Jaeger UI: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/jaeger-query 16686:16686`
  - Kiali UI: `kubectl port-forward --address 127.0.0.1 -n monitoring svc/kiali 20001:20001`

**Repo touchpoints:**

- `docs/plans/internal-observability-access-plan.md`
- `docs/architecture/observability.md`
- `README.md`
- `AGENTS.md`
- `deploy/README.md`
- `kubernetes/production/README.md`

**Exit criteria:**

- one documented install strategy per tool
- one documented namespace per tool
- one documented local/prod port-forward contract per tool

### Phase 7.2 - Establish A Monitoring Namespace Security Baseline

**Goal:** Add Jaeger and Kiali behind explicit namespace-local controls instead
of relying on today's mostly Prometheus-specific posture.

**Status, 2026-04-19:** Complete. `monitoring` now has repo-owned deny/allow
NetworkPolicies, Tilt applies them with the core policy set, and the local plus
deployment network-policy verifiers exercise the monitoring namespace directly.

**Implementation:**

- Add repo-owned `monitoring` namespace NetworkPolicies:
  - deny-by-default ingress and egress for `monitoring`
  - allow Grafana -> Prometheus
- allow Kiali -> Prometheus
- allow Kiali -> Jaeger query gRPC/HTTP
- allow Kiali -> Kubernetes API
- target Jaeger NetworkPolicies at the shared single-binary Jaeger pod label;
  query and collector access are separated by port, not by pretending the two
  Services are distinct pods
- allow Kiali -> Istiod debug interface only if required by validated Kiali
  features
  - allow mesh workloads in `default`, `istio-ingress`, `istio-egress`, and
    `monitoring` to send OTLP to `jaeger-collector`
- Extend the network-policy verifier so `monitoring` becomes a first-class
  enforced namespace instead of an implicit side case.

**Repo touchpoints:**

- new `kubernetes/network-policies/monitoring-deny.yaml`
- new `kubernetes/network-policies/monitoring-allow.yaml`
- `Tiltfile`
- `deploy/scripts/07-apply-network-policies.sh`
- `deploy/scripts/08-verify-network-policy-enforcement.sh`
- `docs/architecture/security-architecture.md`

**Exit criteria:**

- `monitoring` is covered by deny + allow manifests
- Kiali/Jaeger-required pod-to-pod flows are explicit
- no route or firewall change is needed for operator access

### Phase 7.3 - Add The Jaeger Backend

**Goal:** Deploy a stable, pinned Jaeger v2 backend without introducing a new
external datastore.

**Status, 2026-04-20:** Implemented for the local Tilt path. The repo now
contains the digest-pinned Jaeger v2 manifests under
`kubernetes/monitoring/jaeger/`, Tilt exposes a `jaeger` resource with a
loopback UI port-forward, the image-pinning inventory includes the Jaeger
deployment, and the observability port-forward verifier checks the Jaeger query
API. Phase 7.4 is still required before app traces arrive.

**Implementation:**

- Add Jaeger manifests under `kubernetes/monitoring/jaeger/`:
  - `configmap.yaml`
  - `deployment.yaml`
  - `services.yaml`
  - `pvc.yaml`
- Configure Jaeger v2 as a single binary with:
  - OTLP gRPC on `4317`
  - optional OTLP HTTP on `4318`
  - query gRPC on `16685`
  - query HTTP/UI on `16686`
  - query `base_path: /jaeger`
  - Badger storage rooted on the PVC mount
- Pin the Jaeger image by digest.
- Harden the pod explicitly:
  - non-root UID/GID
  - `seccompProfile.type: RuntimeDefault`
  - `allowPrivilegeEscalation: false`
  - drop all capabilities
  - explicit writable paths only
  - disable service-account token automount unless a validated runtime need is
    discovered

**Tilt / runtime wiring:**

- Add a `jaeger` resource in `Tiltfile`.
- Make it depend on `monitoring-namespace`, `istiod`, and the network-policy
  baseline.

**Validation:**

- `kubectl apply --dry-run=server -f kubernetes/monitoring/jaeger`
- local `tilt up`
- port-forward Jaeger UI on `16686`
- generate sample traces only after Phase 7.4 lands

**Exit criteria:**

- Jaeger is running as a `ClusterIP`-only service in `monitoring`
- no external datastore was added
- Jaeger UI is reachable only through loopback port-forward

### Phase 7.4 - Wire Istio Tracing To Jaeger

**Goal:** Make the existing Istio mesh emit traces to the internal Jaeger
backend.

**Implementation:**

- Update `kubernetes/istio/istiod-values.yaml`:
  - keep `meshConfig.enableTracing: true`
  - keep `defaultConfig.tracing: {}` to avoid legacy tracer options
  - add a new `extensionProviders` entry:
    - `name: jaeger`
    - `opentelemetry.service: jaeger-collector.monitoring.svc.cluster.local`
    - `opentelemetry.port: 4317`
- Add a new mesh-default Telemetry manifest, for example
  `kubernetes/istio/tracing-telemetry.yaml`, that selects the `jaeger`
  provider.
- Keep the initial sampling rate conservative. Start with Istio defaults unless
  local proof shows traces are too sparse to validate; if sampling needs to be
  raised, make that an explicit reviewed setting rather than an ad hoc debug
  tweak.
- Restart injected workloads or let Tilt redeploy them so sidecars consume the
  new tracing config.

**Validation:**

- `istioctl analyze` or repo-equivalent static validation if available
- `kubectl get telemetry -A`
- generate requests through the real ingress path and confirm traces appear in
  Jaeger

**Exit criteria:**

- `istiod` exposes a repo-owned Jaeger extension provider
- a checked-in Telemetry resource enables tracing
- traces from the real app path arrive in Jaeger

### Phase 7.5 - Add Kiali With Least-Privilege Defaults

**Goal:** Add Kiali without opening a new operator/control-plane management
surface and without giving it broader access than this repo needs.

**Implementation:**

- Refresh the `kiali` Helm repo from repo-owned automation before install, the
  same way this repo already refreshes `istio`, `prometheus-community`, and
  `kyverno`.
- Add `kubernetes/monitoring/kiali-values.yaml`.
- Install `kiali/kiali-server` `2.24.0` in `Tiltfile`.
- Set at minimum:
  - `auth.strategy: token`
  - `deployment.image_name: quay.io/kiali/kiali`
  - `deployment.image_version: v2.24.0`
  - `deployment.image_digest: sha256:744439cbdbbc23c7a5d70544911abf8fe0b32c88c082e9a41ae6b50748bf736e`
  - `deployment.view_only_mode: true`
  - `deployment.cluster_wide_access: false`
  - discovery selectors / accessible namespace config limited to:
    - `default`
    - `monitoring`
    - `istio-system`
    - `istio-ingress`
    - `istio-egress`
  - ingress disabled
  - service type left at `ClusterIP`
- Configure Kiali external services:
  - Prometheus internal URL to the existing `prometheus-stack-kube-prom-prometheus`
  - Jaeger tracing `internal_url` to
    `http://jaeger-query.monitoring:16685/jaeger`
  - `use_grpc: true`
- Do **not** set a public `external_url` for Jaeger or Grafana.

**Auth handling:**

- Keep Kiali on `token` auth.
- Document the operator flow for obtaining a short-lived token, for example
  `kubectl -n monitoring create token <service-account>`, only after the exact
  service account / RBAC model is finalized.

**Exit criteria:**

- Kiali is reachable only through loopback port-forward
- Kiali login requires a Kubernetes token
- Kiali can render mesh topology from the current namespaces
- Kiali can query Jaeger tracing data internally

### Phase 7.6 - Add Render Checks, Guardrails, And Smokes

**Goal:** Keep the rollout from regressing into public exposure or unpinned
third-party drift.

**Implementation:**

- Add a Jaeger/Kiali render verifier, either by extending
  `scripts/smoketest/verify-monitoring-rendered-manifests.sh` or creating a new
  companion verifier.
- Validate:
  - images are digest-pinned
  - services remain `ClusterIP`
  - Jaeger/Kiali manifests do not create ingress resources
  - Kiali does not enable anonymous auth
  - Kiali does not request cluster-wide access unless explicitly documented
  - Jaeger does not depend on Elasticsearch/OpenSearch by default
- Extend `scripts/guardrails/verify-phase-7-static-manifests.sh` so it fails on
  public Jaeger/Kiali routes, unpinned images, or forbidden auth mode drift.
- Extend `scripts/guardrails/verify-production-image-overlay.sh` so production
  render checks continue to reject any observability route exposure.
- Extend `scripts/smoketest/verify-observability-port-forward-access.sh` only
  after the service names and health endpoints are stable.

**Exit criteria:**

- static checks fail on public Jaeger/Kiali drift
- static checks fail on image-digest drift
- local smokes can prove port-forward access for all four observability tools

### Phase 7.7 - Local End-To-End Proof

**Goal:** Prove the full stack works in the default Tilt/Kind runtime before
touching OCI.

**Validation checklist:**

- `tilt up`
- monitoring stack healthy in `monitoring`
- Jaeger UI reachable through `127.0.0.1:16686`
- Kiali reachable through `https://127.0.0.1:20001`
- application traffic through `https://app.budgetanalyzer.localhost` produces
  traces visible in Jaeger
- Kiali graph and workload pages load against the real mesh
- Kiali tracing panels work against Jaeger
- Grafana and Prometheus continue to work through their existing port-forwards
- network-policy verifier, monitoring verifier, and observability port-forward
  smoke all pass

**Exit criteria:**

- no production work starts until the local proof is green

### Phase 7.8 - Production OCI Rollout

**Goal:** Add Jaeger and Kiali to OCI with the same internal-only access model
and the same repo-owned manifests.

**Implementation:**

- Apply the same Jaeger manifests to OCI.
- Install the same Kiali chart version with the same pinned values.
- Keep both services `ClusterIP`.
- Reuse the same documented operator access contract:
  - OCI host `kubectl port-forward`
  - optional SSH local forward from workstation
- Do not add DNS, public certs, Gateway listeners, or `HTTPRoute`s.
- If production-specific storage sizing differs from local, keep it in an
  explicit checked-in override file, not an imperative one-off.

**Validation checklist:**

- `kubectl get svc -n monitoring | grep -E 'jaeger|kiali'`
- `kubectl get httproute -A | grep -Ei 'grafana|prometheus|kiali|jaeger' || true`
- loopback-bound port-forward access from the OCI host
- optional workstation SSH tunnel proof
- public negative checks from outside OCI confirm no Jaeger/Kiali exposure

**Exit criteria:**

- local and OCI use the same access model
- public internet cannot reach Jaeger or Kiali

## Deferred Follow-Ups

- If Kiali's namespace-scoped RBAC turns out too limiting for a real workflow,
  revisit `cluster_wide_access=false` only after documenting the exact missing
  capabilities and updating the guardrails.
- If Jaeger Badger storage proves too fragile or too large for unattended OCI
  use, evaluate a checked-in storage migration separately. Do not smuggle a new
  datastore into this rollout.
- Only add Jaeger/Kiali to the aggregate smoke once their service names,
  health endpoints, and token/auth workflow are stable enough to avoid flaky CI
  or local developer confusion.

## Success Criteria

- Jaeger `2.17.0` and Kiali `2.24.0` are added with digest-pinned,
  multi-architecture images.
- Jaeger and Kiali remain internal-only in local and OCI.
- Istio emits traces to Jaeger through a checked-in extension provider +
  Telemetry resource.
- Kiali runs in view-only, token-authenticated mode with non-cluster-wide RBAC.
- No public observability route or hostname is introduced.
- Static guardrails and local smokes make future drift obvious.
