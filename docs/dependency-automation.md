# Dependency Automation

**Status:** Trial branches and workflow controls are published, and the initial
hosted branch measurements completed under the bounded zero-spend trial. On
2026-09-14 the operator reconfirmed disabled expansion gates and zero current
Actions spend, then authorized the temporary-default orchestration pilot.
The protected `dependency-automation-trial` branch is now orchestration's
temporary default, and the Step 5.3 trial-default dry run passed. A malformed
ruleset target briefly left `main` unprotected after it ceased being default;
the target is now repaired and both refs independently receive all three rules
with their recorded SHAs unchanged. Orchestration-only administrator activation
is complete in Scan and Alert mode, and Renovate opened the Dependency Dashboard
against the trial default. Representative routine PR #56 targets the trial
default, contains only the expected Renovate patch, passed its applicable check,
and explicitly reports automerge disabled. Mend-side cycle timing, queueing, and
lookup/error-log review was operator-checked without a reported blocker. The
orchestration pilot is ready for the Step 6 per-repository pre-expansion audits;
live vulnerability-alert and sustained limit behavior remain later evidence.

This document owns the operating policy for dependency automation across the
Budget Analyzer repositories. The preserved
[September 6 dependency review](research/dependency-update-review-2026-09-06.md)
is the historical acceptance benchmark; its observed versions are not bot
targets. The executable rollout and acceptance sequence remains in the
[dependency automation plan](plans/dependency-automation-plan.md).

## Ownership and policy

Renovate is the only service allowed to open dependency update pull requests.
Dependabot remains alert-only: keep the dependency graph and Dependabot alerts
enabled, disable Dependabot version updates and overlapping Dependabot security
update pull requests, and let Renovate consume alerts when its App permission
allows that. Never enable automerge, including for security fixes.

The shared policy is
[`renovate-presets/default.json`](../renovate-presets/default.json). Repository
configuration extends it and adds only repository-specific manager paths and
extraction rules. Routine pull requests are created weekly, with no more than
three open routine pull requests and two new routine pull requests per hour in
one repository. Vulnerability fixes use Renovate's dedicated alert path and an
unrestricted schedule. Major, chart, stateful, platform, and checksum-coupled
updates require Dependency Dashboard approval.

Patch, minor, and major proposals remain distinct. Digest refreshes must retain
an immutable digest and any image flavor suffix. Reviewers must independently
verify Linux ARM64 support. An available tag or a changed digest is not evidence
of architecture support, embedded package versions, vulnerability remediation,
or upstream support status.

The following stay outside Renovate ownership:

- historical/generated outputs and the retained stale test suites
- local `:latest` and generated `:tilt-*` images listed by the image-pinning
  inventories
- first-party production images and their synchronized manifest, inventory,
  overlay, runtime metadata, and API-docs metadata
- Pod Security compatibility labels
- arbitrary per-platform checksum calculation

Renovate may propose checksum-coupled tool versions, but dashboard approval and
the existing checksum verification remain mandatory. A reviewer must update the
complete checksum table; no validation may be weakened to merge the proposal.

## Cost and service boundary

Use the open-source Renovate engine through the free Mend Renovate Community
GitHub App. Do not provision a self-hosted bot or opt into paid Merge Confidence,
enterprise scheduling, enhanced cache, a trial, or another subscription. The
selected security evidence uses GitHub's dependency graph and Dependabot alerts,
Gradle's open-source basic dependency-submission path, Trivy, `npm audit`, and
`govulncheck`.

The only new account surface expected by this rollout is a Mend Developer Portal
profile, accessed with the existing GitHub identity through OAuth. It administers
the free hosted App; it is not a paid Mend subscription. The existing GitHub
account must already have authority to install Apps and administer Actions,
security, package, and repository settings for the scoped organization. GitHub
Actions, GitHub Packages, the dependency graph, Dependabot, Trivy, `npm audit`,
`govulncheck` and the public registries and advisory databases do
not require separate new accounts for this rollout.

