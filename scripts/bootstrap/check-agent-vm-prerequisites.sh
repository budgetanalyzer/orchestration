#!/bin/bash

# Read-only preflight for the explicit guest-local bootstrap path.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/local-docker-target.sh
# shellcheck disable=SC1091 # Resolved through SCRIPT_DIR at runtime.
. "$SCRIPT_DIR/../lib/local-docker-target.sh"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    fail "run this check from the development VM host, not an agent container"
fi

if [[ ! -r /etc/os-release ]]; then
    fail "cannot read /etc/os-release"
fi

# shellcheck disable=SC1091 # This is the standard Linux OS identity file.
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    fail "expected Ubuntu 24.04 LTS for the development VM"
fi

required_commands=(docker git openssl java node npm)
for command_name in "${required_commands[@]}"; do
    command -v "$command_name" >/dev/null 2>&1 \
        || fail "required command is missing: $command_name"
done

assert_local_docker_target || exit 1
docker compose version >/dev/null 2>&1 \
    || fail "Docker Compose v2 is required for the guest agent container"

java_major="$(java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1)"
[[ "$java_major" == "25" ]] || fail "JDK 25 is required; detected major '${java_major:-unknown}'"

node_major="$(node --version | sed -nE 's/^v([0-9]+).*/\1/p')"
[[ "$node_major" =~ ^[0-9]+$ && "$node_major" -ge 20 ]] \
    || fail "Node.js 20 or newer is required"

npm_major="$(npm --version | sed -nE 's/^([0-9]+).*/\1/p')"
[[ "$npm_major" =~ ^[0-9]+$ && "$npm_major" -ge 10 ]] \
    || fail "npm 10 or newer is required"

if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
    fail "SSH_AUTH_SOCK is set; do not forward a personal SSH agent into the guest"
fi

for token_variable in GITHUB_TOKEN GH_TOKEN GIT_ASKPASS SSH_ASKPASS; do
    if [[ -n "${!token_variable:-}" ]]; then
        fail "$token_variable is set; the development VM must not receive host GitHub authority"
    fi
done

if git config --global --get-all credential.helper 2>/dev/null | grep -q .; then
    fail "a global Git credential helper is configured in the development VM"
fi

printf 'Guest-local prerequisites pass: Ubuntu 24.04, local Docker/Compose, Git, OpenSSL, JDK 25, Node.js and npm.\n'
