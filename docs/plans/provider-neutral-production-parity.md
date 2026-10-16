# OCI Retirement and Provider-Neutral Kubernetes Parity

OCI is retired. The project's available OCI free-tier capacity is no longer
sufficient for the full stack, and there is currently no production environment.
Preserve the deployment implementation as a frozen reference for a possible
return to OCI, while removing its ongoing maintenance burden from active work.

The repository's purpose remains demonstrating near-identical local and
production Kubernetes architecture. Keep provider-independent Kubernetes
configuration and production overlays in the maintained repository. Preserve
shared workload, routing, security, persistence, and observability behavior;
document the small, intentional environment differences. Local Kind/Tilt is the
live validation target. Production overlays are an offline-validated reference,
not evidence of a running or currently tested production deployment.

Use `archive/oci/` for the frozen snapshot, retaining original repository-relative
paths beneath it. Copy scripts and supporting inputs unchanged before modifying
or removing active originals. A new archive README owns the retirement notice,
snapshot provenance, inventory, and restoration caveats. Historical ADRs and
existing `docs/archive/` files keep their original text; active entry points must
identify OCI material as retired. These are the drafting defaults for archive
location and historical-document treatment.

Keep this work bounded: retirement, documentation cleanup, separation of existing
provider coupling, and narrow parity fixes. Do not build a provider-adapter
framework, choose another host, create a generic deployment lifecycle, reorganize
all Kubernetes manifests, or require broad NGINX consolidation. Restoring OCI
would be a separate, explicitly authorized project using the snapshot as input.

All implementation work stays in this repository. Do not access, reconcile, or
delete OCI infrastructure, perform TLS writes, change sibling service code, or
run Git write operations. Live checks require the exact guarded local
`kind-kind` target and prerequisites in
`docs/architecture/autonomous-ai-execution.md`. Follow
`docs/agents-md-checkstyle.md` when editing agent instructions. Validate every
changed active shell script with `bash -n` and ShellCheck; frozen copies are
preservation artifacts and must not be repaired to satisfy current checks.

## Phase 1: Preserve the OCI deployment as an unchanged archive

### Workspace

.

### Goal

Capture the checked-in OCI implementation and supporting inputs before active
cleanup, with a clear retirement boundary and verifiable fidelity.

### Scope

Discovery, the new snapshot and README, documentation ownership, and exclusions
needed to keep the snapshot outside active maintenance.

### Non-goals

Executing archived scripts, collecting live cloud state or secrets, changing
historical file contents, or making scripts executable from their new location.

### Required context

- `AGENTS.md`, `docs/agents-md-checkstyle.md`, `docs/OWNERSHIP.md`
- `deploy/README.md`, `deploy/scripts/`, `deploy/instance.env.template`
- `deploy/helm-values/`, `deploy/manifests/`, `kubernetes/production/`
- `docs/runbooks/oci-release-deployment-checklist.md`, `docs/ci-cd.md`
- `docs/dependency-automation.md`, `renovate.json`, `renovate-presets/default.json`
- `scripts/README.md`, affected workflows and image-pinning inventories

### Execution steps

1. Inventory OCI deployment entry points and follow their sourced libraries,
   templates, Helm values, Kubernetes inputs, and documentation references.
   Search beyond filenames containing OCI: k3s CNI values, public TLS templates,
   release helpers, and the observability SSH tunnel helper also contain
   deployment assumptions. Classify OCI-only, reusable, and mixed assets.
2. Create `archive/oci/README.md` and update `docs/OWNERSHIP.md` to identify it
   as the retirement/snapshot owner. Record the capacity reason, absence of
   production, snapshot date, source commit, and original path inventory. Record
   pre-existing working-tree differences in copied files so the commit is not
   misrepresented as identifying uncommitted content.
3. Preserve direct, byte-for-byte copies of all checked-in scripts used for OCI:
   bootstrap, secrets, render, reconcile, release, verification, and libraries.
   Snapshot the whole existing `deploy/` tree and supporting checked-in inputs
   outside it needed to understand and reconstruct that implementation. Preserve
   original relative paths and executable modes. Include original production
   metadata, overlays, and OCI operating docs. Reusable originals remain active;
   their snapshot copies are historical.