GitHub Actions usage is separate from Mend hosting. Standard GitHub-hosted
runners are currently free for public repositories, but artifact storage is
still limited by the GitHub plan and shares its allowance with GitHub Packages.
Public packages are currently free; private package storage and transfer have
plan allowances. Public package visibility does not remove GitHub Packages'
authentication requirement for Maven installation.

Branch runs use the same account allowances as runs on `main`. Before the first
hosted trial, record current retained artifact bytes, accrued billing usage,
the organization plan and allowance, package visibility, and effective no-spend
controls. Include existing JAR, test-result, and frontend build artifacts that
bot PRs will trigger. Actions caches have a separate allowance; inventory cache
producers and account settings separately from pooled artifact/Packages storage.
Runner-local Docker layers and scanner databases are not Actions artifacts unless
uploaded or saved as caches. The workspace scanner uploads reports and build
logs, not its built Docker image.

Missing local bundle sizes do not require merging or block a bounded measurement
run. Prepare trial workflows with schedules and uploads disabled by default. Run
the complete scan on a standard public-repository runner, measure the exact
upload paths, and report sizes in the job summary. Then permit one capped upload
at a time with one-day trial retention, within verified remaining headroom.
Enforce the cap before upload, including uploads after failure. A size-only run
does not replace retained detailed acceptance evidence. Replace estimates with
the artifact API's `size_in_bytes` before enabling further uploads or schedules.

Project storage as `sum(bytes / 2^30 * retained_hours)` GiB-hours, adding existing
accrual and expected non-trial use. Compare with the actual billing-cycle
allowance and keep headroom for retries and overlapping runs. Weekly bundles
retained seven days average approximately one bundle each; one-day trial
retention must not be used to understate the seven-day production projection.
Deletion stops future accrual, not usage already accrued. Billing views may lag.
If no payment method is present, confirm over-limit use is blocked; otherwise
require an effective spend-stopping control for every relevant billed product.
A notification-only budget is insufficient. Stop hosted work if that boundary
cannot be established; local preparation may continue.

If authenticated per-artifact inventory is unavailable, record that access gap
instead of reporting unknown private-repository bytes as zero. A confirmed
no-payment-method block establishes the zero-spend boundary, but it does not prove
that upload capacity remains. Keep initial uploads disabled, treat a quota-blocked
upload as a trial failure rather than a reason to add billing information, and
replace the unknown with measured artifact bytes only when the hosted platform
makes them available.

The operator must approve a bounded trial before any workflow-triggering
publication or App activation; accepting ongoing operation is a later decision.
Mend currently documents Community Cloud as a free tier for unlimited public
and private repositories and publishes its resource
limits. The GitHub App listing says no paid plan is required. Those statements
are current service policy, not a promise that the hosted tier will remain free
for a particular duration. The open-source Renovate engine provides a technical
fallback if hosting changes, but self-hosting is deliberately outside this
rollout and would require a new cost and operations decision. Stop for user
direction if that policy-change risk is unacceptable or if required coverage
needs spending, a trial, an account not listed above, or a capability unavailable
on the free offerings.

## Activation procedure

Configuration preparation does not authorize GitHub setting changes. A
repository administrator performs activation only after all rollout phases have
prepared and locally validated their files. Phases 1–10 require no credentials;
all authenticated validation and credential review belong to Phase 12. Agents
must never receive GitHub, package, registry, or Mend credentials, including in
Phase 12. The user performs authenticated operations in GitHub/Mend or their own
trusted environment and supplies sanitized evidence for agent review.

Missing authentication, authenticated-only API access, and unauthenticated API
rate limits are recorded as pending Phase 12 evidence; they do not block local
configuration preparation. This includes authenticated Maven resolution,
complete remotely resolved Java snapshots, graph submission, published-preset
resolution, and hosted bot/scanner runs. Local schema validation, extraction,
workflow lint, and checks that can run without credentials remain required.
Preserve actual failures and incomplete outputs; never report a deferred check
as passed or weaken a hosted job's failure behavior. Non-authentication
prerequisites and implementation defects remain blockers under the owning
repository's rules.

