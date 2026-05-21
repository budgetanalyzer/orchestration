# OCI Candidate Deployment

Use this runbook to deploy a tag-required candidate image to the single OCI
production slot for a controlled staging window before a SemVer release tag
exists.

The canonical terminology lives in [docs/ci-cd.md](../ci-cd.md). Record
evidence with
[oci-release-deployment-checklist.md](oci-release-deployment-checklist.md).

## Candidate Tag Policy

- Candidate tags are Git tags, not GitHub Releases.
- Candidate tags must start with `candidate-` and must not start with `v`.
- Use `candidate-<artifact>-YYYYMMDD-<short-sha>`, for example
  `candidate-transaction-service-20260521-abc123`.
- The runtime image workflow publishes the same Docker-safe tag as the image
  tag, for example
  `ghcr.io/budgetanalyzer/transaction-service:candidate-transaction-service-20260521-abc123@sha256:...`.
- Keep the candidate tag until the deployment manifest, workflow run URL, and
  run-log evidence are no longer needed.

## Preconditions

- The candidate source is on the selected artifact repository's `main` branch.
- The selected repository is clean and matches `origin/main`.
- The relevant `publish-release.yml` workflow accepts both `v*` and
  `candidate-*` tags.
- The current accepted production deployment manifest is available for
  rollback.
- The staging window is announced because the single OCI instance will briefly
  run candidate state on the public demo endpoint.

## Procedure

1. Prepare the candidate tag:
   ```bash
   ./scripts/repo/prepare-candidate-deployment.sh \
     --service transaction-service
   ```

   After reviewing the printed source commit, create and push the tag:
   ```bash
   ./scripts/repo/prepare-candidate-deployment.sh \
     --service transaction-service \
     --create-tag \
     --push
   ```

2. Wait for the artifact workflow to complete. It must print a digest-pinned
   image reference and must not publish `latest` or create a GitHub Release.

3. Generate a candidate deployment manifest from the current production
   inventory, replacing only the selected artifact:
   ```bash
   ./scripts/repo/generate-deployment-manifest.sh \
     --deployment-id oci-YYYYMMDD.N \
     --status candidate \
     --service transaction-service \
     --artifact-image transaction-service=ghcr.io/budgetanalyzer/transaction-service:candidate-transaction-service-YYYYMMDD-abcdef0@sha256:<digest> \
     --source-ref transaction-service=refs/tags/candidate-transaction-service-YYYYMMDD-abcdef0 \
     --source-commit transaction-service=<40-char-sha> \
     --output tmp/deployments/oci-YYYYMMDD.N.yaml
   ```

4. Update and review the checked-in production baseline:
   ```bash
   ./deploy/scripts/23-update-production-release-images.sh \
     --deployment-manifest tmp/deployments/oci-YYYYMMDD.N.yaml
   ```

5. Run the static gate:
   ```bash
   ./deploy/scripts/24-verify-oci-upgrade-lockstep.sh
   ```

6. Open the OCI staging window and capture preflight state in the checklist.
   On the OCI host, deploy the selected workload:
   ```bash
   ./deploy/scripts/25-deploy-oci-release.sh \
     --mode app-only \
     --services transaction-service \
     --deployment-manifest kubernetes/production/apps/deployment-manifest.yaml
   ```

7. Run the focused behavior checks for the candidate plus the production
   verifiers in the checklist. Capture the workflow URL, digest-pinned image,
   snapshot directory, public `/api-docs/release-metadata.json` output, and
   live pod metadata proof.

8. Accept or reject the candidate:

   - **Accept without rebuilding** when the candidate digest is the production
     artifact identity you want to keep. Record the tested manifest as the
     accepted production baseline.
   - **Retag or rebuild as SemVer** when a named release artifact is required.
     Reuse the same source commit, compare the resulting digest, then deploy
     the SemVer manifest.
   - **Reject** by rolling back the selected artifact with
     [oci-single-service-rollback.md](oci-single-service-rollback.md) and the
     previous accepted manifest.

9. Capture post-window state and close the staging window in the checklist.

## Notes

Do not deploy arbitrary branch names in this phase. Commit-SHA candidate
deployment waits for the independent black-box gates described in the release
versioning plan.
