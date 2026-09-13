# Dependency Automation

**Status:** Configuration prepared; administrator activation is still required.

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
`govulncheck`, `pip-audit`, and the public registries and advisory databases do
not require separate new accounts for this rollout.

GitHub Actions usage is separate from Mend hosting. Standard GitHub-hosted
runners are currently free for public repositories, but artifact storage is
still limited by the GitHub plan and shares its allowance with GitHub Packages.
Public packages are currently free; private package storage and transfer have
plan allowances. Before enabling automation, inspect the organization plan,
Actions artifact usage, package visibility and usage, payment-method state, and
budgets. If no payment method is present, over-limit use should be blocked rather
than billed; if a payment method exists, require a zero-dollar budget or another
effective no-spend control. Recheck runner and storage allowances if repository
or package visibility changes.

The operator must make an explicit third-party dependency decision before any
publication or activation. Mend currently documents Community Cloud as a free
tier for unlimited public and private repositories and publishes its resource
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
prepared and locally validated their files. Phases 1–11 require no credentials;
all authenticated validation and credential review belong to Phase 12. Agents
must never receive GitHub, package, registry, or Mend credentials, including in
Phase 12. The user performs authenticated operations in GitHub/Mend or their own
trusted environment and supplies sanitized evidence for agent review.

Missing authentication, authenticated-only API access, and unauthenticated API
rate limits are recorded as pending Phase 12 evidence; they do not block local
configuration preparation. This includes private Maven resolution, complete
remotely resolved Java snapshots, graph submission, published-preset resolution,
and hosted bot/scanner runs. Local schema validation, extraction, workflow lint,
and checks that can run without credentials remain required. Preserve actual
failures and incomplete outputs; never report a deferred check as passed or
weaken a hosted job's failure behavior. Non-authentication prerequisites and
implementation defects remain blockers under the owning repository's rules.

For each deferred check, record the repository, check/command, affected packages
or configurations, observed failure or reason not attempted, and the Phase 12
operator action and expected proof. Sibling phases keep this handoff in their
own docs and link here; Phase 12 consolidates it in the coverage report.

The Phase 12 operator sequence is:

1. Use the existing GitHub administrator identity to sign in to the Mend
   Developer Portal with GitHub OAuth, without installing the App, starting a
   trial, selecting a paid product, or adding payment information. Inventory all
   third-party dependencies, verify the currently published free terms and
   limits, inspect GitHub Actions artifact and Packages usage, confirm package
   visibility and existing Maven secret names, and record a dated go/no-go
   decision. Confirm that App scope can be restricted during installation and
   that hosted credentials are supported; prove repository selection and actual
   authenticated Maven lookup later during the pilot. Stop before publication if
   the operator does not accept the hosted-service durability risk or zero-spend
   boundary.
2. Publish the orchestration repository and its shared preset before publishing
   consumer configurations.
3. Manually dispatch
   `dependency-automation-config.yml` with `run_hosted_dry_run` enabled. Its
   GitHub-provided job token has read permissions only, Renovate runs with
   `--dry-run=full`, and the user retains control of the trigger. Preserve the
   workflow URL and confirm that the published preset resolves before proceeding;
   never copy the job token into an agent environment.
4. Install the Renovate Community App only on the repositories listed in the
   rollout plan. Grant read access to Dependabot alerts when available.
5. Enable the dependency graph and Dependabot alerts. Disable Dependabot version
   updates and automatic Dependabot security-update pull requests.
6. First use the GitHub Packages host rules that Mend provisions from the App's
   platform token. If that token cannot read the required package, store the
   existing scoped credential in the Mend App settings and reference it from a
   `hostRules` entry with Mend's secret-placeholder syntax. Mend no longer
   supports repository-config encrypted secrets. Never commit a token and never
   use `pull_request_target` to expose trusted credentials to dependency
   branches.
7. Run each Java repository's graph-submission workflow on its trusted default
   branch using its existing scoped package-read secrets and a separate GitHub
   job token for submission. Verify complete application/runtime/test dependency
   coverage and GitHub acceptance for every repo. A successful ordinary build,
   package-access preflight, or partial snapshot is insufficient. Preserve a
   sanitized snapshot or equivalent detailed graph evidence with the run URL and
   source revision; the orchestration-only Renovate dry run does not prove Maven
   resolution or Java submission. Resolve every other deferred authenticated
   lookup/build/scan and retain its evidence too.
8. Run onboarding for orchestration first. Inspect the resolved configuration,
   extraction logs, dashboard, job duration, and any rate-limit or timeout
   message before enabling consumers.
9. Record every baseline item in the coverage report as reproduced, superseded,
   false positive with evidence, or missing. Update discovery, advisory evidence,
   and lifecycle assessment are separate results.

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
full dry run through the manually dispatched, read-only workflow; its ephemeral
job token is never provided to an agent.

Extraction and lookup evidence belongs in
[`docs/research/dependency-automation-coverage.md`](research/dependency-automation-coverage.md),
not in a second desired-version inventory.

## Exact-image security evidence

`exact-image-security-evidence.yml` runs weekly and by manual dispatch. It has
no pull-request trigger and findings do not create a merge gate. The job fails
when rendering, registry resolution, database download, package inventory, or a
vulnerability scan is incomplete; vulnerability findings themselves leave the
scan successful. The final upload runs even after failure and retains evidence
for seven days without relying on SARIF hosting or a paid service.

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
  Maven/registry access through the Phase 12 operator handoff. During Phases 1–11,
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
