# Runbooks

Operational guides for debugging and troubleshooting the Budget Analyzer development environment.

Runbooks assume you already used the supported setup path in
[../development/getting-started.md](../development/getting-started.md). If the
stack is not up yet, start there first.

## Available Runbooks

| Runbook | Description | When to Use |
|---------|-------------|-------------|
| [Tilt Debugging](tilt-debugging.md) | Debug Tilt/Kind local development environment | Services not starting, auth failures, network issues |
| [Kiali Expected Warnings](kiali-expected-warnings.md) | Reference for Kiali warnings this repo intentionally ignores | Kiali triage shows low-signal warnings and you need the repo policy |
| [OCI Release Deployment Checklist](oci-release-deployment-checklist.md) | Evidence template for OCI release deploys | Running or reviewing `deploy/scripts/25-deploy-oci-release.sh` |
| [OCI Single-Service Release](oci-single-service-release.md) | Procedure for deploying one changed runtime artifact | One service or frontend image changes and unrelated artifacts stay pinned |
| [OCI Single-Service Rollback](oci-single-service-rollback.md) | Procedure for restoring one artifact from a previous manifest | A selected app-only rollout needs rollback |
| [OCI Candidate Deployment](oci-candidate-deployment.md) | Staging-window flow for tag-required candidate images | Testing a candidate image before a SemVer release tag |

## Runbook Philosophy

These runbooks follow a **decision tree approach**:
1. Start with the symptom you're seeing
2. Follow the diagnostic steps
3. Each step either resolves the issue or points to the next diagnostic

## Quick Links

### Tilt Development
- **Tilt UI**: http://localhost:10350
- **App URL**: https://app.budgetanalyzer.localhost
- **API Base**: https://app.budgetanalyzer.localhost/api

### Related Documentation
- [Getting Started](../development/getting-started.md) - Supported local
  startup path
- [Local Environment Mechanics](../development/local-environment.md) - How the
  local environment works after bring-up
- [Tilt/Kind Manual Deep Dive](../tilt-kind-setup-guide.md) - Manual bootstrap
  internals only; not the default onboarding path
- [Oracle Cloud Deployment Path](../../deploy/README.md) - OCI deployment
  script order, reviewed inputs, and operator-facing release helpers
- [NGINX Gateway README](../../nginx/README.md) - Routing configuration
- [AGENTS.md](../../AGENTS.md) - Architecture overview

## Contributing

When adding new runbooks:
1. Use the existing runbook as a template
2. Include a quick reference section at the top
3. Organize by symptom, not by component
4. Include actual commands that can be copy-pasted
5. Add the runbook to the table above
