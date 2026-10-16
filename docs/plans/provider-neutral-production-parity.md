# Provider-Neutral Production Parity and OCI Retirement

Separate provider-neutral production desired state from the retired OCI/k3s
deployment implementation, and make local development plus production overlays
compose shared Kubernetes sources wherever their runtime behavior is meant to
match.

This is a follow-up architecture and cleanup plan, not part of the ingress
rate-limit review PR. It does not migrate, inspect, reconcile, or delete an
existing OCI cluster. The legacy `ingress-auth-local-rate-limit` object needs
no OCI upgrade cleanup because there is no supported OCI upgrade target.
Historical ADRs and archived plans remain unchanged. Retired OCI scripts may be
isolated or clearly labeled, but must not be generalized speculatively for an
unknown replacement provider.

The target layering is:

```text
shared Kubernetes bases
├── local Kind/Tilt overlays
├── provider-neutral production overlays
└── future provider adapter
    ├── cluster/runtime installation
    ├── public ingress publication
    ├── persistent storage class
    ├── secret store integration
    └── certificate/DNS automation
```

Production parity means common behavior has one source, not that development
and production are byte-identical. Hostnames, immutable image refs, built
frontend delivery, storage sizing, and publication are valid overlay concerns.
Authorization boundaries, service routing, gateway pod security/diagnostics,
and shared workload configuration should not be copied manually.

All validation is offline or against guarded local `kind-kind`. Do not access
OCI or another production environment, perform TLS writes, choose a replacement
provider without user direction, modify ADRs/archives, or run Git write
operations. Follow `docs/agents-md-checkstyle.md` for every `AGENTS.md` edit and
run `bash -n` plus ShellCheck on every changed shell script.

## Phase 1: Establish production and provider-adapter ownership

### Workspace

.

### Goal

Make the repository describe OCI as retired and define which production
contracts are provider-neutral versus provider-specific.

### Scope

Active repository guidance, documentation ownership, a discovery-backed
manifest/deployment inventory, and explicit future provider-adapter boundaries.

### Non-goals

Changing live infrastructure, deleting historical records, selecting a cloud,
or rewriting manifests before ownership and intended differences are recorded.

### Required context

- `AGENTS.md`, `docs/agents-md-checkstyle.md`, `docs/OWNERSHIP.md`
- `README.md`, `deploy/README.md`, `kubernetes/production/README.md`
- `docs/architecture/system-overview.md`
- `docs/architecture/security-architecture.md`
- `docs/architecture/port-reference.md`
- `docs/development/local-environment.md`
- active files under `deploy/`, `kubernetes/`, and `kubernetes/production/`
- OCI ADRs only as historical context; do not edit them

### Execution steps

1. Inventory production inputs by behavior and source relationship. At minimum
   classify workloads/images, application routing, authorization, rate limits,
   ingress gateway configuration, NGINX, stateful storage, monitoring, secrets,
   certificates, cluster installation, public publication, and release
   metadata.
2. Record which current assets already compose shared local sources and which
   are copied or provider-bound. Treat `kubernetes/production/` as the intended
   provider-neutral desired-state layer; do not claim it is complete until the
   later phases pass.
3. Update `AGENTS.md` and active owner docs to retire OCI as the production
   target. State that the k3s installer, fixed NodePorts/NLB assumptions, OCI
   Vault instance principal, OCI release wrappers, SSH defaults, and
   `oci-production` metadata are legacy provider implementation details.
4. Define the future provider-adapter contract: cluster/CNI installation,
   ingress Service publication, storage class, secret provider, DNS and
   certificate integration, and provider credentials. Keep those inputs out of
   shared workload/security bases.
5. Mark active OCI deployment instructions as retired or unsupported without
   changing historical ADRs. Remove them from current happy paths and acceptance
   gates. Preserve files needed for historical reference until a separately
   reviewed deletion decision is made.
6. Add a parity matrix identifying intentional local/production differences
   and shared invariants. Link detailed owners instead of copying configuration
   inventories into `AGENTS.md`.

### Implementation notes

Provider-neutral does not mean lowest-common-denominator Kubernetes. It means
the reusable layer names its prerequisites and leaves cloud/runtime decisions
to adapters. A default storage class or `LoadBalancer` implementation is still
a provider contract and must not be silently assumed.

### Validation

- Run the repository's `AGENTS.md` checkstyle workflow.
- Search active docs and scripts for statements that still call OCI the
  canonical production target; each remaining occurrence must be historical,
  explicitly retired, or provider-specific by design.
- Confirm no historical ADR or archived document changed.
- Run `git diff --check`.

### Completion criteria

