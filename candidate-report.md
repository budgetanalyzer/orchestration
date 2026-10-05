# Host isolation audit candidate
Collection time UTC: 2026-10-05T16:58:47.449548+00:00
NOT A SECURITY PASS. Review privately before sharing. Local addresses,
interface names, chain/set names and process names are retained.
Raw evidence and XML remain on the personal host. No active probes ran.

## ufw-status
exit=0; optional=False
```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)
New profiles: skip

To                         Action      From
--                         ------      ----
67/udp on virbr1           ALLOW IN    68/udp                     # agent VM DHCP
192.168.231.1 53/udp on virbr1 ALLOW IN    Anywhere                   # agent VM DNS UDP
192.168.231.1 53/tcp on virbr1 ALLOW IN    Anywhere                   # agent VM DNS TCP
Anywhere on virbr1         DENY IN     Anywhere                   # deny agent VM to host
Anywhere (v6) on virbr1    DENY IN     Anywhere (v6)              # deny agent VM to host
```

## ufw-numbered
exit=0; optional=False
```text
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 67/udp on virbr1           ALLOW IN    68/udp                     # agent VM DHCP
[ 2] 192.168.231.1 53/udp on virbr1 ALLOW IN    Anywhere                   # agent VM DNS UDP
[ 3] 192.168.231.1 53/tcp on virbr1 ALLOW IN    Anywhere                   # agent VM DNS TCP
[ 4] Anywhere on virbr1         DENY IN     Anywhere                   # deny agent VM to host
[ 5] Anywhere (v6) on virbr1    DENY IN     Anywhere (v6)              # deny agent VM to host
```

