# Dependency Automation

**Status:** Active production policy

This document owns the dependency-automation operating policy for the Budget
Analyzer repositories. The shared Renovate policy lives in
[`renovate-presets/default.json`](../renovate-presets/default.json), while each
repository owns its extraction rules and workflows. The preserved
[September 6 dependency review](research/dependency-update-review-2026-09-06.md)
is a point-in-time benchmark; its observed versions are not update targets.

## Ownership and update policy

Renovate is the only service allowed to open dependency-update pull requests.
Keep GitHub's dependency graph and Dependabot alerts enabled, but keep
Dependabot version updates and automatic Dependabot security-update pull
requests disabled. Never enable automerge, including for vulnerability fixes.

Every scoped repository extends the normal default-branch preset:

```json
{
  "extends": [
    "github>budgetanalyzer/orchestration//renovate-presets/default"
  ]
}
```

The shared preset provides these controls:

- routine updates run weekly, with at most three open routine pull requests
  and two new routine pull requests per hour in one repository;
- vulnerability fixes may run at any time, use a separate three-pull-request
  concurrency limit, and remain non-automerge;
- patch, minor, and major proposals remain distinguishable;
- major, Helm, stateful, platform, chart-image override, and
  checksum-coupled updates require Dependency Dashboard approval;
- digest updates retain digest pinning, and first-party production image
  promotion remains owned by the existing release process; and
- generated outputs, historical material, local images, and retained stale
  test suites remain outside update ownership.

Review every image or platform proposal for Linux ARM64 support. A registry tag
or new digest does not prove platform support, the embedded application
version, vulnerability remediation, or upstream support status. For
checksum-coupled tools, update and verify the complete supported-platform
checksum table; never weaken checksum validation to accept a proposal.

Use native Renovate managers first. Keep nonstandard path matching, adjacent
annotations, and declarative regex managers in the repository that owns the
declaration. Do not add a custom crawler or seed a historical expected version
to make discovery appear complete.

## Service and cost boundary

Use the open-source Renovate engine through the free Mend Renovate Community
GitHub App. Do not add a payment method, paid Mend feature, paid expansion,
self-hosted Renovate service, or separate bot infrastructure without a new
explicit architecture and cost decision. The selected supporting tools remain
GitHub dependency graph and Dependabot alerts, Gradle's open-source basic
dependency-submission path, Trivy, `npm audit`, and `govulncheck`.

GitHub Actions usage and the shared Actions-artifact/GitHub-Packages storage
allowance are separate from Mend hosting. Keep production evidence bounded and
short-lived. Do not trim findings, targets, inventories, or logs to fit a
storage limit; an incomplete artifact is an evidence-delivery failure.

The regular-CI artifact contracts are intentionally different from scanner
evidence:

- `currency-service`, `permission-service`, `transaction-service`, and
  `session-gateway` upload no `app-jar`. They retain only JUnit XML after a
  failed build, for one day. Their release workflows build deployable images
  from source and do not consume regular-CI JAR artifacts.
- `service-common` retains its package/library JAR and test artifacts because
  those belong to the library build contract.
- `budget-analyzer-web` retains its normal `dist` build artifact.
- dependency scanner artifacts retain for seven days under the evidence
  contract below.

Review Actions and package storage periodically. A quota rejection is a failed
operation, not authority to buy capacity, remove evidence, or weaken a scan.

## Configuration and repository ownership

The production scope is `orchestration`, `service-common`, `currency-service`,
`permission-service`, `transaction-service`, `session-gateway`,
`budget-analyzer-web`, `ext-authz`, and `workspace`.

Orchestration owns the shared preset and its own extraction for Kubernetes,
Helm values, Tilt, Kind, shell version contracts, pinned tools, chart image
overrides, and the exact-image scanner. Consumer repositories own their native
package managers and any repository-specific extraction:

| Repository family | Repository-owned coverage |
| --- | --- |
| Java library and services | Gradle/version catalogs, wrapper, Actions, Dockerfiles, complete resolved dependency submission |
| Frontend | npm manifest and lockfile, Dockerfiles, Actions, full and production-only npm audit |
| `ext-authz` | Go modules, Go/runtime declarations, Dockerfiles, Actions, reachable `govulncheck` |
| `workspace` | Dockerfile bases and arguments, downloaded tools, Actions, checksum-coupled tools, built-image scanning |