Active guidance identifies a provider-neutral production layer, OCI paths are
unambiguously retired, provider responsibilities are explicit, and the parity
matrix gives later phases a reviewable source of truth.

## Phase 2: Derive ingress and authorization overlays from shared bases

### Workspace

.

### Goal

Make gateway pod behavior, ingress security policy, and service authorization
shared by construction across local and production.

### Scope

Ingress gateway ConfigMap Kustomize bases/overlays, Istio rate-limit and
authorization policy composition, Tilt wiring, production render targets, and
structural parity tests.

### Non-goals

Public load-balancer selection, DNS/TLS automation, secret providers, changing
security policy semantics, or maintaining retired OCI templates.

### Required context

- final ingress rate-limit PR changes
- `kubernetes/istio/ingress-gateway-config.yaml`
- `kubernetes/istio/ingress-rate-limit.yaml`
- `kubernetes/istio/authorization-policies.yaml`
- `kubernetes/production/istio-ingress-policies/kustomization.yaml`
- `kubernetes/production/istio/authorization-policies.yaml`
- `Tiltfile`
- `scripts/guardrails/verify-ingress-rate-limit-config.sh`
- `scripts/guardrails/verify-static-security-manifests.sh`
- parity matrix from Phase 1

### Execution steps

1. Extract the provider-neutral ingress gateway ConfigMap fields into one
   common source: deployment pod security, narrow proxy stats selection, and
   service-account behavior. Remove the temporary three-copy stats annotation
   introduced by the rate-limit PR once all active consumers use the base.
2. Add a local overlay that preserves the current Kind NodePort contract. Add a
   generic production overlay that imports the same common source but leaves
   public Service publication to a future provider adapter.
3. Change Tilt and offline production render/guardrail paths to consume those
   overlays. Preserve resource names so the refactor does not create duplicate
   ConfigMaps.
4. Keep the rate-limit EnvoyFilter as one shared object with no production-only
   semantic patches. Deep-compare its production render to the common source.
5. Replace the copied production authorization-policy file with a Kustomize
   overlay over the shared policy set. Express the intentional production
   omission of the standalone frontend policy as a narrow delete patch tied to
   the production frontend topology.
6. Add structural tests that compare shared gateway deployment configuration,
   rate-limit filters, and all authorization policies except explicitly listed
   overlay operations. Reject unexpected production-only additions or missing
   shared resources.

### Implementation notes

Embedded YAML strings in the gateway ConfigMap should be inherited whole; do
not rely on manually synchronized edits inside `data.deployment`. Service
publication is deliberately excluded from the common base because Kind
NodePorts and a future production load balancer are different adapter choices.

### Validation

- Render local and production ingress gateway overlays and compare their common
  embedded structures.
- Render production ingress and authorization overlays with Kustomize and run
  focused structural parity checks.
- Run local ingress/rate-limit verification after the Tilt wiring change.
- Run applicable static security manifest guardrails.
- Run `bash -n` and `shellcheck` for every changed shell script.

### Completion criteria

Gateway pod behavior, rate limiting, and authorization originate from shared
sources; local/production differences are explicit overlays; copied production
security manifests and temporary stats duplication are gone.

## Phase 3: Consolidate application routing and production packaging inputs

### Workspace

.

### Goal

Eliminate avoidable production copies while preserving legitimate differences
in frontend delivery, immutable images, hostnames, and storage sizing.

### Scope

Gateway routes, NGINX configuration ownership, production app/infrastructure
Kustomize inputs, documentation assets, and parity guardrails.

### Non-goals

Making the Vite development frontend behave like the production static bundle,
changing public API routes, rebuilding service images, or selecting provider
storage/publication implementations.

### Required context

- parity matrix from Phase 1
- `kubernetes/gateway/`
- `kubernetes/production/gateway-routes/kustomization.yaml`
- `nginx/nginx.k8s.conf`, `nginx/nginx.production.k8s.conf`
- `kubernetes/production/nginx/`
- `kubernetes/production/apps/kustomization.yaml`
- `kubernetes/infrastructure/`
- `kubernetes/production/infrastructure/kustomization.yaml`
- `docs/architecture/resource-routing-pattern.md`
- `nginx/README.md`, `docs-aggregator/README.md`
- production image/render guardrails

### Execution steps

1. Preserve the production route overlay's narrow hostname patches over shared
   local `HTTPRoute` resources. Add a structural assertion that path matches,
   backends, filters, and route ownership remain equal except for the declared
   hostname difference.
2. Remove the second checked-in copy of `nginx.production.k8s.conf` by making
   the production ConfigMap generator consume one canonical production NGINX
   source. Preserve production-only static frontend and strict-CSP behavior.