## ufw-effective
exit=0; optional=False
```text
IPV4 (raw):

Chain INPUT (policy DROP 2444 packets, 89182 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  962406 1326502814 LIBVIRT_INP  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  912069 1321979743 ufw-before-logging-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  912069 1321979743 ufw-before-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    8618   993192 ufw-after-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    2444    89182 ufw-after-logging-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    2444    89182 ufw-reject-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
    2444    89182 ufw-track-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain FORWARD (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  914457 4067835391 DOCKER-USER  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  914457 4067835391 DOCKER-FORWARD  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  914188 4067787320 LIBVIRT_FWX  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  914188 4067787320 LIBVIRT_FWI  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  412737 98022843 LIBVIRT_FWO  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-before-logging-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-before-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-after-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-after-logging-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-reject-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ufw-track-forward  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain OUTPUT (policy ACCEPT 18 packets, 800 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
  885356 375039429 LIBVIRT_OUT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  885415 375035669 ufw-before-logging-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  885415 375035669 ufw-before-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
   16788  2898285 ufw-after-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
   16788  2898285 ufw-after-logging-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
   16788  2898285 ufw-reject-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
   16788  2898285 ufw-track-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain DOCKER (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  !docker0 docker0  0.0.0.0/0            0.0.0.0/0           

Chain DOCKER-BRIDGE (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DOCKER     0    --  *      docker0  0.0.0.0/0            0.0.0.0/0           

Chain DOCKER-CT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      docker0  0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED

Chain DOCKER-FORWARD (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
  914457 4067835391 DOCKER-CT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  914421 4067809832 DOCKER-ISOLATION-STAGE-1  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
  914421 4067809832 DOCKER-BRIDGE  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
       0        0 ACCEPT     0    --  docker0 *       0.0.0.0/0            0.0.0.0/0           

Chain DOCKER-ISOLATION-STAGE-1 (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DOCKER-ISOLATION-STAGE-2  0    --  docker0 !docker0  0.0.0.0/0            0.0.0.0/0           

Chain DOCKER-ISOLATION-STAGE-2 (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  *      docker0  0.0.0.0/0            0.0.0.0/0           

Chain DOCKER-USER (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 REJECT     0    --  virbr1 br-+    0.0.0.0/0            0.0.0.0/0            ctstate NEW /* deny agent VM to Docker */ reject-with icmp-port-unreachable
       0        0 REJECT     0    --  virbr1 docker0  0.0.0.0/0            0.0.0.0/0            ctstate NEW /* deny agent VM to Docker */ reject-with icmp-port-unreachable

Chain LIBVIRT_FWI (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
  501451 3969764477 ACCEPT     0    --  *      virbr1  0.0.0.0/0            192.168.231.0/24     ctstate RELATED,ESTABLISHED
       0        0 REJECT     0    --  *      virbr1  0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
       0        0 ACCEPT     0    --  *      virbr0  0.0.0.0/0            192.168.122.0/24     ctstate RELATED,ESTABLISHED
       0        0 REJECT     0    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable

Chain LIBVIRT_FWO (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
  412731 98022483 ACCEPT     0    --  virbr1 *       192.168.231.0/24     0.0.0.0/0           
       6      360 REJECT     0    --  virbr1 *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
       0        0 ACCEPT     0    --  virbr0 *       192.168.122.0/24     0.0.0.0/0           
       0        0 REJECT     0    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable

Chain LIBVIRT_FWX (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  virbr1 virbr1  0.0.0.0/0            0.0.0.0/0           
       0        0 ACCEPT     0    --  virbr0 virbr0  0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_INP (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
   50394  4519837 ACCEPT     17   --  virbr1 *       0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  virbr1 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
      31    10368 ACCEPT     17   --  virbr1 *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ACCEPT     6    --  virbr1 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:67
       0        0 ACCEPT     17   --  virbr0 *       0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       0        0 ACCEPT     17   --  virbr0 *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ACCEPT     6    --  virbr0 *       0.0.0.0/0            0.0.0.0/0            tcp dpt:67

Chain LIBVIRT_OUT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     17   --  *      virbr1  0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  *      virbr1  0.0.0.0/0            0.0.0.0/0            tcp dpt:53
      31    10974 ACCEPT     17   --  *      virbr1  0.0.0.0/0            0.0.0.0/0            udp dpt:68
       0        0 ACCEPT     6    --  *      virbr1  0.0.0.0/0            0.0.0.0/0            tcp dpt:68
       0        0 ACCEPT     17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:53
       0        0 ACCEPT     6    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            tcp dpt:53
       0        0 ACCEPT     17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:68
       0        0 ACCEPT     6    --  *      virbr0  0.0.0.0/0            0.0.0.0/0            tcp dpt:68

Chain ufw-after-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-after-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:137
     135    32330 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:138
       0        0 ufw-skip-to-policy-input  6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:139
       0        0 ufw-skip-to-policy-input  6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:445
       9     4192 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:67
       0        0 ufw-skip-to-policy-input  17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:68
    6030   867488 ufw-skip-to-policy-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type BROADCAST

Chain ufw-after-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw-after-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
    2444    89182 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

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
  262684 247893325 ACCEPT     0    --  lo     *       0.0.0.0/0            0.0.0.0/0           
  639828 1072980298 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
       1       40 ufw-logging-deny  0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
       1       40 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 3
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 11
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 12
       0        0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0            icmptype 8
       0        0 ACCEPT     17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp spt:67 dpt:68
    9556  1106080 ufw-not-local  0    --  *      *       0.0.0.0/0            0.0.0.0/0           
     936   111618 ACCEPT     17   --  *      *       0.0.0.0/0            224.0.0.251          udp dpt:5353
       0        0 ACCEPT     17   --  *      *       0.0.0.0/0            239.255.255.250      udp dpt:1900
    8620   994462 ufw-user-input  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-before-logging-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-logging-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-logging-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-before-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
  262686 247893405 ACCEPT     0    --  *      lo      0.0.0.0/0            0.0.0.0/0           
  605941 124243979 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate RELATED,ESTABLISHED
   16788  2898285 ufw-user-output  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-logging-allow (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW ALLOW] "

Chain ufw-logging-deny (2 references)
    pkts      bytes target     prot opt in     out     source               destination         
       1       40 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate INVALID limit: avg 3/min burst 10
       0        0 LOG        0    --  *      *       0.0.0.0/0            0.0.0.0/0            limit: avg 3/min burst 10 LOG flags 0 level 4 prefix "[UFW BLOCK] "

Chain ufw-not-local (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL
    3382   202070 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type MULTICAST
    6174   904010 RETURN     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type BROADCAST
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
    6174   904010 DROP       0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-skip-to-policy-output (0 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain ufw-track-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-track-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-track-output (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
    3231   193860 ACCEPT     6    --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate NEW
   13539  2703625 ACCEPT     17   --  *      *       0.0.0.0/0            0.0.0.0/0            ctstate NEW

Chain ufw-user-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw-user-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 ACCEPT     17   --  virbr1 *       0.0.0.0/0            0.0.0.0/0            udp spt:68 dpt:67
       0        0 ACCEPT     17   --  virbr1 *       0.0.0.0/0            192.168.231.1        udp dpt:53
       0        0 ACCEPT     6    --  virbr1 *       0.0.0.0/0            192.168.231.1        tcp dpt:53
       2     1270 DROP       0    --  virbr1 *       0.0.0.0/0            0.0.0.0/0           

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

Chain PREROUTING (policy ACCEPT 62234 packets, 5722587 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
   50328  4520891 DOCKER     0    --  *      *       0.0.0.0/0            0.0.0.0/0            ADDRTYPE match dst-type LOCAL

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 38544 packets, 4549100 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DOCKER     0    --  *      *       0.0.0.0/0           !127.0.0.0/8          ADDRTYPE match dst-type LOCAL

Chain POSTROUTING (policy ACCEPT 38561 packets, 4550386 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 MASQUERADE  0    --  *      !docker0  172.17.0.0/16        0.0.0.0/0           
   41518  4730874 LIBVIRT_PRT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain DOCKER (2 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 RETURN     0    --  docker0 *       0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
      23     2190 RETURN     0    --  *      *       192.168.231.0/24     224.0.0.0/24        
       0        0 RETURN     0    --  *      *       192.168.231.0/24     IP4_1     
    2909   174604 MASQUERADE  6    --  *      *       192.168.231.0/24    !192.168.231.0/24     masq ports: 1024-65535
      44     3344 MASQUERADE  17   --  *      *       192.168.231.0/24    !192.168.231.0/24     masq ports: 1024-65535
       0        0 MASQUERADE  0    --  *      *       192.168.231.0/24    !192.168.231.0/24    
      23     2190 RETURN     0    --  *      *       192.168.122.0/24     224.0.0.0/24        
       0        0 RETURN     0    --  *      *       192.168.122.0/24     IP4_1     
       0        0 MASQUERADE  6    --  *      *       192.168.122.0/24    !192.168.122.0/24     masq ports: 1024-65535
       0        0 MASQUERADE  17   --  *      *       192.168.122.0/24    !192.168.122.0/24     masq ports: 1024-65535
       0        0 MASQUERADE  0    --  *      *       192.168.122.0/24    !192.168.122.0/24    

Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain FORWARD (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain POSTROUTING (policy ACCEPT 1800013 packets, 4442897836 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
 1800013 4442897836 LIBVIRT_PRT  0    --  *      *       0.0.0.0/0            0.0.0.0/0           

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
      31    10974 CHECKSUM   17   --  *      virbr1  0.0.0.0/0            0.0.0.0/0            udp dpt:68 CHECKSUM fill
       0        0 CHECKSUM   17   --  *      virbr0  0.0.0.0/0            0.0.0.0/0            udp dpt:68 CHECKSUM fill

Chain PREROUTING (policy ACCEPT 1876847 packets, 5394334462 bytes)
    pkts      bytes target     prot opt in     out     source               destination         

Chain OUTPUT (policy ACCEPT 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         


IPV6:

Chain INPUT (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
    1431   182504 LIBVIRT_INP  0    --  *      *       ::/0                 ::/0                
    1432   182580 ufw6-before-logging-input  0    --  *      *       ::/0                 ::/0                
    1432   182580 ufw6-before-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-logging-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-reject-input  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-track-input  0    --  *      *       ::/0                 ::/0                

Chain FORWARD (policy DROP 0 packets, 0 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DOCKER-USER  0    --  *      *       ::/0                 ::/0                
       0        0 DOCKER-FORWARD  0    --  *      *       ::/0                 ::/0                
       0        0 LIBVIRT_FWX  0    --  *      *       ::/0                 ::/0                
       0        0 LIBVIRT_FWI  0    --  *      *       ::/0                 ::/0                
       0        0 LIBVIRT_FWO  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-before-logging-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-before-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-after-logging-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-reject-forward  0    --  *      *       ::/0                 ::/0                
       0        0 ufw6-track-forward  0    --  *      *       ::/0                 ::/0                

Chain OUTPUT (policy ACCEPT 20 packets, 2160 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
     205    21815 LIBVIRT_OUT  0    --  *      *       ::/0                 ::/0                
     206    21891 ufw6-before-logging-output  0    --  *      *       ::/0                 ::/0                
     206    21891 ufw6-before-output  0    --  *      *       ::/0                 ::/0                
     155    18043 ufw6-after-output  0    --  *      *       ::/0                 ::/0                
     155    18043 ufw6-after-logging-output  0    --  *      *       ::/0                 ::/0                
     155    18043 ufw6-reject-output  0    --  *      *       ::/0                 ::/0                
     155    18043 ufw6-track-output  0    --  *      *       ::/0                 ::/0                

Chain DOCKER (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain DOCKER-BRIDGE (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain DOCKER-CT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain DOCKER-FORWARD (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DOCKER-CT  0    --  *      *       ::/0                 ::/0                
       0        0 DOCKER-ISOLATION-STAGE-1  0    --  *      *       ::/0                 ::/0                
       0        0 DOCKER-BRIDGE  0    --  *      *       ::/0                 ::/0                

Chain DOCKER-ISOLATION-STAGE-1 (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain DOCKER-ISOLATION-STAGE-2 (0 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain DOCKER-USER (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 REJECT     0    --  virbr1 br-+    ::/0                 ::/0                 ctstate NEW /* deny agent VM to Docker */ reject-with icmp6-port-unreachable
       0        0 REJECT     0    --  virbr1 docker0  ::/0                 ::/0                 ctstate NEW /* deny agent VM to Docker */ reject-with icmp6-port-unreachable

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
      10      712 ACCEPT     0    --  lo     *       ::/0                 ::/0                
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
      85     4384 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 133 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 134 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 135 HL match HL == 255
       3      216 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 136 HL match HL == 255
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
    1334   177268 ACCEPT     17   --  *      *       ::/0                 ff02::fb             udp dpt:5353
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
      10      712 ACCEPT     0    --  *      lo      ::/0                 ::/0                
       0        0 DROP       0    --  *      *       ::/0                 ::/0                 rt type:0
       0        0 ACCEPT     0    --  *      *       ::/0                 ::/0                 ctstate RELATED,ESTABLISHED
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 1
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 2
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 3
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 4
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 128
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 129
      23     1104 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 133 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 136 HL match HL == 255
       4      288 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 135 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 134 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 141 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 142 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 130
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 131
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 132
      14     1744 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 143
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 148 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       ::/0                 ::/0                 ipv6-icmptype 149 HL match HL == 255
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 151 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 152 HL match HL == 1
       0        0 ACCEPT     58   --  *      *       fe80::/10            ::/0                 ipv6-icmptype 153 HL match HL == 1
     155    18043 ufw6-user-output  0    --  *      *       ::/0                 ::/0                

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
     135    15883 ACCEPT     17   --  *      *       ::/0                 ::/0                 ctstate NEW

Chain ufw6-user-forward (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain ufw6-user-input (1 references)
    pkts      bytes target     prot opt in     out     source               destination         
       0        0 DROP       0    --  virbr1 *       ::/0                 ::/0                

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

Chain POSTROUTING (policy ACCEPT 359 packets, 38418 bytes)
    pkts      bytes target     prot opt in     out     source               destination         
     359    38418 LIBVIRT_PRT  0    --  *      *       ::/0                 ::/0                

Chain LIBVIRT_PRT (1 references)
    pkts      bytes target     prot opt in     out     source               destination         

Chain PREROUTING (policy ACCEPT 1435 packets, 182884 bytes)
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
:POSTROUTING ACCEPT [1800017:4442898212]
:LIBVIRT_PRT - [0:0]
[1800017:4442898212] -A POSTROUTING -j LIBVIRT_PRT
[31:10974] -A LIBVIRT_PRT -o virbr1 -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
[0:0] -A LIBVIRT_PRT -o virbr0 -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
COMMIT


*raw
:PREROUTING ACCEPT [1876851:5394334838]
:OUTPUT ACCEPT [0:0]
COMMIT


*filter
:INPUT DROP [2444:89182]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [18:800]
:DOCKER - [0:0]
:DOCKER-BRIDGE - [0:0]
:DOCKER-CT - [0:0]
:DOCKER-FORWARD - [0:0]
:DOCKER-ISOLATION-STAGE-1 - [0:0]
:DOCKER-ISOLATION-STAGE-2 - [0:0]
:DOCKER-USER - [0:0]
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
[962410:1326503190] -A INPUT -j LIBVIRT_INP
[912073:1321980119] -A INPUT -j ufw-before-logging-input
[912073:1321980119] -A INPUT -j ufw-before-input
[8618:993192] -A INPUT -j ufw-after-input
[2444:89182] -A INPUT -j ufw-after-logging-input
[2444:89182] -A INPUT -j ufw-reject-input
[2444:89182] -A INPUT -j ufw-track-input
[914457:4067835391] -A FORWARD -j DOCKER-USER
[914457:4067835391] -A FORWARD -j DOCKER-FORWARD
[914188:4067787320] -A FORWARD -j LIBVIRT_FWX
[914188:4067787320] -A FORWARD -j LIBVIRT_FWI
[412737:98022843] -A FORWARD -j LIBVIRT_FWO
[0:0] -A FORWARD -j ufw-before-logging-forward
[0:0] -A FORWARD -j ufw-before-forward
[0:0] -A FORWARD -j ufw-after-forward
[0:0] -A FORWARD -j ufw-after-logging-forward
[0:0] -A FORWARD -j ufw-reject-forward
[0:0] -A FORWARD -j ufw-track-forward
[885360:375039805] -A OUTPUT -j LIBVIRT_OUT
[885419:375036045] -A OUTPUT -j ufw-before-logging-output
[885419:375036045] -A OUTPUT -j ufw-before-output
[16788:2898285] -A OUTPUT -j ufw-after-output
[16788:2898285] -A OUTPUT -j ufw-after-logging-output
[16788:2898285] -A OUTPUT -j ufw-reject-output
[16788:2898285] -A OUTPUT -j ufw-track-output
[0:0] -A DOCKER ! -i docker0 -o docker0 -j DROP
[0:0] -A DOCKER-BRIDGE -o docker0 -j DOCKER
[0:0] -A DOCKER-CT -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[914457:4067835391] -A DOCKER-FORWARD -j DOCKER-CT
[914421:4067809832] -A DOCKER-FORWARD -j DOCKER-ISOLATION-STAGE-1
[914421:4067809832] -A DOCKER-FORWARD -j DOCKER-BRIDGE
[0:0] -A DOCKER-FORWARD -i docker0 -j ACCEPT
[0:0] -A DOCKER-ISOLATION-STAGE-1 -i docker0 ! -o docker0 -j DOCKER-ISOLATION-STAGE-2
[0:0] -A DOCKER-ISOLATION-STAGE-2 -o docker0 -j DROP
[0:0] -A DOCKER-USER -i virbr1 -o br-+ -m conntrack --ctstate NEW -m comment "REDACTED_COMMENT" "deny agent VM to Docker" -j REJECT --reject-with icmp-port-unreachable
[0:0] -A DOCKER-USER -i virbr1 -o docker0 -m conntrack --ctstate NEW -m comment "REDACTED_COMMENT" "deny agent VM to Docker" -j REJECT --reject-with icmp-port-unreachable
[501451:3969764477] -A LIBVIRT_FWI -d 192.168.231.0/24 -o virbr1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A LIBVIRT_FWI -o virbr1 -j REJECT --reject-with icmp-port-unreachable
[0:0] -A LIBVIRT_FWI -d 192.168.122.0/24 -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A LIBVIRT_FWI -o virbr0 -j REJECT --reject-with icmp-port-unreachable
[412731:98022483] -A LIBVIRT_FWO -s 192.168.231.0/24 -i virbr1 -j ACCEPT
[6:360] -A LIBVIRT_FWO -i virbr1 -j REJECT --reject-with icmp-port-unreachable
[0:0] -A LIBVIRT_FWO -s 192.168.122.0/24 -i virbr0 -j ACCEPT
[0:0] -A LIBVIRT_FWO -i virbr0 -j REJECT --reject-with icmp-port-unreachable
[0:0] -A LIBVIRT_FWX -i virbr1 -o virbr1 -j ACCEPT
[0:0] -A LIBVIRT_FWX -i virbr0 -o virbr0 -j ACCEPT
[50394:4519837] -A LIBVIRT_INP -i virbr1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr1 -p tcp -m tcp --dport 53 -j ACCEPT
[31:10368] -A LIBVIRT_INP -i virbr1 -p udp -m udp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr1 -p tcp -m tcp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p tcp -m tcp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p udp -m udp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_INP -i virbr0 -p tcp -m tcp --dport 67 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr1 -p tcp -m tcp --dport 53 -j ACCEPT
[31:10974] -A LIBVIRT_OUT -o virbr1 -p udp -m udp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr1 -p tcp -m tcp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p tcp -m tcp --dport 53 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p udp -m udp --dport 68 -j ACCEPT
[0:0] -A LIBVIRT_OUT -o virbr0 -p tcp -m tcp --dport 68 -j ACCEPT
[0:0] -A ufw-after-input -p udp -m udp --dport 137 -j ufw-skip-to-policy-input
[135:32330] -A ufw-after-input -p udp -m udp --dport 138 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p tcp -m tcp --dport 139 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p tcp -m tcp --dport 445 -j ufw-skip-to-policy-input
[9:4192] -A ufw-after-input -p udp -m udp --dport 67 -j ufw-skip-to-policy-input
[0:0] -A ufw-after-input -p udp -m udp --dport 68 -j ufw-skip-to-policy-input
[6030:867488] -A ufw-after-input -m addrtype --dst-type BROADCAST -j ufw-skip-to-policy-input
[0:0] -A ufw-after-logging-forward -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[2444:89182] -A ufw-after-logging-input -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw-before-forward -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 3 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 11 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 12 -j ACCEPT
[0:0] -A ufw-before-forward -p icmp -m icmp --icmp-type 8 -j ACCEPT
[0:0] -A ufw-before-forward -j ufw-user-forward
[262688:247893701] -A ufw-before-input -i lo -j ACCEPT
[639828:1072980298] -A ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[1:40] -A ufw-before-input -m conntrack --ctstate INVALID -j ufw-logging-deny
[1:40] -A ufw-before-input -m conntrack --ctstate INVALID -j DROP
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 3 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 11 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 12 -j ACCEPT
[0:0] -A ufw-before-input -p icmp -m icmp --icmp-type 8 -j ACCEPT
[0:0] -A ufw-before-input -p udp -m udp --sport 67 --dport 68 -j ACCEPT
[9556:1106080] -A ufw-before-input -j ufw-not-local
[936:111618] -A ufw-before-input -d 224.0.0.251/32 -p udp -m udp --dport 5353 -j ACCEPT
[0:0] -A ufw-before-input -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j ACCEPT
[8620:994462] -A ufw-before-input -j ufw-user-input
[262690:247893781] -A ufw-before-output -o lo -j ACCEPT
[605941:124243979] -A ufw-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[16788:2898285] -A ufw-before-output -j ufw-user-output
[0:0] -A ufw-logging-allow -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW ALLOW] "
[1:40] -A ufw-logging-deny -m conntrack --ctstate INVALID -m limit --limit 3/min --limit-burst 10 -j RETURN
[0:0] -A ufw-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw-not-local -m addrtype --dst-type LOCAL -j RETURN
[3382:202070] -A ufw-not-local -m addrtype --dst-type MULTICAST -j RETURN
[6174:904010] -A ufw-not-local -m addrtype --dst-type BROADCAST -j RETURN
[0:0] -A ufw-not-local -m limit --limit 3/min --limit-burst 10 -j ufw-logging-deny
[0:0] -A ufw-not-local -j DROP
[0:0] -A ufw-skip-to-policy-forward -j DROP
[6174:904010] -A ufw-skip-to-policy-input -j DROP
[0:0] -A ufw-skip-to-policy-output -j ACCEPT
[3231:193860] -A ufw-track-output -p tcp -m conntrack --ctstate NEW -j ACCEPT
[13539:2703625] -A ufw-track-output -p udp -m conntrack --ctstate NEW -j ACCEPT
[0:0] -A ufw-user-input -i virbr1 -p udp -m udp --sport 68 --dport 67 -j ACCEPT
[0:0] -A ufw-user-input -d 192.168.231.1/32 -i virbr1 -p udp -m udp --dport 53 -j ACCEPT
[0:0] -A ufw-user-input -d 192.168.231.1/32 -i virbr1 -p tcp -m tcp --dport 53 -j ACCEPT
[2:1270] -A ufw-user-input -i virbr1 -j DROP
[0:0] -A ufw-user-limit -m limit --limit 3/min -j LOG --log-prefix "[UFW LIMIT BLOCK] "
[0:0] -A ufw-user-limit -j REJECT --reject-with icmp-port-unreachable
[0:0] -A ufw-user-limit-accept -j ACCEPT
COMMIT


*nat
:PREROUTING ACCEPT [62234:5722587]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [38545:4549164]
:POSTROUTING ACCEPT [38562:4550450]
:DOCKER - [0:0]
:LIBVIRT_PRT - [0:0]
[50328:4520891] -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
[41519:4730938] -A POSTROUTING -j LIBVIRT_PRT
[0:0] -A DOCKER -i docker0 -j RETURN
[23:2190] -A LIBVIRT_PRT -s 192.168.231.0/24 -d 224.0.0.0/24 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.231.0/24 -d IP4_1/32 -j RETURN
[2909:174604] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -p tcp -j MASQUERADE --to-ports 1024-65535
[44:3344] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -p udp -j MASQUERADE --to-ports 1024-65535
[0:0] -A LIBVIRT_PRT -s 192.168.231.0/24 ! -d 192.168.231.0/24 -j MASQUERADE
[23:2190] -A LIBVIRT_PRT -s 192.168.122.0/24 -d 224.0.0.0/24 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 -d IP4_1/32 -j RETURN
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -p tcp -j MASQUERADE --to-ports 1024-65535
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -p udp -j MASQUERADE --to-ports 1024-65535
[0:0] -A LIBVIRT_PRT -s 192.168.122.0/24 ! -d 192.168.122.0/24 -j MASQUERADE
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
:POSTROUTING ACCEPT [359:38418]
:LIBVIRT_PRT - [0:0]
[359:38418] -A POSTROUTING -j LIBVIRT_PRT
COMMIT


*raw
:PREROUTING ACCEPT [1435:182884]
:OUTPUT ACCEPT [0:0]
COMMIT


*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [20:2160]
:DOCKER - [0:0]
:DOCKER-BRIDGE - [0:0]
:DOCKER-CT - [0:0]
:DOCKER-FORWARD - [0:0]
:DOCKER-ISOLATION-STAGE-1 - [0:0]
:DOCKER-ISOLATION-STAGE-2 - [0:0]
:DOCKER-USER - [0:0]
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
[1431:182504] -A INPUT -j LIBVIRT_INP
[1432:182580] -A INPUT -j ufw6-before-logging-input
[1432:182580] -A INPUT -j ufw6-before-input
[0:0] -A INPUT -j ufw6-after-input
[0:0] -A INPUT -j ufw6-after-logging-input
[0:0] -A INPUT -j ufw6-reject-input
[0:0] -A INPUT -j ufw6-track-input
[0:0] -A FORWARD -j DOCKER-USER
[0:0] -A FORWARD -j DOCKER-FORWARD
[0:0] -A FORWARD -j LIBVIRT_FWX
[0:0] -A FORWARD -j LIBVIRT_FWI
[0:0] -A FORWARD -j LIBVIRT_FWO
[0:0] -A FORWARD -j ufw6-before-logging-forward
[0:0] -A FORWARD -j ufw6-before-forward
[0:0] -A FORWARD -j ufw6-after-forward
[0:0] -A FORWARD -j ufw6-after-logging-forward
[0:0] -A FORWARD -j ufw6-reject-forward
[0:0] -A FORWARD -j ufw6-track-forward
[205:21815] -A OUTPUT -j LIBVIRT_OUT
[206:21891] -A OUTPUT -j ufw6-before-logging-output
[206:21891] -A OUTPUT -j ufw6-before-output
[155:18043] -A OUTPUT -j ufw6-after-output
[155:18043] -A OUTPUT -j ufw6-after-logging-output
[155:18043] -A OUTPUT -j ufw6-reject-output
[155:18043] -A OUTPUT -j ufw6-track-output
[0:0] -A DOCKER-FORWARD -j DOCKER-CT
[0:0] -A DOCKER-FORWARD -j DOCKER-ISOLATION-STAGE-1
[0:0] -A DOCKER-FORWARD -j DOCKER-BRIDGE
[0:0] -A DOCKER-USER -i virbr1 -o br-+ -m conntrack --ctstate NEW -m comment "REDACTED_COMMENT" "deny agent VM to Docker" -j REJECT --reject-with icmp6-port-unreachable
[0:0] -A DOCKER-USER -i virbr1 -o docker0 -m conntrack --ctstate NEW -m comment "REDACTED_COMMENT" "deny agent VM to Docker" -j REJECT --reject-with icmp6-port-unreachable
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
[10:712] -A ufw6-before-input -i lo -j ACCEPT
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
[85:4384] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 133 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 134 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 135 -m hl --hl-eq 255 -j ACCEPT
[3:216] -A ufw6-before-input -p ipv6-icmp -m icmp6 --icmpv6-type 136 -m hl --hl-eq 255 -j ACCEPT
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
[1334:177268] -A ufw6-before-input -d ff02::fb/128 -p udp -m udp --dport 5353 -j ACCEPT
[0:0] -A ufw6-before-input -d ff02::f/128 -p udp -m udp --dport 1900 -j ACCEPT
[0:0] -A ufw6-before-input -j ufw6-user-input
[10:712] -A ufw6-before-output -o lo -j ACCEPT
[0:0] -A ufw6-before-output -m rt --rt-type 0 -j DROP
[0:0] -A ufw6-before-output -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 1 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 2 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 3 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 4 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 128 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 129 -j ACCEPT
[23:1104] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 133 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 136 -m hl --hl-eq 255 -j ACCEPT
[4:288] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 135 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 134 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 141 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 142 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 130 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 131 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 132 -j ACCEPT
[14:1744] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 143 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 148 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -p ipv6-icmp -m icmp6 --icmpv6-type 149 -m hl --hl-eq 255 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 151 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 152 -m hl --hl-eq 1 -j ACCEPT
[0:0] -A ufw6-before-output -s fe80::/10 -p ipv6-icmp -m icmp6 --icmpv6-type 153 -m hl --hl-eq 1 -j ACCEPT
[155:18043] -A ufw6-before-output -j ufw6-user-output
[0:0] -A ufw6-logging-allow -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW ALLOW] "
[0:0] -A ufw6-logging-deny -m conntrack --ctstate INVALID -m limit --limit 3/min --limit-burst 10 -j RETURN
[0:0] -A ufw6-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW BLOCK] "
[0:0] -A ufw6-skip-to-policy-forward -j DROP
[0:0] -A ufw6-skip-to-policy-input -j DROP
[0:0] -A ufw6-skip-to-policy-output -j ACCEPT
[0:0] -A ufw6-track-output -p tcp -m conntrack --ctstate NEW -j ACCEPT
[135:15883] -A ufw6-track-output -p udp -m conntrack --ctstate NEW -j ACCEPT
[0:0] -A ufw6-user-input -i virbr1 -j DROP
[0:0] -A ufw6-user-limit -m limit --limit 3/min -j LOG --log-prefix "[UFW LIMIT BLOCK] "
[0:0] -A ufw6-user-limit -j REJECT --reject-with icmp6-port-unreachable
[0:0] -A ufw6-user-limit-accept -j ACCEPT
COMMIT


*nat
:PREROUTING ACCEPT [320:39549]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [96:10098]
:POSTROUTING ACCEPT [96:10098]
:DOCKER - [0:0]
:LIBVIRT_PRT - [0:0]
[0:0] -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A OUTPUT ! -d ::1/128 -m addrtype --dst-type LOCAL -j DOCKER
[96:10098] -A POSTROUTING -j LIBVIRT_PRT
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
		iifname "lo" counter packets 262696 bytes 247894453 accept # handle 95
		ct state related,established counter packets 639828 bytes 1072980298 accept # handle 97
		ct state invalid counter packets 1 bytes 40 jump ufw-logging-deny # handle 100
		ct state invalid counter packets 1 bytes 40 drop # handle 101
		ip protocol icmp icmp type destination-unreachable counter packets 0 bytes 0 accept # handle 102
		ip protocol icmp icmp type time-exceeded counter packets 0 bytes 0 accept # handle 103
		ip protocol icmp icmp type parameter-problem counter packets 0 bytes 0 accept # handle 104
		ip protocol icmp icmp type echo-request counter packets 0 bytes 0 accept # handle 105
		udp sport 67 udp dport 68 counter packets 0 bytes 0 accept # handle 110
		counter packets 9556 bytes 1106080 jump ufw-not-local # handle 111
		ip daddr 224.0.0.251 udp dport 5353 counter packets 936 bytes 111618 accept # handle 117
		ip daddr 239.255.255.250 udp dport 1900 counter packets 0 bytes 0 accept # handle 118
		counter packets 8620 bytes 994462 jump ufw-user-input # handle 146
	}

	chain ufw-before-output { # handle 5
		oifname "lo" counter packets 262698 bytes 247894533 accept # handle 96
		ct state related,established counter packets 605941 bytes 124243979 accept # handle 98
		counter packets 16788 bytes 2898285 jump ufw-user-output # handle 147
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
		udp dport 138 counter packets 135 bytes 32330 jump ufw-skip-to-policy-input # handle 120
		tcp dport 139 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 121
		tcp dport 445 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 122
		udp dport 67 counter packets 9 bytes 4192 jump ufw-skip-to-policy-input # handle 123
		udp dport 68 counter packets 0 bytes 0 jump ufw-skip-to-policy-input # handle 124
		fib daddr type broadcast counter packets 6030 bytes 867488 jump ufw-skip-to-policy-input # handle 125
	}

	chain ufw-after-output { # handle 8
	}

	chain ufw-after-forward { # handle 9
	}

	chain ufw-after-logging-input { # handle 10
		limit rate 3/minute burst 10 packets counter packets 2444 bytes 89182 log prefix "[UFW BLOCK] " # handle 138
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
		ip protocol tcp ct state new counter packets 3231 bytes 193860 accept # handle 40
		ip protocol udp ct state new counter packets 13539 bytes 2703625 accept # handle 41
	}

	chain ufw-track-forward { # handle 18
	}

	chain INPUT { # handle 19
		type filter hook input priority filter; policy drop;
		counter packets 962418 bytes 1326503942 jump LIBVIRT_INP # handle 150
		counter packets 912081 bytes 1321980871 jump ufw-before-logging-input # handle 20
		counter packets 912081 bytes 1321980871 jump ufw-before-input # handle 21
		counter packets 8618 bytes 993192 jump ufw-after-input # handle 22
		counter packets 2444 bytes 89182 jump ufw-after-logging-input # handle 23
		counter packets 2444 bytes 89182 jump ufw-reject-input # handle 24
		counter packets 2444 bytes 89182 jump ufw-track-input # handle 25
	}

	chain OUTPUT { # handle 26
		type filter hook output priority filter; policy accept;
		counter packets 885368 bytes 375040557 jump LIBVIRT_OUT # handle 152
		counter packets 885427 bytes 375036797 jump ufw-before-logging-output # handle 27
		counter packets 885427 bytes 375036797 jump ufw-before-output # handle 28
		counter packets 16788 bytes 2898285 jump ufw-after-output # handle 29
		counter packets 16788 bytes 2898285 jump ufw-after-logging-output # handle 30
		counter packets 16788 bytes 2898285 jump ufw-reject-output # handle 31
		counter packets 16788 bytes 2898285 jump ufw-track-output # handle 32
	}

	chain FORWARD { # handle 33
		type filter hook forward priority filter; policy drop;
		counter packets 914457 bytes 4067835391 jump DOCKER-USER # handle 211
		counter packets 914457 bytes 4067835391 jump DOCKER-FORWARD # handle 191
		counter packets 914188 bytes 4067787320 jump LIBVIRT_FWX # handle 158
		counter packets 914188 bytes 4067787320 jump LIBVIRT_FWI # handle 156
		counter packets 412737 bytes 98022843 jump LIBVIRT_FWO # handle 154
		counter packets 0 bytes 0 jump ufw-before-logging-forward # handle 34
		counter packets 0 bytes 0 jump ufw-before-forward # handle 35
		counter packets 0 bytes 0 jump ufw-after-forward # handle 36
		counter packets 0 bytes 0 jump ufw-after-logging-forward # handle 37
		counter packets 0 bytes 0 jump ufw-reject-forward # handle 38
		counter packets 0 bytes 0 jump ufw-track-forward # handle 39
	}

	chain ufw-logging-deny { # handle 42
		ct state invalid limit rate 3/minute burst 10 packets counter packets 1 bytes 40 return # handle 140
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW BLOCK] " # handle 141
	}

	chain ufw-logging-allow { # handle 43
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 log prefix "[UFW ALLOW] " # handle 142
	}

	chain ufw-skip-to-policy-input { # handle 44
		counter packets 6174 bytes 904010 drop # handle 47
	}

	chain ufw-skip-to-policy-output { # handle 45
		counter packets 0 bytes 0 accept # handle 48
	}

	chain ufw-skip-to-policy-forward { # handle 46
		counter packets 0 bytes 0 drop # handle 49
	}

	chain ufw-not-local { # handle 94
		fib daddr type local counter packets 0 bytes 0 return # handle 112
		fib daddr type multicast counter packets 3382 bytes 202070 return # handle 113
		fib daddr type broadcast counter packets 6174 bytes 904010 return # handle 114
		limit rate 3/minute burst 10 packets counter packets 0 bytes 0 jump ufw-logging-deny # handle 115
		counter packets 0 bytes 0 drop # handle 116
	}

	chain ufw-user-input { # handle 126
		iifname "virbr1" udp sport 68 udp dport 67 counter packets 0 bytes 0 accept # handle 134
		ip daddr 192.168.231.1 iifname "virbr1" udp dport 53 counter packets 0 bytes 0 accept # handle 135
		ip daddr 192.168.231.1 iifname "virbr1" tcp dport 53 counter packets 0 bytes 0 accept # handle 136
		iifname "virbr1" counter packets 2 bytes 1270 drop # handle 137
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
		iifname "virbr1" udp dport 53 counter packets 50394 bytes 4519837 accept # handle 241
		iifname "virbr1" tcp dport 53 counter packets 0 bytes 0 accept # handle 240
		iifname "virbr1" udp dport 67 counter packets 31 bytes 10368 accept # handle 237
		iifname "virbr1" tcp dport 67 counter packets 0 bytes 0 accept # handle 236
		iifname "virbr0" udp dport 53 counter packets 0 bytes 0 accept # handle 228
		iifname "virbr0" tcp dport 53 counter packets 0 bytes 0 accept # handle 227
		iifname "virbr0" udp dport 67 counter packets 0 bytes 0 accept # handle 224
		iifname "virbr0" tcp dport 67 counter packets 0 bytes 0 accept # handle 223
	}

	chain LIBVIRT_OUT { # handle 151
		oifname "virbr1" udp dport 53 counter packets 0 bytes 0 accept # handle 243
		oifname "virbr1" tcp dport 53 counter packets 0 bytes 0 accept # handle 242
		oifname "virbr1" udp dport 68 counter packets 31 bytes 10974 accept # handle 239
		oifname "virbr1" tcp dport 68 counter packets 0 bytes 0 accept # handle 238
		oifname "virbr0" udp dport 53 counter packets 0 bytes 0 accept # handle 230
		oifname "virbr0" tcp dport 53 counter packets 0 bytes 0 accept # handle 229
		oifname "virbr0" udp dport 68 counter packets 0 bytes 0 accept # handle 226
		oifname "virbr0" tcp dport 68 counter packets 0 bytes 0 accept # handle 225
	}

	chain LIBVIRT_FWO { # handle 153
		ip saddr 192.168.231.0/24 iifname "virbr1" counter packets 412731 bytes 98022483 accept # handle 247
		iifname "virbr1" counter packets 6 bytes 360 reject # handle 244
		ip saddr 192.168.122.0/24 iifname "virbr0" counter packets 0 bytes 0 accept # handle 234
		iifname "virbr0" counter packets 0 bytes 0 reject # handle 231
	}

	chain LIBVIRT_FWI { # handle 155
		ip daddr 192.168.231.0/24 oifname "virbr1" ct state related,established counter packets 501451 bytes 3969764477 accept # handle 248
		oifname "virbr1" counter packets 0 bytes 0 reject # handle 245
		ip daddr 192.168.122.0/24 oifname "virbr0" ct state related,established counter packets 0 bytes 0 accept # handle 235
		oifname "virbr0" counter packets 0 bytes 0 reject # handle 232
	}

	chain LIBVIRT_FWX { # handle 157
		iifname "virbr1" oifname "virbr1" counter packets 0 bytes 0 accept # handle 246
		iifname "virbr0" oifname "virbr0" counter packets 0 bytes 0 accept # handle 233
	}

	chain DOCKER { # handle 185
		iifname != "docker0" oifname "docker0" counter packets 0 bytes 0 drop # handle 213
	}

	chain DOCKER-FORWARD { # handle 186
		counter packets 914457 bytes 4067835391 jump DOCKER-CT # handle 194
		counter packets 914421 bytes 4067809832 jump DOCKER-ISOLATION-STAGE-1 # handle 193
		counter packets 914421 bytes 4067809832 jump DOCKER-BRIDGE # handle 192
		iifname "docker0" counter packets 0 bytes 0 accept # handle 212
	}

	chain DOCKER-BRIDGE { # handle 187
		oifname "docker0" counter packets 0 bytes 0 jump DOCKER # handle 215
	}

	chain DOCKER-CT { # handle 188
		oifname "docker0" ct state related,established counter packets 0 bytes 0 accept # handle 214
	}

	chain DOCKER-ISOLATION-STAGE-1 { # handle 189
		iifname "docker0" oifname != "docker0" counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-2 # handle 216
	}

	chain DOCKER-ISOLATION-STAGE-2 { # handle 190
		oifname "docker0" counter packets 0 bytes 0 drop # handle 217
	}

	chain DOCKER-USER { # handle 210
		iifname "virbr1" oifname "br-*" ct state new  counter packets 0 bytes 0 reject # handle 222
		iifname "virbr1" oifname "docker0" ct state new  counter packets 0 bytes 0 reject # handle 221
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
		iifname "lo" counter packets 10 bytes 712 accept # handle 50
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
		meta l4proto ipv6-icmp icmpv6 type nd-router-solicit ip6 hoplimit 255 counter packets 85 bytes 4384 accept # handle 66
		meta l4proto ipv6-icmp icmpv6 type nd-router-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 67
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-solicit ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 68
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-advert ip6 hoplimit 255 counter packets 3 bytes 216 accept # handle 69
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
		ip6 daddr ff02::fb udp dport 5353 counter packets 1334 bytes 177268 accept # handle 113
		ip6 daddr ff02::f udp dport 1900 counter packets 0 bytes 0 accept # handle 114
		counter packets 0 bytes 0 jump ufw6-user-input # handle 138
	}

	chain ufw6-before-output { # handle 5
		oifname "lo" counter packets 10 bytes 712 accept # handle 51
		rt type 0 counter packets 0 bytes 0 drop # handle 54
		ct state related,established counter packets 0 bytes 0 accept # handle 56
		meta l4proto ipv6-icmp icmpv6 type destination-unreachable counter packets 0 bytes 0 accept # handle 81
		meta l4proto ipv6-icmp icmpv6 type packet-too-big counter packets 0 bytes 0 accept # handle 82
		meta l4proto ipv6-icmp icmpv6 type time-exceeded counter packets 0 bytes 0 accept # handle 83
		meta l4proto ipv6-icmp icmpv6 type parameter-problem counter packets 0 bytes 0 accept # handle 84
		meta l4proto ipv6-icmp icmpv6 type echo-request counter packets 0 bytes 0 accept # handle 85
		meta l4proto ipv6-icmp icmpv6 type echo-reply counter packets 0 bytes 0 accept # handle 86
		meta l4proto ipv6-icmp icmpv6 type nd-router-solicit ip6 hoplimit 255 counter packets 23 bytes 1104 accept # handle 87
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 88
		meta l4proto ipv6-icmp icmpv6 type nd-neighbor-solicit ip6 hoplimit 255 counter packets 4 bytes 288 accept # handle 89
		meta l4proto ipv6-icmp icmpv6 type nd-router-advert ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 90
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 91
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 92
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-query counter packets 0 bytes 0 accept # handle 93
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-report counter packets 0 bytes 0 accept # handle 94
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp icmpv6 type mld-listener-done counter packets 0 bytes 0 accept # handle 95
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" counter packets 14 bytes 1744 accept # handle 96
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 97
		meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 255 counter packets 0 bytes 0 accept # handle 98
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 99
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 100
		ip6 saddr fe80::/10 meta l4proto ipv6-icmp xt match "icmp6" ip6 hoplimit 1 counter packets 0 bytes 0 accept # handle 101
		counter packets 155 bytes 18043 jump ufw6-user-output # handle 139
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
		meta l4proto udp ct state new counter packets 135 bytes 15883 accept # handle 41
	}

	chain ufw6-track-forward { # handle 18
	}

	chain INPUT { # handle 19
		type filter hook input priority filter; policy drop;
		counter packets 1431 bytes 182504 jump LIBVIRT_INP # handle 142
		counter packets 1432 bytes 182580 jump ufw6-before-logging-input # handle 20
		counter packets 1432 bytes 182580 jump ufw6-before-input # handle 21
		counter packets 0 bytes 0 jump ufw6-after-input # handle 22
		counter packets 0 bytes 0 jump ufw6-after-logging-input # handle 23
		counter packets 0 bytes 0 jump ufw6-reject-input # handle 24
		counter packets 0 bytes 0 jump ufw6-track-input # handle 25
	}

	chain OUTPUT { # handle 26
		type filter hook output priority filter; policy accept;
		counter packets 205 bytes 21815 jump LIBVIRT_OUT # handle 144
		counter packets 206 bytes 21891 jump ufw6-before-logging-output # handle 27
		counter packets 206 bytes 21891 jump ufw6-before-output # handle 28
		counter packets 155 bytes 18043 jump ufw6-after-output # handle 29
		counter packets 155 bytes 18043 jump ufw6-after-logging-output # handle 30
		counter packets 155 bytes 18043 jump ufw6-reject-output # handle 31
		counter packets 155 bytes 18043 jump ufw6-track-output # handle 32
	}

	chain FORWARD { # handle 33
		type filter hook forward priority filter; policy drop;
		counter packets 0 bytes 0 jump DOCKER-USER # handle 168
		counter packets 0 bytes 0 jump DOCKER-FORWARD # handle 157
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
		iifname "virbr1" counter packets 0 bytes 0 drop # handle 129
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

	chain DOCKER { # handle 151
	}

	chain DOCKER-FORWARD { # handle 152
		counter packets 0 bytes 0 jump DOCKER-CT # handle 160
		counter packets 0 bytes 0 jump DOCKER-ISOLATION-STAGE-1 # handle 159
		counter packets 0 bytes 0 jump DOCKER-BRIDGE # handle 158
	}

	chain DOCKER-BRIDGE { # handle 153
	}

	chain DOCKER-CT { # handle 154
	}

	chain DOCKER-ISOLATION-STAGE-1 { # handle 155
	}

	chain DOCKER-ISOLATION-STAGE-2 { # handle 156
	}

	chain DOCKER-USER { # handle 167
		iifname "virbr1" oifname "br-*" ct state new  counter packets 0 bytes 0 reject # handle 170
		iifname "virbr1" oifname "docker0" ct state new  counter packets 0 bytes 0 reject # handle 169
	}
}
table ip nat { # handle 3
	chain LIBVIRT_PRT { # handle 1
		ip saddr 192.168.231.0/24 ip daddr 224.0.0.0/24 counter packets 23 bytes 2190 return # handle 40
		ip saddr 192.168.231.0/24 ip daddr IP4_1 counter packets 0 bytes 0 return # handle 39
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 ip protocol tcp counter packets 2909 bytes 174604 masquerade to :1024-65535 # handle 38
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 ip protocol udp counter packets 44 bytes 3344 masquerade to :1024-65535 # handle 37
		ip saddr 192.168.231.0/24 ip daddr != 192.168.231.0/24 counter packets 0 bytes 0 masquerade # handle 36
		ip saddr 192.168.122.0/24 ip daddr 224.0.0.0/24 counter packets 23 bytes 2190 return # handle 35
		ip saddr 192.168.122.0/24 ip daddr IP4_1 counter packets 0 bytes 0 return # handle 34
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 ip protocol tcp counter packets 0 bytes 0 masquerade to :1024-65535 # handle 33
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 ip protocol udp counter packets 0 bytes 0 masquerade to :1024-65535 # handle 32
		ip saddr 192.168.122.0/24 ip daddr != 192.168.122.0/24 counter packets 0 bytes 0 masquerade # handle 31
	}

	chain POSTROUTING { # handle 2
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr 172.17.0.0/16 oifname != "docker0" counter packets 0 bytes 0 masquerade # handle 26
		counter packets 41521 bytes 4731066 jump LIBVIRT_PRT # handle 3
	}

	chain DOCKER { # handle 14
		iifname "docker0" counter packets 0 bytes 0 return # handle 27
	}

	chain PREROUTING { # handle 15
		type nat hook prerouting priority dstnat; policy accept;
		fib daddr type local counter packets 50328 bytes 4520891 jump DOCKER # handle 16
	}

	chain OUTPUT { # handle 17
		type nat hook output priority dstnat; policy accept;
		ip daddr != 127.0.0.0/8 fib daddr type local counter packets 0 bytes 0 jump DOCKER # handle 18
	}
}
table ip mangle { # handle 4
	chain LIBVIRT_PRT { # handle 1
		oifname "virbr1" udp dport 68 counter packets 31 bytes 10974 xt target "CHECKSUM" # handle 7
		oifname "virbr0" udp dport 68 counter packets 0 bytes 0 xt target "CHECKSUM" # handle 6
	}

	chain POSTROUTING { # handle 2
		type filter hook postrouting priority mangle; policy accept;
		counter packets 1800025 bytes 4442898964 jump LIBVIRT_PRT # handle 3
	}
}
table ip6 nat { # handle 5
	chain LIBVIRT_PRT { # handle 1
	}

	chain POSTROUTING { # handle 2
		type nat hook postrouting priority srcnat; policy accept;
		counter packets 96 bytes 10098 jump LIBVIRT_PRT # handle 3
	}

	chain DOCKER { # handle 4
	}

	chain PREROUTING { # handle 5
		type nat hook prerouting priority dstnat; policy accept;
		fib daddr type local counter packets 0 bytes 0 jump DOCKER # handle 6
	}

	chain OUTPUT { # handle 7
		type nat hook output priority dstnat; policy accept;
		ip6 daddr != ::1 fib daddr type local counter packets 0 bytes 0 jump DOCKER # handle 8
	}
}
table ip6 mangle { # handle 6
	chain LIBVIRT_PRT { # handle 1
	}

	chain POSTROUTING { # handle 2
		type filter hook postrouting priority mangle; policy accept;
		counter packets 359 bytes 38418 jump LIBVIRT_PRT # handle 3
	}
}
table ip raw { # handle 7
	chain PREROUTING { # handle 1
		type filter hook prerouting priority raw; policy accept;
	}
}
table ip6 raw { # handle 8
	chain PREROUTING { # handle 1
		type filter hook prerouting priority raw; policy accept;
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
*nat
:PREROUTING ACCEPT [62047:5703057]
:INPUT ACCEPT [50552:4543590]
:OUTPUT ACCEPT [38179:4519155]
:POSTROUTING ACCEPT [41106:4695495]
:DOCKER - [0:0]
[50271:4516035] -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A OUTPUT ! -d 127.0.0.0/8 -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
COMMIT


*filter
:INPUT ACCEPT [958359:1313191849]
:FORWARD ACCEPT [913909:4067730912]
:OUTPUT ACCEPT [881651:374690594]
:DOCKER - [0:0]
:DOCKER-BRIDGE - [0:0]
:DOCKER-CT - [0:0]
:DOCKER-FORWARD - [0:0]
:DOCKER-INTERNAL - [0:0]
:DOCKER-USER - [0:0]
[913909:4067730912] -A FORWARD -j DOCKER-USER
[913909:4067730912] -A FORWARD -j DOCKER-FORWARD
[0:0] -A DOCKER ! -i docker0 -o docker0 -j DROP
[0:0] -A DOCKER-BRIDGE -o docker0 -j DOCKER
[0:0] -A DOCKER-CT -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
[913909:4067730912] -A DOCKER-FORWARD -j DOCKER-CT
[913909:4067730912] -A DOCKER-FORWARD -j DOCKER-INTERNAL
[913909:4067730912] -A DOCKER-FORWARD -j DOCKER-BRIDGE
[0:0] -A DOCKER-FORWARD -i docker0 -j ACCEPT
COMMIT
```

