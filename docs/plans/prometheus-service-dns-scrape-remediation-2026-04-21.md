# Plan: Prometheus Service-DNS Scrape Remediation

Date: 2026-04-21

Related documents:

- [docs/architecture/observability.md](../architecture/observability.md)
- [kubernetes/monitoring/prometheus-stack-values.yaml](../../kubernetes/monitoring/prometheus-stack-values.yaml)
- [scripts/smoketest/verify-monitoring-runtime.sh](../../scripts/smoketest/verify-monitoring-runtime.sh)
- [scripts/ops/triage-kiali-findings.sh](../../scripts/ops/triage-kiali-findings.sh)

## Problem Statement

Kiali currently reports Prometheus health as `Failure` even though the
Prometheus pod itself is healthy and the Spring Boot service scrapes in
`default` are working.

The immediate issue is that several monitoring and control-plane scrape targets
are being scraped at pod IPs from a mesh-injected Prometheus pod and are
returning `502 Bad Gateway`. The same targets are reachable from Prometheus when
addressed through their stable Kubernetes Service DNS names and service ports.

This means the failure is in the scrape addressing model, not in the Prometheus
process and not in the monitored workloads themselves.

## Validated Diagnosis

Evidence captured on 2026-04-21 from the live Tilt cluster:

- Kiali marked `monitoring/prometheus` as `Failure` with a high error ratio.
- Prometheus active targets showed these `DOWN` scrape URLs:
  - `http://192.168.82.12:15014/metrics` for `istiod`
  - `http://192.168.82.25:3000/metrics` for `prometheus-stack-grafana`
  - `http://192.168.82.5:8080/metrics` for `prometheus-stack-kube-prom-operator`
  - `http://192.168.82.36:8080/metrics` for `kube-state-metrics`
- From inside the Prometheus pod, those same workloads were reachable through
  service DNS and service ports:
  - `http://istiod.istio-system.svc.cluster.local:15014/metrics` -> `200`
  - `http://prometheus-stack-grafana.monitoring.svc.cluster.local:80/metrics` -> `200`
  - `http://prometheus-stack-kube-prom-operator.monitoring.svc.cluster.local:8080/metrics` -> `200`
  - `http://prometheus-stack-kube-state-metrics.monitoring.svc.cluster.local:8080/metrics` -> `200`
- The checked-in monitoring values explicitly mesh-inject Prometheus, but do not
  mesh-inject Grafana or kube-state-metrics.

## Root Cause

Prometheus is mesh-injected because it must scrape Envoy metrics and Spring Boot
metrics under the repo's STRICT mTLS and policy posture.

The current generated `ServiceMonitor` targets for parts of the monitoring stack
and `istiod` resolve to endpoint pod IP scrapes. In this cluster, that pod-IP
path is not reliable from the meshed Prometheus pod, while the service-DNS path
is reliable.

The repo already documents the correct pattern for Spring Boot services:

- rewrite scrape addresses to stable service DNS names rather than pod IPs
- keep the Prometheus pod mesh-injected

This plan extends that same contract to the failing monitoring and control-plane
targets.

## Goals

1. Restore healthy Prometheus scrapes for the currently failing monitoring and
   control-plane targets.
2. Clear the Kiali `monitoring/prometheus` failure that is caused by those
   scrape errors.
3. Preserve the current observability surface:
   - Spring Boot service scrapes
   - Envoy sidecar scrapes
   - `istiod` scrape
   - Grafana, Prometheus Operator, and kube-state-metrics scrapes
4. Keep Prometheus mesh-injected.
5. Make the fix repo-owned and reproducible from checked-in manifests or Helm
   values.

## Non-Goals

- Do not disable affected scrapes just to silence Kiali.
- Do not remove Prometheus sidecar injection as a shortcut.
- Do not introduce manual live-cluster drift as the durable fix.
- Do not re-architect the entire monitoring stack before fixing the scrape path.

## Recommended Direction

Prefer service-DNS-based scrapes for the affected `ServiceMonitor` targets.

Concretely:

- keep Prometheus mesh-injected
- keep the monitored workloads in their current injection mode unless a target
  proves impossible to scrape through its Service VIP
- change the failing scrape jobs so Prometheus uses stable service DNS names and
  service ports rather than endpoint pod IPs

This is the smallest change that matches the repo's existing Spring Boot
monitoring contract and the live evidence from the cluster.

## Rejected Directions

### Disable The Failing ServiceMonitors

Do not do this. It would hide real observability coverage gaps and break the
documented observability story.

### Remove Prometheus Sidecar Injection

Do not do this. The repo intentionally mesh-injects Prometheus so it can scrape
protected in-mesh metrics under the existing STRICT mTLS and policy posture.

### Mesh-Inject Every Monitoring Workload First

This may work, but it is more invasive than needed for the current failure.
The service-DNS path already succeeds for the failing targets, so rewrite-first
is the better first move.

## Implementation Plan

### Phase 1: Inventory The Affected ServiceMonitor Sources

Identify the lowest-drift way to control address relabeling for:

- `ServiceMonitor/monitoring/prometheus-stack-grafana`
- `ServiceMonitor/monitoring/prometheus-stack-kube-prom-operator`
- `ServiceMonitor/monitoring/prometheus-stack-kube-state-metrics`
- `ServiceMonitor/monitoring/istio-mesh`

For each target, record:

- owning chart or checked-in manifest source
- current generated scrape port and path
- whether chart values can inject relabelings directly
- whether a repo-owned replacement or patch is needed

Decision rule:

- prefer Helm values first
- prefer repo-owned manifest replacements second
- use post-render patching only if the chart does not expose a cleaner control

#### Phase 1 Findings

Phase 1 inventory was completed on 2026-04-21 against the checked-in values
plus the live Tilt cluster resources.

| Target | Owning source | Current scrape port/path | Direct relabel control | Phase 2 implementation choice |
| --- | --- | --- | --- | --- |
| `ServiceMonitor/monitoring/prometheus-stack-grafana` | Grafana subchart managed through `kubernetes/monitoring/prometheus-stack-values.yaml`; live object labels show `helm.sh/chart: grafana-11.6.0` | `port: http-web`, `path: /metrics`; the backing Service port is `80` | Yes. The chart exposes `grafana.serviceMonitor.relabelings` in values. | Use Helm values only. Rewrite `__address__` to `prometheus-stack-grafana.monitoring.svc.cluster.local:80`. No replacement or post-render patch is needed. |
| `ServiceMonitor/monitoring/prometheus-stack-kube-prom-operator` | Main `kube-prometheus-stack` chart-managed ServiceMonitor | `port: http`, default path `/metrics`; the backing Service port is `8080` | Yes. The chart exposes `prometheusOperator.serviceMonitor.relabelings` in values and threads them into the generated ServiceMonitor. | Use Helm values only. Rewrite `__address__` to `prometheus-stack-kube-prom-operator.monitoring.svc.cluster.local:8080`. No replacement or post-render patch is needed. |
| `ServiceMonitor/monitoring/prometheus-stack-kube-state-metrics` | `kube-state-metrics` subchart managed through the same values file; live object labels show `helm.sh/chart: kube-state-metrics-7.2.2` | `port: http`, default path `/metrics`; the backing Service port is `8080` | Yes. The subchart exposes `kube-state-metrics.prometheus.monitor.http.relabelings` for the main metrics endpoint. | Use Helm values only. Rewrite `__address__` to `prometheus-stack-kube-state-metrics.monitoring.svc.cluster.local:8080`. No replacement or post-render patch is needed. |
| `ServiceMonitor/monitoring/istio-mesh` | Repo-owned additional ServiceMonitor declared in `kubernetes/monitoring/prometheus-stack-values.yaml` under `prometheus.additionalServiceMonitors` | `port: http-monitoring`, default path `/metrics`; the backing Service port is `15014` | Yes. This entry is already authored as raw ServiceMonitor spec, so `endpoints[].relabelings` can be added directly in the checked-in values. | Use the existing repo-owned values entry. Rewrite `__address__` to `istiod.istio-system.svc.cluster.local:15014`. No replacement or post-render patch is needed. |

