# Dependency Automation Coverage

**Status:** Local preparation and Step 3 controls are complete, all nine trial
refs are published, and initial Step 4 hosted branch measurements completed.
The operator authorized the temporary-default orchestration pilot on
2026-09-14 after reconfirming disabled expansion gates and zero current Actions
spend. Administrator activation, default-only acceptance, and benchmark
reconciliation remain pending. The orchestration pre-switch audit, Step 5.2
switch, and Step 5.3 dry run are complete. Post-run inspection found `main`
unprotected because the active ruleset contains a malformed combined branch
pattern; repair is required before App installation.

**Last updated:** 2026-09-14 (orchestration Step 5.3 dry run and ruleset blocker;
prior local and hosted evidence retained)

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
solely to alter their timing, and all remaining trial work must be serialized.
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

Post-run public API inspection found a ruleset defect: the active include
conditions are `~DEFAULT_BRANCH` and malformed literal
`refs/heads/"main", "dependency-automation-trial"`. The trial branch receives
the three intended rules only as the current default, while `main` receives no
active rule. Both SHAs remain unchanged. Repair this to two separate explicit
branch refs and verify both receive deletion, non-fast-forward, and pull-request
rules before installing Mend.
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

The 2026-09-14 operator report and public checks establish the bounded trial's
zero-spend control, published trial refs, initial hosted branch measurements,
and current public artifact snapshot. The orchestration dry run and branch
build/scan/generation jobs are now linked below. There is still no App
installation evidence, Dependency Dashboard URL, accepted Java graph submission,
Dependabot settings or alert export, bot pull request, or scheduled scanner run.
Those default-only rows remain `pending`; none is being reclassified as a
scanner limitation or a pass.

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
| All 9 scoped repositories | Free Mend Community support, portal profile, durability decision, and App scope | Mend's public documentation confirms that Community is free for unlimited public and private repositories, with one concurrent organization job, four-hour active scheduling, a 30-minute timeout, and hosted credential settings. The App listing says no paid plan is required. The operator reports no Mend payment method and no paid trial. Neither source promises a perpetual free tier, grandfathering, SLA, or Community helpdesk support. | The operator recorded `TRIAL GO` on `2026-09-14`, initially kept `main` default, then authorized and performed the temporary-default orchestration switch after the pre-change audit. The cap remains one 25 MiB one-day bundle and the review date remains `2026-09-21`. Repair the discovered `main` protection defect before installation, then confirm restricted App scope and prove authenticated Maven lookup before expansion. | **Bounded Community trial and orchestration switch approved — protection repair, App scope, and hosted lookup pending** |
| Orchestration | Persistent protection for `main` and `dependency-automation-trial` during the temporary-default pilot | The operator intended active deletion, non-fast-forward, and pull-request rules on both refs. Post-run public API inspection showed the ruleset contains `~DEFAULT_BRANCH` plus malformed literal `refs/heads/"main", "dependency-automation-trial"`; only the current default trial ref receives rules, while `main` receives none. Both SHAs remain unchanged. | Replace the malformed combined condition with separate explicit `refs/heads/main` and `refs/heads/dependency-automation-trial` includes. Preserve all three rules. Verify both branches independently before App installation. | **Blocked — `main` protection repair required before Step 5.4** |
| All 9 scoped repositories | Phase 12 branch workflow controls | The trial required exact branch/base triggers, trusted event/ref guards, generation-only Java graphs, disabled schedules/uploads/submissions/caches, complete output measurement, and a total upload cap before publication. | Local implementation uses the exact `dependency-automation-trial` ref, four disabled-by-default repository variables, generation-only Java graph runs until both submission gates pass, cache-controlled build/scan jobs, a shared-shape sealed-archive helper in each repo, a 24 MiB payload ceiling beneath the approved 25 MiB artifact cap, and one-day trial retention. On 2026-09-14, Node `24.20.0` strict validation passed for all nine configs and the shared preset; local extraction completed with 108, 55, 60, 48, 46, 42, 72, 24, and 18 dependency occurrences respectively in orchestration, service-common, currency-service, permission-service, transaction-service, session-gateway, budget-analyzer-web, ext-authz, and workspace. Public metadata now records successful initial branch jobs in all nine repositories with zero artifacts. The publication-triggered jobs overlapped, violating the one-job-at-a-time process rule; preserve the deviation and serialize remaining work. | **Trial refs and initial hosted branch jobs passed — detailed report review, default-only behavior, and upload sizing remain pending** |
| Orchestration, then all consumers | Shared preset publication order | Consumer `renovate.json` files resolve the explicit orchestration trial ref. | Orchestration source and preset ref `24ffc8e36bf87a730bb6a25961059becbdb67d72` resolved successfully in hosted dry-run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973); all nine trial refs are publicly resolvable. Keep the preset ref frozen during each evidence batch. | **Trial preset publication and hosted resolution passed** |
| Orchestration | `.github/workflows/dependency-automation-config.yml`, manual dispatch with `run_hosted_dry_run=true` or the trial-only marked-push fallback | Local platform mode cannot perform a true full dry run or GitHub lookups. Before the temporary-default switch, GitHub did not expose **Run workflow**, so the branch-only workflow used its reviewed one-repository wrapper. The temporary default now permits normal manual dispatch without changing that read-only execution contract. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) established 109 dependencies in 37 package files and retained the Aqua Security IP-allow-list and anonymous Docker Hub page-11 gaps. Trial-default manual run [34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322) then passed on the same exact source/preset SHA: both jobs succeeded sequentially in 2 minutes 27 seconds, all structural hard gates passed, uploads skipped, and artifact count was zero. | **Trial-default hosted mechanics passed — individual Aqua Security and Docker Hub lookup coverage remains incomplete** |
| All 9 scoped repositories | Renovate Community App, Dependency Dashboard, dependency graph, Dependabot alerts, and update-PR ownership | Installation and settings changes are administrator-owned. | Install the App only on the scoped repositories, grant alert-read access, enable graph/alerts, and keep Dependabot version and security-update PRs disabled. Retain settings plus dashboard/alert URLs and prove Renovate is the sole update-PR owner with `automerge=false`. | **Pending — evidence not supplied** |
| Four Java consumers | Mend App-settings GitHub Packages access | Public inspection on `2026-09-13` showed all four published `service-common` Maven packages in GitHub's public-package filter. GitHub Packages still requires authentication to install public Maven packages; agents cannot inspect or receive the existing credential. | Reconfirm package visibility, then first test Mend's App-token GitHub Packages host rules. If a separate credential is required, store it only in Mend App settings and reference it from `hostRules` with a secret placeholder. Confirm free-App support and retain sanitized lookup logs for each consumer. | **Public visibility preflight passed — authenticated hosted lookup pending** |
| All 9 scoped repositories | Two successful Renovate cycles and one scheduled scanner cycle | Automation has not been installed or observed. | Record two successful bot cycles per repository plus one scheduled scan cycle for each prepared scanner, using a manual first scan for immediate feedback. Include timestamps, revisions, durations, dashboard/proposal links, database versions, and rate-limit/timeout results. | **Pending — evidence not supplied** |
| All 9 scoped repositories | No paid features, automerge, duplicate PR owner, or first-party production promotion | Effective hosted behavior cannot be inferred from local config alone. | Export effective config and representative proposals/checks; show no paid feature, no automatic merge, no Dependabot update PRs, successful required checks/credential access, and no Renovate edits under the release-owned first-party production paths. | **Pending — evidence not supplied** |

