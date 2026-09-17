#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
GH_BIN="${GH_BIN:-gh}"
ORG="budgetanalyzer"
TRIAL_BRANCH="dependency-automation-trial"
UPLOAD_VARIABLE="DEPENDENCY_AUTOMATION_TRIAL_UPLOADS_ENABLED"
SCHEDULE_VARIABLE="DEPENDENCY_AUTOMATION_TRIAL_SCHEDULES_ENABLED"
CACHE_VARIABLE="DEPENDENCY_AUTOMATION_TRIAL_CACHES_ENABLED"
RETAINED_CAP_BYTES=26214400
PUBLIC_ALLOWANCE_BYTES=524288000
FAILURE_DIAGNOSTIC_RESERVE_BYTES=1330666
WAIT_SECONDS="${PHASE12_WAIT_SECONDS:-10}"
WAIT_LIMIT="${PHASE12_WAIT_LIMIT:-1440}"

usage() {
  cat <<'USAGE'
Usage: run-dependency-automation-upload-batch.sh --confirm 'UPLOAD BATCH GO' \
  [--resume-first-run RUN_ID --resume-first-artifact ARTIFACT_ID]

Runs the reviewed Phase 12 Gate C matrix from a clean checkout whose HEAD is
already published as budgetanalyzer/orchestration:dependency-automation-trial.
The helper uses the operator's existing gh session, serializes all rows, restores
the upload variable after each dispatch, downloads and checksums each exact
artifact, deletes only that captured artifact ID, and writes a sanitized ledger
under tmp/dependency-automation/. The resume options recover an interrupted
first row only; the helper verifies the exact run and artifact before use and
does not dispatch a duplicate first-row workflow.
USAGE
}

confirmation=""
resume_first_run=""
resume_first_artifact=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --confirm)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      confirmation="$2"
      shift 2
      ;;
    --resume-first-run)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      resume_first_run="$2"
      shift 2
      ;;
    --resume-first-artifact)
      [[ "$#" -ge 2 ]] || { usage >&2; exit 2; }
      resume_first_artifact="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${confirmation}" != 'UPLOAD BATCH GO' ]]; then
  echo "Refusing to run without --confirm 'UPLOAD BATCH GO'." >&2
  exit 2
fi

