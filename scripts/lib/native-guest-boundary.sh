#!/bin/bash

# Shared fail-closed checks for commands that must run as a native process in
# the development VM without personal-host credential forwarding. Source this
# file; do not execute it directly.

assert_native_guest_process() {
    local filesystem_root="${1:-/}" container_type vm_type

    if [[ -f "${filesystem_root%/}/.dockerenv" \
        || -f "${filesystem_root%/}/run/.containerenv" ]]; then
        printf 'ERROR: run this check as a native development VM process, not in a container.\n' >&2
        return 1
    fi

    # A synthetic root is used only by the tracked marker fixtures. Production
    # callers use the default root and must also prove native QEMU/KVM identity.
    if [[ "$filesystem_root" == "/" ]]; then
        if ! command -v systemd-detect-virt >/dev/null 2>&1; then
            printf 'ERROR: systemd-detect-virt is required for native VM identity.\n' >&2
            return 1
        fi

        if container_type="$(systemd-detect-virt --container 2>/dev/null)"; then
            printf 'ERROR: container execution detected: %s\n' \
                "${container_type:-unknown}" >&2
            return 1
        fi
        if [[ "$container_type" != "none" ]]; then
            printf 'ERROR: unable to prove non-container execution.\n' >&2
            return 1
        fi

        vm_type="$(systemd-detect-virt --vm 2>/dev/null || true)"
        case "$vm_type" in
            kvm|qemu) ;;
            *)
                printf 'ERROR: expected native QEMU/KVM execution; detected %s.\n' \
                    "${vm_type:-none}" >&2
                return 1
                ;;
        esac
    fi

    return 0
}

assert_no_forwarded_host_authority() {
    local credential_variable

    for credential_variable in \
        SSH_AUTH_SOCK GPG_AGENT_INFO GITHUB_TOKEN GH_TOKEN GIT_ASKPASS SSH_ASKPASS; do
        if [[ -n "${!credential_variable:-}" ]]; then
            printf 'ERROR: %s is set; the development VM must not receive personal-host authority.\n' \
                "$credential_variable" >&2
            return 1
        fi
    done

    if git config --global --get-all credential.helper 2>/dev/null | grep -q .; then
        printf 'ERROR: a global Git credential helper is configured in the development VM.\n' >&2
        return 1
    fi

    return 0
}
