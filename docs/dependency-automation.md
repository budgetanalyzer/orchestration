# Dependency Automation

**Status:** Active dependency-automation policy

This document owns the dependency-automation operating policy for the Budget
Analyzer repositories. The shared Renovate policy lives in
[`renovate-presets/default.json`](../renovate-presets/default.json), while each
repository owns its extraction rules and workflows. The archived
[Dependency Notification Guide](archive/dependency-notifications.md) is
historical context; its observed versions are not update targets.

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
- digest updates retain digest pinning, while first-party production-reference
  images remain outside automatic promotion; and
- generated outputs, historical material, local images, and retained stale
  test suites remain outside update ownership.

The retired OCI lean archive under `archive/oci/` is historical material. The
shared preset excludes it from dependency discovery in both this repository
and any repository that reuses the preset. Renovate must not refresh archived
versions, digests, Helm values, Actions references, or copied scripts. General
secret detection remains applicable to the archive; retirement is not a
secret-scanning exception. Archive and complete-tree Git provenance,
inventory, and restoration caveats live in
[archive/oci/README.md](../archive/oci/README.md).

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
The API-tests repository additionally owns `pip-audit`, CycloneDX SBOM, and
exact locked-graph parity evidence for its selected Python environment.

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

The active dependency-automation scope contains ten repositories: `orchestration`,
`service-common`, `currency-service`, `permission-service`,
`transaction-service`, `session-gateway`, `budget-analyzer-web`, `ext-authz`,
`workspace`, and `budget-analyzer-api-tests`.

Orchestration owns the shared preset and its own extraction for Kubernetes,
Helm values, Tilt, Kind, shell version contracts, pinned tools, chart image
overrides, the exact-image scanner, and the bounded PyYAML input used only by
the ingress rate-limit static proof. Consumer repositories own their native
package managers and any repository-specific extraction:

| Repository family | Repository-owned coverage |
| --- | --- |
| Java library and services | Gradle/version catalogs, wrapper, Actions, Dockerfiles, complete resolved dependency submission |
| Frontend | npm manifest and lockfile, Dockerfiles, Actions, full and production-only npm audit |
| `ext-authz` | Go modules, Go/runtime declarations, Dockerfiles, Actions, reachable `govulncheck` |
| `workspace` | Native npm manifest and lock, downloaded-tool declarations with standard datasources, Actions, and version/URL/checksum/architecture-coupled inputs |
| `budget-analyzer-api-tests` | Bounded PEP 621 requirements, Python/runtime and tool pins, exact uv lock, Actions, frozen CI, lock maintenance, and complete parity/SBOM/audit evidence |

The four Java consumers must continue to exclude `org.budgetanalyzer` from
Maven Central while preserving Maven Local for local development and the
authenticated `service-common` GitHub Packages repository for hosted builds.
Workspace uses Renovate's npm manager for `native/npm/package.json` and its
lockfile. It uses declarative custom extraction only for pinned native tools
that Renovate can identify through a sound standard datasource. A proposal for
one of those tools is discovery, not approval to change one field in isolation:
review the version, release URLs, SHA-256 values for every supported
architecture, validation patterns, and any linked native npm inputs together.
These coupled proposals remain Dependency Dashboard approval-gated. Inputs
without a sound standard datasource remain explicit manual lifecycle review
items; do not add a custom crawler or pretend they are covered.

### Bounded orchestration PyYAML tool dependency

`scripts/guardrails/requirements-ingress-rate-limit.txt` is a one-package
static-tool contract, not a Python application environment. It pins the exact
PyYAML version and only the reviewed upstream Linux x86_64 CPython 3.12 wheel
hash used by `security-guardrails.yml`; source distributions and implicit
source builds are outside the contract. The workflow creates a disposable
private virtual environment under `.cache/phase7-static-tools`, installs with
pip hash enforcement and no dependencies, proves the imported module is inside
that environment, and does not upload the environment as evidence.

Renovate's native `pip_requirements` manager owns version discovery for this
input. Every proposal remains non-automerge and requires Dependency Dashboard
approval. Reviewers must update the exact version and all accepted wheel hashes
together, verify each hash against the upstream PyPI release metadata, confirm
the wheel still matches the hosted runner's declared Python/platform contract,
and rerun the static guardrails. Do not add an sdist merely to make a new
runtime installable, and do not move this package into the standalone-binary
installer. This bounded input is intentionally distinct from the
`budget-analyzer-api-tests` PEP 621, uv lock, SBOM, audit, and parity contract.