if [[ -n "${resume_first_run}" || -n "${resume_first_artifact}" ]]; then
  if [[ ! "${resume_first_run}" =~ ^[1-9][0-9]*$ || ! "${resume_first_artifact}" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Both resume IDs must be supplied as positive integers.' >&2
    exit 2
  fi
fi

if [[ ! "${WAIT_SECONDS}" =~ ^[0-9]+$ || ! "${WAIT_LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
  echo 'PHASE12_WAIT_SECONDS and PHASE12_WAIT_LIMIT must be non-negative integers.' >&2
  exit 2
fi

for required_command in "${GH_BIN}" git jq sha256sum unzip; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${required_command}" >&2
    exit 1
  fi
done

cd "${REPO_ROOT}"
if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo 'The orchestration checkout must be clean before Gate C execution.' >&2
  exit 1
fi

orchestration_sha="$(git rev-parse --verify HEAD)"
if [[ ! "${orchestration_sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo 'Could not resolve an exact orchestration HEAD SHA.' >&2
  exit 1
fi

run_stamp="${PHASE12_RUN_STAMP:-$(date -u '+%Y%m%dT%H%M%SZ')}"
if [[ ! "${run_stamp}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo 'PHASE12_RUN_STAMP contains unsupported path characters.' >&2
  exit 2
fi
output_dir="${REPO_ROOT}/tmp/dependency-automation/gate-c-${run_stamp}"
if [[ -e "${output_dir}" ]]; then
  echo "Refusing to overwrite an existing Gate C output directory: ${output_dir}" >&2
  exit 1
fi
mkdir -p "${output_dir}/artifacts"
ledger_path="${output_dir}/ledger.json"
ledger_tmp="${output_dir}/ledger.json.tmp"

active_repository=""
failure_phase="preflight"
failure_reason=""
batch_complete=false

set_failure() {
  failure_reason="$1"
  echo "${failure_reason}" >&2
  return 1
}

variable_value() {
  local repository="$1"
  local variable_name="$2"
  "${GH_BIN}" api \
    "repos/${ORG}/${repository}/actions/variables/${variable_name}" \
    --jq '.value'
}

set_upload_value() {
  local repository="$1"
  local value="$2"
  "${GH_BIN}" api --method PATCH \
    "repos/${ORG}/${repository}/actions/variables/${UPLOAD_VARIABLE}" \
    -f "name=${UPLOAD_VARIABLE}" \
    -f "value=${value}" >/dev/null
}

restore_active_upload_gate() {
  local repository="${active_repository}"
  [[ -n "${repository}" ]] || return 0

  if ! set_upload_value "${repository}" false; then
    return 1
  fi
  if [[ "$(variable_value "${repository}" "${UPLOAD_VARIABLE}")" != false ]]; then
    return 1
  fi
  active_repository=""
}

finish() {
  local exit_code="$?"
  local restore_ok=true
  local final_status=failed
  trap - EXIT

  if ! restore_active_upload_gate; then
    restore_ok=false
    exit_code=1
    failure_reason="${failure_reason:+${failure_reason}; }failed to restore ${UPLOAD_VARIABLE} to false"
  fi
  if [[ "${batch_complete}" == true && "${exit_code}" -eq 0 ]]; then
    final_status=completed
  fi

  if [[ -f "${ledger_path}" ]]; then
    jq \
      --arg status "${final_status}" \
      --arg finished_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
      --arg failure_phase "${failure_phase}" \
      --arg failure_reason "${failure_reason}" \
      --argjson restore_ok "${restore_ok}" \
      '.status = $status |
       .finished_at = $finished_at |
       .failure = (if $status == "completed" then null else {
         phase: $failure_phase,
         reason: (if $failure_reason == "" then "command failed; inspect sanitized row state" else $failure_reason end)
       } end) |
       .final_upload_gate_restore_succeeded = $restore_ok' \
      "${ledger_path}" > "${ledger_tmp}"
    mv "${ledger_tmp}" "${ledger_path}"
  fi

  printf 'Sanitized Gate C ledger: %s\n' "${ledger_path}"
  exit "${exit_code}"
}
trap finish EXIT

matrix_json="$(jq -n \
  --arg orchestration_sha "${orchestration_sha}" \
  '[
    {
      order: 1,
      repository: "ext-authz",
      workflow: "go-vulnerability-check.yml",
      source_sha: "75ed2bda4de7460332a8dea656def0459064753f",
      artifact_prefix: "trial-govulncheck-evidence-",
      payload_file: "govulncheck-evidence.tar.gz",
      required_evidence: "scanner and database metadata plus the complete govulncheck result"
    },
    {
      order: 2,
      repository: "budget-analyzer-web",
      workflow: "dependency-audit.yml",
      source_sha: "2cbef3f17f546fe167628b221a1cb9dec810c2bd",
      artifact_prefix: "trial-npm-audit-evidence-",
      payload_file: "audit-evidence.tar.gz",
      required_evidence: "complete full-tree and production npm audit reports"
    },
    {
      order: 3,
      repository: "service-common",
      workflow: "dependency-submission.yml",
      source_sha: "e9b91a63eccbc3e7e98528d80cbe89677d0d1f94",
      artifact_prefix: "trial-dependency-graph-evidence-",
      payload_file: "dependency-graph-evidence.tar.gz",
      required_evidence: "strict resolution output and the complete generated dependency graph"
    },
    {
      order: 4,
      repository: "workspace",
      workflow: "workspace-image-security-evidence.yml",
      source_sha: "6a6bf33fb019825b7709693a1b103c8a1dd7d726",
      artifact_prefix: "trial-workspace-image-evidence-",
      payload_file: "workspace-image-evidence.tar.gz",
      required_evidence: "complete workspace image inventory, scanner metadata, and report"
    },
    {
      order: 5,
      repository: "orchestration",
      workflow: "exact-image-security-evidence.yml",
      source_sha: $orchestration_sha,
      artifact_prefix: "trial-exact-image-security-evidence-",
      payload_file: "image-security-evidence.tar.gz",
      required_evidence: "all rendered targets, exact-platform inventories, scanner metadata, and vulnerability reports"
    }
  ] | map(. + {delete_after_download: true})')"

jq -n \
  --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --arg orchestration_sha "${orchestration_sha}" \
  --argjson retained_cap_bytes "${RETAINED_CAP_BYTES}" \
  --argjson public_allowance_bytes "${PUBLIC_ALLOWANCE_BYTES}" \
  --argjson failure_diagnostic_reserve_bytes "${FAILURE_DIAGNOSTIC_RESERVE_BYTES}" \
  --argjson matrix "${matrix_json}" \
  --arg resume_run_id "${resume_first_run}" \
  --arg resume_artifact_id "${resume_first_artifact}" \
  '{
    schema_version: 1,
    gate: "UPLOAD BATCH GO",
    status: "running",
    generated_at: $generated_at,
    finished_at: null,
    orchestration_execution_sha: $orchestration_sha,
    limits: {
      retained_artifact_cap_bytes: $retained_cap_bytes,
      public_allowance_bytes: $public_allowance_bytes,
      one_retry_artifact_count: 2,
      failure_diagnostic_reserve_bytes: $failure_diagnostic_reserve_bytes
    },
    matrix: $matrix,
    preflight: null,
    resume: (if $resume_run_id == "" then null else {
      first_row_run_id: ($resume_run_id | tonumber),
      first_row_artifact_id: ($resume_artifact_id | tonumber)
    } end),
    rows: [],
    failure: null,
    final_upload_gate_restore_succeeded: false
  }' > "${ledger_path}"

if ! "${GH_BIN}" auth status --hostname github.com >/dev/null 2>&1; then
  set_failure 'The existing gh session is not authenticated for github.com.'
  exit 1
fi

preflight_rows='[]'
while IFS= read -r row; do
  repository="$(jq -r '.repository' <<< "${row}")"
  expected_sha="$(jq -r '.source_sha' <<< "${row}")"
  remote_sha="$("${GH_BIN}" api "repos/${ORG}/${repository}/git/ref/heads/${TRIAL_BRANCH}" --jq '.object.sha')"
  default_branch="$("${GH_BIN}" api "repos/${ORG}/${repository}" --jq '.default_branch')"
  schedule_value="$(variable_value "${repository}" "${SCHEDULE_VARIABLE}")"
  cache_value="$(variable_value "${repository}" "${CACHE_VARIABLE}")"
  upload_value="$(variable_value "${repository}" "${UPLOAD_VARIABLE}")"

  if [[ "${remote_sha}" != "${expected_sha}" ]]; then
    set_failure "Trial SHA mismatch for ${repository}: expected ${expected_sha}, observed ${remote_sha}."
    exit 1
  fi
  if [[ "${default_branch}" != "${TRIAL_BRANCH}" ]]; then
    set_failure "Default branch mismatch for ${repository}: observed ${default_branch}."
    exit 1
  fi
  if [[ "${schedule_value}" != false || "${cache_value}" != false || "${upload_value}" != false ]]; then
    set_failure "Expansion gates are not all false for ${repository}."
    exit 1
  fi

  preflight_rows="$(jq \
    --arg repository "${repository}" \
    --arg source_sha "${remote_sha}" \
    --arg default_branch "${default_branch}" \
    '. + [{
      repository: $repository,
      source_sha: $source_sha,
      default_branch: $default_branch,
      schedules_enabled: false,
      caches_enabled: false,
      uploads_enabled: false
    }]' <<< "${preflight_rows}")"
done < <(jq -c '.[]' <<< "${matrix_json}")

collect_public_storage() {
  local repositories_json
  local artifacts_json
  local caches_json
  local repository
  local combined_artifacts='[]'
  local combined_caches='[]'

  repositories_json="$(
    "${GH_BIN}" api --paginate "orgs/${ORG}/repos?type=public&per_page=100" |
      jq -s '.'
  )" || return 1
  while IFS= read -r repository; do
    artifacts_json="$(
      "${GH_BIN}" api --paginate \
        "repos/${ORG}/${repository}/actions/artifacts?per_page=100" |
        jq -s '.'
    )" || return 1
    caches_json="$(
      "${GH_BIN}" api --paginate \
        "repos/${ORG}/${repository}/actions/caches?per_page=100" |
        jq -s '.'
    )" || return 1
    combined_artifacts="$(jq \
      --arg repository "${repository}" \
      --argjson pages "${artifacts_json}" \
      '. + [$pages[].artifacts[]? | select(.expired == false) | {
        repository: $repository,
        id,
        name,
        size_in_bytes,
        expires_at,
        workflow_run: {id: .workflow_run.id, head_branch: .workflow_run.head_branch, head_sha: .workflow_run.head_sha}
      }]' <<< "${combined_artifacts}")" || return 1
    combined_caches="$(jq \
      --arg repository "${repository}" \
      --argjson pages "${caches_json}" \
      '. + [$pages[].actions_caches[]? | {
        repository: $repository,
        id,
        key,
        ref,
        size_in_bytes
      }]' <<< "${combined_caches}")" || return 1
  done < <(jq -r '[.[][]] | map(select(.visibility == "public")) | .[].name' <<< "${repositories_json}" | sort -u)

  jq -n \
    --argjson artifacts "${combined_artifacts}" \
    --argjson caches "${combined_caches}" \
    '{
      artifact_count: ($artifacts | length),
      artifact_bytes: ($artifacts | map(.size_in_bytes) | add // 0),
      cache_count: ($caches | length),
      cache_bytes: ($caches | map(.size_in_bytes) | add // 0),
      app_jar_recurrence: [$artifacts[] | select(.name == "app-jar")],
      controlled_upload_artifacts: [
        $artifacts[] |
        select(.name | test("^trial-(govulncheck|npm-audit|dependency-graph|workspace-image|exact-image-security)-evidence-[0-9]+$"))
      ],
      artifacts: $artifacts,
      caches: $caches
    }'
}

