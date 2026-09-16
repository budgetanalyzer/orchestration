# Dependency Automation Coverage

**Status:** Local preparation and Step 3 controls are complete, all nine trial
refs are published, and initial Step 4 hosted branch measurements completed.
The operator authorized the temporary-default orchestration pilot on
2026-09-14 after reconfirming disabled expansion gates and zero current Actions
spend. Ecosystem-wide activation, default-only acceptance, and benchmark
reconciliation remain pending. The orchestration pre-switch audit, Step 5.2
switch, and Step 5.3 dry run are complete. Post-run inspection found `main`
unprotected because the active ruleset contains a malformed combined branch
pattern; the administrator repaired it, and both refs now independently receive
all three intended rules with unchanged SHAs. Renovate-only Community
installation is complete for orchestration in Scan and Alert mode, and
Dependency Dashboard #55 is active. Representative routine PR #56 has the
correct trial base, one-file patch, successful applicable check, and explicit
no-automerge behavior. The operator reported no issue in the requested Mend
cycle/queue/lookup review, and Step 5 proposal controls passed. The public Step
6.1 audit found all eight remaining repositories initially missing protection.
The serialized `service-common` batch now has dual-branch protection, a trial
default, two operator-reported green Mend cycles, accepted 222-package graph
submission, 89 graph-backed alerts, and passing representative PR #57. All
seven remaining B1 onboarding results are green and the four Java consumer
graphs are accepted with complete internal-package coverage. B4 is paused
before execution: the first onboarding cycles opened five frontend and one Go
security PR, exposing that vulnerability alerts ignore the top-level PR limits.
The shared preset now prepares a dedicated three-PR vulnerability budget for
publication before the seven second cycles. Scheduled and upload-size evidence
remains pending.

**Last updated:** 2026-09-16 (B1–B3 evidence recorded; pre-B4 security-PR burst
paused execution; nested vulnerability limit prepared; prior local and hosted
evidence retained)

This report records observed extraction and lookup behavior. It is not a list
of desired dependency versions. The preserved
[dependency review](dependency-update-review-2026-09-06.md) remains the
historical acceptance benchmark, and
[Dependency Automation](../dependency-automation.md) owns operating policy.

## Phase 12 branch rehearsal handoff

Follow the [revised operator plan](../plans/dependency-automation-phase-12-operator-plan.md)
for the remaining hosted trial. The operator selected a bounded trial and
reported that neither GitHub nor Mend has a payment method. GitHub documents that
over-quota Actions use is blocked without a valid payment method, establishing a
zero-spend boundary. All nine trial refs are now published, initial branch
measurement runs completed, and default-only App, schedule, and alert checks
remain deferred.

Public metadata for the initial branch runs records successful frontend audit,
Go vulnerability, orchestration/workspace image, Java build, and generation-only
graph jobs, with no uploaded artifacts. Those publication-triggered runs
overlapped across repositories, contrary to the one-job-at-a-time trial rule.
The overlap is a retained process deviation; successful jobs will not be rerun
solely to alter their timing. Remaining human-dispatched Actions work stays
serialized, while non-triggering administration uses the operator plan's Batch
A.
The operator reconfirmed disabled orchestration cache, schedule, and upload gates
and zero current Actions spend before authorizing the Step 5 temporary-default
orchestration pilot. Upload sizing remains pending, so uploads remain off.
The operator subsequently reported that orchestration has no repository
rulesets or classic branch-protection rules. The absence removes default-target
migration risk but initially left the trial ref unprotected. The operator then
activated `dependency-automation-trial-protection`, intending to cover both
`main` and the trial ref, block deletion and force pushes, and require pull
requests without unavailable status checks. The pre-switch review incorrectly
accepted the malformed combined target as effective. The operator confirmed
that Renovate/Mend had no
access to orchestration before the switch. Public refs then still showed `main`
as default at `dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5` and the protected trial at
`24ffc8e36bf87a730bb6a25961059becbdb67d72`; the pre-switch audit is complete.
The human then changed only the orchestration default to the protected trial
branch. Credential-free verification at `2026-09-14T14:28Z` confirmed the new
default/trial SHA and unchanged `main` SHA, zero open PRs and issues, and no
post-switch workflow or visible bot activity. The newest visible Actions run
remained pre-switch run `34848193973`. The unauthenticated artifact API was rate
limited during this check; because no post-switch workflow ran, there was no new
run capable of uploading an artifact, but a direct artifact inventory is not
claimed.
Manual-dispatch run
[34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322)
then passed on the exact trial/default SHA. Its strict validation and hosted
dry-run jobs succeeded sequentially in 2 minutes 27 seconds; hard gates establish
the matching preset ref, exact trial base, mutation simulation, repository
result `done`, and no `ERROR`/`FATAL` records. Both upload paths skipped and the
run artifact count was zero. Existing Aqua Security and Docker Hub lookup gaps
remain unresolved.

