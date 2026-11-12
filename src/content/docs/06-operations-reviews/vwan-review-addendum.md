---
title: Virtual WAN Review Verification Playbook
description: Runnable Azure Resource Graph (ARG) KQL queries, Azure CLI commands, Portal checks, and pass/fail criteria for every control in the Virtual WAN Review Checklist.
sidebar:
  order: 2
---

This verification playbook is the operational companion to the [Virtual WAN & Landing Zone Review Checklist](/azure-networking/06-operations-reviews/vwan-review-checklist/). Every section (`A-TOP-*`, `A-RES-*`, `A-RT-*`, `A-SEC-*`, `A-PERF-*`, `A-OPS-*`, `A-GOV-*`) provides the **authoritative Microsoft Learn reference**, **architectural rationale**, **common field misconfigurations**, and **exact Azure Resource Graph (ARG) KQL, `az` CLI, or Portal inspection steps** with explicit pass/fail criteria.

:::note[ARG Coverage Reality Tagging]
Azure Resource Graph does not project every Virtual WAN control-plane child property (such as `routingIntent` or VPN link custom IPsec policies). Controls where ARG lacks coverage are explicitly tagged **`ARG: Not exposed — use az CLI / Portal`** so reviewers never waste time debugging empty KQL projections.
:::

---

## 1. Topology & CAF Landing Zone Verification (`A-TOP`)

### A-TOP-01

- **Checklist Control**: [TOP-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-01) — Platform Connectivity subscription placement.
- **Learn Reference**: [CAF Virtual WAN network topology](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/virtual-wan-network-topology).
- **Common Misconfiguration**: Virtual Hubs or Secured Hub Firewalls scattered across workload landing zone subscriptions, fragmenting RBAC and quota management.
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ (
    'microsoft.network/virtualwans',
    'microsoft.network/virtualhubs',
    'microsoft.network/vpngateways',
    'microsoft.network/expressroutegateways',
    'microsoft.network/p2svpngateways',
    'microsoft.network/azurefirewalls'
  )
| summarize ResourceCount = count(), Types = make_set(type) by subscriptionId, resourceGroup
```

- **Pass / Fail**: **Pass** if 100% of Virtual WAN core resources reside in the designated Platform Connectivity subscription(s); **Fail** if hubs/gateways appear in application workload subscriptions.

### A-TOP-02

- **Checklist Control**: [TOP-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-02) — Unified Resource Group lifecycle boundary.
- **Learn Reference**: [CAF Virtual WAN network topology](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/virtual-wan-network-topology).
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ ('microsoft.network/virtualwans','microsoft.network/virtualhubs','microsoft.network/vpngateways','microsoft.network/expressroutegateways','microsoft.network/p2svpngateways')
| summarize RGs = make_set(resourceGroup), Resources = count() by subscriptionId
```

- **Pass / Fail**: **Pass** if `RGs` aligns with a single governed Resource Group (or cleanly standardized regional RG pattern managed by one IaC stack) without orphaned ad-hoc RGs.

### A-TOP-03

- **Checklist Control**: [TOP-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-03) — Hub CIDR `/23` minimum and non-overlapping IPAM.
- **Learn Reference**: [Virtual WAN FAQ — Hub address space](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-faq) and [VNet Sizing & IPv4/IPv6 Planning](/azure-networking/01-foundations/vnet-and-ip-addressing/).
- **Common Misconfiguration**: Carving `/25` or `/26` hub ranges that block future gateway or NVA deployments, or overlapping a hub CIDR with a legacy branch subnet.
- **Verification (ARG KQL + CLI)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| extend prefix = tostring(properties.addressPrefix)
| extend maskLen = toint(split(prefix, '/')[1])
| project name, location, prefix, maskLen, underSized = (maskLen > 23)
```

- **Pass / Fail**: **Pass** if `maskLen <= 23` (`underSized == false`) on every production hub and cross-checked against enterprise IPAM with zero overlap.

### A-TOP-04

- **Checklist Control**: [TOP-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-04) — Shared services (DNS Private Resolver, AD DS) in a dedicated spoke VNet.
- **Learn Reference**: [DNS & Private Resolver](/azure-networking/01-foundations/dns-and-private-resolver/).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/dnsresolvers'
| project name, location, resourceGroup, vnetId = tostring(properties.virtualNetwork.id)
```

- **Pass / Fail**: **Pass** if DNS Private Resolvers and domain controllers run in a dedicated Shared Services / Identity spoke VNet connected to the hub.

### A-TOP-05

- **Checklist Control**: [TOP-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-05) — Single hub per region unless scale limits require sharding.
- **Learn Reference**: [Azure Virtual WAN service limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-virtual-wan-limits).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| summarize HubCount = count(), HubNames = make_list(name) by location, vwanId = tostring(properties.virtualWan.id)
| where HubCount > 1
```

- **Pass / Fail**: **Pass** if empty (1 hub per region) or if multiple in-region hubs have an approved ADR (e.g., >540 VNet prefixes or strict SD-WAN/NGFW hub separation).

### A-TOP-06

- **Checklist Control**: [TOP-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-06) — ExpressRoute Global Reach vs. vWAN inter-hub transit evaluation.
- **Learn Reference**: [ExpressRoute Global Reach](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-global-reach) and [AVS Networking & Transit](/azure-networking/05-workload-networking/avs-networking/).
- **Verification (`az` CLI)**:

```bash
az network express-route list -o table --query "[].{Name:name, Location:location, Sku:sku.tier, GlobalReach:peerings[].circuitConnections[].circuitConnectionStatus}"
```

- **Pass / Fail**: **Pass** if Global Reach peerings match documented architecture intent (remembering Global Reach bypasses Secured Hub firewalls).

### A-TOP-07

- **Checklist Control**: [TOP-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-07) — Brownfield Hub-and-Spoke to Virtual WAN migration runbook.
- **Learn Reference**: [Migrate from hub-and-spoke to Azure Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/migrate-from-hub-spoke-topology).
- **Verification (`ARG: Not exposed — design artifact`)**: Inspect migration wave runbook, BGP ASN transition plan, and rollback validation steps.
- **Pass / Fail**: **Pass** if coexistence routing symmetry and rollback steps are documented and tested in non-prod; `N/A` for greenfield deployments.

### A-TOP-08

- **Checklist Control**: [TOP-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-08) — Certified SD-WAN / NVA Managed Application hub coexistence.
- **Learn Reference**: [About NVAs in a Virtual WAN hub](https://learn.microsoft.com/en-us/azure/virtual-wan/about-nva-hub).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/networkvirtualappliances'
| project name, location, nvaSku = tostring(properties.nvaSku.vendor), scaleUnit = tostring(properties.nvaSku.bundledScaleUnit), vhubId = tostring(properties.virtualHub.id)
```

