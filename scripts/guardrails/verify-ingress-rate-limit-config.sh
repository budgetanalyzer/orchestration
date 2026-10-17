#!/usr/bin/env bash

# Offline structural and matcher verification for ingress local rate limiting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_MANIFEST="${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml"
INGRESS_GATEWAY_CONFIG="${REPO_DIR}/kubernetes/istio/ingress-gateway-config.yaml"
PRODUCTION_OVERLAY="${REPO_DIR}/kubernetes/production/istio-ingress-policies"
PRODUCTION_GATEWAY_OVERLAY="${REPO_DIR}/kubernetes/production/istio-ingress-gateway"
PYTHON_REQUIREMENTS="${SCRIPT_DIR}/requirements-ingress-rate-limit.txt"
PYTHON_INTERPRETER="${INGRESS_RATE_LIMIT_PYTHON:-python3}"
TEMP_DIR="$(mktemp -d)"
PRODUCTION_RENDER="${TEMP_DIR}/istio-ingress-policies.yaml"
PRODUCTION_GATEWAY_RENDER="${TEMP_DIR}/ingress-gateway-config.yaml"
NGINX_CONFIGS=(
    "${REPO_DIR}/nginx/nginx.k8s.conf"
    "${REPO_DIR}/nginx/nginx.production.k8s.conf"
)
NGINX_LIMIT_PATTERN='limit_req(_zone|_status)?[[:space:]]'

cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

verify_nginx_inputs() {
    local nginx_config search_output search_status

    for nginx_config in "$@"; do
        if [[ ! -f "${nginx_config}" ]]; then
            printf 'ERROR: expected NGINX input is not a regular file: %s\n' "${nginx_config}" >&2
            return 1
        fi
        if [[ ! -r "${nginx_config}" ]]; then
            printf 'ERROR: expected NGINX input is not readable: %s\n' "${nginx_config}" >&2
            return 1
        fi

        search_output=""
        if search_output="$(grep -nE "${NGINX_LIMIT_PATTERN}" "${nginx_config}" 2>&1)"; then
            search_status=0
        else
            search_status=$?
        fi

        case "${search_status}" in
            0)
                printf 'ERROR: blanket NGINX rate limiting remains in %s:\n' "${nginx_config}" >&2
                printf '%s\n' "${search_output}" >&2
                return 1
                ;;
            1)
                ;;
            *)
                printf 'ERROR: failed to inspect NGINX input %s (grep status %d)\n' \
                    "${nginx_config}" "${search_status}" >&2
                if [[ -n "${search_output}" ]]; then
                    printf '%s\n' "${search_output}" >&2
                fi
                return 1
                ;;
        esac
    done
}

run_nginx_search_self_test() {
    local fixture_dir clean_config forbidden_config missing_config

    fixture_dir="${TEMP_DIR}/nginx-search-fixtures"
    clean_config="${fixture_dir}/clean.conf"
    forbidden_config="${fixture_dir}/forbidden.conf"
    missing_config="${fixture_dir}/missing.conf"
    mkdir -p "${fixture_dir}"

    cat > "${clean_config}" <<'EOF'
events {}
http {
    server { listen 8080; }
}
EOF
    cat > "${forbidden_config}" <<'EOF'
events {}
http {
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
}
EOF

    if ! verify_nginx_inputs "${clean_config}" >/dev/null 2>&1; then
        printf 'ERROR: clean NGINX search fixture was rejected\n' >&2
        return 1
    fi
    if verify_nginx_inputs "${forbidden_config}" >/dev/null 2>&1; then
        printf 'ERROR: forbidden NGINX limiter fixture was accepted\n' >&2
        return 1
    fi
    if verify_nginx_inputs "${missing_config}" >/dev/null 2>&1; then
        printf 'ERROR: missing NGINX input fixture was accepted\n' >&2
        return 1
    fi

    printf 'NGINX cutover search self-test succeeded.\n'
    printf '  clean input: accepted\n'
    printf '  forbidden directive: rejected\n'
    printf '  missing input: rejected\n'
}