4. Record a simple checksum inventory and compare it with originals before
   cleanup. Preserve non-secret templates, but do not collect ignored instance
   configuration, credentials, certificates, kubeconfigs, or runtime output.
   Identify external prerequisites and sibling repositories without copying
   them. Do not substitute links into the active tree for snapshot files.
5. Explain in the README that the snapshot is unmaintained, untested against
   current OCI, and not an executable entry point at its new path. Its original
   instructions and relative paths deliberately remain unchanged. Restoration
   requires a new review of dependencies, assumptions, and available capacity.
6. Exclude `archive/oci/**` from dependency-update discovery, maintained image
   inventories, deployment acceptance checks, and active build/update discovery
   as applicable. Keep general secret detection intact. Use existing automation
   configuration, not a new archive-maintenance framework. Update the relevant
   owner docs with this boundary.

### Implementation notes

Snapshot copies of reusable inputs intentionally preserve the old deployment
context as active sources evolve. They are not a second maintained production
tree. Put retirement notices in the new README and active links, without changing
preserved files. Existing ADRs and historical archives remain unchanged.

### Validation

- Compare snapshot file lists, checksums, and executable modes with originals.
- Check coverage of scripts and checked-in dependencies; document external
  prerequisites without claiming a self-contained installer.
- Verify archive exclusions from active updates and deployment checks.
- Run affected automation configuration checks and `git diff --check`.

### Completion criteria

The original OCI scripts and supporting inputs are recoverable unchanged in one
explicitly retired directory. Provenance and maintenance exclusions are recorded,
and active behavior remains intact.

## Phase 2: Remove OCI from active execution and maintenance paths

### Workspace

.

### Goal

Retire OCI operations without losing reusable configuration or breaking local
development and provider-neutral offline checks.

### Scope

OCI-only active files, mixed helpers, metadata consumers, offline render/check
paths, CI, and dependency discovery.

### Non-goals

A replacement deployment system, compatibility wrappers for retired commands,
changes to the frozen snapshot, or application behavior changes.

### Required context

- Archive inventory and checksums from Phase 1
- `deploy/scripts/lib/common.sh`, `deploy/scripts/lib/version-contract.sh`
- `deploy/scripts/render/`, `deploy/helm-values/`, `deploy/manifests/`
- `Tiltfile`, production app/image and docs-aggregator metadata
- `scripts/guardrails/verify-production-image-overlay.sh`
- `scripts/guardrails/verify-static-security-manifests.sh`
- `scripts/security/render-image-scan-inputs.sh`, release metadata verifiers
- Image-pinning inventories, affected workflows and Renovate configuration
- `docs/dependency-automation.md`, `scripts/README.md`

### Execution steps

1. Retain provider-independent Kubernetes overlays, policies, Helm values,
   image contracts, and shared version/tool inputs in active locations.
   Classify by content and consumers, not the current directory name. Do not
   archive generic Kubernetes configuration solely because OCI introduced it.
2. Separate minimal reusable pieces from OCI environment loading, k3s kubeconfig
   defaults, instance principals, fixed OCI NodePorts/NLB publication, SSH
   defaults, and cloud mutations. Prefer existing render commands and small
   helpers. Do not generalize the old OCI lifecycle.
3. Update active consumers before removing originals. Static security and image
   scanning currently source deployment version contracts and Helm values;
   render scripts source `common.sh`; Tilt reads production docs release
   metadata. None may source or execute the archive afterward. Update nearby
   owner documentation with changed paths in the same phase.
4. Remove active OCI-only originals after verifying their snapshot copies and
   detaching callers. Include OCI bootstrap/apply/upgrade/release operations
   and OCI-specific remote access helpers with no remaining generic consumer.
   Remove their commands from active catalogs and acceptance gates. Keep only
   brief documentation retirement pointers where they help existing links.
5. Retain immutable image references and useful source provenance in the active
   production reference. Preserve original OCI deployment identity in the
   archive. Remove or clearly label historical OCI identity in active metadata
   without inventing a new deployment, timestamp, or live status. Update Tilt
   docs metadata generation and consistency checks together. Do not require new
   application releases as part of retirement.
6. Make retained production render/check commands work without OCI instance
   files, credentials, cloud tools, or live cluster access. Replace live Helm
   dry-run dependencies in offline checks with the existing offline pattern.
   Identify required local runtime checks separately. Reuse the existing
   production verifier as the entry point where practical.
