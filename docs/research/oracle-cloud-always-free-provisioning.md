# Oracle Cloud Always Free Provisioning Research

**Date:** 2026-04-06
**Status:** Retired historical pointer; not provisioning guidance

OCI is retired because the available OCI Free Tier capacity no longer supports
the full Budget Analyzer stack. No production environment is currently
configured. Do not provision an OCI account or instance, run k3s installation
steps, open cloud firewall ports, or use old capacity-workaround advice for this
project.

The former checked-in deployment implementation is preserved unchanged under
[`archive/oci/`](../../archive/oci/README.md), including its provenance,
inventory, external prerequisites, and restoration caveats. The older Oracle
deployment plan remains unchanged as labeled historical context in
[`docs/archive/oracle-cloud-deployment-plan.md`](../archive/oracle-cloud-deployment-plan.md).

The dated provider and sizing comparison remains in
[`single-instance-demo-hosting.md`](single-instance-demo-hosting.md), which is
also historical and does not select a replacement provider. Maintained
provider-neutral Kubernetes renders and the prerequisites intentionally left
unresolved are documented in [`deploy/README.md`](../../deploy/README.md).

Restoring OCI or selecting any replacement host requires a separate, explicitly
authorized project. Neither the frozen snapshot nor these research records are
evidence that an old deployment procedure remains safe, affordable, or
functional.