Post-run public API inspection found a ruleset defect: the initial include
conditions were `~DEFAULT_BRANCH` and one malformed combined literal. The first
remediation split the condition but retained quotes, yielding
`refs/heads/"main"` and `refs/heads/"dependency-automation-trial"`. Those values
still match neither branch. The trial receives the three intended rules only as
the current default, while `main` receives no active rule. Both SHAs remain
unchanged. Remove the literal quotes and verify both branches before installing
Mend.
The administrator then saved unquoted patterns. Verification at
`2026-09-14T15:00:04Z` found exact `refs/heads/main` and
`refs/heads/dependency-automation-trial` conditions and all three rules on both
branches. Both SHAs, the successful run list, and zero-open-PR state remained
unchanged; the Step 5.4 protection blocker is cleared.
The operator then installed Renovate-only Mend Community in Scan and Alert mode
for orchestration only and reports graph/alerts enabled with competing Dependabot
update PRs disabled. Renovate opened
[Dependency Dashboard #55](https://github.com/budgetanalyzer/orchestration/issues/55)
with 95 approval-gated and 75 schedule-gated entries. No PR, branch, commit, or
Actions run accompanied onboarding.
The operator then selected only routine proposal `renovate/renovate-44.66.x`.
[PR #56](https://github.com/budgetanalyzer/orchestration/pull/56) opened at
`2026-09-14T15:13:39Z` into `dependency-automation-trial` from head
`a12888e1d19309eb79bde14d06f673e4ab683479`. Its one-commit, one-file diff
changes only the workflow's Renovate pin from `44.65.5` to `44.66.1`.
[Run 34860772186](https://github.com/budgetanalyzer/orchestration/actions/runs/34860772186)
passed the applicable config validation in 37 seconds overall, correctly skipped
the manual-only hosted dry run, and uploaded no artifact. The PR body explicitly
reports automerge disabled by config. Public refs and the dashboard show no
second Renovate PR or branch. The operator reviewed both Mend cycles and
reported no issue in the requested status, queueing, timeout, rate-limit,
authentication, or lookup fields; exact portal timestamps/durations were not
transcribed. Dashboard/config review confirmed routine schedule/limits,
approval-gated sensitive categories, maintained-line and flavor-preserving
digest proposals, and no first-party image proposal. No live
vulnerability-fix PR was available, so graph-backed alert behavior remains Step
6 evidence.

The subsequent public Step 6.1 audit found all eight remaining repositories
still on `main`, with zero open PRs, clean local checkouts whose main/trial SHAs
match public refs, and explicit trial-preset references. Trial refs are two or
three commits ahead and zero behind. No repository has a ruleset or classic
branch protection on either ref, so protection was the next prerequisite. Trial
schedules, uploads, graph submissions, and optional caches remain gated off;
default changes do not trigger the observed release/snapshot workflows. The
initial expansion therefore began with `service-common` after protecting both
refs and confirming its administrator-only integration state.

That `service-common` batch is now complete through its manual acceptance
surface. Active ruleset `23413311` independently protects `main` and
`dependency-automation-trial`; the human switched only the default and public
checks preserved main at `f31557761b80f17ce8fadc128e273b21b4fd07fe` and the
trial/default at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94`. Mend onboarding
created [Dashboard #56](https://github.com/budgetanalyzer/service-common/issues/56)
without a PR burst. Its public content proves Gradle/catalog/wrapper/Actions and
explicit trial-preset discovery with no visible config warning; the operator
reported both the onboarding cycle and a post-graph manual cycle green. The
operator canceled one pending scheduled Mend job before expansion to preserve
serialization; that canceled cycle is retained but does not count as a success.

The first attempt of manual dependency-submission
[run 34937981854](https://github.com/budgetanalyzer/service-common/actions/runs/34937981854)
preserved a real prerequisite failure: complete dependency resolution passed,
but GitHub rejected submission because Dependency graph was disabled. The
Gradle action automatically uploaded failure artifact `10383564434` (7,444
bytes; expiry `2026-12-14T06:40:17Z`) even though the repo-owned upload step was
off. After the human enabled Dependency graph and Dependabot alerts while
leaving competing Dependabot update PRs disabled, attempt 2 passed on the exact
trial/default SHA. GitHub's accepted SBOM contains 222 packages and the operator
reported 89 graph-backed alerts. The repo-owned upload paths remained skipped;
do not classify the run itself as zero-artifact because the attempt-1 diagnostic
remains attached.

The second green Mend cycle created no automatic vulnerability-fix PR. The
operator then selected only routine Gradle `9.5.0` to `9.5.1`.
[PR #57](https://github.com/budgetanalyzer/service-common/pull/57) targets the
trial default, has one commit and one changed wrapper-properties line, and
states automerge is disabled. Its
[build 34940825035](https://github.com/budgetanalyzer/service-common/actions/runs/34940825035)
passed in 2 minutes 13 seconds with trial cache disabled, all upload steps
skipped, and zero artifacts. Keep PR #57 open. Batch A now configures all seven
remaining repositories together; cron and detailed upload-size acceptance
remain pending.

The operator checklist was simplified after the `service-common` batch exposed
that per-repository conversational handoffs do not scale. The remaining seven
repositories now use one non-triggering setup batch followed by one agent
verification checkpoint, then one Mend/graph activation batch. Mend's Community
organization concurrency remains one job, and human-dispatched GitHub graph
workflows remain sequential within the batch. This changes coordination, not
the credential, no-merge, no-upload, no-schedule, or zero-spend boundaries.

The 2026-09-16 Batch A public checkpoint passed after correcting one malformed
`transaction-service` branch target, activating the prepared `session-gateway`
ruleset, and switching the `ext-authz` default. All seven repositories retain
their recorded `main` and trial SHAs, advertise the trial ref as default, and
have an active no-bypass ruleset with exact default, `main`, and trial targets
and only deletion, non-fast-forward, and pull-request rules. Their dependency
graph SBOM endpoints and exact trial-preset references resolve, with no open
issues or pull requests and no new repository-defined workflow. GitHub
automatically ran successful `ext-authz` graph updates for the old and new
defaults while graph/default settings changed; these were platform-generated
`dynamic` events rather than operator-dispatched workflows.

Batch B App expansion then reached `transaction-service`. Its first Renovate
cycle reported `no-result` for `org.budgetanalyzer:spring-platform`,
`org.budgetanalyzer:service-core`, and `org.budgetanalyzer:service-web` in
`gradle/libs.versions.toml`. This is preserved as evidence that Mend's
installation token did not satisfy the authenticated GitHub Packages Maven
lookup; it is not evidence that the published coordinates are absent. The
operator reports storing the previously retained package-read PAT in Mend and
configuring an organization-level Renovate Maven host rule for only
`https://maven.pkg.github.com/budgetanalyzer/service-common/`, using the PAT
owner's GitHub username. No secret value or username is recorded here. The
durable repository correction and post-merge scan result are recorded below.
All seven B1 green onboarding outcomes still need confirmation before B2.

### Internal Maven routing correction

All four Java consumers previously declared Maven Local, the authenticated
`service-common` GitHub Packages repository, and an unrestricted Maven Central
repository. The durable correction preserves that order and excludes
`org.budgetanalyzer` from Maven Central, so internal coordinates resolve only
from Maven Local or GitHub Packages. It deliberately does not use Gradle
`exclusiveContent`, which would prevent the intended Maven Local fallback. No
dependency version, credential, Renovate configuration, workflow, or
`service-common` artifact changed.

The correction was merged into each `main` branch and then forward into the
protected trial branch:

| Repository | `main` pull request and resulting SHA | Trial pull request and resulting SHA |
| --- | --- | --- |
| `orchestration` | [#59](https://github.com/budgetanalyzer/orchestration/pull/59) — `57089578957bae3da42587a7e2902727c5473149` | [#60](https://github.com/budgetanalyzer/orchestration/pull/60) — `dab623ea7517e12cf9d08d8ea570529e745ecd3a` |
| `currency-service` | [#85](https://github.com/budgetanalyzer/currency-service/pull/85) — `aa432316849c9231389f8a844325dcf0d64f7335` | [#86](https://github.com/budgetanalyzer/currency-service/pull/86) — `93da3e3599e71cfa453ed78d41691fdfd1edadc3` |
| `permission-service` | [#21](https://github.com/budgetanalyzer/permission-service/pull/21) — `f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1` | [#22](https://github.com/budgetanalyzer/permission-service/pull/22) — `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` |
| `transaction-service` | [#85](https://github.com/budgetanalyzer/transaction-service/pull/85) — `ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a` | [#86](https://github.com/budgetanalyzer/transaction-service/pull/86) — `aa439d27aec63031ab056d4f4afe70cc43e13cca` |
| `session-gateway` | [#26](https://github.com/budgetanalyzer/session-gateway/pull/26) — `a37c7a0bb832b857d3d7371e521ac82e99fc3b93` | [#27](https://github.com/budgetanalyzer/session-gateway/pull/27) — `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` |

Local validation passed `clean spotlessApply`, `clean build`, and
`git diff --check` in all four consumers. The operator subsequently ran the
required post-merge `currency-service` Renovate scan and reported that it
succeeded with no warnings. No raw Mend log or separate per-coordinate result
was supplied, so this records the sanitized operator report without claiming
independent inspection of the scan transcript. The routing-fix checkpoint is
complete; the operator subsequently confirmed all seven B1 onboarding outcomes
green.

### Batch B graph and security-PR checkpoint

The first B2 graph pass exposed a control-scope error rather than a dependency
failure. The operator had created the trial control names as repository secrets,
but the workflows intentionally read non-sensitive controls from the `vars`
context. [`currency-service` run 35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407)
submitted successfully after its graph control was corrected. The first
`permission-service`, `transaction-service`, and `session-gateway` runs stayed
in generation-only mode while still passing their package-access and build
checks. Those non-submitting runs were
[`permission-service` 35083948086](https://github.com/budgetanalyzer/permission-service/actions/runs/35083948086),
[`transaction-service` 35084259266](https://github.com/budgetanalyzer/transaction-service/actions/runs/35084259266), and
[`session-gateway` 35084554215](https://github.com/budgetanalyzer/session-gateway/actions/runs/35084554215).
A second
[`permission-service` diagnostic run 35085536053](https://github.com/budgetanalyzer/permission-service/actions/runs/35085536053)
also remained generation-only and made the mistaken scope explicit. These
successful generation-only runs are retained and are not counted as accepted
submissions.

After the operator created the required repository variables, replacement runs
passed sequentially on the exact trial/default SHAs:

| Repository | Accepted run | Trial SHA | Accepted SBOM packages | Open alerts |
| --- | --- | --- | ---: | ---: |
| `currency-service` | [35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407) | `93da3e3599e71cfa453ed78d41691fdfd1edadc3` | 314 | 108 |
| `permission-service` | [35091521154](https://github.com/budgetanalyzer/permission-service/actions/runs/35091521154) | `a31e7c5880a3d3e742e7224297e8226d9e7a47ff` | 236 | 54 |
| `transaction-service` | [35091855229](https://github.com/budgetanalyzer/transaction-service/actions/runs/35091855229) | `aa439d27aec63031ab056d4f4afe70cc43e13cca` | 238 | 54 |
| `session-gateway` | [35092673426](https://github.com/budgetanalyzer/session-gateway/actions/runs/35092673426) | `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5` | 241 | 78 |

Public SBOM inspection found `org.budgetanalyzer:spring-platform`,
`org.budgetanalyzer:service-core`, and `org.budgetanalyzer:service-web` where
applicable in all four consumer graphs. The graphs also expose Spring Framework
6.2.18 and Jackson Databind 2.21.2 throughout; the servlet services include
Tomcat 10.1.54, while `session-gateway` contains WebFlux, Reactor Netty/Netty,
and Lettuce with no Tomcat package. Every accepted run used `workflow_dispatch`
on `dependency-automation-trial`, completed successfully, skipped the repo-owned
upload paths, and has zero artifacts. The operator also ran
[`service-common` 35092182970](https://github.com/budgetanalyzer/service-common/actions/runs/35092182970),
which reconfirmed its existing 222-package graph and 89 alerts with zero
artifacts. That refresh was not required by B2 and must not be repeated for this
batch.

Before B4, public inspection found six automatic vulnerability-fix PRs created
during the initial onboarding cycles. `budget-analyzer-web` opened
[#116](https://github.com/budgetanalyzer/budget-analyzer-web/pull/116),
[#117](https://github.com/budgetanalyzer/budget-analyzer-web/pull/117),
[#118](https://github.com/budgetanalyzer/budget-analyzer-web/pull/118),
[#119](https://github.com/budgetanalyzer/budget-analyzer-web/pull/119), and
[#120](https://github.com/budgetanalyzer/budget-analyzer-web/pull/120), while
`ext-authz` opened [#1](https://github.com/budgetanalyzer/ext-authz/pull/1).
All six target `dependency-automation-trial`, carry the `security` label, and
have GitHub auto-merge disabled. The five-PR frontend burst crossed the plan's
three-PR stop threshold.

This is a shared-policy defect, not evidence that the top-level routine limit
failed. Renovate vulnerability-alert PRs ignore top-level
`branchConcurrentLimit`, `commitHourlyLimit`, `prConcurrentLimit`,
`prHourlyLimit`, and schedule by default. Their default dedicated concurrent
limit is zero, meaning unlimited. The shared preset correction adds
`vulnerabilityAlerts.prConcurrentLimit: 3`, retaining an unrestricted security
schedule and `automerge: false` while giving vulnerability fixes a separate
three-PR budget. It does not close the six existing PRs. Publish and validate
the corrected trial preset before B4, preserve those PRs open and unmerged, and
use them as the baseline for the seven second cycles.

The executable
[trial-ref and ignore remediation plan](../plans/dependency-automation-trial-ref-and-ignore-remediation-plan.md)
owns the completed local preset-reference and generated-state ignore corrections.
The reviewed trial refs are published; keep them recoverable and frozen during
each evidence batch.
Record source/default refs, main SHAs, actual artifact bytes and retention, cache
use, billing observations, and detailed report evidence alongside existing
deferred checks. Report trial acceptance, ongoing installation, and benchmark
parity separately. A paused successful trial does not mean ongoing activation.

## Phase 1 pilot evidence

Renovate `44.65.5` was initially run under Node `24.13.0` and rerun under the
workspace baseline Node `24.20.0` against a plain copy of the checkout. The
unpublished shared preset and repository configuration were merged in memory,
repository config discovery was suppressed, and local platform dry-run mode
was used with debug logging. This avoids resolving the not-yet-published GitHub
preset and includes newly created, untracked files.

The final extraction rerun found 98 occurrences in 34 package files:

| Manager | Files | Occurrences | Evidence |
| --- | ---: | ---: | --- |
| Dockerfile | 1 | 1 | `nginx/Dockerfile.prod-smoke-assets` -> `alpine` |
| GitHub Actions | 3 | 11 | Both existing workflows plus the new validator workflow; checkout, setup-node, Node input, and runner identities were recognized. |
| Helm values | 2 | 13 | Kyverno digest overrides and five kube-prometheus-stack image identities were recognized. |
| Kubernetes | 11 | 29 | Stateful infrastructure, Jaeger, service init images, gateway images, local first-party images, and Kubernetes API kinds were recognized. |
| Regex | 17 | 44 | Shell/Tilt chart pins, tool releases, Kind, Kiali, inline Temurin, probe images, Playwright, and the Renovate validator were recognized. |

Three of the GitHub Actions occurrences come from the manual hosted-dry-run job
and repeat already-covered runner, setup-node, and Node identities; they do not
add a new dependency surface.

The first lookup run completed in about 34 seconds and reported 57 distinct
dependency records, 31 outdated records, and 104 candidate branches before
routine limits and dashboard approvals. Live lookups succeeded for all six
configured Helm repositories, npm, and most container registries. The final
rerun completed lookup and returned 101 candidate branches, with the expected
missing-GitHub-token warning and an anonymous Docker token warning. Registry
lookup failures are retained below instead of being presented as a clean scan.

Renovate's documented local platform supports `extract` and `lookup`, not a
true `full` dry run. Passing `--dry-run=full` falls back to lookup behavior.
Therefore extraction and live lookup are demonstrated locally, but branch-file
mutation and the published preset resolution still require a no-write hosted
observation after publication. No GitHub token was available in this worker,
by design, so GitHub-backed identities were extracted with
`github-token-required` and were not looked up. Those lookups are deferred to
the user-triggered Phase 12 job, which receives its ephemeral read-only token
inside GitHub Actions.

## Phase 2 exact-image evidence

With generated `tmp/` output excluded, a Node 24 Renovate `44.65.5` extraction
rerun against the locally merged repository configuration found 108 occurrences
across 36 manager package-file records (34 distinct paths): two Dockerfile, 19
GitHub Actions, 13 Helm-values, 29 Kubernetes, and 45 regex-managed occurrences.
The same command against the pre-remediation snapshot also found 108
occurrences. This measured rerun supersedes the earlier 104-occurrence, 35-file
count, which did not reproduce.

The workflow now contributes six native GitHub Actions occurrences: checkout,
the pinned Trivy setup action, the pinned Trivy CLI input, two artifact-upload
references, and the runner identity. `mikefarah/yq` moved from one native
GitHub Actions occurrence to one `github-releases` occurrence in
`scripts/lib/pinned-tool-versions.sh`; no yq Actions occurrence remains. Its
version and complete platform checksum table remain coupled through the verified
tool contract.

The verified installer supplied Helm, kubectl, and yq `v4.53.6` for a local
offline rerun of the workflow's exact render, extraction, and target-manifest
steps. It produced the unchanged 32 distinct image/platform targets from
checked-in sources: 28 scannable production/controller refs for `linux/arm64`,
three local-only refs for `linux/amd64`, and the Istio gateway chart's unresolved
`image: auto` marker for `linux/arm64`. The workflow scans each registry ref only
after resolving the platform child digest. The `auto` marker is explicitly
unscannable without the live Istio injector, so the workflow retains it as a
known gap without turning that expected limitation into a scan error. Unexpected
render, resolution, database, and Trivy failures do fail. The render included
controller hooks, the cert-manager solver argument, the Prometheus
config-reloader argument, and all five explicit monitoring image overrides;
first-party Budget Analyzer refs remained excluded.

The previous hosted exact-image job was rejected before step execution because
the organization Actions policy did not authorize the `mikefarah/yq` action
source. That job is distinct from the Dependency Automation Configuration
workflow started by the same branch push. Local remediation does not establish
hosted admission: a replacement exact-image run, source revision, and sanitized
outcome remain pending.

Representative scans used Trivy `0.74.0` with vulnerability DB version 2,
updated `2026-09-06 07:00:11 UTC`. These observed artifact digests are evidence
for this run, not desired-version inputs:

| Baseline item | Exact platform artifact and inventory evidence | Advisory comparison |
| --- | --- | --- |
| Redis | The checked-in index selected `redis@sha256:d6550289...` for ARM64. Trivy identified Alpine 3.21.7 and 17 OS packages, but did not identify the Redis server binary/version; the only Go binary inventory was `gosu`. | `GHSA-c8h9-259x-jff4` is **missing** because the affected Redis application was not inventoried. The scan cannot prove Redis 7.4.8 or remediation. |
| Tilt Temurin base | The checked-in index selected `eclipse-temurin@sha256:609c3d51...` for AMD64. Trivy identified Alpine 3.23.4 and 44 OS packages but no OpenJDK/Temurin/JDK package or application component. | The review's JDK 25.0.3+9 observation is **missing** from scanner evidence. A successful Alpine scan does not establish the Java CPU level. |
| External Secrets | The rendered mutable tag resolved through index `sha256:876e627d...` to ARM64 artifact `ghcr.io/external-secrets/external-secrets@sha256:c2649798...`. Trivy found Debian 13.4, five OS packages, and 377 Go packages, but the primary module had an empty version. | `GHSA-r2pg-r6h7-crf3` and `GHSA-wv26-88m5-6h59` are **missing**. The unversioned primary module prevents a supported affected-version match. |
| Kyverno | The checked-in index selected `reg.kyverno.io/kyverno/kyverno@sha256:875beb24...` for ARM64. Trivy found the primary Go module as `v1.18.0+dirty`. | `GHSA-79gf-7frw-68m9` is **reproduced** as `CVE-2026-54523`; the GHSA URL is retained in the finding references and the fixed version is 1.18.2. |
| Prometheus | The checked-in index selected `quay.io/prometheus/prometheus@sha256:65acbbb6...` for ARM64. The image exposed no OS metadata, but Trivy inventoried the Go module as 3.11.1. | Stored XSS `GHSA-vffh-x6r8-xx99` is **reproduced** as `CVE-2026-40179`. Remote-read DoS `GHSA-8rm2-7qqf-34qm` is **missing** from this scan. |

The missing rows remain acceptance gaps, not clean results or false positives.
Raw inventories, vulnerability JSON, resolver manifests, stderr, and database
metadata are the authoritative workflow artifacts. Job summaries deliberately
separate OS-package and application-package counts and identify mutable source
refs; they do not infer embedded versions from tags.

## Orchestration extraction map

| Surface and source paths | Extracted identities | Lookup evidence or gap |
| --- | --- | --- |
| Production chart contract: `deploy/scripts/lib/version-contract.sh` | `base`, `external-secrets`, `cert-manager`, `kyverno`, `kube-prometheus-stack`, `kiali-server`; real Helm repository URL attached to each | All six repositories returned release metadata. Istio showed maintained-line and 1.30 proposals; later lines were also visible for the other charts. Every chart proposal is approval-gated. |
| Local chart commands: `Tiltfile` | Istio `base`, `cni`, `istiod`, and `gateway`; `kyverno`, `kube-prometheus-stack`, `kiali-server` | Lookups succeeded and repeated declarations resolve to the same datasource identities without native-manager duplication. Istio declarations are grouped per repository. |
| Production platform releases: `deploy/scripts/lib/version-contract.sh` | `k3s-io/k3s`, `kubernetes-sigs/gateway-api` | Extracted, including the literal `v` prefix and K3s `+k3sN` build component. Authenticated lookup is deferred to the Phase 12 hosted job. `PHASE4_POD_SECURITY_VERSION` is intentionally not extracted. |
| Checksum-coupled tools: `scripts/lib/pinned-tool-versions.sh` | `kubernetes/kubernetes`, `helm/helm`, `tilt-dev/tilt`, `FiloSottile/mkcert`, `kubernetes-sigs/kind`, `yannh/kubeconform`, `stackrox/kube-linter`, `kyverno/kyverno`, `mikefarah/yq`, `kubernetes-sigs/gateway-api`, `projectcalico/calico` | All identities extracted; Tilt's absent `v` and Kyverno CLI's release prefix are explicit. Authenticated lookup is deferred to the Phase 12 hosted job. Proposals are approval-gated and state that Renovate cannot regenerate the checksum table. |
| Kind node: `kind-cluster-config.yaml` | `kindest/node:v1.35.0` plus its current digest | Docker lookup succeeded and exposed separate 1.35, 1.36, and 1.37 lines. Platform/ARM64 review is approval-gated. The stale setup-flow Kind image is excluded. |
| Stateful services: `kubernetes/infrastructure/{postgresql,rabbitmq,redis}/statefulset.yaml` and annotated probe scripts listed in `scripts/lib/image-pinning-targets.txt` | `postgres:16-alpine`, `rabbitmq:3.13-management`, `redis:7-alpine`, plus exact digests | Redis lookup exposed a maintained broad-tag digest refresh and Redis 8; RabbitMQ exposed RabbitMQ 4. PostgreSQL lookup timed out in the pilot. All are approval-gated. Broad tags do not identify the embedded Redis/PostgreSQL patch, so Redis 7.4.11 parity is **missing** until a separately reviewed explicit alias or image inventory proves it. |
| Edge and utility images: service manifests, `nginx/Dockerfile.prod-smoke-assets`, and annotated smoke scripts | `nginxinc/nginx-unprivileged`, `swaggerapi/swagger-ui`, `busybox`, `alpine`, `curlimages/curl`, `mendhak/http-https-echo`, `python` | Lookups exposed later NGINX maintained/minor lines, Swagger UI lines, and updates for the probe images. Exact digest refreshes were resolved. Repeated probe refs share identities. |
| Runtime JDK: inline Dockerfile in `Tiltfile` | `eclipse-temurin:25-jre-alpine` plus digest | Digest lookup succeeded, but the broad tag exposes only digest movement and not the embedded JDK patch. JDK patch/support parity is an explicit **gap** pending image inventory/scanning. |
| Jaeger: `kubernetes/monitoring/jaeger/deployment.yaml` | `cr.jaegertracing.io/jaegertracing/jaeger:2.17.0` plus digest | Lookup exposed 2.18, 2.19, and 2.20 lines. The matching literal in `scripts/guardrails/verify-production-image-overlay.sh` remains an intentional validation companion; Renovate does not silently rewrite that assertion. |
| Monitoring image overrides: `kubernetes/monitoring/prometheus-stack-values.yaml` | `docker.io/grafana/grafana`, `registry.k8s.io/kube-state-metrics/kube-state-metrics`, `quay.io/prometheus/prometheus`, and both Prometheus Operator images | Native Helm-values extraction found all five tags. Kube-state-metrics, Prometheus, and Operator lookups produced later lines; Grafana and config-reloader had registry timeouts on repeat validation. The chart's nonstandard `sha` fields are not associated with tags by the native manager, so complete tag-plus-digest mutation is an explicit **gap** and must fail review until handled as a companion change. |
| Kiali override: `kubernetes/monitoring/kiali-values.yaml` | `quay.io/kiali/kiali:v2.24.0` plus digest | Nonstandard keys are covered by an adjacent regex annotation. Lookup was not completed because the repeat run stopped on registry host errors; chart lookup did succeed. |
| Production controller overrides: `deploy/helm-values/{cert-manager,external-secrets,kyverno}.values.yaml` | Seven Kyverno image repositories/digests; cert-manager and External Secrets are chart-only | Kyverno's digest-only structure was extracted but lacks a trustworthy tag and must not be refreshed from `latest`; all chart-value image proposals are approval-gated. Cert-manager and External Secrets omit repository/tag keys, so native image extraction cannot identify them. Rendering and exact-image scanning must close this **gap** in the later security-evidence phase. |
| GitHub Actions: `.github/workflows/*.yml` | `actions/checkout`, `actions/setup-node`, Node 24, `renovate`, and the exact-image workflow's Trivy setup/CLI and artifact upload inputs | Extraction succeeded, including all scanner inputs. yq is now extracted only as a checksum-coupled GitHub release tool, not an action. Authenticated lookups are deferred to the Phase 12 hosted job. All workflows retain `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true`; runner labels are not update targets. |
| Temporary Playwright runner: `scripts/ops/grafana-ui-playwright-debug.sh` | `@playwright/test` | npm lookup succeeded. Generated runner directories remain excluded. |
| First-party local and production images | Seven approved local repositories; synchronized GHCR production artifacts under `kubernetes/production/apps` | Local names are extracted by Kubernetes but disabled by package policy. Production promotion paths are excluded so Renovate cannot desynchronize the release-owned manifest, inventory, overlays, or metadata. |

## Coverage contract status

| Baseline area implemented in orchestration | Update discovery | Security/support evidence |
| --- | --- | --- |
| Redis, PostgreSQL, RabbitMQ, NGINX, Temurin, Jaeger, Swagger UI, and other deployed third-party images | Demonstrated except the noted PostgreSQL/Grafana/config-reloader/Kiali retry gaps. Both maintained and later lines appeared where the tag encoded a version. | Exact platform scan path implemented. Representative Redis and Temurin scans retained their missing primary-application metadata instead of inferring patch levels. The remaining images are targets in the weekly/manual workflow. |
| External Secrets, Kyverno, cert-manager, Istio, kube-prometheus-stack, and Kiali charts | Demonstrated against each real chart name and repository. | Offline exact-image path implemented for rendered controllers and hooks. Kyverno advisory parity was reproduced; External Secrets advisories remain missing, and the Istio gateway `auto` image remains explicitly unscannable offline. |
| Prometheus, Grafana, Prometheus Operator, and kube-state-metrics overrides | All identities extracted; most lookups demonstrated. | All five overrides are workflow targets, including the rendered config-reloader argument. Representative Prometheus scanning reproduced stored XSS but missed the remote-read advisory. |
| K3s, Kind, Kubernetes tooling, Gateway API, Calico, Helm, Tilt, and pinned guardrail tools | Extraction demonstrated, including prefixes/suffixes; Kind lookup demonstrated. GitHub lookups are deferred to the Phase 12 hosted job. | Checksum and ARM64 compatibility remain human approval requirements. |
| GitHub Actions | Native extraction demonstrated, including the new workflow. | GitHub lookup and hosted workflow URL are deferred to Phase 12 after publication. |
| Lifecycle decisions for K3s/Kubernetes, Istio, RabbitMQ, NGINX, and image runtimes | Later release lines are visible for non-GitHub sources; GitHub-backed lines await authenticated lookup. | No automated EOL claim. Quarterly upstream lifecycle review remains required. |

The repository-specific preparation phases are now complete. Their local
evidence and every authenticated handoff are consolidated below. Local results
remain preparation evidence: they do not prove that the published preset
resolves, GitHub accepted a graph submission, a hosted scanner completed, or
the Mend App is active.

## Phase 12 activation evidence

The 2026-09-14 operator report and subsequent public checks establish the
bounded trial's zero-spend control, published trial refs, initial hosted branch
measurements, all nine Dependency Dashboards, five accepted Java graphs, alert
counts, and eight live bot PRs. The orchestration dry run and branch
build/scan/generation jobs are linked below. Seven consumer second cycles,
scheduled scanner runs, uploads, and final benchmark reconciliation remain
pending. B4 is paused until the nested vulnerability limit is published; no
pending row is being reclassified as a scanner limitation or a pass.

The operator must follow the ordered
[activation procedure](../dependency-automation.md#activation-procedure) and
provide public links or sanitized exports. Do not provide credentials, job
tokens, secret values, cookies, or private registry responses. Evidence should
identify the repository, source revision, UTC run time, workflow or bot-cycle
URL, tool/database version where applicable, and the final status.

### Cross-repository administrator gates

| Repository or scope | Check and configuration | Reason deferred | Operator action and required evidence | Disposition |
| --- | --- | --- | --- | --- |
| All organization repositories and 9 scoped repositories | Visibility and GitHub Actions billing/storage | All nine scoped repositories were public and used `main` at `2026-09-14T01:45:30Z`. A fully paginated unauthenticated snapshot covered all 15 publicly visible organization repositories and 1,191 historical artifact records; none was unexpired, so currently retained public artifact bytes were zero. The operator reports that private repositories exist but that the observed authenticated UI offered no practical per-artifact inventory; private retained bytes and upload headroom remain unknown. The operator also reports no GitHub payment method, and GitHub's current Actions billing documentation says over-quota usage is blocked without one. This prevents financial exposure but does not guarantee that a capped upload will succeed. | Keep uploads and schedules off initially. Measure exact output locally and runner-side, permit at most one 25 MiB bundle with one-day retention, and treat a quota rejection as failed evidence delivery. Do not add a payment method. Replace unknown private headroom with measured artifact bytes if GitHub later exposes them, and recalculate before expansion or scheduling. On 2026-09-14 the operator reconfirmed zero current Actions spend and disabled orchestration upload, cache, and schedule gates; public metadata showed zero artifacts on every listed initial branch run. | **Zero-spend control reconfirmed and initial runs retained zero artifacts — private headroom and upload sizing remain pending; uploads stay off** |
| All 9 scoped repositories | Free Mend Community support, portal profile, durability decision, and App scope | Mend's public documentation confirms that Community is free for unlimited public and private repositories, with one concurrent organization job, four-hour active scheduling, a 30-minute timeout, and hosted credential settings. The App listing says no paid plan is required. The operator reports no Mend payment method and no paid trial. Neither source promises a perpetual free tier, grandfathering, SLA, or Community helpdesk support. | The operator recorded `TRIAL GO` on `2026-09-14`, initially kept `main` default, then authorized and performed the temporary-default orchestration switch after the pre-change audit. The cap remains one 25 MiB one-day bundle and the review date remains `2026-09-21`. The discovered `main` protection defect is repaired, and the operator restricted initial App access to orchestration. Prove hosted lookup behavior before expansion. | **Bounded Community trial, orchestration switch, protection, and pilot App scope passed — hosted lookup pending** |
| Orchestration | Persistent protection for `main` and `dependency-automation-trial` during the temporary-default pilot | The operator intended active deletion, non-fast-forward, and pull-request rules on both refs. Post-run inspection found only the dynamic default target effective. The first remediation retained quoted patterns; the final saved repair uses exact unquoted refs. | Public verification at `2026-09-14T15:00:04Z` showed exact `refs/heads/main` and `refs/heads/dependency-automation-trial` conditions. Both branches independently receive deletion, non-fast-forward, and pull-request rules; both SHAs remain unchanged. Preserve the ruleset through pilot rollback. | **Passed — both branches independently protected before Step 5.4** |
| All 9 scoped repositories | Phase 12 branch workflow controls | The trial required exact branch/base triggers, trusted event/ref guards, generation-only Java graphs, disabled schedules/uploads/submissions/caches, complete output measurement, and a total upload cap before publication. | Local implementation uses the exact `dependency-automation-trial` ref, four disabled-by-default repository variables, generation-only Java graph runs until both submission gates pass, cache-controlled build/scan jobs, a shared-shape sealed-archive helper in each repo, a 24 MiB payload ceiling beneath the approved 25 MiB artifact cap, and one-day trial retention. On 2026-09-14, Node `24.20.0` strict validation passed for all nine configs and the shared preset; local extraction completed with 108, 55, 60, 48, 46, 42, 72, 24, and 18 dependency occurrences respectively in orchestration, service-common, currency-service, permission-service, transaction-service, session-gateway, budget-analyzer-web, ext-authz, and workspace. Public metadata now records successful initial branch jobs in all nine repositories with zero artifacts. The publication-triggered jobs overlapped, violating the one-job-at-a-time process rule; preserve the deviation and serialize remaining work. | **Trial refs and initial hosted branch jobs passed — detailed report review, default-only behavior, and upload sizing remain pending** |
| Orchestration, then all consumers | Shared preset publication order | Consumer `renovate.json` files resolve the explicit orchestration trial ref. | Orchestration source and preset ref `24ffc8e36bf87a730bb6a25961059becbdb67d72` resolved successfully in hosted dry-run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973); all nine trial refs are publicly resolvable. Keep the preset ref frozen during each evidence batch. | **Trial preset publication and hosted resolution passed** |
| Orchestration | `.github/workflows/dependency-automation-config.yml`, manual dispatch with `run_hosted_dry_run=true` or the trial-only marked-push fallback | Local platform mode cannot perform a true full dry run or GitHub lookups. Before the temporary-default switch, GitHub did not expose **Run workflow**, so the branch-only workflow used its reviewed one-repository wrapper. The temporary default now permits normal manual dispatch without changing that read-only execution contract. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) established 109 dependencies in 37 package files and retained the Aqua Security IP-allow-list and anonymous Docker Hub page-11 gaps. Trial-default manual run [34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322) then passed on the same exact source/preset SHA: both jobs succeeded sequentially in 2 minutes 27 seconds, all structural hard gates passed, uploads skipped, and artifact count was zero. | **Trial-default hosted mechanics passed — individual Aqua Security and Docker Hub lookup coverage remains incomplete** |
| All 9 scoped repositories | Renovate Community App, Dependency Dashboard, dependency graph, Dependabot alerts, and update-PR ownership | Installation and settings changes are administrator-owned. | Mend is now restricted to all nine selected repositories and all nine Dashboards exist. The operator reports all seven consumer onboarding jobs green after the narrowly scoped Maven correction. Five consumer graphs are accepted and graph-backed alert counts are recorded. Orchestration and `service-common` retain their representative routine PRs; six consumer vulnerability PRs use the trial base and have automerge disabled. The five-PR frontend burst exposed the missing dedicated vulnerability limit, so B4 remains paused until the corrected preset is published. | **All repositories onboarded — nested alert-limit correction and seven second cycles pending** |
| Four Java consumers | Mend App-settings GitHub Packages access | Public inspection on `2026-09-13` showed all four published `service-common` Maven packages in GitHub's public-package filter. GitHub Packages still requires authentication to install public Maven packages; agents cannot inspect or receive the existing credential. | The operator stored the existing package-read credential in Mend and configured an organization-level Maven host rule scoped only to `https://maven.pkg.github.com/budgetanalyzer/service-common/`. All four Dashboards now list their applicable internal coordinates, B1 completed green, and the accepted SBOMs independently prove package resolution in Actions. | **Authenticated hosted lookup and graph package resolution passed — credential details intentionally not retained** |
| All 9 scoped repositories | Two successful Renovate cycles and one scheduled scanner cycle | Public effects show orchestration and `service-common` onboarding plus dashboard-triggered second cycles; the operator reviewed those Mend cycles without reporting an issue, but exact private timestamps/durations were not transcribed. The seven remaining repositories have one green onboarding cycle each. | Publish the nested vulnerability limit, then request and record one second green cycle for each of the seven remaining repositories. Scheduled scanner cycles remain a later, separately authorized batch. | **Two-cycle acceptance passed for orchestration and service-common — seven B4 cycles and scheduled scans pending** |
| All 9 scoped repositories | No paid features, automerge, duplicate PR owner, or first-party production promotion | Effective hosted behavior required live App evidence. | Renovate-only Community remains the sole PR owner. The operator reports Dependabot update PRs disabled. The two representative routine PRs and six consumer security PRs all use the trial base with GitHub auto-merge disabled. The security burst is retained as evidence and does not authorize merge or paid features. | **No duplicate owner or automerge observed — B4 and remaining proposal review pending** |

### Repository deferred-check reconciliation

| Repository | Check/workflow and affected surface | Reason deferred | Operator action and expected proof | Disposition |
| --- | --- | --- | --- | --- |
| `orchestration` | Hosted Renovate full dry run for charts, release/tool pins, Actions, Docker/Helm/Kubernetes inputs, and registry retries | GitHub token, published preset, and true full-dry-run behavior are hosted-only. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) validated the trial wrapper and preset, extracted 109 dependencies from 37 package files, selected the trial base, simulated mutations, and returned `done`. Preserve the Aqua Security IP-allow-list failures and anonymous Docker Hub page-11 failures as incomplete lookups; do not classify them as a clean lookup pass. | **Hosted mechanics passed — Aqua Security and Docker Hub lookup gaps pending** |
| `orchestration` | `.github/workflows/exact-image-security-evidence.yml` for 32 rendered targets | The prior hosted job was rejected before execution because organization policy did not authorize the yq action source. The action was replaced by the checksum-verified yq CLI. | Push run [34831702464](https://github.com/budgetanalyzer/orchestration/actions/runs/34831702464) passed on source `be9ed6b936c4e35f31d58f7056b9771918bf9889`; the exact-image workflow and scan inputs are unchanged through the current trial source. It uploaded no artifact. Retain detailed findings separately and observe one scheduled run later. | **Hosted admission and no-upload measurement passed — detailed report and scheduled evidence pending** |
| `orchestration` | Dashboard/proposals and required checks | App/settings were previously inactive. | [Dashboard #55](https://github.com/budgetanalyzer/orchestration/issues/55) proves normal onboarding and surfaces maintained-line, digest, chart, platform, checksum, and major proposals under approval/schedule controls. Representative [PR #56](https://github.com/budgetanalyzer/orchestration/pull/56) targets `dependency-automation-trial`, changes only the Renovate `44.65.5` to `44.66.1` pin, passed [run 34860772186](https://github.com/budgetanalyzer/orchestration/actions/runs/34860772186), and explicitly reports automerge disabled. The operator reported both Mend cycles looked good. Keep the PR unmerged. Live vulnerability and sustained-limit behavior remain broader-trial evidence. | **Step 5 pilot passed — later scheduled/alert evidence pending** |
| `service-common` | Hosted Renovate lookup for Gradle/catalog/wrapper/Actions | Actions and published-preset lookups require hosted GitHub access. | [Dashboard #56](https://github.com/budgetanalyzer/service-common/issues/56) shows Gradle, catalog, wrapper, Actions, maintained Spring-line and Spring 4/test-stack proposals, plus the explicit trial preset, with no visible config warning. The operator reported onboarding and post-graph cycles green. | **Passed for dashboard discovery — private log details not transcribed** |
| `service-common` | `.github/workflows/dependency-submission.yml` | The complete 216-coordinate local snapshot was not submitted. | Trial push run [34823856894](https://github.com/budgetanalyzer/service-common/actions/runs/34823856894) passed generation-only mode. Manual [run 34937981854](https://github.com/budgetanalyzer/service-common/actions/runs/34937981854) attempt 1 exposed disabled Dependency graph and automatically retained 7,444-byte artifact `10383564434` through `2026-12-14`; after enablement, attempt 2 submitted successfully at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94`. GitHub's accepted SBOM has 222 packages. | **Accepted complete graph passed — scheduled submission pending** |
| `service-common` | Representative bot PR `build.yml`, graph/alerts, and dashboard | No App, PR, or administrator evidence was previously available. | The operator reported 89 graph-backed Dependabot alerts. Representative [PR #57](https://github.com/budgetanalyzer/service-common/pull/57) targets the trial default, changes only Gradle `9.5.0` to `9.5.1`, states automerge is disabled, and passed [build 34940825035](https://github.com/budgetanalyzer/service-common/actions/runs/34940825035) with cache and uploads off. No second PR or security-fix PR appeared. | **Manual rehearsal passed — scheduled and live vulnerability-fix PR evidence pending** |
| `currency-service` | Hosted Renovate lookup for 57 extracted records, including internal `org.budgetanalyzer` coordinates and Actions | Authenticated Maven and GitHub lookups were intentionally unavailable locally. | The post-routing-fix scan was operator-reported green with no warnings, and Dashboard #84 lists the applicable internal packages through the explicit trial preset. | **Hosted internal Maven lookup passed by sanitized operator report and Dashboard evidence — second cycle pending** |
| `currency-service` | `.github/workflows/dependency-submission.yml` | Local output had only 87 build/tool coordinates because `serviceCommon` 0.0.16 could not resolve. | Manual [run 35083509407](https://github.com/budgetanalyzer/currency-service/actions/runs/35083509407) passed at `93da3e3599e71cfa453ed78d41691fdfd1edadc3`. GitHub's accepted SBOM has 314 packages, including all applicable internal coordinates; the operator reported 108 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `currency-service` | Representative bot PR `build.yml`, graph/alerts, and settings | Historical ordinary build `34027551741` predates submission automation and is insufficient. | Retain a current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — current evidence not supplied** |
| `permission-service` | Hosted Renovate lookup for 45 extracted records, including three internal coordinates and Actions | Authenticated Maven and GitHub lookups were deferred. | The operator reported green B1 onboarding, and Dashboard #20 lists all three internal packages through the explicit trial preset. | **Hosted internal Maven lookup passed by operator report and Dashboard evidence — second cycle pending** |
| `permission-service` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted internal and application runtime/test trees. | After correcting the secret/variable scope, manual [run 35091521154](https://github.com/budgetanalyzer/permission-service/actions/runs/35091521154) passed at `a31e7c5880a3d3e742e7224297e8226d9e7a47ff`. GitHub's accepted SBOM has 236 packages and all three internal coordinates; the operator reported 54 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `permission-service` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `transaction-service` | Hosted Renovate lookup for 43 extracted records, including three internal coordinates and Actions | The first onboarding cycle returned `no-result` before the scoped Mend credential and Maven routing correction. | The operator reported a post-correction green B1 result, and Dashboard #84 lists all three internal packages through the explicit trial preset. | **Hosted internal Maven lookup passed after correction — second cycle pending** |
| `transaction-service` | `.github/workflows/dependency-submission.yml` | Local 91-coordinate graph omitted internal, PostgreSQL, and Testcontainers trees. | After correcting the secret/variable scope, manual [run 35091855229](https://github.com/budgetanalyzer/transaction-service/actions/runs/35091855229) passed at `aa439d27aec63031ab056d4f4afe70cc43e13cca`. GitHub's accepted SBOM has 238 packages and all three internal coordinates; the operator reported 54 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete graph passed — detailed advisory mapping and scheduled submission pending** |
| `transaction-service` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `session-gateway` | Hosted Renovate lookup for 39 extracted records, including internal coordinates, Actions, and images | Authenticated Maven and GitHub lookups were deferred. | The operator reported green B1 onboarding, and Dashboard #25 lists its internal packages through the explicit trial preset. | **Hosted internal Maven lookup passed by operator report and Dashboard evidence — second cycle pending** |
| `session-gateway` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted the reactive application tree after a GitHub Packages HTTP 401. | After correcting the secret/variable scope, manual [run 35092673426](https://github.com/budgetanalyzer/session-gateway/actions/runs/35092673426) passed at `8f8b8c30aa3008f870879ab623a0b6ef8ee04ec5`. GitHub's accepted SBOM has 241 packages and all three internal coordinates; the operator reported 78 alerts. Uploads skipped and the run has zero artifacts. | **Accepted complete reactive graph passed — detailed advisory mapping and scheduled submission pending** |
| `session-gateway` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `budget-analyzer-web` | Hosted Renovate lookup for 65 npm/lockfile/Dockerfile/Actions records | Actions and published preset were hosted-only; local Docker token acquisition repeatedly failed for Node and NGINX. | Retain App logs/dashboard proving npm, lockfile, Node, NGINX, Actions, and setup-node lookups succeed and both maintained and toolchain-major proposals remain visible. | **Pending — Docker/GitHub retries unproved** |
| `budget-analyzer-web` | `.github/workflows/dependency-audit.yml` | Local audits reproduced findings, but hosted install/registry/audit execution was unobserved. | Trial push run [34823959669](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/34823959669) passed at `2cbef3f17f546fe167628b221a1cb9dec810c2bd` with uploads disabled. Retain/reconcile the detailed reports before claiming finding parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed report and scheduled evidence pending** |
| `budget-analyzer-web` | Representative bot PR `build.yml`, graph/alerts, and settings | Onboarding opened five vulnerability PRs before the planned representative routine proposal. | Security PRs #116–#120 all target the trial branch, carry the security label, and have auto-merge disabled, but their count exceeded the trial stop threshold. Preserve them and publish the nested three-PR vulnerability limit before B4 or Batch C. | **Live vulnerability path proved but concurrency acceptance failed — correction and representative routine PR pending** |
| `ext-authz` | Hosted Renovate lookup for 21 Go/Dockerfile/Actions/scanner records | GitHub lookups and the Go builder Docker lookup were incomplete locally. | Retain App logs/dashboard proving preset, Actions, Go input, `golang:1.24-alpine`, modules, and scanner lookups succeed. | **Pending — Go builder/GitHub retries unproved** |
| `ext-authz` | `.github/workflows/go-vulnerability-check.yml` | Local `govulncheck` reproduced GO-2025-3540, but the hosted scanner/database path was unobserved. | Trial push run [34823939945](https://github.com/budgetanalyzer/ext-authz/actions/runs/34823939945) passed at `75ed2bda4de7460332a8dea656def0459064753f` with uploads disabled. Retain/reconcile the detailed finding before claiming advisory parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed finding and scheduled evidence pending** |
| `ext-authz` | Representative bot PR `build.yml`, graph/alerts, and settings | Onboarding opened a vulnerability PR before the planned representative routine proposal. | Security PR #1 targets the trial branch, carries the security label, and has auto-merge disabled. Preserve it as the one-PR baseline; after the nested limit is published, at most two additional vulnerability PRs may open. | **Live vulnerability path and no-automerge passed — second cycle and representative routine PR pending** |
| `workspace` | Hosted Renovate lookup for 16 Dockerfile/ARG/download/Actions records | Published preset and GitHub release lookups are hosted-only. | Retain App logs/dashboard proving every identity resolves, Ubuntu 24.04 updates preserve digest-only syntax, maintained Go line and majors remain visible, and checksum proposals remain approval-gated. | **Pending — no hosted lookup** |
| `workspace` | `.github/workflows/workspace-image-security-evidence.yml`, cost, and public downloads | The no-cache build may consume substantial Actions time; hosted download/build/scan paths were previously unobserved. | Trial push run [34823984859](https://github.com/budgetanalyzer/workspace/actions/runs/34823984859) passed at `d8e384474512eafb827970db8194413764b79098` in about six minutes with uploads and optional caches disabled. Retain/review the detailed inventory and scan report before claiming parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed report, upload sizing, and scheduled evidence pending** |
| `workspace` | Graph/alerts, dashboard, and settings | Administrator settings are not visible locally. | Retain sanitized settings, dashboard/proposal and alert evidence, including explicit unversioned apt/npm/PyPI, VIA, Go amd64-only, and lifecycle limitations. | **Pending — no hosted evidence** |

## Benchmark comparison status

The user-applied workspace Node 24 rebuild is baseline context, not a Renovate
finding or bot-applied update. The active container reported Node `24.20.0`
during Phases 1–10. The historical review is unchanged; its SHA-256 is
`3c0c4075e021884227d5ecbd0861a9c4f18471e184b8fbbf8cecc1ac8014c347`.

The categories below describe preparation evidence only. Final Phase 12
dispositions require hosted URLs/artifacts and must use `reproduced`,
`superseded`, `false positive with evidence`, or `missing`.

| Baseline area | Local preparation evidence | Phase 12 disposition |
| --- | --- | --- |
| Spring Boot, Cloud, Modulith, SpringDoc, Testcontainers, and other Java dependencies | Native extraction exists in all five Java repos. GitHub now has accepted complete graphs for `service-common` and all four consumers, including internal packages and the expected servlet/reactive runtime split. | **Accepted graph coverage passed; pending** per-advisory alert mapping, maintained-line proposals, and Spring 4 migration visibility across the B4 Dashboards. |
| Frontend direct/transitive packages and toolchain majors | Renovate extracted npm/lockfile inputs; both local audits reproduced the benchmark's 20 full-tree and four production findings by package identity. | **Pending** hosted audit, alerts, dashboard, maintained patches, later majors, and bot PR checks. |
| `go-redis` and Go runtime | Local Renovate lookup found go-redis 9.7.3 and later v9 lines; local govulncheck reproduced reachable GO-2025-3540. | **Pending** hosted scanner/database evidence, alerts, Go builder lookup, and Go lifecycle migration proposal. |
| Deployed third-party images | Extraction and an exact-platform scan path exist. Redis and Temurin primary versions were not inventoried; some registry retries failed. | **Pending** full hosted image artifact and proposals; Redis, Temurin, and PostgreSQL patch parity is not established. |
| External Secrets, Kyverno, cert-manager, Istio, kube-prometheus-stack, and Kiali | Chart extraction succeeded. Representative scans reproduced Kyverno but missed both External Secrets advisories; Istio gateway `image: auto` remains offline-unscannable. | **Pending** hosted rendered scan and dashboard. Current missing advisories remain prominently unresolved. |
| Prometheus, Grafana, Operator, and kube-state-metrics | Overrides were extracted; representative Prometheus scan reproduced stored XSS but missed remote-read DoS. Grafana/config-reloader lookups timed out. | **Pending** hosted lookup/scan evidence and alert comparison. |
| K3s, Kind, Kubernetes tools, Gateway API, Calico, Helm, Tilt, and pinned tools | Extraction succeeded and Kind lookup showed maintained/later lines; GitHub-backed lookups were deferred. | **Pending** hosted lookup, checksum-complete proposals, and ARM64 review evidence. |
| Workspace base image, Node/Go/Zulu, and installed packages | Local no-cache build and Trivy scan identified Node, Zulu, and Go; Ubuntu digest-only update behavior was extracted. Unversioned installs, VIA, and Go amd64-only remain gaps. | **Pending** zero-spend approval and complete hosted build/scan. Node 24 is prerequisite context, not bot discovery. |
| EOL decisions | Some later release lines appeared locally. | **Pending** dashboard evidence and quarterly human lifecycle review; automation is not an EOL authority. |

### Named high-priority advisory reconciliation

| Advisory | Affected area | Local preparation evidence | Final disposition |
| --- | --- | --- | --- |
| `GHSA-c8h9-259x-jff4` | Redis 7.4.8 | Redis binary/version absent from Trivy inventory. | **Missing; hosted evidence pending** |
| `GHSA-7m2p-62gw-p8qq` | Spring Framework 6.2.18 | Accepted graphs expose Spring 6.2.18 in all four consumers; aggregate alert counts are recorded. | **Pending per-advisory alert mapping** |
| `GHSA-5m62-pw8w-7w9f` | Tomcat 10.1.54 | Accepted servlet-service graphs expose Tomcat 10.1.54; `session-gateway` correctly has no Tomcat package. | **Pending per-advisory alert mapping and applicability review** |
| `GHSA-9xv2-5v5q-p794` | Tomcat 10.1.54 | Accepted servlet-service graphs expose Tomcat 10.1.54; `session-gateway` correctly has no Tomcat package. | **Pending per-advisory alert mapping and applicability review** |
| `GHSA-38f8-5428-x5cv` | Netty 4.1.132 | The accepted `session-gateway` graph exposes Reactor Netty/Netty 4.1.132 and Lettuce. | **Pending per-advisory alert mapping** |
| `GHSA-8c42-7qj2-3j46` | Netty 4.1.132 | The accepted `session-gateway` graph exposes Reactor Netty/Netty 4.1.132 and Lettuce. | **Pending per-advisory alert mapping** |
| `GHSA-j3rv-43j4-c7qm` | Jackson 2.21.2 | Accepted graphs expose Jackson Databind 2.21.2 in all four consumers; aggregate alert counts are recorded. | **Pending per-advisory alert mapping** |
| `GHSA-r2pg-r6h7-crf3` | External Secrets 2.2.0 | Primary Go module had no version in representative image inventory. | **Missing; hosted evidence pending** |
| `GHSA-wv26-88m5-6h59` | External Secrets 2.2.0 | Primary Go module had no version in representative image inventory. | **Missing; hosted evidence pending** |
| `GHSA-79gf-7frw-68m9` | Kyverno 1.18.0 | Reproduced locally as `CVE-2026-54523`; fixed version 1.18.2. | **Pending hosted reproduction/supersession proof** |
| Frontend advisory set | npm lockfile | Local full and production audits reproduced the saved package identities and counts. | **Pending hosted reports/alerts and per-advisory mapping** |
| `GO-2025-3540` | go-redis 9.7.0 | Reproduced locally with a reachable `Ping` to `initConn` call path; fixed in 9.7.3. | **Pending hosted reproduction/supersession proof** |
| `GHSA-qm8v-g4f9-qhjx` | Istio 1.29.2 | Maintained Istio updates were discoverable; checked-in configuration has no `BackendTLSPolicy`. | **Pending advisory evidence and applicability record** |
| `GHSA-vffh-x6r8-xx99` | Prometheus 3.11.1 | Reproduced locally as `CVE-2026-40179`. | **Pending hosted reproduction/supersession proof** |
| `GHSA-8rm2-7qqf-34qm` | Prometheus 3.11.1 | Not reported by the representative Trivy scan. | **Missing; hosted evidence pending** |

Redis 7.4.11, Temurin 25.0.4.1, PostgreSQL 16.15, Istio 1.29.7,
maintained Spring patches, controller updates, and later migration lines must
remain visible alongside majors in the hosted dashboard. Broad image tags and
digest-only proposals are not proof of those embedded patch versions.

## Current outcome

Ecosystem-wide installation and benchmark parity are both **not established**.
The orchestration Step 5 pilot and `service-common` rehearsal passed. All seven
remaining repositories passed Batch A and B1, and all four consumer Java graphs
are accepted with complete internal-package coverage and recorded alert counts.
The graph run exposed and corrected repository controls mistakenly entered as
secrets instead of variables. B4 is paused before its Dashboard requests because
the first onboarding cycles opened five frontend vulnerability PRs and one Go
vulnerability PR. Their bases and no-automerge state are correct, but the
frontend exceeded the trial stop threshold because Renovate's vulnerability
path ignored the top-level PR limits. Publish and validate the nested three-PR
vulnerability limit, then resume B4 against the retained six-PR baseline.
Scheduled scan cycles, Batch C, and final benchmark dispositions remain pending.
Existing local misses remain gaps; lifecycle and exploitability assessment
remain human work.
