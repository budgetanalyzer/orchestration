# Host isolation audit candidate
Collection time UTC: 2026-10-06T05:41:25.631248+00:00
NOT A SECURITY PASS. Review privately before sharing. Local addresses,
unselected interface names, chain/set names and process names are retained.
Raw evidence and XML remain on the personal host. No active probes ran.

## domain-live
exit=0; optional=False
```text
{
  "domain_type": "kvm",
  "security_labels": [
    {
      "type": "dynamic",
      "model": "apparmor",
      "relabel": "yes"
    },
    {
      "type": "dynamic",
      "model": "dac",
      "relabel": "yes"
    }
  ],
  "security_label_text_present": true,
  "custom_namespace_elements": [
    "{http://libosinfo.org/xmlns/libvirt/domain/1.0}libosinfo",
    "{http://libosinfo.org/xmlns/libvirt/domain/1.0}os"
  ],
  "devices": [
    {
      "kind": "disk",
      "attributes": {
        "type": "file",
        "device": "disk"
      },
      "children": [
        {
          "kind": "driver",
          "attributes": {
            "name": "qemu",
            "type": "qcow2"
          }
        },
        {
          "kind": "source",
          "attributes": {
            "file": "HOST_PATH_PRESENT",
            "index": "2"
          }
        },
        {
          "kind": "backingStore",
          "attributes": {}
        },
        {
          "kind": "target",
          "attributes": {
            "dev": "HOST_PATH_PRESENT",
            "bus": "virtio"
          }
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "virtio-disk0"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x04",
            "slot": "0x00",
            "function": "0x0"
          }
        }
      ]
    },
    {
      "kind": "disk",
      "attributes": {
        "type": "file",
        "device": "cdrom"
      },
      "children": [
        {
          "kind": "driver",
          "attributes": {
            "name": "qemu"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "dev": "HOST_PATH_PRESENT",
            "bus": "sata"
          }
        },
        {
          "kind": "readonly",
          "attributes": {}
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "sata0-0-0"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "drive",
            "controller": "0",
            "bus": "0",
            "target": "0",
            "unit": "0"
          }
        }
      ]
    },
    {
      "kind": "interface",
      "attributes": {
        "type": "network"
      },
      "children": [
        {
          "kind": "mac",
          "attributes": {
            "address": "REDACTED_MAC"
          }
        },
        {
          "kind": "source",
          "attributes": {
            "network": "NETWORK_1",
            "portid": "UUID_1",
            "bridge": "virbr1"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "dev": "HOST_PATH_PRESENT"
          }
        },
        {
          "kind": "model",
          "attributes": {
            "type": "virtio"
          }
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "net0"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x01",
            "slot": "0x00",
            "function": "0x0"
          }
        }
      ]
    },
    {
      "kind": "serial",
      "attributes": {
        "type": "pty"
      },
      "children": [
        {
          "kind": "source",
          "attributes": {
            "path": "HOST_PATH_PRESENT"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "type": "isa-serial",
            "port": "0"
          }
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "serial0"
          }
        }
      ]
    },
    {
      "kind": "console",
      "attributes": {
        "type": "pty",
        "tty": "/dev/pts/0"
      },
      "children": [
        {
          "kind": "source",
          "attributes": {
            "path": "HOST_PATH_PRESENT"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "type": "serial",
            "port": "0"
          }
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "serial0"
          }
        }
      ]
    },
    {
      "kind": "channel",
      "attributes": {
        "type": "unix"
      },
      "children": [
        {
          "kind": "source",
          "attributes": {
            "mode": "bind",
            "path": "HOST_PATH_PRESENT"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "type": "virtio",
            "name": "org.qemu.guest_agent.0",
            "state": "disconnected"
          }
        },
        {
          "kind": "alias",
          "attributes": {
            "name": "channel0"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "virtio-serial",
            "controller": "0",
            "bus": "0",
            "port": "1"
          }
        }
      ]
    },
    {
      "kind": "graphics",
      "attributes": {
        "type": "vnc",
        "port": "5900",
        "autoport": "yes",
        "listen": "127.0.0.1"
      },
      "children": [
        {
          "kind": "listen",
          "attributes": {
            "type": "address",
            "address": "127.0.0.1"
          }
        }
      ]
    }
  ]
}
```

## domain-persistent
exit=0; optional=False
```text
{
  "domain_type": "kvm",
  "security_labels": [],
  "security_label_text_present": false,
  "custom_namespace_elements": [
    "{http://libosinfo.org/xmlns/libvirt/domain/1.0}libosinfo",
    "{http://libosinfo.org/xmlns/libvirt/domain/1.0}os"
  ],
  "devices": [
    {
      "kind": "disk",
      "attributes": {
        "type": "file",
        "device": "disk"
      },
      "children": [
        {
          "kind": "driver",
          "attributes": {
            "name": "qemu",
            "type": "qcow2"
          }
        },
        {
          "kind": "source",
          "attributes": {
            "file": "HOST_PATH_PRESENT"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "dev": "HOST_PATH_PRESENT",
            "bus": "virtio"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x04",
            "slot": "0x00",
            "function": "0x0"
          }
        }
      ]
    },
    {
      "kind": "disk",
      "attributes": {
        "type": "file",
        "device": "cdrom"
      },
      "children": [
        {
          "kind": "driver",
          "attributes": {
            "name": "qemu",
            "type": "raw"
          }
        },
        {
          "kind": "target",
          "attributes": {
            "dev": "HOST_PATH_PRESENT",
            "bus": "sata"
          }
        },
        {
          "kind": "readonly",
          "attributes": {}
        },
        {
          "kind": "address",
          "attributes": {
            "type": "drive",
            "controller": "0",
            "bus": "0",
            "target": "0",
            "unit": "0"
          }
        }
      ]
    },
    {
      "kind": "interface",
      "attributes": {
        "type": "network"
      },
      "children": [
        {
          "kind": "mac",
          "attributes": {
            "address": "REDACTED_MAC"
          }
        },
        {
          "kind": "source",
          "attributes": {
            "network": "NETWORK_1"
          }
        },
        {
          "kind": "model",
          "attributes": {
            "type": "virtio"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "pci",
            "domain": "0x0000",
            "bus": "0x01",
            "slot": "0x00",
            "function": "0x0"
          }
        }
      ]
    },
    {
      "kind": "serial",
      "attributes": {
        "type": "pty"
      },
      "children": [
        {
          "kind": "target",
          "attributes": {
            "type": "isa-serial",
            "port": "0"
          }
        }
      ]
    },
    {
      "kind": "console",
      "attributes": {
        "type": "pty"
      },
      "children": [
        {
          "kind": "target",
          "attributes": {
            "type": "serial",
            "port": "0"
          }
        }
      ]
    },
    {
      "kind": "channel",
      "attributes": {
        "type": "unix"
      },
      "children": [
        {
          "kind": "target",
          "attributes": {
            "type": "virtio",
            "name": "org.qemu.guest_agent.0"
          }
        },
        {
          "kind": "address",
          "attributes": {
            "type": "virtio-serial",
            "controller": "0",
            "bus": "0",
            "port": "1"
          }
        }
      ]
    },
    {
      "kind": "graphics",
      "attributes": {
        "type": "vnc",
        "port": "-1",
        "autoport": "yes",
        "listen": "127.0.0.1"
      },
      "children": [
        {
          "kind": "listen",
          "attributes": {
            "type": "address",
            "address": "127.0.0.1"
          }
        }
      ]
    }
  ]
}
```

## network-live
exit=0; optional=False
```text
<network connections="1">
  <forward mode="nat">
    <nat>
      <port start="1024" end="65535" />
    </nat>
  </forward>
  <bridge name="BRIDGE_1" stp="on" delay="0" />
  <domain name="REDACTED" />
  <ip address="192.168.231.1" netmask="IP4_1">
    <dhcp>
      <range start="192.168.231.128" end="192.168.231.254" />
      <host mac="REDACTED" name="REDACTED" ip="192.168.231.10" />
    </dhcp>
  </ip>
</network>
```

## network-persistent
exit=0; optional=False
```text
<network>
  <forward mode="nat" />
  <bridge name="BRIDGE_1" stp="on" delay="0" />
  <domain name="REDACTED" />
  <ip address="192.168.231.1" netmask="IP4_1">
    <dhcp>
      <range start="192.168.231.128" end="192.168.231.254" />
      <host mac="REDACTED" name="REDACTED" ip="192.168.231.10" />
    </dhcp>
  </ip>
</network>
```

## ufw-status
exit=0; optional=False
```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
67/udp on BRIDGE_1           ALLOW IN    68/udp                     # agent VM DHCP
192.168.231.1 53/udp on BRIDGE_1 ALLOW IN    Anywhere                   # agent VM DNS UDP
192.168.231.1 53/tcp on BRIDGE_1 ALLOW IN    Anywhere                   # agent VM DNS TCP
Anywhere on BRIDGE_1         DENY IN     Anywhere                   # deny agent VM to host
Anywhere (v6) on BRIDGE_1    DENY IN     Anywhere (v6)              # deny agent VM to host
```

## ufw-numbered
exit=0; optional=False
```text
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 67/udp on BRIDGE_1           ALLOW IN    68/udp                     # agent VM DHCP
[ 2] 192.168.231.1 53/udp on BRIDGE_1 ALLOW IN    Anywhere                   # agent VM DNS UDP
[ 3] 192.168.231.1 53/tcp on BRIDGE_1 ALLOW IN    Anywhere                   # agent VM DNS TCP
[ 4] Anywhere on BRIDGE_1         DENY IN     Anywhere                   # deny agent VM to host
[ 5] Anywhere (v6) on BRIDGE_1    DENY IN     Anywhere (v6)              # deny agent VM to host
```

