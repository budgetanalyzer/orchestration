# Manual Ecosystem Dependency Modernization Plan

**Status:** Proposed  
**Created:** 2026-10-18  
**Execution model:** Human-led, manual execution with AI assistance  
**Explicit exclusion:** This is not an AI Session Handler plan and is not
formatted or authorized for autonomous phase execution.

## Purpose

Bring the Budget Analyzer ecosystem to intentionally selected current dependency
and platform versions, establish reproducible final Spring Boot 3 baselines,
complete the confusing orchestration and Helm work against those stable
applications, and only then migrate the Java platform to Spring Boot 4.

The ordering is deliberate:

1. remediate the independently fixable `service-common` findings;
2. prove and tag the final Spring Boot 3 Java baseline;
3. modernize orchestration, Helm charts, images, tools, and the other ecosystem
   repositories without mixing in Spring Boot 4;
4. establish a known-good pre-Boot-4 system checkpoint; and
5. perform Spring Boot 4 as a separately attributable Java platform migration.

The goal is not to make every Dependency Dashboard empty. The goal is to make
every accepted version an explicit support, security, compatibility, or
maintenance decision, and to leave every deferred proposal with a recorded
rationale.

## How To Use This Plan

This document is a human checklist and decision record. It intentionally does
not use the AI Session Handler template, autonomous success markers, or numbered
phase headings.

The human operator owns:

- Dependency Dashboard approvals;
- the order in which pull requests are created and merged;
- all Git commits, tags, pushes, GitHub releases, and package publication;
- any personal-host action;
- final acceptance of compatibility and vulnerability dispositions; and
- any future staging or production activity.

AI assistance may inspect repositories, trace resolved dependencies, prepare
reviewable source/configuration/documentation changes, and run authorized local
validation. AI assistance must continue to follow repository boundaries, the
exact local Kubernetes target guard, certificate restrictions, and the ban on
staging or production administration.

Do not bulk-approve a Dependency Dashboard. Create and review one coherent
update unit at a time.

## Canonical References

Use these documents for current commands and operating contracts instead of
copying their complete procedures into this plan:

- dependency policy and Dashboard semantics:
  [`docs/dependency-automation.md`](../dependency-automation.md)
- script and verifier entry points: [`scripts/README.md`](../../scripts/README.md)
- local prerequisites and supported startup:
  [`docs/development/getting-started.md`](../development/getting-started.md)
- local Tilt and live-update mechanics:
  [`docs/development/local-environment.md`](../development/local-environment.md)
- local target and autonomous-execution boundaries:
  [`docs/architecture/autonomous-ai-execution.md`](../architecture/autonomous-ai-execution.md)
- provider-neutral production-reference rendering:
  [`deploy/README.md`](../../deploy/README.md)
- observability architecture and validation:
  [`docs/architecture/observability.md`](../architecture/observability.md)
- Tilt troubleshooting: [`docs/runbooks/tilt-debugging.md`](../runbooks/tilt-debugging.md)
- development-VM and host boundary:
  [`../../workspace/docs/host-isolation.md`](../../../workspace/docs/host-isolation.md)
- `service-common` dependency and release rules:
  [`../../service-common/docs/dependency-automation.md`](../../../service-common/docs/dependency-automation.md)
  and
  [`../../service-common/docs/versioning-and-compatibility.md`](../../../service-common/docs/versioning-and-compatibility.md)

## Scope

The active repository scope is:

- `orchestration`
- `service-common`
- `currency-service`
- `permission-service`
- `transaction-service`
- `session-gateway`
- `budget-analyzer-web`
- `ext-authz`
- `workspace`
- `budget-analyzer-api-tests`

The plan covers direct dependencies, inherited dependency platforms, build and
test tooling, runtime/container images, Kubernetes and Istio versions, Helm
charts, chart image overrides, checksum-coupled tools, and the checked-in
offline production reference.

## Non-Goals

- Do not create a production environment or claim hosted-runtime parity.
- Do not deploy or administer staging or production.
- Do not restore retired OCI tooling or use `archive/oci/` as active input.
- Do not generate or rotate browser or infrastructure certificates.
- Do not weaken security, persistence, ARM64, exposure, or verification rules
  to make an upgrade pass.
- Do not combine the Spring Boot 4 migration with unresolved Helm/platform
  migrations.
- Do not require every optional major upgrade merely to make a dashboard empty.

## Working Principles

### Select targets intentionally

Immediately before opening each update, refresh the repository's public
Dependency Dashboard, upstream support status, release notes, and vulnerability
evidence. Versions named in this plan are the 2026-10-18 audit snapshot, not a
license to ignore a newer patch available at execution time.

