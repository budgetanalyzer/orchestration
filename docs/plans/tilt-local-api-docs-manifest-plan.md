# Tilt Local API Docs Runtime Manifest Plan

Make the `/api-docs` "Runtime Manifest" section in local Tilt describe the
local checkouts Tilt actually built, instead of re-rendering the retired OCI
reference rows. The Tilt view becomes purely local: no production reference id,
no GHCR digests, no reference tags. The production overlay page and its
checked-in reference metadata stay unchanged.

Current state, verified 2026-10-27:

- `Tiltfile:261-376` copies
  `kubernetes/production/docs-aggregator/release-metadata.json` into
  `.tilt/api-docs/release-metadata.json`, rewrites `deployment` with a
  `productionReferenceId`, and adds a per-artifact `localSource` block.
- `docs-aggregator/swagger-initializer.js` renders the reference rows
  (`v0.0.15` refs, GHCR digests, service-common `0.0.14`) and uses
  `localSource` only to tint dirty rows. The Orchestration fact renders
  `unknown` in Tilt.
- Tilt publishes `../service-common` to Maven Local (`service-common-publish`),
  and Spring services resolve `mavenLocal()` first. A service whose
  `gradle/libs.versions.toml` `serviceCommon` equals the local service-common
  `build.gradle.kts` `version` is therefore built from the local service-common
  working tree.
- `nginx-gateway` copies the docs ConfigMap in an init container, so the page
  reflects the metadata present when the `nginx-gateway` pod last started.

Target local view:

- Header facts: Environment `local-development`, Orchestration
  (version, short commit, dirty), Shared library (service-common version,
  local describe, short commit, dirty).
- Table rows, in order: `transaction-service`, `currency-service`,
  `permission-service`, `session-gateway`, `budget-analyzer-web`, `ext-authz`.
- Table columns: Repository, Version, Commit, Branch, Committed, Shared library.
- Version is derived from `git describe --tags --long`: `v0.1.0` at a tag,
  `v0.1.0+3` for three commits after the nearest reachable tag, `untagged`
  with no reachable tag. Dirty state is shown separately and tints the row.
- Shared library is `n/a` for repos with no `serviceCommon` declaration.
  Otherwise it shows the declared version and whether it matches the local
  service-common checkout, for example `0.1.0 (local checkout)` or
  `0.0.14 (not local; checkout is 0.1.0)`.
- The section states that values are captured at Tilt start. No live refresh,
  no live image tags, no generated-at timestamp (a timestamp would rewrite the
  file on every Tiltfile evaluation and defeat the write-if-changed guard).

Constraints:

- Do not modify `kubernetes/production/docs-aggregator/release-metadata.json`,
  `docs-aggregator/release-metadata.json`, the production deployment manifest,
  image inventory, or runtime metadata patch.
- `docs-aggregator/{index.html,swagger-initializer.js,swagger-ui-overrides.css}`
  must stay byte-identical to their `kubernetes/production/docs-aggregator/`
  copies; the production overlay consumes those copies.
- The production page must render exactly as it does today.
- Read-only git commands only against sibling repos. Do not write to sibling
  repos.
- Render all metadata values through `textContent`; never `innerHTML`.
- Do not edit `docs/archive/`, `docs/decisions/`, or `archive/oci/`.
- Follow `AGENTS.md` shell validation, path portability, and git write rules.

## Phase 1: Local Metadata Generator

### Workspace

.

### Goal

Replace the inline Tiltfile Python with a standalone, stdlib-only generator
that produces purely local metadata from git and Gradle version files, and keep
the offline production-reference guardrail passing.

### Scope

- New `scripts/repo/generate-local-api-docs-metadata.py`.
- `Tiltfile` metadata generation block.
- Tilt-related assertions in `scripts/guardrails/verify-production-image-overlay.sh`.

### Non-goals

- Page rendering, HTML, CSS, or JavaScript changes.
- README or other documentation updates beyond what is required for the
  guardrail to pass.
- Any change to production reference metadata.

### Required context

