#!/usr/bin/env bash
# Pinned tool versions and verified download metadata for Phase 7 Sessions 4 and 6.

PHASE7_KUBECTL_VERSION="v1.30.8"
PHASE7_HELM_VERSION="v3.20.1"
PHASE7_TILT_VERSION="0.37.0"
PHASE7_MKCERT_VERSION="v1.4.4"
PHASE7_KUBECONFORM_VERSION="v0.7.0"
PHASE7_KUBE_LINTER_VERSION="v0.8.3"
PHASE7_KYVERNO_CLI_VERSION="v1.17.1"

phase7_normalize_os() {
    local raw_os

    raw_os="${1:-$(uname -s)}"
    case "$raw_os" in
        Linux|linux)
            printf 'linux\n'
            ;;
        Darwin|darwin)
            printf 'darwin\n'
            ;;
        *)
            echo "Unsupported operating system: $raw_os" >&2
            return 1
            ;;
    esac
}

phase7_normalize_arch() {
    local raw_arch

    raw_arch="${1:-$(uname -m)}"
    case "$raw_arch" in
        x86_64|amd64)
            printf 'amd64\n'
            ;;
        arm64|aarch64)
            printf 'arm64\n'
            ;;
        *)
            echo "Unsupported CPU architecture: $raw_arch" >&2
            return 1
            ;;
    esac
}

phase7_platform_key() {
    local os
    local arch

    os="$(phase7_normalize_os "${1:-}")" || return 1
    arch="$(phase7_normalize_arch "${2:-}")" || return 1
    printf '%s-%s\n' "$os" "$arch"
}

phase7_sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
        return 0
    fi

    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
        return 0
    fi

    echo "Neither sha256sum nor shasum is available" >&2
    return 1
}

phase7_verify_sha256() {
    local file expected actual

    file="$1"
    expected="$2"
    actual="$(phase7_sha256_file "$file")" || return 1

    if [[ "$actual" != "$expected" ]]; then
        echo "Checksum mismatch for $file" >&2
        echo "Expected: $expected" >&2
        echo "Actual:   $actual" >&2
        return 1
    fi
}

phase7_tool_version() {
    case "$1" in
        kubectl)
            printf '%s\n' "$PHASE7_KUBECTL_VERSION"
            ;;
        helm)
            printf '%s\n' "$PHASE7_HELM_VERSION"
            ;;
        tilt)
            printf '%s\n' "$PHASE7_TILT_VERSION"
            ;;
        mkcert)
            printf '%s\n' "$PHASE7_MKCERT_VERSION"
            ;;
        kubeconform)
            printf '%s\n' "$PHASE7_KUBECONFORM_VERSION"
            ;;
        kube-linter)
            printf '%s\n' "$PHASE7_KUBE_LINTER_VERSION"
            ;;
        kyverno)
            printf '%s\n' "$PHASE7_KYVERNO_CLI_VERSION"
            ;;
        *)
            echo "Unsupported tool: $1" >&2
            return 1
            ;;
    esac
}

