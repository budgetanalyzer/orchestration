# Scripts Directory

This directory contains automation and tooling scripts for the Budget Analyzer orchestration repository.

## Documentation Validation Scripts

### validate-claude-context.sh

Validates AGENTS.md files for broken references and documentation issues.

**Usage:**
```bash
# From repository root
./scripts/validate-claude-context.sh

# Or from scripts directory
cd scripts && ./validate-claude-context.sh

# Or from anywhere with full path
/path/to/orchestration/scripts/validate-claude-context.sh
```

**Note:** The script automatically changes to the repository root directory, so it works correctly regardless of where you call it from.

**What it checks:**
- `@references` point to existing files (e.g., `@nginx/nginx.k8s.conf`)
- AGENTS.md files are not too large (< 200 lines recommended for pattern-based docs)
- Common commands referenced (docker compose, mvnw) are available

**Exit codes:**
- `0` - All checks passed (with or without warnings)
- `1` - Validation failed (broken references found)

**Recommended usage:**
- Run before committing changes to AGENTS.md files
- Add to CI/CD pipeline to catch drift early
- Run after reorganizing documentation structure

### doc-coverage-report.sh

Reports on documentation coverage across the Budget Analyzer project.

**Usage:**
```bash
# From repository root
./scripts/doc-coverage-report.sh

# Or from scripts directory
cd scripts && ./doc-coverage-report.sh

# Or from anywhere with full path
/path/to/orchestration/scripts/doc-coverage-report.sh
```

**Note:** The script automatically changes to the repository root directory, so it works correctly regardless of where you call it from.

**What it reports:**
- AGENTS.md files presence and size
- Documentation structure (docs/architecture, docs/decisions, etc.)
- Architecture Decision Records (ADRs)
- NGINX gateway configuration
- Docker Compose configuration
- Service-common documentation
- Service API documentation (OpenAPI specs)

**Output:**
- Summary with pass/fail status for each category
- Overall coverage percentage
- Color-coded status (Excellent/Good/Fair/Poor)

**Recommended usage:**
- Run quarterly to assess documentation health
- Use to identify gaps in documentation
- Track improvement over time

## Repository Management Scripts

### repo-config.sh

Configuration for repository structure and service locations.

### validate-repos.sh

Validates repository structure and checks for common issues.

**Usage:**
```bash
./scripts/validate-repos.sh
```

## Release Management Scripts

### tag-release.sh

Creates and pushes release tags for services.

**Usage:**
```bash
./scripts/tag-release.sh v1.2.3
```

## API Documentation Scripts

### generate-unified-api-docs.sh

Generates unified API documentation from all services.

**Usage:**
```bash
./scripts/generate-unified-api-docs.sh
```

## Development Scripts

Located in `scripts/dev/` directory - for development environment setup and maintenance.

Key scripts:

- `scripts/dev/install-verified-tool.sh` - Host-side installer for the repo-pinned `kubectl`, Helm, Tilt, `mkcert`, `kubeconform`, `kube-linter`, and `kyverno` releases. It verifies checked-in SHA-256 values before installing.
- `scripts/dev/check-tilt-prerequisites.sh` - Tooling/repo preflight checks and optional runtime security verification.
- `scripts/dev/setup-k8s-tls.sh` - Host-only bootstrap for the browser-facing wildcard certificate and TLS secret.
- `scripts/dev/setup-infra-tls.sh` - Host-only bootstrap for the internal `infra-ca` plus the Redis/PostgreSQL/RabbitMQ TLS secrets. `setup.sh` calls it during the standard local platform bootstrap.
- `scripts/dev/render-istio-egress-config.sh` - Renders or applies the checked-in Auth0/FRED Istio egress manifests. The Auth0 host is derived from `AUTH0_ISSUER_URI` so the egress allowlist can stay aligned with the `auth0-credentials` secret in both local Tilt and production secret-sourcing flows.
- `scripts/dev/seed-ext-authz-session.sh` - Seeds a test ext-authz session in Redis using the TLS-only in-cluster Redis listener.
- `scripts/dev/install-calico.sh` - Installs pinned Calico CNI for Kind clusters created with `disableDefaultCNI`.
- `scripts/dev/verify-security-prereqs.sh` - Deterministic Phase 0 runtime proof (NetworkPolicy, PSA, Istio readiness, and the retained Kyverno smoke-policy bootstrap check that now runs alongside the broader Phase 7 admission suite).
- `scripts/dev/verify-phase-1-credentials.sh` - Phase 1 runtime proof for PostgreSQL, RabbitMQ, Redis ACLs, and ext-authz over Redis TLS.
- `scripts/dev/verify-phase-2-network-policies.sh` - Phase 2 runtime proof for current NetworkPolicy allowlists across Istio ingress, service-to-service, infrastructure, and Istio egress gateway paths.
- `scripts/dev/verify-phase-3-istio-ingress.sh` - Phase 3 runtime proof for Istio ingress/egress hardening, ext_authz integration, ingress path ownership, forwarded-header behavior, and `AUTH0_ISSUER_URI` to egress-host alignment.
- `scripts/dev/verify-phase-4-transport-encryption.sh` - Phase 4 runtime proof for Redis/PostgreSQL/RabbitMQ client TLS verification, secondary RabbitMQ listener-state checks, and Phase 1/2 regression coverage.
- `scripts/dev/verify-phase-5-runtime-hardening.sh` - Phase 5 runtime proof for PSA enforcement targets, Istio CNI sidecar compatibility, service-account token hardening, repo-managed workload runtime security contexts, the Session 4 `nginx-gateway` specifics (UID/GID `101`, read-only config/docs mounts, and the explicit `/tmp` writable mount), the Session 5 `budget-analyzer-web` UID/GID `1001` contract, the Redis Session 6 specifics (`runAsUser`/`runAsGroup` plus the explicit `/tmp` and `/data` writable mounts), the PostgreSQL Session 7 specifics (main-container `runAsUser`/`runAsGroup`, explicit `/tmp` and `/var/run/postgresql` writable mounts, plus the hardened `fix-tls-perms` init-container baseline including `readOnlyRootFilesystem: true`), the RabbitMQ Session 8 specifics (`fsGroup`, `runAsUser`/`runAsGroup`, read-only config/TLS mounts, and the explicit `/var/lib/rabbitmq` PVC mount), and Phase 1 through Phase 4 regression coverage. The regression reruns are bounded per script with `--regression-timeout` (default `10m`) so the final Phase 5 gate fails instead of hanging indefinitely.
- `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` - Phase 6 Session 7 runtime proof that NGINX trusts only the pod-local sidecar hop for `real_ip_*`, preserves the forwarded-header chain, rejects forged external `X-Forwarded-For` bucket selection, and gives distinct downstream clients separate API limiter buckets.
- `scripts/dev/verify-phase-6-edge-browser-hardening.sh` - Phase 6 completion gate. It proves the checked-in dev/strict CSP split on the real app paths, the local-production route contract, direct auth-edge throttling coverage for `/login`, `/auth/*`, `/logout`, and `/login/oauth2/*`, reruns the Session 3 CSP audit and Session 7 API identity verifier, and then reruns the Phase 5 runtime-hardening cascade. It still probes `/api/docs`, but docs-route problems are warning-only so breakage stays visible without blocking Phase 6 completion. It does not replace the manual browser-console validation still required on `/_prod-smoke/`.
- `scripts/dev/check-phase-7-image-pinning.sh` - Static Phase 7 Session 2 scan for orchestration-owned image refs. It reads the maintained inventories in `scripts/dev/lib/phase-7-image-pinning-targets.txt` and `scripts/dev/lib/phase-7-allowed-latest.txt`, validates that the approved local-image list still matches the checked-in `repo:latest` contract, fails if an orchestration-owned third-party `image:`/`FROM`/verifier image constant is missing `@sha256:`, and fails if any unexpected checked-in `:latest` appears outside the approved local Tilt image repos. It also exposes the approved repo list and representative `:tilt-<hash>` refs for the static replay guard.
- `scripts/dev/verify-phase-7-static-manifests.sh` - Phase 7 Session 6 local static guardrail gate. It bootstraps pinned `kubeconform`, `kube-linter`, and `kyverno` binaries into a repo-local cache, validates checked-in manifests, runs the checked-in Kyverno fixture suite, runs a generated Kyverno replay for representative approved local Tilt `:tilt-<hash>` deploy refs using the current Tilt `imagePullPolicy: IfNotPresent` contract, reuses the image-pinning check, scans active setup guidance for forbidden pipe-to-shell patterns, verifies namespace PSA labels, and ships `--self-test` to prove the workflow rejects intentional bad fixtures.
- `scripts/dev/verify-clean-tilt-deployment-admission.sh` - Host-side clean-start proof for the app workloads after `./setup.sh` and `tilt up`. It waits for the seven expected default-namespace deployments, checks their rollouts, prints deployment/pod/event summaries, and fails if `phase7-require-third-party-image-digests` still reports `PolicyViolation` events in `default`.
- `scripts/dev/verify-phase-7-runtime-guardrails.sh` - Phase 7 Session 7 live-cluster guardrail proof. It creates pinned, policy-compliant Redis, PostgreSQL, and RabbitMQ probe pods plus self-cleaning temporary `NetworkPolicy` rules, proves Redis ACL command/key-pattern denials, proves PostgreSQL cross-database denials, proves RabbitMQ least-privilege denials over the live AMQPS path used by workloads, explicitly verifies the temporary probe resources and forbidden RabbitMQ vhost are cleaned up, and then reruns `scripts/dev/verify-phase-6-edge-browser-hardening.sh` as the reused runtime regression umbrella for the intended Phase 2 through Phase 6 coverage.
- `scripts/dev/verify-phase-7-security-guardrails.sh` - Final local Phase 7 completion gate. It runs `scripts/dev/verify-phase-7-static-manifests.sh` first and `scripts/dev/verify-phase-7-runtime-guardrails.sh` second, keeping CI intentionally static-only while giving contributors one clear local command for full Phase 7 completion. It accepts only the narrow runtime timeout passthrough flags `--runtime-wait-timeout` and `--runtime-regression-timeout`.
- `scripts/dev/lib/redis-cli.sh` - Shared shell helper for Redis TLS commands executed inside the Redis pod.