## ufw-effective
exit=0; optional=False
```text
IPV4 (raw):
Chain INPUT (policy DROP 170 packets, 7318 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  233265 315746868 LIBVIRT_INP  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  232647 315692480 ufw-before-logging-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  232647 315692480 ufw-before-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     373    55425 ufw-after-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     245    12854 ufw-after-logging-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     245    12854 ufw-reject-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     245    12854 ufw-track-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain FORWARD (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  140569 199978730 LIBVIRT_FWX  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  140569 199978730 LIBVIRT_FWI  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
   66803 13987571 LIBVIRT_FWO  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-before-logging-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-before-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-after-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-after-logging-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-reject-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-track-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain OUTPUT (policy ACCEPT 16 packets, 680 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  148660 24680827 LIBVIRT_OUT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  148746 24686764 ufw-before-logging-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  148746 24686764 ufw-before-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    1932   442992 ufw-after-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    1932   442992 ufw-after-logging-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    1932   442992 ufw-reject-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    1932   442992 ufw-track-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_FWI (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      virbr0  0.0.0.0/0            192.168.122.0/24     ctstate RELATED,ESTABLISHED
       0        0 REJECT     0    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
   73766 185991159 ACCEPT     0    --  *      BRIDGE_1  0.0.0.0/0            192.168.231.0/24     ctstate RELATED,ESTABLISHED
       0        0 REJECT     0    --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable

Chain LIBVIRT_FWO (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  virbr0 *       192.168.122.0/24     0.0.0.0/0           
       0        0 REJECT     0    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
   66795 13987091 ACCEPT     0    --  BRIDGE_1 *       192.168.231.0/24     0.0.0.0/0           
       8      480 REJECT     0    --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable

Chain LIBVIRT_FWX (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  virbr0 virbr0  0.0.0.0/0            0.0.0.0/0           
       0        0 ACCEPT     0    --  BRIDGE_1 BRIDGE_1  0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_INP (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     17   --  virbr0 *       0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       0        0 ACCEPT     17   --  virbr0 *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ACCEPT     6    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:67
     702    60291 ACCEPT     17   --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       3     1016 ACCEPT     17   --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ACCEPT     6    --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:67

Chain LIBVIRT_OUT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       0        0 ACCEPT     17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:68
       0        0 ACCEPT     6    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            tcp dpt:68
       0        0 ACCEPT     17   --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       3     1062 ACCEPT     17   --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            udp dpt:68
       0        0 ACCEPT     6    --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            tcp dpt:68

Chain ufw-after-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-after-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:137
      10     2395 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:138
       0        0 ufw-skip-to-policy-input  6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:139
       0        0 ufw-skip-to-policy-input  6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:445
       0        0 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:68
     118    40176 ufw-skip-to-policy-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type BROADCAST

Chain ufw-after-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw-after-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
     170     7318 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw-after-logging-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-after-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 3
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 11
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 12
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 8
       0        0 ufw-user-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-before-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
   17502  6485120 ACCEPT     0    --  lo     *       0.0.0.0/0            0.0.0.0/0           
  214654 309139876 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
       0        0 ufw-logging-deny  0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
       0        0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 3
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 11
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 12
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 8
       0        0 ACCEPT     17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp spt:67 dpt:68
     416    61948 ufw-not-local  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     116    10789 ACCEPT     17   --  *      *       0.0.0.0/0            224.0.0.251          udp dpt:5353
       0        0 ACCEPT     17   --  *      *       0.0.0.0/0            239.255.255.250      udp dpt:1900
     300    51159 ufw-user-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-before-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-logging-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
   17503  6485112 ACCEPT     0    --  *      lo      0.0.0.0/0            0.0.0.0/0           
  129311 17758660 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
    1856   437368 ufw-user-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-logging-allow (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW ALLOW] "

Chain ufw-logging-deny (2 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID limit: avg 3/min burst 10
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw-not-local (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
     288    19377 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type MULTICAST
     128    42571 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type BROADCAST
       0        0 ufw-logging-deny  0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10
       0        0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-reject-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-reject-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-reject-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-skip-to-policy-forward (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-skip-to-policy-input (7 references)
    pkts      bytes target     prot opt in     out     source               destination         
     128    42571 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-skip-to-policy-output (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-track-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-track-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-track-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
     348    20880 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate NEW
    1530   418088 ACCEPT     17   --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate NEW

Chain ufw-user-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-user-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     17   --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0            udp spt:68 dpt:67
       0        0 ACCEPT     17   --  BRIDGE_1 *       0.0.0.0/0            192.168.231.1        udp dpt:53
       0        0 ACCEPT     6    --  BRIDGE_1 *       0.0.0.0/0            192.168.231.1        tcp dpt:53
       2     1270 DROP       0    --  BRIDGE_1 *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-user-limit (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 5 LOG flags 0 level 4 prefix "[UFW LIMIT BLOCK] "
       0        0 REJECT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable

Chain ufw-user-limit-accept (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-user-logging-forward (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-user-logging-input (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-user-logging-output (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-user-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain POSTROUTING (policy ACCEPT 2955 packets, 516039 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
    3278   537847 LIBVIRT_PRT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       8      559 RETURN     0    --  *      *       192.168.122.0/24     224.0.0.0/24        
       0        0 RETURN     0    --  *      *       192.168.122.0/24     IP4_2     
       0        0 MASQUERADE  6    --  *      *       192.168.122.0/24    !192.168.122.0/24     masq ports: 1024-65535
       2     1270 MASQUERADE  17   --  *      *       192.168.122.0/24    !192.168.122.0/24     masq ports: 1024-65535
       0        0 MASQUERADE  0    --  *      *       192.168.122.0/24    !192.168.122.0/24    
       8      559 RETURN     0    --  *      *       192.168.231.0/24     224.0.0.0/24        
       0        0 RETURN     0    --  *      *       192.168.231.0/24     IP4_2     
     311    18660 MASQUERADE  6    --  *      *       192.168.231.0/24    !192.168.231.0/24     masq ports: 1024-65535
      10     1878 MASQUERADE  17   --  *      *       192.168.231.0/24    !192.168.231.0/24     masq ports: 1024-65535
       0        0 MASQUERADE  0    --  *      *       192.168.231.0/24    !192.168.231.0/24    
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain POSTROUTING (policy ACCEPT 289279 packets, 224666999 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  289279 224666999 LIBVIRT_PRT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 CHECKSUM   17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:68 CHECKSUM fill
       3     1062 CHECKSUM   17   --  *      BRIDGE_1  0.0.0.0/0            0.0.0.0/0            udp dpt:68 CHECKSUM fill
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         


IPV6:
Chain INPUT (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
     126    13792 LIBVIRT_INP  0    --  *      *       ::/0                 ::/0                
     128    13944 ufw6-before-logging-input  0    --  *      *       ::/0                 ::/0                
     128    13944 ufw6-before-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-logging-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-reject-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-track-input  0    --  *      *       ::/0                 ::/0                

Chain FORWARD (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LIBVIRT_FWX  0    --  *      *       ::/0                 ::/0                
       0        0 LIBVIRT_FWI  0    --  *      *       ::/0                 ::/0                
       0        0 LIBVIRT_FWO  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-before-logging-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-before-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-logging-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-reject-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-track-forward  0    --  *      *       ::/0                 ::/0                

Chain OUTPUT (policy ACCEPT 4 packets, 344 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
      64     5762 LIBVIRT_OUT  0    --  *      *       ::/0                 ::/0                
      66     5914 ufw6-before-logging-output  0    --  *      *       ::/0                 ::/0                
      66     5914 ufw6-before-output  0    --  *      *       ::/0                 ::/0                
      34     3922 ufw6-after-output  0    --  *      *       ::/0                 ::/0                
      34     3922 ufw6-after-logging-output  0    --  *      *       ::/0                 ::/0                
      34     3922 ufw6-reject-output  0    --  *      *       ::/0                 ::/0                
      34     3922 ufw6-track-output  0    --  *      *       ::/0                 ::/0                

Chain LIBVIRT_FWI (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain LIBVIRT_FWO (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain LIBVIRT_FWX (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain LIBVIRT_INP (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain LIBVIRT_OUT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-after-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-after-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ufw6-skip-to-policy-input  17   --  *      *       ::/0                 ::/0                 udp dpt:137
       0        0 ufw6-skip-to-policy-input  17   --  *      *       ::/0                 ::/0                 udp dpt:138
       0        0 ufw6-skip-to-policy-input  6    --  *      *       ::/0                 ::/0                 tcp dpt:139
       0        0 ufw6-skip-to-policy-input  6    --  *      *       ::/0                 ::/0                 tcp dpt:445
       0        0 ufw6-skip-to-policy-input  17   --  *      *       ::/0                 ::/0                 udp dpt:546
       0        0 ufw6-skip-to-policy-input  17   --  *      *       ::/0                 ::/0                 udp dpt:547

Chain ufw6-after-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       ::/0                 ::/0                 limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw6-after-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       ::/0                 ::/0                 limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw6-after-logging-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-after-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-before-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  *      *       ::/0                 ::/0                 rt type:0
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                 ctstate RELATED,ESTABLISHED
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 1
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 2
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 3
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 4
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 128
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 129
       0        0 ufw6-user-forward  0    --  *      *       ::/0                 ::/0                

Chain ufw6-before-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       4      292 ACCEPT     0    --  lo     *       ::/0                 ::/0                
       0        0 DROP       0    --  *      *       ::/0                 ::/0                 rt type:0
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                 ctstate RELATED,ESTABLISHED
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 129
       0        0 ufw6-logging-deny  0    --  *      *       ::/0                 ::/0                 ctstate INVALID
       0        0 DROP       0    --  *      *       ::/0                 ::/0                 ctstate INVALID
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 1
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 2
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 3
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 4
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 128
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 133 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 134 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 135 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 136 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 141 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 142 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 130
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 131
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 132
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 143
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 148 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 149 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 151 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 152 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 153 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 144
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 145
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 146
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 147
       0        0 ACCEPT     17   --  *      *       fe80::/10            fe80::/10            udp spt:547 dpt:546
     124    13652 ACCEPT     17   --  *      *       ::/0                 ff02::fb             udp dpt:5353
       0        0 ACCEPT     17   --  *      *       ::/0                 ff02::f              udp dpt:1900
       0        0 ufw6-user-input  0    --  *      *       ::/0                 ::/0                

Chain ufw6-before-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-before-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-before-logging-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-before-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       4      292 ACCEPT     0    --  *      lo      ::/0                 ::/0                
       0        0 DROP       0    --  *      *       ::/0                 ::/0                 rt type:0
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                 ctstate RELATED,ESTABLISHED
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 1
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 2
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 3
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 4
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 128
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 129
      20     1040 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 133 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 136 HL match HL == 255
       2      144 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 135 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 134 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 141 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 142 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 130
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 131
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 132
       6      516 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 143
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 148 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 149 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 151 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 152 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 153 HL match HL == 1
      34     3922 ufw6-user-output  0    --  *      *       ::/0                 ::/0                

Chain ufw6-logging-allow (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       ::/0                 ::/0                 limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW ALLOW] "

Chain ufw6-logging-deny (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 RETURN     0    --  *      *       ::/0                 ::/0                 ctstate INVALID limit: avg 3/min burst 10
       0        0 LOG        0    --  *      *       ::/0                 ::/0                 limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw6-reject-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-reject-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-reject-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-skip-to-policy-forward (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  *      *       ::/0                 ::/0                

Chain ufw6-skip-to-policy-input (6 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  *      *       ::/0                 ::/0                

Chain ufw6-skip-to-policy-output (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                

Chain ufw6-track-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-track-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-track-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     6    --  *      *       ::/0                 ::/0                 ctstate NEW
      30     3578 ACCEPT     17   --  *      *       ::/0                 ::/0                 ctstate NEW

Chain ufw6-user-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-user-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  BRIDGE_1 *       ::/0                 ::/0                

Chain ufw6-user-limit (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       ::/0                 ::/0                 limit: avg 3/min burst 5 LOG flags 0 level 4 prefix "[UFW LIMIT BLOCK] "
       0        0 REJECT     0    --  *      *       ::/0                 ::/0                 reject-with icmp6-port-unreachable

Chain ufw6-user-limit-accept (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                

Chain ufw6-user-logging-forward (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-user-logging-input (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-user-logging-output (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-user-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain POSTROUTING (policy ACCEPT 94 packets, 9340 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
      94     9340 LIBVIRT_PRT  0    --  *      *       ::/0                 ::/0                

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination
```

