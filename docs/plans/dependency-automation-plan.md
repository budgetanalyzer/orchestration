# Dependency Automation Plan

**Status:** Local preparation in progress; Phases 1–10 are credential-free.
All authenticated validation and human activation are deferred to Phase 12.
Automation is not installed or enabled by this document.

Phase 12 now uses a branch rehearsal before the operator's merge decision; see
the [operator checklist](dependency-automation-phase-12-operator-plan.md).
Completed preparation phases retain their history. Trial workflow adaptations
are additional owning-repository work, not evidence already completed here.

Use Renovate to discover dependency updates and open reviewable pull requests across
Budget Analyzer. Keep GitHub Dependabot alerts enabled for vulnerability detection,
and use existing open-source scanners for dependencies that update discovery alone
cannot assess. No dependency upgrades are part of implementing this plan.

Preserve [the September 6 review](../research/dependency-update-review-2026-09-06.md)
unchanged as the acceptance benchmark. Its versions are historical observations,
not inputs to the bot's target selection. Automation must independently discover
equivalent or newer applicable updates. Record misses explicitly; an update PR is
not proof that the associated security advisory was detected.

## Selected tools and cost

| Purpose | Selection | Cost and boundary |
| --- | --- | --- |
| Version and digest update PRs | Open-source Renovate, run by the Mend Renovate Community GitHub App | The app explicitly supports public and private repositories without a paid plan. No self-hosted bot infrastructure is needed. |
| Dependency vulnerability alerts | GitHub dependency graph and Dependabot alerts | Available on GitHub Free. GitHub's hosted service is proprietary; the update engine and added scanning tools are open source. |
| Resolved Java dependency graph | Official `gradle/actions/dependency-submission` | Use the open-source `cache-provider: basic` path, not the proprietary enhanced cache or a preview subscription. |
| Image packages and vulnerabilities | Trivy CLI/action | Open source; no Aqua subscription, server, or commercial database required. |
| Frontend and Go verification | `npm audit` and `govulncheck` | Existing ecosystem tools; no subscription. |

Renovate is the sole update-PR owner. Do not add Dependabot version-update
configuration or enable overlapping Dependabot security-update PRs. Renovate can
consume Dependabot alerts and attempt security fixes itself. Alert-only findings,
especially inherited Gradle versions, remain visible when it cannot produce a fix.

The free Mend service currently documents unlimited repositories, one concurrent
job per organization, approximately four-hour scheduling for active repositories,
and a 30-minute job timeout. That is adequate for initial dependency discovery;
the pilot must verify actual completion for this project. Paid Merge Confidence,
enterprise scheduling, support, and approval for enhanced OSS resources are not
prerequisites.

GitHub Actions compute and artifact storage are a separate cost consideration.
Use standard Linux runners, short artifact retention, and existing jobs where
practical. Public-repository standard runners are free; private-repository usage
must fit the account's included allowance with paid overages disabled. Repository
visibility, billing settings, and bot installation cannot be inferred from the
checkout; the unauthenticated API check during planning returned HTTP 403.
Before activation, verify these settings. If a necessary capability requires a
subscription, trial conversion, paid runner, or additional spend, stop and discuss
it with the user. Do not silently switch to a paid offering or provision a server.

## Scope and operating policy

The rollout covers `orchestration`, `service-common`, `currency-service`,
`permission-service`, `transaction-service`, `session-gateway`,
`budget-analyzer-web`, `ext-authz`, and `workspace`. Other sibling checkouts are
outside this rollout.
Each sibling phase executes in that repository's context and reads its own
`AGENTS.md`; orchestration workers must not implement sibling service logic.

The implementation consists of repository configuration, small CI additions, and
documentation. Use native Renovate managers first. For existing shell variables,
Tilt strings, and download URLs, use Renovate's documented declarative regex
manager and annotation comments. This is configuration of an existing tool, not a
new dependency crawler. Do not build custom scanners, advisory matching code,
version-selection scripts, lifecycle services, dashboards, or cross-repo bots.

Put common rules in `renovate-presets/default.json` in orchestration. Sibling
`renovate.json` files extend
`github>budgetanalyzer/orchestration//renovate-presets/default`; keep file-specific
extraction rules in their owning repository. Publish the preset before activating
consumers. Operating policy belongs in `docs/dependency-automation.md`,
with sibling docs linking to it instead of copying detailed policy.

Initial policy:

- Start from `config:recommended`, enable the Dependency Dashboard, and set
  `automerge: false` everywhere, including security fixes.
- Create routine PRs weekly, initially at most three open routine PRs per repo
  and two new routine PRs per hour. Security fixes bypass the routine schedule;
  verify the effective Renovate configuration preserves that behavior.
- Keep patch, minor, and major recommendations distinguishable. Show both
  maintained-line updates and later release lines where supported by the
  datasource. Use dashboard approval for majors and stateful/platform migrations;
  do not hide them using blanket major exclusions or restrictive version ceilings.
- Group only concrete compatibility families: React/React DOM, Vitest packages,
  related Spring coordinates within a repo, repeated Istio pins, and related
  chart/CLI declarations. Helm chart majors are not application majors: all
  controller/chart updates need review even when semver calls them a patch.
- Keep Helm 4, RabbitMQ/PostgreSQL migrations, and Kubernetes/Istio coordination
  visible as proposals requiring compatibility review. Bots cannot coordinate an
  atomic merge across repositories or infer the correct Spring release train.
- Enable digest refreshes and retain digest pinning and image flavor suffixes.
  Never replace an immutable reference with a floating tag. Verify ARM64 support
  before accepting image updates; an available registry tag is insufficient.