The four Java consumers must continue to exclude `org.budgetanalyzer` from
Maven Central while preserving Maven Local for local development and the
authenticated `service-common` GitHub Packages repository for hosted builds.
The workspace must retain its public `git-tags` fallback for
`aquasecurity/setup-trivy` and its digest-only Ubuntu extraction rule.

## Production workflow matrix

The workflow files are the executable source of truth for exact paths,
schedules, permissions, and concurrency. This matrix records the durable event
and evidence shape:

| Owner | Workflow | Production events | Durable result |
| --- | --- | --- | --- |
| `orchestration` | Dependency Automation Configuration | Relevant pushes and pull requests on `main`; manual dispatch | Strict validation of the repository config and shared preset under Node 24 |
| `orchestration` | Exact Image Security Evidence | Pushes to `main`; weekly schedule; manual dispatch | Offline render, exact platform resolution, Trivy inventory and vulnerability evidence |
| `service-common` | Dependency Submission | Trusted `main` events, weekly schedule, and manual dispatch as declared by the workflow | Complete resolved Gradle graph submitted with job-scoped `contents: write` |
| Four deployable Java services | Dependency Submission | Trusted `main` events, weekly schedule, and manual dispatch as declared by each workflow | Complete Gradle-resolved application/runtime/test graph submission using package-read credentials |
| `budget-analyzer-web` | Dependency Audit | Weekly schedule and manual dispatch on `main` | Full and production-only npm audit reports |
| `ext-authz` | Go Vulnerability Check | Pushes to `main`; weekly schedule; manual dispatch | Reachability-aware text and JSON `govulncheck` reports |
| `workspace` | Workspace Image Security Evidence | Pushes to `main`; same-repository pull requests targeting `main`; weekly schedule; manual dispatch | No-start/no-push image build, package inventory, and vulnerability scan |

Build workflows continue to validate Renovate pull requests through their
normal `main` pull-request events. Keep scheduled workflows least-privileged.
Java dependency submission alone receives job-scoped `contents: write`; package
reads use the existing package credential pair rather than the submission job
token. Scanner and validation workflows remain read-only.

Vulnerability findings are visible but non-gating unless an owning repository
defines a stricter policy. Malformed output, failed dependency resolution,
failed graph submission, failed database download, incomplete inventory,
platform mismatch, and incomplete scans remain workflow failures.

## Evidence artifact contract

Each scanner workflow uploads its declared evidence paths directly as exactly
one GitHub Actions artifact with normal upload-action compression and seven-day
retention. Keep the upload step under `if: always()` so a failed scan retains
the diagnostics produced before failure, and keep `if-no-files-found: error` so
a run cannot silently omit all evidence.

The allowlist is the successful-run contract. Every declared path and required
output must be present when scanning succeeds; incomplete successful-run
evidence is a workflow failure. A failed run may upload only the diagnostic
paths created before the original failure, and that upload must not turn the
failed run into a success.

The allowlists are semantic contracts, with exact paths declared in each
workflow's upload step:

- orchestration includes rendered inputs, target maps and completion status,
  scanner/database metadata, and every per-target package inventory and
  vulnerability report;
- the frontend includes audit status and diagnostics plus both full-tree and
  production-only audit reports;
- `ext-authz` includes scanner metadata and both human-readable and JSON
  reachable-vulnerability reports; and
- workspace includes build metadata/logs, the exact built-image identity,
  scanner/database metadata, package inventory, vulnerability report, and
  required-tool inventory.

Do not add caches, image layers, unrelated workspace files, or credentials to
an evidence artifact. When changing an allowlist, update the workflow's upload
paths, verify the complete successful-run artifact, and preserve all outputs
needed to distinguish findings from operational failure.

## Exact-image security evidence

Orchestration's exact-image workflow calls
`scripts/security/render-image-scan-inputs.sh`. It renders the production app
and infrastructure overlays plus the selected controller charts from their
checked-in values and version contracts, without requiring a Kubernetes API.
It covers rendered third-party controllers, hooks, infrastructure images,
Kind, Tilt runtime bases, and the frontend production-smoke base. First-party
service images stay under their release workflows.