## iptables-v4
exit=0; optional=False
```text
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [289283:224667359]
:LIBVIRT_PRT - [0:0]
[289283:224667359] -A POSTROUTING -j LIBVIRT_PRT
[0:0] -A LIBVIRT_PRT -o virbr0 -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
[3:1062] -A LIBVIRT_PRT -o BRIDGE_1 -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
COMMIT


*filter
:INPUT DROP [170:7318]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [16:680]
:LIBVIRT_FWI - [0:0]
:LIBVIRT_FWO - [0:0]
:LIBVIRT_FWX - [0:0]
:LIBVIRT_INP - [0:0]
:LIBVIRT_OUT - [0:0]
:ufw-after-forward - [0:0]
:ufw-after-input - [0:0]
:ufw-after-logging-forward - [0:0]
:ufw-after-logging-input - [0:0]
:ufw-after-logging-output - [0:0]
:ufw-after-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-before-input - [0:0]
:ufw-before-logging-forward - [0:0]
:ufw-before-logging-input - [0:0]
:ufw-before-logging-output - [0:0]
:ufw-before-output - [0:0]
:ufw-logging-allow - [0:0]
:ufw-logging-deny - [0:0]
:ufw-not-local - [0:0]
:ufw-reject-forward - [0:0]
:ufw-reject-input - [0:0]
:ufw-reject-output - [0:0]
:ufw-skip-to-policy-forward - [0:0]
:ufw-skip-to-policy-input - [0:0]
:ufw-skip-to-policy-output - [0:0]
:ufw-track-forward - [0:0]
:ufw-track-input - [0:0]
:ufw-track-output - [0:0]
:ufw-user-forward - [0:0]
:ufw-user-input - [0:0]
:ufw-user-limit - [0:0]
:ufw-user-limit-accept - [0:0]
:ufw-user-logging-forward - [0:0]
:ufw-user-logging-input - [0:0]
:ufw-user-logging-output - [0:0]
:ufw-user-output - [0:0]
[233269:315747228] -A INPUT -j LIBVIRT_INP
[232651:315692840] -A INPUT -j ufw-before-logging-input
[232651:315692840] -A INPUT -j ufw-before-input
[373:55425] -A INPUT -j ufw-after-input
[245:12854] -A INPUT -j ufw-after-logging-input
[245:12854] -A INPUT -j ufw-reject-input
[245:12854] -A INPUT -j ufw-track-input
[140569:199978730] -A FORWARD -j LIBVIRT_FWX
[140569:199978730] -A FORWARD -j LIBVIRT_FWI
[66803:13987571] -A FORWARD -j LIBVIRT_FWO
[0:0] -A FORWARD -j ufw-before-logging-forward
[0:0] -A FORWARD -j ufw-before-forward
[0:0] -A FORWARD -j ufw-after-forward
[0:0] -A FORWARD -j ufw-after-logging-forward
[0:0] -A FORWARD -j ufw-reject-forward
[0:0] -A FORWARD -j ufw-track-forward
[148664:24681187] -A OUTPUT -j LIBVIRT_OUT
[148750:24687124] -A OUTPUT -j ufw-before-logging-output
[148750:24687124] -A OUTPUT -j ufw-before-output
[1932:442992] -A OUTPUT -j ufw-after-output
[1932:442992] -A OUTPUT -j ufw-after-logging-output
[1932:442992] -A OUTPUT -j ufw-reject-output
[1932:442992] -A OUTPUT -j ufw-track-output
[0:0] -A LIBVIRT_FWI -d 192.168.122.0/24 -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A LIBVIRT_FWI -o virbr0 -j REJECT --reject-with icmp-port-unreachable
[73766:185991159] -A LIBVIRT_FWI -d 192.168.231.0/24 -o BRIDGE_1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A LIBVIRT_FWI -o BRIDGE_1 -j REJECT --reject-with icmp-port-unreachable
[0:0] -A LIBVIRT_FWO -s 192.168.122.0/24 -i virbr0 -j ACCEPT
[0:0] -A LIBVIRT_FWO -i virbr0 -j REJECT --reject-with icmp-port-unreachable
[66795:13987091] -A LIBVIRT_FWO -s 192.168.231.0/24 -i BRIDGE_1 -j ACCEPT
[8:480] -A LIBVIRT_FWO -i BRIDGE_1 -j REJECT --reject-with icmp-port-unreachable
[0:0] -A LIBVIRT_FWX -i virbr0 -o virbr0 -j ACCEPT
[0:0] -A LIBVIRT_FWX -i BRIDGE_1 -o BRIDGE_1 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p tcp -m tcp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p udp -m udp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p tcp -m tcp --dport 67 -j ACCEPT
[702:60291] -A LIBVIRT_INP -i BRIDGE_1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i BRIDGE_1 -p tcp -m tcp --dport 53 -j ACCEPT
[3:1016] -A LIBVIRT_INP -i BRIDGE_1 -p udp -m udp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_INP -i BRIDGE_1 -p tcp -m tcp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p tcp -m tcp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p udp -m udp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p tcp -m tcp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o BRIDGE_1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o BRIDGE_1 -p tcp -m tcp --dport 53 -j ACCEPT
[3:1062] -A LIBVIRT_OUT -o BRIDGE_1 -p udp -m udp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o BRIDGE_1 -p tcp -m tcp --dport 68 -j ACCEPT
[0:0] -A ufw-after-input -p udp -m udp --dport 137 -j ufw-skip-to-policy-input
[10:2395] -A ufw-after-input -p udp -m udp --dport 138 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p tcp -m tcp --dport 139 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p tcp -m tcp --dport 445 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p udp -m udp --dport 67 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p udp -m udp --dport 68 -j ufw-skip-to-policy-input
[118:40176] -A ufw-after-input -m addrtype --dst-type BROADCAST -j ufw-skip-to-policy-input
[0:0] -A ufw-after-logging-forward -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[170:7318] -A ufw-after-logging-input -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 3 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 11 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 12 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 8 -j ACCEPT
[0:0] -A ufw-before-forward -j ufw-user-forward
[17506:6485480] -A ufw-before-input -i lo -j ACCEPT
[214654:309139876] -A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
[0:0] -A ufw-before-input -m conntrack --ctstate INVALID -j DROP
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 3 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 11 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 12 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 8 -j ACCEPT
[0:0] -A ufw-before-input -p udp -m udp --sport 67 --dport 68 -j ACCEPT
[416:61948] -A ufw-before-input -j ufw-not-local
[116:10789] -A ufw-before-input -d 224.0.0.251/32 -p udp -m udp --dport 5353 -j ACCEPT
[0:0] -A ufw-before-input -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j ACCEPT
[300:51159] -A ufw-before-input -j ufw-user-input
[17507:6485472] -A ufw-before-output -o lo -j ACCEPT
[129311:17758660] -A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[1856:437368] -A ufw-before-output -j ufw-user-output
[0:0] -A ufw-logging-allow -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW ALLOW] "
[0:0] -A ufw-logging-deny -m conntrack --ctstate INVALID -m limit --limit 3/min --limit-burst 10 -j RETURN
[0:0] -A ufw-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw-not-local -m addrtype --dst-type LOCAL -j RETURN
[288:19377] -A ufw-not-local -m addrtype --dst-type MULTICAST -j RETURN
[128:42571] -A ufw-not-local -m addrtype --dst-type BROADCAST -j RETURN
[0:0] -A ufw-not-local -m limit --limit 3/min --limit-burst 10 -j ufw-logging-deny
[0:0] -A ufw-not-local -j DROP
[0:0] -A ufw-skip-to-policy-forward -j DROP
[128:42571] -A ufw-skip-to-policy-input -j DROP
[0:0] -A ufw-skip-to-policy-output -j ACCEPT
[348:20880] -A ufw-track-output -p tcp -m conntrack --ctstate NEW -j ACCEPT
[1530:418088] -A ufw-track-output -p udp -m conntrack --ctstate NEW -j ACCEPT
[0:0] -A ufw-user-input -i BRIDGE_1 -p udp -m udp --sport 68 --dport 67 -j ACCEPT
[0:0] -A ufw-user-input -d 192.168.231.1/32 -i BRIDGE_1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A ufw-user-input -d 192.168.231.1/32 -i BRIDGE_1 -p tcp -m tcp --dport 53 -j ACCEPT
[2:1270] -A ufw-user-input -i BRIDGE_1 -j DROP
[0:0] -A ufw-user-limit -m limit --limit 3/min -j LOG --log-prefix "[UFW LIMIT BLOCK] "
[0:0] -A ufw-user-limit -j REJECT --reject-with icmp-port-unreachable
[0:0] -A ufw-user-limit-accept -j ACCEPT
COMMIT


*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [2956:516103]
:LIBVIRT_PRT - [0:0]
[3279:537911] -A POSTROUTING -j LIBVIRT_PRT
[8:559] -A LIBVIRT_PRT -s 192.168.122.0/24 -d 224.0.0.0/24 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 -d IP4_2/32 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -p tcp -j MASQUERADE --to-ports 1024-65535
[2:1270] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -p udp -j MASQUERADE --to-ports 1024-65535
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -j MASQUERADE
[8:559] -A LIBVIRT_PRT -s 192.168.231.0/24 -d 224.0.0.0/24 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.231.0/24 -d IP4_2/32 -j RETURN
[311:18660] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -p tcp -j MASQUERADE --to-ports 1024-65535
[10:1878] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -p udp -j MASQUERADE --to-ports 1024-65535
[0:0] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -j MASQUERADE
COMMIT
```

## iptables-v6
exit=0; optional=False
```text
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [94:9340]
:LIBVIRT_PRT - [0:0]
[94:9340] -A POSTROUTING -j LIBVIRT_PRT
COMMIT


*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [4:344]
:LIBVIRT_FWI - [0:0]
:LIBVIRT_FWO - [0:0]
:LIBVIRT_FWX - [0:0]
:LIBVIRT_INP - [0:0]
:LIBVIRT_OUT - [0:0]
:ufw6-after-forward - [0:0]
:ufw6-after-input - [0:0]
:ufw6-after-logging-forward - [0:0]
:ufw6-after-logging-input - [0:0]
:ufw6-after-logging-output - [0:0]
:ufw6-after-output - [0:0]
:ufw6-before-forward - [0:0]
:ufw6-before-input - [0:0]
:ufw6-before-logging-forward - [0:0]
:ufw6-before-logging-input - [0:0]
:ufw6-before-logging-output - [0:0]
:ufw6-before-output - [0:0]
:ufw6-logging-allow - [0:0]
:ufw6-logging-deny - [0:0]
:ufw6-reject-forward - [0:0]
:ufw6-reject-input - [0:0]
:ufw6-reject-output - [0:0]
:ufw6-skip-to-policy-forward - [0:0]
:ufw6-skip-to-policy-input - [0:0]
:ufw6-skip-to-policy-output - [0:0]
:ufw6-track-forward - [0:0]
:ufw6-track-input - [0:0]
:ufw6-track-output - [0:0]
:ufw6-user-forward - [0:0]
:ufw6-user-input - [0:0]
:ufw6-user-limit - [0:0]
:ufw6-user-limit-accept - [0:0]
:ufw6-user-logging-forward - [0:0]
:ufw6-user-logging-input - [0:0]
:ufw6-user-logging-output - [0:0]
:ufw6-user-output - [0:0]
[126:13792] -A INPUT -j LIBVIRT_INP
[128:13944] -A INPUT -j ufw6-before-logging-input
[128:13944] -A INPUT -j ufw6-before-input
[0:0] -A INPUT -j ufw6-after-input
[0:0] -A INPUT -j ufw6-after-logging-input
[0:0] -A INPUT -j ufw6-reject-input
[0:0] -A INPUT -j ufw6-track-input
[0:0] -A FORWARD -j LIBVIRT_FWX
[0:0] -A FORWARD -j LIBVIRT_FWI
[0:0] -A FORWARD -j LIBVIRT_FWO
[0:0] -A FORWARD -j ufw6-before-logging-forward
[0:0] -A FORWARD -j ufw6-before-forward
[0:0] -A FORWARD -j ufw6-after-forward
[0:0] -A FORWARD -j ufw6-after-logging-forward
[0:0] -A FORWARD -j ufw6-reject-forward
[0:0] -A FORWARD -j ufw6-track-forward
[64:5762] -A OUTPUT -j LIBVIRT_OUT
[66:5914] -A OUTPUT -j ufw6-before-logging-output
[66:5914] -A OUTPUT -j ufw6-before-output
[34:3922] -A OUTPUT -j ufw6-after-output
[34:3922] -A OUTPUT -j ufw6-after-logging-output
[34:3922] -A OUTPUT -j ufw6-reject-output
[34:3922] -A OUTPUT -j ufw6-track-output
[0:0] -A ufw6-after-input -p udp -m udp --dport 137 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-input -p udp -m udp --dport 138 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-input -p tcp -m tcp --dport 139 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-input -p tcp -m tcp --dport 445 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-input -p udp -m udp --dport 546 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-input -p udp -m udp --dport 547 -j ufw6-skip-to-policy-input
[0:0] -A ufw6-after-logging-forward -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw6-after-logging-input -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw6-before-forward -m rt --rt-type 0 -j DROP
[0:0] -A ufw6-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT
[0:0] -A ufw6-before-forward -p ipv6-icmp -m icmp6 --icmpv6-type 129 -j ACCEPT
[0:0] -A ufw6-before-forward -j ufw6-user-forward
[4:292] -A ufw6-before-input -i lo -j ACCEPT
[0:0] -A ufw6-before-input -m rt --rt-type 0 -j DROP
[0:0] -A ufw6-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 129 -j ACCEPT
[0:0] -A ufw6-before-input -m conntrack --ctstate INVALID -j ufw6-logging-deny
[0:0] -A ufw6-before-input -m conntrack --ctstate INVALID -j DROP
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 133 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 134 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 135 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 136 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 141 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 142 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 130 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 131 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 132 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 143 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 148 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 149 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 151 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 152 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 153 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 144 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 145 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 146 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 147 -j ACCEPT
[0:0] -A ufw6-before-input -s fe80::/10 -d fe80::/10 -p udp -m udp --sport 547 --dport 546 -j ACCEPT
[124:13652] -A ufw6-before-input -d ff02::fb/128 -p udp -m udp --dport 5353 -j ACCEPT
[0:0] -A ufw6-before-input -d ff02::f/128 -p udp -m udp --dport 1900 -j ACCEPT
[0:0] -A ufw6-before-input -j ufw6-user-input
[4:292] -A ufw6-before-output -o lo -j ACCEPT
[0:0] -A ufw6-before-output -m rt --rt-type 0 -j DROP
[0:0] -A ufw6-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 129 -j ACCEPT
[20:1040] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 133 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 136 -m hl --hl-eq 255 -j ACCEPT
[2:144] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 135 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 134 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 141 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 142 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 130 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 131 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 132 -j ACCEPT
[6:516] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 143 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 148 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 149 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 151 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 152 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 153 -m hl --hl-eq 1 -j ACCEPT
[34:3922] -A ufw6-before-output -j ufw6-user-output
[0:0] -A ufw6-logging-allow -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW ALLOW] "
[0:0] -A ufw6-logging-deny -m conntrack --ctstate INVALID -m limit --limit 3/min --limit-burst 10 -j RETURN
[0:0] -A ufw6-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw6-skip-to-policy-forward -j DROP
[0:0] -A ufw6-skip-to-policy-input -j DROP
[0:0] -A ufw6-skip-to-policy-output -j ACCEPT
[0:0] -A ufw6-track-output -p tcp -m conntrack --ctstate NEW -j ACCEPT
[30:3578] -A ufw6-track-output -p udp -m conntrack --ctstate NEW -j ACCEPT
[0:0] -A ufw6-user-input -i BRIDGE_1 -j DROP
[0:0] -A ufw6-user-limit -m limit --limit 3/min -j LOG --log-prefix "[UFW LIMIT BLOCK] "
[0:0] -A ufw6-user-limit -j REJECT --reject-with icmp6-port-unreachable
[0:0] -A ufw6-user-limit-accept -j ACCEPT
COMMIT


*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [15:1582]
:LIBVIRT_PRT - [0:0]
[15:1582] -A POSTROUTING -j LIBVIRT_PRT
COMMIT
```