if ! storage_json="$(collect_public_storage)"; then
  set_failure 'Could not collect the complete public artifact and cache inventory.'
  exit 1
fi
current_public_bytes="$(jq -r '.artifact_bytes' <<< "${storage_json}")"
current_cache_count="$(jq -r '.cache_count' <<< "${storage_json}")"
app_jar_count="$(jq -r '.app_jar_recurrence | length' <<< "${storage_json}")"
baseline_artifact_ids="$(jq '[.artifacts[].id] | sort' <<< "${storage_json}")"
rolling_peak_bytes=$((current_public_bytes + (2 * RETAINED_CAP_BYTES) + FAILURE_DIAGNOSTIC_RESERVE_BYTES))
remaining_bytes=$((PUBLIC_ALLOWANCE_BYTES - rolling_peak_bytes))

if ((current_cache_count != 0)); then
  set_failure "Public cache inventory is not empty (${current_cache_count} entries)."
  exit 1
fi
if ((app_jar_count != 0)); then
  set_failure "Public app-jar recurrence detected (${app_jar_count} artifacts)."
  exit 1
fi
controlled_upload_count="$(jq -r '.controlled_upload_artifacts | length' <<< "${storage_json}")"
if [[ -n "${resume_first_run}" ]]; then
  if [[ "${controlled_upload_count}" != 1 ]] || ! jq -e \
    --argjson run_id "${resume_first_run}" \
    --argjson artifact_id "${resume_first_artifact}" \
    '[.controlled_upload_artifacts[] | select(
      .repository == "ext-authz" and
      .id == $artifact_id and
      .name == ("trial-govulncheck-evidence-" + ($run_id | tostring)) and
      .workflow_run.id == $run_id and
      .workflow_run.head_sha == "75ed2bda4de7460332a8dea656def0459064753f"
    )] | length == 1' >/dev/null <<< "${storage_json}"; then
    set_failure 'The retained controlled-upload artifact does not exactly match the requested first-row resume IDs.'
    exit 1
  fi