Choose versions in this order of importance:

1. a fixed release for a relevant vulnerability;
2. a supported runtime or platform line when the current line is unsupported;
3. the latest compatible patch or minor in the selected line;
4. a major migration with a concrete support, security, or capability benefit;
5. routine tool freshness.

When Renovate offers both an intermediate patch and a newer compatible minor,
normally select the newer target and avoid sequential churn. An intermediate
chart patch is acceptable when it creates a useful diagnostic baseline before
a large chart-generation migration.

### Keep coupled families together

Treat these as coordinated version families:

- Spring Boot, Spring Cloud, Spring Framework, Spring Modulith, Springdoc, and
  the associated test platform;
- the common Gradle wrapper and Java quality tools across all Java consumers;
- Kubernetes node image, Kubernetes tools, Kind, CNI, Gateway API, and Istio;
- each Helm chart and every repository-owned image override for that chart;
- Prometheus Operator and config reloader images;
- React/React DOM and their type packages;
- Vitest, its UI, and coverage packages; and
- workspace and orchestration declarations for the same native tool.

Coordination does not require one cross-repository release artifact. Each
service may still release independently after the shared compatibility proof.

### Keep review units attributable

Use separate review units for:

- vulnerability remediation;
- build-tool updates;
- one Helm family;
- one stateful major migration;
- one Kubernetes/Istio platform move; and
- the Spring Boot 4 release train.

Do not mix unrelated frontend, database, chart, and Java framework majors in
one change merely because Renovate discovered them at the same time.

## Entry Preconditions

Before implementation begins:

- [ ] Read the canonical references relevant to the selected update.
- [ ] Confirm all ten repositories are present side by side and record their
      current commit SHAs and worktree status.
- [ ] Confirm Renovate remains the only dependency-update PR owner and
      automerge remains disabled.
- [ ] Capture the current Dependency Dashboard proposals and scanner evidence.
- [ ] Confirm the imported local TLS files and trust prerequisites are valid;
      stop for the documented human workflow if they are not.
- [ ] Before any agent-authorized Kubernetes mutation, prove the exact
      `kind-kind` context, loopback HTTPS API authority, local Kind cluster, and
      Ready `kind-control-plane` node as required by the architecture contract.
- [ ] Confirm the repository-local pinned PyYAML environment exists before the
      static security verifier is used. Do not substitute the VM package.
- [ ] Record a clean baseline from the relevant static, build, and live-local
      verifiers before changing platform versions.

## Stage: Final Spring Boot 3 `service-common` Baseline

### Objective

Apply the independently safe `service-common` updates that do not require
Spring Boot BOM overrides, prove compatibility with all four Java consumers,
and carry the remaining framework-coupled work into the Spring Boot 4
migration.

### Cherry-picked execution record

On 2026-10-18, the operator chose not to create temporary Spring Boot 3
overrides for BOM-managed dependency families because the next Java platform
step will be Spring Boot 4. The completed work and explicit deferrals below
replace the original expectation that every listed Boot 3 finding would be
remediated before that migration.

Completed:

- OpenCSV was upgraded from `3.10` to `5.12.0`. The parser now translates the
  checked OpenCSV 5 parsing exceptions to its existing public `IOException`
  contract, with malformed-input coverage.
- The resolved `service-core` runtime graph now contains BeanUtils `1.11.0`
  and Commons Lang `3.18.0`; BeanUtils `1.9.3` is no longer present. No explicit
  Commons Lang platform override was added. Existing Springdoc resolution also
  causes the published `service-web` metadata to select Commons Lang `3.20.0`.
- Checkstyle was upgraded from `12.0.1` to `12.3.1`, and JaCoCo was upgraded
  from `0.8.13` to `0.8.15`. Gradle `9.8.1` and Spotless `8.10.4` were already
  at the selected targets.
- The complete `service-common` build passed, the candidate was published to
  Maven Local, and clean refreshed builds passed in `currency-service`,
  `permission-service`, `transaction-service`, and `session-gateway` without
  consumer source or runtime orchestration configuration changes.

Deferred to the Spring Boot 4 migration:

- Do not add temporary Commons Lang `3.21.0`, Tomcat, or Netty constraints to
  the Spring Boot 3 platform. Re-evaluate their resolved versions and fixed
  floors after selecting the Boot 4 BOM.
- Carry the Spring Framework residual advisories into the coordinated Spring
  Framework 7 upgrade.
- Upgrade Testcontainers to `2.x` with the Boot 4 test stack rather than
  introducing broad test-infrastructure churn immediately beforehand.
