# Azure Networking: Field Architect Handbook, Labs & Tools

Enterprise Azure networking guidance covering topology design, routing behavior, failure modes, and platform limits, paired with deployable Bicep and Terraform labs and operational tools.

## Repository contents

### Handbook (`src/content/docs/`, built with Astro 7, Starlight 0.42, and Mermaid 12)

1. **[Foundations](src/content/docs/01-foundations/)**: VNet sizing, IPv4/IPv6 dual-stack planning, Azure route-selection precedence, and hybrid DNS with Azure DNS Private Resolver.
2. **[Core Topologies](src/content/docs/02-core-topologies/)**: Hub-and-spoke vs. Virtual WAN trade-off matrix, Azure Route Server (`ASN 65515`) patterns, Routing Intent, Route Maps, and Azure Virtual Network Manager.
3. **[Hybrid Connectivity](src/content/docs/03-hybrid-connectivity/)**: ExpressRoute dual-peering resiliency, bow-tie failure matrices, FastPath bypass limits, circuit traffic segregation, `ErGwScale` and Availability Zone gateways, and S2S VPN backup.
4. **[Network Security & Private Link](src/content/docs/04-network-security/)**: Azure Firewall vs. NVA high availability and Gateway Load Balancer chaining, plus Private Link DNS governance with Azure Policy and Deployment Stacks.
5. **[Workload Networking](src/content/docs/05-workload-networking/)**: AKS (Azure CNI Overlay, Cilium, Application Gateway for Containers with Gateway API, outbound egress), Azure VMware Solution (Gen 1 and Gen 2), Microsoft Foundry Standard Agent BYO-VNet, and Microsoft Fabric.
6. **[Day-2 Operations, Reviews & Labs](src/content/docs/06-operations-reviews/)**: WAF and CAF review checklists, routing decision matrices, Virtual WAN FAQ, Azure Resource Graph validation queries, and guides for the repository labs and tools.

### Hands-on labs and samples

- **[`labs/aks/`](labs/aks/README.md)**: Azure CNI Overlay, Azure CNI Powered by Cilium, Application Gateway for Containers (Gateway API), outbound egress control, and Linux container networking labs.
- **[`labs/foundry-networking/`](labs/foundry-networking/README.md)**: Microsoft Foundry Standard Agent BYO-VNet Bicep deployment (`build-foundry-standard-agent-vnet.bicep`) and private ML workspace topologies.
- **[`labs/virtual-wan-playground/`](labs/virtual-wan-playground/README.md)**: Multi-region Bicep lab builder (`main.bicep`) for customer-managed hub-and-spoke, Virtual WAN, and Azure Virtual Network Manager topologies.
- **[`samples/bgp-bird/`](samples/bgp-bird/README.md)**: BIRD BGP daemon and VXLAN Linux NVA configurations for Azure Route Server and BGP peering experiments.

### Operational tools

- **[`tools/firewall-monitor/`](tools/firewall-monitor/README.md)**: Real-time Azure Firewall log stream analyzer built with Angular 22, Vitest 5, .NET 8 isolated Azure Functions, Azure Event Hubs, and Bicep deployment templates.
- **[`tools/netbench/`](tools/netbench/README.md)**: Automated intra-zone, cross-zone, and inter-region Azure latency (`qperf`) and throughput (`iperf3`) benchmark suite provisioned with Terraform (`azurerm` 5.13 and `azapi` 2.13), Node.js Azure Functions, and Azure Static Web Apps.

## Local development and verification

```powershell
npm ci
npm run dev       # Start local Astro 7 + Starlight 0.42 dev server
npm run build     # Build static handbook output to dist/
npm run verify    # Check routes, exact-case links/assets, anchors, Mermaid blocks, lockfiles, and archive manifest
```

## Provenance and archive

- **[LICENSE](LICENSE)**: MIT License for this repository.
- **[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)**: Upstream authorship, copyright notices, diagram provenance, and consolidation history across the 11 incorporated source repositories.
- **[`.archive/ARCHIVE_MANIFEST.json`](.archive/ARCHIVE_MANIFEST.json)**: Inventory and SHA-256 digests of 298 deduplicated, obsolete, and archived upstream files packaged into gitignored `.archive/legacy-archive.tar.gz`.