For each deferred check, record the repository, check/command, affected packages
or configurations, observed failure or reason not attempted, and the Phase 12
operator action and expected proof. Sibling phases keep this handoff in their
own docs and link here; Phase 12 consolidates it in the coverage report.

### Branch rehearsal before a merge decision

Keep the prepared implementation on `dependency-automation-trial` in all nine
scoped repositories. Use that exact shared name for trial refs and workflow guards.
The [Phase 12 operator plan](plans/dependency-automation-phase-12-operator-plan.md)
owns the checklist, required workflow adaptations, trial limits, and rollback.
This planning change does not perform branch operations or activate anything.

GitHub schedules run only on the repository's default branch. New manual
workflows normally need default-branch registration; selecting a ref does not
make a branch-only workflow automatically discoverable. Renovate normally reads
its repository config from the default branch. Shared presets can use an explicit
Git ref, so preset publication itself does not require a merge to `main`.

There are two acceptance modes:

- Keep `main` as default: use explicitly scoped branch push/PR triggers for
  hosted build, scan, size-measurement, and read-only Renovate checks. Actual
  default-branch scheduling, normal Mend onboarding, and alert integration remain
  pending unless separately demonstrated through supported hosted configuration.
  Do not claim full activation from these results.
- With explicit operator agreement, temporarily make the protected trial branch
  the default, first in orchestration and then in consumers. This permits normal
  Mend onboarding, scheduled jobs, and default-branch dependency-graph/alert
  acceptance without moving `main`. Audit repository-wide default-branch effects
  first. Pause the App before restoring defaults and making the merge decision.

The second mode is a real installation in the existing repositories, not an
isolated account sandbox. App permissions, issues, PRs, alerts, artifacts,
caches, and billing are repository/account state. Default-branch changes affect
new PR bases, applicable rulesets, schedules, and integrations. Neither mode
authorizes dependency merges, package publication, releases, or deployment.

On 2026-09-14 the operator selected this temporary-default mode for the
orchestration pilot after confirming that the trial cache, schedule, and upload
gates remained off and current GitHub Actions spend remained zero. This approval
does not itself authorize an agent to change repository settings. Complete the
operator plan's pre-change audit, preserve `main` protection, and have the human
administrator make and verify the bounded default-branch change.

The 2026-09-14 orchestration pre-change audit found no existing repository
rulesets or classic branch-protection rules. There is therefore no dynamic
default-branch rule that would move away from `main`, but the trial ref does not
initially satisfy the protected-branch prerequisite. The human administrator
then created `dependency-automation-trial-protection`, intending to protect both
`main` and `dependency-automation-trial` with deletion and force pushes blocked
and pull requests required without unavailable status checks. The pre-switch
review incorrectly accepted the configured target as equivalent protection;
the post-run API audit below exposed the malformed target condition.

The operator also confirmed that Renovate/Mend had no access to orchestration
before the default-branch switch. The human administrator then changed only the
default branch to `dependency-automation-trial`. Credential-free verification
at `2026-09-14T14:28Z` found the advertised default and trial head unchanged at
`24ffc8e36bf87a730bb6a25961059becbdb67d72`, with `main` unchanged at
`dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5`. Open pull requests and issues
remained zero, and the newest visible Actions run was still the pre-switch run
`34848193973` from `2026-09-14T13:16:09Z`; the switch therefore triggered no
workflow or artifact-producing run. The unauthenticated artifact API was rate
limited during this check, so direct post-switch artifact inventory remains an
access gap rather than a claimed zero-byte snapshot.

