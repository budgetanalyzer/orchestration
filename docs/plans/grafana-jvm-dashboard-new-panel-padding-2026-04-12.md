# Grafana JVM Dashboard and `newPanelPadding` Investigation

## Scope

Investigate why setting `feature_toggles.newPanelPadding: false` fixed the
Spring Boot dashboard layout but caused the JVM Micrometer dashboard to show
`N/A`, without making dashboard/config changes during the investigation.

Follow-up implementation scope is JVM-only. The Spring Boot dashboard JSON is a
known-good reference and regression baseline; do not change it as part of this
plan unless later evidence proves it is independently broken.

## Implementation Attempt

The first implementation pass keeps the scope JVM-only:

- Added a reference modernized JVM dashboard source at
  `kubernetes/monitoring/dashboards-src/jvm-micrometer-grafana-4701-rev10.modernized.json`.
- Kept the original Grafana 4701 rev10 export in place for provenance.
- Removed the provisioned JVM dashboard's legacy top-level `rows` layout by
  flattening it into top-level Grafana row/panel entries.
- Converted the Quick Facts `singlestat` panels to native `stat` panels while
  preserving their existing panel PromQL.
- Changed the active JVM dashboard's `application` and `instance` variables to
  resolve from `jvm_info`, matching the documented dashboard label contract.
- Removed two obsolete JVM graph panels that rendered visible `No data` for the
  current Micrometer metric set: the Tomcat/Jetty thread-utilisation panel and
  the old `process_memory_*` process-memory panel. Prometheus exposes the
  existing JVM thread, file descriptor, CPU, and JVM memory metrics for the
  selected services, but not those older metric families.
- Kept `kubernetes/monitoring/grafana-dashboards-configmap.yaml` as the
  canonical deployment artifact. The dashboard source files under
  `kubernetes/monitoring/dashboards-src/` are reference/provenance only, and
  Tilt does not consume them directly.
- Browser verification for
  `tmp/grafana-ui-debug/jvm-modernized-attempt-2` opened both dashboards,
  confirmed the Grafana backend query for the selected JVM metric returned
  rows, and reported no visible JVM `N/A`, no visible JVM `No data`, and no
  JVM panel errors. One Grafana date-parsing console warning remains; it does
  not correspond to a panel error or failed request in that run.

## What I Checked

1. The toggle is wired exactly where expected in
   [kubernetes/monitoring/prometheus-stack-values.yaml](/workspace/orchestration/kubernetes/monitoring/prometheus-stack-values.yaml:68).
   Grafana is running with:
   - `newPanelPadding = false`
   - Grafana `12.4.2`

2. The repository provisions two dashboards through the mounted
   `grafana-dashboards` ConfigMap, as documented in
   [docs/architecture/observability.md](/workspace/orchestration/docs/architecture/observability.md:100).

3. The JVM dashboard is still an old export:
   - source file:
     [kubernetes/monitoring/dashboards-src/jvm-micrometer-grafana-4701-rev10.upstream.json](/workspace/orchestration/kubernetes/monitoring/dashboards-src/jvm-micrometer-grafana-4701-rev10.upstream.json:12)
   - declares Grafana `4.6.5`
   - uses legacy `rows`
   - uses deprecated `singlestat` panels

4. The provisioned JVM dashboard in
   [kubernetes/monitoring/grafana-dashboards-configmap.yaml](/workspace/orchestration/kubernetes/monitoring/grafana-dashboards-configmap.yaml:10)
   still contains that legacy shape:
   - `type":"singlestat"` in the top "Quick Facts" row at
     [kubernetes/monitoring/grafana-dashboards-configmap.yaml](/workspace/orchestration/kubernetes/monitoring/grafana-dashboards-configmap.yaml:20)
   - `schemaVersion":14` at
     [kubernetes/monitoring/grafana-dashboards-configmap.yaml](/workspace/orchestration/kubernetes/monitoring/grafana-dashboards-configmap.yaml:136)

5. The Spring Boot dashboard is materially different:
   - modern `panels` layout
   - `type":"stat"` and other current panel types
   - explicit `pluginVersion":"9.5.1"`
   - see
     [kubernetes/monitoring/grafana-dashboards-configmap.yaml](/workspace/orchestration/kubernetes/monitoring/grafana-dashboards-configmap.yaml:141)
   - this dashboard should be used as the model for the JVM Micrometer update,
     not edited as part of the fix

6. This is not a scrape or datasource failure.
   I verified at runtime that:
   - Prometheus has `jvm_info` for the Spring services
   - Prometheus returns `process_uptime_seconds{application="currency-service",instance="currency-service.default.svc.cluster.local:8084"}`
   - Grafana's own datasource proxy and `/api/ds/query` return valid frames for
     that same query

7. Grafana did not log dashboard parse/provisioning failures during startup.

