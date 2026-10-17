# OCI Release Deployment Checklist

**Status:** Retired

OCI is no longer an active deployment target, no production environment is
currently configured, and this checklist must not be used as an operator
procedure.

The historical checklist is not copied into the lean archive. Its complete
pre-retirement version is in the Git tree at public tag `pre-oci-archive`,
verified at commit `60510f4ce9331968988516947f394152f6aa0da4`. Inspect it
read-only from a clone containing the tag:

```bash
git show pre-oci-archive:docs/runbooks/oci-release-deployment-checklist.md
```

If the tag is unavailable or does not resolve to the recorded commit, use the
commit hash in place of the tag. Do not execute commands from that checklist.
Read [archive/oci/README.md](../../archive/oci/README.md) first for the lean
inventory, complete-tree provenance, exclusions, and restoration caveats.
Restoring OCI would require a separate, explicitly authorized and newly
reviewed project.