## ip6tables-legacy-save
exit=0; optional=False
```text
*nat
:PREROUTING ACCEPT [315:39032]
:INPUT ACCEPT [315:39032]
:OUTPUT ACCEPT [80:8423]
:POSTROUTING ACCEPT [80:8423]
:DOCKER - [0:0]
[0:0] -A PREROUTING -m addrtype --dst-type LOCAL -j DOCKER
[0:0] -A OUTPUT ! -d ::1/128 -m addrtype --dst-type LOCAL -j DOCKER
COMMIT


*filter
:INPUT ACCEPT [1317:169692]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [109:11031]
:DOCKER - [0:0]
:DOCKER-BRIDGE - [0:0]
:DOCKER-CT - [0:0]
:DOCKER-FORWARD - [0:0]
:DOCKER-INTERNAL - [0:0]
:DOCKER-USER - [0:0]
[0:0] -A FORWARD -j DOCKER-USER
[0:0] -A FORWARD -j DOCKER-FORWARD
[0:0] -A DOCKER-FORWARD -j DOCKER-CT
[0:0] -A DOCKER-FORWARD -j DOCKER-INTERNAL
[0:0] -A DOCKER-FORWARD -j DOCKER-BRIDGE
COMMIT
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


-A ufw-user-input -i virbr1 -p udp --dport 67 --sport 68 -j ACCEPT

-A ufw-user-input -i virbr1 -p udp -d 192.168.231.1 --dport 53 -j ACCEPT

-A ufw-user-input -i virbr1 -p tcp -d 192.168.231.1 --dport 53 -j ACCEPT

-A ufw-user-input -i virbr1 -j DROP


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


-A ufw6-user-input -i virbr1 -j DROP


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
       valid_lft 80753sec preferred_lft 80753sec
    inet6 fe80::102c:d847:ccb:e53d/64 scope link noprefixroute 
       valid_lft forever preferred_lft forever
4: virbr1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether MAC_5 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 65535 
    bridge forward_delay 200 hello_time 200 max_age 2000 ageing_time 30000 stp_state 1 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.52:54:0:4e:d7:52 designated_root 8000.52:54:0:4e:d7:52 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.40 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  141.03 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address MAC_6 mcast_snooping 1 no_linklocal_learn 0 mcast_vlan_snooping 0 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet 192.168.231.1/24 brd 192.168.231.255 scope global virbr1
       valid_lft forever preferred_lft forever
5: virbr0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default qlen 1000
    link/ether MAC_7 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 65535 
    bridge forward_delay 200 hello_time 200 max_age 2000 ageing_time 30000 stp_state 1 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.52:54:0:45:c1:37 designated_root 8000.52:54:0:45:c1:37 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.40 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  272.13 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address MAC_6 mcast_snooping 1 no_linklocal_learn 0 mcast_vlan_snooping 0 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet 192.168.122.1/24 brd 192.168.122.255 scope global virbr0
       valid_lft forever preferred_lft forever
6: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether MAC_8 brd MAC_3 promiscuity 0  allmulti 0 minmtu 68 maxmtu 65535 
    bridge forward_delay 1500 hello_time 200 max_age 2000 ageing_time 30000 stp_state 0 priority 32768 vlan_filtering 0 vlan_protocol 802.1Q bridge_id 8000.MAC_8 designated_root 8000.MAC_8 root_port 0 root_path_cost 0 topology_change 0 topology_change_detected 0 hello_timer    0.00 tcn_timer    0.00 topology_change_timer    0.00 gc_timer  272.13 vlan_default_pvid 1 vlan_stats_enabled 0 vlan_stats_per_port 0 group_fwd_mask 0 group_address MAC_6 mcast_snooping 1 no_linklocal_learn 0 mcast_vlan_snooping 0 mcast_router 1 mcast_query_use_ifaddr 0 mcast_querier 0 mcast_hash_elasticity 16 mcast_hash_max 4096 mcast_last_member_count 2 mcast_startup_query_count 2 mcast_last_member_interval 100 mcast_membership_interval 26000 mcast_querier_interval 25500 mcast_query_interval 12500 mcast_query_response_interval 1000 mcast_startup_query_interval 3125 mcast_stats_enabled 0 mcast_igmp_version 2 mcast_mld_version 1 nf_call_iptables 0 nf_call_ip6tables 0 nf_call_arptables 0 numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
9: tunl0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1000
    link/ipip 0.0.0.0 brd 0.0.0.0 promiscuity 0  allmulti 0 minmtu 0 maxmtu 0 
    ipip any remote any local any ttl inherit nopmtudisc numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
10: vnet0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue master virbr1 state UNKNOWN group default qlen 1000
    link/ether MAC_9 brd MAC_3 promiscuity 1  allmulti 1 minmtu 68 maxmtu 65521 
    tun type tap pi off vnet_hdr on persist off 
    bridge_slave state forwarding priority 32 cost 2 hairpin off guard off root_block off fastleave off learning on flood on port_id 0x8001 port_no 0x1 designated_port 32769 designated_cost 0 designated_bridge 8000.52:54:0:4e:d7:52 designated_root 8000.52:54:0:4e:d7:52 hold_timer    0.00 message_age_timer    0.00 forward_delay_timer    0.00 topology_change_ack 0 config_pending 0 proxy_arp off proxy_arp_wifi off mcast_router 1 mcast_fast_leave off mcast_flood on bcast_flood on mcast_to_unicast off neigh_suppress off group_fwd_mask 0 group_fwd_mask_str 0x0 vlan_tunnel off isolated off locked off numtxqueues 1 numrxqueues 1 gso_max_size 65536 gso_max_segs 65535 tso_max_size 65536 tso_max_segs 65535 gro_max_size 65536 
    inet6 fe80::fc54:ff:fed9:c270/64 scope link 
       valid_lft forever preferred_lft forever
```

