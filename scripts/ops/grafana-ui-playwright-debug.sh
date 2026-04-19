#!/usr/bin/env bash
# Browser-side Grafana dashboard diagnostic using an isolated Playwright runner.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GRAFANA_URL="${GRAFANA_URL:-http://127.0.0.1:3300}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
PLAYWRIGHT_VERSION="${PLAYWRIGHT_VERSION:-1.59.1}"
DEBUG_APPLICATION="${GRAFANA_DEBUG_APPLICATION:-currency-service}"
DEBUG_NAMESPACE="${GRAFANA_DEBUG_NAMESPACE:-default}"
DEBUG_INSTANCE="${GRAFANA_DEBUG_INSTANCE:-currency-service.default.svc.cluster.local:8084}"
ARTIFACT_DIR="${GRAFANA_DEBUG_ARTIFACT_DIR:-${REPO_DIR}/tmp/grafana-ui-debug}"
RUNNER_DIR="${ARTIFACT_DIR}"
SPEC_FILE="${ARTIFACT_DIR}/grafana-ui-debug.spec.mjs"
CONFIG_FILE="${ARTIFACT_DIR}/playwright.config.mjs"
BROWSERS_DIR="${ARTIFACT_DIR}/ms-playwright"

usage() {
    cat <<'EOF'
Usage: ./scripts/ops/grafana-ui-playwright-debug.sh [options]

Runs a one-off Playwright probe against a port-forwarded Grafana URL and writes
transient artifacts under tmp/grafana-ui-debug by default.

Options:
  --url URL              Grafana base URL.
                         Default: http://127.0.0.1:3300
  --application NAME     Dashboard application variable.
                         Default: currency-service
  --namespace NAME       Dashboard Namespace variable.
                         Default: default
  --instance VALUE       Dashboard instance variable.
                         Default: currency-service.default.svc.cluster.local:8084
  --artifact-dir PATH    Artifact directory. Default: tmp/grafana-ui-debug
  --with-deps            Also install Chromium OS dependencies through
                         Playwright. Use only if the container lacks them.
  -h, --help             Show this help text.

Environment overrides:
  GRAFANA_ADMIN_USER
  GRAFANA_ADMIN_PASSWORD
  PLAYWRIGHT_VERSION
  GRAFANA_DEBUG_APPLICATION
  GRAFANA_DEBUG_NAMESPACE
  GRAFANA_DEBUG_INSTANCE
  GRAFANA_DEBUG_ARTIFACT_DIR

The admin password is fetched from Secret/monitoring/prometheus-stack-grafana
when GRAFANA_ADMIN_PASSWORD is not set. It is passed to Playwright through the
environment only and is not written to generated files or artifacts. Start a
loopback-bound Grafana port-forward first unless --url points to an existing
reachable Grafana endpoint.
EOF
}

WITH_DEPS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            GRAFANA_URL="${2:-}"
            shift 2
            ;;
        --application)
            DEBUG_APPLICATION="${2:-}"
            shift 2
            ;;
        --namespace)
            DEBUG_NAMESPACE="${2:-}"
            shift 2
            ;;
        --instance)
            DEBUG_INSTANCE="${2:-}"
            shift 2
            ;;
        --artifact-dir)
            ARTIFACT_DIR="${2:-}"
            RUNNER_DIR="${ARTIFACT_DIR}"
            SPEC_FILE="${ARTIFACT_DIR}/grafana-ui-debug.spec.mjs"
            CONFIG_FILE="${ARTIFACT_DIR}/playwright.config.mjs"
            BROWSERS_DIR="${ARTIFACT_DIR}/ms-playwright"
            shift 2
            ;;
        --with-deps)
            WITH_DEPS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_non_empty() {
    local name="$1" value="$2"
    if [[ -z "${value}" ]]; then
        printf 'ERROR: %s must not be empty\n' "${name}" >&2
        exit 1
    fi
}