- `AGENTS.md` (path portability, shell validation, cross-repo boundaries)
- `Tiltfile` lines around `LOCAL_API_DOCS_RELEASE_METADATA` and
  `service-common-publish`
- `scripts/guardrails/verify-production-image-overlay.sh`
  (`verify_reference_metadata_contract`)
- `docs-aggregator/README.md`
- `../service-common/build.gradle.kts` (`version = "..."`) and
  `../transaction-service/gradle/libs.versions.toml` (`serviceCommon`), read-only

### Execution steps

1. Create `scripts/repo/generate-local-api-docs-metadata.py`, stdlib only,
   runnable as `python3 -I scripts/repo/generate-local-api-docs-metadata.py`.
   - Resolve the orchestration root from the script location. Resolve sibling
     repos from the root's parent by default, with an optional
     `--repos-parent DIR` override for validation fixtures.
   - Accept `--output PATH`, defaulting to
     `<root>/.tilt/api-docs/release-metadata.json`. Create the parent directory.
   - Emit this shape:

     ```json
     {
       "schemaVersion": 3,
       "deployment": {
         "id": "tilt-local-development",
         "environment": "local-development",
         "runtime": "tilt"
       },
       "orchestration": { "...repo state..." },
       "sharedLibrary": { "...repo state...", "version": "0.1.0" },
       "repositories": {
         "transaction-service": {
           "...repo state...",
           "serviceCommon": { "declared": "0.1.0", "matchesLocalCheckout": true }
         }
       }
     }
     ```

   - Repo state fields: `repository`, `status` (`ok` or `missing-repo`),
     `version`, `tag`, `commitsSinceTag`, `commit`, `shortCommit`, `branch`
     (`detached` when `HEAD` is detached), `commitDate` (`%cs`), `dirty`.
   - Derive `tag` and `commitsSinceTag` by parsing
     `git describe --tags --long` output (`<tag>-<N>-g<sha>`; tags may contain
     `-`, so split from the right). Format `version` as the tag when `N` is 0,
     `<tag>+<N>` otherwise, or `untagged` when describe fails.
   - Derive `dirty` from `git status --porcelain --untracked-files=normal`,
     matching the current behavior.
   - Read `serviceCommon` from `[versions]` in `gradle/libs.versions.toml` with
     `tomllib`. Omit the `serviceCommon` key when the file or key is absent.
   - Read the local service-common version from the first
     `^\s*version\s*=\s*"([^"]+)"` match in `../service-common/build.gradle.kts`;
     use `null` when not found, which makes every `matchesLocalCheckout` false.
   - A missing sibling repo produces a `missing-repo` entry, not a failure.
   - Write the file only when the rendered content changes. Emit no timestamps.
2. Replace the inline `local("""...python3 - <<'PY' ... PY""")` block in the
   `Tiltfile` with a `local()` call to the new script, keep
   `LOCAL_API_DOCS_RELEASE_METADATA` and the `nginx-gateway-docs` ConfigMap
   wiring unchanged, and add `watch_file()` for the generator script.
3. In `verify_reference_metadata_contract`, replace the two Tilt assertions
   that require the production `source_path` and `productionReferenceId` with
   assertions that the Tiltfile invokes
   `scripts/repo/generate-local-api-docs-metadata.py` and that the generator
   does not reference `kubernetes/production` or `productionReferenceId`.
   Keep the `release-metadata.json=' + LOCAL_API_DOCS_RELEASE_METADATA` and
   prod-smoke assertions.

### Implementation notes

- The nearest reachable tag is intentional; do not use the newest tag in the
  repository.
- Keep sibling access read-only: only `git -C <repo>` read commands and file
  reads.
- The current page still expects `artifacts`. Until Phase 2, the Tilt page
  will show an empty manifest table; that is an accepted intermediate state.

### Validation

- `python3 -I scripts/repo/generate-local-api-docs-metadata.py --output "$(mktemp -d)/m.json"`
  succeeds and `jq .` on the output shows all six repositories, orchestration,
  and sharedLibrary with values matching
  `git -C ../<repo> describe --tags --long --dirty` and each repo's
  `serviceCommon`.
