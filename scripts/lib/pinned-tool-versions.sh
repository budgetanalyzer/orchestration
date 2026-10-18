#!/usr/bin/env bash
# Pinned tool versions and verified download metadata for security guardrail tooling.

# renovate: datasource=github-releases depName=kubernetes/kubernetes
PHASE7_KUBECTL_VERSION="v1.35.9"
# renovate: datasource=github-releases depName=helm/helm
PHASE7_HELM_VERSION="v3.22.1"
# renovate: datasource=github-releases depName=tilt-dev/tilt extractVersion=^v(?<version>.*)$
PHASE7_TILT_VERSION="0.37.8"
# renovate: datasource=github-releases depName=FiloSottile/mkcert
PHASE7_MKCERT_VERSION="v1.4.4"
# renovate: datasource=github-releases depName=kubernetes-sigs/kind
PHASE7_KIND_VERSION="v0.33.0"
# renovate: datasource=github-releases depName=yannh/kubeconform
PHASE7_KUBECONFORM_VERSION="v0.8.0"
# renovate: datasource=github-releases depName=stackrox/kube-linter
PHASE7_KUBE_LINTER_VERSION="v0.8.3"
# renovate: datasource=github-releases depName=kyverno/kyverno extractVersion=^kyverno-cli-(?<version>v.*)$
PHASE7_KYVERNO_CLI_VERSION="v1.18.0"
# renovate: datasource=github-releases depName=mikefarah/yq
PHASE7_YQ_VERSION="v4.54.1"
# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
PHASE7_GATEWAY_API_VERSION="v1.5.1"
# renovate: datasource=github-releases depName=projectcalico/calico
PHASE7_CALICO_VERSION="v3.33.0"

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
        kind)
            printf '%s\n' "$PHASE7_KIND_VERSION"
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
        yq)
            printf '%s\n' "$PHASE7_YQ_VERSION"
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
        kind)
            printf 'https://github.com/kubernetes-sigs/kind/releases/download/%s/kind-%s-%s\n' "$PHASE7_KIND_VERSION" "$os" "$arch"
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
        yq)
            case "$platform" in
                linux-amd64) suffix='linux_amd64' ;;
                linux-arm64) suffix='linux_arm64' ;;
                darwin-amd64) suffix='darwin_amd64' ;;
                darwin-arm64) suffix='darwin_arm64' ;;
                *)
                    echo "Unsupported yq platform: $platform" >&2
                    return 1
                    ;;
            esac
            printf 'https://github.com/mikefarah/yq/releases/download/%s/yq_%s\n' "$PHASE7_YQ_VERSION" "$suffix"
            ;;
        *)
            echo "Unsupported tool: $tool" >&2
            return 1
            ;;
    esac
}

