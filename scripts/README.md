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
- `@references` point to existing files (e.g., `@nginx/nginx.dev.conf`)
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
- `scripts/dev/install-calico.sh` - Installs pinned Calico CNI for Kind clusters created with `disableDefaultCNI`.
- `scripts/dev/verify-security-prereqs.sh` - Deterministic Phase 0 runtime proof (NetworkPolicy, PSA, Istio, Kyverno smoke policy).

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