- ShedLock `7.10.1` was attempted and reverted. Its published dependency on
  Spring Context `7.0.9` won Gradle conflict resolution over the Boot 3 BOM's
  Spring Context `6.2.19`, producing a mixed Spring 6/7 runtime and application
  startup failures (`ThemeSource` was missing). Retain ShedLock `6.10.0` until
  the Spring 7 migration.

### Current audited dependency facts

At the 2026-10-18 audit snapshot, Spring Boot `3.5.16` resolves:

- Spring Framework `6.2.19`;
- Tomcat `10.1.55`;
- Netty `4.1.135.Final`; and
- Commons Lang `3.17.0` in the `service-core` graph.

OpenCSV `3.10` independently introduces BeanUtils `1.9.3`.

The selected public fixed floors are:

- BeanUtils `1.11.0`;
- Commons Lang `3.18.0` or newer;
- Tomcat `10.1.58`; and
- Netty `4.1.137.Final`.

Spring Framework's XSLT view, fragment-rendered SSE, and WebFlux functional
header-predicate advisories have a public fixed version on the Spring Framework
7 line but no public fixed `6.2.x` version in the audit data. These are the
known residual findings that motivate, but do not get folded into, the later
Spring Boot 4 migration.

### Required update units

- [x] Upgrade OpenCSV to the reviewed `5.12.0` release.
- [x] Prove the resolved graph uses BeanUtils `1.11.0` or newer and no vulnerable
      older BeanUtils remains in any published/runtime configuration.
- [x] Prove the resolved graph reaches the Commons Lang fixed floor without an
      explicit platform override.
- [ ] **Deferred to Spring Boot 4:** Re-evaluate Commons Lang, Tomcat, and Netty
      against the selected Boot 4 BOM and add only overrides still required by
      the reviewed fixed floors.
- [x] Keep the Boot plugin and BOM coordinated at the selected final Boot 3.5
      patch.
- [x] Keep Spring Cloud on the selected compatible `2025.0.x` service release.
- [x] Keep Spring Modulith and Springdoc on the selected Boot-3-compatible release
      lines rather than prematurely selecting their Boot 4 majors.

### Independent major dispositions

The original baseline proposed these as independent pre-Boot-4 changes. Their
execution dispositions are:

- [ ] **Deferred to Spring Boot 4:** Testcontainers latest reviewed `2.x`
      release.
- [ ] **Deferred to Spring Boot 4:** ShedLock latest reviewed `7.x` release;
      retain the failed-attempt evidence in the execution record above.

Also align recognized build/test tooling where appropriate:

- [x] Gradle `9.8.1` or newer selected compatible `9.x` patch.
- [x] Spotless `8.10.4` or newer compatible `8.x` release.
- [x] Checkstyle `12.3.1` or newer compatible `12.x` release.
- [x] JaCoCo `0.8.15` or newer compatible `0.8.x` release.

### Validation before release

- [x] Run the complete `service-common` formatting and build sequence.
- [x] Inspect dependency insight for BeanUtils, Commons Lang, Spring Framework,
      Tomcat, and every Netty artifact named by an alert.
- [x] Confirm publication metadata exposes the intended platform constraints.
- [x] Publish the candidate locally using the documented workflow.
- [x] Build `currency-service`, `permission-service`, `transaction-service`, and
      `session-gateway` against that exact local candidate.
- [x] Run the relevant integration suites, including servlet and reactive
      consumers, CSV import paths, Redis/session behavior, messaging, and
      database-backed tests.
- [x] Confirm no consumer needs an undeclared Maven Local substitution or a
      compensating orchestration change.
- [x] Re-run resolved dependency evidence and record remaining findings.

### Human release checkpoint

No final Spring Boot 3 release, tag, or consumer version update was performed
as part of this cherry-picked work. If the operator still chooses to create
that checkpoint before Boot 4, do so only after the completed consumer
validation above:

- [ ] Select the stable release version under the existing versioning contract.
- [ ] Have the human publish, commit, tag, and push the final Boot 3
      `service-common` release.
- [ ] Record the known Spring Framework 6.2 residual advisories and the verified
      non-use of their vulnerable features in the release notes or linked
      security disposition.
- [ ] Update each Java consumer from the snapshot to the stable release.
- [ ] Build and tag each consumer's final Boot 3 baseline under its normal
      human-owned release process.

Do not describe a final Boot 3 release as vulnerability-free. This is the
validated cherry-picked baseline; the BOM-managed and framework-coupled
findings recorded above remain explicitly deferred to Boot 4.

