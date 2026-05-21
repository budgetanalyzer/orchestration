# OCI Single-Service Release

**Status:** Superseded by full-stack OCI promotion.

Production no longer has a service-scoped apply path. When one runtime
artifact changes, run the normal promotion flow:

```bash
./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
./deploy/scripts/promote-current-stack-to-oci.sh
```

The promotion command still rebuilds only changed artifacts and carries
unchanged digests forward, but the deployment snapshot and production apply are
complete. Record evidence with
[oci-release-deployment-checklist.md](oci-release-deployment-checklist.md).