- Fixture check in a temporary directory passed via `--repos-parent`: a repo
  at a tag, a repo two commits after a tag (`v0.1.0+2`), an untagged repo, a
  dirty repo, a missing repo, and a service-common version mismatch each
  produce the expected fields. Create fixtures only inside a `mktemp -d`
  directory.
- Running the generator twice leaves the output file's mtime unchanged on the
  second run.
- `rg -n "productionReferenceId|kubernetes/production/docs-aggregator" Tiltfile scripts/repo/generate-local-api-docs-metadata.py`
  returns nothing.
- `bash -n` and `shellcheck` on `scripts/guardrails/verify-production-image-overlay.sh`.
- `./scripts/guardrails/verify-production-image-overlay.sh` passes.

### Completion criteria

The generator exists and produces purely local metadata, the Tiltfile uses it,
the production reference metadata files are unchanged (`git diff --stat` shows
no change under `kubernetes/production/` or `docs-aggregator/release-metadata.json`),
and the offline production-reference verifier passes.

## Phase 2: Local Rendering In The Docs Page

### Workspace

.

### Goal

Render the Phase 1 local metadata as the target local view while keeping the
production page output identical to today.

### Scope

- `docs-aggregator/swagger-initializer.js`, `docs-aggregator/index.html`,
  `docs-aggregator/swagger-ui-overrides.css`.
- The byte-identical copies under `kubernetes/production/docs-aggregator/`.

### Non-goals

- Changes to the generator or Tiltfile, except fixing a defect found while
  integrating.
- README updates.
- Live refresh, image tags, or production-reference display in Tilt.

### Required context

- Phase 1 output: `scripts/repo/generate-local-api-docs-metadata.py` and a
  generated sample
- `docs-aggregator/swagger-initializer.js`, `index.html`,
  `swagger-ui-overrides.css`
- `kubernetes/production/docs-aggregator/release-metadata.json` (production
  shape that must still render)
- `nginx/includes/security-headers-docs-csp.conf` (no inline scripts or
  styles may be introduced)

### Execution steps

1. In `swagger-initializer.js`, branch on `deployment.runtime === "tilt"`:
   - Local mode: set summary to `Tilt local development`, set the section
     caption to `Local repository state at Tilt start`, render the
     Environment, Orchestration, and Shared library facts, rebuild the table
     header to Repository / Version / Commit / Branch / Committed /
     Shared library, and render `repositories` in the existing fixed order
     followed by any extra names.
   - Version cell: `version`, plus ` · dirty` when `dirty`. Commit cell:
     `shortCommit` with the full `commit` as the title. Missing repos render
     `missing repo` in the Version cell and `unknown` elsewhere.
   - Shared library cell: `n/a` without `serviceCommon`; otherwise
     `<declared> (local checkout)` or
     `<declared> (not local; checkout is <sharedLibrary.version>)`.
   - Keep dirty-row tinting via `deployment-row-dirty`.
   - Production mode: keep the existing rendering path and output unchanged.
   - Remove local-only references to `productionReferenceId`,
     `productionBaselineId`, and `localSource`.
2. In `index.html`, add the Shared library fact element and give the table
   header row and caption ids so the script can replace them. Keep the
   production defaults in the static markup. Hide the Shared library fact in
   production mode via script, not inline styles.
3. Adjust `swagger-ui-overrides.css` only if the new fact or columns need it.
4. Copy the three files to `kubernetes/production/docs-aggregator/` so they
   remain byte-identical.

### Implementation notes

- Match the existing ES5 style (`var`, `function`), with no new dependencies.
- Use `textContent` for every metadata value; never build HTML from strings.
- Column count changes: update every `colSpan` that assumes 7 columns so
  loading, empty, and error rows span the active header.

### Validation

- `cmp` each of the three files against its production copy.
- `node --check docs-aggregator/swagger-initializer.js` when `node` is
  available. Report if `node` is unavailable.
