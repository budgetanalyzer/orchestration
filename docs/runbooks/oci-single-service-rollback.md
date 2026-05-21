# OCI Single-Service Rollback

Use this runbook to restore one artifact to the digest and metadata recorded in
a previous schema v2 deployment manifest while preserving unrelated artifacts
from the current production baseline.

Record evidence with
[oci-release-deployment-checklist.md](oci-release-deployment-checklist.md).

## Preconditions

- The rollback target manifest is the intended previous accepted production
  state for the selected artifact.
- The rollback is app-only. If the failed deployment changed platform,
  infrastructure, secrets, data shape, or public TLS behavior, review the
  broader deployment checklist before using this path.
- The operator understands any data migration or queue-message compatibility
  risk for the selected service.

## Procedure

1. Generate a rollback manifest for one artifact:
   ```bash
   ./deploy/scripts/26-rollback-oci-artifact.sh \
     --service transaction-service \
     --to-manifest tmp/deployments/previous-accepted.yaml \
     --deployment-id rollback-YYYYMMDD.N-transaction-service \
     --output tmp/deployments/rollback-YYYYMMDD.N-transaction-service.yaml
   ```

2. Review the generated manifest. The selected artifact should match the
   previous manifest; unrelated artifacts should match the current production
   image inventory.

3. Update the checked-in production baseline from the rollback manifest:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --deployment-manifest tmp/deployments/rollback-YYYYMMDD.N-transaction-service.yaml
   ```

   The rollback helper can run this step directly with
   `--update-production-baseline`, but the default separate review step is
   preferred for production changes.

4. On the OCI host, deploy only the selected workload:
   ```bash
   ./deploy/scripts/25-deploy-oci-release.sh \
     --mode app-only \
     --services transaction-service \
     --deployment-manifest kubernetes/production/apps/deployment-manifest.yaml
   ```

5. Verify the selected workload metadata:
   ```bash
   ./scripts/ops/show-pod-version-labels.sh \
     --deployment-manifest kubernetes/production/apps/deployment-manifest.yaml \
     --services transaction-service \
     --tracked-only \
     --strict
   ```

6. Run focused smoke checks for the rolled-back service and record public route
   or `/api-docs/release-metadata.json` evidence when public TLS is active.

## Notes

- `budget-analyzer-web` rollback maps to the production `nginx-gateway`
  workload because NGINX serves the released frontend bundle and docs assets.
- Do not use this helper to hide a service-owned contract failure with
  orchestration changes. Fix the owning service or shared library first.