ensure_grafana_url_is_reachable() {
    local health_url="${GRAFANA_URL%/}/api/health"

    if ! curl -fsSk --max-time 5 "${health_url}" >/dev/null; then
        printf 'ERROR: Grafana is not reachable at %s\n' "${health_url}" >&2
        printf 'Start a loopback-bound port-forward first, for example:\n' >&2
        printf '  kubectl port-forward --address 127.0.0.1 -n monitoring svc/prometheus-stack-grafana 3300:80\n' >&2
        exit 1
    fi
}

fetch_grafana_password() {
    kubectl get secret -n monitoring prometheus-stack-grafana \
        -o jsonpath='{.data.admin-password}' | base64 --decode
}

write_runner_package() {
    mkdir -p "${RUNNER_DIR}"
    cat > "${RUNNER_DIR}/package.json" <<EOF
{
  "private": true,
  "type": "module",
  "dependencies": {
    "@playwright/test": "${PLAYWRIGHT_VERSION}"
  }
}
EOF
}

write_playwright_config() {
    cat > "${CONFIG_FILE}" <<'EOF'
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  outputDir: './test-results',
  timeout: 120000,
  expect: {
    timeout: 15000,
  },
  fullyParallel: false,
  reporter: [['line']],
  use: {
    baseURL: process.env.GRAFANA_URL || 'http://127.0.0.1:3300',
    ignoreHTTPSErrors: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    viewport: { width: 1440, height: 1200 },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
EOF
}

write_playwright_spec() {
    cat > "${SPEC_FILE}" <<'EOF'
import { test, expect } from '@playwright/test';
import fs from 'node:fs/promises';
import path from 'node:path';

const artifactDir = process.env.GRAFANA_ARTIFACT_DIR;
const username = process.env.GRAFANA_ADMIN_USER || 'admin';
const password = process.env.GRAFANA_ADMIN_PASSWORD;
const debugApplication = process.env.GRAFANA_DEBUG_APPLICATION || 'currency-service';
const debugNamespace = process.env.GRAFANA_DEBUG_NAMESPACE || 'default';
const debugInstance = process.env.GRAFANA_DEBUG_INSTANCE || 'currency-service.default.svc.cluster.local:8084';

if (!artifactDir) {
  throw new Error('GRAFANA_ARTIFACT_DIR is required');
}

if (!password) {
  throw new Error('GRAFANA_ADMIN_PASSWORD is required');
}

async function writeJson(name, value) {
  await fs.writeFile(path.join(artifactDir, name), `${JSON.stringify(value, null, 2)}\n`);
}

async function responseJson(response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return { parseError: true, text: text.slice(0, 4000) };
  }
}

function dashboardByUidOrTitle(dashboards, uid, titlePattern) {
  return dashboards.find((item) => item.uid === uid)
    || dashboards.find((item) => titlePattern.test(item.title || ''));
}

function dashboardUrl(item, params) {
  const url = new URL(item.url, process.env.GRAFANA_URL || 'http://127.0.0.1:3300');
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return `${url.pathname}${url.search}`;
}

async function fillFirst(page, options, value) {
  const labels = options.labels || [];
  const placeholders = options.placeholders || [];
  const selectors = options.selectors || [];

  for (const label of labels) {
    const locator = page.getByLabel(label).first();
    if (await locator.count() && await locator.isVisible().catch(() => false)) {
      await locator.fill(value);
      return;
    }
  }

  for (const placeholder of placeholders) {
    const locator = page.getByPlaceholder(placeholder).first();
    if (await locator.count() && await locator.isVisible().catch(() => false)) {
      await locator.fill(value);
      return;
    }
  }

  for (const selector of selectors) {
    const locator = page.locator(selector).first();
    if (await locator.count() && await locator.isVisible().catch(() => false)) {
      await locator.fill(value);
      return;
    }
  }

  throw new Error(`Could not find input matching labels=${labels.join(', ')} placeholders=${placeholders.join(', ')} selectors=${selectors.join(', ')}`);
}

async function waitForDashboard(page) {
  await page.waitForLoadState('domcontentloaded');
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(5000);
  await page.locator([
    '[data-testid="panel-container"]',
    '.panel-container',
    '[data-testid*="data-testid Panel"]',
    'text=/No data|N\\/A|Uptime|Heap|Threads/i',
  ].join(',')).first().waitFor({ timeout: 30000 }).catch(() => {});
}

async function inspectDashboard(page) {
  const bodyText = await page.locator('body').innerText({ timeout: 15000 }).catch(() => '');
  const visibleFlags = {
    nA: /\bN\/A\b/.test(bodyText),
    noData: /No data/i.test(bodyText),
    panelError: /Panel plugin not found|Query error|Datasource.*error|An unexpected error happened/i.test(bodyText),
  };

  const panels = await page.evaluate(() => {
    const selectors = [
      '[data-testid="panel-container"]',
      '.panel-container',
      '[class*="panel-container"]',
      '[class*="PanelContainer"]',
    ];
    const nodes = Array.from(new Set(selectors.flatMap((selector) => Array.from(document.querySelectorAll(selector)))));

    return nodes.slice(0, 80).map((node, index) => {
      const text = (node.innerText || '').replace(/\s+/g, ' ').trim();
      const titleNode = node.querySelector([
        '[data-testid*="Panel header"]',
        '[class*="panel-title"]',
        '[class*="PanelHeader"]',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
      ].join(','));
      const title = (titleNode?.textContent || '').replace(/\s+/g, ' ').trim() || text.slice(0, 100);

      return {
        index,
        title,
        hasNA: /\bN\/A\b/.test(text),
        hasNoData: /No data/i.test(text),
        hasError: /Panel plugin not found|Query error|Datasource.*error|An unexpected error happened/i.test(text),
        text: text.slice(0, 700),
      };
    });
  });

  return {
    url: page.url(),
    title: await page.title().catch(() => ''),
    visibleFlags,
    bodyMatches: {
      nACount: (bodyText.match(/\bN\/A\b/g) || []).length,
      noDataCount: (bodyText.match(/No data/gi) || []).length,
    },
    panels,
  };
}

function grafanaDataFramesHaveRows(payload) {
  const frames = payload?.results?.A?.frames || [];
  return frames.some((frame) => {
    const values = frame?.data?.values || [];
    return values.some((series) => Array.isArray(series) && series.length > 0);
  });
}

test('Grafana dashboard UI debug probe', async ({ page, request }) => {
  test.setTimeout(180000);

  const consoleErrors = [];
  const requestFailures = [];

  page.on('console', (message) => {
    if (['error', 'warning'].includes(message.type())) {
      consoleErrors.push({
        type: message.type(),
        text: message.text(),
        location: message.location(),
      });
    }
  });

  page.on('pageerror', (error) => {
    consoleErrors.push({
      type: 'pageerror',
      text: error.message,
      stack: error.stack,
    });
  });

  page.on('requestfailed', (req) => {
    requestFailures.push({
      method: req.method(),
      url: req.url(),
      failure: req.failure()?.errorText || 'unknown',
      resourceType: req.resourceType(),
    });
  });

  await test.step('Ingress smoke', async () => {
    const response = await request.get('/api/health');
    const payload = await responseJson(response);
    await writeJson('health.json', {
      status: response.status(),
      ok: response.ok(),
      payload,
    });
    expect(response.status()).toBe(200);
  });

  await test.step('Login flow', async () => {
    await page.goto('/login');
    await fillFirst(page, {
      labels: [/email or username/i, /username/i, /email/i],
      placeholders: [/email or username/i, /username/i, /email/i],
      selectors: [
        'input[name="user"]',
        'input[name="username"]',
        'input[autocomplete="username"]',
        'input[type="text"]',
        'input[type="email"]',
      ],
    }, username);
    await fillFirst(page, {
      labels: [/password/i],
      placeholders: [/password/i],
      selectors: [
        'input[name="password"]',
        'input[autocomplete="current-password"]',
        'input[type="password"]',
      ],
    }, password);

    await Promise.all([
      page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {}),
      page.locator('button[type="submit"], button:has-text("Log in"), button:has-text("Login")').first().click(),
    ]);

    const skip = page.getByRole('button', { name: /skip/i });
    if (await skip.isVisible({ timeout: 5000 }).catch(() => false)) {
      await skip.click();
      await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
    }

    const user = await page.evaluate(async () => {
      const res = await fetch('/api/user', { credentials: 'same-origin' });
      const text = await res.text();
      let payload;
      try {
        payload = JSON.parse(text);
      } catch {
        payload = { parseError: true, text: text.slice(0, 1000) };
      }
      return { status: res.status, ok: res.ok, payload };
    });
    await writeJson('post-login-user.json', user);
    await page.screenshot({ path: path.join(artifactDir, 'post-login.png'), fullPage: true });
    expect(user.ok).toBeTruthy();
  });

  let dashboards;
  let springBootDashboard;
  let jvmDashboard;

  await test.step('Dashboard inventory', async () => {
    const response = await page.request.get('/api/search?type=dash-db');
    dashboards = await responseJson(response);
    await writeJson('dashboard-search.json', {
      status: response.status(),
      ok: response.ok(),
      dashboards,
    });
    expect(response.ok()).toBeTruthy();

    springBootDashboard = dashboardByUidOrTitle(dashboards, 'spring-boot-3x', /Spring Boot 3\.x Statistics/i);
    jvmDashboard = dashboardByUidOrTitle(dashboards, 'jvm-micrometer', /JVM.*Micrometer/i);

    expect(springBootDashboard, 'Spring Boot dashboard should be provisioned').toBeTruthy();
    expect(jvmDashboard, 'JVM dashboard should be provisioned').toBeTruthy();
  });

  const commonParams = {
    orgId: '1',
    from: 'now-15m',
    to: 'now',
    'var-application': debugApplication,
    'var-Namespace': debugNamespace,
    'var-instance': debugInstance,
  };

  let springBootInspection;
  await test.step('Spring Boot dashboard baseline', async () => {
    await page.goto(dashboardUrl(springBootDashboard, commonParams));
    await waitForDashboard(page);
    await page.screenshot({ path: path.join(artifactDir, 'spring-boot-dashboard.png'), fullPage: true });
    springBootInspection = await inspectDashboard(page);
    await writeJson('spring-boot-panel-states.json', springBootInspection);
  });

  let jvmInspection;
  await test.step('JVM dashboard failure reproduction', async () => {
    await page.goto(dashboardUrl(jvmDashboard, commonParams));
    await waitForDashboard(page);
    await page.screenshot({ path: path.join(artifactDir, 'jvm-dashboard.png'), fullPage: true });
    jvmInspection = await inspectDashboard(page);
    await writeJson('jvm-panel-states.json', jvmInspection);
  });

  let queryPayload;
  await test.step('Grafana backend query check', async () => {
    const now = Date.now();
    const body = {
      from: String(now - 15 * 60 * 1000),
      to: String(now),
      queries: [
        {
          refId: 'A',
          datasource: { type: 'prometheus', uid: 'prometheus' },
          expr: `jvm_info{namespace="${debugNamespace}", application="${debugApplication}"}`,
          format: 'time_series',
          instant: true,
          range: false,
          intervalMs: 15000,
          maxDataPoints: 100,
        },
      ],
    };

    const response = await page.request.post('/api/ds/query', {
      data: body,
      headers: { 'content-type': 'application/json' },
    });
    queryPayload = await responseJson(response);
    await writeJson('jvm-query.json', {
      status: response.status(),
      ok: response.ok(),
      hasRows: grafanaDataFramesHaveRows(queryPayload),
      query: body.queries[0].expr,
      payload: queryPayload,
    });
    expect(response.ok()).toBeTruthy();
  });

  const summary = {
    grafanaUrl: process.env.GRAFANA_URL,
    debugVariables: {
      application: debugApplication,
      namespace: debugNamespace,
      instance: debugInstance,
    },
    dashboards: {
      springBoot: {
        uid: springBootDashboard.uid,
        title: springBootDashboard.title,
        url: springBootDashboard.url,
      },
      jvm: {
        uid: jvmDashboard.uid,
        title: jvmDashboard.title,
        url: jvmDashboard.url,
      },
    },
    results: {
      springBootVisibleFlags: springBootInspection.visibleFlags,
      jvmVisibleFlags: jvmInspection.visibleFlags,
      jvmBodyMatches: jvmInspection.bodyMatches,
      jvmBackendQueryHasRows: grafanaDataFramesHaveRows(queryPayload),
      consoleErrorCount: consoleErrors.length,
      requestFailureCount: requestFailures.length,
    },
    artifacts: {
      health: 'health.json',
      dashboardSearch: 'dashboard-search.json',
      postLoginScreenshot: 'post-login.png',
      springBootScreenshot: 'spring-boot-dashboard.png',
      jvmScreenshot: 'jvm-dashboard.png',
      consoleErrors: 'console-errors.json',
      requestFailures: 'request-failures.json',
      jvmQuery: 'jvm-query.json',
      springBootPanelStates: 'spring-boot-panel-states.json',
      jvmPanelStates: 'jvm-panel-states.json',
    },
  };

  await writeJson('console-errors.json', consoleErrors);
  await writeJson('request-failures.json', requestFailures);
  await writeJson('summary.json', summary);

  console.log(JSON.stringify(summary, null, 2));
});
EOF
}

