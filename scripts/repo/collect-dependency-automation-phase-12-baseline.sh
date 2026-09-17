#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
API_ROOT="https://api.github.com"
ORG="budgetanalyzer"
PER_PAGE=100
DEFAULT_OUTPUT="${REPO_ROOT}/tmp/dependency-automation/phase-12-phase-2-public-baseline.json"
OUTPUT_PATH="${1:-${DEFAULT_OUTPUT}}"

if [[ "$#" -gt 1 ]]; then
  echo "Usage: $0 [OUTPUT_PATH]" >&2
  exit 2
fi

for required_command in curl git jq rg; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${required_command}" >&2
    exit 1
  fi
done

output_dir="$(dirname "${OUTPUT_PATH}")"
mkdir -p "${output_dir}"
collection_id="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
raw_dir="${PHASE_2_RAW_DIR:-${output_dir}/raw-${collection_id}}"
mkdir -p "${raw_dir}"

api_get() {
  local url="$1"
  local destination="$2"
  local expected_status="${3:-200}"
  local attempt=1
  local http_status
  local reset_epoch
  local now_epoch
  local wait_seconds

  while ((attempt <= 3)); do
    http_status="$(curl --disable --silent --show-error --location \
      --header 'Accept: application/vnd.github+json' \
      --header 'X-GitHub-Api-Version: 2022-11-28' \
      --dump-header "${destination}.headers" \
      --output "${destination}" \
      --write-out '%{http_code}' \
      "${url}")"

    if [[ "${http_status}" == "${expected_status}" ]]; then
      return 0
    fi

    if [[ "${http_status}" == 403 || "${http_status}" == 429 ]]; then
      reset_epoch="$(awk 'tolower($1) == "x-ratelimit-reset:" {gsub("\r", "", $2); print $2}' \
        "${destination}.headers" | tail -n 1)"
      if [[ "${reset_epoch}" =~ ^[0-9]+$ ]]; then
        now_epoch="$(date -u '+%s')"
        wait_seconds=$((reset_epoch - now_epoch + 1))
        if ((wait_seconds > 0 && wait_seconds <= 60)); then
          sleep "${wait_seconds}"
          attempt=$((attempt + 1))
          continue
        fi
      fi
    fi

    if [[ "${http_status}" =~ ^5[0-9][0-9]$ ]] && ((attempt < 3)); then
      sleep "$((attempt * 2))"
      attempt=$((attempt + 1))
      continue
    fi

    echo "GitHub API request failed: expected HTTP ${expected_status}, received ${http_status}: ${url}" >&2
    if [[ -s "${destination}" ]]; then
      jq -r '.message // empty' "${destination}" >&2 2>/dev/null || true
    fi
    if [[ "${reset_epoch:-}" =~ ^[0-9]+$ ]]; then
      echo "Anonymous API reset: $(date -u -d "@${reset_epoch}" '+%Y-%m-%dT%H:%M:%SZ')" >&2
    fi
    exit 1
  done

  echo "GitHub API request exhausted retries: ${url}" >&2
  exit 1
}

collect_paginated_array() {
  local endpoint="$1"
  local jq_path="$2"
  local destination="$3"
  local page=1
  local page_file
  local item_count

  : > "${destination}.jsonl"
  while :; do
    page_file="${raw_dir}/$(basename "${destination}")-page-${page}.json"
    api_get "${API_ROOT}${endpoint}$([[ "${endpoint}" == *\?* ]] && printf '&' || printf '?')per_page=${PER_PAGE}&page=${page}" \
      "${page_file}"
    jq -c "${jq_path}[]" "${page_file}" >> "${destination}.jsonl"
    item_count="$(jq "${jq_path} | length" "${page_file}")"
    if ((item_count < PER_PAGE)); then
      break
    fi
    page=$((page + 1))
  done
  jq -s '.' "${destination}.jsonl" > "${destination}"
}

repos_file="${raw_dir}/public-repositories.json"
if [[ ! -s "${repos_file}" ]]; then
  collect_paginated_array "/orgs/${ORG}/repos?type=public" '.' "${repos_file}"
fi

artifact_items="${raw_dir}/artifact-items.jsonl"
cache_items="${raw_dir}/cache-items.jsonl"
: > "${artifact_items}"
: > "${cache_items}"