### Repository deferred-check reconciliation

| Repository | Check/workflow and affected surface | Reason deferred | Operator action and expected proof | Disposition |
| --- | --- | --- | --- | --- |
| `orchestration` | Hosted Renovate full dry run for charts, release/tool pins, Actions, Docker/Helm/Kubernetes inputs, and registry retries | GitHub token, published preset, and true full-dry-run behavior are hosted-only. | Marked-push run [34848193973](https://github.com/budgetanalyzer/orchestration/actions/runs/34848193973) validated the trial wrapper and preset, extracted 109 dependencies from 37 package files, selected the trial base, simulated mutations, and returned `done`. Preserve the Aqua Security IP-allow-list failures and anonymous Docker Hub page-11 failures as incomplete lookups; do not classify them as a clean lookup pass. | **Hosted mechanics passed — Aqua Security and Docker Hub lookup gaps pending** |
| `orchestration` | `.github/workflows/exact-image-security-evidence.yml` for 32 rendered targets | The prior hosted job was rejected before execution because organization policy did not authorize the yq action source. The action was replaced by the checksum-verified yq CLI. | Push run [34831702464](https://github.com/budgetanalyzer/orchestration/actions/runs/34831702464) passed on source `be9ed6b936c4e35f31d58f7056b9771918bf9889`; the exact-image workflow and scan inputs are unchanged through the current trial source. It uploaded no artifact. Retain detailed findings separately and observe one scheduled run later. | **Hosted admission and no-upload measurement passed — detailed report and scheduled evidence pending** |
| `orchestration` | Dashboard/proposals and required checks | App/settings are not active. | Retain two bot cycles, dashboard and proposal URLs, maintained-line plus major proposals, approval gates, immutable digest/flavor preservation, ARM64 review records, and successful applicable checks. | **Pending — no bot-cycle evidence** |
| `service-common` | Hosted Renovate lookup for Gradle/catalog/wrapper/Actions | Actions and published-preset lookups require hosted GitHub access. | Retain App log/dashboard evidence for all 52 locally extracted occurrences, including maintained Spring lines and Spring 4/test-stack proposals. | **Pending — no hosted lookup** |
| `service-common` | `.github/workflows/dependency-submission.yml` | The complete 216-coordinate local snapshot was not submitted. | Trial push run [34823856894](https://github.com/budgetanalyzer/service-common/actions/runs/34823856894) passed generation-only mode at `e9b91a63eccbc3e7e98528d80cbe89677d0d1f94` with no artifact. Submission and GitHub graph acceptance remain gated until the trial branch is default. | **Hosted generation passed — accepted submission pending** |
| `service-common` | Representative bot PR `build.yml`, graph/alerts, and dashboard | No App, PR, or administrator evidence is available. | Retain bot PR/check URLs and sanitized graph/alert/settings evidence; prove no automerge or overlapping Dependabot update PRs. | **Pending — no hosted evidence** |
| `currency-service` | Hosted Renovate lookup for 57 extracted records, including three `org.budgetanalyzer` coordinates and Actions | Authenticated Maven and GitHub lookups were intentionally unavailable locally. | Retain App log/dashboard evidence proving preset, Actions, and authenticated Maven lookups succeed without auth/config/timeout errors. | **Pending — no hosted lookup** |
| `currency-service` | `.github/workflows/dependency-submission.yml` | Local output had only 87 build/tool coordinates because `serviceCommon` 0.0.16 could not resolve. | Trial push run [34823893235](https://github.com/budgetanalyzer/currency-service/actions/runs/34823893235) passed generation-only mode at `e89758adfced41af4106dc9d0c7398bfdff604e8`; companion build [34823893237](https://github.com/budgetanalyzer/currency-service/actions/runs/34823893237) also passed, proving hosted package resolution. Submission, detailed graph review, and GitHub acceptance remain pending. | **Hosted build/generation passed — accepted complete graph pending** |
| `currency-service` | Representative bot PR `build.yml`, graph/alerts, and settings | Historical ordinary build `34027551741` predates submission automation and is insufficient. | Retain a current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — current evidence not supplied** |
| `permission-service` | Hosted Renovate lookup for 45 extracted records, including three internal coordinates and Actions | Authenticated Maven and GitHub lookups were deferred. | Retain App log/dashboard evidence proving preset, Actions, and authenticated Maven lookups succeed. | **Pending — no hosted lookup** |
| `permission-service` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted internal and application runtime/test trees. | Trial push run [34823913812](https://github.com/budgetanalyzer/permission-service/actions/runs/34823913812) passed generation-only mode at `3e532f87eed65fa0202e35039938f131f1c453f8`; companion build [34823913772](https://github.com/budgetanalyzer/permission-service/actions/runs/34823913772) also passed. Submission, detailed graph review, and GitHub acceptance remain pending. | **Hosted build/generation passed — accepted complete graph pending** |
| `permission-service` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `transaction-service` | Hosted Renovate lookup for 43 extracted records, including three internal coordinates and Actions | Authenticated Maven and GitHub lookups were deferred. | Retain App log/dashboard evidence proving preset, Actions, and authenticated Maven lookups succeed. | **Pending — no hosted lookup** |
| `transaction-service` | `.github/workflows/dependency-submission.yml` | Local 91-coordinate graph omitted internal, PostgreSQL, and Testcontainers trees. | Trial push run [34823873554](https://github.com/budgetanalyzer/transaction-service/actions/runs/34823873554) passed generation-only mode at `0a9de2ec5b8ea9742ad44b02c4b7148ca568c190`; companion build [34823873507](https://github.com/budgetanalyzer/transaction-service/actions/runs/34823873507) also passed. Submission, detailed graph review, and GitHub acceptance remain pending. | **Hosted build/generation passed — accepted complete graph pending** |
| `transaction-service` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `session-gateway` | Hosted Renovate lookup for 39 extracted records, including two internal coordinates, Actions, and images | Authenticated Maven and GitHub lookups were deferred. | Retain App log/dashboard evidence proving preset, Actions, authenticated Maven, and image lookups succeed. | **Pending — no hosted lookup** |
| `session-gateway` | `.github/workflows/dependency-submission.yml` | Local 87-coordinate graph omitted the reactive application tree after a GitHub Packages HTTP 401. | Trial push run [34824028238](https://github.com/budgetanalyzer/session-gateway/actions/runs/34824028238) passed generation-only mode at `fe6061562e52eccf42570265b5299439c6827c9b`; companion build [34824028192](https://github.com/budgetanalyzer/session-gateway/actions/runs/34824028192) also passed. Submission, detailed reactive graph review, and GitHub acceptance remain pending. | **Hosted build/generation passed — accepted complete graph pending** |
| `session-gateway` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted PR or administrator evidence exists. | Retain current bot PR build with package access plus accepted graph, alerts, dashboard, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
| `budget-analyzer-web` | Hosted Renovate lookup for 65 npm/lockfile/Dockerfile/Actions records | Actions and published preset were hosted-only; local Docker token acquisition repeatedly failed for Node and NGINX. | Retain App logs/dashboard proving npm, lockfile, Node, NGINX, Actions, and setup-node lookups succeed and both maintained and toolchain-major proposals remain visible. | **Pending — Docker/GitHub retries unproved** |
| `budget-analyzer-web` | `.github/workflows/dependency-audit.yml` | Local audits reproduced findings, but hosted install/registry/audit execution was unobserved. | Trial push run [34823959669](https://github.com/budgetanalyzer/budget-analyzer-web/actions/runs/34823959669) passed at `2cbef3f17f546fe167628b221a1cb9dec810c2bd` with uploads disabled. Retain/reconcile the detailed reports before claiming finding parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed report and scheduled evidence pending** |
| `budget-analyzer-web` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted bot PR or settings evidence exists. | Retain successful checks for representative lockfile maintenance and approved toolchain-major proposals, dashboard/alert URLs, and no-duplicate/no-automerge evidence. | **Pending — no hosted evidence** |
| `ext-authz` | Hosted Renovate lookup for 21 Go/Dockerfile/Actions/scanner records | GitHub lookups and the Go builder Docker lookup were incomplete locally. | Retain App logs/dashboard proving preset, Actions, Go input, `golang:1.24-alpine`, modules, and scanner lookups succeed. | **Pending — Go builder/GitHub retries unproved** |
| `ext-authz` | `.github/workflows/go-vulnerability-check.yml` | Local `govulncheck` reproduced GO-2025-3540, but the hosted scanner/database path was unobserved. | Trial push run [34823939945](https://github.com/budgetanalyzer/ext-authz/actions/runs/34823939945) passed at `75ed2bda4de7460332a8dea656def0459064753f` with uploads disabled. Retain/reconcile the detailed finding before claiming advisory parity, and observe one scheduled run later. | **Hosted no-upload measurement passed — detailed finding and scheduled evidence pending** |
| `ext-authz` | Representative bot PR `build.yml`, graph/alerts, and settings | No hosted bot PR or administrator evidence exists. | Retain successful bot PR checks, dashboard/alert URLs, and no-duplicate/no-automerge settings evidence. | **Pending — no hosted evidence** |
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
| Spring Boot, Cloud, Modulith, SpringDoc, Testcontainers, and other Java dependencies | Native extraction exists in all five Java repos. Only `service-common` produced a complete local graph; four consumer graphs were incomplete without authenticated Maven access. | **Pending** complete accepted submissions, inherited alerts, maintained-line proposals, and Spring 4 migration visibility for all five repos. |
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
| `GHSA-7m2p-62gw-p8qq` | Spring Framework 6.2.18 | Complete local `service-common` graph only; no submitted consumer graphs or alerts. | **Pending** |
| `GHSA-5m62-pw8w-7w9f` | Tomcat 10.1.54 | Same graph limitation; applicability needs service review. | **Pending** |
| `GHSA-9xv2-5v5q-p794` | Tomcat 10.1.54 | Same graph limitation; applicability needs service review. | **Pending** |
| `GHSA-38f8-5428-x5cv` | Netty 4.1.132 | Consumer reactive graph is incomplete. | **Pending** |
| `GHSA-8c42-7qj2-3j46` | Netty 4.1.132 | Consumer reactive graph is incomplete. | **Pending** |
| `GHSA-j3rv-43j4-c7qm` | Jackson 2.21.2 | No accepted graph or Dependabot alert evidence. | **Pending** |
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

Installation status and benchmark parity are both **not established**. Local
configuration and scanner preparation are complete, but automation is not
demonstrably active and no Phase 12 authenticated operational check has passed.
The operator evidence in the tables above is required before this report can
record two bot cycles, a scheduled scan cycle, accepted Java graphs, or final
benchmark dispositions. Existing local misses remain gaps; lifecycle and
exploitability assessment remain human work.