## Stage: Java Consumer Tooling Alignment

Align all four deployable Java repositories before orchestration work begins:

- [x] Gradle `9.8.1`, using the same version in all four consumers and
      `service-common`.
- [x] Spotless `8.10.4`.
- [x] Checkstyle `12.3.1`.
- [x] JaCoCo `0.8.15`.
- [x] JUnit Platform `1.14.4`.
- [x] `docker/dockerfile` `1.28` frontend at the reviewed pinned digest.
- [x] Current digest for the selected Temurin Java 25 image.
- [x] PDFBox `3.0.8` in `transaction-service`.

Do not independently select Spring Boot 4, JUnit 6, or another Spring release
train in a consumer. Those remain part of the final Spring migration.

For consistency without release coupling, prefer one canary consumer followed
by the other three repositories using the same selected versions and checks.

## Stage: Orchestration Toolchain Normalization

### Objective

Establish a current and consistent toolchain before debugging chart or runtime
behavior. Coordinate duplicate declarations with `workspace`.

Review the latest compatible releases at execution time. The initial target
set from the audit is:

- Helm latest compatible `3.x` (`3.22.1` in the audit), skipping the redundant
  intermediate `3.20.2` target;
- Kubernetes tools `1.35.9` while the selected cluster line remains `1.35`;
- Kind `0.33.0`;
- Tilt `0.37.8`;
- yq `4.54.1`;
- kubeconform `0.8.0`;
- Calico `3.32.2` or `3.33.0`, selected from its Kubernetes compatibility data;
- Trivy `0.76.0`;
- the current reviewed Renovate `44.x`; and
- current same-major Playwright where used by orchestration diagnostics.

Checklist:

- [x] Update complete supported-architecture checksum tables together with each
      checksum-coupled version.
- [x] Verify every downloaded tool and image continues to support Linux ARM64.
- [x] Keep matching workspace tool declarations aligned in a separately
      reviewed workspace change.
- [x] Pin eligible GitHub Action references to reviewed commit SHAs.
- [x] Retain the repository's stated Node-24-ready Action majors unless the
      shared Actions baseline is deliberately changed first.
- [x] Run the repository configuration, checksum, shell, and static guardrails.

### Execution record

On 2026-10-18, this stage was re-applied after the current-generation platform
refresh had been started out of order. The platform-refresh edits were
preserved while the prerequisite toolchain was normalized to Helm `3.22.1`,
Kubernetes tools `1.35.9`, Kind `0.33.0`, Tilt `0.37.8`, yq `4.54.1`,
kubeconform `0.8.0`, Calico `3.33.0`, Trivy `0.76.0`, Renovate `44.167.1`, and
Playwright `1.64.1`. Helm remained on major 3.

The orchestration checksum table now covers Linux and macOS on amd64 and arm64
for every checksum-coupled tool. The retained DinD test image was corrected to
verify the Kind download as well as kubectl, Helm, and Tilt. The matching
workspace Linux amd64/arm64 manifest, URLs, checksums, validation patterns,
tests, documentation, and Renovate workflow pin were updated together.

Upstream release assets prove arm64 availability for the selected binary tools
and Trivy. Calico `3.33.0` explicitly tests Kubernetes `1.35`, and every image
referenced by its manifest publishes a Linux arm64 platform. Playwright's
supported Linux matrix includes Ubuntu on arm64.

Validation completed with ShellCheck and Bash syntax for every changed shell
file, actionlint for the affected workflows, strict Renovate configuration
validation in both repositories, all 48 workspace native tests, the workspace
14-artifact release-input checksum verifier, the orchestration static security
suite, and the offline production-reference verifier. Workspace's full local
Renovate dry run completed with all 18 dependencies extracted. Orchestration's
full local run extracted all 110 dependencies but its registry lookup ended
with external-host exit `7` after repeated unauthenticated Quay API timeouts;
the strict configuration validation and deterministic repository guardrails
passed independently.

Do not select Helm 4 merely because Renovate reports it. Helm 4 is a separate
major migration and receives its own decision gate later in this plan.

## Stage: Current-Generation Platform Refresh

**Status:** Complete

### Objective

Remove stale patches and digests without yet changing the major architecture.
This produces a clean baseline from which later Helm-generation failures can be
attributed.

Initial audited targets include:

- Kind node/Kubernetes `1.35.8` on the existing Kubernetes 1.35 line;
- PostgreSQL 16 and Redis 7 current-tag digest refreshes;
- selected Java, Python 3.12, Ubuntu 22.04, Alpine, BusyBox, curl, NGINX,
  Swagger UI, Jaeger, Grafana, Prometheus, and scanner same-line updates;