- **Pass / Fail**: **Pass** if at most one Routing-Intent-compatible NVA/SaaS pattern exists per hub (no unsupported separate SD-WAN NVA + Cloud NGFW co-deployment in the same hub).

---

## 2. Resiliency & Availability Verification (`A-RES`)

### A-RES-01

- **Checklist Control**: [RES-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-01) — Virtual WAN Standard SKU on all production deployments.
- **Learn Reference**: [WAF Virtual WAN service guide — Reliability](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualwans'
| project name, sku = tostring(properties.type), location, resourceGroup, subscriptionId
| where sku !~ 'Standard'
```

- **Pass / Fail**: **Pass** if query returns **0 rows** (`sku == "Standard"` everywhere).

### A-RES-02

- **Checklist Control**: [RES-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-02) — Multi-region Virtual Hubs (`>= 2` regions).
- **Learn Reference**: [Disaster recovery design for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/disaster-recovery-design).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| summarize Hubs = make_set(name), Regions = make_set(location), RegionCount = dcount(location) by vwanId = tostring(properties.virtualWan.id)
```

- **Pass / Fail**: **Pass** if `RegionCount >= 2` for multi-region production Virtual WANs.

### A-RES-03

- **Checklist Control**: [RES-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-03) — Availability Zone-redundant Gateways.
- **Learn Reference**: [ExpressRoute Resiliency](/azure-networking/03-hybrid-connectivity/expressroute-resiliency/).
- **Verification (`az` CLI — `ARG partial for gateway PIP zones`)**:

```bash
az network vpn-gateway show -n <vpn-gw-name> -g <rg> --query "{name:name, scaleUnits:vpnGatewayScaleUnit, ips:ipConfigurations[].publicIpAddress}" -o json
az network express-route gateway show -n <er-gw-name> -g <rg> --query "{name:name, minUnits:autoScaleConfiguration.bounds.min}" -o json
```

- **Pass / Fail**: **Pass** if gateways are deployed in AZ-enabled regions using zone-redundant configurations (`zones: ["1","2","3"]` on associated Public IPs / AZ gateway deployment).

### A-RES-04

- **Checklist Control**: [RES-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-04) — Active-Active S2S VPN tunnels with BGP on both links.
- **Learn Reference**: [WAF Virtual WAN — Reliability](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability).
- **Verification (`az` CLI)**:

```bash
az network vpn-gateway connection list --gateway-name <vpn-gw-name> -g <rg> \
  --query "[].{Connection:name, Links:vpnLinkConnections[].{Link:name, BgpEnabled:enableBgp, Status:connectionStatus}}" -o json
```

- **Pass / Fail**: **Pass** if every production branch connection terminates `>= 2` `vpnLinkConnections` with `BgpEnabled: true` and `Status: Connected`.

### A-RES-05

- **Checklist Control**: [RES-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-05) — S2S VPN backup behind ExpressRoute with deterministic BGP preference.
- **Learn Reference**: [ExpressRoute Bow-Tie Failures](/azure-networking/03-hybrid-connectivity/expressroute-bowtie-failures/).
- **Verification (ARG KQL + `az` CLI)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| project name, location,
    hasErGw = isnotempty(tostring(properties.expressRouteGateway.id)),
    hasVpnGw = isnotempty(tostring(properties.vpnGateway.id)),
    routingPref = tostring(properties.hubRoutingPreference)
```

- **Pass / Fail**: **Pass** if critical ER hubs also host an active S2S VPN failover path and both Azure (`hubRoutingPreference`) and on-premises BGP (`Local Preference` + `AS-Path Prepend`) prefer ExpressRoute symmetrically.

### A-RES-06

- **Checklist Control**: [RES-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-06) — Hub Routing Infrastructure Units pre-sized above baseline (`~25 min` scale-out latency).
- **Learn Reference**: [Virtual hub routing infrastructure units](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing#hubcapacity).
- **Verification (`az` CLI)**:

```bash
az network vhub show -n <hub-name> -g <rg> \
  --query "{Hub:name, MinRouterUnits:virtualRouterAutoScaleConfiguration.minCapacity, RoutingState:routingState}" -o table
```

- **Pass / Fail**: **Pass** if `MinRouterUnits` is sized above expected burst throughput (3 Gbps/2,000 VMs per unit; default `2` units = 3 Gbps) rather than relying on reactive 25-minute autoscale during traffic surges.

### A-RES-07

- **Checklist Control**: [RES-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-07) — Global P2S VPN profile + `>= 2x` client pool sizing.
- **Learn Reference**: [Design resilience for Point-to-Site VPN](https://learn.microsoft.com/en-us/azure/virtual-wan/point-to-site-how-to).
- **Verification (`az` CLI)**:

```bash
az network p2s-vpn-gateway list -g <rg> \
  --query "[].{Gateway:name, Location:location, Pool:p2SVpnConnectionConfigurations[].vpnClientAddressPool.addressPrefixes}" -o json
```

- **Pass / Fail**: **Pass** if Global (WAN-level) profile is distributed to clients and each regional pool holds `>= 2x` peak concurrent session IPs.

### A-RES-08

- **Checklist Control**: [RES-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-08) — Failure Mode Analysis (FMA) documented.
- **Learn Reference**: [WAF Virtual WAN — Failure mode analysis](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability).
- **Verification (`ARG: Not exposed — design artifact`)**: Inspect customer FMA table covering regional outage, single MSEE failure, CPE failure, BGP route leak, and hub router scale-out delay.
- **Pass / Fail**: **Pass** if blast radius, RTO/RPO, and automated/manual recovery steps are documented for all 5 failure modes.

### A-RES-09

- **Checklist Control**: [RES-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-09) — End-to-end Composite SLA calculated.
- **Verification (`ARG: Not exposed — architecture worksheet`)**: Multiply serial path SLAs (e.g., `Hub 99.95% x ER GW 99.95% x Azure Firewall AZ 99.99% x Dual-Circuit ER 99.95%`).
- **Pass / Fail**: **Pass** if composite SLA meets business-tier targets without hidden single-CPE or non-AZ bottlenecks.

### A-RES-10

- **Checklist Control**: [RES-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-10) — Annual live DR and BGP failover drill executed.
- **Learn Reference**: [Disaster recovery design for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/disaster-recovery-design).
- **Verification (`ARG: Not exposed — operational evidence`)**: Review timestamped failover test report within last 12 months showing measured packet-loss window during ER -> VPN and Hub 1 -> Hub 2 failover.
- **Pass / Fail**: **Pass** if tested within 12 months with zero unresolved asymmetric drops.

---

## 3. Routing Decision Matrix Verification (`A-RT`)

### A-RT-01

- **Checklist Scenario**: [RT-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-01) — Any-to-any default transit (`defaultRouteTable`).
- **Learn Reference**: [About virtual hub routing](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing).
- **Verification (`az` CLI)**:

```bash
az network vhub route-table show --vhub-name <hub-name> -g <rg> -n defaultRouteTable -o json
```

- **Pass / Fail**: **Fail** in production if `defaultRouteTable` runs without Routing Intent or custom isolation when policy mandates East-West/North-South inspection.

### A-RT-02

- **Checklist Scenario**: [RT-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-02) — Internet egress via Azure Firewall (`InternetTraffic` policy).
- **Learn Reference**: [Configure Virtual WAN Hub routing intent and policies](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies).
- **Verification (`az` CLI — `ARG: Not exposed`)**:

```bash
az network vhub routing-intent list --vhub-name <hub-name> -g <rg> -o json
```

- **Pass / Fail**: **Pass** if `routingPolicies` contains `destinations: ["Internet"]` pointing `nextHop` to the hub Azure Firewall resource ID, and `enableInternetSecurity: true` is set on target VNet connections.

### A-RT-03

- **Checklist Scenario**: [RT-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-03) — Internet egress via Cloud NGFW SaaS or certified NVA.
- **Learn Reference**: [Configure Palo Alto Networks Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw#configure-routing).
- **Verification (`az` CLI)**: Run `az network vhub routing-intent list --vhub-name <hub-name> -g <rg> -o json` across **every** regional hub.
- **Pass / Fail**: **Pass** if every regional hub that requires internet breakout has its own local SaaS/NVA `Internet` policy (remembering `0.0.0.0/0` never propagates inter-hub).

### A-RT-04

- **Checklist Scenario**: [RT-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-04) — Intra-region Private inspection (`PrivateTraffic` policy).
- **Learn Reference**: [Virtual WAN & Routing Intent](/azure-networking/02-core-topologies/virtual-wan-and-routing-intent/).
- **Verification (`az` CLI)**:

```bash
az network vhub routing-intent list --vhub-name <hub-name> -g <rg> \
  --query "[].routingPolicies[?contains(join(',',destinations),'PrivateTraffic')]" -o json
```

- **Pass / Fail**: **Pass** if `PrivateTraffic` maps `nextHop` to the hub Azure Firewall, Cloud NGFW SaaS, or eligible NGFW NVA.

### A-RT-05

- **Checklist Scenario**: [RT-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-05) — Inter-hub cross-region Private inspection.
- **Verification (`az` CLI)**: Run `A-RT-04` across **all** hubs in the Virtual WAN and inspect effective routes:

```bash
az network vhub get-effective-routes --name <hub-name> -g <rg> \
  --resource-type RouteTable \
  --resource-id "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualHubs/<hub-name>/hubRouteTables/defaultRouteTable" -o json
```

- **Pass / Fail**: **Pass** if both source and destination hubs enforce `PrivateTraffic` Routing Intent and remote hub prefixes steer symmetrically via each hub's security solution.

### A-RT-06

- **Checklist Scenario**: [RT-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-06) — Routing Intent snapshot governance & `<= 600` local VNet address-space limit.
- **Learn Reference**: [Routing intent — Considerations and limits](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies#considerations).
- **Verification (`az` CLI)**:

```bash
# Snapshot route tables & connections before enabling Routing Intent
az network vhub route-table list --vhub-name <hub-name> -g <rg> -o json > vhub-rt-backup.json
az network vhub connection list --vhub-name <hub-name> -g <rg> -o json > vhub-conn-backup.json
```

- **Pass / Fail**: **Pass** if pre-change JSON backup is stored in version control and total locally connected VNet address prefixes per hub remain `< 540` (90% of the 600-prefix limit).

### A-RT-07

- **Checklist Scenario**: [RT-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-07) — ExpressRoute transit & SKU validation.
- **Learn Reference**: [ExpressRoute FastPath & SKUs](/azure-networking/03-hybrid-connectivity/expressroute-fastpath-and-skus/).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/expressroutecircuits'
| project name, location, tier = tostring(sku.tier), family = tostring(sku.family)
```

- **Pass / Fail**: **Pass** if circuits requiring vWAN transit use `Standard` or `Premium` tier (never `Local` SKU for transit) and ER-to-ER paths have explicit Global Reach or spoke transit design.

### A-RT-08

- **Checklist Scenario**: [RT-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-08) — Branch-to-branch transit (`VPN <-> VPN`, `VPN <-> ER`).
- **Verification (`az` CLI)**:

```bash
az network vwan show -n <vwan-name> -g <rg> --query "{Name:name, BranchToBranch:allowBranchToBranchTraffic}" -o table
```

- **Pass / Fail**: **Pass** if `BranchToBranch` matches enterprise branch transit intent (`true` when branches transit Azure; `false` if blocked intentionally).

### A-RT-09

- **Checklist Scenario**: [RT-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-09) — Non-RFC 1918 & CGNAT `100.64.0.0/10` explicit prefixes in Private Traffic Routing Intent.
- **Common Misconfiguration**: Deploying AKS Pod/Node CGNAT (`100.64.0.0/10`) or legacy public-owned internal CIDRs without adding them to Private Traffic additional prefixes—causing traffic to follow `0.0.0.0/0` Internet SNAT rules or drop!
- **Verification (`az` CLI)**:

```bash
az network vhub routing-intent show --vhub-name <hub-name> -g <rg> -n <intent-name> \
  --query "routingPolicies[?name=='PrivateTrafficPolicy'].destinations[]" -o json
```

- **Pass / Fail**: **Pass** if every non-RFC 1918 internal prefix in the customer IPAM is explicitly listed alongside `PrivateTraffic`.

### A-RT-10

- **Checklist Scenario**: [RT-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-10) — Custom Route Tables, Labels, and Route Maps.
- **Learn Reference**: [How to configure virtual hub routing](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-virtual-hub-routing).
- **Verification (`az` CLI)**:

```bash
az network vhub route-table list --vhub-name <hub-name> -g <rg> \
  --query "[].{Table:name, Labels:labels, StaticRoutes:length(routes)}" -o table
az network vhub route-map list --vhub-name <hub-name> -g <rg> -o table
```

- **Pass / Fail**: **Pass** if custom route tables are used strictly where multi-tenant VRF isolation precludes Routing Intent, with documented association/propagation matrices.

---

## 4. Network Security & Secured Hub Verification (`A-SEC`)

### A-SEC-01

- **Checklist Control**: [SEC-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-01) — Microsoft Cloud Security Benchmark (MCSB) baseline applied.
- **Learn Reference**: [Azure security baseline for Virtual WAN](https://learn.microsoft.com/en-us/security/benchmark/azure/baselines/virtual-wan-security-baseline).
- **Verification (ARG KQL)**:

```kusto
securityresources
| where type =~ 'microsoft.security/assessments'
| where tostring(properties.resourceDetails.Id) has '/virtualWans/' or tostring(properties.resourceDetails.Id) has '/virtualHubs/'
| summarize Count = count() by Status = tostring(properties.status.code), Assessment = tostring(properties.displayName)
```

- **Pass / Fail**: **Pass** if zero high-severity `Unhealthy` MCSB network assessments remain open without an approved exemption.

### A-SEC-02

- **Checklist Control**: [SEC-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-02) — Secured Virtual Hub with Routing Intent.
- **Learn Reference**: [Secure Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/secure-virtual-wan).
- **Verification (`az` CLI)**: Execute `az network vhub routing-intent list --vhub-name <hub-name> -g <rg> -o json` and confirm both `PrivateTraffic` and `Internet` policies resolve to active hub security resources.
- **Pass / Fail**: **Pass** if all production hubs enforce Secured Hub inspection via Routing Intent.

### A-SEC-03

- **Checklist Control**: [SEC-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-03) — P2S VPN enforces Microsoft Entra ID + Conditional Access + MFA.
- **Learn Reference**: [Configure P2S User VPN for Microsoft Entra ID authentication](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-point-to-site-azure-ad).
- **Verification (`az` CLI)**:

```bash
az network vpn-server-config list -g <rg> \
  --query "[].{Name:name, AuthTypes:vpnAuthenticationTypes, AadAudience:aadAuthenticationParameters.aadAudience}" -o json
```

- **Pass / Fail**: **Pass** if `AuthTypes` equals `["AAD"]` (no legacy shared RADIUS/certificate-only auth unless justified for headless IoT) and Entra Conditional Access enforces MFA on the Azure VPN enterprise app.

### A-SEC-04

- **Checklist Control**: [SEC-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-04) — Spoke subnet NSGs + `defaultOutboundAccess: false`.
- **Learn Reference**: [Default outbound access in Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand subnet = properties.subnets
| extend subnetName = tostring(subnet.name),
         nsgId = tostring(subnet.properties.networkSecurityGroup.id),
         defaultOutbound = tostring(subnet.properties.defaultOutboundAccess)
| where subnetName !in~ ('GatewaySubnet','AzureFirewallSubnet','AzureFirewallManagementSubnet','RouteServerSubnet')
| where isempty(nsgId) or defaultOutbound =~ 'true'
| project vnet = name, resourceGroup, subnetName, missingNsg = isempty(nsgId), defaultOutbound
```

- **Pass / Fail**: **Pass** if query returns **0 rows** across production spoke VNets (note `AzureBastionSubnet` requires its documented Bastion NSG rules).

### A-SEC-05

- **Checklist Control**: [SEC-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-05) — PaaS Private Endpoints (`publicNetworkAccess: Disabled`) + `RouteTableEnabled` on PE subnets.
- **Learn Reference**: [Private Link & DNS at Scale](/azure-networking/04-network-security/private-link-and-dns-at-scale/) and [Routing intent — Private Endpoint symmetry](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies#troubleshooting).
- **Verification (ARG KQL)**:

```kusto
// 1. Audit PaaS data resources leaving publicNetworkAccess enabled
resources
| where type in~ (
    'microsoft.sql/servers',
    'microsoft.storage/storageaccounts',
    'microsoft.documentdb/databaseaccounts',
    'microsoft.keyvault/vaults',
    'microsoft.search/searchservices',
    'microsoft.cognitiveservices/accounts'
  )
| extend pna = coalesce(tostring(properties.publicNetworkAccess), 'Enabled')
| where pna !~ 'Disabled'
| project type, name, resourceGroup, subscriptionId, pna
```

```kusto
// 2. Verify PE subnets enable RouteTable network policies for Routing Intent symmetry
resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand subnet = properties.subnets
| where array_length(subnet.properties.privateEndpoints) > 0
| extend peNetPol = tostring(subnet.properties.privateEndpointNetworkPolicies)
| where peNetPol !in~ ('RouteTableEnabled', 'Enabled')
| project vnet = name, subnetName = tostring(subnet.name), peNetPol
```

- **Pass / Fail**: **Pass** if production PaaS resources report `pna == "Disabled"` and spoke PE subnets connected to Routing-Intent hubs enable `RouteTableEnabled` (or `Enabled`).

### A-SEC-06

- **Checklist Control**: [SEC-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-06) — Shared Azure DDoS Network Protection / IP Protection on spoke public IPs.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/publicipaddresses'
| where not(id has '/virtualHubs/')
| extend ddosMode = tostring(properties.ddosSettings.protectionMode),
         vnetDdos = tostring(properties.ipConfiguration.id)
| where ddosMode !~ 'Enabled'
| project name, resourceGroup, location, ddosMode
```

- **Pass / Fail**: **Pass** if all internet-exposed spoke VNets attach to the tenant's shared ALZ DDoS Network Protection plan or enable per-IP DDoS Protection.

### A-SEC-07

- **Checklist Control**: [SEC-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-07) — Strong IPsec/IKE cipher policy (`GCMAES256` + `SHA256`/`SHA384`).
- **Learn Reference**: [Virtual WAN IPsec policies](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-ipsec).
- **Verification (`az` CLI — `ARG: Not exposed`)**:

```bash
az network vpn-gateway connection list --gateway-name <vpn-gw-name> -g <rg> \
  --query "[].{Conn:name, Policies:vpnLinkConnections[].ipsecPolicies[]}" -o json
```

- **Pass / Fail**: **Pass** if every link specifies custom IPsec policies using `GCMAES256` and `SHA256`/`SHA384` with PFS enabled; **Fail** if default fallback allows `DES`, `3DES`, `MD5`, or `SHA1`.

### A-SEC-08

- **Checklist Control**: [SEC-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-08) — ExpressRoute encryption in transit (MACsec or IPsec over ER).
- **Learn Reference**: [IPsec over ExpressRoute for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/vpn-over-expressroute).
- **Verification (`az` CLI)**:

```bash
az network express-route port list --query "[].{Port:name, Location:location, MacSecState:links[].macSecConfig.cipher}" -o json
```

- **Pass / Fail**: **Pass** for regulated workloads if ExpressRoute Direct ports enforce `GcmAes256` MACsec or end-to-end IPsec VPN-over-ExpressRoute tunnels are active.

### A-SEC-09

- **Checklist Control**: [SEC-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-09) — Inter-hub encryption validation.
- **Verification (Portal / ADR)**: Inspect Virtual WAN -> Hubs -> Encryption properties and regional capability matrix if compliance requires customer-configured inter-hub encryption on top of Microsoft backbone physical/link protections.
- **Pass / Fail**: **Pass** if documented against compliance posture.

### A-SEC-10

- **Checklist Control**: [SEC-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-10) — Least-privilege RBAC on Connectivity scope.
- **Verification (ARG KQL)**:

```kusto
authorizationresources
| where type =~ 'microsoft.authorization/roleassignments'
| where tostring(properties.scope) has '/resourceGroups/<connectivity-rg>'
| extend roleDefId = tostring(properties.roleDefinitionId), principalId = tostring(properties.principalId)
| where roleDefId endswith '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' // Owner
     or roleDefId endswith 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
| project principalId, roleDefId, scope = tostring(properties.scope)
```

- **Pass / Fail**: **Pass** if zero standing human `Owner`/`Contributor` assignments exist (PIM-eligible JIT or scoped deployment Managed Identities only).

### A-SEC-11

- **Checklist Control**: [SEC-11](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-11) — Forced tunneling (`0.0.0.0/0`) for P2S VPN clients.
- **Learn Reference**: [Configure forced tunneling in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-forced-tunnel).
- **Verification (`az` CLI)**:

```bash
az network vhub connection list --vhub-name <hub-name> -g <rg> --query "[].{Conn:name, EnableInternetSecurity:enableInternetSecurity}" -o table
az network p2s-vpn-gateway show -n <p2s-gw-name> -g <rg> --query "p2SVpnConnectionConfigurations[].enableInternetSecurity" -o json
```

- **Pass / Fail**: **Pass** if `enableInternetSecurity == true` when corporate policy requires remote P2S internet inspection.

### A-SEC-12

- **Checklist Control**: [SEC-12](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-12) — VPN PSKs and certificates stored in Azure Key Vault with rotation.
- **Verification (`az` CLI — `ARG: Secrets intentionally unexposed`)**:

```bash
az keyvault secret list --vault-name <connectivity-kv> \
  --query "[].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires, Updated:attributes.updated}" -o table
```

- **Pass / Fail**: **Pass** if all PSKs/certificates have non-null expiration dates and automated CI/CD or Event Grid rotation runbooks.

### A-SEC-13

- **Checklist Control**: [SEC-13](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-13) — Microsoft Sentinel integration.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.operationsmanagement/solutions' and name startswith 'SecurityInsights'
| project sentinelSolution = name, workspaceId = tostring(properties.workspaceResourceId), location
```

- **Pass / Fail**: **Pass** if Sentinel is enabled on the central SIEM workspace and ingests `AZFW*` structured tables, `AzureDiagnostics` (gateways), and Cloud NGFW / NVA syslog/CEF feeds.

### A-SEC-14

- **Checklist Control**: [SEC-14](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-14) — GA Cloud NGFW / SaaS prerequisites (`PaloAltoNetworks.Cloudngfw` registered, supported region, `RoutingState == Provisioned`).
- **Learn Reference**: [Configure Palo Alto Networks Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw).
- **Verification (`az` CLI + ARG KQL)**:

```bash
az provider show -n PaloAltoNetworks.Cloudngfw \
  --query "{State:registrationState, LatestGaApi:resourceTypes[?resourceType=='firewalls'].defaultApiVersion | [0]}" -o json
az network vhub show -n <hub-name> -g <rg> --query "{Hub:name, Location:location, RoutingState:routingState}" -o table
```

- **Pass / Fail**: **Pass** if `State == "Registered"` using current GA `PaloAltoNetworks.Cloudngfw` API versions (do not pin legacy `2022-08-29-preview` templates), hub region is on the Palo Alto GA region matrix, and `RoutingState == "Provisioned"`.

### A-SEC-15

- **Checklist Control**: [SEC-15](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-15) — Locked Cloud NGFW policy management plane & clean reverse-deletion runbook.
- **Learn Reference**: [Cloud NGFW by Palo Alto Networks FAQ](https://learn.microsoft.com/en-us/azure/partner-solutions/palo-alto/faq).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'paloaltonetworks.cloudngfw/firewalls'
| project name, location, isPanorama = tostring(properties.isPanoramaManaged), isStrata = tostring(properties.isStrataCloudManaged), rulestackId = tostring(properties.associatedRulestack.resourceId)
```

- **Pass / Fail**: **Pass** if one management authority (Azure Rulestack, Panorama, or Strata Cloud Manager) is consistently applied across all hubs and the runbook enforces reverse teardown order: **`1. Routing Intent -> 2. Cloud NGFW -> 3. Hub SaaS resource -> 4. Virtual Hub`**.

### A-SEC-16

- **Checklist Control**: [SEC-16](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-16) — Inbound DNAT scoped to hub-local backends and never paired with Forced Tunnel Internet mode.
- **Learn Reference**: [Securing internet access with routing intent — Known limitations](https://learn.microsoft.com/en-us/azure/virtual-wan/about-internet-routing#known-limitations).
- **Verification (Architecture + Policy Review)**: Export Azure Firewall DNAT Rule Collections (`az network firewall policy rule-collection-group list`) or Cloud NGFW DNAT configs and verify every translated private IP belongs to a spoke VNet or branch directly attached to **that same regional hub**, and confirm the hub is in **Direct Access** Internet mode (not Forced Tunnel).
- **Pass / Fail**: **Pass** if zero cross-hub DNAT targets exist and Forced Tunnel hubs host zero public inbound DNAT rules.

---

## 5. Performance Efficiency Verification (`A-PERF`)

### A-PERF-01

- **Checklist Control**: [PERF-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-01) — Hub placement near traffic gravity.
- **Learn Reference**: [WAF Virtual WAN — Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#performance-efficiency).
- **Verification**: Compare hub `location` values (`A-RES-02`) against ExpressRoute peering cities, major branch populations, and spoke VNet regions; benchmark actual RTT using [`tools/netbench`](/azure-networking/06-operations-reviews/labs-and-tools-guide/).
- **Pass / Fail**: **Pass** if spoke VNets peer to local-region hubs without unnecessary cross-continent hairpins.

### A-PERF-02

- **Checklist Control**: [PERF-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-02) — S2S VPN Gateway scale units sized for p95 peak + ER failover.
- **Verification (`az` CLI)**:

```bash
az network vpn-gateway list -g <rg> --query "[].{Name:name, Location:location, ScaleUnits:vpnGatewayScaleUnit, ProvisionedMbps:to_number(vpnGatewayScaleUnit)*`500`}" -o table
```

Compare against 30-day p95 `TunnelBandwidth` in Azure Monitor Metrics.
- **Pass / Fail**: **Pass** if `(ScaleUnits * 500 Mbps)` exceeds p95 peak + failover load with `>= 25%` headroom.

### A-PERF-03

- **Checklist Control**: [PERF-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-03) — ExpressRoute Gateway scale units (`2 Gbps/unit`) & FastPath evaluation.
- **Learn Reference**: [ExpressRoute FastPath & SKUs](/azure-networking/03-hybrid-connectivity/expressroute-fastpath-and-skus/).
- **Verification (`az` CLI)**:

```bash
az network express-route gateway list -g <rg> \
  --query "[].{Name:name, Location:location, MinUnits:autoScaleConfiguration.bounds.min, MaxUnits:autoScaleConfiguration.bounds.max}" -o table
```

- **Pass / Fail**: **Pass** if `MinUnits * 2 Gbps` covers sustained p95 `BitsInPerSecond` / `BitsOutPerSecond` and FastPath requirements are documented.

### A-PERF-04

- **Checklist Control**: [PERF-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-04) — Hub router ~50 Gbps aggregate ceiling respected.
- **Learn Reference**: [Azure Virtual WAN limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-virtual-wan-limits).
- **Verification**: Inspect Azure Monitor Virtual Hub metric `VirtualHubDataProcessed` over 30 days and calculate peak Gbps (`Bytes * 8 / IntervalSeconds / 1e9`).
- **Pass / Fail**: **Pass** if peak hub router throughput remains safely below 40 Gbps (80% of the 50 Gbps / 50-unit ceiling); shard across a second hub or use direct VNet peering above that mark.

### A-PERF-05

- **Checklist Control**: [PERF-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-05) — `GCMAES256` IPsec cipher for hardware offload.
- **Verification**: Same query as [A-SEC-07](#a-sec-07).
- **Pass / Fail**: **Pass** if `ipsecEncryption == "GCMAES256"` and `ipsecIntegrity == "GCMAES256"` on high-throughput S2S links.

### A-PERF-06

- **Checklist Control**: [PERF-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-06) — `hubRoutingPreference` aligned with primary hybrid transport.
- **Learn Reference**: [About virtual hub routing preference](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing-preference).
- **Verification (`az` CLI)**:

```bash
az network vhub list -g <rg> --query "[].{Hub:name, Location:location, Preference:hubRoutingPreference}" -o table
```

- **Pass / Fail**: **Pass** if set intentionally (`ExpressRoute` for ER-primary WANs, `ASPath` when preserving end-to-end BGP AS-path length across multi-hub VPN+ER topologies, `VpnGateway` for VPN/SD-WAN-primary fabrics).

### A-PERF-07

- **Checklist Control**: [PERF-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-07) — Proactive 70% / 80% capacity alerts.
- **Verification (`az` CLI)**: Same metric alert audit as [A-OPS-07](#a-ops-07), verifying threshold rules at 70% (warning) and 80% (scale-up action).
- **Pass / Fail**: **Pass** if utilization threshold alerts are active and routed to NetOps on-call.

---

## 6. Operational Excellence Verification (`A-OPS`)

### A-OPS-01

- **Checklist Control**: [OPS-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-01) — 100% modular Bicep or Terraform IaC coverage.
- **Verification (`Repository & Deployment History Audit`)**:

```bash
az deployment group list -g <connectivity-rg> --query "[0:10].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" -o table
```

- **Pass / Fail**: **Pass** if all hub, gateway, firewall policy, and Routing Intent mutations flow through Git-backed Bicep/Terraform templates with clean zero-drift `what-if` / `terraform plan` output.

### A-OPS-02

- **Checklist Control**: [OPS-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-02) — CI/CD validation, approval gates, and rollback runbook.
- **Verification**: Inspect GitHub Actions / Azure DevOps environment protection rules and verify `what-if`/`plan` artifacts require peer review before production apply.
- **Pass / Fail**: **Pass** if production deployments enforce environment approval gates and automated route-table backup steps.

### A-OPS-03

- **Checklist Control**: [OPS-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-03) — Azure Monitor Network Insights enabled.
- **Learn Reference**: [Azure Monitor Insights for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/azure-monitor-insights).
- **Verification (Portal)**: Navigate to **Azure Monitor -> Network Insights -> Virtual WAN** and verify live topology health and dependency views render without permission or diagnostic gaps.
- **Pass / Fail**: **Pass** if topology health and metric workbooks populate across all production hubs.

### A-OPS-04

- **Checklist Control**: [OPS-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-04) — Resource-specific Diagnostic Settings on all Hubs, Gateways, and Firewalls.
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ (
    'microsoft.network/virtualhubs',
    'microsoft.network/vpngateways',
    'microsoft.network/expressroutegateways',
    'microsoft.network/p2svpngateways',
    'microsoft.network/azurefirewalls'
  )
| join kind=leftouter (
    insightsresources
    | where type =~ 'microsoft.insights/diagnosticsettings'
    | project diagName = name, targetId = tolower(tostring(properties.targetResourceId)),
              logDestType = tostring(properties.logAnalyticsDestinationType),
              workspaceId = tostring(properties.workspaceId)
  ) on $left.id == $right.targetId
| where isempty(workspaceId)
| project type, name, location, resourceGroup, subscriptionId
```

- **Pass / Fail**: **Pass** if query returns **0 rows** and Azure Firewalls use `logAnalyticsDestinationType == "Dedicated"` (Resource-Specific tables `AZFWNetworkRule`, `AZFWApplicationRule`, `AZFWNatRule`, `AZFWIdpsSignature`).

### A-OPS-05

- **Checklist Control**: [OPS-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-05) — Network Watcher Connection Monitor synthetic coverage.
- **Learn Reference**: [Connection Monitor overview](https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-overview).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/networkwatchers/connectionmonitors'
| project name, location, resourceGroup, testGroups = array_length(properties.testGroups)
```

- **Pass / Fail**: **Pass** if synthetic probes continuously measure TCP/ICMP reachability and packet loss across spoke-to-spoke, inter-hub, and hybrid branch paths.

### A-OPS-06

- **Checklist Control**: [OPS-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-06) — VNet Flow Logs + Traffic Analytics enabled on spoke VNets.
- **Learn Reference**: [Virtual network flow logs overview](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview).
- **Common Misconfiguration**: Relying on retiring NSG Flow Logs or leaving new spoke VNets without VNet Flow Logs + Traffic Analytics enabled.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| extend vnetId = tolower(id)
| join kind=leftouter (
    resources
    | where type =~ 'microsoft.network/networkwatchers/flowlogs'
    | where properties.enabled == true
    | project flowLogName = name, targetId = tolower(tostring(properties.targetResourceId)),
              trafficAnalytics = tobool(properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled)
  ) on $left.vnetId == $right.targetId
| where isempty(flowLogName)
| project vnet = name, location, resourceGroup, subscriptionId
```

- **Pass / Fail**: **Pass** if production spoke VNets have active **VNet Flow Logs** (`enabled == true`) with `trafficAnalytics == true`.

### A-OPS-07

- **Checklist Control**: [OPS-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-07) — Alerts on critical Virtual WAN & Firewall telemetry.
- **Verification (`az` CLI)**:

```bash
az monitor metrics alert list \
  --query "[?enabled==\`true\`].{Alert:name, RG:resourceGroup, Criteria:criteria.allOf[].metricName}" -o json
```

- **Pass / Fail**: **Pass** if active alerts cover `TunnelEgressPacketDropCount`, `TunnelIngressPacketDropCount`, `BgpPeerStatus`, `RoutingState`, `VirtualHubDataProcessed`, and Firewall `SNATPortUtilization` / `FirewallHealth`.

### A-OPS-08

- **Checklist Control**: [OPS-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-08) — Staggered customer-controlled Gateway Maintenance Windows.
- **Learn Reference**: [Configure customer-controlled maintenance for Virtual WAN gateways](https://learn.microsoft.com/en-us/azure/virtual-wan/maintenance-virtual-wan).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.maintenance/configurationassignments'
| where tostring(properties.resourceId) has_any ('vpnGateways','expressRouteGateways','p2sVpnGateways','azureFirewalls')
| project name, target = tostring(properties.resourceId), configId = tostring(properties.maintenanceConfigurationId)
```

- **Pass / Fail**: **Pass** if primary and secondary regional hub gateways/firewalls are assigned to non-overlapping off-hours maintenance configurations.

### A-OPS-09

- **Checklist Control**: [OPS-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-09) — Azure Policy guardrails assigned at Management Group scope.
- **Learn Reference**: [Azure Policy built-in definitions for Networking](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies#network).
- **Verification (ARG KQL)**:

```kusto
policyresources
| where type =~ 'microsoft.authorization/policyassignments'
| where tostring(properties.displayName) has_any ('Virtual WAN','VPN','ExpressRoute','Firewall','Private Endpoint','Outbound')
| project name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), enforcement = tostring(properties.enforcementMode)
```

- **Pass / Fail**: **Pass** if preventative/corrective policies enforce Standard vWAN SKU, Entra P2S auth, Private Link DNS zones, and `enforcementMode == "Default"`.

---

## 7. Governance & Cost Optimization Verification (`A-GOV`)

### A-GOV-01

- **Checklist Control**: [GOV-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-01) — Pre-deployment TCO model (fixed units + double per-GB processing).
- **Learn Reference**: [Virtual WAN pricing](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-about#pricing) and [Hub-Spoke vs. Virtual WAN](/azure-networking/02-core-topologies/hub-spoke-vs-vwan/).
- **Verification (`Design & FinOps Artifact`)**: Confirm pricing workbook accounts for Hub Base Fee + Routing Infrastructure Units + Hub Data Processing ($/GB) + Gateway Scale Units + Secured Hub Firewall Base & Data Processing ($/GB) + Inter-Hub Egress.
- **Pass / Fail**: **Pass** if both fixed and variable per-GB components are modeled at baseline and peak traffic volumes.

### A-GOV-02

- **Checklist Control**: [GOV-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-02) — FinOps cost-allocation tags enforced on all vWAN resources.
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ ('microsoft.network/virtualwans','microsoft.network/virtualhubs','microsoft.network/vpngateways','microsoft.network/expressroutegateways','microsoft.network/p2svpngateways','microsoft.network/azurefirewalls')
| extend tagKeys = bag_keys(tags)
| where not(tagKeys has 'CostCenter' and tagKeys has 'Environment' and tagKeys has 'Owner')
| project type, name, resourceGroup, existingTags = tags
```

- **Pass / Fail**: **Pass** if **0 rows** are returned for required organizational FinOps tags.

### A-GOV-03

- **Checklist Control**: [GOV-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-03) — Quarterly scale-unit rightsizing review.
- **Verification**: Compare provisioned VPN/ER gateway scale units and Hub Routing Units (`A-RES-06`, `A-PERF-02`, `A-PERF-03`) against 90-day p95 utilization in Azure Monitor.
- **Pass / Fail**: **Pass** if gateways sustained `< 30%` p95 utilization (outside required DR failover reserve) have scheduled rightsizing tickets.

### A-GOV-04

- **Checklist Control**: [GOV-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-04) — Direct VNet peering evaluated for high-volume spoke-to-spoke replication.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand peering = properties.virtualNetworkPeerings
| project sourceVnet = name, targetVnet = tostring(peering.properties.remoteVirtualNetwork.id), state = tostring(peering.properties.peeringState)
```

- **Pass / Fail**: **Pass** if high-throughput intra-region storage/DB replication spokes either use approved direct VNet peering (with NSG controls) or intentionally accept hub + firewall per-GB charges in `A-GOV-01`.

### A-GOV-05

- **Checklist Control**: [GOV-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-05) — Inter-region hub-to-hub bandwidth cost audit.
- **Verification (Azure Cost Management)**: Group Connectivity subscription spend by `MeterCategory == "Bandwidth"` and `MeterSubCategory == "Virtual WAN"` / `"Inter-Region"` over the trailing 90 days.
- **Pass / Fail**: **Pass** if top cross-region talkers (via VNet Flow Logs Traffic Analytics) are justified by business DR/active-active requirements.

### A-GOV-06

- **Checklist Control**: [GOV-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-06) — Cost Management budgets and anomaly alerts configured.
- **Verification (`az` CLI)**:

```bash
az consumption budget list --subscription <connectivity-sub-id> -o table
```

- **Pass / Fail**: **Pass** if active monthly/quarterly budgets trigger alerts at `80%`, `100%`, and `110%` forecasted spend plus Cost Anomaly alerts.

### A-GOV-07

- **Checklist Control**: [GOV-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-07) — Branch transport tiering (ExpressRoute vs. S2S VPN) aligned to criticality.
- **Verification**: Cross-reference branch site inventory tiers (Tier 1 DC/HQ vs. Tier 3 small branch) against `expressRouteConnections` and `vpnConnections` per hub.
- **Pass / Fail**: **Pass** if ExpressRoute circuits are reserved for latency/throughput/SLA-critical locations while small branches leverage S2S IPsec/SD-WAN.

### A-GOV-08

- **Checklist Control**: [GOV-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-08) — Cloud NGFW SaaS / Marketplace NGFW PAYG consumption governed.
- **Learn Reference**: [Palo Alto Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw).
- **Verification**: Filter Azure Cost Management by `PublisherType == "Marketplace"` / resource provider `PaloAltoNetworks.Cloudngfw`, verify committed vs. PAYG tiering, and confirm zero orphaned `Microsoft.Network/networkVirtualAppliances` NVA-IU charges remain on Cloud NGFW hubs.
- **Pass / Fail**: **Pass** if Marketplace SaaS spend has dedicated budget alerts and zero duplicate NVA-IU billing.
