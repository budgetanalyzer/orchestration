# Grafana UI Playwright Debug Plan

## Goal

Use Playwright from the orchestration workspace to exercise the live Grafana UI
through the same local ingress URL a browser uses:

```bash
https://grafana.budgetanalyzer.localhost
```

The immediate debugging target is the Grafana dashboard/UI behavior described in
`docs/plans/grafana-jvm-dashboard-new-panel-padding-2026-04-12.md`.

## Current Verified Facts

- Grafana is running in the `monitoring` namespace as
  `deployment/prometheus-stack-grafana`.
- The route is `HTTPRoute/monitoring/grafana-route`.
- The route host is `grafana.budgetanalyzer.localhost`.
- The route backend is `Service/monitoring/prometheus-stack-grafana` on port
  `80`.
- `https://grafana.budgetanalyzer.localhost/api/health` currently returns
  `200` with `curl -k`.
- The container resolves `grafana.budgetanalyzer.localhost` to `127.0.0.1`.
- Node `v20.20.2` and npm `10.8.2` are available in the container.
- There is no repo-local Playwright project/configuration to reuse.
- Repo-local `tmp/` is ignored by `.gitignore`.

## Credential Handling

Fetch the admin password at runtime from Kubernetes and keep it out of checked-in
files:

```bash
GRAFANA_ADMIN_PASSWORD="$(
  kubectl get secret -n monitoring prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 --decode
)"
```

Use `admin` as the username unless the chart configuration proves otherwise.

Do not write the password into plan files, screenshots, traces, logs, or
committed scripts. If a temporary Playwright script is needed, pass the password
through environment variables only.

## Playwright Execution Strategy

Because this repo has no existing Playwright setup, use an isolated runner
instead of adding a permanent JavaScript test project for a one-off debugging
probe.

Create a real temporary spec file at:

```bash
tmp/grafana-ui-debug/grafana-ui-debug.spec.mjs
```

Keep it untracked under ignored `tmp/`. If a fully out-of-repo temporary file is
preferred for a given run, use `/tmp/grafana-ui-debug.spec.mjs` with the same
contents.

Preferred command shape:

```bash
npx playwright install chromium
GRAFANA_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
  npx playwright test tmp/grafana-ui-debug/grafana-ui-debug.spec.mjs \
    --project=chromium \
    --reporter=line
```

If browser dependencies are missing inside the container, install only the
needed Chromium dependencies for the current environment, then rerun the same
probe. Do not change repo dependency files unless the debugging evolves into a
repeatable project test.

Configure Playwright with:

- `baseURL: "https://grafana.budgetanalyzer.localhost"`
- `ignoreHTTPSErrors: true`, because the container's Playwright browser does
  not necessarily trust the host mkcert CA even when the user's browser does
- screenshots on failure
- trace collection for targeted failing probes
- console and page error capture

Do not generate or rewrite TLS certificates from the container. The goal is to
debug Grafana UI behavior, so Playwright should tolerate the local development
certificate trust mismatch rather than changing the certificate setup.

## Probe Sequence

1. **Ingress smoke**
   - Request `/api/health` through Playwright's API context.
   - Assert HTTP `200`.
   - Record the JSON response for version and database status.

2. **Login flow**
   - Open `/login`.
   - Fill username `admin`.
   - Fill the password from `GRAFANA_ADMIN_PASSWORD`.
   - Submit the form.
   - Assert the page reaches an authenticated Grafana shell.
   - Save a post-login screenshot.

3. **Dashboard inventory**
   - Call Grafana's authenticated dashboard search API.
   - Confirm the provisioned dashboards are present:
     - JVM/Micrometer dashboard
     - Spring Boot 3.x dashboard
   - Capture dashboard UIDs and URLs from the API instead of relying on brittle
     menu navigation.

4. **Spring Boot dashboard baseline**
   - Navigate directly to the Spring Boot dashboard URL.
   - Wait for panels to finish loading.
   - Capture a screenshot.
   - Record console errors, request failures, and visible panel error states.

5. **JVM dashboard failure reproduction**
   - Navigate directly to the JVM dashboard URL.
   - Wait for panels to finish loading.
   - Capture a screenshot.
   - Record visible `N/A`, `No data`, and panel error states.
   - Capture browser console errors and failed network requests.

6. **Grafana backend query check from the browser session**
   - From the authenticated browser context, call Grafana datasource/query APIs
     for a simple JVM metric already known to exist in Prometheus.
   - Compare "backend query returns data" with "panel renders N/A" to separate
     data-path failures from frontend rendering/migration failures.

7. **Targeted UI inspection**
   - Inspect the rendered panel DOM for the affected JVM panels.
   - Record panel title, plugin type visible in the page model if available,
     displayed value, and any panel-level error text.
   - If useful, open the panel inspect drawer and capture the query/data view.

## Artifacts To Collect

Store transient artifacts under a local ignored location such as:

```bash
tmp/grafana-ui-debug/
```

Collect:

- `health.json`
- `dashboard-search.json`
- `spring-boot-dashboard.png`
- `jvm-dashboard.png`
- `console-errors.json`
- `request-failures.json`
- Playwright trace archive for any failing case

Do not store credentials in artifacts.

## Success Criteria

The first Playwright pass is successful when it can:

- authenticate to Grafana through `https://grafana.budgetanalyzer.localhost`
- open both provisioned dashboards
- capture screenshots for both dashboards
- report whether the JVM dashboard `N/A` state is visible in the browser
- report whether Grafana backend queries return data for the same JVM metrics
- capture enough browser-side evidence to decide whether the next step is
  dashboard modernization, Grafana configuration, or ingress/session routing

## Initial Triage Rules

- If `/api/health` fails in Playwright but works with `curl -k`, focus on
  Playwright DNS/TLS/browser launch environment.
- If login fails, verify the admin password secret and check Grafana logs before
  investigating dashboards.
- If dashboard search fails after login, inspect Grafana auth/session cookies
  and API responses.
- If backend query APIs return data but panels render `N/A`, continue from the
  legacy dashboard migration/rendering theory in
  `docs/plans/grafana-jvm-dashboard-new-panel-padding-2026-04-12.md`.
- If backend query APIs do not return data, shift focus to datasource
  provisioning, Prometheus labels, and query templating variables.

## Next Action

Create a disposable Playwright spec, run the probe sequence, and summarize the
screenshots/API evidence before changing dashboard JSON or Grafana
configuration.

## Implementation

Implemented as `./scripts/ops/grafana-ui-playwright-debug.sh`.

The helper keeps the Playwright runner, generated spec/config, browser cache,
screenshots, API responses, console errors, request failures, and panel-state
summaries under ignored `tmp/grafana-ui-debug/`. It installs
`@playwright/test` only inside that ignored artifact directory, fetches the
Grafana admin password from the Kubernetes secret when
`GRAFANA_ADMIN_PASSWORD` is not already set, and passes credentials to the
generated spec through environment variables only.

Run:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh
```

Optional overrides:

```bash
./scripts/ops/grafana-ui-playwright-debug.sh \
  --application currency-service \
  --namespace default \
  --instance currency-service.default.svc.cluster.local:8084
```

The first verified run authenticated to Grafana through
`https://grafana.budgetanalyzer.localhost`, opened both provisioned dashboards,
captured screenshots, and confirmed the Grafana backend datasource query for
`jvm_info{namespace="default", application="currency-service"}` returned rows.
The JVM dashboard rendered two visible `No data` panel states and no visible
`N/A` states for that run.