- cert-manager `1.20.4`;
- Kyverno chart `3.8.2`;
- Istio charts `1.29.9`; and
- kube-prometheus-stack `83.4.3`.

Checklist:

- [x] Review release notes and exact image/platform manifests before accepting
      a floating-tag digest refresh.
- [x] Preserve immutable digests and the executable pinning inventories.
- [x] Preserve the PostgreSQL and Redis PVC-backed StatefulSet contracts and
      validate both workloads from a clean deployment.
- [x] Recreate the disposable local cluster when that gives cleaner evidence
      than carrying live drift.
- [x] Run the aggregate local smoke test after the stage.
- [x] Re-render and verify the offline production reference.

### Execution record

The source-side refresh selects Kind node/Kubernetes `1.35.8`, cert-manager
`1.20.4`, Kyverno chart `3.8.2`, Istio charts `1.29.9`, and
kube-prometheus-stack `83.4.3`. It also refreshes the same supported image lines
for Temurin Java 25, PostgreSQL 16, Redis 7, Python 3.12, Ubuntu 22.04, Alpine
3.22, BusyBox, curl, NGINX, Swagger UI, Jaeger 2, Grafana 12, and Prometheus 3.
All checked-in image references remain digest-pinned, the image inventories
accept the refreshed set, and active owner documentation names the selected
baselines.

The changed shell files pass Bash syntax and ShellCheck. The pinned-PyYAML
static security suite passes, including the Kyverno `3.8.2` render and all 80
policy fixture assertions. The provider-neutral production-reference verifier
also passes. Upstream comparison confirms that kube-prometheus-stack `83.4.3`
retains Prometheus Operator `v0.90.1` and does not change the operator RBAC
baseline. Istio `1.29.9` publishes Linux ARM64 artifacts and includes security
fixes relevant to method-based authorization and egress enforcement.

The workspace system-tool refresh initially exposed an installer defect: its
preflight rejected every non-equal managed version, so an explicitly reviewed
upgrade could not reach the existing checksum-verified overwrite path. The
workspace provisioner now replaces older managed releases, retains equal
releases, and rejects installed releases newer than the reviewed manifest. Its
release downloads also have visible progress, bounded timeouts, and bounded
retries after a GitHub Kind download otherwise waited indefinitely. The focused
provisioner tests and the complete 48-test workspace native suite pass.

The human-owned native preparation then completed. A fresh read-only runtime
preflight verified the complete workspace runtime contract and exact local
target. The supported setup path recreated Kind from checked-in state, Tilt
started the complete stack successfully, and PostgreSQL and Redis reached their
intended Ready state with their PVC-backed StatefulSet contracts intact. This
clean-rebuild acceptance intentionally reset disposable local data and does not
claim an in-place data migration or preservation across cluster recreation;
stateful generation migrations remain later work.

The aggregate local smoke test passed. Its first run exposed one stale verifier
assumption after the Jaeger refresh: Jaeger's versioned query API now serves the
services response under `/jaeger/api/v3/services`, while the stable operator UI
remains `/jaeger`. The focused port-forward verifier and operator helper were
updated without changing the Jaeger base path, Kubernetes services, Kiali
integration, or public routing. Bash syntax, ShellCheck, the focused
observability verifier, and the complete aggregate smoke test then passed.

Intermediate chart patches in this stage are intentional diagnostic baselines.
They do not obligate a second intermediate update when a later direct target is
already known to be compatible.

## Stage: Helm Family Migrations

### Shared chart rule

For every chart family:

1. select the chart version from upstream compatibility and release evidence;
2. render the chart without repository image overrides;
3. identify the exact image names, tags, and workload topology selected by that
   chart;
4. update repository-owned values and image overrides to those intended chart
   images;
5. resolve and verify immutable digests for each supported architecture;
6. compare CRDs, RBAC, security contexts, selectors, persistence, services,
   and deprecated values; and
7. validate both local behavior and the offline production reference where the
   chart participates in each surface.

Never approve chart-image digest proposals independently merely because they
appear as separate Dashboard checkboxes. A digest-only update must still name
the image intended by the selected chart.

### Gateway API and Istio

Treat Gateway API and Istio as one compatibility decision, while keeping their
source changes reviewable:

- [ ] Select Gateway API `1.6.3` or the latest version supported by the chosen
      Istio and Kubernetes lines.
- [ ] Upgrade `base`, `cni`, `gateway`, and `istiod` together, initially from
      Istio `1.29.x` to `1.30.x`.
