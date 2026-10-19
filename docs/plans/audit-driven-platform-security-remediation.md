# Audit-Driven Safe Platform Upgrades Plan

Implement only the platform changes justified by the 2026-10-18 lifecycle and
image-security audit. This plan supersedes the Helm/platform modernization scope
in `docs/plans/manual-ecosystem-dependency-modernization.md`; that broad manual
plan is context, not an execution dependency. Do not continue its freshness-led
Kubernetes, Gateway API, cert-manager, external-secrets, Grafana, Helm, or other
dependency work while executing this plan.

The intended end state is:

- Kubernetes stays on `1.35.8` and Helm stays on `3.22.1`;
- Gateway API stays on `1.5.1` while Istio moves from `1.29.9` to `1.30.6`;
- Kyverno moves from chart `3.8.2` / app `1.18.2` to chart `3.9.1` / app
  `1.19.1`;
- Kiali moves with Istio to a chart/application release whose published
  compatibility data explicitly covers Istio `1.30`;
- kube-prometheus-stack stays on chart `83.4.3`, and its component versions stay
  unchanged during this plan; and
- cert-manager `1.20.4`, external-secrets `2.2.0`, and Grafana `12.4.13` remain
  unchanged.

The kube-state-metrics finding is deliberately sequenced afterward in
`docs/plans/kube-state-metrics-security-remediation.md`. That plan keeps chart
`83.4.3` and changes only the kube-state-metrics image. It is not part of this
plan's completion criteria.

Use exact versions in this plan as the reviewed target lines. A newer release is
not an automatic substitute. A newer patch on the same selected line may replace
an exact target only when fresh support/security evidence makes the reason
explicit in the durable audit record and the resulting scope remains unchanged.

All phases execute only in this orchestration repository. Preserve unrelated
user changes and do not edit sibling service code. Do not perform Git write
operations, publish anything, administer staging or production, restore retired
OCI paths, or generate/rotate TLS material. The production surface is an offline
provider-neutral reference only. Keep every third-party image immutable and
Linux ARM64-capable, and keep observability internal-only.

Before any Kubernetes mutation, follow
`docs/architecture/autonomous-ai-execution.md`: require the exact `kind-kind`
context and referenced cluster, an exact loopback HTTPS API authority with no
proxy override, the local `kind` cluster, and a Ready `kind-control-plane` node.
If imported TLS or native-runtime prerequisites fail, stop for the documented
human workflow; never bypass verification. Before the static security suite,
use the repository-local hash-verified PyYAML interpreter documented in
`docs/ci-cd.md#security-guardrailsyml`.

The implementation must retain the audit's distinction between raw scanner
findings and demonstrated exploitability. Record exact images, platforms,
scanner/database metadata, and fixed-version evidence; do not claim that every
reported package vulnerability is reachable or that a lower count proves an
image is risk-free. The durable audit record created by this plan is
`docs/research/platform-security-audit-2026-10-18.md`.

## Phase 1: Record The Bounded Audit And Explicit Deferrals

### Workspace

.

### Goal

Create a durable, reproducible decision record for the reduced platform scope,
including the explicit decision to leave monitoring unchanged until the
standalone kube-state-metrics remediation plan runs.

### Scope

- Reconfirm the checked-in and rendered versions for Kubernetes, Helm, Gateway
  API, Istio, Kyverno, kube-prometheus-stack, Kiali, cert-manager,
  external-secrets, Grafana, kube-state-metrics, Prometheus Operator, and
  Prometheus.
- Record the supplied support and Trivy `0.76` audit conclusions in
  `docs/research/platform-security-audit-2026-10-18.md`, including source URLs,
  retrieval dates, exact image references/digests, target platform,
  scanner/database metadata, and the keep/upgrade/defer verdict for every
  family.
- Record kube-prometheus-stack `83.4.3`, kube-state-metrics `2.18.0`, Prometheus
  Operator/config reloader `0.90.1`, Prometheus `3.11.3`, and Grafana `12.4.13`
  as unchanged by this plan.
- Link the kube-state-metrics finding to
  `docs/plans/kube-state-metrics-security-remediation.md` as ordered follow-up
  work after this plan completes.

### Non-goals