## nft-ruleset
exit=0; optional=False
```text
table ip filter { # handle 1
	chain ufw-before-logging-input { # handle 1
	}

	chain ufw-before-logging-output { # handle 2
	}

	chain ufw-before-logging-forward { # handle 3
	}

	chain ufw-before-input { # handle 4
		iifname "lo" counter packets 17514 bytes 6486200 accept # handle 95
		ct state related,established counter packets 214654 bytes 309139876 accept # handle 97
		ct state invalid counter packets 0 bytes 0 jump ufw-logging-deny # handle 100
		ct state invalid counter packets 0 bytes 0 drop # handle 101
		ip protocol icmp icmp type destination-unreachable counter packets 0 bytes 0 accept # handle 102
		ip protocol icmp icmp type time-exceeded counter packets 0 bytes 0 accept # handle 103
		ip protocol icmp icmp type parameter-problem counter packets 0 bytes 0 accept # handle 104
		ip protocol icmp icmp type echo-request counter packets 0 bytes 0 accept # handle 105
		udp sport 67 udp dport 68 counter packets 0 bytes 0 accept # handle 110
		counter packets 416 bytes 61948 jump ufw-not-local # handle 111
		ip daddr 224.0.0.251 udp dport 5353 counter packets 116 bytes 10789 accept # handle 117
		ip daddr 239.255.255.250 udp dport 1900 counter packets 0 bytes 0 accept # handle 118
		counter packets 300 bytes 51159 jump ufw-user-input # handle 146
	}

	chain ufw-before-output { # handle 5
		oifname "lo" counter packets 17515 bytes 6486192 accept # handle 96
		ct state related,established counter packets 129311 bytes 17758660 accept # handle 98
		counter packets 1856 bytes 437368 jump ufw-user-output # handle 147
	}

	chain ufw-before-forward { # handle 6
		ct state related,established counter packets 0 bytes 0 accept # handle 99
		ip protocol icmp icmp type destination-unreachable counter packets 0 bytes 0 accept # handle 106
		ip protocol icmp icmp type time-exceeded counter packets 0 bytes 0 accept # handle 107
		ip protocol icmp icmp type parameter-problem counter packets 0 bytes 0 accept # handle 108
		ip protocol icmp icmp type echo-request counter packets 0 bytes 0 accept # handle 109
		counter packets 0 bytes 0 jump ufw-user-forward # handle 148
	}

	chain ufw-after-input { # handle 7
		udp dport 137 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 119
		udp dport 138 counter packets 10 bytes 2395 jump ufw-skip-to-policy-input # handle 120
		tcp dport 139 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 121
		tcp dport 445 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 122
		udp dport 67 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 123
		udp dport 68 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 124
		fib daddr type broadcast counter packets 118 bytes 40176 jump ufw-skip-to-policy-input # handle 125
	}

	chain ufw-after-output { # handle 8
	}

	chain ufw-after-forward { # handle 9
	}

	chain ufw-after-logging-input { # handle 10
		limit rate 3/minute burst 10 packets counter packets 170 bytes 7318 log prefix "[UFW BLOCK] " # handle 138
	}

	chain ufw-after-logging-output { # handle 11
	}

	chain ufw-after-logging-forward { # handle 12
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 139
	}

	chain ufw-reject-input { # handle 13
	}

	chain ufw-reject-output { # handle 14
	}

	chain ufw-reject-forward { # handle 15
	}

	chain ufw-track-input { # handle 16
	}

	chain ufw-track-output { # handle 17
		ip protocol tcp ct state new counter packets 348 bytes 20880 accept # handle 40
		ip protocol udp ct state new counter packets 1530 bytes 418088 accept # handle 41
	}

	chain ufw-track-forward { # handle 18
	}

	chain INPUT { # handle 19
		type filter hook input priority filter; policy drop;
		counter packets 233277 bytes 315747948 jump LIBVIRT_INP # handle 150
		counter packets 232659 bytes 315693560 jump ufw-before-logging-input # handle 20
		counter packets 232659 bytes 315693560 jump ufw-before-input # handle 21
		counter packets 373 bytes 55425 jump ufw-after-input # handle 22
		counter packets 245 bytes 12854 jump ufw-after-logging-input # handle 23
		counter packets 245 bytes 12854 jump ufw-reject-input # handle 24
		counter packets 245 bytes 12854 jump ufw-track-input # handle 25
	}

	chain OUTPUT { # handle 26
		type filter hook output priority filter; policy accept;
		counter packets 148672 bytes 24681907 jump LIBVIRT_OUT # handle 152
		counter packets 148758 bytes 24687844 jump ufw-before-logging-output # handle 27
		counter packets 148758 bytes 24687844 jump ufw-before-output # handle 28
		counter packets 1932 bytes 442992 jump ufw-after-output # handle 29
		counter packets 1932 bytes 442992 jump ufw-after-logging-output # handle 30
		counter packets 1932 bytes 442992 jump ufw-reject-output # handle 31
		counter packets 1932 bytes 442992 jump ufw-track-output # handle 32
	}

	chain FORWARD { # handle 33
		type filter hook forward priority filter; policy drop;
		counter packets 140569 bytes 199978730 jump LIBVIRT_FWX # handle 158
		counter packets 140569 bytes 199978730 jump LIBVIRT_FWI # handle 156
		counter packets 66803 bytes 13987571 jump LIBVIRT_FWO # handle 154
		counter packets 0 bytes 0 jump ufw-before-logging-forward # handle 34
		counter packets 0 bytes 0 jump ufw-before-forward # handle 35
		counter packets 0 bytes 0 jump ufw-after-forward # handle 36
		counter packets 0 bytes 0 jump ufw-after-logging-forward # handle 37
		counter packets 0 bytes 0 jump ufw-reject-forward # handle 38
		counter packets 0 bytes 0 jump ufw-track-forward # handle 39
	}

	chain ufw-logging-deny { # handle 42
		ct state invalid limit rate 3/minute burst 10 packets counter packets 0 bytes 0 return # handle 140
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 141
	}

	chain ufw-logging-allow { # handle 43
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW ALLOW] " # handle 142
	}

	chain ufw-skip-to-policy-input { # handle 44
		counter packets 128 bytes 42571 drop # handle 47
	}

	chain ufw-skip-to-policy-output { # handle 45
		counter packets 0 bytes 0 accept # handle 48
	}

	chain ufw-skip-to-policy-forward { # handle 46
		counter packets 0 bytes 0 drop # handle 49
	}

	chain ufw-not-local { # handle 94
		fib daddr type local counter packets 0 bytes 0 return # handle 112
		fib daddr type multicast counter packets 288 bytes 19377 return # handle 113
		fib daddr type broadcast counter packets 128 bytes 42571 return # handle 114
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 jump ufw-logging-deny # handle 115
		counter packets 0 bytes 0 drop # handle 116
	}

	chain ufw-user-input { # handle 126
		iifname "BRIDGE_1" udp sport 68 udp dport 67 counter packets 0 bytes 0 accept # handle 134
		ip daddr 192.168.231.1 iifname "BRIDGE_1" udp dport 53 counter packets 0 bytes 0 accept # handle 135
		ip daddr 192.168.231.1 iifname "BRIDGE_1" tcp dport 53 counter packets 0 bytes 0 accept # handle 136
		iifname "BRIDGE_1" counter packets 2 bytes 1270 drop # handle 137
	}

	chain ufw-user-output { # handle 127
	}

	chain ufw-user-forward { # handle 128
	}

	chain ufw-user-logging-input { # handle 129
	}

	chain ufw-user-logging-output { # handle 130
	}

	chain ufw-user-logging-forward { # handle 131
	}

	chain ufw-user-limit { # handle 132
		limit rate 3/minute burst 5 packets counter packets 0 bytes 0 log prefix "[UFW LIMIT BLOCK] " # handle 143
		counter packets 0 bytes 0 reject # handle 144
	}

	chain ufw-user-limit-accept { # handle 133
		counter packets 0 bytes 0 accept # handle 145
	}

	chain LIBVIRT_INP { # handle 149
		iifname "virbr0" udp dport 53 counter packets 0 bytes 0 accept # handle 177
		iifname "virbr0" tcp dport 53 counter packets 0 bytes 0 accept # handle 176
		iifname "virbr0" udp dport 67 counter packets 0 bytes 0 accept # handle 173
		iifname "virbr0" tcp dport 67 counter packets 0 bytes 0 accept # handle 172
		iifname "BRIDGE_1" udp dport 53 counter packets 702 bytes 60291 accept # handle 164
		iifname "BRIDGE_1" tcp dport 53 counter packets 0 bytes 0 accept # handle 163
		iifname "BRIDGE_1" udp dport 67 counter packets 3 bytes 1016 accept # handle 160
		iifname "BRIDGE_1" tcp dport 67 counter packets 0 bytes 0 accept # handle 159
	}

	chain LIBVIRT_OUT { # handle 151
		oifname "virbr0" udp dport 53 counter packets 0 bytes 0 accept # handle 179
		oifname "virbr0" tcp dport 53 counter packets 0 bytes 0 accept # handle 178
		oifname "virbr0" udp dport 68 counter packets 0 bytes 0 accept # handle 175
		oifname "virbr0" tcp dport 68 counter packets 0 bytes 0 accept # handle 174
		oifname "BRIDGE_1" udp dport 53 counter packets 0 bytes 0 accept # handle 166
		oifname "BRIDGE_1" tcp dport 53 counter packets 0 bytes 0 accept # handle 165
		oifname "BRIDGE_1" udp dport 68 counter packets 3 bytes 1062 accept # handle 162
		oifname "BRIDGE_1" tcp dport 68 counter packets 0 bytes 0 accept # handle 161
	}

	chain LIBVIRT_FWO { # handle 153
		ip saddr 192.168.122.0/24 iifname "virbr0" counter packets 0 bytes 0 accept # handle 183
		iifname "virbr0" counter packets 0 bytes 0 reject # handle 180
		ip saddr 192.168.231.0/24 iifname "BRIDGE_1" counter packets 66795 bytes 13987091 accept # handle 170
		iifname "BRIDGE_1" counter packets 8 bytes 480 reject # handle 167
	}

	chain LIBVIRT_FWI { # handle 155
		ip daddr 192.168.122.0/24 oifname "virbr0" ct state related,established counter packets 0 bytes 0 accept # handle 184
		oifname "virbr0" counter packets 0 bytes 0 reject # handle 181
		ip daddr 192.168.231.0/24 oifname "BRIDGE_1" ct state related,established counter packets 73766 bytes 185991159 accept # handle 171
		oifname "BRIDGE_1" counter packets 0 bytes 0 reject # handle 168
	}

	chain LIBVIRT_FWX { # handle 157
		iifname "virbr0" oifname "virbr0" counter packets 0 bytes 0 accept # handle 182
		iifname "BRIDGE_1" oifname "BRIDGE_1" counter packets 0 bytes 0 accept # handle 169
	}
}
table ip6 filter { # handle 2
	chain ufw6-before-logging-input { # handle 1
	}

	chain ufw6-before-logging-output { # handle 2
	}

	chain ufw6-before-logging-forward { # handle 3
	}

	chain ufw6-before-input { # handle 4
		iifname "lo" counter packets 4 bytes 292 accept # handle 50
		rt type 0 counter packets 0 bytes 0 drop # handle 52
		ct state related,established counter packets 0 bytes 0 accept # handle 55
		meta l4proto ipv6-icmp icmpv6 type echo-reply counter packets 0 bytes 0 accept # handle 58
		ct state invalid counter packets 0 bytes 0 jump ufw6-logging-deny # handle 59
		ct state invalid counter packets 0 bytes 0 drop # handle 60
		meta l4proto ipv6-icmp icmpv6 type destination-unreachable counter packets 0 bytes 0 accept # handle 61
		meta l4proto ipv6-icmp icmpv6 type packet-too-big counter packets 0 bytes 0 accept # handle 62
		meta l4proto ipv6-icmp icmpv6 type time-exceeded counter packets 0 bytes 0 accept # handle 63
		meta l4proto ipv6-icmp icmpv6 type parameter-problem counter packets 0 bytes 0 accept # handle 64
		meta l4proto ipv6-icmp icmpv6 type echo-request counter packets 0 bytes 0 accept # handle 65
		meta l4proto ipv6-icmp icmpv6 type nd-router-solicit ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 66
		meta l4proto ipv6-icmp icmpv6 type nd-router-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 67
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-solicit ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 68
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 69
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 70
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 71
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-query counter packets 0 bytes 0 accept # handle 72
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-report counter packets 0 bytes 0 accept # handle 73
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-done counter packets 0 bytes 0 accept # handle 74
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" counter packets 0 bytes 0 accept # handle 75
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 76
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 77
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 78
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 79
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 80
		meta l4proto ipv6-icmp xt match "icmp6" counter packets 0 bytes 0 accept # handle 108
		meta l4proto ipv6-icmp xt match "icmp6" counter packets 0 bytes 0 accept # handle 109
		meta l4proto ipv6-icmp xt match "icmp6" counter packets 0 bytes 0 accept # handle 110
		meta l4proto ipv6-icmp xt match "icmp6" counter packets 0 bytes 0 accept # handle 111
		ip6 saddr fe80::/10 ip6 daddr fe80::/10 udp sport 547 udp dport 546 counter packets 0 bytes 0 accept # handle 112
		ip6 daddr ff02::fb udp dport 5353 counter packets 124 bytes 13652 accept # handle 113
		ip6 daddr ff02::f udp dport 1900 counter packets 0 bytes 0 accept # handle 114
		counter packets 0 bytes 0 jump ufw6-user-input # handle 138
	}

	chain ufw6-before-output { # handle 5
		oifname "lo" counter packets 4 bytes 292 accept # handle 51
		rt type 0 counter packets 0 bytes 0 drop # handle 54
		ct state related,established counter packets 0 bytes 0 accept # handle 56
		meta l4proto ipv6-icmp icmpv6 type destination-unreachable counter packets 0 bytes 0 accept # handle 81
		meta l4proto ipv6-icmp icmpv6 type packet-too-big counter packets 0 bytes 0 accept # handle 82
		meta l4proto ipv6-icmp icmpv6 type time-exceeded counter packets 0 bytes 0 accept # handle 83
		meta l4proto ipv6-icmp icmpv6 type parameter-problem counter packets 0 bytes 0 accept # handle 84
		meta l4proto ipv6-icmp icmpv6 type echo-request counter packets 0 bytes 0 accept # handle 85
		meta l4proto ipv6-icmp icmpv6 type echo-reply counter packets 0 bytes 0 accept # handle 86
		meta l4proto ipv6-icmp icmpv6 type nd-router-solicit ip6 hoplimit 255 counter packets 20 bytes 1040 accept # handle 87
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 88
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-solicit ip6 hoplimit 255 counter packets 2 bytes 144 accept # handle 89
		meta l4proto ipv6-icmp icmpv6 type nd-router-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 90
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 91
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 92
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-query counter packets 0 bytes 0 accept # handle 93
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-report counter packets 0 bytes 0 accept # handle 94
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-done counter packets 0 bytes 0 accept # handle 95
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" counter packets 6 bytes 516 accept # handle 96
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 97
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 98
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 99
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 100
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 101
		counter packets 34 bytes 3922 jump ufw6-user-output # handle 139
	}

	chain ufw6-before-forward { # handle 6
		rt type 0 counter packets 0 bytes 0 drop # handle 53
		ct state related,established counter packets 0 bytes 0 accept # handle 57
		meta l4proto ipv6-icmp icmpv6 type destination-unreachable counter packets 0 bytes 0 accept # handle 102
		meta l4proto ipv6-icmp icmpv6 type packet-too-big counter packets 0 bytes 0 accept # handle 103
		meta l4proto ipv6-icmp icmpv6 type time-exceeded counter packets 0 bytes 0 accept # handle 104
		meta l4proto ipv6-icmp icmpv6 type parameter-problem counter packets 0 bytes 0 accept # handle 105
		meta l4proto ipv6-icmp icmpv6 type echo-request counter packets 0 bytes 0 accept # handle 106
		meta l4proto ipv6-icmp icmpv6 type echo-reply counter packets 0 bytes 0 accept # handle 107
		counter packets 0 bytes 0 jump ufw6-user-forward # handle 140
	}

	chain ufw6-after-input { # handle 7
		udp dport 137 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 115
		udp dport 138 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 116
		tcp dport 139 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 117
		tcp dport 445 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 118
		udp dport 546 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 119
		udp dport 547 counter packets 0 bytes 0 jump ufw6-skip-to-policy-input # handle 120
	}

	chain ufw6-after-output { # handle 8
	}

	chain ufw6-after-forward { # handle 9
	}

	chain ufw6-after-logging-input { # handle 10
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 130
	}

	chain ufw6-after-logging-output { # handle 11
	}

	chain ufw6-after-logging-forward { # handle 12
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 131
	}

	chain ufw6-reject-input { # handle 13
	}

	chain ufw6-reject-output { # handle 14
	}

	chain ufw6-reject-forward { # handle 15
	}

	chain ufw6-track-input { # handle 16
	}

	chain ufw6-track-output { # handle 17
		meta l4proto tcp ct state new counter packets 0 bytes 0 accept # handle 40
		meta l4proto udp ct state new counter packets 30 bytes 3578 accept # handle 41
	}

	chain ufw6-track-forward { # handle 18
	}

	chain INPUT { # handle 19
		type filter hook input priority filter; policy drop;
		counter packets 126 bytes 13792 jump LIBVIRT_INP # handle 142
		counter packets 128 bytes 13944 jump ufw6-before-logging-input # handle 20
		counter packets 128 bytes 13944 jump ufw6-before-input # handle 21
		counter packets 0 bytes 0 jump ufw6-after-input # handle 22
		counter packets 0 bytes 0 jump ufw6-after-logging-input # handle 23
		counter packets 0 bytes 0 jump ufw6-reject-input # handle 24
		counter packets 0 bytes 0 jump ufw6-track-input # handle 25
	}

	chain OUTPUT { # handle 26
		type filter hook output priority filter; policy accept;
		counter packets 64 bytes 5762 jump LIBVIRT_OUT # handle 144
		counter packets 66 bytes 5914 jump ufw6-before-logging-output # handle 27
		counter packets 66 bytes 5914 jump ufw6-before-output # handle 28
		counter packets 34 bytes 3922 jump ufw6-after-output # handle 29
		counter packets 34 bytes 3922 jump ufw6-after-logging-output # handle 30
		counter packets 34 bytes 3922 jump ufw6-reject-output # handle 31
		counter packets 34 bytes 3922 jump ufw6-track-output # handle 32
	}

	chain FORWARD { # handle 33
		type filter hook forward priority filter; policy drop;
		counter packets 0 bytes 0 jump LIBVIRT_FWX # handle 150
		counter packets 0 bytes 0 jump LIBVIRT_FWI # handle 148
		counter packets 0 bytes 0 jump LIBVIRT_FWO # handle 146
		counter packets 0 bytes 0 jump ufw6-before-logging-forward # handle 34
		counter packets 0 bytes 0 jump ufw6-before-forward # handle 35
		counter packets 0 bytes 0 jump ufw6-after-forward # handle 36
		counter packets 0 bytes 0 jump ufw6-after-logging-forward # handle 37
		counter packets 0 bytes 0 jump ufw6-reject-forward # handle 38
		counter packets 0 bytes 0 jump ufw6-track-forward # handle 39
	}

	chain ufw6-logging-deny { # handle 42
		ct state invalid limit rate 3/minute burst 10 packets counter packets 0 bytes 0 return # handle 132
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 133
	}

	chain ufw6-logging-allow { # handle 43
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW ALLOW] " # handle 134
	}

	chain ufw6-skip-to-policy-input { # handle 44
		counter packets 0 bytes 0 drop # handle 47
	}

	chain ufw6-skip-to-policy-output { # handle 45
		counter packets 0 bytes 0 accept # handle 48
	}

	chain ufw6-skip-to-policy-forward { # handle 46
		counter packets 0 bytes 0 drop # handle 49
	}

	chain ufw6-user-input { # handle 121
		iifname "BRIDGE_1" counter packets 0 bytes 0 drop # handle 129
	}

	chain ufw6-user-output { # handle 122
	}

	chain ufw6-user-forward { # handle 123
	}

	chain ufw6-user-logging-input { # handle 124
	}

	chain ufw6-user-logging-output { # handle 125
	}

	chain ufw6-user-logging-forward { # handle 126
	}

	chain ufw6-user-limit { # handle 127
		limit rate 3/minute burst 5 packets counter packets 0 bytes 0 log prefix "[UFW LIMIT BLOCK] " # handle 135
		counter packets 0 bytes 0 reject # handle 136
	}

	chain ufw6-user-limit-accept { # handle 128
		counter packets 0 bytes 0 accept # handle 137
	}

	chain LIBVIRT_INP { # handle 141
	}

	chain LIBVIRT_OUT { # handle 143
	}

	chain LIBVIRT_FWO { # handle 145
	}

	chain LIBVIRT_FWI { # handle 147
	}

	chain LIBVIRT_FWX { # handle 149
	}
}
table ip nat { # handle 3
	chain LIBVIRT_PRT { # handle 1
		ip saddr 192.168.122.0/24 ip daddr 224.0.0.0/24 counter packets 8 bytes 559 return # handle 13
		ip saddr 192.168.122.0/24 ip daddr IP4_2 counter packets 0 bytes 0 return # handle 12
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 ip protocol tcp counter packets 0 bytes 0 masquerade to :1024-65535 # handle 11
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 ip protocol udp counter packets 2 bytes 1270 masquerade to :1024-65535 # handle 10
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 counter packets 0 bytes 0 masquerade # handle 9
		ip saddr 192.168.231.0/24 ip daddr 224.0.0.0/24 counter packets 8 bytes 559 return # handle 8
		ip saddr 192.168.231.0/24 ip daddr IP4_2 counter packets 0 bytes 0 return # handle 7
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 ip protocol tcp counter packets 311 bytes 18660 masquerade to :1024-65535 # handle 6
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 ip protocol udp counter packets 10 bytes 1878 masquerade to :1024-65535 # handle 5
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 counter packets 0 bytes 0 masquerade # handle 4
	}

	chain POSTROUTING { # handle 2
		type nat hook postrouting priority srcnat; policy accept;
		counter packets 3281 bytes 538039 jump LIBVIRT_PRT # handle 3
	}
}
table ip mangle { # handle 4
	chain LIBVIRT_PRT { # handle 1
		oifname "virbr0" udp dport 68 counter packets 0 bytes 0 xt target "CHECKSUM" # handle 5
		oifname "BRIDGE_1" udp dport 68 counter packets 3 bytes 1062 xt target "CHECKSUM" # handle 4
	}

	chain POSTROUTING { # handle 2
		type filter hook postrouting priority mangle; policy accept;
		counter packets 289291 bytes 224668079 jump LIBVIRT_PRT # handle 3
	}
}
table ip6 nat { # handle 5
	chain LIBVIRT_PRT { # handle 1
	}

	chain POSTROUTING { # handle 2
		type nat hook postrouting priority srcnat; policy accept;
		counter packets 15 bytes 1582 jump LIBVIRT_PRT # handle 3
	}
}
table ip6 mangle { # handle 6
	chain LIBVIRT_PRT { # handle 1
	}

	chain POSTROUTING { # handle 2
		type filter hook postrouting priority mangle; policy accept;
		counter packets 94 bytes 9340 jump LIBVIRT_PRT # handle 3
	}
}
```