main() {
    require_command kubectl
    require_command base64
    require_command curl
    require_command npm

    require_non_empty "--url" "${GRAFANA_URL}"
    require_non_empty "--application" "${DEBUG_APPLICATION}"
    require_non_empty "--namespace" "${DEBUG_NAMESPACE}"
    require_non_empty "--instance" "${DEBUG_INSTANCE}"
    require_non_empty "--artifact-dir" "${ARTIFACT_DIR}"
    ensure_grafana_url_is_reachable

    if [[ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        GRAFANA_ADMIN_PASSWORD="$(fetch_grafana_password)"
    fi
    require_non_empty "Grafana admin password" "${GRAFANA_ADMIN_PASSWORD}"

    mkdir -p "${ARTIFACT_DIR}"
    write_runner_package
    write_playwright_config
    write_playwright_spec

    printf 'Preparing isolated Playwright runner in %s\n' "${RUNNER_DIR}"
    npm install --prefix "${RUNNER_DIR}" --no-audit --no-fund >/dev/null

    export PLAYWRIGHT_BROWSERS_PATH="${BROWSERS_DIR}"
    if (( WITH_DEPS == 1 )); then
        "${RUNNER_DIR}/node_modules/.bin/playwright" install --with-deps chromium
    else
        "${RUNNER_DIR}/node_modules/.bin/playwright" install chromium
    fi

    printf 'Running Grafana UI debug probe against %s\n' "${GRAFANA_URL}"
    GRAFANA_URL="${GRAFANA_URL}" \
    GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER}" \
    GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD}" \
    GRAFANA_ARTIFACT_DIR="${ARTIFACT_DIR}" \
    GRAFANA_DEBUG_APPLICATION="${DEBUG_APPLICATION}" \
    GRAFANA_DEBUG_NAMESPACE="${DEBUG_NAMESPACE}" \
    GRAFANA_DEBUG_INSTANCE="${DEBUG_INSTANCE}" \
        "${RUNNER_DIR}/node_modules/.bin/playwright" test "${SPEC_FILE}" \
            --config "${CONFIG_FILE}" \
            --project=chromium \
            --reporter=line

    printf '\nGrafana UI debug artifacts written to %s\n' "${ARTIFACT_DIR}"
}

main "$@"
