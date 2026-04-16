#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=deploy/scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

phase4_load_instance_env
phase4_require_commands kubectl sudo iptables apt-get
phase4_require_cluster_access

ingress_service_name="$(phase4_ingress_service_name)"
[[ -n "${ingress_service_name}" ]] || phase4_die "could not find the auto-provisioned ingress Service in namespace ${PHASE4_INGRESS_GATEWAY_NAMESPACE}"

http_node_port="$(phase4_find_service_nodeport "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" "${ingress_service_name}" 80)"
https_node_port="$(phase4_find_service_nodeport "${PHASE4_INGRESS_GATEWAY_NAMESPACE}" "${ingress_service_name}" 443)"

phase4_info "ingress Service ${ingress_service_name} nodePorts: http=${http_node_port:-unset} https=${https_node_port:-unset}"

if ! command -v netfilter-persistent >/dev/null 2>&1; then
    phase4_info "installing iptables-persistent so redirects survive reboot"
    phase4_run_sudo env DEBIAN_FRONTEND=noninteractive apt-get update
    phase4_run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
fi

if [[ -n "${http_node_port}" ]]; then
    phase4_add_nat_redirect 80 "${http_node_port}"
else
    phase4_remove_nat_redirects 80
    phase4_warn "no ingress nodePort 80 exists yet; removed any stale port 80 redirect"
fi

if [[ -n "${https_node_port}" ]]; then
    phase4_add_nat_redirect 443 "${https_node_port}"
else
    phase4_remove_nat_redirects 443
    phase4_warn "no ingress nodePort 443 exists yet; removed any stale port 443 redirect. Phase 4 is expected to stay HTTP-only until Phase 11 wires the TLS listener"
fi

phase4_run_sudo netfilter-persistent save >/dev/null
phase4_info "saved host redirect rules via netfilter-persistent"