## iptables-backend
exit=0; optional=False
```text
iptables v1.8.10 (nf_tables)
```

## ip6tables-backend
exit=0; optional=False
```text
ip6tables v1.8.10 (nf_tables)
```

## iptables-legacy-save
exit=0; optional=False
```text

```

## ip6tables-legacy-save
exit=0; optional=False
```text

```

## ufw-before.rules
exit=0; optional=False
```text
*filter
:ufw-before-input - [0:0]
:ufw-before-output - [0:0]
:ufw-before-forward - [0:0]
:ufw-not-local - [0:0]


-A ufw-before-input -i lo -j ACCEPT
-A ufw-before-output -o lo -j ACCEPT

-A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

-A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
-A ufw-before-input -m conntrack --ctstate INVALID -j DROP

-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-input -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-input -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT

-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type time-exceeded -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type parameter-problem -j ACCEPT
-A ufw-before-forward -p icmp --icmp-type echo-request -j ACCEPT

-A ufw-before-input -p udp --sport 67 --dport 68 -j ACCEPT



-A ufw-before-input -j ufw-not-local

-A ufw-not-local -m addrtype --dst-type LOCAL -j RETURN

-A ufw-not-local -m addrtype --dst-type MULTICAST -j RETURN

-A ufw-not-local -m addrtype --dst-type BROADCAST -j RETURN

-A ufw-not-local -m limit --limit 3/min --limit-burst 10 -j ufw-logging-deny
-A ufw-not-local -j DROP


-A ufw-before-input -p udp -d 224.0.0.251 --dport 5353 -j ACCEPT


-A ufw-before-input -p udp -d 239.255.255.250 --dport 1900 -j ACCEPT

COMMIT
```

## ufw-before6.rules
exit=0; optional=False
```text
*filter
:ufw6-before-input - [0:0]
:ufw6-before-output - [0:0]
:ufw6-before-forward - [0:0]


-A ufw6-before-input -i lo -j ACCEPT
-A ufw6-before-output -o lo -j ACCEPT

-A ufw6-before-input -m rt --rt-type 0 -j DROP
-A ufw6-before-forward -m rt --rt-type 0 -j DROP
-A ufw6-before-output -m rt --rt-type 0 -j DROP

-A ufw6-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw6-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
-A ufw6-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT



-A ufw6-before-input -p icmpv6 --icmpv6-type echo-reply -j ACCEPT

-A ufw6-before-input -m conntrack --ctstate INVALID -j ufw6-logging-deny
-A ufw6-before-input -m conntrack --ctstate INVALID -j DROP

-A ufw6-before-input -p icmpv6 --icmpv6-type destination-unreachable -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type packet-too-big -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type time-exceeded -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type parameter-problem -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type echo-request -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type router-solicitation -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type router-advertisement -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-input -p icmpv6 --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 141 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 142 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 130 -s fe80::/10 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 131 -s fe80::/10 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 132 -s fe80::/10 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 143 -s fe80::/10 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 148 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 149 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 151 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 152 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 153 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type destination-unreachable -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type packet-too-big -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type time-exceeded -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type parameter-problem -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type echo-request -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type echo-reply -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type router-solicitation -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type neighbor-advertisement -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type neighbor-solicitation -m hl --hl-eq 255 -j ACCEPT
-A ufw6-before-output -p icmpv6 --icmpv6-type router-advertisement -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 141 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 142 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 130 -s fe80::/10 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 131 -s fe80::/10 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 132 -s fe80::/10 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 143 -s fe80::/10 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 148 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 149 -m hl --hl-eq 255 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 151 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 152 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-output -p icmpv6 --icmpv6-type 153 -s fe80::/10 -m hl --hl-eq 1 -j ACCEPT

-A ufw6-before-forward -p icmpv6 --icmpv6-type destination-unreachable -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type packet-too-big -j ACCEPT

-A ufw6-before-forward -p icmpv6 --icmpv6-type time-exceeded -j ACCEPT

-A ufw6-before-forward -p icmpv6 --icmpv6-type parameter-problem -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type echo-request -j ACCEPT
-A ufw6-before-forward -p icmpv6 --icmpv6-type echo-reply -j ACCEPT


-A ufw6-before-input -p icmpv6 --icmpv6-type 144 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 145 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 146 -j ACCEPT

-A ufw6-before-input -p icmpv6 --icmpv6-type 147 -j ACCEPT

-A ufw6-before-input -p udp -s fe80::/10 --sport 547 -d fe80::/10 --dport 546 -j ACCEPT

-A ufw6-before-input -p udp -d ff02::fb --dport 5353 -j ACCEPT

-A ufw6-before-input -p udp -d ff02::f --dport 1900 -j ACCEPT

COMMIT
```