elif ((controlled_upload_count != 0)); then
  set_failure "Found ${controlled_upload_count} retained controlled-upload artifact(s); use the reviewed exact-ID resume path."
  exit 1
fi
if ((remaining_bytes < 0)); then
  set_failure "The conservative rolling peak exceeds the public allowance by $((-remaining_bytes)) bytes."
  exit 1
fi

sanitized_storage="$(jq 'del(.artifacts, .caches)' <<< "${storage_json}")"
jq \
  --argjson repositories "${preflight_rows}" \
  --argjson storage "${sanitized_storage}" \
  --argjson rolling_peak_bytes "${rolling_peak_bytes}" \
  --argjson remaining_bytes "${remaining_bytes}" \
  '.preflight = {
    repositories: $repositories,
    public_storage: $storage,
    conservative_rolling_peak_bytes: $rolling_peak_bytes,
    remaining_public_allowance_bytes: $remaining_bytes,
    private_artifact_bytes: "unknown",
    private_package_bytes: "unknown"
  }' "${ledger_path}" > "${ledger_tmp}"
mv "${ledger_tmp}" "${ledger_path}"

failure_phase="upload_batch"
while IFS= read -r row; do
  order="$(jq -r '.order' <<< "${row}")"
  repository="$(jq -r '.repository' <<< "${row}")"
  workflow="$(jq -r '.workflow' <<< "${row}")"
  expected_sha="$(jq -r '.source_sha' <<< "${row}")"
  artifact_prefix="$(jq -r '.artifact_prefix' <<< "${row}")"
  payload_file="$(jq -r '.payload_file' <<< "${row}")"
  delete_after_download="$(jq -r '.delete_after_download' <<< "${row}")"
  expected_artifact=""
  full_repository="${ORG}/${repository}"
  resumed_row=false

  if [[ "$(variable_value "${repository}" "${SCHEDULE_VARIABLE}")" != false \
    || "$(variable_value "${repository}" "${CACHE_VARIABLE}")" != false \
    || "$(variable_value "${repository}" "${UPLOAD_VARIABLE}")" != false ]]; then
    set_failure "Expansion gate drift detected immediately before ${repository}."
    exit 1
  fi
  if [[ "$("${GH_BIN}" api "repos/${full_repository}/git/ref/heads/${TRIAL_BRANCH}" --jq '.object.sha')" != "${expected_sha}" ]]; then
    set_failure "Trial SHA drift detected immediately before ${repository}."
    exit 1
  fi

  run_id=""
  run_json=""
  if [[ "${order}" == 1 && -n "${resume_first_run}" ]]; then
    resumed_row=true
    run_id="${resume_first_run}"
    if ! run_json="$("${GH_BIN}" api "repos/${full_repository}/actions/runs/${run_id}")"; then
      set_failure "Could not read resumed ${repository} run ${run_id}."
      exit 1
    fi
  else
    prior_run_ids="$("${GH_BIN}" api \
      "repos/${full_repository}/actions/workflows/${workflow}/runs?branch=${TRIAL_BRANCH}&event=workflow_dispatch&per_page=100")"
    prior_run_ids="$(jq '[.workflow_runs[].id]' <<< "${prior_run_ids}")"

    active_repository="${repository}"
    set_upload_value "${repository}" true
    if [[ "$(variable_value "${repository}" "${UPLOAD_VARIABLE}")" != true ]]; then
      set_failure "Upload gate did not become true for ${repository}."
      exit 1
    fi

    "${GH_BIN}" workflow run "${workflow}" --repo "${full_repository}" --ref "${TRIAL_BRANCH}" >/dev/null

    for ((attempt = 1; attempt <= WAIT_LIMIT; attempt++)); do
      runs_json="$("${GH_BIN}" api \
        "repos/${full_repository}/actions/workflows/${workflow}/runs?branch=${TRIAL_BRANCH}&event=workflow_dispatch&per_page=100")"
      run_id="$(jq -r \
        --arg sha "${expected_sha}" \
        --argjson prior "${prior_run_ids}" \
        '[.workflow_runs[] | select(.head_sha == $sha and (.id as $id | $prior | index($id) | not))] |
         sort_by(.created_at) | last | .id // empty' <<< "${runs_json}")"
      [[ -n "${run_id}" ]] && break
      sleep "${WAIT_SECONDS}"
    done
    if [[ -z "${run_id}" ]]; then
      set_failure "No new source-exact workflow_dispatch run appeared for ${repository}."
      exit 1
    fi

    for ((attempt = 1; attempt <= WAIT_LIMIT; attempt++)); do
      run_json="$("${GH_BIN}" api "repos/${full_repository}/actions/runs/${run_id}")"
      [[ "$(jq -r '.status' <<< "${run_json}")" == completed ]] && break
      sleep "${WAIT_SECONDS}"
    done
    if [[ "$(jq -r '.status' <<< "${run_json}")" != completed ]]; then
      set_failure "Timed out waiting for ${repository} run ${run_id}."
      exit 1
    fi

    if ! restore_active_upload_gate; then
      active_repository="${repository}"
      set_failure "Failed to restore the upload gate after ${repository} run ${run_id}."
      exit 1
    fi
  fi

  if [[ "$(jq -r '.conclusion' <<< "${run_json}")" != success \
    || "$(jq -r '.head_branch' <<< "${run_json}")" != "${TRIAL_BRANCH}" \
    || "$(jq -r '.head_sha' <<< "${run_json}")" != "${expected_sha}" \
    || "$(jq -r '.event' <<< "${run_json}")" != workflow_dispatch ]]; then
    set_failure "Run metadata or conclusion failed acceptance for ${repository} run ${run_id}."
    exit 1
  fi

  if ! jobs_json="$(
    "${GH_BIN}" api --paginate \
      "repos/${full_repository}/actions/runs/${run_id}/jobs?per_page=100" |
      jq -s '.'
  )"; then
    set_failure "Could not collect all jobs for ${repository} run ${run_id}."
    exit 1
  fi
  if ! jq -e '[.[].jobs[]] | length > 0 and all(.[]; .status == "completed" and .conclusion == "success")' \
    >/dev/null <<< "${jobs_json}"; then
    set_failure "One or more jobs failed acceptance for ${repository} run ${run_id}."
    exit 1
  fi

  expected_artifact="${artifact_prefix}${run_id}"
  artifacts_json="$("${GH_BIN}" api \
    "repos/${full_repository}/actions/runs/${run_id}/artifacts?per_page=100")"
  artifact_count="$(jq '.artifacts | length' <<< "${artifacts_json}")"
  if [[ "${artifact_count}" != 1 \
    || "$(jq -r '.artifacts[0].name' <<< "${artifacts_json}")" != "${expected_artifact}" ]]; then
    set_failure "Expected exactly artifact ${expected_artifact} for ${repository} run ${run_id}."
    exit 1
  fi

  artifact_id="$(jq -r '.artifacts[0].id' <<< "${artifacts_json}")"
  artifact_bytes="$(jq -r '.artifacts[0].size_in_bytes' <<< "${artifacts_json}")"
  expires_at="$(jq -r '.artifacts[0].expires_at' <<< "${artifacts_json}")"
  artifact_sha="$(jq -r '.artifacts[0].workflow_run.head_sha' <<< "${artifacts_json}")"
  if [[ ! "${artifact_id}" =~ ^[0-9]+$ || ! "${artifact_bytes}" =~ ^[0-9]+$ \
    || "${artifact_sha}" != "${expected_sha}" || "${artifact_bytes}" -gt "${RETAINED_CAP_BYTES}" ]]; then
    set_failure "Artifact metadata or retained-size acceptance failed for ${repository} run ${run_id}."
    exit 1
  fi
  if [[ "${resumed_row}" == true && "${artifact_id}" != "${resume_first_artifact}" ]]; then
    set_failure "Resumed artifact ID mismatch for ${repository} run ${run_id}."
    exit 1
  fi

  row_dir="${output_dir}/artifacts/$(printf '%02d' "${order}")-${repository}"
  mkdir -p "${row_dir}/extracted"
  zip_path="${row_dir}/${expected_artifact}.zip"
  "${GH_BIN}" api "repos/${full_repository}/actions/artifacts/${artifact_id}/zip" > "${zip_path}"
  zip_sha256="$(sha256sum "${zip_path}" | cut -d' ' -f1)"

  mapfile -t archive_entries < <(unzip -Z1 "${zip_path}")
  if [[ "${#archive_entries[@]}" -ne 1 \
    || "${archive_entries[0]}" == /* \
    || "/${archive_entries[0]}/" == *'/../'* \
    || "$(basename -- "${archive_entries[0]}")" != "${payload_file}" ]]; then
    set_failure "Downloaded artifact ${artifact_id} has an unexpected archive shape."
    exit 1
  fi
  unzip -q "${zip_path}" -d "${row_dir}/extracted"
  payload_path="${row_dir}/extracted/${archive_entries[0]}"
  payload_sha256="$(sha256sum "${payload_path}" | cut -d' ' -f1)"
  payload_bytes="$(stat --format='%s' "${payload_path}")"
  if ((payload_bytes > 25165824)); then
    set_failure "Downloaded payload for artifact ${artifact_id} exceeds the 24 MiB payload cap."
    exit 1
  fi

  if [[ "${delete_after_download}" == true ]]; then
    "${GH_BIN}" api --method DELETE \
      "repos/${full_repository}/actions/artifacts/${artifact_id}" >/dev/null
    deletion_confirmed=false
    for ((attempt = 1; attempt <= WAIT_LIMIT; attempt++)); do
      if post_delete_artifacts_json="$("${GH_BIN}" api \
        "repos/${full_repository}/actions/runs/${run_id}/artifacts?per_page=100")"; then
        if ! jq -e --argjson artifact_id "${artifact_id}" \
          '.artifacts[]? | select(.id == $artifact_id)' \
          >/dev/null <<< "${post_delete_artifacts_json}"; then
          deletion_confirmed=true
          break
        fi
      fi
      sleep "${WAIT_SECONDS}"
    done
    if [[ "${deletion_confirmed}" != true ]]; then
      set_failure "Exact-ID deletion was not confirmed for artifact ${artifact_id}."
      exit 1
    fi
  fi

  row_ledger="$(jq -n \
    --argjson order "${order}" \
    --arg repository "${repository}" \
    --arg workflow "${workflow}" \
    --arg source_sha "${expected_sha}" \
    --argjson run_id "${run_id}" \
    --arg run_url "$(jq -r '.html_url' <<< "${run_json}")" \
    --arg conclusion "$(jq -r '.conclusion' <<< "${run_json}")" \
    --argjson artifact_id "${artifact_id}" \
    --arg artifact_name "${expected_artifact}" \
    --argjson artifact_bytes "${artifact_bytes}" \
    --arg expires_at "${expires_at}" \
    --arg local_zip "${zip_path#"${REPO_ROOT}"/}" \
    --arg zip_sha256 "${zip_sha256}" \
    --arg local_payload "${payload_path#"${REPO_ROOT}"/}" \
    --argjson payload_bytes "${payload_bytes}" \
    --arg payload_sha256 "${payload_sha256}" \
    --argjson resumed "${resumed_row}" \
    --argjson deletion_requested "${delete_after_download}" \
    --argjson deletion_confirmed "${deletion_confirmed:-false}" \
    '{
      order: $order,
      repository: $repository,
      workflow: $workflow,
      source_sha: $source_sha,
      resumed_from_interrupted_batch: $resumed,
      run: {id: $run_id, url: $run_url, event: "workflow_dispatch", conclusion: $conclusion},
      artifact: {
        id: $artifact_id,
        name: $artifact_name,
        api_size_in_bytes: $artifact_bytes,
        expires_at: $expires_at,
        local_zip: $local_zip,
        zip_sha256: $zip_sha256,
        local_payload: $local_payload,
        payload_bytes: $payload_bytes,
        payload_sha256: $payload_sha256,
        exact_id_deletion_requested_after_download: $deletion_requested,
        exact_id_deletion_confirmed: $deletion_confirmed
      },
      upload_gate_restored: true
    }')"
  jq --argjson row "${row_ledger}" '.rows += [$row]' \
    "${ledger_path}" > "${ledger_tmp}"
  mv "${ledger_tmp}" "${ledger_path}"

  if ! storage_json="$(collect_public_storage)"; then
    set_failure "Could not refresh public artifact and cache inventory after ${repository}."
    exit 1
  fi
  if [[ "$(jq -r '.cache_count' <<< "${storage_json}")" != 0 \
    || "$(jq -r '.app_jar_recurrence | length' <<< "${storage_json}")" != 0 ]]; then
    set_failure "Unexpected cache or app-jar state appeared after ${repository}."
    exit 1
  fi
  new_artifact_count="$(jq \
    --argjson baseline "${baseline_artifact_ids}" \
    '[.artifacts[].id | select(. as $id | $baseline | index($id) | not)] | length' \
    <<< "${storage_json}")"
  current_public_bytes="$(jq -r '.artifact_bytes' <<< "${storage_json}")"
  rolling_peak_bytes=$((current_public_bytes + (2 * RETAINED_CAP_BYTES) + FAILURE_DIAGNOSTIC_RESERVE_BYTES))
  if ((new_artifact_count != 0 || rolling_peak_bytes > PUBLIC_ALLOWANCE_BYTES)); then
    set_failure "Unexpected artifact growth or insufficient rolling headroom appeared after ${repository}."
    exit 1
  fi
done < <(jq -c '.[]' <<< "${matrix_json}")

failure_phase="final_verification"
while IFS= read -r repository; do
  if [[ "$(variable_value "${repository}" "${UPLOAD_VARIABLE}")" != false ]]; then
    set_failure "Final upload-gate verification failed for ${repository}."
    exit 1
  fi
done < <(jq -r '.[].repository' <<< "${matrix_json}")

batch_complete=true
