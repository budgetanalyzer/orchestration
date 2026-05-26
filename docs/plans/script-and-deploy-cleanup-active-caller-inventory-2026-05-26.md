# Script And Deploy Cleanup: Active Caller Inventory

Date: 2026-05-26

Related plan: `docs/plans/script-and-deploy-cleanup-2026-05-26.md`

## Method

This inventory covers the 93 shell scripts under `scripts/` and
`deploy/scripts/`.

Active references were discovered with `rg` against the repository while
excluding `docs/archive/`, `tmp/`, and `node_modules/`. Reference summaries
below omit uninteresting self-matches unless the self-reference is important
for usage text or a recursive dispatch path.

## Legend

- **Canonical**: `yes` means documented as a normal human/operator entry point.
  `bootstrap order` means listed in the current OCI bootstrap run sequence.
  `lower-level` means documented for direct use only in repair or explicit
  replay cases. `library` means sourced or used as a post-renderer, not a
  normal standalone command.
- **Mutates**: records the main side effects: `none`, `tmp`, `repo files`,
  `sibling repos`, `git`, `cluster`, `host`, `OCI Vault`, `GitHub`, `local
  processes`, or `local data`.
- **Lifecycle**: uses the cleanup plan's buckets where they fit: bootstrap,
  continuing deployment, verification, local ops, or one-time repair. Release
  management and libraries are called out separately because they are real
  active surfaces but not deployment lifecycle scripts.

## Deploy Scripts