- Do not change Tilt, production-reference, chart, image, or runtime version
  declarations in this phase.
- Do not upgrade a retained family to make Renovate or another dashboard quiet.
- Do not change any monitoring chart, CRD, component image, values,
  post-renderer, RBAC, or runtime behavior.
- Do not create an ADR or modify files under `docs/decisions/` or
  `docs/archive/`.
- Do not contact or mutate a Kubernetes cluster; this phase is render- and
  evidence-only.

### Required context

- `AGENTS.md`
- `docs/OWNERSHIP.md`
- `docs/dependency-automation.md`
- `docs/architecture/observability.md`
- `deploy/README.md`
- `kubernetes/production/README.md`
- `scripts/README.md`
- `scripts/security/render-image-scan-inputs.sh`
- `.github/workflows/exact-image-security-evidence.yml`
- `kubernetes/monitoring/prometheus-stack-values.yaml`
- `scripts/ops/post-render-prometheus-stack.sh`
- `docs/research/prometheus-operator-rbac-baseline.md`

### Execution steps

1. Inspect the worktree first and preserve all pre-existing edits. Inventory
   version declarations and rendered images from active sources; exclude
   `archive/oci/`, `docs/archive/`, and generated state.
2. Reproduce or verify the audit evidence with upstream release/support data,
   Helm chart metadata and default values, Linux ARM64 manifest inspection, and
   Trivy `0.76` evidence for the exact candidate image digests. Clearly separate
   raw OS/package findings from reachability claims.
3. Render the current monitoring chart only to verify and record its existing
   exact chart/component baseline. Do not test or select an alternate monitoring
   chart in this plan.
4. Add `docs/research/platform-security-audit-2026-10-18.md`. Include the safe
   upgrade set, scanner caveats, retained/deferred families, and the explicit
   ordered handoff to
   `docs/plans/kube-state-metrics-security-remediation.md`. Update
   `docs/OWNERSHIP.md` only if this work establishes a new recurring canonical
   documentation topic.

### Implementation notes

Use disposable directories below `tmp/` for candidate renders and scanner
artifacts. Do not put generated evidence or caches under version control. The
research record should summarize reproducible commands and findings rather than
copy full scanner JSON. Monitoring implementation belongs only to the ordered
follow-up plan.

The supplied audit found these raw counts: kube-state-metrics `2.18.0` had 2
critical/47 high versus 0 critical/9 high for `2.20.0`; Operator `0.90.1` had
31 high versus 4 high for `0.94.1`; and Prometheus `3.11.3` had 86 high versus 8
high for `3.15.0-distroless`. Reproduction may differ as vulnerability databases
change, so preserve timestamped metadata and explain differences instead of
forcing counts to match.

### Validation

- Render the current monitoring baseline with Helm `3.22.1` and Kubernetes
  `1.35.8` capabilities without applying it, and record its existing versions.
- Confirm the research record explicitly says that Kubernetes `1.35.8`, Helm
  `3.22.1`, Gateway API `1.5.1`, cert-manager `1.20.4`, external-secrets `2.2.0`,
  kube-prometheus-stack `83.4.3`, all current monitoring component versions, and
  Grafana `12.4.13` are not upgrade targets in this plan.
- Confirm the record links the standalone kube-state-metrics plan and does not
  authorize any other monitoring migration.

### Completion criteria

A fresh worker can identify the exact safe upgrade set, the unchanged families,
and the separately ordered kube-state-metrics follow-up without interpreting the
broad manual modernization plan.

## Phase 2: Upgrade Istio And Its Coupled Kiali Release

### Workspace

.

### Goal

Move all active local and offline-reference Istio chart declarations to
`1.30.6`, retain Gateway API `1.5.1`, and update Kiali to an explicitly
Istio-1.30-compatible release while preserving the edge, egress, tracing,
security, and internal-only observability contracts.

### Scope

- Update the Istio base, CNI, istiod, and egress gateway chart pins and all
  coupled active comments, render inputs, version contracts, and documentation.
- Select the Kiali chart/application pair from its published compatibility
  matrix rather than by freshness, then update its chart pin, image tag, digest,
  values, post-renderer assumptions, render inputs, and documentation together.