cache_counts_file="${raw_dir}/cache-counts.jsonl"
repository_count="$(jq 'length' "${repos_file}")"
if [[ ! -s "${cache_counts_file}" ]] \
  || [[ "$(jq -s 'length' "${cache_counts_file}")" != "${repository_count}" ]]; then
  : > "${cache_counts_file}"
  while IFS= read -r repository; do
    cache_page="${raw_dir}/${repository}-caches.html"
    curl --disable --silent --show-error --location \
      --output "${cache_page}" \
      "https://github.com/${ORG}/${repository}/actions/caches"
    cache_count="$(sed -nE 's/.*<strong>([0-9,]+) caches?<\/strong>.*/\1/p' "${cache_page}" \
      | head -n 1 | tr -d ',')"
    if [[ ! "${cache_count}" =~ ^[0-9]+$ ]]; then
      echo "Could not read the public Actions cache count for ${ORG}/${repository}" >&2
      exit 1
    fi
    jq -n --arg repository "${repository}" --argjson count "${cache_count}" \
      '{repository: $repository, count: $count}' >> "${cache_counts_file}"
  done < <(jq -r '.[].name' "${repos_file}" | sort)
fi
if [[ -z "${PHASE_2_RAW_DIR:-}" ]]; then
  rate_limit_file="${raw_dir}/rate-limit.json"
  api_get "${API_ROOT}/rate_limit" "${rate_limit_file}"
  remaining_requests="$(jq -r '.resources.core.remaining' "${rate_limit_file}")"
  reset_epoch="$(jq -r '.resources.core.reset' "${rate_limit_file}")"
  # Artifact history may require multiple pages. Reserve the full anonymous
  # allowance for a new collection; interrupted collections can resume from
  # their preserved raw directory without repeating completed requests.
  minimum_required_requests=59
  if ((remaining_requests < minimum_required_requests)); then
    echo "Anonymous GitHub API allowance is too low for a fresh collection: ${remaining_requests} remaining; ${minimum_required_requests} required." >&2
    echo "Anonymous API reset: $(date -u -d "@${reset_epoch}" '+%Y-%m-%dT%H:%M:%SZ')" >&2
    exit 1
  fi
fi

while IFS= read -r repository; do
  artifacts_file="${raw_dir}/${repository}-artifacts.json"
  caches_file="${raw_dir}/${repository}-caches.json"
  if [[ ! -s "${artifacts_file}" ]]; then
    collect_paginated_array "/repos/${ORG}/${repository}/actions/artifacts" '.artifacts' "${artifacts_file}"
  fi
  cache_count="$(jq -sr --arg repository "${repository}" \
    'map(select(.repository == $repository))[0].count' "${cache_counts_file}")"
  if ((cache_count > 0)); then
    collect_paginated_array "/repos/${ORG}/${repository}/actions/caches" '.actions_caches' "${caches_file}"
    observed_cache_count="$(jq 'length' "${caches_file}")"
    if [[ "${observed_cache_count}" != "${cache_count}" ]]; then
      echo "Public cache UI/API count mismatch for ${ORG}/${repository}: ${cache_count} vs ${observed_cache_count}" >&2
      exit 1
    fi
  else
    printf '[]\n' > "${caches_file}"
  fi

  jq -c --arg repository "${repository}" '
    .[] |
    select(.expired == false) |
    {
      repository: $repository,
      id,
      name,
      size_in_bytes,
      expired,
      created_at,
      updated_at,
      expires_at,
      workflow_run: {
        id: .workflow_run.id,
        head_branch: .workflow_run.head_branch,
        head_sha: .workflow_run.head_sha
      }
    }
  ' "${artifacts_file}" >> "${artifact_items}"

  jq -c --arg repository "${repository}" '
    .[] |
    {
      repository: $repository,
      id,
      key,
      ref,
      size_in_bytes,
      created_at,
      last_accessed_at
    }
  ' "${caches_file}" >> "${cache_items}"
done < <(jq -r '.[].name' "${repos_file}" | sort)