## routes-4
exit=0; optional=False
```text
default via 192.168.50.1 dev wlp0s20f3 proto dhcp src 192.168.50.178 metric 600 
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown 
192.168.50.0/24 dev wlp0s20f3 proto kernel scope link src 192.168.50.178 metric 600 
192.168.122.0/24 dev virbr0 proto kernel scope link src 192.168.122.1 linkdown 
192.168.231.0/24 dev virbr1 proto kernel scope link src 192.168.231.1 
local 127.0.0.0/8 dev lo table local proto kernel scope host src 127.0.0.1 
local 127.0.0.1 dev lo table local proto kernel scope host src 127.0.0.1 
broadcast 127.255.255.255 dev lo table local proto kernel scope link src 127.0.0.1 
local 172.17.0.1 dev docker0 table local proto kernel scope host src 172.17.0.1 
broadcast 172.17.255.255 dev docker0 table local proto kernel scope link src 172.17.0.1 linkdown 
local 192.168.50.178 dev wlp0s20f3 table local proto kernel scope host src 192.168.50.178 
broadcast 192.168.50.255 dev wlp0s20f3 table local proto kernel scope link src 192.168.50.178 
local 192.168.122.1 dev virbr0 table local proto kernel scope host src 192.168.122.1 
broadcast 192.168.122.255 dev virbr0 table local proto kernel scope link src 192.168.122.1 linkdown 
local 192.168.231.1 dev virbr1 table local proto kernel scope host src 192.168.231.1 
broadcast 192.168.231.255 dev virbr1 table local proto kernel scope link src 192.168.231.1
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
fe80::/64 dev vnet0 proto kernel metric 256 pref medium
fe80::/64 dev wlp0s20f3 proto kernel metric 1024 pref medium
local ::1 dev lo table local proto kernel metric 0 pref medium
anycast fe80:: dev wlp0s20f3 table local proto kernel metric 0 pref medium
anycast fe80:: dev vnet0 table local proto kernel metric 0 pref medium
local fe80::102c:d847:ccb:e53d dev wlp0s20f3 table local proto kernel metric 0 pref medium
local fe80::fc54:ff:fed9:c270 dev vnet0 table local proto kernel metric 0 pref medium
multicast ff00::/8 dev wlp0s20f3 table local proto kernel metric 256 pref medium
multicast ff00::/8 dev vnet0 table local proto kernel metric 256 pref medium
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
udp UNCONN 0      0       192.168.122.1:53    0.0.0.0:* users:(("dnsmasq",pid=1772,fd=5))          
udp UNCONN 0      0       192.168.231.1:53    0.0.0.0:* users:(("dnsmasq",pid=1736,fd=5))          
udp UNCONN 0      0          127.0.0.54:53    0.0.0.0:* users:(("systemd-resolve",pid=916,fd=16))  
udp UNCONN 0      0       127.0.0.53%lo:53    0.0.0.0:* users:(("systemd-resolve",pid=916,fd=14))  
udp UNCONN 0      0      0.0.0.0%virbr0:67    0.0.0.0:* users:(("dnsmasq",pid=1772,fd=3))          
udp UNCONN 0      0      0.0.0.0%virbr1:67    0.0.0.0:* users:(("dnsmasq",pid=1736,fd=3))          
udp UNCONN 0      0             0.0.0.0:5353  0.0.0.0:* users:(("avahi-daemon",pid=1151,fd=12))    
udp UNCONN 0      0             0.0.0.0:44112 0.0.0.0:* users:(("avahi-daemon",pid=1151,fd=14))    
udp UNCONN 0      0                [::]:33462    [::]:* users:(("avahi-daemon",pid=1151,fd=15))    
udp UNCONN 0      0                [::]:5353     [::]:* users:(("avahi-daemon",pid=1151,fd=13))    
tcp LISTEN 0      32      192.168.122.1:53    0.0.0.0:* users:(("dnsmasq",pid=1772,fd=6))          
tcp LISTEN 0      1           127.0.0.1:5900  0.0.0.0:* users:(("qemu-system-x86",pid=16493,fd=11))
tcp LISTEN 0      32      192.168.231.1:53    0.0.0.0:* users:(("dnsmasq",pid=1736,fd=6))          
tcp LISTEN 0      4096       127.0.0.54:53    0.0.0.0:* users:(("systemd-resolve",pid=916,fd=17))  
tcp LISTEN 0      4096        127.0.0.1:631   0.0.0.0:* users:(("cupsd",pid=1578,fd=8))            
tcp LISTEN 0      128         127.0.0.1:33027 0.0.0.0:* users:(("ssh",pid=346569,fd=4))            
tcp LISTEN 0      128         127.0.0.1:443   0.0.0.0:* users:(("ssh",pid=655143,fd=4))            
tcp LISTEN 0      4096    127.0.0.53%lo:53    0.0.0.0:* users:(("systemd-resolve",pid=916,fd=15))  
tcp LISTEN 0      4096            [::1]:631      [::]:* users:(("cupsd",pid=1578,fd=7))
```