- Static rendering check: a small throwaway harness outside the repo, or
  inspection, confirms local mode handles the Phase 1 sample, a dirty repo, a
  missing repo, and a service-common mismatch, and that production mode
  produces the same seven-column rows from
  `kubernetes/production/docs-aggregator/release-metadata.json` as before.
- `rg -n "innerHTML" docs-aggregator/swagger-initializer.js` returns nothing.
- `./scripts/guardrails/verify-production-image-overlay.sh` passes.

### Completion criteria

The page renders the target local view from Phase 1 metadata, production mode
renders unchanged, the production copies are byte-identical, and the offline
verifier passes.

## Phase 3: Documentation And Live Verification

### Workspace

.

### Goal

Update the owning documentation for the new local behavior and verify the page
end to end in local Tilt when the runtime is available.

### Scope

- `docs-aggregator/README.md` (owner doc for `/api-docs` behavior).
- `scripts/README.md` entry for the new generator.
- `kubernetes/production/README.md` only if it describes Tilt deriving local
  metadata from the production reference.
- Live local verification.

### Non-goals

- Code changes, except fixing defects found during verification.
- Changes to the production reference baseline or its documentation of the
  historical OCI provenance.
- `docs/archive/`, `docs/decisions/`, `archive/oci/`.

### Required context

- `docs/OWNERSHIP.md`
- `docs-aggregator/README.md`
- `scripts/README.md` (`repo/` section)
- `kubernetes/production/README.md` ("Application And Image Baseline")
- `docs/architecture/autonomous-ai-execution.md` (cluster mutation preflight)
- `docs/runbooks/tilt-debugging.md`

### Execution steps

1. Rewrite the local-metadata paragraphs in `docs-aggregator/README.md`:
   Tilt generates purely local metadata with
   `scripts/repo/generate-local-api-docs-metadata.py`. Document the fields,
   the `+N` and dirty semantics, the nearest-reachable-tag rule, the
   service-common match meaning (Maven Local shadows the release when versions
   match), and that values reflect Tiltfile evaluation and appear after the
   `nginx-gateway` pod restarts. State that the production overlay still
   serves the checked-in reference-only metadata. Remove the descriptions of
   `productionReferenceId` and `localSource`.
2. Add the generator to the `repo/` entries in `scripts/README.md`.
3. Check `kubernetes/production/README.md` and `docs/development/` for any
   statement that Tilt derives local metadata from the production reference;
   update it if present.
4. Live verification, only if Tilt is already running:
   - Run the cluster mutation preflight from
     `docs/architecture/autonomous-ai-execution.md` (context and cluster
     `kind-kind`, loopback HTTPS API, `kind-control-plane` Ready).
   - Restart `nginx-gateway` so its init container restages the docs files
     (`kubectl rollout restart deployment/nginx-gateway` and wait for
     rollout).
   - `curl` `https://app.budgetanalyzer.localhost/api-docs/release-metadata.json`
     with normal TLS verification and confirm `deployment.runtime` is `tilt`,
     `repositories` is present, and no `productionReferenceId` or GHCR image
     appears.
   - If Tilt is not running or the preflight fails, do not start or modify the
     runtime; record live verification as not run.

### Implementation notes

- Do not use `--insecure` or bypass TLS verification. If the local CA is not
  trusted in the VM, report that instead of working around it.
- Keep `AGENTS.md` unchanged unless a guardrail or workflow it states has
  become false.

### Validation

- `rg -n "productionReferenceId|localSource" docs-aggregator scripts/README.md kubernetes/production/README.md docs/development`
  returns nothing outside unchanged historical contexts.
- `./scripts/guardrails/verify-production-image-overlay.sh` passes.
- `INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python ./scripts/guardrails/verify-static-security-manifests.sh`
  passes. If the pinned interpreter is missing, create it per
  `docs/ci-cd.md#security-guardrailsyml`; do not use the system PyYAML.
- Live check results from step 4, or an explicit not-run note.

### Completion criteria

Owner documentation describes the local-only Tilt manifest and the unchanged
production reference behavior, both static verifiers pass, and live
verification either passed or is explicitly reported as not run with the
reason.