8. A repeatable browser-side verification helper now exists:
   `./scripts/ops/grafana-ui-playwright-debug.sh`. The first verified run
   authenticated through `https://grafana.budgetanalyzer.localhost`, opened both
   provisioned dashboards, captured screenshots, and confirmed Grafana's backend
   datasource query for
   `jvm_info{namespace="default", application="currency-service"}` returned
   rows. In that run the JVM dashboard rendered visible `No data` states rather
   than visible `N/A` states, which still points at dashboard rendering or
   templating because the backend query had data.

## Working Theory

The `N/A` state is most likely a frontend compatibility problem in Grafana 12,
not a metrics problem.

More specifically:

- The JVM dashboard is relying on Grafana's legacy compatibility path to
  migrate old `singlestat` and `rows` JSON into the current scene-based
  dashboard renderer.
- The Spring Boot dashboard is already modern enough that disabling
  `newPanelPadding` only changes layout/chrome behavior and does not force
  fragile compatibility behavior.
- Because the JVM dashboard's queries succeed through Grafana's backend, the
  `N/A` output is most plausibly happening after query execution, during legacy
  dashboard migration or stat rendering.

Secondary possibility:

- The old templating/current-value model on the JVM dashboard is also fragile,
  and the visible `N/A` may be a variable-resolution regression rather than the
  `singlestat` migration itself.
- I did not see enough evidence to put this ahead of the legacy panel theory.

## Why This Fits the Evidence

- Grafana's own docs mark `newPanelPadding` as a preview feature toggle, not a
  stable compatibility contract:
  https://grafana.com/docs/grafana/latest/setup-grafana/configure-grafana/feature-toggles/
- Grafana's v8 release notes say `Singlestat` was discontinued and existing
  panels are automatically migrated to `Stat`:
  https://grafana.com/docs/grafana/latest/whatsnew/whats-new-in-v8-0/
- Our JVM dashboard is still effectively asking Grafana 12 to keep migrating a
  Grafana 4-era dashboard at render time, while the Spring Boot dashboard is
  already on modern panel definitions.

## Options

### Option 1: Modernize the JVM dashboard once, from source

This is the cleanest path.

Approach:

1. Capture a Playwright baseline before editing:
   ```bash
   ./scripts/ops/grafana-ui-playwright-debug.sh \
     --artifact-dir tmp/grafana-ui-debug/baseline
   ```
2. Open the JVM dashboard in Grafana 12.
3. Save a modernized JVM Micrometer export from the UI after converting the
   legacy top row to native `stat` panels and preserving the existing PromQL.
   Use the working Spring Boot dashboard as the shape/model for current
   Grafana panel JSON, but do not change the Spring Boot dashboard source.
4. Replace the dashboard source file under `kubernetes/monitoring/dashboards-src/`
   for the JVM Micrometer dashboard only, then regenerate/update only the JVM
   provisioned dashboard entry from that source instead of hand-editing the
   embedded ConfigMap blob.
5. Let Tilt apply the monitoring manifest change, or apply the updated
   `grafana-dashboards` ConfigMap directly during a local debugging iteration.
   Wait for Grafana's file provider to reload the mounted dashboard
   configuration.
6. Re-run Playwright against a new artifact directory:
   ```bash
   ./scripts/ops/grafana-ui-playwright-debug.sh \
     --artifact-dir tmp/grafana-ui-debug/jvm-modernized-attempt-1
   ```
7. Inspect `summary.json`, `jvm-panel-states.json`, `spring-boot-panel-states.json`,
   `jvm-query.json`, `jvm-dashboard.png`, `spring-boot-dashboard.png`,
   `console-errors.json`, and `request-failures.json`.
8. If the JVM dashboard still shows visible `N/A`, visible `No data`, panel
   errors, or empty JVM frames while the backend query has rows, adjust the
   dashboard JSON/export and repeat with
   `tmp/grafana-ui-debug/jvm-modernized-attempt-2`, then `attempt-3`, until the
   browser evidence passes.

Why this is preferable:

- Removes the dependency on Grafana's legacy migration path.
- Keeps the change focused to the JVM Micrometer dashboard.
- Avoids piecemeal JSON surgery in the ConfigMap.
- Produces browser screenshots and machine-readable panel state for every
  candidate fix, so the work can be iterated instead of judged by manual visual
  inspection alone.

Cost:

- One dashboard JSON refresh.
- Some JSON churn, but it is intentional churn, not incremental hacks.

## Option 2: Create a temporary modern canary dashboard first

If replacing the existing JVM dashboard feels too risky, create a parallel
dashboard first.

Approach:

1. Duplicate the JVM dashboard in Grafana.
2. Modernize only the top "Quick Facts" row first.
3. Export that dashboard as a candidate source file.
4. Compare behavior with `newPanelPadding: false` before touching the existing
   `jvm-micrometer` UID.

Why this is useful:

- Proves whether the failure is specifically the old `singlestat` row.
- Keeps rollback trivial.

Cost:

- Temporary duplicate dashboard management.

## Option 3: Keep the JVM dashboard legacy and back out the global toggle