Production and controller images resolve and scan as `linux/arm64`.
Local-only sources use the scanner runner's platform. Each target records its
source files, declared ref, registry manifest, selected platform digest, all
packages, vulnerabilities, scanner metadata, and completion state. Mutable
rendered tags remain labelled mutable even though one exact digest is scanned
for that run.

Known representation limits remain explicit. A chart may render a tag even
when a checked-in value carries a digest, and the Istio gateway chart renders
`image: auto`, which only a live injector resolves. Record that gateway as
offline-unscannable; do not invent an image or add a live-cluster dependency.
Trivy inventory also is not proof of an embedded product's support lifecycle or
exact primary application patch.

## GitHub and Mend settings

Keep `main` as every repository's default branch and normal protected merge
target. Scope Mend to the nine repositories above, let it follow each default
branch, and do not configure a separate base branch. Use Scan and Alert behavior
with automerge disabled.

For every scoped repository:

1. Enable the GitHub dependency graph and Dependabot alerts.
2. Disable Dependabot version updates and automatic security-update pull
   requests so Renovate remains the sole update-PR owner.
3. Grant only the permissions needed by the checked workflows and Mend alert
   integration.
4. Keep credentials in GitHub Secrets or Mend's supported encrypted settings;
   never commit them or expose them through `pull_request_target`.

The Maven host rule must be scoped exactly to
`https://maven.pkg.github.com/budgetanalyzer/service-common/`. Use the existing
package-read identity and token in Mend's encrypted settings only if the App's
platform token cannot read that package. Do not document credential values or
broaden the rule to all GitHub Packages hosts.

## Operator routine

Every week:

1. Review every Dependency Dashboard, new Renovate pull request, and lookup,
   authentication, queue, timeout, or rate-limit error.
2. Review Dependabot alerts separately from update proposals. Map an alert to
   the resolved package and configuration or image; a pull request does not
   prove advisory detection.
3. Check the latest dependency-submission and scanner runs. Treat missing or
   partial reports as operational failures, not clean results.
4. Review bot-branch checks and package or registry access without moving
   secrets into untrusted pull-request execution.
5. Confirm Renovate is still the sole update-PR owner, automerge is off, the
   first-party release path is untouched, and Actions/storage usage remains
   within the approved free boundary.

Every quarter, compare Spring, Node, Go, Java, Ubuntu, Kubernetes/K3s, Istio,
RabbitMQ, NGINX, and other runtime lines with upstream support policies.
Renovate discovery, abandonment heuristics, and vulnerability databases are
not comprehensive end-of-life authorities.

## Failure triage

- **Configuration error:** reproduce with the pinned strict validator and
  correct the preset or repository config. Treat warnings and migrations as
  failures.
- **No extraction:** inspect the native manager pattern or adjacent annotation
  and debug output. Do not copy a historical target into configuration.
- **No lookup or wrong package:** verify the datasource identity, registry or
  chart URL, tag prefix, suffix, and flavor. Preserve unresolved standard-tool
  gaps instead of adding a custom crawler.
- **Authentication or resolution failure:** preserve the error and fix the
  encrypted package or registry setting in its owning system. Never use Maven
  Local as proof of hosted resolution, drop internal dependencies, or swallow
  the failure.
- **Finding without an update:** retain and route the finding to the owning
  service; advisory detection and update discovery are separate outcomes.
- **Bot-branch CI failure:** review checksums, chart rendering, ARM64 support,
  state migration, and cross-repository companions. Do not relax a guardrail.
- **Scanner or graph failure:** distinguish findings from failed download,
  resolution, generation, submission, inventory, or report production. Never
  turn unavailable evidence into a clean result.

## Validation and changes

Before changing Renovate configuration, workflow events, permissions,
credentials, evidence allowlists, retention, or Mend settings, read this guide
and the owning repository's instructions. Validate the changed repository with
its pinned strict Renovate validator, `actionlint`, and required checks for any
changed scripts. Keep workflows on the repository's Node 24-ready action
baseline.

Run the strict validator command from
`.github/workflows/dependency-automation-config.yml` so the checked-in pinned
version remains the source of truth. Run `actionlint` on that workflow and
`.github/workflows/exact-image-security-evidence.yml` after workflow changes.
