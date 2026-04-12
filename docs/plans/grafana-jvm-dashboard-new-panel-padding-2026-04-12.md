# Grafana JVM Dashboard and `newPanelPadding` Investigation

## Scope

Investigate why setting `feature_toggles.newPanelPadding: false` fixed the
Spring Boot dashboard layout but caused the JVM Micrometer dashboard to show
`N/A`, without making dashboard/config changes during the investigation.

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

6. This is not a scrape or datasource failure.
   I verified at runtime that:
   - Prometheus has `jvm_info` for the Spring services
   - Prometheus returns `process_uptime_seconds{application="currency-service",instance="currency-service.default.svc.cluster.local:8084"}`
   - Grafana's own datasource proxy and `/api/ds/query` return valid frames for
     that same query

7. Grafana did not log dashboard parse/provisioning failures during startup.

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

1. Open the JVM dashboard in Grafana 12.
2. Save a modernized export from the UI after converting the legacy top row to
   native `stat` panels and preserving the existing PromQL.
3. Replace the dashboard source file under `kubernetes/monitoring/dashboards-src/`
   and regenerate/update the provisioned dashboard from that source, instead of
   hand-editing the embedded ConfigMap blob.

Why this is preferable:

- Removes the dependency on Grafana's legacy migration path.
- Keeps the change focused to one dashboard.
- Avoids piecemeal JSON surgery in the ConfigMap.

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

## Minimal Next Probe

Before changing repo files, the smallest useful confirmation step is:

1. In Grafana UI, duplicate the JVM dashboard.
2. Replace only the four legacy `Quick Facts` `singlestat` panels with native
   `stat` panels using the same PromQL.
3. Leave `newPanelPadding: false`.
4. If the duplicate renders correctly, treat that as confirmation that the
   issue is legacy panel migration/rendering, not Prometheus data.

That gives a clear go/no-go signal without committing to broad JSON edits.