- [ ] Review CRD and Gateway API conversion/deprecation notes.
- [ ] Verify ingress identity, TLS termination, `ext_authz`, route ownership,
      header sanitization, auth/API rate limiting, egress `REGISTRY_ONLY`, mTLS,
      and tracing.
- [ ] Confirm the production reference renders the same intended control-plane
      and gateway contracts with only documented local/production differences.

### Kyverno

- [ ] Select the Kyverno chart generation, initially `3.9.x` after the current
      `3.8.x` baseline is clean.
- [ ] Render the chart and derive the intended admission, background, cleanup,
      reports, CLI, pre-upgrade, and readiness-checker images from it.
- [ ] Update all Kyverno image overrides and digests as one chart-compatible
      change.
- [ ] Review CRDs, webhook behavior, failure policy, namespace exclusions,
      cleanup behavior, and policy-report changes.
- [ ] Re-run image-pinning, policy, runtime-security, and production-reference
      guardrails.

Do not merge the seven standalone Kyverno digest proposals as unrelated image
maintenance.

### Prometheus stack and Grafana

Use two deliberate checkpoints because the chart-generation jump is large:

- [ ] Establish a clean `83.4.x` patch baseline.
- [ ] Evaluate `83.7.x` versus the latest reviewed chart major, `92.x` in the
      audit, using upstream upgrade notes and rendered diffs.
- [ ] Select one target rather than mechanically applying every offered chart
      version.
- [ ] Derive Prometheus Operator and config-reloader image versions from the
      selected chart and update them together.
- [ ] Review Prometheus, Grafana, kube-state-metrics, CRDs, RBAC, selectors,
      retention, storage, scrape configuration, and repository post-rendering.
- [ ] Re-prove the Prometheus Operator least-privilege model rather than
      accepting upstream broad RBAC.
- [ ] Keep all observability services internal-only.

Grafana 13 is not automatically required by a newer stack chart. Accept it only
when the selected chart requires it or its migration benefit is explicitly
approved.

### Kiali

- [ ] Upgrade the Kiali chart and `quay.io/kiali/kiali` application image as one
      compatible set, initially toward the current `2.x` release.
- [ ] Preserve standalone Kiali, token authentication, namespace-scoped RBAC,
      ClusterIP-only exposure, and loopback-only guest publication.
- [ ] Validate the local UI/API access proof and deterministic offline render.

### cert-manager

- [ ] Establish the latest selected `1.20.x` patch.
- [ ] Review the `1.21.x` CRD and upgrade notes before selecting `1.21.x`.
- [ ] Compare installed and rendered CRDs before applying a live-local change.
- [ ] Do not use this work to generate, rotate, or replace browser-trusted
      certificates.

### external-secrets

- [ ] Treat the `2.2.x` to current `2.x` move as a separate production-reference
      migration.
- [ ] Validate values, CRDs, RBAC, image policy, and offline rendering.
- [ ] Do not describe the result as live production proof; no production
      environment is configured.

## Stage: Kubernetes, Runtime, and Stateful Generations

### Kubernetes decision gate

After the chart families are green on Kubernetes 1.35:

- [ ] Decide whether the pre-Boot-4 baseline should remain on the fully patched
      1.35 line or move to the latest supported Kubernetes minor.
- [ ] If moving beyond 1.35, review each skipped minor's API removals and the
      compatibility ranges for Kind, Calico, Gateway API, Istio, Kyverno,
      cert-manager, and the monitoring stack.
- [ ] Because the local Kind cluster is disposable, a direct recreation may be
      selected, but manifest/API review must still cover intervening removals.
- [ ] Align kubectl/tool versions and workspace declarations with the selected
      cluster line.
- [ ] Re-run the complete local and offline-reference proof after recreation.

Kubernetes `1.37` is therefore a deliberate platform decision, not an automatic
Dashboard approval.

### Stateless runtime images

Review and update supported runtime lines such as:

- NGINX `1.31.x`;
- Jaeger current compatible `2.x`;
- Prometheus current compatible `3.x`;
- Swagger UI current compatible `5.x`;
- Alpine, BusyBox, curl, and test-helper images; and
- the selected JRE image digest.

Prefer the latest compatible target rather than first merging an intermediate
minor, unless the intermediate is needed to isolate a migration failure.

### Stateful workloads

Handle each stateful major independently:

- [ ] Migrate RabbitMQ 3.13 to the selected RabbitMQ 4 release because support
      lifecycle makes this substantive work rather than cosmetic churn.
- [ ] Prove definitions, users/permissions, queues/exchanges, TLS, persistence,
      restart, and application messaging compatibility.
