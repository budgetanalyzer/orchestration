# Single-Instance Demo Hosting Research

**Date:** 2026-04-06
**Status:** Historical hosting research; no provider is selected

This research explored whether the full Budget Analyzer stack could run as a
low-cost, single-node public demo without removing Kubernetes, Istio, the
security layers, persistence, or observability. Its provider prices, capacity
claims, sizing estimates, operational recommendations, and provisioning steps
are dated and are not approved for execution.

The former recommendation selected OCI Always Free as the first option and a
paid ARM host as a fallback. OCI is now retired because the available free-tier
capacity no longer supports the full stack. No replacement provider or
production environment is currently configured.

The durable conclusions are narrower:

- Preserve the full architecture for local demonstration instead of removing
  the controls that the reference project exists to show.
- Keep all container images compatible with `linux/arm64`.
- Treat single-node persistence, backups, ingress publication, client-address
  preservation, TLS, secret delivery, observability access, and recovery as
  explicit hosting decisions rather than properties of the shared manifests.
- Revalidate capacity, cost, upstream support, storage, networking, and failure
  recovery before selecting any future provider or Kubernetes distribution.

The old Oracle deployment plan remains unchanged as labeled historical context
in [`docs/archive/oracle-cloud-deployment-plan.md`](../archive/oracle-cloud-deployment-plan.md).
The former implementation is frozen under
[`archive/oci/`](../../archive/oci/README.md). Use
[`deploy/README.md`](../../deploy/README.md) for the maintained provider-neutral
production reference and its unresolved prerequisites; use the local
[`getting-started.md`](../development/getting-started.md) flow for live
validation.