- Keep Gateway API CRDs at `v1.5.1` in both local and offline-reference sources.
- Adapt repository-owned values or checks only where the selected releases
  changed a real render contract.

### Non-goals

- Do not move to Istio `1.31`, Gateway API `1.6.3`, Kubernetes `1.37`, or Kiali
  merely because it is latest.
- Do not change public routes, authentication lanes, rate-limit policy,
  observability publication, or service logic.
- Do not apply to staging or production.

### Required context

- `docs/research/platform-security-audit-2026-10-18.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/observability.md`
- `docs/development/local-environment.md`
- `docs/architecture/session-edge-authorization-pattern.md`
- `Tiltfile`
- `scripts/lib/production-version-contract.sh`
- `scripts/security/render-image-scan-inputs.sh`
- `kubernetes/istio/`
- `kubernetes/monitoring/kiali-values.yaml`
- `scripts/ops/post-render-kiali-server.sh`
- `deploy/README.md`

### Execution steps

1. Review Istio `1.30.6` upgrade notes and the Kiali compatibility matrix. Record
   the exact compatible Kiali chart/app choice and why it is coupled to Istio
   `1.30` in `docs/research/platform-security-audit-2026-10-18.md` or the
   nearest owner document.
2. Update every active Istio chart declaration to `1.30.6`, including local
   Tilt installs and `scripts/lib/production-version-contract.sh`. Update stale
   comments and docs that name `1.29.9`; do not touch archived files.
3. Render the base, CNI, istiod, and gateway charts for Kubernetes `1.35.8`.
   Review value/schema changes and reconcile only required differences while
   preserving CNI, `REGISTRY_ONLY` egress, ext_authz, tracing, gateway
   hardening, ClusterIP egress, and Linux ARM64 support.
4. Update the Kiali chart and application image as one unit, using an immutable
   ARM64-capable digest. Re-evaluate the existing Jaeger gRPC/HTTP wiring and
   version-probe workaround against the selected release; remove or change the
   workaround only if the new behavior and focused checks prove it obsolete.
5. Update render/verifier assumptions, executable image inventories, and owner
   documentation affected by actual changed behavior. Keep Kiali standalone,
   token-authenticated, namespace-scoped, view-only, and ClusterIP-only.
6. Assert by source search and render inspection that active Gateway API pins
   remain exactly `v1.5.1` and no unrelated retained family changed.

### Implementation notes

The Kiali exact version is intentionally selected from published compatibility
evidence during execution because the audit specified a compatibility outcome,
not a freshness target. The completed source must still contain one exact chart
pin and one exact digest; do not leave a floating range. If Kiali has no release
with published Istio `1.30` compatibility, stop rather than guessing.

If any shell script changes, run `bash -n` and ShellCheck on every changed shell
file and fix all warnings. Preserve any pre-existing user edit in
`scripts/lib/production-version-contract.sh` while integrating the version
changes.

### Validation

- Render all selected Istio and Kiali charts through the repository-owned local
  and production-reference paths.
- Run `./scripts/guardrails/verify-production-image-overlay.sh`.
- Run `./scripts/security/render-image-scan-inputs.sh --output-dir` with a new
  empty disposable directory and inspect the resulting Istio/Kiali images.
- With the pinned PyYAML interpreter, run
  `./scripts/guardrails/verify-static-security-manifests.sh` and its
  `--self-test` mode.
- Run focused tests for any changed post-renderer or verifier and validate every
  changed shell script with Bash syntax and ShellCheck.
- Confirm active source contains Istio `1.30.6`, the selected exact Kiali pin,
  and Gateway API `v1.5.1`, with no active `1.29.9` or Kiali `2.24.0` deployment
  pin left behind.

### Completion criteria

Local and offline-reference sources render one coherent Istio `1.30.6` and
compatible Kiali family, all static/production checks pass, Gateway API remains
`1.5.1`, and documentation describes only behavior actually selected and
verified.

## Phase 3: Upgrade Kyverno To The Supported 1.19 Line

### Workspace

.

### Goal

Upgrade Kyverno from chart `3.8.2` / app `1.18.2` to chart `3.9.1` / app
`1.19.1` across local Tilt and the offline production reference while retaining
the existing admission, image-pinning, hardening, and policy-test contracts.

