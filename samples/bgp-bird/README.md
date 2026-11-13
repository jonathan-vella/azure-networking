# BIRD 2 BGP and VXLAN Linux NVA samples for Azure Route Server and Virtual WAN

Reference configurations for running a Linux Network Virtual Appliance (NVA) on Ubuntu 24.04 LTS (`noble`) with **BIRD 2 (`bird2`)** and **VXLAN** to test dynamic eBGP route injection, AS-path prepending, split default-route origination (`0.0.0.0/1` + `128.0.0.0/1`), and transitive overlay routing with **Azure Route Server** (`ASN 65515`) or **Azure Virtual WAN** BGP peers.

> **Field Architect Handbook:**
> - **[Hub-Spoke and Azure Route Server (`hub-spoke-and-route-server.md`)](../../src/content/docs/02-core-topologies/hub-spoke-and-route-server.md)** ([live handbook page](https://jonathan-vella.github.io/azure-networking/02-core-topologies/hub-spoke-and-route-server/)) for Dual-Home, Bow-Tie, and No-Loop route filter patterns and ECMP next-hop behavior.
> - **[Azure VMware Solution Networking (`avs-networking.md`)](../../src/content/docs/05-workload-networking/avs-networking.md)** ([live handbook page](https://jonathan-vella.github.io/azure-networking/05-workload-networking/avs-networking/)) for NVA default-route origination (`0.0.0.0/0` vs. `0.0.0.0/1` + `128.0.0.0/1`) and Route Server transit integration.

---

## Files in this sample

| File | Purpose |
| --- | --- |
| [`bird-east.conf`](bird-east.conf) | **BIRD 2 (`bird2`)** configuration (`/etc/bird/bird.conf`, `ASN 65001`) using explicit `ipv4 { ... };` channel blocks, eBGP `multihop` sessions to both Azure Route Server instances (`172.16.201.4` and `172.16.201.5`, `ASN 65515`), `/30`-`/32` export filtering (`to_routeserver`), and a VXLAN peer (`192.168.100.2`, `ASN 65002`). |
| [`bird-notes.md`](bird-notes.md) | Ubuntu 24.04 LTS commands to install `bird2`, validate syntax (`bird -p`), apply non-disruptive reloads (`birdc configure`), and inspect `master4` RIB exports (`birdc show protocols all`). |
| [`vxlan-notes.md`](vxlan-notes.md) | Step-by-step setup of a point-to-point UDP `4789` VXLAN tunnel (`vxlan-demo`, VNI `5001`, MTU `1450`) between East and West Linux NVAs across peered Azure VNets. |
| [`masq.sh`](masq.sh) | Enables Linux kernel `net.ipv4.ip_forward = 1`, detects the default egress NIC (`${WAN_IF:-eth0}`), and applies idempotent `iptables` `POSTROUTING` rules (`iptables -C ... || iptables -A ...`) that preserve RFC 1918 source IPs while SNATing internet-bound `0.0.0.0/0` traffic. |

---

## Key Azure SDN caveats demonstrated in `bird-east.conf`

1. **Always enable eBGP `multihop`:** Even when the NVA subnet and `RouteServerSubnet` (or Virtual WAN Hub router) reside in the same VNet, Azure's software-defined fabric forwards packets through the subnet's `.1` virtual gateway (`172.16.25.1`). `multihop;` is mandatory in `template bgp PEERS`.
2. **Use explicit BIRD 2 `ipv4` channel blocks:** Ubuntu 24.04 LTS replaced legacy `bird` 1.6 with `bird2`. `protocol kernel`, `protocol static`, and `protocol bgp` must declare `ipv4 { import ...; export ...; };` (or `ipv4;` in `protocol static`), and routes install into `master4`.
3. **Pin `/32` routes to peer IPs via the Azure subnet gateway (`.1`):** When originating `0.0.0.0/0` (or split `0.0.0.0/1` + `128.0.0.0/1`) and syncing routes into the Linux kernel (`protocol kernel { ipv4 { export all; }; }`), pin explicit `/32` static routes for both Route Server IPs (`172.16.201.4/32` and `172.16.201.5/32`) and remote VXLAN underlay endpoints (`172.17.25.4/32`) to `172.16.25.1` so BGP never recurses into its own overlay tunnel.
4. **Filter `/30`-`/32` host prefixes before exporting to Route Server:** The `to_routeserver` filter rejects `/30`-`/32` prefixes (`[ 0.0.0.0/0{30,32} ]`) on `routeserver1` and `routeserver2` so internal `/32` peer pins are not advertised into VNet routing tables and do not consume Azure Route Server's 1,000-route advertisement limit.
