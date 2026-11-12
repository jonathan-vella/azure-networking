# Azure Networking — Field Architect Handbook, Labs & Tools

An opinionated **Field Architect Handbook** for designing, securing, validating, and operating enterprise Azure networks—paired with deployable hands-on labs and live operational tools.

## What's Inside

### Handbook (`src/content/docs/` — published with Astro Starlight)

1. **[Foundations](src/content/docs/01-foundations/)** — VNet sizing, IPv4/IPv6 dual-stack planning, Azure route-selection precedence, and hybrid DNS with Azure DNS Private Resolver.
2. **[Core Topologies](src/content/docs/02-core-topologies/)** — Hub-and-Spoke vs. Virtual WAN trade-off matrix, Azure Route Server patterns, Routing Intent, Route Maps, and AVNM.
3. **[Hybrid Connectivity](src/content/docs/03-hybrid-connectivity/)** — ExpressRoute resiliency, Bow-Tie failure matrices, FastPath limits, circuit traffic segregation, `ErGwScale` / AZ gateways, and S2S VPN backup.
4. **[Network Security & Private Link](src/content/docs/04-network-security/)** — Azure Firewall vs. NVA HA and Gateway Load Balancer, plus enterprise Private Link DNS topologies with Azure Policy and Deployment Stacks.
5. **[Workload Networking](src/content/docs/05-workload-networking/)** — AKS (CNI Overlay, Cilium, Application Gateway for Containers / Gateway API, egress), Azure VMware Solution (Gen 1 & Gen 2), Microsoft Foundry Standard Agent BYO-VNet, and Microsoft Fabric.
6. **[Day-2 Operations, Reviews & Labs](src/content/docs/06-operations-reviews/)** — WAF/CAF architecture review checklists, routing decision matrices, Architecture FAQ, Resource Graph validation queries, and guides to the repository labs and tools.

### Hands-On Labs & Samples

- **[`labs/aks/`](labs/aks/README.md)** — Azure CNI Overlay, Azure CNI Powered by Cilium, Application Gateway for Containers (Gateway API), outbound egress control, and Linux/container networking fundamentals.
- **[`labs/foundry-networking/`](labs/foundry-networking/README.md)** — Microsoft Foundry Standard Agent BYO-VNet and private ML workspace topologies.
- **[`labs/virtual-wan-playground/`](labs/virtual-wan-playground/README.md)** — Multi-region Bicep lab builder for Hub-and-Spoke, Virtual WAN, and Azure Virtual Network Manager scenarios.
- **[`samples/bgp-bird/`](samples/bgp-bird/README.md)** — BIRD BGP daemon and VXLAN Linux NVA configurations for Route Server / BGP peering experiments.

### Operational Tools

- **[`tools/firewall-monitor/`](tools/firewall-monitor/README.md)** — Real-time Azure Firewall stream analyzer (Angular 20 + .NET 8 isolated Azure Functions + Event Hubs).
- **[`tools/netbench/`](tools/netbench/README.md)** — Automated cross-zone and inter-region Azure latency (`qperf`) and throughput (`iperf3`) benchmark suite (Terraform + Azure Functions + Static Web App).

## Local Development & Verification

```powershell
npm install
npm run dev       # Start local Astro Starlight handbook
npm run build     # Production build to dist/
npm run verify    # Verify internal links, anchors, Mermaid blocks, and archive manifest
```

## Provenance & Archive

- **[LICENSE](LICENSE)** — MIT License for this repository.
- **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)** — Upstream authorship, copyright notices, and consolidation provenance across the 11 incorporated source repositories.
- **[`.archive/ARCHIVE_MANIFEST.json`](.archive/ARCHIVE_MANIFEST.json)** — Inventory and SHA-256 digests of duplicate, obsolete, and retired migration artifacts packaged into gitignored `.archive/legacy-archive.tar.gz`.