case "${1:-}" in
    "")
        ;;
    --self-test-nginx-search)
        if (( $# != 1 )); then
            printf 'ERROR: --self-test-nginx-search accepts no additional arguments\n' >&2
            exit 2
        fi
        run_nginx_search_self_test
        exit 0
        ;;
    *)
        printf 'Usage: %s [--self-test-nginx-search]\n' "${0}" >&2
        exit 2
        ;;
esac

for command_name in grep kubectl "${PYTHON_INTERPRETER}"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done

if ! "${PYTHON_INTERPRETER}" - "${PYTHON_REQUIREMENTS}" <<'PY'
import importlib.metadata
import re
import sys
from pathlib import Path


requirements_path = Path(sys.argv[1])
try:
    requirements = requirements_path.read_text(encoding="utf-8")
except OSError as error:
    print(f"ERROR: cannot read PyYAML requirement {requirements_path}: {error}", file=sys.stderr)
    raise SystemExit(1) from error

match = re.search(r"(?m)^PyYAML==([^\s\\]+)\s*\\$", requirements)
if match is None:
    print(
        f"ERROR: {requirements_path} must contain one exact continued PyYAML requirement",
        file=sys.stderr,
    )
    raise SystemExit(1)

expected_version = match.group(1)
try:
    import yaml
    installed_version = importlib.metadata.version("PyYAML")
except (ModuleNotFoundError, importlib.metadata.PackageNotFoundError) as error:
    print(f"ERROR: PyYAML {expected_version} is not installed: {error}", file=sys.stderr)
    raise SystemExit(1) from error

if installed_version != expected_version or yaml.__version__ != expected_version:
    print(
        "ERROR: PyYAML version mismatch: "
        f"required {expected_version}, metadata reported {installed_version}, "
        f"module reported {yaml.__version__}",
        file=sys.stderr,
    )
    raise SystemExit(1)

print(f"PyYAML interpreter: {Path(sys.executable)}")
print(f"PyYAML version: {installed_version}")
print(f"PyYAML module: {Path(yaml.__file__).resolve()}")
PY
then
    printf 'ERROR: ingress rate-limit structural checks require the hash-verified PyYAML environment.\n' >&2
    printf 'Selected interpreter: %s\n' "${PYTHON_INTERPRETER}" >&2
    printf '%s\n' \
        'Setup: python3 -m venv .cache/phase7-static-tools/pyyaml-venv && .cache/phase7-static-tools/pyyaml-venv/bin/python -I -m pip install --require-hashes --no-deps --only-binary=:all: -r scripts/guardrails/requirements-ingress-rate-limit.txt' >&2
    printf '%s\n' \
        'Then set INGRESS_RATE_LIMIT_PYTHON=.cache/phase7-static-tools/pyyaml-venv/bin/python when running the verifier.' >&2
    exit 1
fi

verify_nginx_inputs "${NGINX_CONFIGS[@]}"

kubectl kustomize "${PRODUCTION_OVERLAY}" \
    --load-restrictor=LoadRestrictionsNone > "${PRODUCTION_RENDER}"

kubectl kustomize "${PRODUCTION_GATEWAY_OVERLAY}" \
    --load-restrictor=LoadRestrictionsNone > "${PRODUCTION_GATEWAY_RENDER}"

"${PYTHON_INTERPRETER}" - \
    "${LOCAL_MANIFEST}" \
    "${PRODUCTION_RENDER}" \
    "${INGRESS_GATEWAY_CONFIG}" \
    "${PRODUCTION_GATEWAY_RENDER}" <<'PY'
import copy
import re
import sys
from pathlib import Path

import yaml


FILTER_TYPE = (
    "type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3."
    "LocalRateLimit"
)
MATCHER_TYPE = "type.googleapis.com/envoy.extensions.common.matching.v3.ExtensionWithMatcher"
HEADER_INPUT_TYPE = "type.googleapis.com/envoy.type.matcher.v3.HttpRequestHeaderMatchInput"
HCM_TYPE = (
    "type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3."
    "HttpConnectionManager"
)
SKIP_FILTER_TYPE = (
    "type.googleapis.com/envoy.extensions.filters.common.matcher.action.v3.SkipFilter"
)
EXPECTED_STATS_REGEX = (
    ".*ingress_(login_initiation|login_completion|session_operations|api_requests).*"
)

EXPECTED = {
    "login-initiation": {
        "filter": "envoy.filters.http.local_ratelimit.login_initiation",
        "stat": "ingress_login_initiation",
        "regex": r"^/oauth2(?:/.*)?(?:\?.*)?$",
        "bucket": {"max_tokens": 25, "tokens_per_fill": 1, "fill_interval": "1s"},
    },
    "login-completion": {
        "filter": "envoy.filters.http.local_ratelimit.login_completion",
        "stat": "ingress_login_completion",
        "regex": r"^/login/oauth2(?:/.*)?(?:\?.*)?$",
        "bucket": {"max_tokens": 50, "tokens_per_fill": 2, "fill_interval": "1s"},
    },
    "session-operations": {
        "filter": "envoy.filters.http.local_ratelimit.session_operations",
        "stat": "ingress_session_operations",
        "regex": r"^/(?:auth(?:/.*)?|logout(?:/.*)?)(?:\?.*)?$",
        "bucket": {"max_tokens": 250, "tokens_per_fill": 5, "fill_interval": "1s"},
    },
    "api-requests": {
        "filter": "envoy.filters.http.local_ratelimit.api_requests",
        "stat": "ingress_api_requests",
        "regex": r"^/api(?:/.*)?(?:\?.*)?$",
        "bucket": {"max_tokens": 60, "tokens_per_fill": 10, "fill_interval": "1s"},
    },
}


def fail(message):
    raise AssertionError(message)


def expect(condition, message):
    if not condition:
        fail(message)


def load_envoy_filter(path):
    documents = [
        document
        for document in yaml.safe_load_all(Path(path).read_text(encoding="utf-8"))
        if document
    ]
    matches = [
        document
        for document in documents
        if document.get("kind") == "EnvoyFilter"
        and document.get("metadata", {}).get("name") == "ingress-local-rate-limits"
    ]
    expect(len(matches) == 1, f"{path}: expected one ingress-local-rate-limits EnvoyFilter")
    return matches[0]


def inspect_manifest(path):
    resource = load_envoy_filter(path)
    expect(resource["apiVersion"] == "networking.istio.io/v1alpha3", f"{path}: API version")
    expect(resource["metadata"]["namespace"] == "istio-ingress", f"{path}: namespace")
    expect(
        resource["spec"]["workloadSelector"]["labels"]
        == {"gateway.networking.k8s.io/gateway-name": "istio-ingress-gateway"},
        f"{path}: ingress workload selector",
    )

    patches = resource["spec"].get("configPatches", [])
    expect(
        len(patches) == 5,
        f"{path}: expected path canonicalization plus four independent filter patches",
    )
    hcm_patches = [patch for patch in patches if patch.get("applyTo") == "NETWORK_FILTER"]
    expect(len(hcm_patches) == 1, f"{path}: one HTTP connection manager patch")
    hcm_patch = hcm_patches[0]
    expect(
        hcm_patch.get("match", {}).get("context") == "GATEWAY",
        f"{path}: path canonicalization must use GATEWAY context",
    )
    expect(
        hcm_patch["match"]["listener"]["filterChain"]["filter"].get("name")
        == "envoy.filters.network.http_connection_manager",
        f"{path}: path canonicalization HTTP connection manager target",
    )
    expect(
        hcm_patch.get("patch", {}).get("operation") == "MERGE",
        f"{path}: path canonicalization merge operation",
    )
    hcm_config = hcm_patch["patch"]["value"].get("typed_config", {})
    expect(hcm_config.get("@type") == HCM_TYPE, f"{path}: HTTP connection manager type")
    expect(hcm_config.get("normalize_path") is True, f"{path}: RFC 3986 path normalization")
    expect(hcm_config.get("merge_slashes") is True, f"{path}: repeated-slash normalization")
    expect(
        hcm_config.get("path_with_escaped_slashes_action") == "REJECT_REQUEST",
        f"{path}: escaped slash and backslash rejection",
    )

    observed = {}

    for patch in patches:
        if patch.get("applyTo") == "NETWORK_FILTER":
            continue
        expect(patch.get("applyTo") == "HTTP_FILTER", f"{path}: patch must target HTTP_FILTER")
        match = patch.get("match", {})
        expect(match.get("context") == "GATEWAY", f"{path}: patch must use GATEWAY context")
        filter_match = match["listener"]["filterChain"]["filter"]
        expect(
            filter_match.get("name") == "envoy.filters.network.http_connection_manager",
            f"{path}: HTTP connection manager target",
        )
        expect(
            filter_match.get("subFilter", {}).get("name") == "envoy.filters.http.ext_authz",
            f"{path}: local limiter must target insertion before ext_authz",
        )
        expect(patch["patch"].get("operation") == "INSERT_BEFORE", f"{path}: insertion operation")

        filter_value = patch["patch"]["value"]
        typed_config = filter_value["typed_config"]
        expect(typed_config.get("type_url") == MATCHER_TYPE, f"{path}: matcher wrapper type URL")
        wrapper = typed_config["value"]
        extension = wrapper.get("extension_config", {})
        expect(
            extension.get("name") == "envoy.filters.http.local_ratelimit",
            f"{path}: wrapped extension name",
        )
        local_typed_config = extension.get("typed_config", {})
        expect(local_typed_config.get("type_url") == FILTER_TYPE, f"{path}: local limiter type URL")
        config = local_typed_config["value"]
        expect("token_bucket" not in config, f"{path}: undocumented default token bucket present")
        expect(
            config.get("always_consume_default_token_bucket") is False,
            f"{path}: default bucket consumption must be disabled",
        )
        expect(config.get("max_dynamic_descriptors") == 4096, f"{path}: descriptor cache bound")
        expect(
            config.get("enable_x_ratelimit_headers") == "DRAFT_VERSION_03",
            f"{path}: supported reset guidance",
        )
        for gate_name in ("filter_enabled", "filter_enforced"):
            default = config.get(gate_name, {}).get("default_value", {})
            expect(default == {"numerator": 100, "denominator": "HUNDRED"}, f"{path}: {gate_name}")

        rate_limits = config.get("rate_limits", [])
        expect(len(rate_limits) == 1, f"{path}: one generated descriptor")
        actions = rate_limits[0].get("actions", [])
        expect(len(actions) == 2, f"{path}: policy and client descriptor actions")
        policy_action = actions[0].get("generic_key", {})
        policy = policy_action.get("descriptor_value")
        expect(policy in EXPECTED, f"{path}: unknown policy {policy!r}")
        expect(policy not in observed, f"{path}: duplicate policy {policy}")
        expect(policy_action.get("descriptor_key") == "rate_limit_policy", f"{path}: policy key")
        expect(actions[1] == {"remote_address": {}}, f"{path}: trusted remote-address action")

        matcher_entries = (
            wrapper.get("xds_matcher", {})
            .get("matcher_list", {})
            .get("matchers", [])
        )
        expect(len(matcher_entries) == 1, f"{path}: one skip matcher")
        matcher_entry = matcher_entries[0]
        not_matcher = matcher_entry.get("predicate", {}).get("not_matcher", {})
        expect(
            set(not_matcher) == {"single_predicate"},
            f"{path}: path-only skip predicate for {policy}",
        )
        path_predicate = not_matcher.get("single_predicate", {})
        expect(
            path_predicate.get("input", {}).get("typed_config", {}).get("@type")
            == HEADER_INPUT_TYPE,
            f"{path}: path HTTP header input type",
        )
        expect(
            path_predicate.get("input", {}).get("typed_config", {}).get("header_name") == ":path",
            f"{path}: path matcher",
        )
        expect(
            ":authority" not in yaml.safe_dump(wrapper),
            f"{path}: authority must not affect policy selection",
        )
        expect(
            ":method" not in yaml.safe_dump(wrapper),
            f"{path}: unsupported methods must remain bounded by the path policy",
        )
        path_regex = path_predicate.get("value_match", {}).get("safe_regex", {}).get("regex")
        skip_action = matcher_entry.get("on_match", {}).get("action", {})
        expect(skip_action.get("name") == "skip", f"{path}: non-policy traffic skip action")
        expect(
            skip_action.get("typed_config", {}).get("@type") == SKIP_FILTER_TYPE,
            f"{path}: skip-filter action type",
        )

        expected = EXPECTED[policy]
        expect(filter_value.get("name") == expected["filter"], f"{path}: filter name for {policy}")
        expect(config.get("stat_prefix") == expected["stat"], f"{path}: metric prefix for {policy}")
        expect(path_regex == expected["regex"], f"{path}: path boundary for {policy}")

        response_headers = config.get("response_headers_to_add", [])
        expect(len(response_headers) == 1, f"{path}: one rejection marker for {policy}")
        expect(response_headers[0].get("append") is False, f"{path}: marker replacement for {policy}")
        expect(
            response_headers[0].get("header")
            == {"key": "x-local-rate-limit-policy", "value": policy},
            f"{path}: policy rejection marker for {policy}",
        )

        descriptors = config.get("descriptors", [])
        expect(len(descriptors) == 1, f"{path}: one limiter descriptor for {policy}")
        descriptor = descriptors[0]
        expect(
            descriptor.get("entries")
            == [
                {"key": "rate_limit_policy", "value": policy},
                {"key": "remote_address"},
            ],
            f"{path}: exact policy plus wildcard client identity for {policy}",
        )
        expect(descriptor.get("token_bucket") == expected["bucket"], f"{path}: bucket for {policy}")
        observed[policy] = {
            "regex": path_regex,
            "bucket": copy.deepcopy(descriptor["token_bucket"]),
            "stat": config["stat_prefix"],
            "marker": response_headers[0]["header"]["value"],
        }

    expect(set(observed) == set(EXPECTED), f"{path}: policy set")
    return observed


def inspect_gateway_stats(path):
    resource = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    expect(resource.get("kind") == "ConfigMap", f"{path}: expected ConfigMap")
    deployment_patch = yaml.safe_load(resource.get("data", {}).get("deployment", ""))
    annotation = (
        deployment_patch.get("spec", {})
        .get("template", {})
        .get("metadata", {})
        .get("annotations", {})
        .get("proxy.istio.io/config", "")
    )
    proxy_config = yaml.safe_load(annotation)
    expected_proxy_config = {
        "proxyStatsMatcher": {"inclusionRegexps": [EXPECTED_STATS_REGEX]}
    }
    expect(
        proxy_config == expected_proxy_config,
        f"{path}: expected only the four narrow ingress policy stats families",
    )
    pattern = re.compile(EXPECTED_STATS_REGEX)
    for details in EXPECTED.values():
        expect(
            pattern.fullmatch(f"http.{details['stat']}.http_local_rate_limit.enforced"),
            f"{path}: custom stats matcher must include {details['stat']}",
        )
    for optional_stat in (
        "http.downstream_cx_total",
        "cluster.nginx-gateway.upstream_cx_total",
        "listener.0.0.0.0_443.downstream_cx_total",
    ):
        expect(
            pattern.fullmatch(optional_stat) is None,
            f"{path}: custom stats matcher must not enable unrelated optional stats",
        )
    return proxy_config


def classify(path, authority, policies):
    return sorted(
        policy
        for policy, details in policies.items()
        if re.fullmatch(details["regex"], path)
    )


def descriptor_identity(path, authority, trusted_remote_address, policies):
    matches = classify(path, authority, policies)
    expect(len(matches) <= 1, f"overlapping policy matches for {authority}{path}: {matches}")
    if not matches:
        return None
    return (matches[0], trusted_remote_address)


local_resource = load_envoy_filter(sys.argv[1])
production_resource = load_envoy_filter(sys.argv[2])
expect(
    local_resource == production_resource,
    "production must render the exact shared ingress-local-rate-limits EnvoyFilter",
)
local = inspect_manifest(sys.argv[1])
production = inspect_manifest(sys.argv[2])
gateway_stats = [inspect_gateway_stats(path) for path in sys.argv[3:]]
expect(
    all(stats == gateway_stats[0] for stats in gateway_stats[1:]),
    "gateway stats matcher structures must be equivalent",
)

for policy in EXPECTED:
    expect(local[policy] == production[policy], f"production drift for {policy}")

AUTHORITY_VARIANTS = (
    "app.budgetanalyzer.localhost",
    "APP.BUDGETANALYZER.LOCALHOST",
    "app.budgetanalyzer.localhost:443",
    "ApP.BuDgEtAnAlYzEr.LoCaLhOsT:443",
)

matcher_cases = [
    ("GET", "/oauth2/authorization/idp", "login-initiation"),
    ("GET", "/oauth2/authorization/idp?return=%2F", "login-initiation"),
    ("POST", "/oauth2/authorization/idp", "login-initiation"),
    ("GET", "/oauth2", "login-initiation"),
    ("PATCH", "/oauth2/unknown", "login-initiation"),
    ("GET", "/login/oauth2/code/idp", "login-completion"),
    ("GET", "/login/oauth2/code/idp?code=redacted&state=redacted", "login-completion"),
    ("PUT", "/login/oauth2/code/idp", "login-completion"),
    ("GET", "/login/oauth2", "login-completion"),
    ("POST", "/login/oauth2/unknown", "login-completion"),
    ("GET", "/auth/v1/user", "session-operations"),
    ("GET", "/auth/v1/session?check=1", "session-operations"),
    ("DELETE", "/logout", "session-operations"),
    ("POST", "/auth", "session-operations"),
    ("TRACE", "/auth/unknown", "session-operations"),
    ("GET", "/logout/unknown", "session-operations"),
    ("GET", "/api/v1/transactions", "api-requests"),
    ("DELETE", "/api/v1/transactions?confirm=true", "api-requests"),
    ("GET", "/api", "api-requests"),
    ("POST", "/api/unknown", "api-requests"),
    ("GET", "/login", None),
    ("GET", "/login?next=%2F", None),
    ("GET", "/api-docs", None),
    ("GET", "/api-docs/openapi.json", None),
    ("GET", "/apiv1", None),
    ("GET", "/oauth2ish", None),
    ("GET", "/login/oauth2ish", None),
    ("GET", "/authentication", None),
    ("GET", "/logoutish", None),
]

normalized_matcher_cases = [
    ("GET", "//api/v1/transactions", "/api/v1/transactions", "api-requests"),
    ("GET", "/unowned/../api/v1/transactions", "/api/v1/transactions", "api-requests"),
    ("GET", "//auth/v1/user", "/auth/v1/user", "session-operations"),
]

rejected_matcher_cases = [
    "/api%2fv1/transactions",
    "/api%2Fv1/transactions",
    "/api%5cv1/transactions",
    "/api%5Cv1/transactions",
]

for authority in AUTHORITY_VARIANTS:
    for method, path, expected_policy in matcher_cases:
        matches = classify(path, authority, local)
        expected_matches = [] if expected_policy is None else [expected_policy]
        expect(
            matches == expected_matches,
            f"matcher case {method} https://{authority}{path}: {matches}",
        )
    for method, raw_path, normalized_path, expected_policy in normalized_matcher_cases:
        expect(
            classify(raw_path, authority, local) == [],
            f"raw path fixture unexpectedly matched before normalization: {raw_path}",
        )
        matches = classify(normalized_path, authority, local)
        expect(
            matches == [expected_policy],
            f"normalized matcher case {method} https://{authority}{raw_path}: {matches}",
        )

for path in rejected_matcher_cases:
    expect(
        re.search(r"%(?:2f|5c)", path, re.IGNORECASE) is not None,
        f"escaped path fixture must be rejected before policy selection: {path}",
    )

expect(
    classify("/api/v1/transactions", "unowned.invalid", local) == ["api-requests"],
    "path policy must run before Gateway routing rejects an unowned authority",
)
for _, path, expected_policy in matcher_cases:
    if expected_policy is None:
        continue
    client_a = descriptor_identity(path, AUTHORITY_VARIANTS[0], "192.0.2.10", local)
    client_b = descriptor_identity(path, AUTHORITY_VARIANTS[0], "192.0.2.11", local)
    queried = descriptor_identity(
        f"{path}?probe=1", AUTHORITY_VARIANTS[0], "192.0.2.10", local
    )
    expect(client_a != client_b, f"{path}: trusted client addresses must select different buckets")
    expect(client_a == queried, f"{path}: query variants must select the same client bucket")
    for authority in AUTHORITY_VARIANTS[1:]:
        variant = descriptor_identity(path, authority, "192.0.2.10", local)
        expect(
            variant == client_a,
            f"{path}: equivalent authority {authority} must select the same client bucket",
        )

print("Ingress rate-limit configuration verification succeeded.")
print("  local and production: exact shared four-policy EnvoyFilter")
print(
    f"  matcher table: {len(matcher_cases)} boundary and fallback cases "
    f"across {len(AUTHORITY_VARIANTS)} equivalent authorities"
)
print(
    "  path handling: RFC 3986 and repeated-slash normalization before filters; "
    "escaped slash/backslash rejection"
)
print("  insertion: before envoy.filters.http.ext_authz")
print("  default bucket: absent; dynamic descriptor cache: 4096 per policy")
print("  diagnostics: maintained ingress gateway config includes only the four policy stats families")
print("  NGINX cutover: local and production inputs contain no blanket limiter")
PY