## ufw-after.rules
exit=0; optional=False
```text
*filter
:ufw-after-input - [0:0]
:ufw-after-output - [0:0]
:ufw-after-forward - [0:0]


-A ufw-after-input -p udp --dport 137 -j ufw-skip-to-policy-input
-A ufw-after-input -p udp --dport 138 -j ufw-skip-to-policy-input
-A ufw-after-input -p tcp --dport 139 -j ufw-skip-to-policy-input
-A ufw-after-input -p tcp --dport 445 -j ufw-skip-to-policy-input
-A ufw-after-input -p udp --dport 67 -j ufw-skip-to-policy-input
-A ufw-after-input -p udp --dport 68 -j ufw-skip-to-policy-input

-A ufw-after-input -m addrtype --dst-type BROADCAST -j ufw-skip-to-policy-input

COMMIT
```

## ufw-after6.rules
exit=0; optional=False
```text
*filter
:ufw6-after-input - [0:0]
:ufw6-after-output - [0:0]
:ufw6-after-forward - [0:0]


-A ufw6-after-input -p udp --dport 137 -j ufw6-skip-to-policy-input
-A ufw6-after-input -p udp --dport 138 -j ufw6-skip-to-policy-input
-A ufw6-after-input -p tcp --dport 139 -j ufw6-skip-to-policy-input
-A ufw6-after-input -p tcp --dport 445 -j ufw6-skip-to-policy-input
-A ufw6-after-input -p udp --dport 546 -j ufw6-skip-to-policy-input
-A ufw6-after-input -p udp --dport 547 -j ufw6-skip-to-policy-input

COMMIT
```

## ufw-user.rules
exit=0; optional=False
```text
*filter
:ufw-user-input - [0:0]
:ufw-user-output - [0:0]
:ufw-user-forward - [0:0]
:ufw-before-logging-input - [0:0]
:ufw-before-logging-output - [0:0]
:ufw-before-logging-forward - [0:0]
:ufw-user-logging-input - [0:0]
:ufw-user-logging-output - [0:0]
:ufw-user-logging-forward - [0:0]
:ufw-after-logging-input - [0:0]
:ufw-after-logging-output - [0:0]
:ufw-after-logging-forward - [0:0]
:ufw-logging-deny - [0:0]
:ufw-logging-allow - [0:0]
:ufw-user-limit - [0:0]
:ufw-user-limit-accept - [0:0]


-A ufw-user-input -i BRIDGE_1 -p udp --dport 67 --sport 68 -j ACCEPT

-A ufw-user-input -i BRIDGE_1 -p udp -d 192.168.231.1 --dport 53 -j ACCEPT

-A ufw-user-input -i BRIDGE_1 -p tcp -d 192.168.231.1 --dport 53 -j ACCEPT

-A ufw-user-input -i BRIDGE_1 -j DROP


-A ufw-after-logging-input -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-A ufw-after-logging-forward -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-I ufw-logging-deny -m conntrack --ctstate INVALID -j RETURN -m limit --limit 3/min --limit-burst 10
-A ufw-logging-deny -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-A ufw-logging-allow -j LOG --log-prefix "[UFW ALLOW] " -m limit --limit 3/min --limit-burst 10


-A ufw-user-limit -m limit --limit 3/minute -j LOG --log-prefix "[UFW LIMIT BLOCK] "
-A ufw-user-limit -j REJECT
-A ufw-user-limit-accept -j ACCEPT

COMMIT
```

## ufw-user6.rules
exit=0; optional=False
```text
*filter
:ufw6-user-input - [0:0]
:ufw6-user-output - [0:0]
:ufw6-user-forward - [0:0]
:ufw6-before-logging-input - [0:0]
:ufw6-before-logging-output - [0:0]
:ufw6-before-logging-forward - [0:0]
:ufw6-user-logging-input - [0:0]
:ufw6-user-logging-output - [0:0]
:ufw6-user-logging-forward - [0:0]
:ufw6-after-logging-input - [0:0]
:ufw6-after-logging-output - [0:0]
:ufw6-after-logging-forward - [0:0]
:ufw6-logging-deny - [0:0]
:ufw6-logging-allow - [0:0]
:ufw6-user-limit - [0:0]
:ufw6-user-limit-accept - [0:0]


-A ufw6-user-input -i BRIDGE_1 -j DROP


-A ufw6-after-logging-input -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-A ufw6-after-logging-forward -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-I ufw6-logging-deny -m conntrack --ctstate INVALID -j RETURN -m limit --limit 3/min --limit-burst 10
-A ufw6-logging-deny -j LOG --log-prefix "[UFW BLOCK] " -m limit --limit 3/min --limit-burst 10
-A ufw6-logging-allow -j LOG --log-prefix "[UFW ALLOW] " -m limit --limit 3/min --limit-burst 10


-A ufw6-user-limit -m limit --limit 3/minute -j LOG --log-prefix "[UFW LIMIT BLOCK] "
-A ufw6-user-limit -j REJECT
-A ufw6-user-limit-accept -j ACCEPT

COMMIT
```

## ufw-defaults
exit=0; optional=False
```text
IPV6=yes


DEFAULT_INPUT_POLICY="DROP"


DEFAULT_OUTPUT_POLICY="ACCEPT"


DEFAULT_FORWARD_POLICY="DROP"



DEFAULT_APPLICATION_POLICY="SKIP"



MANAGE_BUILTINS=no




IPT_SYSCTL=/etc/ufw/sysctl.conf










IPT_MODULES=""
```

## ufw-enabled
exit=0; optional=False
```text
ENABLED=yes


LOGLEVEL=low
```

## ufw-file-ownership
exit=0; optional=False
```text
root:root 755 '/etc/ufw'
root:root 644 '/etc/default/ufw'
root:root 644 '/etc/ufw/ufw.conf'
root:root 640 '/etc/ufw/before.rules'
root:root 640 '/etc/ufw/before6.rules'
root:root 640 '/etc/ufw/user.rules'
root:root 640 '/etc/ufw/user6.rules'
root:root 640 '/etc/ufw/after.rules'
root:root 640 '/etc/ufw/after6.rules'
```

## ufw-service
exit=0; optional=False
```text
enabled
```

## ufw-unit
exit=0; optional=False
Private-only: inspect on host; share a manually redacted result if needed.

## ufw-hooks
exit=0; optional=True
Private-only: inspect on host; share a manually redacted result if needed.

## addresses
exit=0; optional=False
```text
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback MAC_1 brd MAC_1 promiscuity 0  allmulti 0 minmtu 0 maxmtu 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 524280 tso_max_segs 65535 gro_max_size 65536 
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host noprefixroute 
       valid_lft forever preferred_lft forever
2: enp3s0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc fq_codel state DOWN group default qlen 1000
    link/ether MAC_2 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 9194 numtxqueues 1 numrxqueues 1 gso_max_size 64000 gso_max_segs 64 tso_max_size 64000 tso_max_segs 64 gro_max_size 65536 parentbus pci parentdev 0000:03:00.0 
3: wlp0s20f3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether MAC_4 brd MAC_3 promiscuity 0  allmulti 0 minmtu 256 maxmtu 2304 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 parentbus pci parentdev 0000:00:14.3 
    inet 192.168.50.178/24 brd 192.168.50.255 scope global dynamic noprefixroute wlp0s20f3
       valid_lft 83045sec preferred_lft 83045sec
    inet6 fe80::102c:d847:ccb:e53d/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
4: BRIDGE_1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether MAC_5 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 65535 
    bridge forward_delay 200 hello_time 200 max_age 2000 ageing_time 30000 stp_state 1 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.52:54:0:4e:d7:52 designated_root 8000.52:54:0:4e:d7:52 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    1.95 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  214.95 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address MAC_6 mcast_snooping 1 no_linklocal_learn 0 mcast_vlan_snooping 0 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet 192.168.231.1/24 brd 192.168.231.255 scope global BRIDGE_1
       valid_lft forever preferred_lft forever
5: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether MAC_7 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 65535 
    bridge forward_delay 200 hello_time 200 max_age 2000 ageing_time 30000 stp_state 1 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.52:54:0:45:c1:37 designated_root 8000.52:54:0:45:c1:37 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.00 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  215.17 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address MAC_6 mcast_snooping 1 no_linklocal_learn 0 mcast_vlan_snooping 0 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0
       valid_lft forever preferred_lft forever
6: TAP_1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master BRIDGE_1 state UNKNOWN group default qlen 1000
    link/ether MAC_8 brd MAC_3 promiscuity 1  allmulti 1 minmtu 68 maxmtu 65521 
    tun type tap pi off vnet_hdr on persist off 
    bridge_slave state forwarding priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8001 port_no 0x1 designated_port 32769 designated_cost 0 designated_bridge 8000.52:54:0:4e:d7:52 designated_root 8000.52:54:0:4e:d7:52 hold_timer    0.95 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on bcast_flood on mcast_to_unicast off neigh_suppress off group_fwd_mask 0 group_fwd_mask_str 0x0 vlan_tunnel off isolated off locked off numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet6 fe80::fc54:ff:fed9:c270/64 scope link 
       valid_lft forever preferred_lft forever
```

## routes-4
exit=0; optional=False
```text
default via 192.168.50.1 dev wlp0s20f3 proto dhcp src 192.168.50.178 metric 600 
192.168.50.0/24 dev wlp0s20f3 proto kernel scope link src 192.168.50.178 metric 600 
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown 
192.168.231.0/24 dev BRIDGE_1 proto kernel scope link src 192.168.231.1 
local 127.0.0.0/8 dev lo table local proto kernel scope host src 127.0.0.1 
local 127.0.0.1 dev lo table local proto kernel scope host src 127.0.0.1 
broadcast 127.255.255.255 dev lo table local proto kernel scope link src 127.0.0.1 
local 192.168.50.178 dev wlp0s20f3 table local proto kernel scope host src 192.168.50.178 
broadcast 192.168.50.255 dev wlp0s20f3 table local proto kernel scope link src 192.168.50.178 
local 192.168.122.1 dev virbr0 table local proto kernel scope host src 192.168.122.1 
broadcast 192.168.122.255 dev virbr0 table local proto kernel scope link src 192.168.122.1 linkdown 
local 192.168.231.1 dev BRIDGE_1 table local proto kernel scope host src 192.168.231.1 
broadcast 192.168.231.255 dev BRIDGE_1 table local proto kernel scope link src 192.168.231.1
```

## policy-4
exit=0; optional=False
```text
0:	from all lookup local
32766:	from all lookup main
32767:	from all lookup default
```

## routes-6
exit=0; optional=False
```text
fe80::/64 dev TAP_1 proto kernel metric 256 pref medium
fe80::/64 dev wlp0s20f3 proto kernel metric 1024 pref medium
local ::1 dev lo table local proto kernel metric 0 pref medium
local fe80::102c:d847:ccb:e53d dev wlp0s20f3 table local proto kernel metric 0 pref medium
local fe80::fc54:ff:fed9:c270 dev TAP_1 table local proto kernel metric 0 pref medium
multicast ff00::/8 dev wlp0s20f3 table local proto kernel metric 256 pref medium
multicast ff00::/8 dev TAP_1 table local proto kernel metric 256 pref medium
```

## policy-6
exit=0; optional=False
```text
0:	from all lookup local
32766:	from all lookup main
```

