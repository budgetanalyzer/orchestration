# Retired OCI Deployment Snapshot

**Status:** Frozen historical reference; unmaintained and not an active
deployment path

Oracle Cloud Infrastructure (OCI) is retired for Budget Analyzer because the
available OCI Free Tier capacity is no longer sufficient for the full stack.
There was no production environment when this snapshot was captured. The
snapshot preserves the former deployment implementation as design and recovery
input if a separately authorized OCI restoration project is undertaken.

## Provenance

- Snapshot time: `2026-10-16T10:09:57Z`
- Source repository commit: `60510f4ce9331968988516947f394152f6aa0da4`
- Source commit date: `2026-10-16T16:50:59+07:00`
- Source commit subject: `delete implemented plans (#83)`
- Source layout: repository-relative paths are retained below `archive/oci/`
- Fidelity inventory: [`SHA256SUMS`](SHA256SUMS)

All 182 preserved files were copied directly from their original paths before
active OCI cleanup. Their bytes and executable mode bits were unchanged by the
snapshot operation. None of the copied source files had a pre-existing
working-tree difference from the source commit. The only pre-existing
working-tree difference was
`docs/plans/provider-neutral-production-parity.md`; it is not a snapshot input
and is not copied here. This README, `SHA256SUMS`, and active documentation or
automation changes that establish the archive boundary are new retirement
metadata, not source-commit content.

## Inventory and classification

`SHA256SUMS` is the exact file-level inventory. Its entries use paths relative
to this directory, which are also the files' original repository-relative
paths.

| Original path | Files | Classification at capture | Reason retained |
| --- | ---: | --- | --- |
| `deploy/**` | 44 | OCI-only | Complete bootstrap, secret, render, reconcile, release, verification, library, Helm-value, template, and operator surface. |
| `kubernetes/production/**` | 21 | Mixed | OCI-coupled production metadata and routing plus reusable production overlays. |
| `kubernetes/gateway/**` | 3 | Reusable | Shared route bases consumed by the production overlay. |
| `kubernetes/infrastructure/**` | 11 | Reusable | Shared PostgreSQL, Redis, and RabbitMQ bases consumed by production. |
| `kubernetes/istio/**` | 17 | Mixed | Shared Istio inputs plus the k3s CNI and egress inputs used by OCI. |
| `kubernetes/kyverno/**` | 14 | Mixed | Shared admission policy inputs and the production digest policy. |
| `kubernetes/monitoring/**` | 12 | Reusable | Shared Prometheus, Grafana, Jaeger, and Kiali inputs used by production reconciliation. |
| `kubernetes/network-policies/**` | 10 | Reusable | Shared network-policy baseline applied by OCI bootstrap. |
| `kubernetes/services/**` | 24 | Reusable | Shared workload bases referenced by the production app overlay. |
| `docs-aggregator/**` | 7 | Reusable | API documentation and release-metadata sources used by release preparation. |
| `docs/ci-cd.md` | 1 | Mixed | Release terminology and the former OCI desired-state workflow. |
| `docs/architecture/observability.md` | 1 | Mixed | Shared observability design and former OCI operator-access contract. |
| `docs/decisions/008-oci-public-ingress-via-nlb.md` | 1 | OCI-only | Historical rationale for the OCI public-ingress shape. |
| `docs/runbooks/oci-release-deployment-checklist.md` | 1 | OCI-only | Former OCI release evidence checklist. |
| `scripts/**` | 14 | Mixed | Direct tool-install, render, verification, release-inspection, secret-inventory, and observability helpers used by the deployment path. |
| `Tiltfile` | 1 | Reusable | Former local-to-OCI chart-version parity input. |

Reusable and mixed files are copies of their old deployment context. Their
active originals may continue to evolve; these copies do not form a second
maintained production tree.

## Deliberate exclusions

The snapshot includes checked-in, non-secret inputs only. It does not include:

- ignored `instance.env` files or generated secret environment files;
- OCI credentials, Vault values, user credentials, session material, SSH
  private keys, certificates, certificate private keys, or kubeconfigs;
- rendered `tmp/` output, release evidence, logs, caches, container state,
  cluster state, or any other runtime output;
- live OCI inventory, DNS, network, load balancer, IAM, Vault, or compute
  state; or
- sibling repositories, their working trees, or built application artifacts.

General repository secret detection still applies to this directory. The
archive is excluded from dependency updates and active deployment/build
discovery, not from secret scanning.

## External prerequisites represented only by references

The preserved implementation was never a self-contained installer. It assumed
an adequately sized ARM64 Ubuntu host; OCI tenancy, compartment, region,
network, load balancer, DNS, IAM, and Vault resources; authenticated OCI and
GitHub/registry access; SSH access; external Helm/chart and release-download
availability; and the CLI tools documented by the copied operator guide. It
also assumed coordinated source and published artifacts from sibling
`service-common`, service, Session Gateway, `ext-authz`, and frontend
repositories. Those external systems and repositories are not copied here.

## Maintenance and restoration boundary

Do not execute preserved scripts from `archive/oci/`. Executable mode bits are
retained only for fidelity. The scripts and documentation deliberately keep
their original repository-relative paths, root-discovery assumptions, commands,
and historical wording, so relocating them under this directory does not make
them a supported entry point. The snapshot is unmaintained and has not been
tested against current OCI services, current upstream dependencies, or a live
production environment.

Renovate ignores `archive/oci/**`. Maintained image-pinning inventories,
deployment acceptance checks, shell-validation sweeps, build discovery, and
release/update automation must continue to target active paths only. Do not fix
or modernize frozen copies when an active check changes.

Restoring OCI requires a new, explicitly authorized project. Before reusing
anything here, reassess available capacity and cost, current OCI APIs and
resource shapes, operating-system and ARM64 support, Kubernetes/k3s and CNI
compatibility, chart and image provenance, secret and certificate handling,
networking and public ingress, persistence and backup, observability access,
sibling-repository contracts, and every security and deployment verifier.
Treat the snapshot as recovery input, not as evidence that deployment remains
safe or functional.
