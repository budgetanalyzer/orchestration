#!/bin/bash

# Binary, read-only go/no-go check for the reviewed personal-host VM boundary.
# Run on the Linux Mint host as root. The deployment constants are intentional.

set -uo pipefail

exec 3>&1
exec >/dev/null 2>&1

result=ERROR
finish() {
    # shellcheck disable=SC2317 # The function is invoked indirectly by the EXIT trap.
    printf '%s\n' "$result" >&3
}
trap finish EXIT
trap 'exit 1' HUP INT TERM

readonly VM_DOMAIN=budget-analyzer-agent
readonly VM_NETWORK=agent-nat
readonly VM_BRIDGE=virbr1
readonly VM_MAC=52:54:00:d9:c2:70
readonly VM_IPV4=192.168.231.10
readonly VM_GATEWAY=192.168.231.1
readonly POLICY_SERVICE=budget-agent-host-input.service
readonly POLICY_FILE=/etc/nftables.d/budget-agent-host-input.nft
readonly POLICY_LOADER=/usr/local/sbin/load-budget-agent-host-input
readonly POLICY_UNIT=/etc/systemd/system/budget-agent-host-input.service
readonly LIBVIRT_URI=qemu:///system

regular_root_file() {
    local path=$1
    local owner group mode

    [[ -f "$path" && ! -L "$path" ]] || return 1
    read -r owner group mode < <(stat -c '%U %G %a' "$path") || return 1
    [[ "$owner" == root && "$group" == root ]] || return 1
    (( (8#$mode & 0022) == 0 )) || return 1
}

unit_has_dependency() {
    local unit=$1
    local property=$2
    local dependencies

    dependencies=$(systemctl show "$unit" --property="$property" --value) || return 1
    [[ " $dependencies " == *" $POLICY_SERVICE "* ]]
}

persistent_drop_in_exists() {
    local unit=$1
    local drop_in

    for drop_in in "/etc/systemd/system/${unit}.d/"*.conf; do
        [[ -e "$drop_in" ]] || continue
        regular_root_file "$drop_in" || return 1
        if grep -Eq '^[[:space:]]*Requires=budget-agent-host-input\.service([[:space:]]|$)' "$drop_in" \
                && grep -Eq '^[[:space:]]*After=budget-agent-host-input\.service([[:space:]]|$)' "$drop_in"; then
            return 0
        fi
    done
    return 1
}

docker_unit_is_inert() {
    local unit=$1
    local active unit_state

    active=$(systemctl show "$unit" --property=ActiveState --value) || return 1
    unit_state=$(systemctl show "$unit" --property=UnitFileState --value) || return 1
    [[ "$active" != active && "$active" != activating ]] || return 1
    [[ "$unit_state" != enabled && "$unit_state" != enabled-runtime \
        && "$unit_state" != static && "$unit_state" != indirect ]]
}

check_domain_and_network() {
    local live_domain inactive_domain live_network inactive_network

    live_domain=$(virsh --connect "$LIBVIRT_URI" dumpxml "$VM_DOMAIN") || return 1
    inactive_domain=$(virsh --connect "$LIBVIRT_URI" dumpxml "$VM_DOMAIN" --inactive) || return 1
    live_network=$(virsh --connect "$LIBVIRT_URI" net-dumpxml "$VM_NETWORK") || return 1
    inactive_network=$(virsh --connect "$LIBVIRT_URI" net-dumpxml "$VM_NETWORK" --inactive) || return 1

    BA_LIVE_DOMAIN=$live_domain \
    BA_INACTIVE_DOMAIN=$inactive_domain \
    BA_LIVE_NETWORK=$live_network \
    BA_INACTIVE_NETWORK=$inactive_network \
    BA_VM_DOMAIN=$VM_DOMAIN \
    BA_VM_NETWORK=$VM_NETWORK \
    BA_VM_BRIDGE=$VM_BRIDGE \
    BA_VM_MAC=$VM_MAC \
    BA_VM_IPV4=$VM_IPV4 \
    BA_VM_GATEWAY=$VM_GATEWAY \
    BA_LIBVIRT_URI=$LIBVIRT_URI \
    python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


def fail():
    raise SystemExit(1)


def one(nodes):
    if len(nodes) != 1:
        fail()
    return nodes[0]


def domain_contract(text, live):
    root = ET.fromstring(text)
    if root.tag != 'domain' or root.get('type') != 'kvm':
        fail()

    labels = [node for node in root.findall('seclabel')
              if node.get('type') == 'dynamic' and node.get('model') == 'apparmor']
    label = one(labels).findtext('label') if live else None
    if live and not label:
        fail()

    devices = one(root.findall('devices'))
    forbidden = {'filesystem', 'hostdev', 'redirdev', 'smartcard', 'shmem', 'vsock'}
    if any(device.tag in forbidden for device in devices):
        fail()

    qemu_namespace = 'http://libvirt.org/schemas/domain/qemu/1.0'
    if any(node.tag.startswith('{' + qemu_namespace + '}') for node in root.iter()):
        fail()

    interfaces = devices.findall('interface')
    interface = one(interfaces)
    source = one(interface.findall('source'))
    mac = one(interface.findall('mac')).get('address', '').lower()
    if interface.get('type') != 'network' or source.get('network') != os.environ['BA_VM_NETWORK']:
        fail()
    if mac != os.environ['BA_VM_MAC']:
        fail()

    for channel in devices.findall('channel'):
        target = one(channel.findall('target'))
        if target.get('type') != 'virtio' or target.get('name') != 'org.qemu.guest_agent.0':
            fail()

    graphics_nodes = devices.findall('graphics')
    for graphics in graphics_nodes:
        if graphics.get('type') != 'vnc' or graphics.get('listen') != '127.0.0.1':
            fail()
        for listen in graphics.findall('listen'):
            if listen.get('type') != 'address' or listen.get('address') != '127.0.0.1':
                fail()

    target = interface.find('target')
    tap = target.get('dev') if live and target is not None else None
    if live and not tap:
        fail()
    return mac, tap, label


def network_contract(text):
    root = ET.fromstring(text)
    if root.tag != 'network' or root.findtext('name') != os.environ['BA_VM_NETWORK']:
        fail()
    bridge = one(root.findall('bridge'))
    forward = one(root.findall('forward'))
    if bridge.get('name') != os.environ['BA_VM_BRIDGE'] or forward.get('mode') != 'nat':
        fail()
    ipv4 = [node for node in root.findall('ip') if ':' not in node.get('address', '')]
    ip_node = one(ipv4)
    if ip_node.get('address') != os.environ['BA_VM_GATEWAY']:
        fail()
    if ip_node.get('prefix') != '24' and ip_node.get('netmask') != '255.255.255.0':
        fail()
    hosts = ip_node.findall('./dhcp/host')
    if not any(node.get('mac', '').lower() == os.environ['BA_VM_MAC']
               and node.get('ip') == os.environ['BA_VM_IPV4'] for node in hosts):
        fail()


live_mac, tap, security_label = domain_contract(os.environ['BA_LIVE_DOMAIN'], True)
inactive_mac, _, _ = domain_contract(os.environ['BA_INACTIVE_DOMAIN'], False)
if live_mac != inactive_mac:
    fail()
network_contract(os.environ['BA_LIVE_NETWORK'])
network_contract(os.environ['BA_INACTIVE_NETWORK'])

virsh = ['virsh', '--connect', os.environ['BA_LIBVIRT_URI']]
domains = subprocess.run(virsh + ['list', '--all', '--name'], check=True,
                         text=True, capture_output=True).stdout.splitlines()
attached = []
for domain in filter(None, map(str.strip, domains)):
    xml = subprocess.run(virsh + ['dumpxml', domain, '--inactive'], check=True,
                         text=True, capture_output=True).stdout
    root = ET.fromstring(xml)
    if any(source.get('network') == os.environ['BA_VM_NETWORK']
           for source in root.findall('./devices/interface/source')):
        attached.append(domain)
if attached != [os.environ['BA_VM_DOMAIN']]:
    fail()

bridge = os.environ['BA_VM_BRIDGE']
if not (Path('/sys/class/net') / bridge / 'bridge').is_dir():
    fail()
master = Path('/sys/class/net') / tap / 'master'
if not master.exists() or master.resolve().name != bridge:
    fail()

processes = []
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit():
        continue
    try:
        command = (proc / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace')
        current = (proc / 'attr/current').read_text().strip()
    except (FileNotFoundError, PermissionError, ProcessLookupError):
        continue
    if ('guest=' + os.environ['BA_VM_DOMAIN']) in command:
        processes.append((current, command))
if len(processes) != 1 or security_label not in processes[0][0] or 'unconfined' in processes[0][0]:
    fail()

print(tap)
PY
}

check_policy() {
    local live_rules

    live_rules=$(nft -a list table inet budget_agent_host_input) || return 1
    BA_LIVE_RULES=$live_rules BA_POLICY_FILE=$POLICY_FILE python3 - <<'PY'
import os
import re
from pathlib import Path


EXPECTED = [
    'iifname "virbr1" ether saddr != 52:54:00:d9:c2:70 counter drop',
    'iifname "virbr1" ct state established,related counter accept',
    ('iifname "virbr1" ether saddr 52:54:00:d9:c2:70 ip saddr 192.168.231.10 '
     'ip daddr 192.168.231.1 meta l4proto { tcp, udp } th dport 53 counter accept'),
    ('iifname "virbr1" ether saddr 52:54:00:d9:c2:70 ip saddr { 0.0.0.0, '
     '192.168.231.10 } ip daddr { 192.168.231.1, 255.255.255.255 } udp sport 68 '
     'udp dport 67 counter accept'),
    'iifname "virbr1" udp dport { 1900, 5353 } counter drop',
    'iifname "virbr1" counter drop',
]


def normalize(value):
    value = re.sub(r'\\\n[ \t]*', ' ', value)
    value = re.sub(r'[ \t]+', ' ', value.strip())
    value = re.sub(r'counter packets \d+ bytes \d+', 'counter', value)
    value = re.sub(r'\s+# handle \d+\s*$', '', value)
    return value


def extract(text, live):
    text = re.sub(r'\\\n[ \t]*', ' ', text)
    lines = [normalize(line) for line in text.splitlines()]
    table_lines = [line for line in lines if line.startswith('table ')]
    chain_lines = [line for line in lines if line.startswith('chain ')]
    if table_lines != ['table inet budget_agent_host_input {']:
        raise SystemExit(1)
    if chain_lines != ['chain early_vm_host_input {']:
        raise SystemExit(1)
    hooks = [line for line in lines if line.startswith('type filter hook input')]
    if len(hooks) != 1 or 'policy accept;' not in hooks[0]:
        raise SystemExit(1)
    if not re.search(r'priority (?:filter )?-\s*190;', hooks[0]):
        raise SystemExit(1)
    ignored = ('', '{', '}', 'table ', 'chain ', 'type filter hook input')
    rules = []
    for line in lines:
        if line in ('', '{', '}') or line.startswith(ignored[3:]):
            continue
        if not live and line.startswith('#'):
            continue
        rules.append(line)
    return rules


live = extract(os.environ['BA_LIVE_RULES'], True)
source = extract(Path(os.environ['BA_POLICY_FILE']).read_text(), False)
if live != EXPECTED or source != EXPECTED:
    raise SystemExit(1)
PY
}

check_no_docker_runtime() {
    local rules packages

    ! command -v docker || return 1
    [[ ! -S /run/docker.sock && ! -S /var/run/docker.sock ]] || return 1
    [[ ! -e /var/lib/docker && ! -e /sys/class/net/docker0 ]] || return 1
    [[ ! -e /usr/local/sbin/agent-vm-docker-isolation ]] || return 1
    [[ ! -e /etc/systemd/system/docker.service.d/agent-vm-isolation.conf ]] || return 1
    ! grep -Eq 'agent-vm-docker-isolation' /etc/ufw/after.init || return 1
    docker_unit_is_inert docker.service || return 1
    docker_unit_is_inert docker.socket || return 1

    packages=$(dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n') || return 1
    ! awk -F '\t' '
        BEGIN {
            split("docker-buildx docker-buildx-plugin docker-ce docker-ce-cli docker-ce-rootless-extras docker-cli docker-compose docker-compose-plugin docker-compose-v2 docker.io moby-buildx moby-cli moby-compose moby-engine", names)
            for (name in names) rejected[names[name]] = 1
        }
        {
            package = $1
            sub(/:[^:]+$/, "", package)
            if (length($2) > 1 && substr($2, 2, 1) == "i" && rejected[package]) found = 1
        }
        END { exit found ? 0 : 1 }
    ' <<<"$packages" || return 1

    rules=$(nft list ruleset) || return 1
    ! grep -Eiq '(^|[^[:alnum:]_])docker([^[:alnum:]_]|$)' <<<"$rules" || return 1
    for command_name in iptables-save ip6tables-save iptables-legacy-save ip6tables-legacy-save; do
        command -v "$command_name" >/dev/null 2>&1 || continue
        rules=$($command_name -c) || return 1
        ! grep -Eiq '(^|[^[:alnum:]_])docker([^[:alnum:]_]|$)' <<<"$rules" || return 1
    done
}

verify() {
    local command_name state line libvirt_unit tap
    local -a required_commands=(
        aa-status awk dpkg-query grep ip nft python3 sed sh stat systemctl
        systemd-detect-virt ufw virsh
    )
    local -a libvirt_units=(
        libvirt-guests.service
        libvirtd.service
        libvirtd-admin.socket
        libvirtd-ro.socket
        libvirtd-tcp.socket
        libvirtd-tls.socket
        libvirtd.socket
    )

    [[ $# -eq 0 && $EUID -eq 0 ]] || return 1
    for command_name in "${required_commands[@]}"; do
        command -v "$command_name" >/dev/null 2>&1 || return 1
    done
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091 # Standard operating-system identity file.
    source /etc/os-release
    [[ ${ID:-} == linuxmint ]] || return 1
    ! systemd-detect-virt --quiet || return 1
    aa-status | grep -Fq 'apparmor module is loaded' || return 1

    [[ $(virsh --connect "$LIBVIRT_URI" domstate "$VM_DOMAIN") == running ]] || return 1
    [[ $(virsh --connect "$LIBVIRT_URI" net-info "$VM_NETWORK" | awk '$1 == "Active:" {print $2}') == yes ]] || return 1
    [[ $(virsh --connect "$LIBVIRT_URI" net-info "$VM_NETWORK" | awk '$1 == "Autostart:" {print $2}') == yes ]] || return 1
    tap=$(check_domain_and_network) || return 1
    ip link show dev "$VM_BRIDGE" || return 1
    ip link show dev "$tap" || return 1
    ip -4 -o address show dev "$VM_BRIDGE" | grep -Eq "[[:space:]]${VM_GATEWAY}/24([[:space:]]|$)" || return 1
    virsh --connect "$LIBVIRT_URI" net-dhcp-leases "$VM_NETWORK" --mac "$VM_MAC" \
        | grep -Eq "[[:space:]]${VM_IPV4}/24([[:space:]]|$)" || return 1

    regular_root_file "$POLICY_FILE" || return 1
    regular_root_file "$POLICY_LOADER" || return 1
    regular_root_file "$POLICY_UNIT" || return 1
    sh -n "$POLICY_LOADER" || return 1
    "$POLICY_LOADER" --check-only || return 1
    [[ $(systemctl is-enabled "$POLICY_SERVICE") == enabled ]] || return 1
    [[ $(systemctl is-active "$POLICY_SERVICE") == active ]] || return 1
    systemctl show "$POLICY_SERVICE" --property=ExecStart --value | grep -Fq "$POLICY_LOADER" || return 1
    systemctl show "$POLICY_SERVICE" --property=ExecReload --value | grep -Fq "$POLICY_LOADER" || return 1
    line=$(systemctl show "$POLICY_SERVICE" --property=Before --value) || return 1
    [[ " $line " == *' ufw.service '* ]] || return 1
    check_policy || return 1
    [[ $(ufw status | sed -n '1s/^Status: //p') == active ]] || return 1

    for libvirt_unit in "${libvirt_units[@]}"; do
        state=$(systemctl show "$libvirt_unit" --property=LoadState --value) || return 1
        [[ "$state" == loaded ]] || return 1
        unit_has_dependency "$libvirt_unit" Requires || return 1
        unit_has_dependency "$libvirt_unit" After || return 1
        persistent_drop_in_exists "$libvirt_unit" || return 1
    done

    check_no_docker_runtime || return 1
}

if verify "$@"; then
    result=SUCCESS
    exit 0
fi
exit 1