| Script | Active refs | Canonical | Mutates | Lifecycle |
| --- | --- | --- | --- | --- |
| `deploy/scripts/01-install-k3s.sh` | `deploy/README.md`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | host, cluster | cluster/platform bootstrap |
| `deploy/scripts/02-bootstrap-cluster.sh` | `deploy/README.md`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | cluster | cluster/platform bootstrap |
| `deploy/scripts/03-render-phase-4-istio-manifests.sh` | `deploy/README.md`; called by `deploy/scripts/04-install-istio.sh`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | tmp | cluster/platform bootstrap render |
| `deploy/scripts/04-install-istio.sh` | `deploy/README.md`; self-usage; `kubernetes/production/README.md`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | cluster, tmp | cluster/platform bootstrap |
| `deploy/scripts/05-install-platform-controllers.sh` | `deploy/README.md`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | cluster | cluster/platform bootstrap |
| `deploy/scripts/07-apply-network-policies.sh` | `deploy/README.md`; referenced by `deploy/scripts/08-verify-network-policy-enforcement.sh`; `docs/research/production-secrets-and-ai-agent-boundaries.md` | bootstrap order | cluster | cluster/platform bootstrap |
| `deploy/scripts/08-verify-network-policy-enforcement.sh` | `deploy/README.md`; `scripts/README.md`; referenced by `deploy/scripts/07-apply-network-policies.sh` | bootstrap order | cluster temporary probes | verification |
| `deploy/scripts/09-render-phase-5-secrets.sh` | `deploy/README.md`; called by `deploy/scripts/10-apply-phase-5-secrets.sh`; `docs/research/auth0-findings.md`; `kubernetes/production/README.md` | yes | tmp | continuing deployment; secret sync render |
| `deploy/scripts/10-apply-phase-5-secrets.sh` | `deploy/README.md`; `docs/research/auth0-findings.md` | yes | cluster, tmp | continuing deployment; secret sync apply |
| `deploy/scripts/11-generate-phase-5-infra-tls.sh` | `deploy/README.md` | yes | local certificate files, cluster secrets | continuing deployment; secret bootstrap |
| `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` | `deploy/README.md`; calls `deploy/scripts/12-update-rabbitmq-definitions-secret.sh` | yes | OCI Vault, local operator receipt | continuing deployment; secret bootstrap |
| `deploy/scripts/12-update-rabbitmq-definitions-secret.sh` | `deploy/README.md`; called by `deploy/scripts/12-bootstrap-phase-5-vault-secrets.sh` | yes | OCI Vault | continuing deployment; secret bootstrap |
| `deploy/scripts/13-render-phase-6-production-manifests.sh` | `deploy/README.md`; called by `deploy/scripts/25-deploy-oci-release.sh`; `kubernetes/production/README.md`; `scripts/guardrails/verify-production-image-overlay.sh` | yes | tmp | continuing deployment; production render |
| `deploy/scripts/14-install-phase-7-kyverno.sh` | `deploy/README.md`; `kubernetes/kyverno/README.md`; `kubernetes/production/README.md` | yes | cluster | continuing deployment; admission bootstrap |
| `deploy/scripts/15-apply-phase-7-policies.sh` | `deploy/README.md`; `kubernetes/kyverno/README.md`; `kubernetes/production/README.md` | yes | cluster | continuing deployment; admission policy apply |
| `deploy/scripts/16-render-phase-11-public-tls-manifests.sh` | `deploy/README.md`; referenced by `deploy/scripts/04-install-istio.sh` | yes | tmp | continuing deployment; public TLS render |
| `deploy/scripts/17-render-production-infrastructure.sh` | `deploy/README.md`; called by `deploy/scripts/18-apply-production-infrastructure.sh`; `kubernetes/production/README.md` | yes | tmp | continuing deployment; infrastructure render |
| `deploy/scripts/18-apply-production-infrastructure.sh` | `deploy/README.md`; `kubernetes/production/README.md` | yes | cluster, tmp | continuing deployment; infrastructure apply |
| `deploy/scripts/20-render-phase-7-observability.sh` | `deploy/README.md`; called by `deploy/scripts/21-apply-phase-7-observability.sh`; `kubernetes/production/README.md`; `scripts/guardrails/verify-production-image-overlay.sh` | yes | tmp | continuing deployment; observability render |
| `deploy/scripts/21-apply-phase-7-observability.sh` | `deploy/README.md`; called by `deploy/scripts/22-apply-production-monitoring.sh`; `kubernetes/production/README.md` | yes | cluster, tmp | continuing deployment; observability apply |
| `deploy/scripts/22-apply-production-monitoring.sh` | `deploy/README.md`; `kubernetes/production/README.md` | yes | cluster, tmp | continuing deployment; monitoring apply |
| `deploy/scripts/23-update-production-release-images.sh` | `deploy/README.md`; called by `deploy/scripts/prepare-oci-manifest-from-current-stack.sh`; `docs-aggregator/README.md`; `docs/ci-cd.md`; cleanup plan; `kubernetes/production/README.md`; `scripts/README.md` | lower-level | repo files, tmp | continuing deployment; baseline renderer |
| `deploy/scripts/24-verify-oci-upgrade-lockstep.sh` | `deploy/README.md`; called by `deploy/scripts/23-update-production-release-images.sh`, `deploy/scripts/25-deploy-oci-release.sh`, and `deploy/scripts/prepare-oci-manifest-from-current-stack.sh`; `docs/ci-cd.md`; `docs/runbooks/oci-release-deployment-checklist.md`; `kubernetes/production/README.md`; `scripts/README.md` | yes | none, tmp | verification |
| `deploy/scripts/25-deploy-oci-release.sh` | `deploy/README.md`; called by `deploy/scripts/deploy-current-oci-manifest.sh`; `docs/ci-cd.md`; cleanup plan; `scripts/README.md` | lower-level | cluster, tmp | continuing deployment; lower-level applier |
| `deploy/scripts/deploy-current-oci-manifest.sh` | `deploy/README.md`; called by `deploy/scripts/prepare-oci-manifest-from-current-stack.sh`; `docs/ci-cd.md`; cleanup plan; `docs/runbooks/oci-release-deployment-checklist.md`; `kubernetes/production/README.md`; `scripts/README.md` | yes | cluster via `25-deploy-oci-release.sh`, tmp | continuing deployment; normal OCI apply |
| `deploy/scripts/lib/common.sh` | sourced by nearly every `deploy/scripts/*.sh`; `deploy/README.md`; `scripts/README.md` | library | none directly | library |
| `deploy/scripts/lib/phase-4-version-contract.sh` | sourced by `deploy/scripts/lib/common.sh`; `scripts/guardrails/verify-phase-7-static-manifests.sh`; `scripts/ops/capture-prometheus-operator-baseline.sh`; `scripts/smoketest/verify-monitoring-rendered-manifests.sh`; `deploy/README.md` | library | none | library; version contract |
| `deploy/scripts/prepare-oci-manifest-from-current-stack.sh` | `deploy/README.md`; `docs/ci-cd.md`; `docs/runbooks/oci-release-deployment-checklist.md`; `kubernetes/production/README.md`; `scripts/README.md`; referenced by `scripts/repo/prepare-lockstep-release.sh` and `scripts/repo/prepare-service-release.sh` | yes | git tags/push in `--push-tags`, repo files in `--resolve-images`, tmp, GHCR reads | continuing deployment; normal local desired-state preparation |

