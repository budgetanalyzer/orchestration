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

- `scripts/dev/check-tilt-prerequisites.sh` - Tooling/repo preflight checks and optional runtime security verification.
- `scripts/dev/setup-k8s-tls.sh` - Host-only bootstrap for the browser-facing wildcard certificate and TLS secret.
- `scripts/dev/setup-infra-tls.sh` - Host-only bootstrap for the internal `infra-ca` plus the Redis/PostgreSQL/RabbitMQ TLS secrets. `setup.sh` calls it during the standard local platform bootstrap.
- `scripts/dev/seed-ext-authz-session.sh` - Seeds a test ext-authz session in Redis using the TLS-only in-cluster Redis listener.
- `scripts/dev/install-calico.sh` - Installs pinned Calico CNI for Kind clusters created with `disableDefaultCNI`.
- `scripts/dev/verify-security-prereqs.sh` - Deterministic Phase 0 runtime proof (NetworkPolicy, PSA, Istio, Kyverno smoke policy).
- `scripts/dev/verify-phase-1-credentials.sh` - Phase 1 runtime proof for PostgreSQL, RabbitMQ, Redis ACLs, and ext-authz over Redis TLS.
- `scripts/dev/verify-phase-2-network-policies.sh` - Phase 2 runtime proof for current NetworkPolicy allowlists across Istio ingress, service-to-service, infrastructure, and Istio egress gateway paths.
- `scripts/dev/verify-phase-3-istio-ingress.sh` - Phase 3 runtime proof for Istio ingress/egress hardening, ext_authz integration, ingress path ownership, and forwarded-header behavior.
- `scripts/dev/verify-phase-4-transport-encryption.sh` - Phase 4 runtime proof for Redis/PostgreSQL/RabbitMQ client TLS verification, secondary RabbitMQ listener-state checks, and Phase 1/2 regression coverage.
- `scripts/dev/verify-phase-5-runtime-hardening.sh` - Phase 5 runtime proof for PSA enforcement targets, Istio CNI sidecar compatibility, service-account token hardening, repo-managed workload runtime security contexts, the Session 4 `nginx-gateway` specifics (UID/GID `101`, read-only config/docs mounts, and the explicit `/tmp` writable mount), the Session 5 `budget-analyzer-web` UID/GID `1001` contract, the Redis Session 6 specifics (`runAsUser`/`runAsGroup` plus the explicit `/tmp` and `/data` writable mounts), the PostgreSQL Session 7 specifics (main-container `runAsUser`/`runAsGroup`, explicit `/tmp` and `/var/run/postgresql` writable mounts, plus the hardened `fix-tls-perms` init-container baseline including `readOnlyRootFilesystem: true`), the RabbitMQ Session 8 specifics (`fsGroup`, `runAsUser`/`runAsGroup`, read-only config/TLS mounts, and the explicit `/var/lib/rabbitmq` PVC mount), and Phase 1 through Phase 4 regression coverage. The regression reruns are bounded per script with `--regression-timeout` (default `10m`) so the final Phase 5 gate fails instead of hanging indefinitely.
- `scripts/dev/verify-phase-6-session-7-api-rate-limit-identity.sh` - Phase 6 Session 7 runtime proof that NGINX trusts only the pod-local sidecar hop for `real_ip_*`, preserves the forwarded-header chain, rejects forged external `X-Forwarded-For` bucket selection, and gives distinct downstream clients separate API limiter buckets.
- `scripts/dev/verify-phase-6-edge-browser-hardening.sh` - Phase 6 completion gate. It proves the checked-in dev/strict CSP split, the local-production route contract, same-origin docs delivery without wildcard CORS, direct auth-edge throttling coverage for `/login`, `/auth/*`, `/logout`, and `/login/oauth2/*`, reruns the Session 3 CSP audit and Session 7 API identity verifier, and then reruns the Phase 5 runtime-hardening cascade. It does not replace the manual browser-console validation still required on `/_prod-smoke/` and `/api/docs`.
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
