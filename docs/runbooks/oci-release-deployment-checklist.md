# OCI Release Deployment Checklist

Use this template to record evidence for an OCI release or deployment. It is a
run-log shape, not a secret store: do not paste kubeconfigs, private keys,
tokens, passwords, cookie values, or raw secret payloads.

The normal production shape is local desired-state preparation, human review,
and OCI-host apply, using the terminology from [docs/ci-cd.md](../ci-cd.md).
GitHub Actions builds release images from source tags; the checked-in
production manifest and image inventory record the desired digest-pinned
artifact set.

`service-common` is a shared Java library version. Record it where it changed
or where a Java artifact consumes it, but do not require a `service-common`
bump for config-only deployments or unrelated service releases.

The recurring deployment commands live in [deploy/README.md](../../deploy/README.md)
and the script help for
[prepare-oci-manifest-from-current-stack.sh](../../deploy/scripts/prepare-oci-manifest-from-current-stack.sh).
Use those sources for the current command sequence, then record the evidence
below.

## Prerequisites

- [ ] `deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag
  vX.Y.Z --plan-only` has been reviewed for tag actions and expected GHCR
  image tags.
- [ ] Any Java `service-common` change has already been published and Java
  consumers are pinned to the intended `serviceCommon` version.
- [ ] The local preparation command completed and produced a reviewed
  orchestration diff.
- [ ] The orchestration desired-state diff was committed and pushed.
- [ ] The OCI host has pulled the orchestration commit that contains the
  reviewed desired-state files.
- [ ] On the OCI host, `KUBECONFIG` points at the intended k3s cluster.
- [ ] On the OCI host, `~/.config/budget-analyzer/instance.env` exists.
- [ ] Any required certificate generation is run by the human operator on the
  host, not from the AI container.

## Release Summary

| Field | Value |
| --- | --- |
| Deployment type | `checked-in desired-state apply` |
| Release version, if applicable | `vX.Y.Z` or `n/a` |
| Deployment id or release label |  |
| Deployment date | `YYYY-MM-DD` |
| Operator |  |
| Local plan-only first | `yes` or `no` |
| Source tag | `vX.Y.Z` |
| Local desired-state manifest | `tmp/deployments/oci-YYYYMMDDTHHMMSSZ.yaml` |
| Production image inventory ref | `kubernetes/production/apps/image-inventory.yaml` |
| Orchestration checkout ref |  |
| OCI apply evidence directory | `tmp/oci-release-deploy/<timestamp>-manifest-<deployment-id>` |

## Source Commits

| Repository | Commit SHA | Source ref or tag | `service-common` version, if consumed | Notes |
| --- | --- | --- | --- | --- |
| `orchestration` |  |  |  |  |
| `service-common` |  |  |  |  |
| `transaction-service` |  |  |  |  |
| `currency-service` |  |  |  |  |
| `permission-service` |  |  |  |  |
| `session-gateway` |  |  |  |  |
| `budget-analyzer-web` |  |  |  |  |
| `ext-authz` |  |  |  |  |

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

| Artifact | Status | Digest-pinned image ref |
| --- | --- | --- |
| `transaction-service` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/transaction-service:X.Y.Z@sha256:...` |
| `currency-service` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/currency-service:X.Y.Z@sha256:...` |
| `permission-service` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/permission-service:X.Y.Z@sha256:...` |
| `session-gateway` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/session-gateway:X.Y.Z@sha256:...` |
| `budget-analyzer-web` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/budget-analyzer-web:X.Y.Z@sha256:...` |
| `ext-authz` | `changed` or `unchanged` | `ghcr.io/budgetanalyzer/ext-authz:X.Y.Z@sha256:...` |

## Preflight Snapshot

| Check | Evidence | Result |
| --- | --- | --- |
| Local preparation plan | `deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z --plan-only` |  |
| Local preparation command | `deploy/scripts/prepare-oci-manifest-from-current-stack.sh --source-tag vX.Y.Z` |  |
| Orchestration diff reviewed | `git diff` |  |
| Orchestration commit pushed | commit SHA |  |
| OCI host pulled commit | `git rev-parse HEAD` |  |
| Current Kubernetes context |  |  |
| Node summary |  |  |
| Pod summary |  |  |
| Workload summary |  |  |
| Gateway and HTTPRoute summary |  |  |
| Istio policy summary |  |  |
| NetworkPolicy summary |  |  |
| Helm release summary |  |  |
| Live image summary |  |  |
| Live runtime deployment metadata | `./scripts/ops/show-pod-version-labels.sh --deployment-manifest kubernetes/production/apps/deployment-manifest.yaml --tracked-only --strict` |  |
| Public release metadata, if public TLS is active | `curl -fsS https://demo.budgetanalyzer.org/api-docs/release-metadata.json` |  |

## Scripts Run

| Order | Script or command | Arguments | Result | Evidence |
| --- | --- | --- | --- | --- |
| 1 | `deploy/scripts/prepare-oci-manifest-from-current-stack.sh` | `--source-tag vX.Y.Z --plan-only` |  |  |
| 2 | `deploy/scripts/prepare-oci-manifest-from-current-stack.sh` | `--source-tag vX.Y.Z` plus options used |  |  |
| 3 | `git diff` | review production desired-state files |  |  |
| 4 | `git pull` | on OCI host |  |  |
| 5 | `deploy/scripts/deploy-current-oci-manifest.sh` | checked-in manifest apply |  |  |
| 6 | `deploy/scripts/24-verify-oci-upgrade-lockstep.sh` | optional rerun after pull |  |  |

Add rows only for reviewed lower-level recovery commands used to replay the
same complete desired-state manifest.

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
| Live runtime deployment metadata |  |  |
| Browser-visible deployment metadata |  |  |
| Observability remains internal-only |  |  |

## Rollback Notes

| Field | Value |
| --- | --- |
| Previous deployment id |  |
| Previous deployment manifest or image inventory ref |  |
| Complete rollback desired-state manifest available | `yes`, `no`, or `needs review` |
| Artifact driving rollback, if any |  |
| Data migration risk |  |
| RabbitMQ queue migration or discard decision |  |
| Platform downgrade risk |  |
| Public TLS or NLB restoration notes |  |
| Rollback command or reviewed runbook path |  |

## Follow-Ups

| Item | Owner | Tracking link | Due |
| --- | --- | --- | --- |
|  |  |  |  |