deleted_ids_file="${raw_dir}/deleted-artifact-ids.jsonl"
if [[ ! -s "${deleted_ids_file}" ]] \
  || [[ "$(jq -s 'length' "${deleted_ids_file}")" != 8 ]]; then
  : > "${deleted_ids_file}"
  while read -r repository artifact_id; do
    response_file="${raw_dir}/deleted-${repository}-${artifact_id}.json"
    api_get "${API_ROOT}/repos/${ORG}/${repository}/actions/artifacts/${artifact_id}" \
      "${response_file}" 404
    jq -n \
      --arg repository "${repository}" \
      --argjson artifact_id "${artifact_id}" \
      '{repository: $repository, artifact_id: $artifact_id, api_status: 404, absent: true}' \
      >> "${deleted_ids_file}"
  done <<'DELETED_IDS'
currency-service 10440009083
currency-service 10440089489
permission-service 10439738759
permission-service 10440034884
transaction-service 10440595892
transaction-service 10440114874
session-gateway 10439454814
session-gateway 10441010133
DELETED_IDS
fi

branch_baselines_file="${raw_dir}/branch-baselines.jsonl"
: > "${branch_baselines_file}"
while read -r repository expected_main expected_trial; do
  remote="https://github.com/${ORG}/${repository}.git"
  main_sha="$(git ls-remote --refs "${remote}" 'refs/heads/main' | awk '{print $1}')"
  trial_sha="$(git ls-remote --refs "${remote}" 'refs/heads/dependency-automation-trial' | awk '{print $1}')"

  if [[ -z "${main_sha}" || -z "${trial_sha}" ]]; then
    echo "Required branch is missing in ${ORG}/${repository}" >&2
    exit 1
  fi

  jq -n \
    --arg repository "${repository}" \
    --arg main_branch main \
    --arg expected_main_sha "${expected_main}" \
    --arg observed_main_sha "${main_sha}" \
    --arg trial_branch dependency-automation-trial \
    --arg expected_trial_sha "${expected_trial}" \
    --arg observed_trial_sha "${trial_sha}" \
    '{
      repository: $repository,
      main: {
        branch: $main_branch,
        expected_sha: $expected_main_sha,
        observed_sha: $observed_main_sha,
        matches: ($expected_main_sha == $observed_main_sha)
      },
      trial: {
        branch: $trial_branch,
        expected_sha: $expected_trial_sha,
        observed_sha: $observed_trial_sha,
        matches: ($expected_trial_sha == $observed_trial_sha)
      }
    }' >> "${branch_baselines_file}"
done <<'BRANCH_BASELINES'
orchestration 57089578957bae3da42587a7e2902727c5473149 c9e6f31208a5f668fcccd3e7ff2fea649654443c
service-common f31557761b80f17ce8fadc128e273b21b4fd07fe e9b91a63eccbc3e7e98528d80cbe89677d0d1f94
currency-service aa432316849c9231389f8a844325dcf0d64f7335 cca334840a5ad812f4745621e7196c281541393d
permission-service f2d9d55b149c1f3a00e7f2edd85bafe01a46c5f1 943edf82fa6fe55e625a70dc7b51bd26424bd3de
transaction-service ccc459f9ea954296a4d1cea6cdbc4b3acf994e6a c8e2b4ccef37e059357d01aed937e93894a85485
session-gateway a37c7a0bb832b857d3d7371e521ac82e99fc3b93 923637aadb8be5d9f87a9f88799bd7d6dd4905d7
budget-analyzer-web b6f0d23c38428daf8412ae055ccbc9db89ac9517 2cbef3f17f546fe167628b221a1cb9dec810c2bd
ext-authz 917eae9c782b4b1c4d576258883c3e558a7d55a1 75ed2bda4de7460332a8dea656def0459064753f
workspace 383efc840832d474cd9d60e0368ed2ded828e03c 6a6bf33fb019825b7709693a1b103c8a1dd7d726
BRANCH_BASELINES

