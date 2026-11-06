#!/usr/bin/env python3
"""Offline CSP rendering shared by Tilt and the production reference."""

import argparse
import ipaddress
import json
from pathlib import Path
import re
import sys
from urllib.parse import urlsplit


TOKEN = "__IDP_LOGOUT_ORIGIN__"
INCLUDES = Path(__file__).resolve().parents[3] / "nginx/includes"


def issuer_origin(issuer):
    """Accept an HTTPS issuer URL and return only its canonical CSP origin."""
    if not issuer or re.search(r"[\s\x00-\x20\x7f*\\\"'<>;]", issuer):
        raise ValueError("issuer must be a nonempty HTTPS URL without wildcards or unsafe characters")
    parsed = urlsplit(issuer)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or "?" in issuer or "#" in issuer):
        raise ValueError("issuer must be an HTTPS URL without credentials, query or fragment")
    if not re.fullmatch(r"(?:\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9.-]+)(?::[0-9]+)?", parsed.netloc):
        raise ValueError("issuer has a malformed HTTPS authority")
    host = parsed.hostname
    if "%" in host:
        raise ValueError("issuer hostname cannot contain percent escapes or IPv6 zone identifiers")
    if ":" in host:
        ipaddress.IPv6Address(host)
        host = f"[{host}]"
    elif (len(host) > 253 or not all(
            re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", label)
            for label in host.split("."))):
        raise ValueError("issuer has a malformed DNS hostname")
    port = parsed.port
    if parsed.netloc.endswith(":") or port == 0:
        raise ValueError("issuer has an invalid port")
    if not re.fullmatch(r"[-A-Za-z0-9._~!$&()+,=:@%/]*", parsed.path):
        raise ValueError("issuer has a malformed URL path")
    if re.search(r"%(?![0-9a-fA-F]{2})", parsed.path):
        raise ValueError("issuer has a malformed percent escape")
    return "https://" + host + (f":{port}" if port and port != 443 else "")


def render(source, origin):
    if TOKEN not in source:
        raise ValueError("CSP source has no IdP logout origin placeholder")
    return source.replace(TOKEN, origin)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--issuer", required=True)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--includes-json", action="store_true",
                      help="emit all NGINX includes as ConfigMap data for Tilt")
    mode.add_argument("--origin", action="store_true", help="print the validated origin only")
    args = parser.parse_args()
    try:
        origin = issuer_origin(args.issuer)
        if args.origin:
            print(origin)
        elif args.includes_json:
            data = {}
            for path in sorted(INCLUDES.glob("*.conf")):
                source = path.read_text()
                data[path.name] = render(source, origin) if path.name.startswith("security-headers-") else source
            print(json.dumps(data))
        else:
            # The production kustomize output uses literal block scalars for
            # these includes; validated origins contain no YAML metacharacters.
            sys.stdout.write(render(sys.stdin.read(), origin))
    except ValueError as exc:
        parser.exit(1, f"CSP issuer/render error: {exc}\n")


if __name__ == "__main__":
    main()