### Scope

- Update every active Kyverno chart pin to `3.9.1`.
- Update all chart-managed controller, init, migration, cleanup, and hook image
  overrides to chart-compatible immutable digests for app `1.19.1`.
- Reconcile chart value-schema or rendered-resource changes without weakening
  admission behavior or security contexts.
- Update affected active comments, inventories, verifiers, and documentation.

### Non-goals

- Do not redesign repository Kyverno policies or relax them to pass the new
  chart.
- Do not accept mutable image tags or omit a chart-managed workload from the
  production render evidence.
- Do not update unrelated charts or archived OCI files.

### Required context

- `docs/research/platform-security-audit-2026-10-18.md`
- `Tiltfile`
- `deploy/helm-values/kyverno.values.yaml`
- `scripts/lib/production-version-contract.sh`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `scripts/lib/image-pinning-targets.txt`
- `scripts/lib/allowed-latest-image-refs.txt`
- `kubernetes/kyverno/policies/`
- `kubernetes/kyverno/tests/`
- `docs/ci-cd.md`

### Execution steps

1. Inspect chart `3.9.1` metadata, defaults, CRDs, hooks, and rendered image set
   for Kubernetes `1.35.8`; confirm app `1.19.1` and Linux ARM64 support.
2. Update local and production-reference chart declarations to `3.9.1`. Migrate
   `deploy/helm-values/kyverno.values.yaml` to the supported value schema and
   replace every rendered image with its reviewed immutable digest.
3. Compare old and new renders for CRDs, webhook failure policy, exclusions,
   controller replicas, service-account token use, Pod Security compatibility,
   resource limits, and hook behavior. Make only compatibility and security
   changes justified by that comparison.
4. Update static checks, image inventories, active comments, and nearest owner
   documentation when rendered names or behavior changed. Do not suppress a
   verifier because the chart changed.
5. Run the complete Kyverno fixture and representative Tilt-image replay path,
   then prove the production chart render contains no mutable controller or
   hook image.

### Implementation notes

Chart `3.9.1` is the audited target because it carries the supported Kyverno
`1.19.1` app and security fixes. Do not substitute a later chart generation
without recording a new audit reason. Preserve fail-closed admission and the
existing recovery exclusion for the `kyverno` namespace.

If any shell script changes, run `bash -n` and ShellCheck on every changed shell
file and fix all warnings.

### Validation

- With the pinned PyYAML interpreter, run
  `./scripts/guardrails/verify-static-security-manifests.sh` and
  `./scripts/guardrails/verify-static-security-manifests.sh --self-test`.
- Run `./scripts/guardrails/verify-production-image-overlay.sh`.
- Render exact image-scan inputs into a new empty disposable directory and
  inspect the Kyverno image set for completeness, immutable digests, and
  `linux/arm64` resolution.
- Run Bash syntax and ShellCheck for every changed shell script.
- Confirm active source has chart `3.9.1`, renders app `1.19.1`, and has no
  active chart `3.8.2` deployment pin.

### Completion criteria

Both deployment surfaces render Kyverno chart `3.9.1` / app `1.19.1` with a
complete immutable ARM64 image set, all policy fixtures and static guardrails
pass, and no admission or hardening control was weakened.

## Phase 4: Prove The Integrated Local Runtime And Close Documentation

### Workspace

.

### Goal

Reconcile the complete changed platform into the authorized local Tilt/Kind
runtime, prove the coupled Istio/Kiali and Kyverno upgrades without regressing
the unchanged monitoring stack, and leave active documentation and evidence
consistent with the reduced audit-led scope.

### Scope

- Perform final static/offline verification from the integrated worktree.
- Reconcile the supported local stack without recreating the cluster unless a
  documented clean-runtime prerequisite genuinely requires the user-owned
  bootstrap workflow.
- Run focused and aggregate live-local acceptance for ingress/egress, admission,
  monitoring, tracing, Kiali, least-privilege RBAC, and general application
  health.
- Resolve stale active documentation and version references introduced by the
  completed work.

### Non-goals

- Do not run `setup.sh` as a daily startup command, erase PVC-backed data, or
  generate TLS certificates.