candidate_runs_file="${raw_dir}/candidate-runs.jsonl"
: > "${candidate_runs_file}"
while read -r repository workflow expected_sha expected_job run_id job_id event run_started_at updated_at allowlisted_path_count target_count; do
  run_page="${raw_dir}/${repository}-${run_id}-run.html"
  job_page="${raw_dir}/${repository}-${job_id}-job.html"
  steps_file="${raw_dir}/${repository}-${job_id}-steps.jsonl"
  curl --disable --silent --show-error --location --output "${run_page}" \
    "https://github.com/${ORG}/${repository}/actions/runs/${run_id}"
  curl --disable --silent --show-error --location --output "${job_page}" \
    "https://github.com/${ORG}/${repository}/actions/runs/${run_id}/job/${job_id}"

  event_pattern="Triggered via ${event}"
  if [[ "${event}" == workflow_dispatch ]]; then
    event_pattern='Manually triggered'
  fi
  if ! rg -q "${event_pattern}" "${run_page}" \
    || ! rg -q "/commit/${expected_sha}" "${run_page}" \
    || ! rg -q 'title="dependency-automation-trial"' "${run_page}" \
    || ! rg -q 'Status</span>' "${run_page}" \
    || ! rg -q 'Success</span>' "${run_page}" \
    || ! sed -n '/Artifacts<\/span>/,+4p' "${run_page}" | rg -q '&ndash;'; then
    echo "Public run page did not match the source-exact successful zero-artifact contract: ${ORG}/${repository} ${run_id}" >&2
    exit 1
  fi

  awk '
    /<check-step/ {
      in_step = 1
      name = ""
      number = ""
      conclusion = ""
      started = ""
      completed = ""
    }
    in_step && /data-name=/ {
      line = $0
      sub(/^.*data-name="/, "", line)
      sub(/".*$/, "", line)
      name = line
    }
    in_step && /data-number=/ {
      line = $0
      sub(/^.*data-number="/, "", line)
      sub(/".*$/, "", line)
      number = line
    }
    in_step && /data-conclusion=/ {
      line = $0
      sub(/^.*data-conclusion="/, "", line)
      sub(/".*$/, "", line)
      conclusion = line
    }
    in_step && /data-started-at=/ {
      line = $0
      sub(/^.*data-started-at="/, "", line)
      sub(/".*$/, "", line)
      started = line
    }
    in_step && /data-completed-at=/ {
      line = $0
      sub(/^.*data-completed-at="/, "", line)
      sub(/".*$/, "", line)
      completed = line
    }
    in_step && /^[[:space:]]*>[[:space:]]*$/ {
      if (name != "") {
        printf "%s\t%s\t%s\t%s\t%s\n", number, name, conclusion, started, completed
      }
      in_step = 0
    }
  ' "${job_page}" | jq -Rc '
    split("\t") |
    {
      number: (.[0] | tonumber),
      name: .[1],
      status: "completed",
      conclusion: .[2],
      started_at: .[3],
      completed_at: .[4]
    }
  ' > "${steps_file}"

  if [[ ! -s "${steps_file}" ]] \
    || ! jq -se 'any(.[]; (.name | startswith("Measure complete trial")) and .conclusion == "success")' \
      "${steps_file}" >/dev/null; then
    echo "Public job page did not expose the successful measurement step: ${ORG}/${repository} ${job_id}" >&2
    exit 1
  fi

  upload_step_count="$(jq -s '[.[] | select(.name | test("^Upload (short-lived|capped)"))] | length' \
    "${steps_file}")"
  skipped_upload_step_count="$(jq -s \
    '[.[] | select((.name | test("^Upload (short-lived|capped)")) and .conclusion == "skipped")] | length' \
    "${steps_file}")"
  if [[ "${upload_step_count}" -lt 1 || "${upload_step_count}" != "${skipped_upload_step_count}" ]]; then
    echo "Upload steps were not uniformly skipped for ${ORG}/${repository} ${workflow}" >&2
    exit 1
  fi

  job_started_at="$(jq -sr 'map(.started_at) | min' "${steps_file}")"
  job_completed_at="$(jq -sr 'map(.completed_at) | max' "${steps_file}")"

  jq -n \
    --slurpfile steps "${steps_file}" \
    --arg repository "${repository}" \
    --arg workflow "${workflow}" \
    --arg expected_sha "${expected_sha}" \
    --arg expected_job "${expected_job}" \
    --argjson run_id "${run_id}" \
    --argjson job_id "${job_id}" \
    --arg event "${event}" \
    --arg run_started_at "${run_started_at}" \
    --arg updated_at "${updated_at}" \
    --arg job_started_at "${job_started_at}" \
    --arg job_completed_at "${job_completed_at}" \
    --argjson allowlisted_path_count "${allowlisted_path_count}" \
    --argjson target_count "${target_count}" \
    --argjson upload_step_count "${upload_step_count}" \
    --argjson skipped_upload_step_count "${skipped_upload_step_count}" '
    {
      repository: $repository,
      workflow: $workflow,
      expected_source_sha: $expected_sha,
      run: {
        id: $run_id,
        event: $event,
        head_branch: "dependency-automation-trial",
        head_sha: $expected_sha,
        status: "completed",
        conclusion: "success",
        run_attempt: 1,
        run_started_at: $run_started_at,
        updated_at: $updated_at,
        public_page_zero_artifacts: true
      },
      job: {
        id: $job_id,
        name: $expected_job,
        status: "completed",
        conclusion: "success",
        started_at: $job_started_at,
        completed_at: $job_completed_at,
        steps: $steps
      },
      no_upload_proof: {
        upload_step_count: $upload_step_count,
        skipped_upload_step_count: $skipped_upload_step_count,
        all_upload_steps_skipped: ($upload_step_count == $skipped_upload_step_count)
      },
      evidence_shape: {
        allowlisted_path_count: $allowlisted_path_count,
        scan_target_count: (if $target_count < 0 then null else $target_count end)
      },
      measurement: {
        source_bytes: null,
        tar_bytes: null,
        gzip_bytes: null,
        upload_allowed: null,
        source: "GitHub custom job summary; unavailable anonymously"
      }
    }
  ' >> "${candidate_runs_file}"
done <<'CANDIDATE_RUNS'
ext-authz go-vulnerability-check.yml 75ed2bda4de7460332a8dea656def0459064753f govulncheck 34823939945 103911598884 push 2026-09-14T08:40:43Z 2026-09-14T08:41:15Z 1 -1
budget-analyzer-web dependency-audit.yml 2cbef3f17f546fe167628b221a1cb9dec810c2bd npm-audit 34823959669 103911663283 push 2026-09-14T08:40:58Z 2026-09-14T08:41:28Z 1 -1
service-common dependency-submission.yml e9b91a63eccbc3e7e98528d80cbe89677d0d1f94 submit-gradle-dependencies 35092182970 104780850860 workflow_dispatch 2026-09-16T11:47:04Z 2026-09-16T11:49:43Z 2 -1
workspace workspace-image-security-evidence.yml 6a6bf33fb019825b7709693a1b103c8a1dd7d726 build-and-scan 35187741819 105093347726 push 2026-09-17T05:56:51Z 2026-09-17T06:00:40Z 1 1
orchestration exact-image-security-evidence.yml c9e6f31208a5f668fcccd3e7ff2fea649654443c exact-image-security-evidence 35095610628 104792069180 push 2026-09-16T12:24:12Z 2026-09-16T12:26:26Z 6 32
CANDIDATE_RUNS

generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ledger_tmp="${OUTPUT_PATH}.tmp-${collection_id}"
measurements_file="${PHASE_2_MEASUREMENTS_PATH:-${output_dir}/phase-12-phase-2-measurements.json}"
if [[ ! -s "${measurements_file}" ]]; then
  measurements_file="${raw_dir}/empty-measurements.json"
  printf '[]\n' > "${measurements_file}"
fi
measurement_count="$(jq 'length' "${measurements_file}")"
if [[ "${measurement_count}" != 0 && "${measurement_count}" != 5 ]]; then
  echo "Measurement input must contain either zero rows or all five rows: ${measurements_file}" >&2
  exit 1
fi
if ! jq -e '
  type == "array" and
  all(.[];
    (.repository | type == "string") and
    (.run_id | type == "number") and
    (.source_bytes | type == "number") and .source_bytes >= 0 and
    (.tar_bytes | type == "number") and .tar_bytes >= 0 and
    (.gzip_bytes | type == "number") and .gzip_bytes >= 0 and
    (.cap_bytes | type == "number") and .cap_bytes > 0 and
    (.upload_allowed | type == "boolean")
  ) and
  ((map([.repository, .run_id]) | unique | length) == length)
' "${measurements_file}" >/dev/null; then
  echo "Measurement input is malformed or contains duplicate repository/run rows: ${measurements_file}" >&2
  exit 1
fi
jq -n \
  --arg generated_at "${generated_at}" \
  --arg organization "${ORG}" \
  --slurpfile repositories "${repos_file}" \
  --slurpfile artifacts "${artifact_items}" \
  --slurpfile caches "${cache_items}" \
  --slurpfile deleted_ids "${deleted_ids_file}" \
  --slurpfile branch_baselines "${branch_baselines_file}" \
  --slurpfile candidate_runs "${candidate_runs_file}" \
  --slurpfile measurements "${measurements_file}" '
  ($candidate_runs | map(
    . as $candidate |
    (
      $measurements[0] |
      map(select(
        .repository == $candidate.repository and
        .run_id == $candidate.run.id
      )) |
      first
    ) as $measurement |
    if $measurement == null then
      .
    else
      .measurement = {
        source_bytes: $measurement.source_bytes,
        tar_bytes: $measurement.tar_bytes,
        gzip_bytes: $measurement.gzip_bytes,
        cap_bytes: $measurement.cap_bytes,
        upload_allowed: $measurement.upload_allowed,
        source: "Operator extraction from the selected GitHub custom job summary"
      }
    end
  )) as $enriched_candidate_runs |
  {
    schema_version: 1,
    generated_at: $generated_at,
    collection: {
      organization: $organization,
      credentialless: true,
      api_version: "2022-11-28",
      per_page: 100,
      cache_inventory_source: "Public GitHub Actions cache page count, with REST detail fallback for nonzero repositories",
      public_repository_count: ($repositories[0] | length),
      public_repositories: ($repositories[0] | map(.name) | sort)
    },
    public_storage: {
      artifacts: {
        non_expired_count: ($artifacts | length),
        total_bytes: ($artifacts | map(.size_in_bytes) | add // 0),
        items: ($artifacts | sort_by(.repository, .id)),
        app_jar_recurrence: ($artifacts | map(select(.name == "app-jar")) | sort_by(.repository, .id))
      },
      caches: {
        count: ($caches | length),
        total_bytes: ($caches | map(.size_in_bytes) | add // 0),
        items: ($caches | sort_by(.repository, .id))
      },
      deleted_artifact_ids: ($deleted_ids | sort_by(.repository, .artifact_id))
    },
    branch_baselines: ($branch_baselines | sort_by(.repository)),
    candidate_runs: $enriched_candidate_runs,
    candidate_execution_timeline: {
      overlaps: ([
        range(0; ($enriched_candidate_runs | length)) as $left_index |
        range($left_index + 1; ($enriched_candidate_runs | length)) as $right_index |
        $enriched_candidate_runs[$left_index] as $left |
        $enriched_candidate_runs[$right_index] as $right |
        select(
          $left.run.run_started_at < $right.run.updated_at and
          $right.run.run_started_at < $left.run.updated_at
        ) |
        {
          left: {repository: $left.repository, run_id: $left.run.id},
          right: {repository: $right.repository, run_id: $right.run.id}
        }
      ]),
      serialized: ([
        range(0; ($enriched_candidate_runs | length)) as $left_index |
        range($left_index + 1; ($enriched_candidate_runs | length)) as $right_index |
        $enriched_candidate_runs[$left_index] as $left |
        $enriched_candidate_runs[$right_index] as $right |
        select(
          $left.run.run_started_at < $right.run.updated_at and
          $right.run.run_started_at < $left.run.updated_at
        )
      ] | length == 0),
      disposition: "The publication-triggered source-exact ext-authz and budget-analyzer-web runs overlapped; this known historical deviation triggers no replacement dispatch because both candidates already exist. Any future Gate B work remains serialized."
    },
    measurement_summary_access: {
      anonymous_rest_api: false,
      anonymous_job_logs_http_status: 403,
      probed_repository: "workspace",
      probed_job_id: ($enriched_candidate_runs | map(select(.repository == "workspace"))[0].job.id),
      missing_rows: ($enriched_candidate_runs | map(select(.measurement.source_bytes == null) | .repository)),
      operator_input_scope: "SOURCE, TAR, GZIP, and ALLOWED for the five selected run IDs only; allowlist and target counts are workflow-derived"
    },
    private_usage: {
      artifact_bytes: "unknown",
      package_bytes: "unknown"
    },
    standing_zero_spend_baseline: {
      carried_forward: true,
      reconfirmation_requested: false
    },
    validation: {
      all_deleted_ids_absent: ($deleted_ids | all(.absent == true)),
      all_branch_shas_match: ($branch_baselines | all(.main.matches and .trial.matches)),
      all_candidate_runs_source_exact: ($enriched_candidate_runs | all(.run.head_sha == .expected_source_sha)),
      all_candidate_runs_match_trial_heads: ($enriched_candidate_runs | all(
        . as $candidate |
        $branch_baselines |
        any(
          .repository == $candidate.repository and
          .trial.observed_sha == $candidate.run.head_sha
        )
      )),
      all_candidate_jobs_successful: ($enriched_candidate_runs | all(.job.conclusion == "success")),
      all_upload_steps_skipped: ($enriched_candidate_runs | all(.no_upload_proof.all_upload_steps_skipped)),
      all_candidate_run_pages_report_zero_artifacts: ($enriched_candidate_runs | all(.run.public_page_zero_artifacts)),
      no_current_candidate_artifacts: (
        $enriched_candidate_runs as $runs |
        $artifacts |
        all(.workflow_run.id as $artifact_run_id | $runs | all(.run.id != $artifact_run_id))
      ),
      public_cache_inventory_empty: (($caches | length) == 0),
      app_jar_recurrence_absent: (($artifacts | map(select(.name == "app-jar")) | length) == 0),
      exact_measurements_complete: ($enriched_candidate_runs | all(
        .measurement.source_bytes != null and
        .measurement.tar_bytes != null and
        .measurement.gzip_bytes != null and
        .measurement.upload_allowed != null
      )),
      measurement_flags_match_cap: ($enriched_candidate_runs | all(
        .measurement.source_bytes == null or
        .measurement.upload_allowed == (
          if .repository == "workspace" then
            .measurement.gzip_bytes <= .measurement.cap_bytes
          else
            .measurement.tar_bytes <= .measurement.cap_bytes and
            .measurement.gzip_bytes <= .measurement.cap_bytes
          end
        )
      ))
    }
  }
' > "${ledger_tmp}"

if ! jq -e '
  .collection.public_repository_count > 0 and
  .validation.all_deleted_ids_absent and
  .validation.all_branch_shas_match and
  .validation.all_candidate_runs_source_exact and
  .validation.all_candidate_runs_match_trial_heads and
  .validation.all_candidate_jobs_successful and
  .validation.all_upload_steps_skipped and
  .validation.all_candidate_run_pages_report_zero_artifacts and
  .validation.no_current_candidate_artifacts and
  .validation.public_cache_inventory_empty and
  .validation.app_jar_recurrence_absent
' "${ledger_tmp}" >/dev/null; then
  echo "Collected evidence failed one or more public baseline invariants: ${ledger_tmp}" >&2
  exit 1
fi
if ((measurement_count > 0)) \
  && ! jq -e '.validation.exact_measurements_complete and .validation.measurement_flags_match_cap' \
    "${ledger_tmp}" >/dev/null; then
  echo "Exact measurement rows are incomplete or inconsistent with the checked-in helper gates: ${ledger_tmp}" >&2
  exit 1
fi

mv "${ledger_tmp}" "${OUTPUT_PATH}"
printf 'Wrote credential-free Phase 2 baseline: %s\n' "${OUTPUT_PATH}"
jq '{
  generated_at,
  public_repository_count: .collection.public_repository_count,
  artifact_count: .public_storage.artifacts.non_expired_count,
  artifact_bytes: .public_storage.artifacts.total_bytes,
  cache_count: .public_storage.caches.count,
  cache_bytes: .public_storage.caches.total_bytes,
  app_jar_count: (.public_storage.artifacts.app_jar_recurrence | length),
  candidate_runs: [.candidate_runs[] | {repository, run_id: .run.id}],
  exact_measurements_complete: .validation.exact_measurements_complete
}' "${OUTPUT_PATH}"