## listeners
exit=0; optional=False
```text
udp UNCONN 0      0       192.168.122.1:53    0.0.0.0:* users:(("dnsmasq",pid=1727,fd=5))         
udp UNCONN 0      0       192.168.231.1:53    0.0.0.0:* users:(("dnsmasq",pid=1691,fd=5))         
udp UNCONN 0      0          127.0.0.54:53    0.0.0.0:* users:(("systemd-resolve",pid=1079,fd=16))
udp UNCONN 0      0       127.0.0.53%lo:53    0.0.0.0:* users:(("systemd-resolve",pid=1079,fd=14))
udp UNCONN 0      0      0.0.0.0%virbr0:67    0.0.0.0:* users:(("dnsmasq",pid=1727,fd=3))         
udp UNCONN 0      0      0.0.0.0%BRIDGE_1:67    0.0.0.0:* users:(("dnsmasq",pid=1691,fd=3))         
udp UNCONN 0      0             0.0.0.0:34554 0.0.0.0:* users:(("avahi-daemon",pid=1142,fd=14))   
udp UNCONN 0      0             0.0.0.0:5353  0.0.0.0:* users:(("avahi-daemon",pid=1142,fd=12))   
udp UNCONN 0      0                [::]:5353     [::]:* users:(("avahi-daemon",pid=1142,fd=13))   
udp UNCONN 0      0                [::]:44345    [::]:* users:(("avahi-daemon",pid=1142,fd=15))   
tcp LISTEN 0      4096    127.0.0.53%lo:53    0.0.0.0:* users:(("systemd-resolve",pid=1079,fd=15))
tcp LISTEN 0      32      192.168.231.1:53    0.0.0.0:* users:(("dnsmasq",pid=1691,fd=6))         
tcp LISTEN 0      128         127.0.0.1:45689 0.0.0.0:* users:(("ssh",pid=5598,fd=4))             
tcp LISTEN 0      1           127.0.0.1:5900  0.0.0.0:* users:(("qemu-system-x86",pid=5161,fd=11))
tcp LISTEN 0      32      192.168.122.1:53    0.0.0.0:* users:(("dnsmasq",pid=1727,fd=6))         
tcp LISTEN 0      4096       127.0.0.54:53    0.0.0.0:* users:(("systemd-resolve",pid=1079,fd=17))
tcp LISTEN 0      4096        127.0.0.1:631   0.0.0.0:* users:(("cupsd",pid=1492,fd=8))           
tcp LISTEN 0      4096            [::1]:631      [::]:* users:(("cupsd",pid=1492,fd=7))
```

## forwarding
exit=0; optional=False
```text
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 0
```

## domain-state
exit=0; optional=False
```text
running
```

## domain-info
exit=0; optional=False
```text
Id:             1
Name:           DOMAIN_1
UUID:           UUID_2
OS Type:        hvm
State:          running
CPU(s):         8
CPU time:       3100.7s
Max memory:     25165824 KiB
Used memory:    25165824 KiB
Persistent:     yes
Autostart:      disable
Managed save:   no
Security model: apparmor
Security DOI:   0
Security label: libvirt-UUID_2 (enforcing)
```

## network-info
exit=0; optional=False
```text
Name:           NETWORK_1
UUID:           UUID_3
Active:         yes
Persistent:     yes
Autostart:      yes
Bridge:         BRIDGE_1
```

## apparmor-status
exit=0; optional=False
```text
apparmor module is loaded.
129 profiles are loaded.
31 profiles are in enforce mode.
   /usr/bin/man
   /usr/lib/NetworkManager/nm-dhcp-client.action
   /usr/lib/NetworkManager/nm-dhcp-helper
   /usr/lib/connman/scripts/dhclient-script
   /usr/lib/cups/backend/cups-pdf
   /usr/lib/lightdm/lightdm-guest-session
   /usr/lib/lightdm/lightdm-guest-session//chromium
   /usr/sbin/cups-browsed
   /usr/sbin/cupsd
   /usr/sbin/cupsd//third_party
   /{,usr/}sbin/dhclient
   libreoffice-senddoc
   libreoffice-soffice//gpg
   libreoffice-xpdfimport
   libvirt-UUID_2
   libvirt-UUID_2//passt
   libvirtd
   libvirtd//qemu_bridge_helper
   lsb_release
   man_filter
   man_groff
   nvidia_modprobe
   nvidia_modprobe//kmod
   plasmashell
   plasmashell//QtWebEngineProcess
   rsyslogd
   swtpm
   tcpdump
   unix-chkpwd
   unprivileged_userns
   virt-aa-helper
6 profiles are in complain mode.
   libreoffice-oosplash
   libreoffice-soffice
   transmission-cli
   transmission-daemon
   transmission-gtk
   transmission-qt
0 profiles are in prompt mode.
0 profiles are in kill mode.
92 profiles are in unconfined mode.
   1password
   Discord
   MongoDB Compass
   QtWebEngineProcess
   balena-etcher
   brave
   brave-browser-stable
   buildah
   cam
   ch-checkns
   ch-run
   chrome
   crun
   devhelp
   element-desktop
   epiphany
   evolution
   firefox
   flatpak
   foliate
   geary
   github-desktop
   goldendict
   ipa_verify
   kchmviewer
   keybase
   lc-compliance
   libcamerify
   linux-sandbox
   loupe
   lxc-attach
   lxc-create
   lxc-destroy
   lxc-execute
   lxc-stop
   lxc-unshare
   lxc-usernsexec
   mint-chromium
   mmdebstrap
   msedge
   nautilus
   notepadqq
   obsidian
   opam
   opera
   pageedit
   podman
   polypane
   privacybrowser
   qcam
   qmapshack
   qutebrowser
   rootlesskit
   rpm
   rssguard
   runc
   sbuild
   sbuild-abort
   sbuild-adduser
   sbuild-apt
   sbuild-checkpackages
   sbuild-clean
   sbuild-createchroot
   sbuild-destroychroot
   sbuild-distupgrade
   sbuild-hold
   sbuild-shell
   sbuild-unhold
   sbuild-update
   sbuild-upgrade
   scide
   signal-desktop
   slack
   slirp4netns
   steam
   stress-ng
   surfshark
   systemd-coredump
   thunderbird
   toybox
   trinity
   tup
   tuxedo-control-center
   userbindmount
   uwsgi-core
   vdens
   virtiofsd
   vivaldi-bin
   vpnns
   vscode
   wike
   wpcom
39 processes have profiles defined.
5 processes are in enforce mode.
   /usr/sbin/cups-browsed (1609) 
   /usr/sbin/cupsd (1492) 
   /usr/bin/qemu-system-x86_64 (5161) libvirt-UUID_2
   /usr/sbin/libvirtd (1496) libvirtd
   /usr/sbin/rsyslogd (1328) rsyslogd
0 processes are in complain mode.
0 processes are in prompt mode.
0 processes are in kill mode.
34 processes are unconfined but have a profile defined.
   /usr/lib/firefox/firefox-bin (6027) firefox
   /usr/lib/firefox/crashhelper (6034) firefox
   /usr/lib/firefox/firefox-bin (6114) firefox
   /usr/lib/firefox/firefox-bin (6121) firefox
   /usr/lib/firefox/firefox-bin (6141) firefox
   /usr/lib/firefox/firefox-bin (6150) firefox
   /usr/lib/firefox/firefox-bin (6221) firefox
   /usr/lib/firefox/firefox-bin (6283) firefox
   /usr/lib/firefox/firefox-bin (6301) firefox
   /usr/lib/firefox/firefox-bin (6307) firefox
   /usr/lib/firefox/firefox-bin (6314) firefox
   /usr/lib/firefox/firefox-bin (12027) firefox
   /usr/lib/firefox/firefox-bin (12033) firefox
   /usr/lib/firefox/firefox-bin (13285) firefox
   /usr/lib/firefox/firefox-bin (13795) firefox
   /usr/lib/firefox/firefox-bin (13857) firefox
   /usr/lib/firefox/firefox-bin (13964) firefox
   /usr/share/code/code (5292) vscode
   /usr/share/code/code (5295) vscode
   /usr/share/code/code (5296) vscode
   /usr/share/code/code (5298) vscode
   /usr/share/code/chrome_crashpad_handler (5314) vscode
   /usr/share/code/code (5329) vscode
   /usr/share/code/code (5332) vscode
   /usr/share/code/code (5361) vscode
   /usr/share/code/code (5408) vscode
   /usr/share/code/code (5441) vscode
   /usr/bin/dash (5461) vscode
   /usr/bin/ssh (5464) vscode
   /usr/share/code/code (5526) vscode
   /usr/share/code/code (5527) vscode
   /usr/bin/dconf (5587) vscode
   /usr/bin/dash (5596) vscode
   /usr/bin/ssh (5598) vscode
0 processes are in mixed mode.
```

