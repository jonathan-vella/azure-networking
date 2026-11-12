# BIRD BGP & VXLAN Linux NVA Samples for Azure Route Server / Virtual WAN

Reference configurations for running a lightweight Linux Network Virtual Appliance (NVA) with **BIRD** and **VXLAN** to test dynamic eBGP route injection, AS-path prepending, default-route origination (`0.0.0.0/1` + `128.0.0.0/1`), and transitive overlay routing with **Azure Route Server** (`ASN 65515`) or **Azure Virtual WAN** BGP peers.

> **Field Architect Handbook:** See **[Core Topologies — Azure Route Server & NVA BGP Patterns](../../src/content/docs/02-core-topologies/)** for Dual-Home / Bow-Tie / No-Loop route filter design and ECMP next-hop behavior.

---

## Files in This Sample

| File | Purpose |
| --- | --- |
| [`bird-east.conf`](bird-east.conf) | Sample BIRD configuration (`ASN 65001`) peering via eBGP `multihop` with both Azure Route Server instances (`172.16.201.4` and `172.16.201.5`, `ASN 65515`) and a remote NVA (`192.168.100.2`, `ASN 65002`) over a VXLAN interface. |
| [`bird-notes.md`](bird-notes.md) | Quickstart commands to install `bird`, load `bird-east.conf`, and inspect session state and RIB exports using `birdc`. |
| [`vxlan-notes.md`](vxlan-notes.md) | Step-by-step setup of a point-to-point UDP `4789` VXLAN tunnel (`vxlan-demo`, VNI `5001`) between East and West Linux NVAs across peered Azure VNets. |
| [`masq.sh`](masq.sh) | Enables Linux kernel `net.ipv4.ip_forward = 1` and configures `iptables` `POSTROUTING` rules that preserve source IPs across RFC 1918 ranges while SNATing (`MASQUERADE`) internet-bound `0.0.0.0/0` egress on `eth0`. |

---

## Key Azure SDN Caveats Demonstrated in `bird-east.conf`

1. **Always Enable eBGP `multihop`**: Even when the NVA subnet and `RouteServerSubnet` (or Virtual WAN Hub router) live in the same VNet, Azure's software-defined fabric routes traffic via the subnet's `.1` virtual gateway (`172.16.25.1`), decrementing TTL or appearing off-link. `multihop;` is mandatory in the `PEERS` template.
2. **Pin `/32` Routes to Peer IPs via the Azure Subnet Gateway (`.1`)**: When advertising `0.0.0.0/0` (or split `0.0.0.0/1` + `128.0.0.0/1`) and syncing routes to the Linux kernel (`protocol kernel { export all; }`), pin explicit `/32` static routes for both Route Server IPs (`172.16.201.4/32` and `172.16.201.5/32`) and remote VXLAN endpoints to the local subnet gateway (`172.16.25.1`) so the NVA never recurses its BGP control plane into its own overlay tunnel.
3. **Filter `/30`–`/32` Host Prefixes Before Exporting to Route Server**: The `to_routeserver` filter drops `/30`–`/32` host routes (`[ 0.0.0.0/0{30,32} ]`) so internal underlay/BGP-peer `/32` helper routes are not accidentally advertised into the VNet routing table (which also protects Azure Route Server's 1,000-route advertisement limit).
