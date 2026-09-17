#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
helper_source="${script_dir}/run-dependency-automation-upload-batch.sh"
mock_source="${script_dir}/test-fixtures/dependency-automation-upload-batch-gh"
test_root="$(mktemp -d)"
trap 'rm -rf "${test_root}"' EXIT

for required_command in git jar jq rg sha256sum unzip; do
  command -v "${required_command}" >/dev/null 2>&1 || {
    echo "Required test command is unavailable: ${required_command}" >&2
    exit 1
  }
done

repo_root="${test_root}/orchestration"
mkdir -p "${repo_root}/scripts/repo" "${test_root}/mock-state/zips"
cp "${helper_source}" "${repo_root}/scripts/repo/"
cp "${mock_source}" "${test_root}/mock-gh"
chmod +x "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh" "${test_root}/mock-gh"
printf 'tmp/\n' > "${repo_root}/.gitignore"

git -C "${repo_root}" init -q
git -C "${repo_root}" config user.name 'Phase 12 Test'
git -C "${repo_root}" config user.email 'phase12-test@example.invalid'
git -C "${repo_root}" add .gitignore scripts/repo/run-dependency-automation-upload-batch.sh
git -C "${repo_root}" commit -qm 'fixture'
orchestration_sha="$(git -C "${repo_root}" rev-parse HEAD)"

for payload in \
  govulncheck-evidence.tar.gz \
  audit-evidence.tar.gz \
  dependency-graph-evidence.tar.gz \
  workspace-image-evidence.tar.gz \
  image-security-evidence.tar.gz; do
  payload_dir="${test_root}/payload-${payload}"
  mkdir -p "${payload_dir}"
  printf 'fixture for %s\n' "${payload}" > "${payload_dir}/${payload}"
  jar --create --file "${test_root}/mock-state/zips/${payload}.zip" \
    --no-manifest -C "${payload_dir}" "${payload}"
done

MOCK_GH_STATE_DIR="${test_root}/mock-state" \
MOCK_ORCHESTRATION_SHA="${orchestration_sha}" \
GH_BIN="${test_root}/mock-gh" \
PHASE12_RUN_STAMP=success \
PHASE12_WAIT_SECONDS=0 \
PHASE12_WAIT_LIMIT=2 \
  "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh" \
    --confirm 'UPLOAD BATCH GO'

success_ledger="${repo_root}/tmp/dependency-automation/gate-c-success/ledger.json"
jq -e '
  .status == "completed" and
  (.rows | length) == 5 and
  all(.rows[]; .upload_gate_restored == true) and
  all(.rows[]; .artifact.exact_id_deletion_requested_after_download == true) and
  .final_upload_gate_restore_succeeded == true
' "${success_ledger}" >/dev/null
[[ "$(wc -l < "${test_root}/mock-state/deleted.log")" == 5 ]]
[[ "$(wc -l < "${test_root}/mock-state/variable.log")" == 10 ]]
if rg -n -- 'gh variable| variable get| variable set|--slurp' \
  "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh"; then
  echo 'The upload helper uses an unsupported GitHub CLI command or flag.' >&2
  exit 1
fi

storage_failure_state="${test_root}/storage-failure-state"
mkdir -p "${storage_failure_state}/zips"
cp "${test_root}/mock-state/zips/"*.zip "${storage_failure_state}/zips/"
if MOCK_GH_STATE_DIR="${storage_failure_state}" \
  MOCK_ORCHESTRATION_SHA="${orchestration_sha}" \
  MOCK_FAIL_PUBLIC_STORAGE=true \
  GH_BIN="${test_root}/mock-gh" \
  PHASE12_RUN_STAMP=storage-failure \
  PHASE12_WAIT_SECONDS=0 \
  PHASE12_WAIT_LIMIT=2 \
  "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh" \
    --confirm 'UPLOAD BATCH GO'; then
  echo 'Expected a public-storage API failure to stop the upload batch.' >&2
  exit 1
fi

storage_failure_ledger="${repo_root}/tmp/dependency-automation/gate-c-storage-failure/ledger.json"
jq -e '
  .status == "failed" and
  (.rows | length) == 0 and
  .failure.phase == "preflight" and
  .failure.reason == "Could not collect the complete public artifact and cache inventory." and
  .final_upload_gate_restore_succeeded == true
' "${storage_failure_ledger}" >/dev/null
if find "${storage_failure_state}" -maxdepth 1 -name 'dispatched-*' -print -quit | grep -q .; then
  echo 'A workflow was dispatched after public-storage collection failed.' >&2
  exit 1
fi

resume_state="${test_root}/resume-state"
mkdir -p "${resume_state}/zips"
cp "${test_root}/mock-state/zips/"*.zip "${resume_state}/zips/"
MOCK_GH_STATE_DIR="${resume_state}" \
MOCK_ORCHESTRATION_SHA="${orchestration_sha}" \
MOCK_RESUME_ARTIFACT=true \
GH_BIN="${test_root}/mock-gh" \
PHASE12_RUN_STAMP=resume \
PHASE12_WAIT_SECONDS=0 \
PHASE12_WAIT_LIMIT=2 \
  "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh" \
    --confirm 'UPLOAD BATCH GO' \
    --resume-first-run 91001 \
    --resume-first-artifact 291001

resume_ledger="${repo_root}/tmp/dependency-automation/gate-c-resume/ledger.json"
jq -e '
  .status == "completed" and
  .resume.first_row_run_id == 91001 and
  .resume.first_row_artifact_id == 291001 and
  (.rows | length) == 5 and
  .rows[0].resumed_from_interrupted_batch == true and
  all(.rows[1:][]; .resumed_from_interrupted_batch == false) and
  .rows[0].artifact.id == 291001 and
  .rows[0].artifact.exact_id_deletion_confirmed == true and
  .final_upload_gate_restore_succeeded == true
' "${resume_ledger}" >/dev/null
[[ ! -e "${resume_state}/dispatched-ext-authz" ]]
for resumed_repository in budget-analyzer-web service-common workspace orchestration; do
  [[ -e "${resume_state}/dispatched-${resumed_repository}" ]]
done

failure_state="${test_root}/failure-state"
mkdir -p "${failure_state}/zips"
cp "${test_root}/mock-state/zips/"*.zip "${failure_state}/zips/"
if MOCK_GH_STATE_DIR="${failure_state}" \
  MOCK_ORCHESTRATION_SHA="${orchestration_sha}" \
  MOCK_FAIL_REPOSITORY=ext-authz \
  GH_BIN="${test_root}/mock-gh" \
  PHASE12_RUN_STAMP=failure \
  PHASE12_WAIT_SECONDS=0 \
  PHASE12_WAIT_LIMIT=2 \
  "${repo_root}/scripts/repo/run-dependency-automation-upload-batch.sh" \
    --confirm 'UPLOAD BATCH GO'; then
    echo 'Expected a failed workflow run to stop the upload batch.' >&2
    exit 1
  fi

failure_ledger="${repo_root}/tmp/dependency-automation/gate-c-failure/ledger.json"
jq -e '
  .status == "failed" and
  (.rows | length) == 0 and
  .final_upload_gate_restore_succeeded == true
' "${failure_ledger}" >/dev/null
[[ "$(sed -n '1p' "${failure_state}/variable-ext-authz-DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED")" == false ]]

echo 'dependency automation upload batch tests passed'