## process-labels
exit=0; optional=False
```text
unconfined                      systemd
unconfined                      kthreadd
unconfined                      pool_workqueue_release
unconfined                      kworker/R-rcu_g
unconfined                      kworker/R-rcu_p
unconfined                      kworker/R-slub_
unconfined                      kworker/R-netns
unconfined                      kworker/0:0H-events_highpri
unconfined                      kworker/R-mm_pe
unconfined                      rcu_tasks_kthread
unconfined                      rcu_tasks_rude_kthread
unconfined                      rcu_tasks_trace_kthread
unconfined                      ksoftirqd/0
unconfined                      rcu_preempt
unconfined                      migration/0
unconfined                      idle_inject/0
unconfined                      cpuhp/0
unconfined                      cpuhp/2
unconfined                      idle_inject/2
unconfined                      migration/2
unconfined                      ksoftirqd/2
unconfined                      kworker/2:0H-kblockd
unconfined                      cpuhp/4
unconfined                      idle_inject/4
unconfined                      migration/4
unconfined                      ksoftirqd/4
unconfined                      kworker/4:0H-events_highpri
unconfined                      cpuhp/6
unconfined                      idle_inject/6
unconfined                      migration/6
unconfined                      ksoftirqd/6
unconfined                      kworker/6:0H-kblockd
unconfined                      cpuhp/8
unconfined                      idle_inject/8
unconfined                      migration/8
unconfined                      ksoftirqd/8
unconfined                      kworker/8:0H-events_highpri
unconfined                      cpuhp/10
unconfined                      idle_inject/10
unconfined                      migration/10
unconfined                      ksoftirqd/10
unconfined                      kworker/10:0H-events_highpri
unconfined                      cpuhp/12
unconfined                      idle_inject/12
unconfined                      migration/12
unconfined                      ksoftirqd/12
unconfined                      kworker/12:0H-events_highpri
unconfined                      cpuhp/13
unconfined                      idle_inject/13
unconfined                      migration/13
unconfined                      ksoftirqd/13
unconfined                      kworker/13:0H-events_highpri
unconfined                      cpuhp/14
unconfined                      idle_inject/14
unconfined                      migration/14
unconfined                      ksoftirqd/14
unconfined                      kworker/14:0H-events_highpri
unconfined                      cpuhp/15
unconfined                      idle_inject/15
unconfined                      migration/15
unconfined                      ksoftirqd/15
unconfined                      kworker/15:0H-events_highpri
unconfined                      cpuhp/16
unconfined                      idle_inject/16
unconfined                      migration/16
unconfined                      ksoftirqd/16
unconfined                      kworker/16:0H-events_highpri
unconfined                      cpuhp/17
unconfined                      idle_inject/17
unconfined                      migration/17
unconfined                      ksoftirqd/17
unconfined                      kworker/17:0H-events_highpri
unconfined                      cpuhp/18
unconfined                      idle_inject/18
unconfined                      migration/18
unconfined                      ksoftirqd/18
unconfined                      kworker/18:0H-events_highpri
unconfined                      cpuhp/19
unconfined                      idle_inject/19
unconfined                      migration/19
unconfined                      ksoftirqd/19
unconfined                      kworker/19:0H-events_highpri
unconfined                      cpuhp/1
unconfined                      idle_inject/1
unconfined                      migration/1
unconfined                      ksoftirqd/1
unconfined                      kworker/1:0H-events_highpri
unconfined                      cpuhp/3
unconfined                      idle_inject/3
unconfined                      migration/3
unconfined                      ksoftirqd/3
unconfined                      kworker/3:0H-events_highpri
unconfined                      cpuhp/5
unconfined                      idle_inject/5
unconfined                      migration/5
unconfined                      ksoftirqd/5
unconfined                      kworker/5:0H-events_highpri
unconfined                      cpuhp/7
unconfined                      idle_inject/7
unconfined                      migration/7
unconfined                      ksoftirqd/7
unconfined                      kworker/7:0H-events_highpri
unconfined                      cpuhp/9
unconfined                      idle_inject/9
unconfined                      migration/9
unconfined                      ksoftirqd/9
unconfined                      kworker/9:0H-events_highpri
unconfined                      cpuhp/11
unconfined                      idle_inject/11
unconfined                      migration/11
unconfined                      ksoftirqd/11
unconfined                      kworker/11:0H-events_highpri
unconfined                      kdevtmpfs
unconfined                      kworker/R-inet_
unconfined                      kauditd
unconfined                      kworker/0:2-mm_percpu_wq
unconfined                      kworker/1:2-mm_percpu_wq
unconfined                      khungtaskd
unconfined                      oom_reaper
unconfined                      kworker/R-write
unconfined                      kcompactd0
unconfined                      ksmd
unconfined                      khugepaged
unconfined                      kworker/R-kinte
unconfined                      kworker/R-kbloc
unconfined                      kworker/R-blkcg
unconfined                      irq/9-acpi
unconfined                      kworker/16:1-events
unconfined                      kworker/R-tpm_d
unconfined                      kworker/R-ata_s
unconfined                      kworker/R-md
unconfined                      kworker/R-md_bi
unconfined                      kworker/R-edac-
unconfined                      kworker/R-devfr
unconfined                      watchdogd
unconfined                      kworker/R-quota
unconfined                      kworker/16:1H-kblockd
unconfined                      kswapd0
unconfined                      ecryptfs-kthread
unconfined                      kworker/R-kthro
unconfined                      irq/124-aerdrv
unconfined                      irq/125-aerdrv
unconfined                      irq/125-pciehp
unconfined                      kworker/R-acpi_
unconfined                      hwrng
unconfined                      kworker/R-hfi-u
unconfined                      kworker/R-mld
unconfined                      kworker/5:1H-kblockd
unconfined                      kworker/R-ipv6_
unconfined                      kworker/R-kstrp
unconfined                      kworker/3:1-events
unconfined                      kworker/11:1-inet_frag_wq
unconfined                      kworker/R-crypt
unconfined                      kworker/18:3-events
unconfined                      kworker/R-charg
unconfined                      kworker/15:1H-kblockd
unconfined                      kworker/18:1H-events_highpri
unconfined                      kworker/2:1H
unconfined                      kworker/8:1H-kblockd
unconfined                      kworker/6:1H
unconfined                      kworker/10:1H-kblockd
unconfined                      kworker/13:1H-kblockd
unconfined                      kworker/17:1H-kblockd
unconfined                      kworker/4:1H-kblockd
unconfined                      kworker/11:1H-kblockd
unconfined                      kworker/1:1H-kblockd
unconfined                      kworker/0:1H-kblockd
unconfined                      kworker/7:1H-kblockd
unconfined                      kworker/12:1H-kblockd
unconfined                      kworker/3:1H-kblockd
unconfined                      kworker/14:1H-kblockd
unconfined                      kworker/19:1H-kblockd
unconfined                      kworker/9:1H-kblockd
unconfined                      scsi_eh_0
unconfined                      kworker/R-scsi_
unconfined                      scsi_eh_1
unconfined                      kworker/R-scsi_
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      irq/143-FTCS1000:00
unconfined                      kworker/7:2-rcu_par_gp
unconfined                      nv_queue
unconfined                      nv_queue
unconfined                      nv_open_q
unconfined                      kworker/R-sdhci
unconfined                      irq/145-mmc0
unconfined                      nvidia-modeset/kthread_q
unconfined                      nvidia-modeset/deferred_close_kthread_q
unconfined                      irq/167-nvidia
unconfined                      nvidia
unconfined                      nv_queue
unconfined                      kworker/R-raid5
unconfined                      jbd2/nvme0n1p2-8
unconfined                      kworker/R-ext4-
unconfined                      systemd-journal
unconfined                      systemd-udevd
unconfined                      psimon
unconfined                      irq/168-mei_me
unconfined                      UVM global queue
unconfined                      UVM deferred release queue
unconfined                      kworker/R-cfg80
unconfined                      UVM Tools Event Queue
unconfined                      irq/169-iwlwifi:default_queue
unconfined                      irq/170-iwlwifi:queue_1
unconfined                      irq/171-iwlwifi:queue_2
unconfined                      irq/172-iwlwifi:queue_3
unconfined                      irq/173-iwlwifi:queue_4
unconfined                      irq/174-iwlwifi:queue_5
unconfined                      irq/175-iwlwifi:queue_6
unconfined                      irq/176-iwlwifi:queue_7
unconfined                      irq/177-iwlwifi:queue_8
unconfined                      irq/178-iwlwifi:queue_9
unconfined                      irq/179-iwlwifi:queue_10
unconfined                      irq/180-iwlwifi:queue_11
unconfined                      irq/181-iwlwifi:queue_12
unconfined                      irq/182-iwlwifi:queue_13
unconfined                      irq/183-iwlwifi:queue_14
unconfined                      irq/184-iwlwifi:exception
unconfined                      kworker/R-ttm
unconfined                      card2-crtc0
unconfined                      card2-crtc1
unconfined                      card2-crtc2
unconfined                      card2-crtc3
unconfined                      kworker/6:4-rcu_gp
unconfined                      kworker/3:2-mm_percpu_wq
unconfined                      jbd2/nvme0n1p3-8
unconfined                      kworker/R-ext4-
unconfined                      systemd-resolve
unconfined                      systemd-timesyn
unconfined                      accounts-daemon
unconfined                      sh
unconfined                      avahi-daemon
unconfined                      cron
unconfined                      dbus-daemon
unconfined                      libinput-debug-
unconfined                      grep
unconfined                      sh
unconfined                      irqbalance
unconfined                      polkitd
unconfined                      switcheroo-cont
unconfined                      nvidia-persiste
unconfined                      systemd-logind
unconfined                      systemd-machine
unconfined                      thermald
unconfined                      udisksd
unconfined                      virtlockd
unconfined                      virtlogd
unconfined                      avahi-daemon
unconfined                      NetworkManager
unconfined                      wpa_supplicant
unconfined                      bluetoothd
rsyslogd (enforce)              rsyslogd
unconfined                      ModemManager
unconfined                      psimon
/usr/sbin/cupsd (enforce)       cupsd
libvirtd (enforce)              libvirtd
unconfined                      containerd
unconfined                      kerneloops
unconfined                      kerneloops
unconfined                      colord
unconfined                      agetty
/usr/sbin/cups-browsed (enforce) cups-browsed
unconfined                      dnsmasq
unconfined                      dnsmasq
unconfined                      dnsmasq
unconfined                      dnsmasq
unconfined                      lightdm
unconfined                      Xorg
unconfined                      nvidia-drm/timeline-15
unconfined                      rtkit-daemon
unconfined                      krfcommd
unconfined                      upowerd
unconfined                      lightdm
unconfined                      systemd
unconfined                      (sd-pam)
unconfined                      pipewire
unconfined                      pipewire
unconfined                      wireplumber
unconfined                      pipewire-pulse
unconfined                      gnome-keyring-d
unconfined                      dbus-daemon
unconfined                      mate-session
unconfined                      ibus-daemon
unconfined                      gvfsd
unconfined                      gvfsd-fuse
unconfined                      ibus-dconf
unconfined                      ibus-ui-gtk3
unconfined                      at-spi-bus-laun
unconfined                      ibus-extension-
unconfined                      ibus-x11
unconfined                      ibus-portal
unconfined                      dbus-daemon
unconfined                      at-spi2-registr
unconfined                      xdg-desktop-por
unconfined                      xdg-permission-
unconfined                      xdg-document-po
unconfined                      fusermount3
unconfined                      xdg-desktop-por
unconfined                      dconf-service
unconfined                      xdg-desktop-por
unconfined                      mate-settings-d
unconfined                      ibus-engine-sim
unconfined                      gvfs-udisks2-vo
unconfined                      gvfs-afc-volume
unconfined                      gvfs-mtp-volume
unconfined                      gvfs-gphoto2-vo
unconfined                      gvfs-goa-volume
unconfined                      goa-daemon
unconfined                      goa-identity-se
unconfined                      agent
unconfined                      polkit-mate-aut
unconfined                      mate-volume-con
unconfined                      i3
unconfined                      mate-power-mana
unconfined                      applet.py
unconfined                      nvidia-prime
unconfined                      blueman-applet
unconfined                      mate-screensave
unconfined                      nm-applet
unconfined                      evolution-alarm
unconfined                      hp-systray
unconfined                      hp-systray
unconfined                      sh
unconfined                      xss-lock
unconfined                      evolution-sourc
unconfined                      agent
unconfined                      mintreport-tray
unconfined                      nvidia-prime
unconfined                      evolution-calen
unconfined                      evolution-addre
unconfined                      obexd
unconfined                      blueman-tray
unconfined                      mate-panel
unconfined                      mintmenu
unconfined                      wnck-applet
unconfined                      clock-applet
unconfined                      mate-xapp-statu
unconfined                      mate-multiload-
unconfined                      get_apt_cache.p
unconfined                      get_apt_cache.p
unconfined                      virt-manager
libvirt-UUID_2 (enforce) qemu-system-x86
unconfined                      kvm-pit/5161
unconfined                      mintUpdate
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             chrome_crashpad
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             sh
vscode (unconfined)             ssh
unconfined                      ssh-agent
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             dconf
vscode (unconfined)             sh
vscode (unconfined)             ssh
unconfined                      mate-terminal
unconfined                      bash
unconfined                      ssh
firefox (unconfined)            firefox-bin
firefox (unconfined)            crashhelper
firefox (unconfined)            forkserver
firefox (unconfined)            Socket Process
firefox (unconfined)            Privileged Cont
firefox (unconfined)            RDD Process
firefox (unconfined)            WebExtensions
firefox (unconfined)            Utility Process
firefox (unconfined)            Isolated Web Co
firefox (unconfined)            Isolated Web Co
firefox (unconfined)            Isolated Web Co
unconfined                      kworker/16:0-inet_frag_wq
unconfined                      kworker/15:0-rcu_par_gp
unconfined                      kworker/6:0-events
unconfined                      kworker/2:1-events
unconfined                      speech-dispatch
unconfined                      sd_espeak-ng-mb
unconfined                      sd_espeak-ng
unconfined                      sd_dummy
unconfined                      sd_openjtalk
unconfined                      kworker/12:1-rcu_par_gp
unconfined                      kworker/17:2-mm_percpu_wq
unconfined                      kworker/u40:0-writeback
unconfined                      kworker/14:2-events
unconfined                      kworker/5:1-mm_percpu_wq
unconfined                      kworker/u40:1-events_unbound
unconfined                      kworker/10:0-events
unconfined                      kworker/9:2-mm_percpu_wq
unconfined                      kworker/15:1-events_freezable
unconfined                      kworker/17:0-events
unconfined                      kworker/19:0-mm_percpu_wq
unconfined                      kworker/18:0-mm_percpu_wq
unconfined                      kworker/u41:2-rb_allocator
unconfined                      kworker/8:2-events
unconfined                      kworker/11:2-mm_percpu_wq
unconfined                      kworker/0:0
unconfined                      kworker/4:2-mm_percpu_wq
firefox (unconfined)            Isolated Web Co
firefox (unconfined)            Isolated Web Co
unconfined                      kworker/5:0-mm_percpu_wq
unconfined                      kworker/13:1-events
unconfined                      kworker/9:0-mm_percpu_wq
unconfined                      kworker/1:1-rcu_par_gp
unconfined                      kworker/8:1-inet_frag_wq
unconfined                      kworker/7:1-mm_percpu_wq
unconfined                      kworker/4:0-events
unconfined                      fwupd
unconfined                      kworker/2:0-events
unconfined                      kworker/14:0-events
unconfined                      kworker/19:1-cgroup_free
unconfined                      kworker/10:2-events
unconfined                      kworker/u40:2-events_unbound
unconfined                      kworker/u41:1-rb_allocator
unconfined                      kworker/10:3-events
unconfined                      kworker/12:0-events
unconfined                      kworker/13:2-events
firefox (unconfined)            Isolated Web Co
unconfined                      kworker/17:1-mm_percpu_wq
unconfined                      kworker/14:1-events
unconfined                      kworker/15:2-inet_frag_wq
unconfined                      kworker/16:2-events
unconfined                      bash
unconfined                      kworker/u40:3-events_power_efficient
unconfined                      kworker/2:2-mm_percpu_wq
firefox (unconfined)            Web Content
unconfined                      kworker/6:1-mm_percpu_wq
unconfined                      kworker/8:0
firefox (unconfined)            Web Content
unconfined                      kworker/7:0-inet_frag_wq
firefox (unconfined)            Web Content
unconfined                      kworker/9:1
unconfined                      kworker/u41:0-rb_allocator
unconfined                      python3
unconfined                      (udev-worker)
unconfined                      kworker/13:0
unconfined                      ps
```

## docker-units
exit=0; optional=False
```text
Id=docker.service
LoadState=loaded
ActiveState=inactive
UnitFileState=disabled

Id=docker.socket
LoadState=loaded
ActiveState=inactive
UnitFileState=disabled
```

## docker-policy-files
exit=0; optional=True
```text
root:root 755 '/usr/local/sbin/agent-vm-docker-isolation'
root:root 644 '/etc/systemd/system/docker.service.d/agent-vm-isolation.conf'
```

## docker-packages
exit=0; optional=False
```text
Installed Docker engine/CLI, containerd and runc package records:
containerd.io	hi 	2.1.5-1~ubuntu.24.04~noble
docker-buildx-plugin	ii 	0.37.1-1~ubuntu.24.04~noble
docker-ce	hi 	5:28.5.2-1~ubuntu.24.04~noble
docker-ce-cli	hi 	5:28.5.2-1~ubuntu.24.04~noble
docker-ce-rootless-extras	ii 	5:29.8.2-1~ubuntu.24.04~noble
docker-compose-plugin	ii 	5.6.0-1~ubuntu.24.04~noble
```

## Collection result
COLLECTED: requires human and agent review; not a security verdict.
Review rule ordering, every input/forward path, protocol exceptions, live confinement,
persistent configuration and post-reboot paired probes using the audit runbook.
