# Kube-State-Metrics Security Remediation Plan

Remediate the audited kube-state-metrics critical image findings without
changing the kube-prometheus-stack chart or any other monitoring component.
Run this plan only after
`docs/plans/audit-driven-platform-security-remediation.md` has completed.

The intended change is deliberately narrow:

- keep kube-prometheus-stack chart `83.4.3`;
- change only the kube-state-metrics runtime image from `2.18.0` to `2.20.0`
  through the existing `kube-state-metrics.image` values override;
- select and pin the exact Linux ARM64-capable digest for `2.20.0`;
- keep Prometheus Operator and config reloader `0.90.1`, Prometheus `3.11.3`,
  Grafana `12.4.13`, all Prometheus Operator CRDs, and all other monitoring
  images unchanged; and
- preserve existing Services, ServiceMonitors, RBAC, NetworkPolicies,
  dashboards, scrape behavior, security contexts, resources, and internal-only
  exposure.

This plan does not authorize a kube-prometheus-stack chart migration. Do not
change the parent chart, replace its bundled kube-state-metrics subchart, copy
templates or CRDs from another chart generation, or use an unrelated chart
upgrade as a workaround. If kube-state-metrics `2.20.0` is not compatible with
the chart `83.4.3` rendered command/RBAC contract, stop and report that concrete
blocker instead of broadening scope.

All phases execute only in this orchestration repository. Preserve unrelated
user changes and do not edit sibling service code. Do not perform Git write
operations, publish anything, administer staging or production, restore retired
OCI paths, or generate/rotate TLS material. The production surface is an offline
provider-neutral reference only. Keep the selected image immutable and Linux
ARM64-capable, and keep observability internal-only.

Before any Kubernetes mutation, follow
`docs/architecture/autonomous-ai-execution.md`: require the exact `kind-kind`
context and referenced cluster, an exact loopback HTTPS API authority with no
proxy override, the local `kind` cluster, and a Ready `kind-control-plane` node.
If imported TLS or native-runtime prerequisites fail, stop for the documented
human workflow; never bypass verification. Before the static security suite,
use the repository-local hash-verified PyYAML interpreter documented in
`docs/ci-cd.md#security-guardrailsyml`.

The audit's raw scanner counts are evidence for prioritization, not proof of
reachability: kube-state-metrics `2.18.0` had 2 critical and 47 high findings,
while `2.20.0` had 0 critical and 9 high findings in the Trivy `0.76` audit.
Scanner databases change, so preserve exact image, platform, scanner, database,
and timestamp metadata and explain count differences rather than forcing a
future run to reproduce those numbers.

## Phase 1: Implement And Statically Prove The Narrow Image Override

### Workspace

.

### Goal

Update only the chart-83 kube-state-metrics image override to the reviewed
`2.20.0` ARM64 digest and prove through source, render comparison, and scanner
evidence that no other monitoring component or contract changed.

### Scope

- Verify the safe-upgrades plan's expected Istio/Kiali and Kyverno state is
  present before beginning this ordered follow-up.
- Confirm kube-state-metrics `2.20.0` accepts the command-line arguments and
  collectors rendered by the bundled chart-83 kube-state-metrics subchart.
- Update the kube-state-metrics image tag and digest in
  `kubernetes/monitoring/prometheus-stack-values.yaml`.
- Update focused assertions, exact-image evidence, and active documentation only
  where necessary to identify and verify the actual runtime image.
- Record final scanner evidence in
  `docs/research/platform-security-audit-2026-10-18.md` or a directly linked
  dated follow-up.

### Non-goals

- Do not change kube-prometheus-stack chart `83.4.3`, its dependency lock, or
  its bundled kube-state-metrics subchart templates.
- Do not change Prometheus Operator, config reloader, Prometheus, Grafana,
  Kiali, Jaeger, Alertmanager, node exporter, CRDs, RBAC, or monitoring
  persistence.
- Do not add a post-render patch to disguise chart metadata or force unrelated
  resource changes.
- Do not claim that all vulnerabilities are reachable or that zero critical
  scanner findings means the image has no security risk.
- Do not contact or mutate a Kubernetes cluster in this phase.

### Required context