The workspace manifest describes a native Ubuntu VM, not a container image.
Ubuntu VM lifecycle and installed apt patching remain human/distribution owned;
the provisioner retains installed packages rather than upgrading them.
NodeSource and Azul signed apt repositories select the available Node and JDK
patches when installation is required. VIA remains manual because its required
archive and standalone-asset checksum records do not have a suitable standard
release feed. Repository validation cannot attest to the mutable packages or
other installed state of the dedicated development VM.

## Active Python consumer: `budget-analyzer-api-tests`

**Activation status:** Active. The repository-local
[dependency-automation guide](https://github.com/budgetanalyzer/budget-analyzer-api-tests/blob/main/docs/dependency-automation.md)
and [dependency contract](https://github.com/budgetanalyzer/budget-analyzer-api-tests/blob/main/docs/dependency-contract.md)
own exact versions, commands, workflow paths, and artifact filenames. This
section owns the shared ecosystem policy.

The Python contract has these layers:

- `pyproject.toml` remains authoritative for direct runtime, build,
  development, and test compatibility. Every direct registry requirement has
  an intentional PEP 440 lower bound and breaking-change upper boundary, or an
  exact pin when no credible compatibility interval exists.
- `.python-version` selects the supported Python patch release, while the PEP
  621 `requires-python` interval describes the matching supported minor line.
  Changes to either declaration must keep those contracts consistent.
- The machine-generated `uv.lock` is the exact direct and transitive graph,
  including versions, sources, markers, artifacts, and integrity hashes for
  the supported runtime. Never edit it manually or accept an unexpected VCS,
  URL, path, editable, or nonstandard-index source.
- Normal local and hosted installs synchronize all selected groups from the
  checked-in graph in frozen mode. A stale manifest/lock pair must fail rather
  than refresh as an incidental side effect. The editable first-party package,
  isolated `uv` bootstrap, and isolated `pip-audit` scanner remain explicitly
  separate from the selected third-party graph.
- Successful evidence proves normalized package-name and exact-version parity
  among the current-platform lock selection, frozen installed inventory,
  `pip-audit` dependency records, and CycloneDX SBOM components. Missing,
  extra, duplicate, malformed, or version-mismatched records are operational
  failures, not clean evidence.
- Playwright's Python distribution owns its coupled browser revision. Evidence
  records derived browser metadata and that no browser was installed; it does
  not introduce an independently updated browser version.

The repository's deterministic CI owns frozen synchronization, dependency
contract and parity validation, unit tests, credential-free test collection,
formatting, linting, and type checking. Its dependency-evidence workflow owns
the locked inventory, dependency tree, SBOM, audit, parity, diagnostics, and
completion evidence. Neither workflow may install Chromium, contact a Budget
Analyzer deployment, provision browser identities, or consume application
credentials. The live `./run-tests` suite remains a separate regression gate
with its documented local prerequisites.

Renovate is the sole update-pull-request owner for:

- bounded PEP 621 requirements and repository-owned build, development, and
  test groups in `pyproject.toml`;
- the exact Python runtime declaration and isolated `uv` and `pip-audit` tool
  pins;
- GitHub Actions references; and
- manifest-driven `uv.lock` refreshes plus explicit lock-file maintenance for
  selected transitive versions.

Use Renovate's native PEP 621, uv, Python-version, and GitHub Actions support
where it models the declaration. Keep any narrow extraction needed for the
repository's tool-pin representation, all manager enablement, grouping, and
Python-specific pull-request notes in the consumer configuration. Every bot
branch that changes a manifest or performs lock-file maintenance must
regenerate the complete lock with the repository's pinned `uv` contract and
pass frozen parity checks. A partial lock refresh or failed bot lock update is
a failed proposal. The shared weekly schedule, automerge prohibition,
major-update approval, and pull-request limits apply without a Python-specific
shared-preset rule.

## Production workflow matrix

The workflow files are the executable source of truth for exact paths,
schedules, permissions, and concurrency. This matrix records the durable event
and evidence shape for the ten active production repositories:

| Owner | Workflow | Production events | Durable result |
| --- | --- | --- | --- |
| `orchestration` | Dependency Automation Configuration | Relevant pushes and pull requests on `main`; manual dispatch | Strict validation of the repository config and shared preset under Node 24 |
| `orchestration` | Exact Image Security Evidence | Pushes to `main`; weekly schedule; manual dispatch | Offline render, exact platform resolution, Trivy inventory and vulnerability evidence |
| `service-common` | Dependency Submission | Trusted `main` events, weekly schedule, and manual dispatch as declared by the workflow | Complete resolved Gradle graph submitted with job-scoped `contents: write` |
| Four deployable Java services | Dependency Submission | Trusted `main` events, weekly schedule, and manual dispatch as declared by each workflow | Complete Gradle-resolved application/runtime/test graph submission using package-read credentials |
| `budget-analyzer-web` | Dependency Audit | Weekly schedule and manual dispatch on `main` | Full and production-only npm audit reports |
| `ext-authz` | Go Vulnerability Check | Pushes to `main`; weekly schedule; manual dispatch | Reachability-aware text and JSON `govulncheck` reports |
| `workspace` | Native dependency evidence | Pushes to `main`; same-repository pull requests targeting `main`; weekly schedule; manual dispatch | Native manifest validation, npm lock-closure and dependency-audit reports, checksum verification against declared public release downloads, and an explicit manual-lifecycle inventory |
| `budget-analyzer-api-tests` | CI | Pushes to `main`; pull requests targeting `main`; manual dispatch | Frozen all-groups synchronization and deterministic dependency, test-collection, formatting, lint, and type checks without browser installation or application access |
| `budget-analyzer-api-tests` | Python Dependency Evidence | Relevant trusted pushes to `main`; weekly schedule; manual dispatch | Exact locked-graph inventory, dependency tree, CycloneDX SBOM, `pip-audit`, Playwright-derived metadata, and cross-representation parity evidence |

Build workflows continue to validate Renovate pull requests through their
normal `main` pull-request events. Keep scheduled workflows least-privileged.
Java dependency submission alone receives job-scoped `contents: write`; package
reads use the existing package credential pair rather than the submission job
token. Scanner and validation workflows remain read-only. Workspace's native
evidence workflow must declare read-only token permissions; it must not run the
provisioner, install packages, mutate a VM, or use private release credentials.
It may read repository inputs and download only the public release assets
needed to verify the checked-in declarations.

Vulnerability findings are visible but non-gating unless an owning repository
defines a stricter policy. Malformed output, failed dependency resolution,
failed graph submission, failed database download, malformed native manifests,
incomplete npm lock closure, missing or mismatched release checksums, incomplete
inventory, platform mismatch, and incomplete scans remain workflow failures.

## Evidence artifact contract

Each scanner or native dependency-evidence workflow uploads its declared
evidence paths directly as exactly one bounded GitHub Actions artifact with
normal upload-action compression and seven-day retention. Keep the upload step
under `if: always()` so a failed check retains the diagnostics produced before
failure, and keep `if-no-files-found: error` so a run cannot silently omit all
evidence.

The allowlist is the successful-run contract. Every declared path and required
output must be present when its workflow succeeds; incomplete successful-run
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
- workspace includes native manifest and npm lock validation status, the full
  and production-only npm dependency-audit reports, per-platform public-release
  checksum results, the explicit manual-lifecycle inventory, diagnostics, and
  overall completion status; and
- `budget-analyzer-api-tests` includes bootstrap and scanner diagnostics,
  metadata, the hashed frozen lock export and platform selection, installed
  inventory and dependency tree, Playwright-derived browser metadata, JSON and
  text `pip-audit` records and status, a CycloneDX SBOM, and exact parity and
  completion records.

The Python workflow must enforce its repository-owned exact file allowlist,
reject undeclared or incomplete successful output, upload bounded diagnostics
under `always()`, and fail when no evidence files exist. Vulnerability findings
remain non-gating only when scanner output is complete and valid. Malformed or
incomplete resolution, inventory, SBOM, audit, parity, or completion evidence
remains gating. The artifact must not contain browser binaries, caches,
credentials, cookies, application secrets, or unrelated workspace files.

Do not add caches, image layers, unrelated workspace files, or credentials to
an evidence artifact. When changing an allowlist, update the workflow's upload
paths, verify the complete successful-run artifact, and preserve all outputs
needed to distinguish findings from operational failure.

Workspace's hosted evidence proves only that checked-in native declarations
are structurally consistent, the npm lock is closed, declared public assets
match reviewed checksums, and dependency audits completed. It is not a scan of
the live development VM, does not report its installed apt package versions,
and does not upgrade them. Update discovery, checksum verification, dependency
vulnerability evidence, and human OS/tool lifecycle review are separate
controls; none substitutes for another.

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
target. Scope Mend to the ten repositories above, let it follow each default
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

### API-tests activation record and hosted graph boundary

Activation was accepted for published revision
[`45aa5835fb5acda29d51f252a116fe2d33b693ce`](https://github.com/budgetanalyzer/budget-analyzer-api-tests/commit/45aa5835fb5acda29d51f252a116fe2d33b693ce).
Public corroboration includes the successful
[CI run](https://github.com/budgetanalyzer/budget-analyzer-api-tests/actions/runs/38258164820),
[Python Dependency Evidence run](https://github.com/budgetanalyzer/budget-analyzer-api-tests/actions/runs/38258164896),
native uv graph-update run, and open
[Dependency Dashboard](https://github.com/budgetanalyzer/budget-analyzer-api-tests/issues/4).
The supervising administrator also confirmed that the hosted Mend job
succeeded, the GitHub dependency graph is populated, Dependabot alerts are
enabled, and Dependabot version updates and automatic security-update pull
requests remain disabled.

A populated GitHub dependency graph does not by itself prove complete native
ingestion of every universal `uv.lock` marker and platform selection. Do not
claim complete hosted graph coverage from that view. The repository-owned
frozen inventory, CycloneDX SBOM, `pip-audit` records, and exact parity checks
remain the complete selected-environment evidence. A separate reviewed
dependency-submission design is required before claiming broader hosted graph
coverage.

## Operator routine

Every week:

1. Review every Dependency Dashboard, new Renovate pull request, and lookup,
   authentication, queue, timeout, or rate-limit error.
2. Review Dependabot alerts separately from update proposals. Map an alert to
   the resolved package and configuration or image; a pull request does not
   prove advisory detection.
3. Check the latest dependency-submission, scanner, native dependency-evidence,
   Python frozen-CI, and Python dependency-evidence runs. For API tests, require
   the selected lock graph, installed inventory, audit records, and SBOM to
   retain exact name/version parity. Treat missing or partial reports as
   operational failures, not clean results.
4. Review bot-branch checks and package or registry access without moving
   secrets into untrusted pull-request execution.
5. Confirm Renovate is still the sole update-PR owner, automerge is off, the
   first-party release path is untouched, and Actions/storage usage remains
   within the approved free boundary.

Every quarter, compare Spring, Node, Go, Java, Python, Ubuntu, Kubernetes,
Istio, RabbitMQ, NGINX, and other runtime lines with upstream support policies.
Renovate discovery, abandonment heuristics, and vulnerability databases are
not comprehensive end-of-life authorities.

For workspace, include every manual-lifecycle manifest input in that review,
including VIA, and separately review Ubuntu VM lifecycle and available apt
maintenance. Hosted repository evidence does not establish the patch or
support state of the installed guest.

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
- **Native workspace evidence failure:** distinguish malformed manifest data,
  incomplete npm lock closure, audit findings, unavailable public release
  assets, checksum or architecture mismatch, and incomplete manual-lifecycle
  inventory. Do not run the provisioner or treat the installed VM as evidence.
- **Stale Python lock or incomplete resolution:** distinguish an intentional
  manifest change from a missing lock refresh, unsatisfied bound, absent group,
  incomplete transitive closure, or failed artifact/hash selection. Regenerate
  only through the pinned repository workflow; never make a frozen install
  update the lock or edit the lock manually.
- **Python marker or platform mismatch:** compare the pinned runtime, PEP 621
  Python interval, lock markers, current-platform selection, and hosted runner.
  Do not drop a marked dependency merely because it is absent on one platform,
  and do not claim universal coverage from one installed selection.
- **Python index or source drift:** fail on inherited index overrides and
  unexpected registry, VCS, URL, path, or editable sources. Preserve source
  diagnostics without persisting package credentials; do not normalize an
  alternate source into an accepted PyPI record.
- **Python graph or evidence mismatch:** compare normalized names and exact
  versions across the selected lock graph, installed inventory, audit records,
  and SBOM. Treat missing Playwright metadata, audit/SBOM components, scanner
  completion, or parity records as incomplete evidence rather than zero
  findings.
- **Python bot lock-update failure:** inspect Renovate extraction, bounded
  requirements, the pinned Python and `uv` versions, package availability,
  source policy, and lock-maintenance logs. Do not merge a manifest-only
  update, hand-edit the lock, relax frozen checks, or disable a dependency to
  make the branch green.
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