phase7_tool_url() {
    local tool platform os arch suffix

    tool="$1"
    platform="$2"
    os="${platform%-*}"
    arch="${platform#*-}"

    case "$tool" in
        kubectl)
            printf 'https://dl.k8s.io/release/%s/bin/%s/%s/kubectl\n' "$PHASE7_KUBECTL_VERSION" "$os" "$arch"
            ;;
        helm)
            printf 'https://get.helm.sh/helm-%s-%s-%s.tar.gz\n' "$PHASE7_HELM_VERSION" "$os" "$arch"
            ;;
        tilt)
            case "$platform" in
                linux-amd64) suffix='linux.x86_64' ;;
                linux-arm64) suffix='linux.arm64' ;;
                darwin-amd64) suffix='mac.x86_64' ;;
                darwin-arm64) suffix='mac.arm64' ;;
                *)
                    echo "Unsupported Tilt platform: $platform" >&2
                    return 1
                    ;;
            esac
            printf 'https://github.com/tilt-dev/tilt/releases/download/v%s/tilt.%s.%s.tar.gz\n' "$PHASE7_TILT_VERSION" "$PHASE7_TILT_VERSION" "$suffix"
            ;;
        mkcert)
            printf 'https://github.com/FiloSottile/mkcert/releases/download/%s/mkcert-%s-%s\n' "$PHASE7_MKCERT_VERSION" "$PHASE7_MKCERT_VERSION" "$platform"
            ;;
        kubeconform)
            printf 'https://github.com/yannh/kubeconform/releases/download/%s/kubeconform-%s.tar.gz\n' "$PHASE7_KUBECONFORM_VERSION" "$platform"
            ;;
        kube-linter)
            case "$platform" in
                linux-amd64) printf 'https://github.com/stackrox/kube-linter/releases/download/%s/kube-linter-linux.tar.gz\n' "$PHASE7_KUBE_LINTER_VERSION" ;;
                linux-arm64) printf 'https://github.com/stackrox/kube-linter/releases/download/%s/kube-linter-linux_arm64.tar.gz\n' "$PHASE7_KUBE_LINTER_VERSION" ;;
                darwin-amd64) printf 'https://github.com/stackrox/kube-linter/releases/download/%s/kube-linter-darwin.tar.gz\n' "$PHASE7_KUBE_LINTER_VERSION" ;;
                darwin-arm64) printf 'https://github.com/stackrox/kube-linter/releases/download/%s/kube-linter-darwin_arm64.tar.gz\n' "$PHASE7_KUBE_LINTER_VERSION" ;;
                *)
                    echo "Unsupported kube-linter platform: $platform" >&2
                    return 1
                    ;;
            esac
            ;;
        kyverno)
            case "$platform" in
                linux-amd64) suffix='linux_x86_64' ;;
                linux-arm64) suffix='linux_arm64' ;;
                darwin-amd64) suffix='darwin_x86_64' ;;
                darwin-arm64) suffix='darwin_arm64' ;;
                *)
                    echo "Unsupported kyverno platform: $platform" >&2
                    return 1
                    ;;
            esac
            printf 'https://github.com/kyverno/kyverno/releases/download/%s/kyverno-cli_%s_%s.tar.gz\n' "$PHASE7_KYVERNO_CLI_VERSION" "$PHASE7_KYVERNO_CLI_VERSION" "$suffix"
            ;;
        *)
            echo "Unsupported tool: $tool" >&2
            return 1
            ;;
    esac
}

