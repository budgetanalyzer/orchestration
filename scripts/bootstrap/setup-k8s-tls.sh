#!/bin/bash

# Backward-compatible human entry point for initial personal-host certificate
# preparation. Browser-facing certificate generation stays on the personal
# host, but Kubernetes now exists only in the development VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf '%s\n' \
    'Preparing personal-host browser trust and transferable ingress files.' \
    'This command does not access or create a Kind cluster.'

exec "$SCRIPT_DIR/renew-host-ingress-tls.sh"