Manual-dispatch run
[34857399322](https://github.com/budgetanalyzer/orchestration/actions/runs/34857399322)
then passed at source `24ffc8e36bf87a730bb6a25961059becbdb67d72` while
the trial branch was the public default. Strict config validation and the hosted
full dry-run job both passed; the workflow's hard gates prove that the exact
trial source/preset ref matched, the trial base was selected, mutation
simulation occurred, the repository result was `done`, and no `ERROR` or
`FATAL` record was emitted. The two jobs ran sequentially, total duration was
2 minutes 27 seconds, both upload paths were skipped, and the run artifact count
was zero. Existing Aqua Security and Docker Hub lookup gaps are not resolved by
this public metadata and remain pending.

The same post-run public API inspection exposed a protection defect. Active
ruleset `dependency-automation-trial-protection` initially included
`~DEFAULT_BRANCH` and one malformed combined literal branch pattern. The first
remediation attempt split that value but retained literal quotes, producing
`refs/heads/"main"` and `refs/heads/"dependency-automation-trial"`. Neither
explicit pattern matches; consequently the current default trial branch receives
the deletion, non-fast-forward, and pull-request rules only through
`~DEFAULT_BRANCH`, while `main` receives no active rule. Both SHAs remain
unchanged. App installation must wait until the administrator removes the quote
characters so the API reports exact `refs/heads/main` and
`refs/heads/dependency-automation-trial` conditions and public checks show all
three rules on both branches.

The administrator saved the corrected unquoted patterns at
`2026-09-14T14:59:43Z`. Credential-free verification at
`2026-09-14T15:00:04Z` confirmed exact conditions `refs/heads/main` and
`refs/heads/dependency-automation-trial`; both branches independently receive
the deletion, non-fast-forward, and pull-request rules. `main` remains at
`dc8f8ecd91f3d1cfbc3c187bb8d59b293370a7e5`, the trial/default remains at
`24ffc8e36bf87a730bb6a25961059becbdb67d72`, open pull requests remain zero,
and no new workflow was triggered. The Step 5.4 protection prerequisite is now
satisfied.

The operator then installed the Renovate-only Mend Community product in Scan
and Alert mode with repository access restricted to orchestration. The operator
reports the dependency graph and Dependabot alerts enabled, competing Dependabot
version-update and security-update PRs disabled, and alert-read access granted
where offered. Renovate opened
[Dependency Dashboard #55](https://github.com/budgetanalyzer/orchestration/issues/55)
at `2026-09-14T15:05:04Z` without creating a PR, branch, commit, or Actions run.
The dashboard contains 95 approval-gated proposals and 75 routine proposals
awaiting schedule, consistent with the configured approval and weekly-schedule
controls. Public settings APIs do not expose the operator-reported security
toggles, so retain that report as administrator evidence.

The operator selected only the routine `renovate/renovate-44.66.x` dashboard
entry. Renovate opened
[PR #56](https://github.com/budgetanalyzer/orchestration/pull/56) at
`2026-09-14T15:13:39Z` from `renovate/renovate-44.66.x` at
`a12888e1d19309eb79bde14d06f673e4ab683479` into
`dependency-automation-trial`. Its one commit changes only
`.github/workflows/dependency-automation-config.yml`, updating
`RENOVATE_VERSION` from `44.65.5` to `44.66.1`. Pull-request run
[34860772186](https://github.com/budgetanalyzer/orchestration/actions/runs/34860772186)
completed successfully in 37 seconds: `validate-renovate-config` passed in 35
seconds, the manual-only hosted dry-run job correctly skipped, and no artifact
was uploaded. The Renovate-generated PR body explicitly says automerge is
disabled by config. Public refs and the dashboard show this as the sole open
Renovate PR and branch; leave it open and unmerged. Mend Developer Portal
cycle timing, queue delay, timeout, and lookup/error logs are not public and
therefore required administrator review before repository-scope expansion.

The operator reviewed the two Mend cycles and reported that all requested
status, queueing, timeout, rate-limit, authentication, and lookup checks looked
good. Exact portal timestamps and durations were not transcribed, so the public
Dashboard and PR timestamps remain the retained timing evidence. Step 5.6 review
also confirmed the effective policy shape:

- routine updates remain on `before 6am on monday`, with three concurrent and
  two hourly PR limits; the Dashboard kept routine proposals under **Awaiting
  Schedule** until the operator selected one;
- major, Helm, stateful, platform/ARM64, chart-image override, and
  checksum-coupled proposals appear under **Pending Approval**, including
  maintained Istio `1.29.7`, Prometheus `3.11.3`, stateful digest, and platform
  release proposals;
- digest proposals retain tags and flavor suffixes such as
  `postgres:16-alpine`, `redis:7-alpine`, and
  `eclipse-temurin:25-jre-alpine`, while detected image updates retain
  `nginx-unprivileged`'s `-alpine` flavor;
- vulnerability alerts are enabled with an unrestricted schedule and
  `automerge: false`; no live vulnerability-fix PR was available in this pilot,
  so graph-backed alert and schedule-bypass behavior remains Step 6 evidence;
  and
- the Dashboard contains no first-party Budget Analyzer image proposal, and the
  production promotion paths remain ignored. The Dashboard does detect the
  service deployment resources themselves, which is not a first-party image
  update proposal.

This completes the orchestration Step 5 pilot without merging PR #56. Runtime
enforcement of the configured concurrency/hourly limits and live vulnerability
behavior still require the deliberately broader Step 6 observation period.

The Step 6.1 public pre-expansion audit found all eight remaining scoped
repositories still defaulting to `main`, with clean local checkouts matching the
published `main` and trial refs, zero open PRs, and the explicit trial preset ref
in every `renovate.json`. Their release workflows are tag/manual-only except
`service-common` snapshot publication, which explicitly follows pushes to
`main`; changing a default branch does not trigger any of them. Trial schedules,
uploads, graph submissions, and optional caches remain gated off. However, none
of the eight repositories has a repository ruleset or classic branch protection
on either `main` or `dependency-automation-trial`. Protect both refs before each
serialized default switch and App-scope expansion. Start with `service-common`,
which is first in the graph-submission dependency order; do not grant Mend
access or switch its default until that protection is publicly verified.

### Trial workflow controls

All nine repositories use the exact protected ref
`refs/heads/dependency-automation-trial`. Relevant build workflows accept pushes
to that ref and pull requests whose base is either `main` or the trial branch.
Scanner and graph workflows accept only direct `main` or trial refs; they reject
pull-request merge refs and unrelated manual-dispatch refs. Snapshot and release
publishing workflows remain unchanged.

Repository variables control every trial-side expansion and are disabled when
unset or set to any value other than the exact string `true`:

| Repository variable | Trial behavior enabled |
| --- | --- |
| `DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED` | Allows a scheduled scanner or graph job to run when the trial branch is the current default. |
| `DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED` | Allows a measured, complete sealed evidence archive to upload for one day. |
| `DEPENDENCY_AUTOMATION_TRIAL_GRAPH_SUBMISSION_ENABLED` | Allows Java graph submission only when the exact trial ref is also the current default branch. |
| `DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED` | Allows the workflow's optional Actions-backed cache after the initial cache-disabled measurement. |

The initial branch measurement therefore runs complete builds, scans, and Java
graph generation with trial schedules, uploads, graph submission, and optional
caches off. Java workflows use Gradle's generation-only graph mode, keep package
read secrets separate from `${{ github.token }}`, and preserve strict dependency
resolution. Main-branch graph submission and existing main build/scanner uploads
retain their production behavior.

Every repository carries `.github/scripts/prepare-trial-evidence.sh`. The helper
archives only a workflow's explicit allowlist, reports source, uncompressed-tar,
and compressed bytes in the job summary, and blocks trial upload unless the
complete archive fits within 24 MiB. The 24 MiB payload ceiling reserves 1 MiB
inside the approved 25 MiB per-run cap for the Actions artifact wrapper and
metadata. Trial uploads use one-day retention and no second compression pass.
Image layers, scanner databases, dependency caches, and unrelated workspace files
are excluded. If an enabled upload would exceed the cap, the workflow fails
evidence delivery without trimming findings. Size-only runner summaries remain
measurement evidence, not scan or graph acceptance.

### Operator sequence

The Phase 12 operator sequence is below. Steps 5–8 apply to the full rehearsal;
when `main` remains default, retain those unperformed checks as pending.

1. Use the existing GitHub administrator identity to sign in to the Mend
   Developer Portal with GitHub OAuth, without installing the App, starting a
   trial, selecting a paid product, or adding payment information. Inventory all
   third-party dependencies, verify the currently published free terms and
   limits, complete the bounded-trial cost prerequisite above, confirm package
   visibility and existing Maven secret names, and record a dated trial go/no-go
   decision. Confirm that App scope can be restricted during installation and
   that hosted credentials are supported; prove repository selection, actual
   hosted artifact sizes, and authenticated Maven lookup later during the pilot.
   Stop before publication if the operator does not accept the hosted-service
   durability risk or zero-spend boundary.
2. Prepare branch-scoped triggers, trusted-ref guards, upload caps, and disabled
   schedules in every owning repository. Publish the orchestration trial preset
   before consumers, using an explicit preset ref. No default-branch merge is
   required. Record each trial SHA and the unchanged `main` SHA.
3. Run
   `dependency-automation-config.yml` with `run_hosted_dry_run` enabled. Its
   GitHub-provided job token has read permissions only, Renovate runs with
   `--dry-run=full`, and the user retains control of the trigger. Preserve the
   workflow URL and confirm the intended trial ref and preset resolve before
   proceeding; never copy the job token into an agent environment. GitHub hides
   **Run workflow** while this workflow exists only on the non-default trial
   branch. In that state, make a reviewed qualifying push whose head commit
   message contains `[run-hosted-renovate-dry-run]`; the marker runs the dry-run
   job and suppresses the exact-image job for that push. An unmarked push leaves
   the dry-run job skipped. Stop using the marker to disable the fallback, and
   remove its push and suppression clauses during final promotion while retaining
   normal `workflow_dispatch`. Because `main` has no Renovate config,
   `baseBranchPatterns` plus `useBaseBranchConfig=merge` cannot bootstrap the
   branch-only run. The workflow instead wraps the reviewed trial
   `renovate.json` as the configuration for exactly this repository, bypasses
   onboarding with `requireConfig=optional`, and forces the trial base. It fails
   unless Renovate extracts dependencies, selects the trial base, emits dry-run
   mutation simulation, finishes with `Repository result: done`, and emits no
   `ERROR` or `FATAL` records.
4. Complete the bounded scanner/build measurement runs. Decide whether to stop
   with branch evidence or perform the temporary-default full rehearsal. For the
   latter, apply the operator plan's default-branch controls and install the
   Renovate Community App on orchestration first. Grant read access to Dependabot
   alerts when available. Expand only after the pilot passes.
5. Enable the dependency graph and Dependabot alerts. Disable Dependabot version
   updates and automatic Dependabot security-update pull requests.
6. First use the GitHub Packages host rules that Mend provisions from the App's
   platform token. If that token cannot read the required package, store the
   existing scoped credential in the Mend App settings and reference it from a
   `hostRules` entry with Mend's secret-placeholder syntax. Mend no longer
   supports repository-config encrypted secrets. Never commit a token and never
   use `pull_request_target` to expose trusted credentials to dependency
   branches.
7. In the full rehearsal, run each Java repository's graph-submission workflow
   on its trusted default branch using existing scoped package-read secrets and a separate GitHub
   job token for submission. Verify complete application/runtime/test dependency
   coverage and GitHub acceptance for every repo. A successful ordinary build,
   package-access preflight, or partial snapshot is insufficient. Preserve a
   sanitized snapshot or equivalent detailed graph evidence with the run URL and
   source revision; the orchestration-only Renovate dry run does not prove Maven
   resolution or Java submission. Resolve every other deferred authenticated
   lookup/build/scan and retain its evidence too.
8. Record two successful Mend cycles per repository, complete detailed scanner
   and Java graph evidence, and an actual scheduled cycle for every prepared
   scheduled workflow. Measure bot-PR build artifacts as well as scanner bundles.
   Pause the trial and restore original defaults before deciding whether to merge.
9. Record every baseline item in the coverage report as reproduced, superseded,
   false positive with evidence, or missing. Update discovery, advisory evidence,
   and lifecycle assessment are separate results. Report trial acceptance,
   ongoing installation, and benchmark parity separately. Ongoing installation
   remains pending until the operator approves promotion and verifies the final
   configuration on the restored default branches.

The Community service's documented single concurrent organization job,
approximately four-hour scheduling, and 30-minute timeout are acceptable only if
the pilot completes in practice. A timeout or unsupported authenticated lookup
blocks broader activation; it is not a reason to omit dependencies.

## Local validation and dry run

The focused workflow validates both JSON files with Renovate's official
`renovate-config-validator` under Node 24. Before publishing the preset, run the
same strict schema validation locally. For an unpublished-preset dry run, load
`renovate-presets/default.json` as the local self-hosted configuration, suppress
repository config discovery, and process the checkout with the local platform.
Use debug logging and do not provide a GitHub token or enable a write-capable
platform mode. Local mode proves extraction and supported lookups but does not
perform a true full dry run. Phase 12 owns the post-publication GitHub-platform
full dry run through the operator-triggered, read-only workflow; its ephemeral
job token is never provided to an agent.

Extraction and lookup evidence belongs in
[`docs/research/dependency-automation-coverage.md`](research/dependency-automation-coverage.md),
not in a second desired-version inventory.

## Exact-image security evidence

`exact-image-security-evidence.yml` preserves weekly and manual operation on
`main` and also accepts direct runs of the exact trial ref. It has no pull-request
trigger and findings do not create a merge gate. The job fails when rendering,
registry resolution, database download, package inventory, or a vulnerability
scan is incomplete; vulnerability findings themselves leave the scan successful.
Main runs retain complete evidence for seven days. Trial runs start with schedule,
Trivy cache, and upload expansion off, report exact allowlisted sizes, and permit
only the capped one-day sealed archive described above.

The workflow calls `scripts/security/render-image-scan-inputs.sh`, which uses
the production Kustomize overlays, controller chart versions from
`deploy/scripts/lib/version-contract.sh`, their checked-in values, and the
Prometheus/Kiali post-renderers. It includes Helm-created controllers and hooks,
operator-supplied cert-manager solver and Prometheus config-reloader images,
standalone Jaeger and infrastructure images, and the Tilt Temurin, Kind, and
frontend production-smoke images. First-party service images remain under the
release workflow and are excluded from this scanner job.

Production/controller images are resolved and scanned as `linux/arm64`.
Local-only sources use the actual scanner-runner platform (`linux/amd64` on the
hosted job). For each deduplicated target, the artifact contains:

- the rendered source ref and every file that contributed it
- the registry manifest and the selected platform child digest
- a Trivy all-package JSON inventory with OS and application package classes
- a separate JSON vulnerability report plus captured stderr
- Trivy CLI/database and registry-resolver metadata, database-download logs,
  and a machine-readable completion status

A rendered tag without a digest is labelled `mutable` even though the job
immediately resolves and scans one exact platform digest. This preserves the
difference between repeatable evidence for that run and immutable checked-in
desired state. In particular, External Secrets chart 2.2.0 currently renders
`ghcr.io/external-secrets/external-secrets:v2.2.0`; its checked-in `image.digest`
value is not emitted by that chart version. The tag resolved to the intended
digest during Phase 2 validation, but later tag movement remains possible.
The cert-manager controller/startup refs and Istio CNI/pilot refs are likewise
tag-only chart output; only their resolved artifact for a particular run is
exact. The cert-manager ACME solver input does retain its checked-in digest.

The existing `deploy/scripts/render/observability.sh` and
`guardrails/verify-production-image-overlay.sh` are not CI render entry points:
they intentionally use a live server-side Helm dry run for Kiali RBAC. The
scanner invokes ordinary `helm template` with the same Kiali values and
post-renderer, so it needs no Kubernetes API or production credentials. One
known gap remains explicit: the Istio gateway chart renders `image: auto`, and
only a live Istio injector chooses the proxy image. The workflow records that
target as a known unscannable gap rather than adding a live-cluster dependency
or claiming coverage. Unexpected render, resolution, database, or scan failures
still fail the job.

Trivy package evidence is not a lifecycle authority and does not guarantee that
an image exposes its primary application version. The coverage report records
known Redis, Temurin, and controller-binary inventory limitations. Never infer a
Redis patch or Java CPU level from the broad source tag or from a successful OS
package scan.

## Post-activation operator workflow

Begin this routine only after Phase 12 records successful activation evidence
in the coverage report. Until then, the same checks are acceptance work, not a
verified operating history.

Every week, an operator should:

1. Review each scoped repository's Dependency Dashboard, newly opened Renovate
   pull requests, and any lookup, authentication, timeout, or rate-limit error.
   Keep maintained-line patches visible alongside approval-gated majors and
   migrations.
2. Review Dependabot alerts separately from update proposals. Map each alert to
   the resolved package and configuration or image artifact; never treat an
   update pull request as proof that an advisory was detected.
3. Check the latest scheduled dependency-submission and scanner workflows.
   Distinguish vulnerability findings from failed resolution, database download,
   inventory, or report generation. A missing or partial report is a failed
   operation, not a clean result.
4. Review bot pull-request checks and any package/registry access failure. Keep
   credentials in GitHub or Mend's supported encrypted storage and preserve the
   trusted-branch boundary; never move dependency checks to
   `pull_request_target` to expose secrets.
5. Confirm Renovate remains the sole update-PR owner, automerge remains off,
   first-party production promotion paths are untouched, and free-service job
   duration/queueing plus Actions usage remain within the approved zero-spend
   boundary.

Every quarter, compare Spring, Node, Go, Java, Ubuntu, Kubernetes/K3s, Istio,
RabbitMQ, NGINX, and other runtime lines with their upstream lifecycle policies.
Record the review even when Renovate proposes no update: release discovery,
abandonment heuristics, and vulnerability databases are not comprehensive EOL
detectors.

When adding a dependency, first use the owning ecosystem's native Renovate
manager and confirm extraction in debug logs. If the version is embedded in a
supported nonstandard declaration, add the smallest adjacent standard Renovate
annotation or declarative regex manager in the owning repository. Preserve tag
prefixes, flavor suffixes, immutable digests, checksums, chart coupling, and
platform requirements. Update the owning repository's handoff or this coverage
report when the new surface introduces an authenticated lookup, scanner target,
or known standard-tool gap. Do not add a custom crawler or seed a historical
target version merely to make discovery appear complete.

## Failure triage

- **Configuration error:** reproduce with the pinned validator version. Treat
  warnings and migrations as failures; correct the preset or repository config.
- **No extraction:** check the owning file's native manager pattern or adjacent
  annotation and compare debug logs. Do not seed the historical expected version
  into configuration.
- **No lookup or wrong package:** verify the real datasource identity, chart
  name, registry URL, tag prefix, build suffix, and flavor suffix. Record an
  unresolved standard-tool gap instead of adding a custom crawler.
- **Authentication or resolution failure:** preserve the failure. Fix encrypted
  Maven/registry access through the Phase 12 operator handoff. During Phases 1–10,
  record authentication-dependent checks as pending and continue independent local
  work. Never seek credentials in the agent environment, use Maven Local as proof
  of remote resolution, drop internal dependencies, or swallow the error. A
  resolution defect unrelated to authentication still needs investigation.
- **Finding without an update:** retain the Dependabot/scanner finding and route
  inherited or transitive remediation to the owning service. An update pull
  request is not proof that an advisory was detected.
- **CI failure on a bot branch:** determine whether the proposal needs its
  documented checksum, chart rendering, ARM64, state migration, or cross-repo
  companion review. Do not relax a guardrail or create orchestration drift.
- **Scanner database/download failure:** report the job as failed separately
  from vulnerability findings. Never turn an unavailable scan into a clean result.

Renovate discovery and vulnerability scanners do not comprehensively establish
end-of-life status. Owners must still perform a quarterly support-policy review
against upstream lifecycle sources.
