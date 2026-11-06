#!/usr/bin/env bash
# Interpreter selection for the static guardrail Python checks. The default is
# the repository-local hash-verified PyYAML venv; INGRESS_RATE_LIMIT_PYTHON is
# the only override. There is no system python3 fallback.

GUARDRAIL_PYTHON_LIB_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARDRAIL_PYTHON="${INGRESS_RATE_LIMIT_PYTHON:-${GUARDRAIL_PYTHON_LIB_REPO_DIR}/.cache/phase7-static-tools/pyyaml-venv/bin/python}"

print_guardrail_python_setup() {
    printf '%s\n' \
        'Setup: python3 -m venv .cache/phase7-static-tools/pyyaml-venv && .cache/phase7-static-tools/pyyaml-venv/bin/python -I -m pip install --require-hashes --no-deps --only-binary=:all: -r scripts/guardrails/requirements-ingress-rate-limit.txt' \
        'The verifiers use that interpreter by default; INGRESS_RATE_LIMIT_PYTHON overrides it.' \
        'See docs/ci-cd.md#security-guardrailsyml.' >&2
}

require_guardrail_python() {
    if command -v -- "${GUARDRAIL_PYTHON}" >/dev/null 2>&1; then
        return 0
    fi

    printf 'ERROR: static guardrail Python interpreter is not executable: %s\n' "${GUARDRAIL_PYTHON}" >&2
    print_guardrail_python_setup
    return 1
}
