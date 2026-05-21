# OCI Single-Service Rollback

**Status:** Superseded by full-stack OCI promotion.

Production no longer rolls back by applying one selected workload. Restore or
generate a complete deployment snapshot that contains the intended previous
artifact digests and metadata, then promote the full managed stack:

```bash
./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
./deploy/scripts/promote-current-stack-to-oci.sh
```

Use [oci-release-deployment-checklist.md](oci-release-deployment-checklist.md)
for evidence. Review data migration, queue compatibility, and platform changes
before treating any rollback as app-only risk.