- `AGENTS.md`
- `docs/plans/audit-driven-platform-security-remediation.md`
- `docs/research/platform-security-audit-2026-10-18.md`
- `docs/dependency-automation.md`
- `docs/architecture/observability.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`
- `Tiltfile`
- `scripts/lib/production-version-contract.sh`
- `kubernetes/monitoring/prometheus-stack-values.yaml`
- `kubernetes/production/monitoring/prometheus-stack-values.override.yaml`
- `scripts/security/render-image-scan-inputs.sh`
- `scripts/smoketest/verify-monitoring-rendered-manifests.sh`
- `.github/workflows/exact-image-security-evidence.yml`

### Execution steps

1. Inspect the worktree and preserve all pre-existing edits. Verify the
   safe-upgrades plan's expected Istio `1.30.6`, selected compatible Kiali pair,
   and Kyverno chart `3.9.1` declarations are present, and verify the monitoring
   baseline is still chart `83.4.3` with kube-state-metrics `2.18.0`. Stop if
   those ordered prerequisites are not satisfied.
2. Inspect kube-state-metrics `2.20.0` release notes and container help output.
   Compare them with the exact arguments, collectors, ports, probes, service
   account, and RBAC rendered by chart `83.4.3`. Search repository dashboards,
   rules, and verifiers for kube-state-metrics metrics used by the application
   and identify any 2.20 metric removal or semantic change that would affect
   them.
3. Resolve the exact `linux/arm64` manifest for kube-state-metrics `2.20.0`,
   verify its provenance/platform availability, and record the immutable digest.
   Update only the `tag` and `sha` fields under the existing
   `kube-state-metrics.image` override.
4. Render chart `83.4.3` before and after the override with the repository's
   values and post-renderer. Compare normalized output and require the only
   deployable change to be the kube-state-metrics container image, except for a
   narrowly justified runtime-version assertion or documentation change. The
   chart, resource names, args, RBAC, Service, ServiceMonitor, NetworkPolicy,
   security context, and resources must remain unchanged.
5. Check how chart `83.4.3` renders `app.kubernetes.io/version`. Its bundled
   subchart may retain `2.18.0` as chart metadata after the image override. Do
   not treat that generated label as runtime truth or rewrite it with a
   post-renderer. Make focused verification use the exact pod image and the
   `kube_state_metrics_build_info` metric, and document the metadata distinction
   if the render confirms it.
6. Render exact image-scan inputs and run Trivy `0.76` against the final exact
   `linux/arm64` digest. Record scanner/database metadata, raw counts, fixed
   critical findings, residual findings, and reachability caveats in the dated
   audit record or linked follow-up.
7. Update the nearest active owner documentation and focused assertions for the
   new runtime image. Do not update archived files or the Prometheus Operator
   RBAC baseline because neither the Operator nor its RBAC changes.

### Implementation notes

The existing values already override the kube-state-metrics image independently
of the parent chart, so this plan uses that supported configuration surface. The
bundled subchart's `Chart.appVersion` may continue to appear in generated labels;
the deployed digest, container image ID, and build-info metric are the acceptance
sources for the actual binary version.

Use disposable directories below `tmp/` for before/after renders and scanner
artifacts. Do not commit generated manifests, image layers, caches, or full
scanner JSON. If a shell script changes, run `bash -n` and ShellCheck on every
changed shell file and fix all warnings.

### Validation

- Render kube-prometheus-stack `83.4.3` with the local values and with the
  production monitoring override; both renders select only the reviewed
  kube-state-metrics `2.20.0` digest.
- Compare normalized before/after manifests and prove no non-image deployable
  monitoring resource changed.
- Run `./scripts/guardrails/verify-production-image-overlay.sh`.
- With the pinned PyYAML interpreter, run
  `./scripts/guardrails/verify-static-security-manifests.sh` and its
  `--self-test` mode.
- Render exact image-scan inputs into a new empty disposable directory, confirm
  the kube-state-metrics target resolves for `linux/arm64`, and run the focused
  Trivy evidence against that exact digest.
- Run focused tests plus Bash syntax and ShellCheck for any changed verifier or
  script.
- Confirm source and rendered output retain chart `83.4.3`, Operator/config
  reloader `0.90.1`, Prometheus `3.11.3`, and Grafana `12.4.13`.

### Completion criteria

Source and both offline render paths select kube-state-metrics `2.20.0` at one
reviewed immutable ARM64 digest, the parent chart and every other monitoring
component remain unchanged, static and production-reference gates pass, and the
dated evidence records the remediated critical findings plus residual caveats.

## Phase 2: Prove The Narrow Upgrade In The Local Runtime

### Workspace

.

### Goal

Reconcile the single kube-state-metrics image change into the authorized local
Tilt/Kind runtime and prove metrics, dashboards, Prometheus targets, Kiali,
RBAC, persistence, and internal-only observability continue to work.