## Repository Scripts

| Script | Active refs | Canonical | Mutates | Lifecycle |
| --- | --- | --- | --- | --- |
| `scripts/bootstrap/check-infra-tls-secrets.sh` | `Tiltfile`; `docs/development/local-environment.md`; `scripts/README.md`; `setup.sh` | yes | none | local bootstrap verification |
| `scripts/bootstrap/check-tilt-prerequisites.sh` | `AGENTS.md`; `docs/dependency-notifications.md`; `docs/development/local-environment.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; `scripts/bootstrap/setup-infra-tls.sh`; `setup.sh` | yes | none | local bootstrap verification |
| `scripts/bootstrap/install-calico.sh` | `docs/dependency-notifications.md`; `docs/development/local-environment.md`; `docs/runbooks/tilt-debugging.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; called by `scripts/bootstrap/check-tilt-prerequisites.sh`; `setup.sh`; stale tests | yes | cluster, Kind node host settings | local cluster bootstrap |
| `scripts/bootstrap/install-verified-tool.sh` | `deploy/README.md`; `docs/ci-cd.md`; `docs/development/local-environment.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; called by bootstrap and guardrail scripts; `setup.sh` | yes | local tool files | local and host bootstrap |
| `scripts/bootstrap/setup-infra-tls.sh` | `AGENTS.md`; `Tiltfile`; `docs/development/database-setup.md`; `docs/development/local-environment.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; called by preflight, smoke, and `setup.sh` | yes, host-only | certificate files, cluster secrets | local bootstrap; forbidden inside AI container |
| `scripts/bootstrap/setup-k8s-tls.sh` | `AGENTS.md`; `Tiltfile`; `docs/architecture/autonomous-ai-execution.md`; `docs/development/local-environment.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; `setup.sh` | yes, host-only | certificate files, cluster secrets | local bootstrap; forbidden inside AI container |
| `scripts/guardrails/check-phase-7-image-pinning.sh` | `scripts/README.md`; called by `scripts/guardrails/verify-phase-7-static-manifests.sh` | no | none | verification; lower-level guardrail |
| `scripts/guardrails/check-secrets-only-handling.sh` | `docs/development/secrets-only-handling.md`; `kubernetes/production/README.md`; `scripts/README.md`; called by `scripts/guardrails/verify-phase-7-static-manifests.sh` | no | none | verification; lower-level guardrail |
| `scripts/guardrails/check-tilt-resource-roots.sh` | `scripts/README.md` | no | none | verification; lower-level guardrail |
| `scripts/guardrails/verify-phase-7-static-manifests.sh` | `docs/ci-cd.md`; `docs/development/secrets-only-handling.md`; `docs/research/single-instance-demo-hosting.md`; `kubernetes/kyverno/README.md`; `scripts/README.md`; called by `scripts/smoketest/smoketest.sh` and `scripts/smoketest/verify-phase-7-security-guardrails.sh` | yes | none, tmp | verification; CI-safe static guardrail |
| `scripts/guardrails/verify-production-image-overlay.sh` | `deploy/README.md`; called by deploy apply/verify scripts; `docs/ci-cd.md`; `kubernetes/kyverno/README.md`; `kubernetes/production/README.md`; `scripts/README.md` | yes | none, tmp, live server dry-run | verification; production static guardrail |
| `scripts/lib/loadtest-common.sh` | sourced by all `scripts/loadtest/*.sh`; `scripts/README.md` | library | none directly | library |
| `scripts/lib/pinned-tool-versions.sh` | `Tiltfile`; `deploy/scripts/lib/common.sh`; `docs/dependency-notifications.md`; `scripts/README.md`; sourced by bootstrap and guardrail scripts; `setup.sh` | library | none | library; version contract |
| `scripts/lib/redis-cli.sh` | sourced by Redis ops scripts and `scripts/smoketest/verify-phase-1-credentials.sh` | library | none directly | library |
| `scripts/loadtest/seed-loadtest-transactions.sh` | `docs/development/local-environment.md`; `scripts/README.md`; uses `scripts/lib/loadtest-common.sh` | yes | cluster fixture data, local session pool read | local ops; loadtest fixtures |
| `scripts/loadtest/seed-loadtest-users.sh` | `docs/development/local-environment.md`; `scripts/README.md`; called by `seed-loadtest-transactions.sh`; uses `scripts/lib/loadtest-common.sh` | yes | cluster fixture data, local session pool | local ops; loadtest fixtures |
| `scripts/loadtest/teardown-loadtest.sh` | `docs/development/local-environment.md`; `scripts/README.md`; uses `scripts/lib/loadtest-common.sh` | yes | cluster fixture data, local session pool | local ops; loadtest fixtures |
| `scripts/ops/capture-prometheus-operator-baseline.sh` | `docs/research/prometheus-operator-rbac-baseline.md`; `scripts/README.md` | yes | repo docs, tmp | local ops; research capture |
| `scripts/ops/flush-redis.sh` | `AGENTS.md`; `docs/development/local-environment.md`; `docs/runbooks/tilt-debugging.md`; `scripts/README.md` | yes | Redis data in cluster | local ops |
| `scripts/ops/grafana-ui-playwright-debug.sh` | `docs/architecture/observability.md`; `scripts/README.md` | yes | tmp debug artifacts | local ops; debugging |
| `scripts/ops/post-render-kiali-server.sh` | `Tiltfile`; `deploy/README.md`; deploy observability scripts; `kubernetes/production/README.md`; `scripts/smoketest/verify-monitoring-rendered-manifests.sh` | library | stdout, tmp | render helper |
| `scripts/ops/post-render-prometheus-stack.sh` | `Tiltfile`; `deploy/README.md`; `deploy/scripts/22-apply-production-monitoring.sh`; `docs/architecture/observability.md`; `kubernetes/production/README.md`; `scripts/README.md`; monitoring render verifier | library | stdout, tmp | render helper |
| `scripts/ops/redis-browse.sh` | `scripts/README.md` | yes | none | local ops; inspection |
| `scripts/ops/render-istio-egress-config.sh` | `Tiltfile`; `deploy/scripts/13-render-phase-6-production-manifests.sh`; `docs/development/local-environment.md`; `docs/research/auth0-findings.md`; `docs/setup/auth0-setup.md`; Istio templates; `scripts/README.md` | yes | stdout/tmp; cluster with `--apply` | local ops and production render helper |
| `scripts/ops/reset-databases.sh` | `scripts/README.md`; ADR context mention | yes | PostgreSQL data in cluster | local ops |
| `scripts/ops/seed-ext-authz-session.sh` | `scripts/README.md`; called by several smoketests | yes | Redis data in cluster | local ops; test fixture |
| `scripts/ops/show-pod-version-labels.sh` | `deploy/scripts/25-deploy-oci-release.sh`; `docs/runbooks/oci-release-deployment-checklist.md`; `scripts/README.md` | yes | none | local ops; production inspection |
| `scripts/ops/start-observability-port-forwards.sh` | `AGENTS.md`; `docs/architecture/observability.md`; `docs/development/getting-started.md`; `docs/development/local-environment.md`; `scripts/README.md`; called by SSH tunnel helper | yes | local processes | local ops; observability access |
| `scripts/ops/start-observability-ssh-tunnels.sh` | `deploy/README.md`; `docs/architecture/observability.md`; `kubernetes/production/README.md`; `scripts/README.md` | yes | local SSH process | local ops; production observability access |
| `scripts/ops/triage-kiali-findings.sh` | `docs/architecture/observability.md`; `docs/runbooks/kiali-expected-warnings.md`; `scripts/README.md`; called by monitoring runtime and Prometheus operator verifiers | yes | tmp/output artifacts, local port-forward | local ops; observability triage |
| `scripts/repo/checkout-main.sh` | cleanup plan; `scripts/README.md` | no | git checkout/pull in sibling repos | repo management; review candidate |
| `scripts/repo/checkout-tag.sh` | cleanup plan; `scripts/README.md` | no | git checkout in sibling repos | repo management; review candidate |
| `scripts/repo/generate-deployment-manifest.sh` | cleanup plan; `scripts/README.md` | lower-level | local manifest output under `tmp/` by default | release management; review candidate |
| `scripts/repo/generate-unified-api-docs.sh` | `docs-aggregator/README.md`; `scripts/README.md`; ADR context mention | yes | repo docs, sibling web docs when present | repo management; docs/API generation |
| `scripts/repo/prepare-lockstep-release.sh` | `scripts/README.md` | yes | none by default; delegates git tagging with `--tag` | release management |
| `scripts/repo/prepare-service-release.sh` | `scripts/README.md` | yes | none by default; delegates git tagging with `--tag` | release management |
| `scripts/repo/release-service-common-snapshot.sh` | `docs/ci-cd.md`; `scripts/README.md` | yes | sibling repo files, git tag/push, Gradle validation | release management |
| `scripts/repo/repo-config.sh` | sourced by repo management scripts; `scripts/README.md`; ADR context mention | library | none | library |
| `scripts/repo/tag-lockstep-release.sh` | `scripts/README.md`; called by `prepare-lockstep-release.sh`; referenced by `tag-release.sh` | yes, explicit release helper | git tag/push in sibling repos | release management |
| `scripts/repo/tag-release.sh` | `docs/ci-cd.md`; `scripts/README.md`; called by `prepare-service-release.sh`; referenced by service-common release helper | yes, explicit release helper | git tag/push in sibling repo | release management |
| `scripts/repo/update-service-common-version.sh` | `scripts/README.md` | yes | sibling repo files | release management |
| `scripts/repo/validate-repos.sh` | cleanup plan; `scripts/README.md`; ADR context mention | no | none by default; optional git checkout/pull with `--fix` or `--clean` | repo management; review candidate |
| `scripts/smoketest/audit-phase-6-session-3-frontend-csp.sh` | `docs/architecture/security-architecture.md`; `docs/development/local-environment.md`; called by `verify-phase-6-edge-browser-hardening.sh` | no | none | verification; lower-level browser security audit |
| `scripts/smoketest/smoketest.sh` | `docs/development/getting-started.md`; `scripts/README.md` | yes | delegates to verification scripts | verification; aggregate local smoke |
| `scripts/smoketest/verify-clean-tilt-deployment-admission.sh` | `docs/architecture/observability.md`; `docs/development/getting-started.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; called by `smoketest.sh`; referenced by Kiali triage | yes | cluster dry-run/probes, tmp | verification |
| `scripts/smoketest/verify-istio-tracing-config.sh` | `docs/architecture/observability.md`; `docs/development/local-environment.md`; `scripts/README.md`; called by `smoketest.sh`; referenced by Kiali triage | yes | none | verification |
| `scripts/smoketest/verify-monitoring-rendered-manifests.sh` | `Tiltfile`; `docs/architecture/observability.md`; `scripts/README.md`; called by `smoketest.sh` and Prometheus operator verifier | yes | none, tmp, Helm cache, server dry-run | verification |
| `scripts/smoketest/verify-monitoring-runtime.sh` | `deploy/scripts/22-apply-production-monitoring.sh`; `docs/development/local-environment.md`; `docs/research/prometheus-operator-rbac-baseline.md`; `scripts/README.md`; called by `smoketest.sh` and Prometheus operator verifier | yes | tmp/output artifacts through Kiali triage | verification |
| `scripts/smoketest/verify-observability-port-forward-access.sh` | `AGENTS.md`; `docs/architecture/observability.md`; `docs/development/local-environment.md`; `scripts/README.md`; called by `smoketest.sh` | yes | temporary local port-forward processes | verification |
| `scripts/smoketest/verify-phase-1-credentials.sh` | `docs/development/database-setup.md`; `docs/runbooks/tilt-debugging.md`; called by phase 4 and 5 verifiers | no | none | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-2-network-policies.sh` | `docs/architecture/port-reference.md`; `docs/runbooks/tilt-debugging.md`; image pinning inventory; called by phase 4 and 5 verifiers | no | cluster temporary probes | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-3-istio-ingress.sh` | `docs/architecture/security-architecture.md`; `docs/architecture/system-overview.md`; `docs/runbooks/tilt-debugging.md`; image pinning inventory; called by phase 5 verifier | no | temporary test/session data | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-4-transport-encryption.sh` | `docs/development/database-setup.md`; image pinning inventory; called by phase 5 verifier | no | none | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-5-runtime-hardening.sh` | `docs/architecture/security-architecture.md`; `docs/development/database-setup.md`; image pinning inventory; called by phase 6 verifier | no | cluster temporary namespace/pods | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-6-edge-browser-hardening.sh` | `docs/architecture/security-architecture.md`; `docs/architecture/session-edge-authorization-pattern.md`; `docs/development/local-environment.md`; `nginx/README.md`; `scripts/README.md`; image pinning inventory; called by phase 7 runtime verifier | yes | temporary test/session data | verification |
| `scripts/smoketest/verify-phase-6-session-7-api-rate-limit-identity.sh` | `docs/architecture/security-architecture.md`; `docs/development/local-environment.md`; `nginx/README.md`; image pinning inventory; called by edge browser verifier | no | temporary test/session data | verification; lower-level security phase check |
| `scripts/smoketest/verify-phase-7-runtime-guardrails.sh` | `docs/architecture/security-architecture.md`; image pinning inventory; called by phase 7 security verifier | no | cluster temporary probes/dry-runs | verification; lower-level guardrail |
| `scripts/smoketest/verify-phase-7-security-guardrails.sh` | `docs/architecture/security-architecture.md`; `docs/ci-cd.md`; `docs/development/getting-started.md`; `docs/tilt-kind-setup-guide.md`; `kubernetes/kyverno/README.md`; `scripts/README.md`; called by `smoketest.sh` | yes | delegates to static and runtime verifiers | verification |
| `scripts/smoketest/verify-prometheus-operator-least-privilege.sh` | `scripts/README.md` | yes | tmp/output artifacts | verification |
| `scripts/smoketest/verify-security-prereqs.sh` | `docs/architecture/autonomous-ai-execution.md`; `docs/architecture/security-architecture.md`; `docs/architecture/system-overview.md`; `docs/development/getting-started.md`; `docs/runbooks/tilt-debugging.md`; `docs/tilt-kind-setup-guide.md`; `scripts/README.md`; called by preflight, `smoketest.sh`, and stale tests | yes | none | verification |
| `scripts/smoketest/verify-session-architecture-phase-5.sh` | `docs/architecture/session-edge-authorization-pattern.md`; `docs/runbooks/tilt-debugging.md`; `scripts/README.md`; called by `smoketest.sh` | yes | none | verification |

## Cleanup Signals From The Inventory

- The confirmed obsolete script deletion pass has been completed. It removed
  the superseded release-manifest generator, the rejected host-redirect
  experiment executable, the completed one-time Redis migration helper, and the
  one-off GitHub repository-topic admin helper.
- The broad git write helpers remain active only as documented repo-management
  commands or review candidates: `checkout-main.sh`, `checkout-tag.sh`, and
  the optional `--fix`/`--clean` paths in `validate-repos.sh`.
- `deploy/scripts/23-update-production-release-images.sh` and
  `deploy/scripts/25-deploy-oci-release.sh` have active wrapper callers and are
  documented as lower-level repair/replay entry points, not normal operator
  commands.