If preserving the existing JVM dashboard exactly matters more than the Spring
Boot layout fix, revert `newPanelPadding: false` and solve the Spring Boot issue
locally in that dashboard instead.

Why to consider it:

- Lowest dashboard migration risk.

Why I would avoid it:

- It keeps us dependent on a global preview toggle for dashboard appearance.
- It leaves the Grafana 4-era JVM dashboard debt in place.

## Option 4: Try a Grafana patch/minor change before touching dashboards

If the goal is to avoid dashboard JSON churn entirely, try a Grafana upgrade
experiment first.

Approach:

1. Keep the dashboards unchanged.
2. Test the same toggle behavior on a newer supported Grafana build.
3. Re-check the JVM dashboard before deciding to modernize it.

Why to consider it:

- The break may be a Grafana 12.4.x renderer regression.

Why I would not start here:

- It trades dashboard debt for platform churn.
- There is no guarantee the next build preserves the Spring Boot fix and also
  fixes the JVM dashboard.

## Recommendation

Option 1 is the best long-term path.

The real problem is not the ConfigMap format. The real problem is that the JVM
dashboard is still a Grafana 4-era dashboard being kept alive by migration
logic inside Grafana 12. As long as that remains true, small global rendering
toggles can produce weird breakage.

If the team wants a lower-risk proving step first, do Option 2, then converge
to Option 1.

## Playwright Verification Loop

Use `./scripts/ops/grafana-ui-playwright-debug.sh` as the acceptance gate for
this plan. Manual Grafana inspection is still useful for editing dashboards, but
a fix is not complete until the script proves the browser behavior.

Baseline command:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh \
  --application currency-service \
  --namespace default \
  --instance currency-service.default.svc.cluster.local:8084 \
  --artifact-dir tmp/grafana-ui-debug/baseline
```

After each JVM dashboard candidate fix:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh \
  --application currency-service \
  --namespace default \
  --instance currency-service.default.svc.cluster.local:8084 \
  --artifact-dir tmp/grafana-ui-debug/attempt-N
```

Use `--with-deps` only if Playwright reports missing Chromium OS dependencies in
the current container. Do not generate or rewrite TLS certificates from the
container; the helper is already configured to tolerate the local mkcert trust
boundary.

For each run, treat these artifacts as the decision record:

- `summary.json`: high-level dashboard result, visible flags, and query status.
- `jvm-panel-states.json`: visible JVM panel text and detected `N/A`,
  `No data`, or panel error states.
- `spring-boot-panel-states.json`: regression check only. It proves the known
  working dashboard still behaves correctly; it is not evidence that the Spring
  Boot dashboard JSON should be edited.
- `jvm-query.json`: proof that Grafana's backend datasource path returns rows
  for the selected JVM metric.
- `jvm-dashboard.png` and `spring-boot-dashboard.png`: visual evidence for the
  current candidate.
- `console-errors.json` and `request-failures.json`: browser/runtime failure
  evidence.

Acceptance criteria:

- The script authenticates to Grafana and opens both provisioned dashboards.
- `jvm-query.json` shows rows for the selected JVM metric.
- The JVM dashboard screenshot and panel-state JSON do not show visible `N/A`,
  visible `No data`, panel plugin errors, query errors, or datasource errors
  for panels that should have data.
- The Spring Boot dashboard still opens cleanly and does not regress to broken
  layout, visible panel errors, or obvious `No data` states for the same
  workload.
- Browser console errors and request failures are either empty or unrelated to
  the dashboard candidate and documented in the run notes.

Iteration rule:

1. Run the baseline and keep its artifacts under a named directory.
2. Apply one small JVM Micrometer dashboard/config candidate.
3. Wait for Grafana to reload the provisioned dashboard.
4. Run Playwright into a fresh artifact directory.
5. Compare the new `summary.json`, panel-state JSON, screenshots, and error
   artifacts against baseline.
6. If the acceptance criteria fail, use the artifacts to choose the next
   JVM dashboard change and repeat. Do not broaden into Spring Boot dashboard
   edits, Grafana upgrades, or ingress changes until the artifacts show the JVM
   dashboard JSON path is exhausted.

## Minimal Next Probe

Before committing to broad dashboard replacement, the smallest useful
confirmation step is:

1. Run the Playwright baseline command above.
2. In Grafana UI, duplicate the JVM dashboard.
3. Replace only the four legacy `Quick Facts` `singlestat` panels with native
   `stat` panels using the same PromQL.
4. Leave `newPanelPadding: false`.
5. Export/apply the duplicate or candidate dashboard in a local-only iteration.
6. Re-run the Playwright helper into `tmp/grafana-ui-debug/canary-attempt-1`.
7. If the candidate renders correctly while `jvm-query.json` still shows rows,
   treat that as confirmation that the issue is legacy panel
   migration/rendering, not Prometheus data. If it still fails, iterate using
   the Playwright artifacts before changing unrelated platform settings.

That gives a clear go/no-go signal without committing to broad JSON edits.