phase7_tool_sha256() {
    case "$1:$2" in
        kubectl:linux-amd64) printf '7f39bdcf768ce4b8c1428894c70c49c8b4d2eee52f3606eb02f5f7d10f66d692\n' ;;
        kubectl:linux-arm64) printf 'e51d6a76fade0871a9143b64dc62a5ff44f369aa6cb4b04967d93798bf39d15b\n' ;;
        kubectl:darwin-amd64) printf '46682e24c3aecfbe92f53b86fb15beb740c43a0fafe0a4e06a1c8bb3ce9e985b\n' ;;
        kubectl:darwin-arm64) printf '52b11bb032f88e4718cd4e3c8374a6b1fad29772aa1ce701276cc4e17d37642f\n' ;;
        helm:linux-amd64) printf '0165ee4a2db012cc657381001e593e981f42aa5707acdd50658326790c9d0dc3\n' ;;
        helm:linux-arm64) printf '56b9d1b0e0efbb739be6e68a37860ace8ec9c7d3e6424e3b55d4c459bc3a0401\n' ;;
        helm:darwin-amd64) printf '580515b544d5c966edc6f782c9ae88e21a9e10c786a7d6c5fd4b52613f321076\n' ;;
        helm:darwin-arm64) printf '75cc96ac3fe8b8b9928eb051e55698e98d1e026967b6bffe4f0f3c538a551b65\n' ;;
        tilt:linux-amd64) printf 'c2c7d3649233f01bc5d230b66b8ccd332401f348dc22b863fcf7244da6970ff1\n' ;;
        tilt:linux-arm64) printf '84457137539d8e4be6e90e9afecf8ef692ad3f8c19e9bf3355f3fbf4f8dce55f\n' ;;
        tilt:darwin-amd64) printf '01c5e53921345ed4feb3ba6bc9585f8f5563e40bea27dae0384620d5bbc2ebea\n' ;;
        tilt:darwin-arm64) printf '5af70d3ab374adeaffe3fb8b0d7f1695a880dc2a02a4c2bccf20223b153929e8\n' ;;
        mkcert:linux-amd64) printf '6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52\n' ;;
        mkcert:linux-arm64) printf 'b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0\n' ;;
        mkcert:darwin-amd64) printf 'a32dfab51f1845d51e810db8e47dcf0e6b51ae3422426514bf5a2b8302e97d4e\n' ;;
        mkcert:darwin-arm64) printf 'c8af0df44bce04359794dad8ea28d750437411d632748049d08644ffb66a60c6\n' ;;
        kubeconform:linux-amd64) printf 'c31518ddd122663b3f3aa874cfe8178cb0988de944f29c74a0b9260920d115d3\n' ;;
        kubeconform:linux-arm64) printf 'cc907ccf9e3c34523f0f32b69745265e0a6908ca85b92f41931d4537860eb83c\n' ;;
        kubeconform:darwin-amd64) printf 'c6771cc894d82e1b12f35ee797dcda1f7da6a3787aa30902a15c264056dd40d4\n' ;;
        kubeconform:darwin-arm64) printf 'b5d32b2cb77f9c781c976b20a85e2d0bc8f9184d5d1cfe665a2f31a19f99eeb9\n' ;;
        kube-linter:linux-amd64) printf '1a6d8419b11971372971fdbc22682b684ebfb7cf1c39591662d1b6ca736c41df\n' ;;
        kube-linter:linux-arm64) printf '802e1b09eabd08f6f0a060a6b8ab2bf7bc7e6bf4f673bb2692303704c84b3e22\n' ;;
        kube-linter:darwin-amd64) printf 'c62e8af3c9df2557c7a3922119ea1b35597794737d1ccad493f63a0d66e7b8fc\n' ;;
        kube-linter:darwin-arm64) printf '6e3443a8ff8625a9fc31a38682c783988d7559018f7ff707a4f8c77c18c92f14\n' ;;
        kyverno:linux-amd64) printf 'd0c0f52e8fc8d66a3663b63942b131e5f91b63f7644b3e446546f79142d1b7a3\n' ;;
        kyverno:linux-arm64) printf '6f6a66711ba8fc2bd54a28aa1755a62605d053a6a3a758186201ba1f56698ced\n' ;;
        kyverno:darwin-amd64) printf 'd221d8d93c622b68a2933f4e0accd61db4f41100336f1ddad141259742f70948\n' ;;
        kyverno:darwin-arm64) printf '851d1fcc4427a317674cc1892af4f43dcd19983c94498a1a913b6b849f71ef8c\n' ;;
        *)
            echo "Unsupported checksum lookup: $1 on $2" >&2
            return 1
            ;;
    esac
}

phase7_install_hint() {
    local tool repo_root installer_path

    tool="$1"
    repo_root="${2:-.}"
    installer_path="${repo_root%/}/scripts/bootstrap/install-verified-tool.sh"

    case "$tool" in
        mkcert)
            printf 'sudo apt-get install -y libnss3-tools && "%s" mkcert\n' "$installer_path"
            ;;
        kubectl|helm|tilt)
            printf '"%s" %s\n' "$installer_path" "$tool"
            ;;
        kubeconform|kube-linter|kyverno)
            printf '"%s" %s\n' "$installer_path" "$tool"
            ;;
        *)
            echo "Unsupported tool hint: $tool" >&2
            return 1
            ;;
    esac
}
