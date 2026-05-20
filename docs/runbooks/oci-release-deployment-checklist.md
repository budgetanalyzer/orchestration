# OCI Release Deployment Checklist

Use this template to record evidence for an OCI release deployment. It is a
run-log shape, not a secret store: do not paste kubeconfigs, private keys,
tokens, passwords, cookie values, or raw secret payloads.

The recurring deployment commands live in [deploy/README.md](../../deploy/README.md)
and the script help for [25-deploy-oci-release.sh](../../deploy/scripts/25-deploy-oci-release.sh).
Use those sources for the current command sequence, then record the evidence
below.

## Prerequisites

- [ ] The production image baseline has been updated and reviewed.
- [ ] The release manifest exists under `tmp/releases/` or another reviewed
  operator path.
- [ ] The operator shell is on the OCI host, or is explicitly using an OCI
  host kubeconfig with `--kubeconfig`.
- [ ] `KUBECONFIG` points at the intended OCI k3s cluster.
- [ ] `~/.config/budget-analyzer/instance.env` exists on the OCI host.
- [ ] Any required certificate generation is run by the human operator on the
  host, not from the AI container.

## Release Summary

| Field | Value |
| --- | --- |
| Release version | `vX.Y.Z` |
| Deployment date | `YYYY-MM-DD` |
| Operator |  |
| Selected mode | `verify-only`, `app-only`, `lockstep`, `platform-only`, or `infrastructure-only` |
| Dry run first | `yes` or `no` |
| Release manifest | `tmp/releases/vX.Y.Z.yaml` |
| Production image inventory ref | `kubernetes/production/apps/image-inventory.yaml` |
| Orchestration checkout ref |  |
| Snapshot directory | `tmp/oci-release-deploy/<timestamp>-<mode>-<version>` |

## Source Commits

| Repository | Commit SHA | Release tag present | Notes |
| --- | --- | --- | --- |
| `orchestration` |  |  |  |
| `service-common` |  |  |  |
| `transaction-service` |  |  |  |
| `currency-service` |  |  |  |
| `permission-service` |  |  |  |
| `session-gateway` |  |  |  |
| `budget-analyzer-web` |  |  |  |

## Artifact Workflows

| Artifact | Workflow run URL | Result |
| --- | --- | --- |
| `transaction-service` |  |  |
| `currency-service` |  |  |
| `permission-service` |  |  |
| `session-gateway` |  |  |
| `budget-analyzer-web` |  |  |
| `ext-authz` |  |  |

## Digest-Pinned Images

| Artifact | Digest-pinned image ref |
| --- | --- |
| `transaction-service` | `ghcr.io/budgetanalyzer/transaction-service:X.Y.Z@sha256:...` |
| `currency-service` | `ghcr.io/budgetanalyzer/currency-service:X.Y.Z@sha256:...` |
| `permission-service` | `ghcr.io/budgetanalyzer/permission-service:X.Y.Z@sha256:...` |
| `session-gateway` | `ghcr.io/budgetanalyzer/session-gateway:X.Y.Z@sha256:...` |
| `budget-analyzer-web` | `ghcr.io/budgetanalyzer/budget-analyzer-web:X.Y.Z@sha256:...` |
| `ext-authz` | `ghcr.io/budgetanalyzer/ext-authz:X.Y.Z@sha256:...` |

## Release Manifest Flags

| Flag | Value | Action taken |
| --- | --- | --- |
| `platform_changed` | `true` or `false` |  |
| `infrastructure_changed` | `true` or `false` |  |
| `secrets_changed` | `true` or `false` |  |
| `observability_changed` | `true` or `false` |  |
| `public_tls_reapply_required` | `true` or `false` |  |

## Preflight Snapshot

| Check | Evidence | Result |
| --- | --- | --- |
| Current Kubernetes context |  |  |
| Node summary |  |  |
| Pod summary |  |  |
| Workload summary |  |  |
| Gateway and HTTPRoute summary |  |  |
| Istio policy summary |  |  |
| NetworkPolicy summary |  |  |
| Helm release summary |  |  |
| Live image summary |  |  |
| Live runtime release labels | `./scripts/ops/show-pod-version-labels.sh --expected-version vX.Y.Z --tracked-only --strict` |  |
| Public release metadata, if public TLS is active | `curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json` |  |

## Scripts Run

| Order | Script or command | Arguments | Result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | `deploy/scripts/24-verify-oci-upgrade-lockstep.sh` |  |  |  |
| 2 | `scripts/guardrails/verify-production-image-overlay.sh` |  |  |  |
| 3 | `deploy/scripts/25-deploy-oci-release.sh` | `--mode ... --release-version ...` |  |  |

Add rows for any reviewed lower-level deployment scripts used instead of the
master script.

## Rollout Results

| Workload | Namespace | Result | Evidence |
| --- | --- | --- | --- |
| `transaction-service` | `default` |  |  |
| `currency-service` | `default` |  |  |
| `permission-service` | `default` |  |  |
| `session-gateway` | `default` |  |  |
| `ext-authz` | `default` |  |  |
| `nginx-gateway` | `default` |  |  |
| PostgreSQL | `infrastructure` |  |  |
| RabbitMQ | `infrastructure` |  |  |
| Redis | `infrastructure` |  |  |
| Prometheus stack | `monitoring` |  |  |
| Jaeger | `monitoring` |  |  |
| Kiali | `monitoring` |  |  |

## Smoke Test Results

| Proof | Result | Evidence |
| --- | --- | --- |
| OCI lockstep static verifier |  |  |
| Production image/render verifier |  |  |
| NetworkPolicy enforcement verifier |  |  |
| Observability port-forward access verifier |  |  |
| Monitoring runtime verifier |  |  |
| Public root route, if public TLS is active |  |  |
| Public `/api-docs` route, if public TLS is active |  |  |
| Public `/api-docs/release-metadata.json`, if public TLS is active |  |  |
| Browser login/session flow |  |  |
| Representative API request |  |  |

## Post-Deploy Snapshot

| Check | Evidence | Result |
| --- | --- | --- |
| Pod summary |  |  |
| Workload summary |  |  |
| Gateway and HTTPRoute summary |  |  |
| Istio policy summary |  |  |
| NetworkPolicy summary |  |  |
| Helm release summary |  |  |
| Live image summary |  |  |
| Live runtime release labels |  |  |
| Browser-visible release metadata |  |  |
| Observability remains internal-only |  |  |

## Rollback Notes

| Field | Value |
| --- | --- |
| Previous release version |  |
| Previous release manifest or image inventory ref |  |
| Safe app-only rollback candidate | `yes`, `no`, or `needs review` |
| Data migration risk |  |
| RabbitMQ queue migration or discard decision |  |
| Platform downgrade risk |  |
| Public TLS or NLB restoration notes |  |
| Rollback command or reviewed runbook path |  |

## Follow-Ups

| Item | Owner | Tracking link | Due |
| --- | --- | --- | --- |
|  |  |  |  |
