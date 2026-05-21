# OCI Single-Service Release

Use this runbook when one runtime artifact changes and unrelated artifacts stay
on their current digest-pinned production images.

The canonical release/deployment terminology lives in
[docs/ci-cd.md](../ci-cd.md). Record evidence with
[oci-release-deployment-checklist.md](oci-release-deployment-checklist.md).

## Preconditions

- The service change is merged to that service repository's `main`.
- The service repository has a reviewed SemVer tag such as `v0.0.15`.
- The service release workflow published a `linux/arm64` GHCR image and printed
  a digest-pinned ref.
- The selected service still consumes the intended `service-common` version.
  Do not bump `service-common` unless the shared library changed.
- The operator has the previous accepted deployment manifest available for
  rollback evidence.

## Procedure

1. Prepare or verify the service release tag:
   ```bash
   ./scripts/repo/prepare-service-release.sh --service transaction-service --version 0.0.15
   ```

2. Generate a scoped schema v2 deployment manifest from the current production
   inventory, replacing only the selected artifact metadata:
   ```bash
   ./scripts/repo/generate-deployment-manifest.sh \
     --deployment-id oci-YYYYMMDD.N \
     --status candidate \
     --service transaction-service \
     --artifact-image transaction-service=ghcr.io/budgetanalyzer/transaction-service:0.0.15@sha256:<digest> \
     --source-ref transaction-service=refs/tags/v0.0.15 \
     --source-commit transaction-service=<40-char-sha> \
     --output tmp/deployments/oci-YYYYMMDD.N.yaml
   ```

3. Update the checked-in production baseline from the reviewed manifest:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --deployment-manifest tmp/deployments/oci-YYYYMMDD.N.yaml
   ```

4. Review the diff. Unrelated artifact image refs should be unchanged.

5. Run the static gate:
   ```bash
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ```

6. On the OCI host, open the staging window and run the selected app-only
   rollout:
   ```bash
   ./deploy/scripts/25-deploy-oci-release.sh \
     --mode app-only \
     --services transaction-service \
     --deployment-manifest kubernetes/production/apps/deployment-manifest.yaml
   ```

   For `budget-analyzer-web`, pass `--services budget-analyzer-web`; the script
   maps it to the production `nginx-gateway` workload.

7. Run focused black-box checks for the changed behavior plus the production
   verifiers listed in the release deployment checklist.

8. Record the manifest as accepted production state in the checklist. On the
   single OCI instance, promotion may be metadata-only when the tested bits are
   already live.

## Rollback

Use [oci-single-service-rollback.md](oci-single-service-rollback.md) with the
previous accepted deployment manifest.