- Exclude historical docs, generated output, local `:tilt-*` images, and documented
  local image repositories from updates. First-party production artifact promotion
  remains owned by the existing release workflow and its synchronized manifest,
  inventory, and overlay; Renovate must not update those independently.
- New checks report the existing vulnerability backlog without blocking every
  unrelated PR. Publish findings and distinguish scan failures from findings;
  do not swallow authentication, database-download, or dependency-resolution
  failures. Introducing a vulnerability merge gate is a separate decision.

## Coverage contract

Create an ordinary Markdown coverage report during implementation at
`docs/research/dependency-automation-coverage.md`. It records source paths,
extracted package identities, observed bot/scanner outputs, and remaining gaps.
Do not maintain a second hand-curated table of desired dependency versions.

| Baseline area | Automated update discovery | Security/support proof and expected limits |
| --- | --- | --- |
| Spring Boot, Cloud, Modulith, SpringDoc, Testcontainers, other Java dependencies | Renovate Gradle/version-catalog and wrapper managers in all five Java repos | Submit resolved graphs, including Framework, Security, Jackson, Tomcat and Netty, to Dependabot. A Boot PR alone does not establish that its BOM fixes every finding. Overrides require service-owner assessment. |
| Frontend direct and transitive packages; later toolchain majors | Renovate npm manager, lockfile maintenance, Dockerfile and Actions managers | Dependabot alerts plus full and production-only `npm audit`. Compare advisory/package identities, not the old total of 20 findings. Preserve browser/SSR/dev-server applicability distinctions. |
| go-redis and Go runtime | Renovate gomod, Dockerfile, Actions, and workspace download extraction | `govulncheck ./...` must reproduce or explain GO-2025-3540 and distinguish reachable calls from package presence. |
| Redis, PostgreSQL, RabbitMQ, NGINX, Temurin, Jaeger, Swagger UI and other deployed third-party images | Dockerfile/Kubernetes/Helm-values managers plus Tilt and script extraction; digest updates | Trivy scans the exact selected digest and inventories the embedded software. A new digest does not prove the exact Redis or JDK patch or advisory fix. Missing package identification is a coverage gap. |
| External Secrets, Kyverno, cert-manager, Istio, kube-prometheus-stack, Kiali | Helm datasource mapped to shell and Tilt pins; explicit chart names and registry URLs | Render selected charts and scan their actual image refs. Chart versions differ from app versions. Controller advisories may lack matching image-package metadata and must be recorded as misses. |
| Prometheus, Grafana, Prometheus Operator, kube-state-metrics | Helm-values image refs plus chart updates | Scan explicitly overridden images as well as chart defaults. Updating a chart does not update an independently overridden image tag. |
| K3s, Kind binary/node image, Kubernetes tooling, Gateway API, Calico, Helm, Tilt and other pinned tools | Built-in Docker/release datasources and annotated existing pins | Show supported-line patches and newer releases independently. Tool versions coupled to checked-in checksums need complete checksum changes before merge. Pod Security labels are compatibility settings, not ordinary package pins. |
| Workspace base image, Node/Go, Zulu and installed packages | Dockerfile/ARG/download extraction where versions are declared | Scan a built workspace image for installed versions. Unversioned apt installs receive updates through rebuilds; Renovate cannot open a version PR for an absent patch pin. Preserve the digest-only Ubuntu base constraint. |
| EOL decisions: Boot, Node, Go, RabbitMQ, NGINX, Kubernetes/K3s and Istio | Newer releases should be visible in the bot dashboard | Renovate release discovery, abandonment heuristics, and vulnerability scanners are not a comprehensive EOL detector. Retain a quarterly human support-policy check against upstream lifecycle sources. |

Both patch and major proposals must remain visible for broad tags such as
`redis:7-alpine` and `eclipse-temurin:25-jre-alpine`. Test actual extraction and
lookup: broad tags can produce only digest updates and conceal patch identities.
If a same-digest, explicit-version alias is needed for reliable recommendations,
record that as a separately reviewed representation change; do not silently
upgrade the underlying image during onboarding.

Keep tool versions with checksum tables, chart/application coupling, and the
digest-only workspace base behind dashboard approval until a proposal contains
all required companion changes. Use existing Renovate checksum capabilities where
they fit and verify them; regex extraction alone does not calculate arbitrary
checksums. Otherwise identify the missing companion work in the proposal and
retain existing validation failures. Do not weaken verification to make a bot PR
mergeable.

## Acceptance and activation boundaries

The target is automated coverage of the same or a superset of the review's update
and security findings. Measure update discovery, advisory detection, and lifecycle
assessment separately. For every baseline item, record one of: reproduced,
superseded by a newer applicable finding, false positive with evidence, or missing.
Include the advisory identifier, affected package/version, proposed target where
available, output URL/artifact, and any required human compatibility decision.

All baseline areas must have a demonstrated extraction/scan path. Missing
high-priority findings block a claim of full review parity. Tool installation can
be reported complete while parity remains incomplete, but those are distinct
outcomes. If standard configuration and the selected tools cannot close a gap,
report it to the user; do not fabricate an advisory match, seed expected versions
into configuration, or add a custom implementation. The lifecycle and
exploitability limits above remain explicit even after successful onboarding.

Implementation phases prepare reviewable local files. No phase authorizes git
writes, merging dependency PRs, releases, certificate writes, or cluster changes.
The user owns committing and publishing changes. Before final observation, a
repository administrator installs the free Renovate App only on the scoped repos,
enables dependency graph and Dependabot alerts, grants the app alert-read access,
and confirms duplicate update-PR services are off. Prepare all configuration and
documentation before this activation handoff. Do not change GitHub settings while
merely executing this planning request.

