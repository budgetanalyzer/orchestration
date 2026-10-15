#!/bin/bash

# Offline structural and matcher verification for ingress local rate limiting.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOCAL_MANIFEST="${REPO_DIR}/kubernetes/istio/ingress-rate-limit.yaml"
INGRESS_GATEWAY_CONFIG="${REPO_DIR}/kubernetes/istio/ingress-gateway-config.yaml"
PRODUCTION_OVERLAY="${REPO_DIR}/kubernetes/production/istio-ingress-policies"
TEMP_DIR="$(mktemp -d)"
PRODUCTION_RENDER="${TEMP_DIR}/istio-ingress-policies.yaml"
NGINX_CONFIGS=(
    "${REPO_DIR}/nginx/nginx.k8s.conf"
    "${REPO_DIR}/nginx/nginx.production.k8s.conf"
    "${REPO_DIR}/kubernetes/production/nginx/nginx.production.k8s.conf"
)

cleanup() {
    rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

for command_name in kubectl python3 rg; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        printf 'ERROR: required command not found: %s\n' "${command_name}" >&2
        exit 1
    fi
done

for nginx_config in "${NGINX_CONFIGS[@]}"; do
    if rg -n 'limit_req(_zone|_status)?[[:space:]]' "${nginx_config}"; then
        printf 'ERROR: blanket NGINX rate limiting remains in %s\n' "${nginx_config}" >&2
        exit 1
    fi
done

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    printf 'ERROR: Python module PyYAML is required for structural manifest checks\n' >&2
    exit 1
fi

kubectl kustomize "${PRODUCTION_OVERLAY}" \
    --load-restrictor=LoadRestrictionsNone > "${PRODUCTION_RENDER}"

python3 - "${LOCAL_MANIFEST}" "${PRODUCTION_RENDER}" "${INGRESS_GATEWAY_CONFIG}" <<'PY'
import copy
import re
import sys
from pathlib import Path

import yaml


LOCAL_AUTHORITY = "app.budgetanalyzer.localhost"
PRODUCTION_AUTHORITY = "demo.budgetanalyzer.org"
FILTER_TYPE = (
    "type.googleapis.com/envoy.extensions.filters.http.local_ratelimit.v3."
    "LocalRateLimit"
)
MATCHER_TYPE = "type.googleapis.com/envoy.extensions.common.matching.v3.ExtensionWithMatcher"
HEADER_INPUT_TYPE = "type.googleapis.com/envoy.type.matcher.v3.HttpRequestHeaderMatchInput"
SKIP_FILTER_TYPE = (
    "type.googleapis.com/envoy.extensions.filters.common.matcher.action.v3.SkipFilter"
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


def inspect_manifest(path, expected_authority):
    resource = load_envoy_filter(path)
    expect(resource["apiVersion"] == "networking.istio.io/v1alpha3", f"{path}: API version")
    expect(resource["metadata"]["namespace"] == "istio-ingress", f"{path}: namespace")
    expect(
        resource["spec"]["workloadSelector"]["labels"]
        == {"gateway.networking.k8s.io/gateway-name": "istio-ingress-gateway"},
        f"{path}: ingress workload selector",
    )

    patches = resource["spec"].get("configPatches", [])
    expect(len(patches) == 4, f"{path}: expected four independent filter patches")
    observed = {}

    for patch in patches:
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
        match_predicates = (
            matcher_entry.get("predicate", {})
            .get("not_matcher", {})
            .get("and_matcher", {})
            .get("predicate", [])
        )
        expect(len(match_predicates) == 2, f"{path}: authority and path match predicates")
        authority_predicate = match_predicates[0].get("single_predicate", {})
        path_predicate = match_predicates[1].get("single_predicate", {})
        expect(
            authority_predicate.get("input", {}).get("typed_config", {}).get("@type")
            == HEADER_INPUT_TYPE,
            f"{path}: authority HTTP header input type",
        )
        expect(
            authority_predicate.get("input", {}).get("typed_config", {}).get("header_name")
            == ":authority",
            f"{path}: authority matcher",
        )
        expect(
            authority_predicate.get("value_match", {}).get("exact") == expected_authority,
            f"{path}: authority for {policy}",
        )
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
            all(
                predicate.get("single_predicate", {})
                .get("input", {})
                .get("typed_config", {})
                .get("header_name")
                != ":method"
                for predicate in match_predicates
            ),
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
            "authority": expected_authority,
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
    regexps = (
        proxy_config.get("proxyStatsMatcher", {}).get("inclusionRegexps", [])
        if isinstance(proxy_config, dict)
        else []
    )
    expect(len(regexps) == 1, f"{path}: expected one custom stats inclusion regexp")
    pattern = re.compile(regexps[0])
    for details in EXPECTED.values():
        expect(
            pattern.fullmatch(f"http.{details['stat']}.http_local_rate_limit.enforced"),
            f"{path}: custom stats matcher must include {details['stat']}",
        )


def classify(path, authority, policies):
    return sorted(
        policy
        for policy, details in policies.items()
        if authority == details["authority"] and re.fullmatch(details["regex"], path)
    )


def descriptor_identity(path, authority, trusted_remote_address, policies):
    matches = classify(path, authority, policies)
    expect(len(matches) <= 1, f"overlapping policy matches for {authority}{path}: {matches}")
    if not matches:
        return None
    return (matches[0], trusted_remote_address)


local = inspect_manifest(sys.argv[1], LOCAL_AUTHORITY)
production = inspect_manifest(sys.argv[2], PRODUCTION_AUTHORITY)
inspect_gateway_stats(sys.argv[3])

for policy in EXPECTED:
    local_semantics = {key: value for key, value in local[policy].items() if key != "authority"}
    production_semantics = {
        key: value for key, value in production[policy].items() if key != "authority"
    }
    expect(local_semantics == production_semantics, f"production drift for {policy}")

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

for method, path, expected_policy in matcher_cases:
    matches = classify(path, LOCAL_AUTHORITY, local)
    expected_matches = [] if expected_policy is None else [expected_policy]
    expect(matches == expected_matches, f"matcher case {method} {path}: {matches}")

expect(
    classify("/api/v1/transactions", "attacker.invalid", local) == [],
    "an unowned authority must not consume a policy bucket",
)
for path in (
    "/oauth2/authorization/idp",
    "/login/oauth2/code/idp",
    "/auth/v1/session",
    "/api/v1/transactions",
):
    client_a = descriptor_identity(path, LOCAL_AUTHORITY, "192.0.2.10", local)
    client_b = descriptor_identity(path, LOCAL_AUTHORITY, "192.0.2.11", local)
    queried = descriptor_identity(f"{path}?probe=1", LOCAL_AUTHORITY, "192.0.2.10", local)
    expect(client_a != client_b, f"{path}: trusted client addresses must select different buckets")
    expect(client_a == queried, f"{path}: query variants must select the same client bucket")

print("Ingress rate-limit configuration verification succeeded.")
print("  local and production: four equivalent per-client policies")
print(f"  matcher table: {len(matcher_cases)} boundary and fallback cases")
print("  insertion: before envoy.filters.http.ext_authz")
print("  default bucket: absent; dynamic descriptor cache: 4096 per policy")
print("  diagnostics: custom policy counters included by the gateway stats matcher")
print("  NGINX cutover: local and production inputs contain no blanket limiter")
PY
