# Retired OCI Deployment Archive

**Status:** Frozen historical reference; unmaintained and not an active
deployment path

Oracle Cloud Infrastructure (OCI) is retired for Budget Analyzer because the
available OCI Free Tier capacity is no longer sufficient for the full stack.
There was no production environment when this retirement archive was created,
and none is currently configured. The files here remain unmaintained design
and recovery input for a separately authorized OCI restoration project.

## Provenance

- Baseline commit: `60510f4ce9331968988516947f394152f6aa0da4`
- Public discovery tag: `pre-oci-archive`
- Source layout: original repository-relative paths are retained below this
  directory
- Fidelity inventory: [`SHA256SUMS`](SHA256SUMS)

The commit is the durable, immutable provenance identity. The lightweight tag
is its convenient public discovery name; its direct resolution was verified as
`60510f4ce9331968988516947f394152f6aa0da4` when this archive was assembled. A
tag can be moved or deleted, so recovery must confirm its resolution against
the recorded commit.

This directory is intentionally lean. It contains byte-for-byte copies of only
the 44 OCI retirement files removed from active repository paths. Each file's
Git executable mode also matches its original path at the baseline commit.
Files that remained active, including reusable and mixed inputs consumed by the
former implementation, are not duplicated here. The complete pre-retirement
repository tree is preserved by Git at the baseline commit, not by this
directory.

## Inventory

`SHA256SUMS` is the exact file-level inventory. Its entries use paths relative
to this directory, which are also the files' original repository-relative
paths.

| Original path category | Files | Contents |
| --- | ---: | --- |
| `deploy/instance.env.template` | 1 | Retired OCI instance configuration template. |
| `deploy/manifests/ingress-bootstrap/**` | 2 | Ingress bootstrap templates. |
| `deploy/manifests/public-tls/**` | 5 | Public TLS and ingress templates. |
| `deploy/manifests/secret-sync/**` | 4 | Secret-store and synchronized-secret templates. |
| `deploy/scripts/bootstrap/**` | 6 | k3s and cluster bootstrap scripts. |
| `deploy/scripts/lib/**` | 4 | Retired OCI deployment and release libraries. |
| `deploy/scripts/reconcile/**` | 5 | Cluster reconciliation scripts. |
| `deploy/scripts/release/**` | 2 | OCI release preparation and apply scripts. |
| `deploy/scripts/render/public-tls.sh` | 1 | Public TLS renderer. |
| `deploy/scripts/secrets/**` | 5 | Secret and infrastructure TLS scripts. |
| `deploy/scripts/verify/**` | 2 | Network-policy and OCI upgrade verification scripts. |
| `kubernetes/istio/cni-k3s-values.yaml` | 1 | Retired k3s-specific Istio CNI values. |
| `kubernetes/production/istio/**` | 1 | Retired production authorization policy. |
| `kubernetes/production/nginx/**` | 4 | Retired production NGINX configuration and includes. |
| `scripts/ops/start-observability-ssh-tunnels.sh` | 1 | Retired OCI observability SSH tunnel helper. |

## Deliberate exclusions

The archive does not duplicate active or reusable inputs merely because the
retired OCI implementation consumed them. In particular, it excludes active
documentation and scripts, shared Kubernetes resources, generated OpenAPI
outputs, Grafana dashboards, the Tiltfile, and historical versions of files
that still have active paths. Mixed and reusable dependencies must be inspected
in the complete tagged tree rather than inferred from their current versions.

The archive also excludes ignored instance configuration, generated secret
environment files, OCI credentials, Vault values, user credentials, session
material, SSH private keys, certificates, certificate private keys,
kubeconfigs, rendered output, release evidence, logs, caches, container or
cluster state, live OCI state, sibling repositories, and built application
artifacts. General repository secret detection still applies to this
directory.

## Read-only historical reconstruction

Use Git to inspect material that is not copied into this lean archive. From a
clone containing the public tag, first verify that the tag still names the
recorded commit:

```bash
test "$(git rev-parse 'pre-oci-archive^{commit}')" = \
  60510f4ce9331968988516947f394152f6aa0da4
```

Then inspect a historical path without restoring or executing it:

```bash
git show pre-oci-archive:PATH
git show 60510f4ce9331968988516947f394152f6aa0da4:PATH
```

Use the commit form when the tag is unavailable or its verified resolution
does not match. `PATH` is the original repository-relative path, such as
`docs/runbooks/oci-release-deployment-checklist.md`. These commands are for
read-only discovery; active tooling must not consume the tag, baseline commit,
or archive.

## Maintenance and restoration boundary

Do not execute preserved scripts from `archive/oci/`. Executable mode bits are
retained only for fidelity. The files deliberately keep their original paths,
root-discovery assumptions, commands, and historical wording, so relocating
them here does not make them a supported entry point.

Renovate ignores `archive/oci/**`. Maintained image-pinning inventories,
deployment acceptance checks, shell-validation sweeps, build discovery, and
release/update automation must continue to target active paths only. Do not
modernize these frozen copies when an active check changes.

The old implementation is unmaintained and is not claimed to remain safe,
complete, or executable. Restoring OCI requires a new, explicitly authorized
and independently reviewed project. Reassess capacity and cost, current OCI
APIs, operating-system and ARM64 support, Kubernetes and k3s compatibility,
chart and image provenance, secret and certificate handling, networking and
ingress, persistence and backup, observability access, sibling-repository
contracts, and all security and deployment verifiers before reusing any
historical material.