Existing Maven package credentials are a Phase 12 prerequisite for complete
remote Java graph resolution and successful bot PR CI, not a prerequisite for
Phases 1–10. Prepare references to the existing scoped GitHub Packages secrets in
trusted CI without reading or verifying their values. The Phase 12 operator
first tests Mend's App-token GitHub Packages access. If Renovate needs a separate
credential for private Maven lookup, the operator stores the existing scoped
credential in the Mend App settings and references it from `hostRules` with
Mend's secret-placeholder syntax. Mend no longer supports repository-config
encrypted secrets. Verify free-app support before activation. Never put tokens
in presets or reports, substitute Maven Local for remote-resolution proof, drop
internal dependencies, or introduce privileged `pull_request_target` execution
of dependency branches to obtain secrets.

## Credential-free preparation and Phase 12 handoff

The user explicitly requires all authentication and credential review to wait
until Phase 12. Agents must never receive or use GitHub, package-registry, image-
registry, or Mend credentials, even in Phase 12. Do not search environment files,
credential stores, host mounts, or sibling repos for secrets; ask for tokens,
logins, or early workflow dispatches; or provision replacement credentials.
Authenticated operations run under the user's control in trusted hosted CI,
GitHub/Mend administration, or the user's own trusted environment. Agents inspect
public output or user-supplied sanitized evidence without authenticated access.
The canonical operating procedure is `docs/dependency-automation.md`.

These rules apply to every phase worker, including retries:

1. Phases 1–10 complete repository configuration, documentation, strict schema
   validation, dependency extraction, workflow lint, and applicable credential-free
   checks. Use local preset files before publication. Run public lookups and local
   scans/builds where available without credentials.
2. All authenticated GitHub/API lookups, private-package resolution, complete
   remotely resolved Java snapshots, hosted graph submissions, published-preset
   resolution, hosted bot/scanner verification, and visibility/billing/App/secret
   review are Phase 12 acceptance work. Do not require a successful historical CI
   build or proof that repository secrets exist to complete preparation.
3. When a check needs authentication, or an unauthenticated API limit prevents
   it, record it as `pending Phase 12` and continue independent preparation. A
   known requirement can be recorded without repeatedly provoking a 401/403.
   Preserve any partial output as incomplete. This also applies to repository
   build/test gates whose execution depends on remote package authentication.
   Their authenticated verification is deferred, not waived or reported passed.
4. Each deferred item must name the repo, check/command, affected package or
   configuration, failure evidence or reason not attempted, required operator
   action, and expected Phase 12 proof. Store sibling handoffs in their own nearest
   docs; Phase 12 consolidates them into orchestration's coverage report. Never
   change runner-owned state or outcomes to bypass a gate.
5. Missing credentials are deliberately not preparation prerequisites under this
   user-approved scope. Once local preparation checks pass and every deferred
   item has a durable handoff, report the phase complete with authenticated
   acceptance pending. Do not return a blocked/clarification outcome solely for
   those deferred checks. Report other missing prerequisites, invalid config,
   extraction defects, crashes, and non-authentication tool failures normally.
   Do not silently classify an unexplained 403 or resolution error as an auth gap.
6. Keep hosted workflows strict: authentication, resolution, download, and scan
   failures must still fail their jobs. A tool's zero exit status or partial Java
   snapshot is not proof of coverage. Do not change dependencies, filters, caches,
   build logic, or checks to manufacture a successful remote-resolution result.
   Optional local snapshots are local evidence only, never hosted acceptance.

Phases 1–10 completion means preparation is complete; it does not mean automation
is active, authenticated checks passed, or review parity was established. Phase 12
is the sole human authentication/activation gate and cannot complete until its
required authenticated evidence is available. Missing evidence then requires a
specific operator handoff, never credentials for the agent.

For the stopped Phase 4 retry, inspect and retain its existing configuration and
validation evidence. The incomplete 87-coordinate snapshot and unavailable Maven
access remain pending Phase 12; neither blocks preparation under this revision.
Revalidate changed files as needed and complete the phase only after its local
checks and durable handoff meet the revised criteria. Preserve phase numbers and
completed phase history. After this edit, the user resumes the stopped runner with
`--retry-stopped --accept-plan-change` added to their existing run command.

## Execution runtime prerequisite

Before resuming this plan at Phase 2, the user will upgrade the sibling
`../workspace` sandbox from Node 22 to Node 24, update that repository's nearest
runtime documentation, rebuild the development container, and complete the
workspace-owned post-rebuild checks. This is a user-owned prerequisite, not a
dependency upgrade implemented by this plan. An orchestration worker must not edit
the workspace repository to satisfy it.

At the start of the next runner invocation, verify `node --version` reports major
version 24 and that `npm --version` succeeds. Stop if the rebuilt runtime is not
active. Renovate `44.65.5` previously loaded under Node `22.23.2` emitted an
unhandled `RegExp.escape is not a function` rejection while returning exit status
zero. Treat any uncaught exception, unhandled rejection, or fatal/error log from
Renovate as validation failure regardless of process status. Classify documented
authentication/API-limit failures as pending Phase 12 under the boundary above;
that classification never turns a failed run into a pass. After this prerequisite
is complete, run local Renovate validation directly under the workspace's Node 24;
do not hide a stale container behind an ad hoc downloaded Node runtime.

The manual Node 22-to-24 change becomes the declared baseline for later extraction
and image scanning. Record it as a prerequisite change, not as a Renovate-discovered
or bot-applied finding when comparing automation with the saved review.