- Do not deploy to or inspect staging/production.
- Do not expand into deferred dependency proposals or service-owned defects.
- Do not modify the accepted source plan while AI Session Handler is executing
  it.

### Required context

- All earlier phase outcomes and
  `docs/research/platform-security-audit-2026-10-18.md`
- `docs/development/getting-started.md`
- `docs/development/local-environment.md`
- `docs/architecture/autonomous-ai-execution.md`
- `docs/architecture/observability.md`
- `docs/runbooks/tilt-debugging.md`
- `scripts/README.md`
- `deploy/README.md`

### Execution steps

1. Inspect the complete diff and active version references. Confirm the only
   intended dependency-family changes are Istio, coupled Kiali, and Kyverno;
   retained/deferred families and all monitoring declarations must remain at
   their audited versions.
2. Ensure the hash-verified PyYAML environment exists, then run the static
   security suite with its explicit interpreter, self-tests, the
   production-reference verifier, and exact image-input render from the final
   worktree. Validate all changed shell scripts with Bash syntax and ShellCheck.
3. Run `./scripts/bootstrap/check-agent-vm-prerequisites.sh --native-runtime`.
   If it fails, stop and report the prerequisite; do not compensate in
   orchestration. If Tilt is not already healthy, start it through the supported
   `tilt up` daily path in a managed terminal and wait for the relevant resources
   to converge. Do not run destructive bootstrap.
4. Confirm the live chart/app/image versions and rollout health for Istio,
   Kiali, and Kyverno. Confirm Gateway API remains `1.5.1`, the unchanged
   monitoring components remain healthy on chart `83.4.3`, all expected pods
   are Ready, and observability Services remain `ClusterIP`.
5. Run the focused ingress, tracing, monitoring render/runtime, observability
   access, security guardrail, and Prometheus Operator least-privilege
   verifiers. Triage failures through the owner docs and fix durable
   repo-controlled causes without relaxing controls or hiding a sibling-service
   defect.
6. Run `./scripts/smoketest/smoketest.sh` as the final integrated local proof.
   Capture concise command/results and scanner evidence in the dated research
   record; keep generated logs and raw artifacts under ignored `tmp/` paths.
7. Update canonical owner documentation first, then summaries/cross-links.
   Remove stale active statements that require the superseded broad Helm work
   or identify old deployed versions. Do not rewrite archived history or ADRs.

### Implementation notes

Expected targeted live commands include
`./scripts/smoketest/verify-istio-ingress.sh`,
`./scripts/smoketest/verify-istio-tracing-config.sh`,
`./scripts/smoketest/verify-monitoring-rendered-manifests.sh`,
`./scripts/smoketest/verify-monitoring-runtime.sh`,
`./scripts/smoketest/verify-observability-port-forward-access.sh`,
`./scripts/smoketest/verify-security-guardrails.sh`, and
`./scripts/smoketest/verify-prometheus-operator-least-privilege.sh`. Use the
canonical script catalog if interfaces changed during earlier phases.

Do not report the task complete merely because manifests render. Conversely,
do not claim production parity: the accepted runtime evidence is local
Tilt/Kind plus offline production-reference rendering.

### Validation

- All final static, self-test, production-reference, shell, and exact-image
  render checks pass.
- `tilt get uiresources` and Kubernetes rollout/pod inspection show the changed
  resources healthy on the verified local target.
- Every focused verifier listed above passes, followed by
  `./scripts/smoketest/smoketest.sh`.
- Source and rendered-output checks prove: Istio `1.30.6`; Gateway API `1.5.1`;
  Kyverno chart `3.9.1` / app `1.19.1`; the selected compatible Kiali pair;
  kube-prometheus-stack `83.4.3`; Kubernetes `1.35.8`; Helm `3.22.1`;
  cert-manager `1.20.4`; external-secrets `2.2.0`; and Grafana `12.4.13`.
- The dated audit record contains the final exact targets, validation results,
  scanner caveats, explicit deferrals, and the ordered link to the standalone
  kube-state-metrics remediation plan.

### Completion criteria

The reduced audit-driven upgrade set is healthy in local Tilt/Kind, the offline
production reference and security evidence are coherent, all relevant
repository gates pass, retained families are unchanged, and active
documentation no longer presents unsupported freshness work as required.