7. Preserve image/security evidence for retained Kubernetes inputs and update
   paths, inventories, and extraction together. Archive-only resources must not
   cause update or deployment work. Keep generic production image policies and
   ARM64 compatibility.

### Implementation notes

Retain existing locations where clear; relocate only to remove provider coupling
or misleading ownership. Offline renders may use documented non-secret reference
values without implying historical hostnames, images, or identity providers are
currently deployed. Describe unresolved publication, storage, secret provision,
and TLS prerequisites in prose, without speculative adapter interfaces.

### Validation

- Run retained production render/image checks without OCI configuration and
  with no usable cluster context; they must not inspect or contact a cluster.
- Run static security checks and affected offline image-scan rendering.
- Verify active executable/configuration references do not consume the archive
  or removed paths; review documentation links separately.
- Verify Tilt metadata generation and frontend production-smoke wiring continue
  to use maintained inputs.
- Run `bash -n`, `shellcheck` on changed active scripts, affected automation
  configuration checks, and `git diff --check`.

### Completion criteria

OCI operations exist only in the archive. Local tooling, retained Kubernetes
configuration, offline production renders, and security checks have no dependency
on that archive or an OCI environment.

## Phase 3: Preserve Kubernetes parity with narrow shared-source fixes

### Workspace

.

### Goal

Keep local and production reference behavior aligned through shared inputs and
focused checks without expanding retirement into a broad refactor.

### Scope

Existing overlays, ingress gateway configuration, authorization, rate limits,
routing, and documented environment differences.

### Non-goals

A universal base/overlay hierarchy, a provider framework, broad NGINX include
extraction, semantic security changes, or a new production deployment.

### Required context

- `kubernetes/production/README.md`, retained inputs from Phase 2
- `kubernetes/istio/ingress-gateway-config.yaml`
- `kubernetes/istio/ingress-rate-limit.yaml`, shared authorization policies
- Production ingress-policy, authorization, and gateway-route overlays
- Shared and production infrastructure manifests
- `nginx/README.md`, both active NGINX variants, production ConfigMap inputs
- `Tiltfile`, affected verifiers, `scripts/README.md`
- `docs/development/local-environment.md#frontend-reactvite`

### Execution steps

1. Record a compact parity table in `kubernetes/production/README.md`: shared
   sources, intentional differences, and available validation for workloads,
   ingress/security, routing, persistence, observability, images, and frontend
   delivery. Avoid a resource inventory or claims of live production equivalence.
2. Preserve existing composition of production apps, routes, infrastructure,
   ingress policies, monitoring, and egress from common inputs. Keep hostname,
   immutable image, static frontend, and storage sizing differences explicit.
   Retain provider-independent admission, network/session security, persistence,
   TLS requirements, and internal-only observability.
3. Resolve known copies of ingress gateway pod configuration and authorization
   policies through narrow shared sources or Kustomize composition. Preserve
   local Kind publication and resource names. Share security and diagnostics;
   leave production publication unspecified until a target exists. Express the
   production omission of the standalone frontend authorization policy as a
   small overlay patch. Archived templates remain unchanged.
4. Keep the rate-limit EnvoyFilter shared without production-only semantic
   patches. Check routes differ only in declared environment fields and that
   infrastructure overlays preserve StatefulSets, persistence, and security.
   Extend existing verifiers with focused structural comparisons where there is
   a real drift risk; do not build a general parity-testing framework.
5. Point the production NGINX ConfigMap generator at the canonical production
   configuration and existing shared includes where this removes direct copies.
   Preserve local Vite and production static frontend variants, route ownership,
   and security behavior. Defer broader NGINX restructuring.
6. Update affected owner docs alongside each change. Preserve the atomic local
   frontend production-smoke image target as the existing local proof of built
   frontend delivery. Do not introduce another full local cluster or claim this
   proves an unspecified cloud deployment.

### Implementation notes

Near-identical environments means shared application behavior and controls with
explicit differences. Production overlays remain useful without a production
host. Defer additional cleanup unless necessary to retain parity or remove the
OCI dependency.

### Validation

- Render retained production Kustomize targets and compare declared shared
  ingress, authorization, rate-limit, route, and persistence structures.