- [ ] Decide separately whether PostgreSQL 18 provides enough benefit over the
      still-supported PostgreSQL 16 line to justify data-format and restore work.
- [ ] Decide separately whether Redis 8 provides enough benefit over the
      selected Redis 7 line to justify persistence and client-compatibility work.

PostgreSQL 18 and Redis 8 are not Spring Boot 4 prerequisites. If deferred,
record the selected supported line and review date instead of treating their
Dashboard entries as forgotten work.

### Helm 4 decision gate

Evaluate Helm 4 only after all selected Helm 3 chart migrations and renders are
stable. Require a concrete benefit, plugin/script compatibility review, full
checksum refresh, and complete local/offline rendering proof. Helm 4 is not a
prerequisite for Spring Boot 4.

## Stage: Remaining Repository Modernization

This work may proceed alongside orchestration when it does not interfere with
shared local-platform validation.

### `budget-analyzer-web`

Security-first updates:

- [ ] Align `react-router` and `react-router-dom` on a fixed current `7.x`
      release.
- [ ] Upgrade PostCSS to a fixed release.
- [ ] Upgrade Vite to a fixed release.
- [ ] Upgrade Vitest, UI, and coverage as a matching fixed family.
- [ ] Upgrade TypeScript-ESLint to a fixed compatible release.
- [ ] Complete the Tailwind 4 migration if the Tailwind 3 closure cannot be
      remediated without it.

Then review the remaining frontend majors by compatible family: Node, React
and types, TypeScript, ESLint/plugins, Vite/plugin-react, testing libraries,
MSW, TanStack, Motion, and UI utilities. Require the locked build, lint,
coverage, production-smoke CSP proof, and browser harness appropriate to each
change.

Recreate intentionally closed security PRs from the Dashboard when their fixes
remain outstanding; do not assume a closed Renovate PR means the finding was
resolved.

### `ext-authz`

- [ ] Upgrade `github.com/redis/go-redis/v9` to at least `9.7.3` and verify the
      CVE-2025-29923 finding is gone.
- [ ] Move the builder to a currently supported Go line, initially Go 1.27 in
      the audit snapshot.
- [ ] Update the pinned `govulncheck` CLI.
- [ ] Run tests, build the ARM64-compatible image, and review reachable
      `govulncheck` evidence.

### `workspace`

- [ ] Align Kubernetes, Helm 3, Kind, Tilt, Go, and Playwright declarations with
      the versions selected by orchestration and their documented ownership.
- [ ] Update Claude Code, Codex, and Gemini CLI pins in bounded batches, not one
      release at a time, unless a security or required compatibility fix makes
      an immediate update necessary.
- [ ] Preserve complete URL/checksum/architecture coupling and native evidence.
- [ ] Keep host isolation, trust, Docker selection, and personal-host policy in
      the workspace-owned boundary.

### `budget-analyzer-api-tests`

- [ ] Update the pinned `uv` tool and regenerate the lock only through the
      repository-owned workflow.
- [ ] Review all bounded PEP 621 direct dependencies.
- [ ] Perform lock maintenance and prove exact parity among the lock selection,
      installed inventory, audit records, and SBOM.
- [ ] Keep Python 3.12 unless a supported-runtime review or concrete capability
      justifies the Python 3.15 migration.
- [ ] Pin eligible Actions to reviewed commit SHAs while retaining the selected
      approved action majors.

## Stage: Pre-Boot-4 System Checkpoint

Do not start Spring Boot 4 until the selected orchestration scope has a stable,
reproducible checkpoint.

Required evidence:

- [ ] A fresh local Kind/Tilt environment can be recreated from checked-in state.
- [ ] Every pod reaches the intended Ready state without manual live drift.
- [ ] Full application smoke, edge authorization, rate limiting, routing,
      egress, session, browser hardening, monitoring, tracing, Kiali, and
      persistence checks pass as applicable.
- [ ] NGINX configuration validation and route fallthrough checks pass.
- [ ] Static security, image pinning, and production-reference guardrails pass.
- [ ] The provider-neutral production reference renders without cloud
      configuration, credentials, kubeconfig, or cluster access.
- [ ] Every changed third-party image is immutable, inventoried, and verified
      for Linux ARM64.
- [ ] Local and production-reference differences remain intentional and
      documented.
- [ ] Workspace declarations and orchestration selections agree.
- [ ] Scanner findings are resolved or carry an explicit applicability and
      deferral record.
- [ ] The human records the repository SHAs that make up this pre-Boot-4
      checkpoint and creates any desired tags/releases.

