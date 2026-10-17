# Production Secrets and AI Agent Boundaries

**Date:** 2026-04-12
**Status:** Retired OCI design summary; not an active secret-provisioning plan

The original research selected OCI Vault, instance principals, and External
Secrets Operator for the former OCI demo. OCI is retired, no production
environment is currently configured, and those provider-specific procedures
must not be used as current operator guidance. The lean removed-file archive,
complete-tree Git provenance, and restoration caveats live in
[`archive/oci/README.md`](../../archive/oci/README.md).

The durable security boundaries are provider-independent:

- Never expose staging or production credentials, kubeconfigs, user
  credentials, or session cookies to an agent environment.
- Keep secret values out of Git, generated review artifacts, plans, logs, and
  agent transcripts.
- Treat names, schemas, and non-secret references as configuration; choose and
  review value provisioning separately for each real environment.
- Local development secrets and the exact trusted-agent boundary follow
  [`autonomous-ai-execution.md`](../architecture/autonomous-ai-execution.md)
  and [`secrets-only-handling.md`](../development/secrets-only-handling.md).

The maintained provider-neutral production reference intentionally does not
choose a secret store, workload identity mechanism, production identity
provider, certificate system, or credential-delivery workflow. Those remain
prerequisites for a future, separately authorized deployment project; see
[`deploy/README.md`](../../deploy/README.md).