### Scope

- Apply the checked-in chart-83 image override through the supported Tilt path.
- Verify the live kube-state-metrics pod runs the exact `2.20.0` digest and
  reports the expected build version.
- Run focused and aggregate monitoring/runtime regression checks.
- Close the audit evidence with live-local results.

### Non-goals

- Do not manually patch the live Deployment or create cluster drift.
- Do not run `setup.sh`, recreate the cluster, erase Prometheus data, or alter
  PVCs.
- Do not change another monitoring component in response to a failure.
- Do not deploy to or inspect staging/production.
- Do not modify the accepted source plan while AI Session Handler is executing
  it.

### Required context

- The Phase 1 outcome and scanner evidence
- `docs/architecture/autonomous-ai-execution.md`
- `docs/architecture/observability.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/runbooks/tilt-debugging.md`
- `scripts/README.md`
- `scripts/smoketest/verify-monitoring-runtime.sh`
- `scripts/smoketest/verify-monitoring-rendered-manifests.sh`
- `scripts/smoketest/verify-prometheus-operator-least-privilege.sh`

### Execution steps

1. Inspect the complete diff and confirm the only deployable monitoring change
   is the kube-state-metrics image tag/digest under chart `83.4.3`.
2. Run `./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime`.
   If it fails, stop and report the prerequisite; do not compensate in
   orchestration. If Tilt is not already healthy, start it through the supported
   `tilt up` daily path in a managed terminal and wait for relevant resources to
   converge. Do not run destructive bootstrap.
3. Let the checked-in `prometheus-stack` Tilt resource perform the Helm upgrade.
   Verify only the kube-state-metrics Deployment rolls, its pod becomes Ready,
   the pod spec uses the expected immutable image, and the runtime container
   image ID resolves to the reviewed digest.
4. Query Prometheus for `kube_state_metrics_build_info` and require version
   `2.20.0`. Verify the kube-state-metrics ServiceMonitor target is Up and check
   the metrics used by repository dashboards/rules for expected labels and
   nonempty series.
5. Run the focused monitoring render/runtime, observability access, security
   guardrail, and Prometheus Operator least-privilege verifiers. Confirm Kiali,
   Grafana, Prometheus, Jaeger, Istio metrics, application metrics, the 10Gi
   Prometheus PVC, and ClusterIP-only exposure remain healthy.
6. Run `./scripts/smoketest/smoketest.sh` as the final integrated local proof.
   Fix only durable repository-controlled regressions caused by the image
   change; do not broaden scope or hide a sibling-service defect.
7. Record concise live version, rollout, target, metric, verifier, and aggregate
   results in the dated audit record or linked follow-up. Keep generated logs
   and raw artifacts under ignored `tmp/` paths.

### Implementation notes

Expected focused commands include
`./scripts/smoketest/verify-monitoring-rendered-manifests.sh`,
`./scripts/smoketest/verify-monitoring-runtime.sh`,
`./scripts/smoketest/verify-observability-port-forward-access.sh`,
`./scripts/smoketest/verify-security-guardrails.sh`, and
`./scripts/smoketest/verify-prometheus-operator-least-privilege.sh`. Use the
canonical script catalog if an interface changed before execution.

The generated app-version label is not sufficient proof of the running binary
when overriding an image under an older bundled subchart. Require the pod's
exact image/image ID plus the build-info metric.

### Validation

- The live kube-state-metrics pod is Ready on the reviewed `2.20.0` ARM64 digest
  and `kube_state_metrics_build_info` reports `2.20.0`.
- Prometheus reports the kube-state-metrics target Up and the repository-used
  kube-state metrics remain queryable with expected labels.
- Focused monitoring, observability, security, and least-privilege verifiers
  pass, followed by `./scripts/smoketest/smoketest.sh`.
- Live inspection confirms chart `83.4.3`, Operator/config reloader `0.90.1`,
  Prometheus `3.11.3`, Grafana `12.4.13`, existing CRDs/RBAC, and the Prometheus
  PVC remain unchanged.
- The final evidence records exact image/runtime proof, scanner caveats, and all
  validation results without claiming hosted production parity.

### Completion criteria

The local runtime uses kube-state-metrics `2.20.0` at the reviewed immutable
digest, the audited critical image findings are remediated, all existing
monitoring consumers and security contracts pass regression checks, and no
parent-chart or unrelated component migration occurred.