## forwarding
exit=0; optional=False
```text
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

## domain-state
exit=0; optional=False
```text
running
```

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
            "network": "agent-nat",
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
            "network": "agent-nat"
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

## domain-info
exit=0; optional=False
```text
Id:             1
Name:           budget-analyzer-agent
UUID:           UUID_2
OS Type:        hvm
State:          running
CPU(s):         8
CPU time:       60128.2s
Max memory:     25165824 KiB
Used memory:    25165824 KiB
Persistent:     yes
Autostart:      disable
Managed save:   no
Security model: apparmor
Security DOI:   0
Security label: libvirt-UUID_2 (enforcing)
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
  <bridge name="virbr1" stp="on" delay="0" />
  <domain name="REDACTED" />
  <ip address="192.168.231.1" netmask="IP4_2">
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
  <bridge name="virbr1" stp="on" delay="0" />
  <domain name="REDACTED" />
  <ip address="192.168.231.1" netmask="IP4_2">
    <dhcp>
      <range start="192.168.231.128" end="192.168.231.254" />
      <host mac="REDACTED" name="REDACTED" ip="192.168.231.10" />
    </dhcp>
  </ip>
</network>
```

## network-info
exit=0; optional=False
```text
Name:           agent-nat
UUID:           UUID_3
Active:         yes
Persistent:     yes
Autostart:      yes
Bridge:         virbr1
```

## apparmor-status
exit=0; optional=False
```text
apparmor module is loaded.
130 profiles are loaded.
32 profiles are in enforce mode.
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
   docker-default
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
36 processes have profiles defined.
5 processes are in enforce mode.
   /usr/sbin/cups-browsed (1687) 
   /usr/sbin/cupsd (1578) 
   /usr/bin/qemu-system-x86_64 (16493) libvirt-UUID_2
   /usr/sbin/libvirtd (16223) libvirtd
   /usr/sbin/rsyslogd (1308) rsyslogd