## Upstream references

These support the tool selection; the review remains the historical benchmark.
Recheck availability and schema options at implementation time.

- [Renovate GitHub App: explicitly free, including private repos](https://github.com/apps/renovate)
- [Mend Community hosting limits and paid-feature separation](https://docs.renovatebot.com/mend-hosted/overview/)
- [Mend App-settings credential storage](https://docs.renovatebot.com/mend-hosted/credentials/)
- [Renovate private-package and GitHub Packages authentication](https://docs.renovatebot.com/getting-started/private-packages/)
- [Renovate open-source license](https://github.com/renovatebot/renovate/blob/main/license)
- [GitHub security features available on all plans](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [Renovate shared presets](https://docs.renovatebot.com/config-presets/)
- [Renovate regex manager](https://docs.renovatebot.com/modules/manager/regex/)
- [Kubernetes manager requires explicit file patterns](https://docs.renovatebot.com/modules/manager/kubernetes/)
- [Renovate vulnerability alert integration](https://docs.renovatebot.com/configuration-options/#vulnerabilityalerts)
- [Renovate OSV limitations: direct dependencies and selected datasources](https://docs.renovatebot.com/configuration-options/#osvvulnerabilityalerts)
- [Gradle dependency submission and basic cache option](https://github.com/gradle/actions/blob/main/docs/dependency-submission.md)
- [Trivy container images, SBOMs and platform selection](https://trivy.dev/latest/docs/target/container_image/)
- [Go vulnerability checking](https://go.dev/doc/security/vuln/)

## Phase 1: Configure the orchestration pilot and shared policy

### Workspace

.

### Goal

Prepare Renovate configuration that discovers the orchestration dependency surface.

### Scope

Shared preset, root Renovate config, annotation comments, configuration validation,
and canonical dependency-automation documentation.

### Non-goals

No dependency/version/digest changes, sibling edits, bot installation, or deployment.

### Required context

Read `AGENTS.md`, `docs/OWNERSHIP.md`, the saved review, `Tiltfile`,
`deploy/scripts/lib/version-contract.sh`, `scripts/lib/pinned-tool-versions.sh`,
both image inventories under `scripts/lib/`, and existing static guardrails.

### Execution steps

1. Create `docs/dependency-automation.md` with the policy, cost boundary, bot
   ownership, activation procedure and failure triage. Transfer active operational
   ownership there in `docs/OWNERSHIP.md`; link from README and relevant CI docs.
2. Add the shared preset and root config. Explicitly configure Kubernetes and
   Helm-values file patterns; Dockerfile detection alone is insufficient.
3. Add documented Renovate annotations/extraction for chart pins in shell and
   Tilt, image strings in Tilt/scripts, Kind node images, and pinned tool releases.
   Bind each chart to its real chart name/repository, not just a GitHub project.
   Cover repeated pins without duplicate native/custom extraction.
4. Preserve pinning exceptions, production artifact ownership and checksum
   contracts. Make stateful/platform/checksum-coupled proposals approval-gated.
5. Add a focused workflow using Renovate's official config validator; initialize
   the coverage report with actual paths and extraction evidence.

### Implementation notes

Use current documented schema options. Validate registry tag formats, K3s build
suffixes, `v` prefixes and image compatibility suffixes. Do not treat Pod Security
labels as dependency versions. Existing docs and version-contract comments that
describe intentional holds should become review prerequisites, not silent ignores.

### Validation

Confirm `node --version` reports major version 24, then run
`renovate-config-validator` against both files. Validate config against the local
preset before it is published, then use Renovate's local platform with debug
extraction/lookup output. Local mode does not implement branch-file mutation and
downgrades `full` dry runs to lookup; record GitHub-authenticated lookups and a true
GitHub-platform full dry run as explicit Phase 12 gaps rather than giving an agent a
token or blocking configuration preparation. Treat Renovate exceptions or error
logs as failures even if its exit status is zero, with documented authentication
and API-limit gaps handed off under the plan-wide boundary. Run `bash -n` and
`shellcheck` on annotated shell files, actionlint on changed workflows, and the existing static
guardrails when their documented prerequisites are present. Missing local
non-authentication prerequisites are blockers, not reasons to bypass checks.

### Completion criteria

Every orchestration row in the coverage contract has extracted identities and
lookup results or an explicit gap. Config validates and checked-in dependency
selections remain unchanged. A successful schema check alone is insufficient.
Publication, authenticated GitHub lookup, published-preset resolution, and hosted
branch mutation simulation are Phase 12 acceptance work and do not block Phase 1.

## Phase 2: Add exact-image security evidence

### Workspace

.

### Goal

Produce repeatable vulnerability reports for pinned infrastructure and controllers.

### Scope

A standard Trivy workflow and the canonical documentation/coverage report.

### Non-goals

No custom scanner, advisory correlator, persistent security service, or live cluster.

### Required context

Read Phase 1 outputs, `scripts/README.md`, `kubernetes/production/README.md`,
observability values, and existing offline chart/render entry points. Identify
which existing render checks require a live API before selecting CI commands.

### Execution steps

1. Add weekly and manual scans of selected source refs. Reuse offline Helm and
   Kustomize rendering with the actual values and post-rendering configuration;
   collect image fields with standard YAML tooling and simple workflow steps.
   Include chart controllers, hooks and overridden monitoring images. Do not
   create a second handwritten list of image versions.
2. Scan exact immutable image refs with Trivy for `linux/arm64`; include relevant
   local-only images on their actual platform. Save resolved ref/platform, package
   inventory, vulnerability report and scanner/database metadata as short-lived
   GitHub artifacts and summarize the findings in the job output.
3. Include the Tilt Temurin base and standalone infrastructure images. Distinguish
   OS packages from embedded application versions; identify images Trivy cannot
   fully inventory. Do not infer a Java CPU or Redis patch from a tag alone.
4. Report vulnerabilities without making the initial backlog a new merge gate.
   Make incomplete scans visibly fail and retain reports even when findings exist.
   Use CLI/artifacts without requiring paid private-repository SARIF hosting.

### Implementation notes

Keep orchestration thin: native tools and workflow glue only. Rendering must not
need production credentials or apply anything. If a controller image cannot be
rendered offline with current entry points, report that prerequisite instead of
adding a live-cluster dependency. Pin newly introduced scanner/action inputs per
repository policy and include them in Renovate discovery.

### Validation

Validate the workflow and run representative scans of the current Redis,
Temurin, External Secrets/Kyverno and monitoring images. Prove reports identify
exact artifacts and retain database/scan errors. Compare advisory IDs with the
review and record unsupported image metadata rather than declaring a clean scan.
Any authenticated registry/database access or hosted-run verification is pending
Phase 12 with a per-target handoff; complete the available credential-free checks.

### Completion criteria

Every targeted image has local scan evidence, an explicit unscannable limitation,
or an authenticated check pending Phase 12. Workflow/configuration validation is
complete and standard CI evidence outputs are configured. Hosted execution is
Phase 12 acceptance work, with no new service or paid feature.

## Phase 3: Onboard service-common and its resolved Java graph

### Workspace

../service-common

### Goal

Discover platform/library updates and expose the actual BOM-managed dependency tree.

### Scope

Renovate config, dependency-submission CI, and nearest repository documentation.

### Non-goals

No BOM changes, overrides, library releases, build-logic redesign, or sibling edits.

### Required context

Read this repository's `AGENTS.md`, version catalog, modules and build workflows,
plus orchestration's shared preset and service-common artifact-resolution guide.

### Execution steps

1. Add a thin Renovate config extending the shared preset. Verify extraction from
   catalogs, Gradle plugins, wrapper, Dockerfiles and Actions where present.
2. Add official Gradle dependency submission on trusted default-branch pushes and
   a weekly/manual refresh. Use `cache-provider: basic`; submit with the job's
   GitHub token and the narrowly required `contents: write` permission.
3. Configure coverage of all relevant modules/configurations, including runtime
   and test trees. Generate local evidence where credential-free resolution works;
   otherwise record graph verification as pending Phase 12. The acceptance proof
   must show Framework, Security, Tomcat, Netty and Jackson where actually resolved,
   not just the imported Boot BOM coordinate.
4. Document inherited-dependency limits, visible major migrations and bot PR checks.

### Implementation notes

Use the existing Node 24-ready Actions baseline. Keep submission on trusted code;
do not publish packages or enable Build Scan services to obtain a dependency graph.

### Validation

Validate Renovate config, inspect extraction/lookup, and run actionlint. Generate
the official dependency snapshot locally where supported without credentials or
submission; check module and transitive coverage. Record authentication-dependent
generation/build checks as pending Phase 12. Hosted resolution and submission are
verified only in Phase 12.

### Completion criteria

The graph-generation workflow and bot config pass local configuration checks.
Local transitive evidence is recorded where available; authenticated checks have
explicit Phase 12 handoffs. Selected versions are unchanged.

## Phase 4: Onboard currency-service

### Workspace

../currency-service

### Goal

Provide dependency update proposals and resolved vulnerability alerts for this service.

### Scope

Repository Renovate config, dependency-submission workflow and nearest docs.

### Non-goals

No dependency upgrades, service logic changes, releases or sibling writes.

### Required context

Read local `AGENTS.md`, build/catalog/workflows, the shared preset, and
`../orchestration/docs/development/service-common-artifact-resolution.md`.

### Execution steps

1. Add the thin shared-preset config and verify Gradle, wrapper, image and Actions
   discovery, including the declared `serviceCommon` dependency.
2. Apply the official dependency-submission pattern from Phase 3 with basic caching
   and references to this repo's existing GitHub Packages secret names. Keep
   package-read credentials distinct from the submission token in the workflow;
   do not verify or obtain either credential during this phase.
3. Configure application/runtime/test graph coverage and document the trusted
   branch schedule, bot PR validation behavior, and Phase 12 evidence handoff.

### Implementation notes

A historical remote-package build may be recorded if already available, but is
neither required nor proof that the new submission workflow works. Full remote
resolution belongs to Phase 12. Do not substitute cached/local artifacts for that
proof or omit the dependency.

### Validation

Run the config validator, extraction, credential-free lookup and actionlint.
Inspect a local snapshot only where generation works without authentication;
record missing runtime/test coverage and authentication-dependent build checks as
pending Phase 12. A complete snapshot and hosted submission are not local gates.

### Completion criteria

Repo-local configuration and credential-free checks pass, declared internal
coordinates are extracted, and each authenticated check has a durable Phase 12
handoff. The phase completes with remote resolution, complete runtime/test graph
coverage, and hosted submission explicitly pending; credentials are not required.

## Phase 5: Onboard permission-service

### Workspace

../permission-service

### Goal

Cover this service's declared and resolved dependencies.

### Scope

Thin Renovate config, official dependency-submission workflow and local docs.

### Non-goals

No selected-version changes, service code, releases or sibling writes.

### Required context

Read local instructions/catalog/workflows, the shared preset and the artifact
resolution guide. Reuse the validated Java configuration pattern from Phases 3–4.

### Execution steps

1. Add the shared-preset config and verify all native dependency managers in use.
2. Configure trusted-branch and weekly/manual Gradle graph submission using basic
   caching, references to existing package-read secrets and a separate submission
   token. Do not obtain or verify credentials during this phase.
3. Document the workflow, local evidence, and this service's own Phase 12
   runtime/test graph acceptance requirements.

### Implementation notes

Validate repo-specific modules and workflow wiring locally. Credential validation
and complete remote graph proof belong to Phase 12; another service's successful
snapshot is not evidence that this service resolves correctly.

### Validation

Run Renovate validation/extraction, credential-free lookup and actionlint. Run
official local graph generation only where available without credentials; record
authenticated resolution/build/graph checks as pending Phase 12. Preserve pins.

### Completion criteria

The repo has independently validated local bot/workflow configuration, extraction
evidence, and explicit Phase 12 handoffs for authenticated checks. Complete remote
graph evidence and credential review are not required to complete preparation.

## Phase 6: Onboard transaction-service

### Workspace

../transaction-service

### Goal

Cover transaction-service dependency discovery and vulnerability graph submission.

### Scope

Renovate config, official dependency-submission workflow and local docs.

### Non-goals

No upgrades, service logic, release operations or sibling changes.

### Required context

Read local instructions, catalog and CI, the shared preset, artifact-resolution
guide and the validated Java pattern from Phases 3–4.

### Execution steps

1. Add the thin preset consumer and verify catalog/plugin/wrapper/image/Action refs.
2. Add trusted-branch and weekly/manual graph submission with basic caching, scoped
   package-read secret references and the proper submission-token reference.
3. Document local evidence and the Phase 12 handoff for this service's complete
   remotely resolved runtime/test graph and authenticated checks.

### Implementation notes

Keep internal library publication and cross-repo upgrades under the existing
release process; Renovate merely proposes available published coordinates.

### Validation

Run Renovate validation/extraction, credential-free lookup and actionlint. Generate
a local graph only where possible without credentials. Remote service-common
resolution, authenticated build checks, and complete inherited-dependency graph
proof are pending Phase 12.

### Completion criteria

Local configuration checks and extraction pass, available local graph evidence is
recorded, and authenticated checks have explicit Phase 12 handoffs. A complete
remotely resolved snapshot is not a preparation gate.

## Phase 7: Onboard session-gateway

### Workspace

../session-gateway

### Goal

Cover the reactive authentication edge and its inherited Netty dependencies.

### Scope

Renovate config, official dependency-submission workflow and local docs.

### Non-goals

No security overrides, auth changes, upgrades, releases or sibling writes.

### Required context

Read local instructions/build/catalog/CI, the shared preset, artifact-resolution
guide and Java graph-submission pattern from Phases 3–4.

### Execution steps

1. Add the preset consumer and verify native manager extraction and update lookup.
2. Add trusted-branch and weekly/manual graph submission with basic caching and
   existing package-secret references kept distinct from the submission token.
3. Document the Phase 12 proof for resolved WebFlux/Reactor Netty/Netty and Spring
   dependencies, available local evidence, and the inherited-BOM limit.

### Implementation notes

Do not add a Tomcat expectation to a service that does not resolve it. Prove
coverage from the actual graph rather than copying another service's package list.

### Validation

Run config validation/extraction, credential-free lookup and actionlint. Generate
a local graph only where possible without credentials and inspect available Netty
evidence without overrides. Record authenticated build/resolution and complete
reactive graph verification as pending Phase 12.

### Completion criteria

Local bot/workflow configuration checks and extraction pass, with available local
evidence and explicit Phase 12 handoffs. A complete remotely resolved reactive
runtime graph and credentials are not required to complete preparation.

## Phase 8: Onboard the frontend and audit its lockfile

### Workspace

../budget-analyzer-web

### Goal

Discover direct/lockfile updates and preserve full versus production audit evidence.

### Scope

Renovate npm/Dockerfile/Actions configuration, audit CI and nearest docs.

### Non-goals

No package bumps, audit fixes, lockfile refresh during onboarding, or frontend code.

### Required context

Read local instructions, package manifests/lockfile, Dockerfiles and existing CI,
plus the shared preset and frontend section of the saved review.

### Execution steps

1. Add the preset consumer; enable scheduled lockfile-maintenance PRs and scoped
   React/React DOM and Vitest grouping. Keep toolchain majors visible for approval.
2. Reuse CI dependency installation and add weekly/manual full `npm audit` and
   `npm audit --omit=dev` reports. Preserve JSON output and distinguish audit
   findings from registry/installation errors.
3. Verify Node build-image and workflow-version discovery alongside npm packages.
   Document report access and existing lint/test/CSP/build checks for bot PRs.

### Implementation notes

No `npm audit fix` in onboarding. Reachability and SSR/RSC applicability remain
human triage; do not discard advisories simply because they are development tools.

### Validation

Validate/extract Renovate config, run actionlint and both audit commands against
the existing lockfile. Confirm package and lockfile selections are unchanged and
full/production reports can be compared independently with the review.
If registry installation/audit or GitHub lookups need authentication, record the
affected checks as pending Phase 12 and complete the independent local checks.

### Completion criteria

Bot extraction covers package and runtime sources, workflow validation passes,
and both audit surfaces have usable local evidence or explicit authenticated
checks pending Phase 12. Existing findings remain visible.

## Phase 9: Onboard ext-authz and reachable Go vulnerability checks

### Workspace

../ext-authz

### Goal

Expose Go/module updates and repeat the review's reachable-call security check.

### Scope

Renovate config, `govulncheck` CI and local documentation.

### Non-goals

No module/toolchain upgrades, `go mod tidy` changes, service code or deployment.

### Required context

Read local instructions, `go.mod`, `go.sum`, Dockerfile and CI, plus the shared
preset and the GO-2025-3540 baseline finding.

### Execution steps

1. Add the preset consumer and verify go-redis, other modules, Go directive,
   builder/runtime images and Actions are extracted.
2. Add official `govulncheck ./...` on trusted default-branch changes and a
   weekly/manual schedule; retain readable and machine-readable output. Make the
   scanner version itself a Renovate-managed input.
3. Document findings versus reachable call paths and reuse existing test/build
   checks for bot PRs. If the scanner needs a newer analysis toolchain, distinguish
   that from the declared application toolchain and report any compatibility gap.

### Implementation notes

Module vulnerability presence is not the same as the reachable call reported in
the research. Preserve call-path evidence where the tool can produce it.

### Validation

Validate/extract the config, run actionlint and govulncheck against current source.
Compare GO-2025-3540 or its alias and confirm `go.mod`/`go.sum` are unchanged.
Authenticated module/tool/database access and GitHub lookups are pending Phase 12;
record their scope and complete the available credential-free validation.

### Completion criteria

Module/runtime extraction and local configuration checks pass. Go vulnerability
evidence is recorded where available, with authenticated checks pending Phase 12
and toolchain or reachability limitations explicitly stated.

## Phase 10: Onboard workspace images and installed tooling

### Workspace

../workspace

### Goal

Cover the development environment's image and declared tool versions.

### Scope

Renovate config/annotations, a standard image inventory/scan job and nearest docs.

### Non-goals

No Go architecture fix, runtime upgrades, certificate generation, sandbox changes,
or service edits. The user-owned Node 24 prerequisite is already complete before
this phase starts; this phase must not perform or disguise it as an automated
upgrade. Other runtime changes remain separate work.

### Required context

Read local `AGENTS.md`, `ai-agent-sandbox/Dockerfile`, image build documentation,
and the shared policy. Confirm the plan-wide prerequisite is reflected in the
Dockerfile, nearest runtime documentation, and active container before proceeding.
The Dockerfile uses a digest-only Ubuntu base deliberately.

### Execution steps

1. Add the preset consumer and native Dockerfile extraction. Annotate the existing
   Node 24 major, Go download, Kubernetes/Helm/Tilt and other explicit tool pins
   with supported datasources; preserve architecture and checksum requirements.
2. Prove digest-only Ubuntu updates stay in the selected Ubuntu release family
   without adding a forbidden tag+digest form. If the standard manager cannot do
   this safely, keep the proposal approval-gated and report the limitation.
3. Add a weekly/manual build-and-Trivy scan using the documented context, with no
   image push, live mounts, host credentials or container startup. Record installed
   Node, Go and Zulu package versions where discoverable. Confirm compute/storage
   fits the zero-spend boundary in Phase 12 before enabling this potentially larger
   job; prepare its configuration now without requiring billing/account access.
4. Document that unpinned apt patch updates need fresh rebuilds and scans; a cached
   build is not proof of current packages. Record unsupported package inventory.

### Implementation notes

Use standard tooling only. The app's runtime limits must not be solved by asking
Renovate to build this development image; its CI scan is a separate operation.

### Validation

Verify the Dockerfile, nearest documentation, and active container all report the
Node 24 baseline. Validate configuration/extraction and workflow syntax under that
runtime. Build and scan using the documented safe image build path when
prerequisites are available; inspect exact base digest, installed versions and
ARM64 compatibility evidence. Do not treat an amd64-only image scan as ARM64 proof.
Authenticated image/package downloads and hosted build/scan verification are
pending Phase 12. Record each affected target and complete independent local
validation; do not request a registry login or early CI run.

### Completion criteria

The declared Node 24 pin and other declared pins are discovered, local config and
workflow checks pass, and image/package evidence is recorded where available.
Authenticated checks have explicit Phase 12 handoffs. Digest-only, checksum,
floating apt and current Go-archive architecture limitations are visible.

## Phase 12: Observe activation and compare against the saved review

### Workspace

.

### Goal

Evaluate hosted dependency automation on trial branches before a merge decision,
then verify ongoing activation only if the operator approves promotion.

### Scope

Operator handoff for deferred authentication and branch rehearsal, review of
public/sanitized hosted evidence, billing and storage projections, orchestration
coverage report, and canonical documentation. Authenticated execution remains
outside the agent environment.

### Non-goals

No credentials for agents, agent-authenticated GitHub/Mend/registry access,
agent-performed dispatch/settings/git operations, dependency upgrades or merges,
sibling implementation, releases, or deployment. A successful rehearsal does not
authorize promotion to main.

### Required context

Read the canonical guide, the
[Phase 12 operator plan](dependency-automation-phase-12-operator-plan.md), all
repo-local deferred-check handoffs, phase evidence, and the saved review.
Phases 1–10 must have completed local preparation. The Mend account is created
according to the operator; tier, billing, App scope, and package access are still
unverified.

The revised operator plan supersedes the previous merge-before-testing sequence.
Trial workflow adaptations are additional preparation in each owning repository
context, not implementation for this orchestration phase. Assemble concrete
handoffs before pausing for operator actions; never ask for credentials.
Public output or sanitized exports are the evidence surface when login is needed.

### Execution steps

1. Consolidate every deferred check: repo, command/workflow, package/configuration,
   reason deferred, operator action, expected proof, and disposition. Include
   trial workflow prerequisites and keep them pending until implemented and
   validated in the owning contexts.
2. Have the operator verify current free terms, account controls, visibility,
   existing Maven secret names, current/accrued storage, and separate cache use.
   Record a bounded trial decision. Unknown output sizes may be measured in hosted
   runs with uploads and schedules off after the no-spend boundary is established;
   a complete local scan estimate is no longer a prerequisite for that measurement.
3. Follow the operator plan to publish all implementation on the identically named
   `dependency-automation-trial` branch in all nine repositories, orchestration
   preset first, with explicit trial preset refs. Preserve outgoing
   history hygiene, unrelated work, and each recorded main SHA. No main merge is
   required. Review the exact-ref/event guards, PR build filters, upload caps,
   retention, and disabled schedule/submission gates before execution.
4. Review the hosted read-only full Renovate dry run with GitHub's ephemeral
   read-permission job token and explicit trial configuration selection. Verify
   source/base/preset SHAs, extraction, authenticated lookups where supported,
   mutation simulation, and all errors. A checkout ref or orchestration-only dry
   run does not prove consumer configuration, Maven graphs, or App behavior.
5. Review complete branch build/scanner measurements and controlled artifact
   uploads. Include implicit graph artifacts, existing bot-PR JAR/test/frontend
   outputs, cache use, and failure-path output. Replace estimates with actual
   artifact bytes, project intended retention and PR volume, and reconcile
   refreshed billing. Missing detailed output remains an evidence gap.
6. Record the operator's trial mode. If main remains default, report branch
   results with default-only cron/onboarding/alert checks pending. For a full
   rehearsal, the operator audits default-branch effects and temporarily makes
   protected trial branches default, orchestration first. Verify unchanged main
   SHAs and trial-ref guards; only the operator changes settings or installs the
   App. Expand App scope only after the orchestration pilot passes.
7. In the full rehearsal, require complete remotely resolved application/runtime/
   test graphs and accepted GitHub submissions for all five Java repos on their
   actual trusted trial defaults. Use existing scoped package-read secrets and
   separate submission tokens. Verify internal coordinates and inherited
   Spring/Jackson/Tomcat/Netty dependencies as applicable, plus graph-backed alerts.
   Preflights, partial snapshots, or another repo's graph do not satisfy this.
8. Require complete scanner reports, real bot-PR checks/package access, two
   successful Mend cycles per repo, and one actual scheduled cycle per scheduled
   scanner and Java graph workflow. Record source refs, timestamps, tool/database
   versions, bytes, duration, and queueing. Do not count skipped/manual jobs as
   scheduled acceptance or hide authentication, timeout, and registry failures.
9. Apply the operator plan's stop/restore procedure before the merge decision:
   pause App/jobs, preserve evidence, restore original defaults/settings, verify
   main SHAs, and record residual repo-wide state. Report trial acceptance,
   ongoing installation, and benchmark parity separately. A paused trial leaves
   ongoing installation pending, even when all trial checks passed.
10. Complete the historical comparison with reproduced, superseded by a newer
    applicable finding, false positive with evidence, or missing classifications.
    Keep maintained-line patches visible alongside major proposals. Record
    workspace Node 24 as an operator-applied prerequisite, not bot discovery.
    Preserve known image inventory, offline Istio, checksum, and ARM64 limits.
11. Prepare a concrete promotion recommendation and diff based on measured
    billing/storage, resource limits, coverage, and PR behavior. The operator
    chooses GO, NO-GO, or DEFER. Without promotion approval, leave implementation
    on branches and record activation as deferred; do not claim Phase 12's
    ongoing-installation acceptance is complete.
12. After an explicit GO, the operator publishes the final shared preset before
    consumers, removes trial-only wiring through reviewed changes, restores the
    intended retention, and reactivates deliberately. Verify changed refs/config
    and main-push paths with fresh evidence, including final graph acceptance,
    App/PR behavior and scheduled runs. Update canonical operating docs only from
    verified behavior; leave saved research, archives, and ADRs unchanged.

### Implementation notes

Do not edit this executable plan while a runner uses its snapshot; record results
in the coverage report. Each sibling implementation handoff belongs in that repo's
context. Branches are not account/billing or credential isolation. Restoring
defaults does not delete alerts, issues, artifacts, caches, or accrued usage.
A missing operator decision requires a concrete handoff, never a token request.

### Validation

Reconcile every deferred check and baseline row with source-ref-aware evidence.
Check the explicit preset resolution, unchanged main SHAs during trial, complete
Java graphs and accepted submissions, real PR checks, actual scheduled events,
artifact/cache accounting, billing controls, and rollback ledger.
Check links and the historical review hash. Distinguish branch evidence, full
rehearsal, and final activation; none automatically substitutes for the next.
Authentication failures and pending runs cannot be relabeled as tool limitations
to claim completion.

### Completion criteria

Trial assessment is ready for the operator's decision when its selected mode's
checks, cost measurements, benchmark comparison, and restore procedure have
evidence, with remaining default-only checks explicit. This is a decision
checkpoint, not automatic ongoing activation.

Phase 12's ongoing-installation objective is complete only after approved
promotion and successful final hosted evidence across all scoped repositories,
including every deferred authenticated operational check. No credentials were
supplied to agents. If promotion is declined or deferred, report that disposition
and leave ongoing activation unclaimed. Full review parity is claimed only when
all high-priority findings are reproduced or superseded with evidence; otherwise
report partial coverage. Lifecycle and exploitability assessment remain human work.