3. Identify backend API route blocks and include files that are semantically
   shared between development and production. Extract only stable common
   fragments where NGINX can include them without obscuring route ownership;
   keep environment-specific frontend shells separate.
4. Retain production app overlays over shared service Deployments/Services,
   with explicit patches for immutable image digests, release metadata,
   production frontend packaging, and generated docs. Reject copied workload
   manifests when a patch or generator input is sufficient.
5. Retain the infrastructure overlay over the shared StatefulSet baseline.
   Document storage capacity as a production policy but leave storage-class
   selection to a provider adapter. Add checks that production does not replace
   shared persistence/security behavior accidentally.
6. Update NGINX, routing, and production docs to identify common sources and
   intentional variants. Extend guardrails to compare route inventories and
   catch drift in shared API behavior.

### Implementation notes

Do not force textual equality between development and production NGINX files:
Vite/HMR and a built static frontend genuinely differ. Share backend routing
and security includes where practical, and enforce semantic parity for public
API ownership with focused tests.

### Validation

- Render production apps, gateway routes, and infrastructure overlays.
- Validate local and production NGINX configurations through their supported
  render/config-test paths.
- Run route-inventory parity checks and production image/render guardrails.
- Confirm the production static frontend path and local Vite path both retain
  their documented behavior.
- Run `bash -n` and `shellcheck` for every changed shell script.

### Completion criteria

Production app, route, NGINX, and infrastructure outputs reuse shared sources
where behavior is common; remaining differences are deliberate, documented,
and structurally tested rather than maintained as unexplained copies.

## Phase 4: Isolate legacy OCI assets and gate generic production renders

### Workspace

.

### Goal

Make provider-neutral production renders the maintained acceptance surface and
prevent retired OCI implementation details from leaking back into it.

### Scope

Generic production render entry points, release metadata vocabulary, static
guardrails, active script/document maps, and isolation of retired OCI assets.

### Non-goals

Deleting cloud resources, deploying a replacement environment, inventing
provider credentials, or guaranteeing old OCI scripts remain executable.

### Required context

- outputs and parity matrix from Phases 1-3
- `deploy/scripts/render/`
- `deploy/scripts/reconcile/`
- OCI-named scripts under `deploy/scripts/{lib,release,verify}/`
- `kubernetes/production/apps/deployment-manifest.yaml`
- `kubernetes/production/apps/image-inventory.yaml`
- production release metadata and guardrails
- `scripts/README.md`, `deploy/README.md`, `kubernetes/production/README.md`

### Execution steps

1. Provide one offline generic production render/check entry point that
   composes apps, infrastructure, routes, ingress/security, gateway pod config,
   monitoring, and egress without requiring an OCI instance env or credentials.
2. Rename generic deployment metadata fields/values that encode
   `oci-production` when they describe provider-neutral artifacts. Preserve
   artifact traceability and immutable image contracts; do not fabricate a new
   deployed environment.
3. Remove OCI upgrade/deployment scripts from generic production acceptance
   gates. Place them behind an explicit legacy boundary or retirement marker so
   new work does not source their k3s, NLB, Vault, SSH, or host assumptions.
4. Add forbidden-pattern and structural checks ensuring the generic production
   render contains no OCI Vault provider, OCI identifiers, k3s CNI paths, fixed
   OCI NodePorts/NLB assumptions, or legacy environment labels.
5. Keep future provider adapter placeholders conceptual unless a provider and
   its requirements have been selected. Do not add empty scripts or speculative
   manifests merely to complete a directory shape.
6. Update active documentation and verifier catalogs to make the generic
   offline render the maintained production proof. Clearly label local live
   checks versus provider-neutral production render checks.

### Implementation notes

Isolation is preferable to preserving a misleading compatibility path. If
removing an obsolete OCI file would erase useful historical context, retain it
under an explicit legacy boundary; if it is redundant with version history,
propose deletion separately rather than mixing destructive cleanup into this
plan.

### Validation

- Run the generic production render/check entry point from a clean environment
  with no OCI variables or credentials.
- Run forbidden-provider scans and all structural parity checks from earlier
  phases.
- Run affected local Tilt and focused ingress/NGINX checks against guarded
  `kind-kind` where live behavior changed.
- Verify active docs contain no canonical OCI deployment instructions and no
  claim that a replacement provider is already supported.
- Run `bash -n`, `shellcheck`, the `AGENTS.md` checkstyle workflow, and
  `git diff --check`.

### Completion criteria

The maintained production acceptance surface is provider-neutral and offline,
shared behavior remains aligned with local development, legacy OCI assets are
isolated from active paths, and no live migration or speculative replacement
deployment has been performed.