0 processes are in complain mode.
0 processes are in prompt mode.
0 processes are in kill mode.
31 processes are unconfined but have a profile defined.
   /usr/lib/firefox/firefox-bin (656700) firefox
   /usr/lib/firefox/crashhelper (656706) firefox
   /usr/lib/firefox/firefox-bin (656786) firefox
   /usr/lib/firefox/firefox-bin (656793) firefox
   /usr/lib/firefox/firefox-bin (656813) firefox
   /usr/lib/firefox/firefox-bin (656821) firefox
   /usr/lib/firefox/firefox-bin (656909) firefox
   /usr/lib/firefox/firefox-bin (656965) firefox
   /usr/lib/firefox/firefox-bin (656982) firefox
   /usr/lib/firefox/firefox-bin (658072) firefox
   /usr/lib/firefox/firefox-bin (659136) firefox
   /usr/lib/firefox/firefox-bin (659141) firefox
   /usr/lib/firefox/firefox-bin (659254) firefox
   /usr/lib/firefox/firefox-bin (659322) firefox
   /usr/share/code/code (346401) vscode
   /usr/share/code/code (346404) vscode
   /usr/share/code/code (346405) vscode
   /usr/share/code/code (346407) vscode
   /usr/share/code/chrome_crashpad_handler (346423) vscode
   /usr/share/code/code (346439) vscode
   /usr/share/code/code (346442) vscode
   /usr/share/code/code (346464) vscode
   /usr/share/code/code (346512) vscode
   /usr/share/code/code (346542) vscode
   /usr/bin/dash (346562) vscode
   /usr/bin/ssh (346565) vscode
   /usr/bin/dash (346567) vscode
   /usr/bin/ssh (346569) vscode
   /usr/share/code/code (346610) vscode
   /usr/share/code/code (346611) vscode
   /usr/bin/dconf (346669) vscode
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
unconfined                      kworker/2:0H-events_highpri
unconfined                      cpuhp/4
unconfined                      idle_inject/4
unconfined                      migration/4
unconfined                      ksoftirqd/4
unconfined                      kworker/4:0H-events_highpri
unconfined                      cpuhp/6
unconfined                      idle_inject/6
unconfined                      migration/6
unconfined                      ksoftirqd/6
unconfined                      kworker/6:0H-events_highpri
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
unconfined                      kworker/1:0H-kblockd
unconfined                      cpuhp/3
unconfined                      idle_inject/3
unconfined                      migration/3
unconfined                      ksoftirqd/3
unconfined                      kworker/3:0H-events_highpri
unconfined                      cpuhp/5
unconfined                      idle_inject/5
unconfined                      migration/5
unconfined                      ksoftirqd/5
unconfined                      kworker/5:0H-kblockd
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
unconfined                      kworker/R-tpm_d
unconfined                      kworker/R-ata_s
unconfined                      kworker/R-md
unconfined                      kworker/R-md_bi
unconfined                      kworker/R-edac-
unconfined                      kworker/R-devfr
unconfined                      watchdogd
unconfined                      kworker/R-quota
unconfined                      kworker/1:1H
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
unconfined                      kworker/6:1H-kblockd
unconfined                      kworker/R-ipv6_
unconfined                      kworker/R-kstrp
unconfined                      kworker/R-crypt
unconfined                      kworker/R-charg
unconfined                      kworker/18:1H-kblockd
unconfined                      kworker/0:1H-events_highpri
unconfined                      kworker/4:1H-kblockd
unconfined                      kworker/13:1H-kblockd
unconfined                      kworker/14:1H-kblockd
unconfined                      kworker/10:1H-events_highpri
unconfined                      kworker/12:1H-kblockd
unconfined                      kworker/19:1H-kblockd
unconfined                      kworker/3:1H-kblockd
unconfined                      kworker/9:1H-kblockd
unconfined                      kworker/5:1H
unconfined                      kworker/15:1H-kblockd
unconfined                      kworker/17:1H-kblockd
unconfined                      kworker/16:1H-kblockd
unconfined                      kworker/11:1H-kblockd
unconfined                      scsi_eh_0
unconfined                      kworker/R-scsi_
unconfined                      scsi_eh_1
unconfined                      kworker/R-scsi_
unconfined                      kworker/8:1H-events_highpri
unconfined                      kworker/7:1H-kblockd
unconfined                      kworker/R-sdhci
unconfined                      irq/135-mmc0
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      kworker/R-nvme-
unconfined                      irq/144-FTCS1000:00
unconfined                      nv_queue
unconfined                      nv_queue
unconfined                      nv_open_q
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
unconfined                      UVM Tools Event Queue
unconfined                      kworker/R-cfg80
unconfined                      jbd2/nvme0n1p3-8
unconfined                      kworker/R-ext4-
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
unconfined                      systemd-resolve
unconfined                      systemd-timesyn
unconfined                      kworker/R-ttm
unconfined                      card2-crtc0
unconfined                      card2-crtc1
unconfined                      card2-crtc2
unconfined                      card2-crtc3
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
rsyslogd (enforce)              rsyslogd
unconfined                      ModemManager
unconfined                      bluetoothd
/usr/sbin/cupsd (enforce)       cupsd
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
unconfined                      ibus-engine-sim
unconfined                      mate-settings-d
unconfined                      mate-screensave
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
unconfined                      nm-applet
unconfined                      evolution-alarm
unconfined                      hp-systray
unconfined                      hp-systray
unconfined                      evolution-sourc
unconfined                      sh
unconfined                      xss-lock
unconfined                      agent
unconfined                      mintreport-tray
unconfined                      nvidia-prime
unconfined                      obexd
unconfined                      blueman-tray
unconfined                      evolution-calen
unconfined                      evolution-addre
unconfined                      mate-panel
unconfined                      mintmenu
unconfined                      wnck-applet
unconfined                      clock-applet
unconfined                      mate-xapp-statu
unconfined                      mate-multiload-
unconfined                      get_apt_cache.p
unconfined                      get_apt_cache.p
unconfined                      mintUpdate
unconfined                      caja
unconfined                      gvfsd-trash
unconfined                      gvfsd-metadata
unconfined                      virt-manager
libvirtd (enforce)              libvirtd
libvirt-UUID_2 (enforce) qemu-system-x86
unconfined                      kvm-pit/16493
unconfined                      mate-terminal
unconfined                      ssh-agent
unconfined                      fwupd
unconfined                      gpg-agent
unconfined                      speech-dispatch
unconfined                      sd_espeak-ng-mb
unconfined                      sd_espeak-ng
unconfined                      sd_dummy
unconfined                      sd_openjtalk
unconfined                      bash
unconfined                      gvfsd-http
unconfined                      ssh
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
vscode (unconfined)             sh
vscode (unconfined)             ssh
vscode (unconfined)             code
vscode (unconfined)             code
vscode (unconfined)             dconf
unconfined                      kworker/2:2H-events_highpri
unconfined                      bash
unconfined                      bash
unconfined                      kworker/1:1-rcu_par_gp
unconfined                      kworker/13:1-mm_percpu_wq
unconfined                      kworker/17:2-events
unconfined                      kworker/3:1-mm_percpu_wq
unconfined                      kworker/6:1-events
unconfined                      kworker/0:0-i915-unordered
unconfined                      kworker/1:2-events
unconfined                      kworker/16:1-mm_percpu_wq
unconfined                      kworker/14:0-mm_percpu_wq
unconfined                      kworker/18:2-events
unconfined                      kworker/8:0-rcu_gp
unconfined                      kworker/12:2-events
unconfined                      kworker/3:0-mm_percpu_wq
unconfined                      kworker/4:2-events
unconfined                      kworker/2:1-events
unconfined                      kworker/15:3-mm_percpu_wq
unconfined                      kworker/u40:11-events_unbound
unconfined                      ssh
unconfined                      bash
firefox (unconfined)            firefox-bin
firefox (unconfined)            crashhelper
firefox (unconfined)            forkserver
firefox (unconfined)            Socket Process
firefox (unconfined)            Privileged Cont
firefox (unconfined)            RDD Process
firefox (unconfined)            WebExtensions
firefox (unconfined)            Utility Process
firefox (unconfined)            Isolated Web Co
unconfined                      kworker/18:1-rcu_par_gp
unconfined                      kworker/6:2-events
unconfined                      kworker/17:1-rcu_par_gp
unconfined                      kworker/0:2
unconfined                      gvfsd-network
unconfined                      gvfsd-dnssd
unconfined                      kworker/19:2-mm_percpu_wq
firefox (unconfined)            Isolated Web Co
unconfined                      ssh
unconfined                      bash
unconfined                      psimon
unconfined                      kworker/13:0-events
unconfined                      kworker/15:1
unconfined                      kworker/16:0
unconfined                      kworker/u41:1-rb_allocator
unconfined                      kworker/2:0-events
unconfined                      kworker/7:0-mm_percpu_wq
unconfined                      kworker/12:0-rcu_par_gp
firefox (unconfined)            Isolated Web Co
firefox (unconfined)            Web Content
firefox (unconfined)            Web Content
firefox (unconfined)            Web Content
unconfined                      kworker/5:0-mm_percpu_wq
unconfined                      kworker/4:1-events
unconfined                      kworker/11:0-events
unconfined                      kworker/14:1
unconfined                      kworker/8:1-mm_percpu_wq
unconfined                      kworker/u40:2-events_unbound
unconfined                      kworker/9:0-events
unconfined                      kworker/10:1
unconfined                      kworker/19:0
unconfined                      kworker/9:3-events
unconfined                      kworker/5:1-mm_percpu_wq
unconfined                      kworker/9:1-events
unconfined                      kworker/u41:2-rb_allocator
unconfined                      kworker/11:1-mm_percpu_wq
unconfined                      kworker/7:2-events
unconfined                      kworker/10:0-events
unconfined                      kworker/u40:1-events_unbound
unconfined                      kworker/9:2-mm_percpu_wq
unconfined                      kworker/11:2-mm_percpu_wq
unconfined                      kworker/3:2-mm_percpu_wq
unconfined                      kworker/u41:0-rb_allocator
unconfined                      python3
unconfined                      (udev-worker)
unconfined                      kworker/13:2-events
unconfined                      kworker/12:1-mm_percpu_wq
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
exit=1; optional=True
Unavailable or failed; inspect private raw output. Never count this as a denial.

## Collection result
COLLECTED: requires human and agent review; not a security verdict.
Review rule ordering, every input/forward path, protocol exceptions, live confinement,
persistent configuration and post-reboot paired probes using the audit runbook.