phase7_tool_sha256() {
    case "$1:$2" in
        kubectl:linux-amd64) printf '3cfeaf80be482b435b0aa214aff6e0b2c312ee23c0ff20810c75517b6004c6eb\n' ;;
        kubectl:linux-arm64) printf '39c98bca82875d9a9ddfb6f3c5ab17c3f78ea0801230683e538a67d5c053308d\n' ;;
        kubectl:darwin-amd64) printf '51a130a5ea965314a41d27e840e96a7f4e4c13c508ab5fa0fd101ee4c1829990\n' ;;
        kubectl:darwin-arm64) printf '652548e6a9405266c5acd2719703bc8d36befa46e79e151a0d646904aa32c89b\n' ;;
        helm:linux-amd64) printf '896cf63684a42a723d61c980369d6e588330927deb13676ca0d85006dd6da0ea\n' ;;
        helm:linux-arm64) printf '4c29e286b279d170fa048ddfc3e4e83dcd069ca9c52102766ba672d7149e694d\n' ;;
        helm:darwin-amd64) printf 'cf850a81b908f8eef0331e6b18776da2767bcac639ca84472311dad20008495c\n' ;;
        helm:darwin-arm64) printf 'e73da8a0b0d5193774fdff17ce6319c7436bb22ee229b45fd64f3c40368c753a\n' ;;
        tilt:linux-amd64) printf 'e39513f958705d30524d55f68b1d46fbef2b46a0da568efd00e6383dee6be44f\n' ;;
        tilt:linux-arm64) printf '7a21281e830930be158202b7f8405ba62445613788b4d9708512ffe51f5cce90\n' ;;
        tilt:darwin-amd64) printf '0d03359e43f7faea07a6ed0e7423bb56176d1959462fa155329e9acabf90e6fa\n' ;;
        tilt:darwin-arm64) printf '2d396b13c479f74deb19cb2161a3f0858f6e03f26f15f8d3b3be982d09ff4484\n' ;;
        mkcert:linux-amd64) printf '6d31c65b03972c6dc4a14ab429f2928300518b26503f58723e532d1b0a3bbb52\n' ;;
        mkcert:linux-arm64) printf 'b98f2cc69fd9147fe4d405d859c57504571adec0d3611c3eefd04107c7ac00d0\n' ;;
        mkcert:darwin-amd64) printf 'a32dfab51f1845d51e810db8e47dcf0e6b51ae3422426514bf5a2b8302e97d4e\n' ;;
        mkcert:darwin-arm64) printf 'c8af0df44bce04359794dad8ea28d750437411d632748049d08644ffb66a60c6\n' ;;
        kind:linux-amd64) printf 'aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d\n' ;;
        kind:linux-arm64) printf '20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2\n' ;;
        kind:darwin-amd64) printf '5a99f26f57246dc9319dd294803313197a0f34d33c525b3ea8b655db5916ece0\n' ;;
        kind:darwin-arm64) printf '0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f\n' ;;
        kubeconform:linux-amd64) printf '9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883\n' ;;
        kubeconform:linux-arm64) printf '1f53fc8e81258197a35e8603054162a5af1de8c5af13746c71ab680d9534ed87\n' ;;
        kubeconform:darwin-amd64) printf '71dbc87ac9f24099a62b93570e65aa06312ba6ac8aea63b7f86e9d999edf5a92\n' ;;
        kubeconform:darwin-arm64) printf 'f84f4dfbebf4a6b0b230385fa065a39ea35e02608c2b50d025dcf64775a69d67\n' ;;
        kube-linter:linux-amd64) printf '1a6d8419b11971372971fdbc22682b684ebfb7cf1c39591662d1b6ca736c41df\n' ;;
        kube-linter:linux-arm64) printf '802e1b09eabd08f6f0a060a6b8ab2bf7bc7e6bf4f673bb2692303704c84b3e22\n' ;;
        kube-linter:darwin-amd64) printf 'c62e8af3c9df2557c7a3922119ea1b35597794737d1ccad493f63a0d66e7b8fc\n' ;;
        kube-linter:darwin-arm64) printf '6e3443a8ff8625a9fc31a38682c783988d7559018f7ff707a4f8c77c18c92f14\n' ;;
        kyverno:linux-amd64) printf '3aa7b7aa68732fd6bc5732f1030d0ed12e1b0ffe7dbac5f5aa21fd8695718904\n' ;;
        kyverno:linux-arm64) printf '37697771e1cc92daf73bebde4eb304691af09e07a4278cc82062e829c8475cec\n' ;;
        kyverno:darwin-amd64) printf '35f4884e98e32e87223f1591e4ca0f82f9136f1cc9e9ba6482c441fdb00611d5\n' ;;
        kyverno:darwin-arm64) printf '9b3d02f999c2b12e315b70b8d5b2db569b08e16f70449a23991515ed390e9268\n' ;;
        yq:linux-amd64) printf '8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f\n' ;;
        yq:linux-arm64) printf '189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b\n' ;;
        yq:darwin-amd64) printf '3a812fce205a4d67014fb71b7fa297092210e580df3d8f52dddc2cf3a599c22b\n' ;;
        yq:darwin-arm64) printf 'fee511a181bd8b3e6b7da98842b41973bfac8cd3bcd341ed29a584620b5b2844\n' ;;
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
        kubectl|helm|tilt|kind|yq)
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

phase7_gateway_api_manifest_url() {
    printf 'https://github.com/kubernetes-sigs/gateway-api/releases/download/%s/standard-install.yaml\n' "$PHASE7_GATEWAY_API_VERSION"
}

phase7_calico_manifest_url() {
    printf 'https://raw.githubusercontent.com/projectcalico/calico/%s/manifests/calico.yaml\n' "$PHASE7_CALICO_VERSION"
}