#### Phase 1 Outcome

Phase 2 does not need manifest replacement or post-render patching for any of
the four failing targets.

The lowest-drift implementation is:

- `grafana.serviceMonitor.relabelings`
- `prometheusOperator.serviceMonitor.relabelings`
- `kube-state-metrics.prometheus.monitor.http.relabelings`
- `prometheus.additionalServiceMonitors[].endpoints[].relabelings`

### Phase 2: Rewrite The Failing Scrapes To Stable Service DNS

For each affected scrape target, ensure the generated Prometheus target address
becomes the Kubernetes Service DNS name and service port instead of the endpoint
pod IP.

Expected target addresses after the change:

- `istiod.istio-system.svc.cluster.local:15014`
- `prometheus-stack-grafana.monitoring.svc.cluster.local:80`
- `prometheus-stack-kube-prom-operator.monitoring.svc.cluster.local:8080`
- `prometheus-stack-kube-state-metrics.monitoring.svc.cluster.local:8080`

Use explicit relabelings or equivalent chart-supported configuration so the
result is deterministic and readable in checked-in config.

### Phase 3: Keep The Monitoring Story Honest In Docs

Update the nearest documentation to state that meshed Prometheus must scrape the
affected monitoring and control-plane targets via stable service DNS rather than
endpoint pod IPs.

At minimum, update:

- `docs/architecture/observability.md`
- any nearby runbook or troubleshooting section that currently implies pod-IP
  scrapes are acceptable for these targets

### Phase 4: Add Or Tighten Verification

Extend repo-owned verification so this regression is caught locally.

Required checks:

- confirm the four previously failing targets are `UP` in Prometheus active
  targets
- confirm Kiali no longer reports Prometheus health as `Failure`
- preserve the existing Spring Boot monitoring verifier behavior

Preferred verifier changes:

- expand `scripts/smoketest/verify-monitoring-runtime.sh` or add a companion
  check so it validates:
  - `istiod`
  - Grafana
  - Prometheus Operator
  - kube-state-metrics
- verify the target `scrapeUrl` hostnames or effective target labels are the
  expected service-DNS addresses, not pod IPs, for the remediated jobs

## Success Criteria

The fix is complete when all of the following are true in a fresh local Tilt
cluster:

1. `./scripts/smoketest/verify-monitoring-runtime.sh` passes with the expanded
   coverage.
2. `kubectl exec` from the Prometheus pod to `/api/v1/targets?state=active`
   shows no `DOWN` targets for:
   - `istiod`
   - `prometheus-stack-grafana`
   - `prometheus-stack-kube-prom-operator`
   - `kube-state-metrics`
3. `./scripts/ops/triage-kiali-findings.sh --output-dir tmp/kiali-triage`
   no longer reports `monitoring/prometheus` as `Failure`.
4. The Spring Boot service scrapes in `default` remain healthy.
5. No manual cluster edits are required beyond repo-owned manifests and scripts.

## Suggested Verification Commands

```bash
./scripts/smoketest/verify-monitoring-runtime.sh

kubectl exec -n monitoring prometheus-prometheus-stack-kube-prom-prometheus-0 -c prometheus -- \
  wget -qO- http://127.0.0.1:9090/api/v1/targets?state=active | \
  jq -r '.data.activeTargets[] | select(.health != "up") | [.labels.namespace, .labels.job, .scrapeUrl, (.lastError // "")] | @tsv'

./scripts/ops/triage-kiali-findings.sh --output-dir tmp/kiali-triage
```

## Open Questions

1. Which `kube-prometheus-stack` values cleanly support the needed relabeling
   for the chart-managed ServiceMonitors, and which targets require a repo-owned
   replacement or patch?
2. Should the repo standardize on service-DNS relabeling for all ServiceMonitor
   jobs that Prometheus scrapes from inside the mesh, not just the currently
   failing four?
3. Once Prometheus health is fixed, which Kiali downstream findings disappear
   automatically and which remain as separate issues?
