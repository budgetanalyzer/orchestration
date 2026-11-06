#!/usr/bin/env python3
"""Pin ingress header ownership and the environment-specific CSP render contract."""

import importlib.util
from pathlib import Path
import subprocess
import sys

import yaml


ROOT = Path(__file__).resolve().parents[2]
RENDERER = ROOT / "deploy/scripts/render/render-csp.py"
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("csp", RENDERER)
csp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(csp)


def check_profiles(data, origin, expected_count):
    profiles = {k: v for k, v in data.items() if k.startswith("security-headers-")}
    assert len(profiles) == expected_count, profiles.keys()
    for name, source in profiles.items():
        assert csp.TOKEN not in source, name
        assert "X-XSS-Protection" not in source, name
        assert source.count("form-action ") == 1, name
        assert f"form-action 'self' {origin};" in source, name


def main():
    valid = {
        "https://TENANT.example/": "https://tenant.example",
        "https://tenant.example:443/oidc": "https://tenant.example",
        "https://tenant.example:8443/oidc": "https://tenant.example:8443",
        "https://[::1]:8443/": "https://[::1]:8443",
    }
    for issuer, origin in valid.items():
        assert csp.issuer_origin(issuer) == origin
        check_profiles({p.name: csp.render(p.read_text(), origin)
                        for p in csp.INCLUDES.glob("security-headers-*.conf")}, origin, 3)
    invalid = ["", "http://tenant.example/", "https://*.example/", "https://user@tenant.example/",
               "https://tenant.example/?x=1", "https://tenant.example/#fragment", "https:///",
               "https://tenant.example\n/", "https://tenant.example:0/", "https://tenant.example:/",
               "https://tenant.example:65536/", "https://tenant.example\\@evil.example/",
               "https://tenant.example/; form-action *", "https://-bad.example/",
               "https://tenant..example/", "https://tenant.example/%zz", "https://tenant.example/a|b", "https://[::1%eth0]/", "https://[::1]evil/"]
    for issuer in invalid:
        result = subprocess.run([sys.executable, str(RENDERER), "--issuer", issuer, "--includes-json"],
                                capture_output=True, text=True)
        assert result.returncode != 0 and not result.stdout, repr(issuer)
        assert "CSP issuer/render error:" in result.stderr, repr(issuer)

    removed = {"forwarded", "x-forwarded-host", "x-forwarded-port", "x-forwarded-prefix", "x-forwarded-ssl"}
    for name in ("auth", "api", "app"):
        route = yaml.safe_load((ROOT / f"kubernetes/gateway/{name}-httproute.yaml").read_text())
        for rule in route["spec"]["rules"]:
            request = [f["requestHeaderModifier"] for f in rule["filters"] if f["type"] == "RequestHeaderModifier"]
            response = [f["responseHeaderModifier"] for f in rule["filters"] if f["type"] == "ResponseHeaderModifier"]
            assert len(request) == len(response) == 1, name
            assert {h.lower() for h in request[0]["remove"]} == removed, name
            assert response == [{"set": [{"name": "Strict-Transport-Security", "value": "max-age=31536000"}]}], name
            if name != "api":
                assert request[0]["set"] == [{"name": "X-Forwarded-Proto", "value": "https"}], name

    if len(sys.argv) > 1:
        resources = list(yaml.safe_load_all(Path(sys.argv[1]).read_text()))
        includes = next(r for r in resources if r.get("kind") == "ConfigMap"
                        and r["metadata"]["name"] == "nginx-gateway-includes")
        check_profiles(includes["data"], "https://auth.budgetanalyzer.org", 2)
    print("Edge header checks passed: all route rules, CSP profiles, issuer rejection and rendered sources")


if __name__ == "__main__":
    main()