## Stage: Spring Boot 4 Migration

### Entry gate

Start only after:

- the final Boot 3 `service-common` and consumer releases exist;
- the selected orchestration/Helm work is complete and green;
- the pre-Boot-4 checkpoint is reproducible; and
- no unrelated infrastructure migration is knowingly in flight.

### Release-train selection

Select a mutually compatible set from current upstream matrices rather than
accepting each latest major independently. The audit indicates the expected
families are:

- Spring Boot current stable `4.x`;
- Spring Cloud `2025.1.x` for Boot 4.0/4.1 compatibility;
- matching Spring Modulith `2.x`;
- Springdoc `3.x`;
- Spring Framework `7.x` managed by the selected Boot BOM;
- Spring Security `7.x` managed by the selected Boot BOM; and
- JUnit 6 and related test-platform updates where required by the selected Boot
  release.

Inspect the selected BOM rather than assuming the major upgrade resolves every
alert. At the audit snapshot, Boot 4 managed fixed Spring Framework and Netty
versions but still selected Tomcat `11.0.24`, while the listed new Tomcat
advisories required `11.0.25`. Retain an explicit fixed Tomcat override or
select a newer Boot patch until dependency insight proves the gap is closed.

### Migration sequence

- [ ] Upgrade the `service-common` platform and libraries first.
- [ ] Resolve source, auto-configuration, Jakarta, Spring Security, test, and
      publishing changes in `service-common`.
- [ ] Publish the Boot 4 candidate locally.
- [ ] Migrate one representative servlet consumer and `session-gateway` as the
      reactive consumer canaries.
- [ ] Migrate the remaining servlet consumers.
- [ ] Run all repository builds and cross-service local validation against the
      already stabilized orchestration platform.
- [ ] Inspect every previously listed Spring, Tomcat, Netty, BeanUtils, and
      Commons Lang finding in the resolved graphs.
- [ ] Publish and tag the Boot 4 `service-common` release through the
      human-owned workflow.
- [ ] Release consumers independently after their normal checks pass.

Do not change Helm charts, Kubernetes versions, ingress behavior, or stateful
generations in the same review units as Boot 4 unless a demonstrated Boot 4
compatibility requirement leaves no narrower option.

## Deferral Record

For every proposal intentionally left open, record:

- repository and dependency family;
- current selected version/support line;
- proposed version;
- why the update is not currently appropriate;
- security and support status;
- compatibility or migration prerequisite;
- next review date; and
- evidence that the deferral does not silently hide a reachable vulnerability.

Typical valid deferrals include a still-supported stateful major, Helm 4 after
the Helm 3 chart baseline is current, an optional language/runtime major, or a
high-frequency developer tool with no needed fix. "Renovate reported too many
updates" is not by itself a valid rationale.

## Completion Criteria

This plan is complete when:

- [ ] Final Spring Boot 3 `service-common` and consumer baselines are released
      and identifiable.
- [ ] All independently fixable listed Boot 3 dependency findings are resolved.
- [ ] The Spring 6.2 residual findings have either disappeared through newer
      upstream maintenance or are resolved by the Boot 4 migration.
- [ ] Selected orchestration tools, charts, image overrides, Kubernetes/Istio
      components, runtime images, and stateful workloads are compatible,
      reproducible, and documented.
- [ ] The live local platform and offline production reference both pass their
      owned verification contracts.
- [ ] Web, Go, workspace, and Python dependency evidence is current and
      complete.
- [ ] Spring Boot 4 and its related Spring release train are deployed to the
      local architecture without infrastructure workarounds for service-owned
      defects.
- [ ] Every remaining Dashboard proposal has a conscious accept/defer decision.
- [ ] No release claim relies on untracked live-cluster drift, a security
      bypass, reduced persistence, omitted evidence, or a non-reproducible
      manual override.

## Stop Conditions

Stop the selected update and reassess when:

- a prerequisite documented by the owning repository is missing;
- an upstream compatibility matrix excludes the proposed combination;
- a required ARM64 image or release artifact is unavailable;
- a chart changes an image identity that the override strategy did not model;
- CRDs or stateful data require an unplanned irreversible migration;
- a local test would require bypassing TLS verification or generating a
  certificate from an agent process;
- a fix would require sibling service-code changes from the orchestration
  context;
- static, scanner, lock-parity, or render evidence is incomplete; or
- the only apparent path is a security relaxation, persistence downgrade,
  manual live drift, or orchestration compensation for a service defect.

Record the evidence, narrow the problem, and create a separately reviewed
decision or implementation change before continuing.
