# OCI Candidate Deployment

**Status:** Superseded by full-stack OCI promotion.

The single OCI production slot no longer has a tag-required, service-scoped
candidate deployment path, and candidate status is no longer an operator-facing
deployment mode. Use the convention-based promotion command for the current
intended workspace stack:

```bash
./deploy/scripts/promote-current-stack-to-oci.sh --plan-only
./deploy/scripts/promote-current-stack-to-oci.sh
```

The command records the accepted intended OCI state in the complete deployment
snapshot, builds only changed artifacts, and applies the full managed app set.
Record evidence with
[oci-release-deployment-checklist.md](oci-release-deployment-checklist.md).