All verification scripts execute against the current `kubectl` context. If they
report missing pods, secrets, or policies while Tilt appears healthy, confirm
the active context and Tilt resource state from the same host shell first.

## Adding New Scripts

When adding a new script:

1. **Create script** in appropriate directory
2. **Make executable**: `chmod +x scripts/path/to/script.sh`
3. **Add documentation** to this README
4. **Test thoroughly** before committing
5. **Add usage examples** in comments at top of script
6. **Follow conventions**:
   - Use `#!/usr/bin/env bash` shebang
   - Use `set -e` for error handling
   - Include clear echo messages
   - Document exit codes
   - Add description as second comment

**Example script header:**
```bash
#!/usr/bin/env bash
# scripts/my-new-script.sh
# Brief description of what this script does

set -e

# Your code here
```

## Script Organization

Current structure:
```
scripts/
├── README.md                          # This file
├── validate-claude-context.sh         # AGENTS.md validation
├── doc-coverage-report.sh             # Documentation coverage report
├── validate-repos.sh                  # Repository validation
├── repo-config.sh                     # Repository configuration
├── tag-release.sh                     # Release tagging
├── generate-unified-api-docs.sh       # API documentation generation
└── dev/                               # Development environment scripts
    └── (development scripts)
```

## Best Practices

1. **Make scripts idempotent** - safe to run multiple times
2. **Provide clear feedback** - use echo statements
3. **Handle errors gracefully** - check prerequisites
4. **Document exit codes** - make scripts CI-friendly
5. **Test in clean environment** - don't assume state
6. **Keep scripts focused** - one script, one purpose

## CI/CD Integration

These scripts are designed to be run in CI/CD pipelines:

- **validate-claude-context.sh** - Run on PRs that touch documentation
- **doc-coverage-report.sh** - Run periodically (weekly/monthly)
- **validate-repos.sh** - Run on all PRs

See `.github/workflows/` (if using GitHub Actions) for integration examples.
