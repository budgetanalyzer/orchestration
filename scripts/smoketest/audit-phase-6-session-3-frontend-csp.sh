#!/bin/bash

# audit-phase-6-session-3-frontend-csp.sh
#
# Static stop-gate audit for the frontend strict-CSP contract.
# Rebuilds the sibling production-smoke frontend bundle and checks for the
# known strict-CSP blockers before the NGINX enforcement split lands.
#
# This script does not replace the manual browser-console validation required
# by the edge/browser security plan. It makes the repo-owned audit repeatable and keeps the
# coordinated sibling prerequisite explicit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATION_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="$(cd "${ORCHESTRATION_DIR}/.." && pwd)"
WEB_DIR="${WORKSPACE_DIR}/budget-analyzer-web"
DOC_PATH="docs/development/local-environment.md"

PASSED=0
FAILED=0

section() { printf '\n=== %s ===\n' "$1"; }
pass() { printf '  [PASS] %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAILED=$((FAILED + 1)); }
info() { printf '  [INFO] %s\n' "$1"; }

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "$1" >&2
        exit 1
    fi
}

require_web_repo() {
    if [[ ! -d "${WEB_DIR}" ]]; then
        printf 'ERROR: sibling repo not found: %s\n' "${WEB_DIR}" >&2
        exit 1
    fi
}

check_same_origin_smoke_assets() {
    local index_html="${WEB_DIR}/dist/index.html"

    if rg -q '/_prod-smoke/assets/index-.*\.js' "${index_html}" &&
        rg -q '/_prod-smoke/assets/index-.*\.css' "${index_html}"; then
        pass "production-smoke index.html references same-origin /_prod-smoke/assets bundle files"
    else
        fail "production-smoke index.html does not reference both same-origin JS and CSS bundle files"
    fi
}

check_eval_tokens() {
    local eval_hits
    local function_hits

    eval_hits="$(grep -RIn 'eval(' "${WEB_DIR}/dist" || true)"
    function_hits="$(grep -RIn 'new Function' "${WEB_DIR}/dist" || true)"

    if [[ -z "${eval_hits}" && -z "${function_hits}" ]]; then
        pass "production-smoke bundle does not contain literal eval/new Function tokens"
    else
        fail "production-smoke bundle still contains eval-like tokens"
        [[ -n "${eval_hits}" ]] && printf '%s\n' "${eval_hits}" >&2
        [[ -n "${function_hits}" ]] && printf '%s\n' "${function_hits}" >&2
    fi
}

check_inline_style_props() {
    local hits

    hits="$(rg -n 'style=\{\{' "${WEB_DIR}/src" -g '*.tsx' -g '*.jsx' || true)"
    if [[ -z "${hits}" ]]; then
        pass "frontend source no longer uses JSX inline style props"
    else
        fail "frontend source still uses JSX inline style props that violate strict style-src"
        printf '%s\n' "${hits}" >&2
    fi
}

check_sonner_runtime_css_injection() {
    local sonner_imports
    local bundle_has_sonner_css=false
    local package_hits=""

    sonner_imports="$(rg -n 'from .sonner.|from \"sonner\"' "${WEB_DIR}/src" || true)"

    if [[ -z "${sonner_imports}" ]]; then
        pass "frontend source does not import sonner"
        return
    fi

    if [[ -d "${WEB_DIR}/node_modules/sonner/dist" ]]; then
        package_hits="$(rg -n "createElement\\('style'\\)|createElement\\(\"style\"\\)|styleSheet\\.cssText|appendChild\\(document\\.createTextNode" "${WEB_DIR}/node_modules/sonner/dist" -g '!**/*.map' || true)"
    fi

    if rg -q '__insertCSS|data-sonner-toaster' "${WEB_DIR}/dist/assets"; then
        bundle_has_sonner_css=true
    fi

    if [[ "${bundle_has_sonner_css}" == "true" || -n "${package_hits}" ]]; then
        fail "sonner remains a strict-CSP blocker because the installed package injects runtime CSS"
        printf '%s\n' "${sonner_imports}" >&2
        if [[ "${bundle_has_sonner_css}" == "true" ]]; then
            printf '%s\n' "built bundle still contains sonner CSS injection markers (__insertCSS/data-sonner-toaster)" >&2
        fi
        [[ -n "${package_hits}" ]] && printf '%s\n' "${package_hits}" >&2
    else
        pass "sonner imports no longer pull runtime CSS injection into the production bundle"
    fi
}

main() {
    section "Frontend CSP Audit"

    require_command npm
    require_command rg
    require_web_repo

    info "Orchestration directory: ${ORCHESTRATION_DIR}"
    info "Frontend repo: ${WEB_DIR}"

    section "Build"
    (
        cd "${WEB_DIR}"
        npm run build:prod-smoke
    )
    pass "npm run build:prod-smoke completed successfully"

    section "Bundle checks"
    check_same_origin_smoke_assets
    check_eval_tokens

    section "Strict-CSP blockers"
    check_inline_style_props
    check_sonner_runtime_css_injection

    section "Summary"
    printf 'Passed: %d\n' "${PASSED}"
    printf 'Failed: %d\n' "${FAILED}"
    info "Static findings are documented in ${DOC_PATH}"
    info "Manual browser-console validation is still required before relying on the strict-CSP check"

    if [[ "${FAILED}" -gt 0 ]]; then
        exit 1
    fi
}

main "$@"