- Run affected ingress/static security, routing, image, and metadata checks.
- Validate NGINX variants through supported configuration checks.
- Run focused local smoke checks when Tilt wiring or runtime behavior changes,
  including the frontend production-smoke path when affected. Report missing
  prerequisites instead of substituting an offline claim.
- Run `bash -n`, `shellcheck` on changed active scripts, and `git diff --check`.

### Completion criteria

Reusable Kubernetes production configuration remains maintained and checked
against shared local behavior. Necessary copies are removed, deliberate
differences are documented, and no new provider/deployment framework exists.

## Phase 4: Finish the production documentation cleanup

### Workspace

.

### Goal

Make repository guidance consistently describe OCI retirement, no current
production environment, and the continuing purpose and limits of parity.

### Scope

All active production/OCI documentation, ownership, catalogs, links, agent
instructions, and final archive/parity verification.

### Non-goals

Rewriting preserved history, calling a replacement provider supported, disabling
unrelated release/CI workflows, or executing a cloud migration.

### Required context

- `docs/OWNERSHIP.md`, `docs/agents-md-checkstyle.md`, `AGENTS.md`, `README.md`
- Archive, retained deployment, and production README files
- `docs/ci-cd.md`, `docs/dependency-automation.md`, `scripts/README.md`
- Architecture owners: system, security, session, ports, observability, autonomy
- `docs/development/`, `docs/runbooks/`, `docs/research/`, `docs/plans/`
- `nginx/README.md`, `docs-aggregator/README.md`, `kubernetes/kyverno/README.md`

### Execution steps

1. Finish updating canonical owners before summaries and links. State that OCI
   was retired because available free-tier capacity no longer supported the
   full stack; no production environment exists; Kind/Tilt and provider-neutral
   production reference overlays are maintained. Remove obsolete OCI capacity
   figures from current prerequisites.
2. Replace claims that OCI/k3s is supported throughout active guidance. Keep
   production-grade local security, persistence, immutable image policy, ARM64
   support, and the parity objective. Distinguish local runtime evidence,
   offline render validation, and historical deployment evidence.
3. Archive OCI-only operator guides, runbooks, and provisioning research
   captured in Phase 1. Replace useful old entry points with short retirement
   links; rewrite mixed docs to retain generic content. Remove obsolete OCI
   upgrade/migration instructions, including retired ingress-filter cleanup,
   from current guidance and gates.
4. Search all active text for OCI, Oracle Cloud, k3s, historical deployment
   hostnames, removed paths, and claims of a current production environment.
   Review every match in context. Remaining OCI docs must describe retirement
   or link to labeled history. Review other provider design documents so none
   accidentally appears to describe a replacement deployment.
5. Keep ADRs and existing `docs/archive/` files unchanged. Label linked OCI
   records as retired historical context in active indexes and entry points.
   Preserved snapshot text remains under the new archive retirement notice.
   Do not globally replace `production`: build modes, architecture standards,
   and operational dependency automation remain valid.
6. Retain release/build and dependency/security automation for active artifacts,
   describing its purpose without implying OCI deployment. Check links and
   commands against final paths; remove obsolete verifier requirements. Apply
   the agent-document authoring checklist to `AGENTS.md`.
7. Verify frozen checksums again, run final affected checks, and report remaining
   environment prerequisites and verification limits. Completion must not imply
   live production validation.

### Implementation notes

Exact retirement/snapshot detail belongs in `archive/oci/README.md`; maintained
overlay/parity detail belongs in `kubernetes/production/README.md`. Record
ownership in `docs/OWNERSHIP.md`; other documents summarize and link. Updating
this plan alone does not mean retirement has been implemented.

### Validation

- Search active documentation for stale claims/unmarked OCI guidance; inspect
  remaining matches instead of banning terms.
- Verify active links resolve and no active command points into the archive.
  Confirm ADRs and older archives have no modifications.
- Verify snapshot checksums and absence of active archive consumers.
- Run retained offline production/static security checks; reuse earlier local
  smoke evidence unless later changes require rerunning it.
- Apply the agent-document checklist, validate changed active shell scripts,
  and run `git diff --check`.

### Completion criteria

OCI is unmistakably retired across active documentation, its original deployment
implementation is preserved unchanged, and it creates no ongoing deployment
maintenance obligations. Maintained shared configuration, explicit differences,
offline checks, and local runtime evidence continue to demonstrate Kubernetes
parity without claiming a production host.
