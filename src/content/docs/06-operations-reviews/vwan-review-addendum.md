---
title: Virtual WAN Review Verification Playbook
description: Runnable Azure Resource Graph (ARG) KQL queries, Azure CLI commands, Portal checks, and pass/fail criteria for every control in the Virtual WAN Review Checklist.
sidebar:
  order: 2
---

This verification playbook is the operational companion to the [Virtual WAN & Landing Zone Review Checklist](/azure-networking/06-operations-reviews/vwan-review-checklist/). Every section (`A-TOP-*`, `A-RES-*`, `A-RT-*`, `A-SEC-*`, `A-PERF-*`, `A-OPS-*`, `A-GOV-*`) lists the Microsoft Learn reference, common field misconfigurations, and runnable Azure Resource Graph (ARG) KQL, `az` CLI, or Portal checks with pass/fail criteria.

:::note[ARG Coverage Tagging]
Azure Resource Graph does not index every Virtual WAN child resource or extension (for example, `Microsoft.Network/virtualHubs/routingIntent`, VPN link custom IPsec policies, and `Microsoft.Insights/diagnosticSettings`). Controls where ARG lacks coverage are tagged **`ARG: Not indexed; use az CLI or Portal`** so reviewers do not spend time debugging empty KQL results.
:::

---

## 1. Topology & CAF landing zone verification (`A-TOP`)

### A-TOP-01

- **Checklist control**: [TOP-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-01): Platform Connectivity subscription placement.
- **Learn reference**: [CAF Virtual WAN network topology](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/virtual-wan-network-topology).
- **Common misconfiguration**: Virtual Hubs or Secured Hub Firewalls deployed inside workload landing zone subscriptions, which splits RBAC boundaries and network quotas.
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

- **Pass / Fail**: **Pass** if 100% of Virtual WAN core resources reside in the designated Platform Connectivity subscription(s); **Fail** if hubs or gateways appear in application workload subscriptions.

### A-TOP-02

- **Checklist control**: [TOP-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-02): Single Resource Group lifecycle boundary.
- **Learn reference**: [CAF Virtual WAN network topology](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/virtual-wan-network-topology).
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ ('microsoft.network/virtualwans','microsoft.network/virtualhubs','microsoft.network/vpngateways','microsoft.network/expressroutegateways','microsoft.network/p2svpngateways')
| summarize RGs = make_set(resourceGroup), Resources = count() by subscriptionId
```

- **Pass / Fail**: **Pass** if `RGs` maps to one governed Resource Group (required by the Virtual WAN portal experience) or an approved IaC stack without ad-hoc Resource Groups.

### A-TOP-03

- **Checklist control**: [TOP-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-03): Hub CIDR `/23` minimum (`/22` with Azure Firewall) and non-overlapping IPAM.
- **Learn reference**: [Virtual hub address space](https://learn.microsoft.com/en-us/azure/virtual-wan/hub-settings#virtual-hub-address-space) and [VNet Sizing & IPv4/IPv6 Planning](/azure-networking/01-foundations/vnet-and-ip-addressing/).
- **Common misconfiguration**: Allocating `/24` hub prefixes (immutable after hub creation) that constrain future NVA or Azure Firewall scale-out, or overlapping a hub CIDR with an on-premises subnet.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| extend prefix = tostring(properties.addressPrefix),
         hasAzFw = isnotempty(tostring(properties.azureFirewall.id))
| extend maskLen = toint(split(prefix, '/')[1])
| project name, location, prefix, maskLen, hasAzFw,
          underSizedHub = (maskLen > 23),
          underSizedForAzFw = (hasAzFw and maskLen > 22)
```

- **Pass / Fail**: **Pass** if `maskLen <= 23` on every hub (`maskLen <= 22` when `hasAzFw == true`) and verified against enterprise IPAM with zero overlap.

### A-TOP-04

- **Checklist control**: [TOP-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-04): Shared services (DNS Private Resolver, AD DS) in a dedicated spoke VNet.
- **Learn reference**: [DNS & Private Resolver](/azure-networking/01-foundations/dns-and-private-resolver/).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/dnsresolvers'
| project name, location, resourceGroup, vnetId = tostring(properties.virtualNetwork.id)
```

- **Pass / Fail**: **Pass** if DNS Private Resolvers and domain controllers run in a dedicated Shared Services or Identity spoke VNet connected to the hub.

### A-TOP-05

- **Checklist control**: [TOP-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-05): Single hub per region unless scale limits or NVA separation require a second hub.
- **Learn reference**: [Azure Virtual WAN service limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-virtual-wan-limits).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| summarize HubCount = count(), HubNames = make_list(name) by location, vwanId = tostring(properties.virtualWan.id)
| where HubCount > 1
```

- **Pass / Fail**: **Pass** if empty (1 hub per region) or if multiple in-region hubs have an approved ADR (for example, `> 540` locally connected VNet prefixes or separate SD-WAN NVA and Cloud NGFW hubs).

### A-TOP-06

- **Checklist control**: [TOP-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-06): ExpressRoute Global Reach vs. Routing Intent private transit evaluation.
- **Learn reference**: [ExpressRoute Global Reach](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-global-reach) and [AVS Networking & Transit](/azure-networking/05-workload-networking/avs-networking/).
- **Verification (`az` CLI)**:

```bash
az network express-route list \
  --query "[].{Name:name, Location:location, Sku:sku.tier, GlobalReachEnabled:globalReachEnabled, Connections:peerings[].connections[].circuitConnectionStatus, PeeredConnections:peerings[].peeredConnections[].circuitConnectionStatus}" -o json
```

- **Pass / Fail**: **Pass** if Global Reach peerings match documented architecture decisions (Global Reach bypasses Secured Hub firewalls and is incompatible with support-enabled Routing Intent ER-to-ER firewall inspection).

### A-TOP-07

- **Checklist control**: [TOP-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-07): Brownfield Hub-and-Spoke to Virtual WAN migration runbook.
- **Learn reference**: [Migrate to Azure Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/migrate-from-hub-spoke-topology).
- **Verification (`ARG: Design artifact`)**: Inspect the migration wave runbook, ExpressRoute coexistence path, and rollback steps.
- **Pass / Fail**: **Pass** if coexistence routing symmetry and rollback steps are documented and tested in non-production; `N/A` for greenfield builds.

### A-TOP-08

- **Checklist control**: [TOP-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#top-08): Certified SD-WAN and NVA Managed Application hub coexistence.
- **Learn reference**: [About NVAs in a Virtual WAN hub](https://learn.microsoft.com/en-us/azure/virtual-wan/about-nva-hub).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/networkvirtualappliances'
| project name, location, nvaVendor = tostring(properties.nvaSku.vendor), scaleUnit = tostring(properties.nvaSku.bundledScaleUnit), vhubId = tostring(properties.virtualHub.id)
```

- **Pass / Fail**: **Pass** if no hub mixes an SD-WAN connectivity NVA with a separate Firewall NVA or Palo Alto Cloud NGFW SaaS resource under Routing Intent.

---

## 2. Resiliency & availability verification (`A-RES`)

### A-RES-01

- **Checklist control**: [RES-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-01): Virtual WAN Standard SKU on all production deployments.
- **Learn reference**: [WAF Virtual WAN service guide: Reliability](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualwans'
| project name, sku = tostring(properties.type), location, resourceGroup, subscriptionId
| where sku !~ 'Standard'
```

- **Pass / Fail**: **Pass** if query returns **0 rows** (`sku == "Standard"` everywhere).

### A-RES-02

- **Checklist control**: [RES-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-02): Multi-region Virtual Hubs (`>= 2` regions).
- **Learn reference**: [Disaster recovery design for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/disaster-recovery-design).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| summarize Hubs = make_set(name), Regions = make_set(location), RegionCount = dcount(location) by vwanId = tostring(properties.virtualWan.id)
```

- **Pass / Fail**: **Pass** if `RegionCount >= 2` for multi-region production Virtual WANs.

### A-RES-03

- **Checklist control**: [RES-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-03): Availability Zone regions for auto-zonal gateways and explicit zones on Secured Hub Azure Firewalls.
- **Learn reference**: [Virtual WAN FAQ: Availability Zones](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-faq#how-are-availability-zones-and-resiliency-handled-in-virtual-wan) and [ExpressRoute Resiliency](/azure-networking/03-hybrid-connectivity/expressroute-resiliency/).
- **Common misconfiguration**: Deploying Azure Firewall in a Secured Hub without specifying `zones` at creation time (unlike vWAN VPN, ExpressRoute, and P2S gateways, Azure Firewall does not deploy across zones automatically and cannot be converted in place).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/azurefirewalls'
| where isnotempty(tostring(properties.virtualHub.id))
| extend zoneCount = iif(isnull(zones), 0, array_length(zones))
| project name, location, resourceGroup, zones, zoneCount, nonZonal = (zoneCount < 2)
```

- **Pass / Fail**: **Pass** if all hub regions support Availability Zones (confirming gateways were created after AZ launch in that region) and every Secured Hub Azure Firewall reports `nonZonal == false` (`zones: ["1","2","3"]`).

### A-RES-04

- **Checklist control**: [RES-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-04): Active-active S2S VPN tunnels with eBGP on both links.
- **Learn reference**: [WAF Virtual WAN service guide: Reliability](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability).
- **Verification (`az` CLI)**:

```bash
az network vpn-gateway connection list --gateway-name <vpn-gw-name> -g <rg> \
  --query "[].{Connection:name, ConnBgp:enableBgp, Links:vpnLinkConnections[].{Link:name, LinkBgp:enableBgp, Status:connectionStatus}}" -o json
```

- **Pass / Fail**: **Pass** if production branch connections run active-active tunnels with BGP enabled (`ConnBgp` or `LinkBgp == true`) and `Status == "Connected"`.

### A-RES-05

- **Checklist control**: [RES-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-05): S2S VPN backup behind ExpressRoute with symmetric BGP preference.
- **Learn reference**: [About virtual hub routing preference](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing-preference) and [ExpressRoute Bow-Tie Failures](/azure-networking/03-hybrid-connectivity/expressroute-bowtie-failures/).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualhubs'
| project name, location,
    hasErGw = isnotempty(tostring(properties.expressRouteGateway.id)),
    hasVpnGw = isnotempty(tostring(properties.vpnGateway.id)),
    routingPref = tostring(properties.hubRoutingPreference)
```

- **Pass / Fail**: **Pass** if critical ExpressRoute hubs also host an active S2S VPN backup path, `hubRoutingPreference` aligns with primary ExpressRoute selection, and on-premises routers prepend BGP AS-path on VPN routes so traffic returns to ExpressRoute after circuit recovery.

### A-RES-06

- **Checklist control**: [RES-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-06): Hub Routing Infrastructure Units pre-sized (`<= 25 min` scale-out time).
- **Learn reference**: [Virtual hub capacity and routing infrastructure units](https://learn.microsoft.com/en-us/azure/virtual-wan/hub-settings#capacity).
- **Verification (`az` CLI)**:

```bash
az network vhub show -n <hub-name> -g <rg> \
  --query "{Hub:name, MinRouterUnits:virtualRouterAutoScaleConfiguration.minCapacity, RoutingState:routingState}" -o table
```

- **Pass / Fail**: **Pass** if `MinRouterUnits` covers connected spoke VM count (`2,000` VMs at default `2` units, `+1,000` VMs per extra unit up to `50,000` VMs at `50` units) plus expected non-Routing-Intent burst throughput (`3 Gbps` at `2-3` units, then `1 Gbps` per unit from `4` to `50` units up to `50 Gbps`) without waiting 25 minutes for reactive autoscale.

### A-RES-07

- **Checklist control**: [RES-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-07): Global P2S VPN profile and non-overlapping client address pools.
- **Learn reference**: [Global and hub User VPN profiles](https://learn.microsoft.com/en-us/azure/virtual-wan/global-hub-profile) and [About P2S client address pools](https://learn.microsoft.com/en-us/azure/virtual-wan/about-client-address-pools).
- **Verification (`az` CLI)**:

```bash
az network p2s-vpn-gateway list -g <rg> \
  --query "[].{Gateway:name, Location:location, ScaleUnits:vpnGatewayScaleUnit, Pools:p2SConnectionConfigurations[].vpnClientAddressPool.addressPrefixes}" -o json
```

- **Pass / Fail**: **Pass** if the WAN-level Global profile is distributed to clients, regional pools hold `>= 2x` peak concurrent sessions, and gateways at `40+` scale units assign at least one distinct pool (`>= 10,000` IPs) per backend gateway instance.

### A-RES-08

- **Checklist control**: [RES-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-08): Failure Mode Analysis (FMA) documented.
- **Learn reference**: [WAF Virtual WAN: Reliability](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#reliability) and [Use Private Link in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/howto-private-link#routing-considerations-with-private-link-in-virtual-wan).
- **Verification (`ARG: Design artifact`)**: Review customer FMA covering regional outage, single MSEE failure, CPE failure, BGP route leak, and hub maintenance or scale-out impact on stateful Private Endpoint flows (`15-30s` TCP timeout tuning).
- **Pass / Fail**: **Pass** if blast radius, RTO/RPO, and recovery actions are documented for all five failure modes.

### A-RES-09

- **Checklist control**: [RES-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-09): End-to-end Composite SLA calculated.
- **Verification (`ARG: Architecture worksheet`)**: Multiply serial component SLAs (for example, Hub `99.95%` x ER Gateway `99.95%` x Zone-Redundant Azure Firewall `99.99%` x Dual-Peering ExpressRoute `99.95%`).
- **Pass / Fail**: **Pass** if composite availability meets application tier targets without unmodeled single-CPE or non-zonal bottlenecks.

### A-RES-10

- **Checklist control**: [RES-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#res-10): Annual live DR and BGP failover drill executed.
- **Learn reference**: [Disaster recovery design for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/disaster-recovery-design).
- **Verification (`ARG: Operational evidence`)**: Inspect a timestamped failover report from the past 12 months measuring convergence time and packet loss across ExpressRoute-to-VPN and Hub-1-to-Hub-2 failovers.
- **Pass / Fail**: **Pass** if executed within 12 months with zero unresolved asymmetric drops.

---

## 3. Routing decision matrix verification (`A-RT`)

### A-RT-01

- **Checklist scenario**: [RT-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-01): Any-to-any default transit (`defaultRouteTable`).
- **Learn reference**: [About virtual hub routing](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing).
- **Verification (`az` CLI)**:

```bash
az network vhub route-table show --vhub-name <hub-name> -g <rg> -n defaultRouteTable -o json
```

- **Pass / Fail**: **Fail** in production if `defaultRouteTable` runs without Routing Intent or custom route isolation when security policy requires east-west or north-south inspection.

### A-RT-02

- **Checklist scenario**: [RT-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-02): Internet egress via Azure Firewall (`Internet` policy).
- **Learn reference**: [Configure Virtual WAN Hub routing intent and policies](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies).
- **Verification (`az` CLI; `ARG: Not indexed`)**:

```bash
az network vhub routing-intent list --vhub <hub-name> -g <rg> -o json
```

- **Pass / Fail**: **Pass** if `routingPolicies` includes `destinations: ["Internet"]` pointing `nextHop` to the hub Azure Firewall resource ID, and `enableInternetSecurity: true` is set on target spoke connections.

### A-RT-03

- **Checklist scenario**: [RT-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-03): Internet egress via Cloud NGFW SaaS or certified NVA.
- **Learn reference**: [Configure Palo Alto Networks Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw#configure-routing).
- **Verification (`az` CLI)**: Run `az network vhub routing-intent list --vhub <hub-name> -g <rg> -o json` across **every** regional hub.
- **Pass / Fail**: **Pass** if every regional hub requiring internet breakout configures its own local SaaS or NVA `Internet` policy (`0.0.0.0/0` never propagates across hubs).

### A-RT-04

- **Checklist scenario**: [RT-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-04): Intra-region Private inspection (`PrivateTraffic` policy).
- **Learn reference**: [Virtual WAN & Routing Intent](/azure-networking/02-core-topologies/virtual-wan-and-routing-intent/).
- **Verification (`az` CLI; `ARG: Not indexed`)**:

```bash
az network vhub routing-intent list --vhub <hub-name> -g <rg> \
  --query "[].routingPolicies[?contains(join(',',destinations),'PrivateTraffic')]" -o json
```

- **Pass / Fail**: **Pass** if `PrivateTraffic` maps `nextHop` to the hub Azure Firewall, Cloud NGFW SaaS, or eligible NGFW NVA.

### A-RT-05

- **Checklist scenario**: [RT-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-05): Inter-hub cross-region Private inspection.
- **Learn reference**: [View virtual hub effective routes](https://learn.microsoft.com/en-us/azure/virtual-wan/effective-routes-virtual-hub).
- **Verification (`az` CLI)**: Run `A-RT-04` across **all** hubs in the Virtual WAN and inspect effective routes:

```bash
az network vhub get-effective-routes --name <hub-name> -g <rg> \
  --resource-type RouteTable \
  --resource-id "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualHubs/<hub-name>/hubRouteTables/defaultRouteTable" -o json
```

- **Pass / Fail**: **Pass** if both source and destination hubs enforce `PrivateTraffic` Routing Intent and remote hub prefixes steer symmetrically via each hub's security solution.

### A-RT-06

- **Checklist scenario**: [RT-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-06): Routing Intent snapshot governance and `<= 600` local VNet address-space limit.
- **Learn reference**: [Routing intent: Address space limits and rollback](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies#address-limits).
- **Verification (`az` CLI)**:

```bash
# Snapshot route tables and connections before enabling Routing Intent
az network vhub route-table list --vhub-name <hub-name> -g <rg> -o json > vhub-rt-backup.json
az network vhub connection list --vhub-name <hub-name> -g <rg> -o json > vhub-conn-backup.json
```

- **Pass / Fail**: **Pass** if pre-change JSON backups are stored in version control (required for manual restoration if Routing Intent is later deleted) and locally connected spoke VNet address spaces per hub stay below `540` (`90%` of the non-adjustable `600`-prefix limit).

### A-RT-07

- **Checklist scenario**: [RT-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-07): ExpressRoute transit and SKU validation.
- **Learn reference**: [About ExpressRoute connections in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-expressroute-about) and [ExpressRoute FastPath & SKUs](/azure-networking/03-hybrid-connectivity/expressroute-fastpath-and-skus/).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/expressroutecircuits'
| project name, location, peeringLocation = tostring(properties.serviceProviderProperties.peeringLocation),
          tier = tostring(sku.tier), family = tostring(sku.family)
```

- **Pass / Fail**: **Pass** if `Local` SKU circuits connect only to local-region hub gateways without expecting Global Reach, `Standard`/`Premium` circuits sit in Global Reach-capable locations when branch transit is required, and ER-to-ER paths choose either Global Reach or support-enabled Private Routing Intent (never both).

### A-RT-08

- **Checklist scenario**: [RT-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-08): Branch-to-branch transit (`VPN <-> VPN`, `VPN <-> ER`).
- **Verification (`az` CLI)**:

```bash
az network vwan show -n <vwan-name> -g <rg> --query "{Name:name, BranchToBranch:allowBranchToBranchTraffic}" -o table
```

- **Pass / Fail**: **Pass** if `BranchToBranch` matches documented branch transit policy (`true` when branches transit Virtual WAN; `false` when blocked intentionally).

### A-RT-09

- **Checklist scenario**: [RT-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-09): Non-RFC 1918, CGNAT `100.64.0.0/10`, and bare-metal delegated prefixes in Private Traffic Routing Intent.
- **Common misconfiguration**: Using AKS CGNAT (`100.64.0.0/10`), public-owned internal ranges, or bare-metal delegated subnets (Azure NetApp Files, Nutanix NC2, Oracle Database@Azure) without listing them on **every** Routing Intent hub and disabling firewall SNAT on those private blocks.
- **Verification (`az` CLI)**:

```bash
az network vhub routing-intent show --vhub <hub-name> -g <rg> -n <intent-name> \
  --query "routingPolicies[?contains(join(',',destinations),'PrivateTraffic')].destinations[]" -o json
```

- **Pass / Fail**: **Pass** if every non-RFC 1918 internal prefix and bare-metal delegated CIDR is listed alongside `PrivateTraffic` on all secured hubs.

### A-RT-10

- **Checklist scenario**: [RT-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#rt-10): Custom Route Tables, Labels, and Route Maps.
- **Learn reference**: [How to configure virtual hub routing](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-virtual-hub-routing).
- **Verification (`az` CLI)**:

```bash
az network vhub route-table list --vhub-name <hub-name> -g <rg> \
  --query "[].{Table:name, Labels:join(',', labels || \`[]\`), StaticRoutes:length(routes || \`[]\`)}" -o table
az network vhub route-map list --vhub-name <hub-name> -g <rg> -o table
```

- **Pass / Fail**: **Pass** if custom route tables are reserved for multi-tenant VRF isolation where Routing Intent is intentionally omitted, with documented association and propagation tables.

---

## 4. Network security & Secured Hub verification (`A-SEC`)

### A-SEC-01

- **Checklist control**: [SEC-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-01): Microsoft Cloud Security Benchmark (MCSB) baseline applied.
- **Learn reference**: [Secure your Azure Virtual WAN deployment](https://learn.microsoft.com/en-us/azure/virtual-wan/secure-virtual-wan) and [Azure security baseline for Virtual WAN](https://learn.microsoft.com/en-us/security/benchmark/azure/baselines/virtual-wan-security-baseline).
- **Verification (ARG KQL)**:

```kusto
securityresources
| where type =~ 'microsoft.security/assessments'
| where id has_any (
    '/virtualWans/',
    '/virtualHubs/',
    '/vpnGateways/',
    '/expressRouteGateways/',
    '/p2sVpnGateways/',
    '/azureFirewalls/'
  )
| summarize Count = count() by
    Status = tostring(properties.status.code),
    Severity = tostring(properties.metadata.severity),
    Assessment = tostring(properties.displayName)
```

- **Pass / Fail**: **Pass** if zero `High` severity `Unhealthy` MCSB network assessments remain open without an approved exemption.

### A-SEC-02

- **Checklist control**: [SEC-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-02): Secured Virtual Hub with Routing Intent.
- **Learn reference**: [Secure your Azure Virtual WAN deployment](https://learn.microsoft.com/en-us/azure/virtual-wan/secure-virtual-wan).
- **Verification (`az` CLI)**: Run `az network vhub routing-intent list --vhub <hub-name> -g <rg> -o json` and confirm both `PrivateTraffic` and `Internet` policies (or Forced Tunnel `0.0.0.0/0` additional prefix) resolve to active hub security resources.
- **Pass / Fail**: **Pass** if all production hubs enforce Secured Hub inspection via Routing Intent.

### A-SEC-03

- **Checklist control**: [SEC-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-03): P2S VPN enforces Microsoft Entra ID (Microsoft-registered App ID) and Conditional Access MFA.
- **Learn reference**: [Configure a P2S User VPN connection with Microsoft Entra ID](https://learn.microsoft.com/en-us/azure/virtual-wan/point-to-site-entra-gateway).
- **Verification (`az` CLI)**:

```bash
az network vpn-server-config list -g <rg> \
  --query "[].{Name:name, AuthTypes:vpnAuthenticationTypes, AadAudience:aadAuthenticationParameters.aadAudience}" -o json
```

- **Pass / Fail**: **Pass** if `AuthTypes` equals `["AAD"]`, `AadAudience` uses the Microsoft-registered Azure VPN Client App ID `c632b3df-fb67-4d84-bdcf-b95ad541b5c8` (or an approved custom App ID, migrating off `41b23e61-6c1e-4545-b367-cd054e0ed4b4` before March 31, 2028), and Conditional Access enforces MFA.

### A-SEC-04

- **Checklist control**: [SEC-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-04): Spoke subnet NSGs and `defaultOutboundAccess: false`.
- **Learn reference**: [Default outbound access in Azure](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/default-outbound-access).
- **Common misconfiguration**: Leaving legacy subnets with `defaultOutboundAccess: null` (which implicitly enables default outbound IPs on older API versions) instead of explicitly setting `false` and deallocating/restarting existing VMs.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand subnet = properties.subnets
| extend subnetName = tostring(subnet.name),
         nsgId = tostring(subnet.properties.networkSecurityGroup.id),
         delegations = iif(isnull(subnet.properties.delegations), 0, array_length(subnet.properties.delegations)),
         defaultOutbound = coalesce(tostring(subnet.properties.defaultOutboundAccess), 'true (implicit)')
| where subnetName !in~ ('GatewaySubnet','AzureFirewallSubnet','AzureFirewallManagementSubnet','RouteServerSubnet')
| where isempty(nsgId) or (subnetName !~ 'AzureBastionSubnet' and delegations == 0 and defaultOutbound !~ 'false')
| project vnet = name, resourceGroup, subnetName, missingNsg = isempty(nsgId), defaultOutbound
```

- **Pass / Fail**: **Pass** if query returns **0 rows** across production spoke VNets (`AzureBastionSubnet` retains its required Bastion NSG).

### A-SEC-05

- **Checklist control**: [SEC-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-05): PaaS Private Endpoints (`publicNetworkAccess: Disabled`), `<= 4,000` PEs per hub, and `RouteTableEnabled` on PE subnets.
- **Learn reference**: [Use Private Link in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/howto-private-link), [Routing intent troubleshooting](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies#troubleshooting-data-path), and [Private Link & DNS at Scale](/azure-networking/04-network-security/private-link-and-dns-at-scale/).
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

- **Pass / Fail**: **Pass** if production PaaS resources set `pna == "Disabled"`, spoke PE subnets enable `RouteTableEnabled` (or `Enabled`), and total Private Endpoints across spokes per hub remain below `4,000`.

### A-SEC-06

- **Checklist control**: [SEC-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-06): Shared Azure DDoS Network Protection or IP Protection on spoke public IPs.
- **Learn reference**: [CAF Virtual WAN topology: DDoS Protection](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/virtual-wan-network-topology#plan-your-virtual-wan-deployment).
- **Verification (ARG KQL)**:

```kusto
// 1. Audit non-hub Public IPs for explicit DDoS disablement or unattached exposure
resources
| where type =~ 'microsoft.network/publicipaddresses'
| extend attachedId = tolower(tostring(properties.ipConfiguration.id)),
         ddosMode = coalesce(tostring(properties.ddosSettings.protectionMode), 'VirtualNetworkInherited')
| where not(attachedId has_any ('/azurefirewalls/', '/vpngateways/', '/expressroutegateways/', '/p2svpngateways/'))
| where ddosMode =~ 'Disabled' or (ddosMode =~ 'VirtualNetworkInherited' and isempty(attachedId))
| project name, subscriptionId, resourceGroup, location, ddosMode, attachedId
```

```kusto
// 2. Verify spoke VNets hosting VirtualNetworkInherited Public IPs enable DDoS Network Protection
resources
| where type =~ 'microsoft.network/virtualnetworks'
| where tobool(properties.enableDdosProtection) != true
| project name, subscriptionId, resourceGroup, location, ddosPlan = tostring(properties.ddosProtectionPlan.id)
```

- **Pass / Fail**: **Pass** if Query 1 returns **0 rows** (`ddosMode != "Disabled"`) and every spoke VNet hosting `VirtualNetworkInherited` internet-facing endpoints links to the central ALZ DDoS Network Protection plan (`enableDdosProtection == true`) or uses per-IP DDoS Protection (`ddosMode == "Enabled"`).

### A-SEC-07

- **Checklist control**: [SEC-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-07): Custom IPsec/IKE cipher policy (`GCMAES256` and `SHA256`/`SHA384`).
- **Learn reference**: [Site-to-site IPsec policies for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-ipsec).
- **Verification (`az` CLI; `ARG: Not indexed`)**:

```bash
az network vpn-gateway connection list --gateway-name <vpn-gw-name> -g <rg> \
  --query "[].{Conn:name, Policies:vpnLinkConnections[].ipsecPolicies[]}" -o json
```

- **Pass / Fail**: **Pass** if every link specifies custom IPsec policies using `GCMAES256` and `SHA256`/`SHA384` with `DHGroup14+`/`ECP256`/`ECP384` and PFS enabled; **Fail** if left on default policy allowing `SHA1`, `DHGroup2`, or `3DES`.

### A-SEC-08

- **Checklist control**: [SEC-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-08): ExpressRoute encryption in transit (MACsec or IPsec over ExpressRoute).
- **Learn reference**: [IPsec over ExpressRoute for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/vpn-over-expressroute) and [Encrypted ExpressRoute with routing intent](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-routing-policies#encryptedER).
- **Verification (`az` CLI)**:

```bash
az network express-route port list --query "[].{Port:name, Location:location, MacSecCipher:links[].macSecConfig.cipher}" -o json
az network vpn-gateway connection list --gateway-name <vpn-gw-name> -g <rg> \
  --query "[].{Conn:name, UsePrivateAzureIp:useLocalAzureIpAddress}" -o json
```

- **Pass / Fail**: **Pass** for regulated workloads if ExpressRoute Direct ports enforce `GcmAes256` MACsec or IPsec VPN-over-ExpressRoute connections set `useLocalAzureIpAddress == true` with more-specific or disjoint VPN BGP prefixes.

### A-SEC-09

- **Checklist control**: [SEC-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-09): Inter-hub encryption posture documented.
- **Verification (Portal / ADR)**: Review compliance requirements against Microsoft backbone encryption guarantees and hub encryption capabilities in target regions.
- **Pass / Fail**: **Pass** if documented and signed off in the security architecture record.

### A-SEC-10

- **Checklist control**: [SEC-10](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-10): Least-privilege RBAC on Connectivity scope.
- **Learn reference**: [Virtual WAN roles and permissions](https://learn.microsoft.com/en-us/azure/virtual-wan/roles-permissions).
- **Verification (ARG KQL)**:

```kusto
authorizationresources
| where type =~ 'microsoft.authorization/roleassignments'
| extend scope = tostring(properties.scope),
         roleDefId = tostring(properties.roleDefinitionId),
         principalId = tostring(properties.principalId),
         principalType = tostring(properties.principalType)
| where scope =~ '/subscriptions/<connectivity-sub-id>'
     or scope has '/resourceGroups/<connectivity-rg>'
     or scope has '/providers/Microsoft.Management/managementGroups/'
| where roleDefId endswith '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' // Owner
     or roleDefId endswith 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
| project principalId, principalType, roleDefId, scope
```

- **Pass / Fail**: **Pass** if zero standing human (`User` or `Group`) `Owner` or `Contributor` assignments exist at management group, Connectivity subscription, or Resource Group scope (PIM-eligible JIT or scoped pipeline `ServicePrincipal` Managed Identities only).

### A-SEC-11

- **Checklist control**: [SEC-11](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-11): Forced tunneling (`0.0.0.0/0`) for P2S VPN clients.
- **Learn reference**: [Configure forced tunneling for Virtual WAN Point-to-site VPN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-forced-tunnel).
- **Verification (`az` CLI)**:

```bash
az network vhub connection list --vhub-name <hub-name> -g <rg> --query "[].{Conn:name, EnableInternetSecurity:enableInternetSecurity}" -o table
az network p2s-vpn-gateway show -n <p2s-gw-name> -g <rg> --query "p2SConnectionConfigurations[].enableInternetSecurity" -o json
```

- **Pass / Fail**: **Pass** if `enableInternetSecurity == true` on `p2SConnectionConfigurations` (and Windows Azure VPN Client profile XML uses `<version>2</version>`) when corporate policy requires remote P2S internet inspection.

### A-SEC-12

- **Checklist control**: [SEC-12](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-12): VPN PSKs and certificates stored in Azure Key Vault with rotation.
- **Verification (`az` CLI; `ARG: Secrets intentionally unexposed`)**:

```bash
az keyvault secret list --vault-name <connectivity-kv> \
  --query "[].{Name:name, Enabled:attributes.enabled, Expires:attributes.expires, Updated:attributes.updated}" -o table
```

- **Pass / Fail**: **Pass** if all PSKs and certificates carry expiration dates and automated CI/CD or Event Grid rotation runbooks.

### A-SEC-13

- **Checklist control**: [SEC-13](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-13): Microsoft Sentinel integration.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.operationsmanagement/solutions' and name startswith 'SecurityInsights'
| project sentinelSolution = name, workspaceId = tostring(properties.workspaceResourceId), location
```

- **Pass / Fail**: **Pass** if Sentinel is enabled on the central SIEM workspace and ingests `AZFW*` structured tables, gateway diagnostics, and Cloud NGFW or NVA feeds.

### A-SEC-14

- **Checklist control**: [SEC-14](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-14): Cloud NGFW SaaS prerequisites (`PaloAltoNetworks.Cloudngfw` registered, supported region, `RoutingState == Provisioned`).
- **Learn reference**: [Configure Palo Alto Networks Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw).
- **Verification (`az` CLI)**:

```bash
az provider show -n PaloAltoNetworks.Cloudngfw \
  --query "{State:registrationState, LatestGaApi:resourceTypes[?resourceType=='firewalls'].defaultApiVersion | [0]}" -o json
az network vhub show -n <hub-name> -g <rg> --query "{Hub:name, Location:location, RoutingState:routingState}" -o table
```

- **Pass / Fail**: **Pass** if `State == "Registered"`, hub region is in Azure Public on Palo Alto's supported region list, and `RoutingState == "Provisioned"` before Cloud NGFW creation.

### A-SEC-15

- **Checklist control**: [SEC-15](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-15): Single Cloud NGFW policy management plane and reverse-deletion runbook.
- **Learn reference**: [Cloud NGFW by Palo Alto Networks FAQ](https://learn.microsoft.com/en-us/azure/partner-solutions/palo-alto/faq).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'paloaltonetworks.cloudngfw/firewalls'
| project name, location, isPanorama = tostring(properties.isPanoramaManaged), isStrata = tostring(properties.isStrataCloudManaged), rulestackId = tostring(properties.associatedRulestack.resourceId)
```

- **Pass / Fail**: **Pass** if one management authority (Azure Rulestack, Panorama, or Strata Cloud Manager) is applied consistently and the teardown runbook enforces reverse dependency order: **`1. Routing Intent -> 2. Cloud NGFW resource -> 3. Hub SaaS resource -> 4. Virtual Hub`**.

### A-SEC-16

- **Checklist control**: [SEC-16](/azure-networking/06-operations-reviews/vwan-review-checklist/#sec-16): Inbound DNAT (`<= 80` standard Secured Hub AzFW PIPs) scoped to hub-local backends in Direct Access mode.
- **Learn reference**: [Securing internet access with routing intent: Known limitations](https://learn.microsoft.com/en-us/azure/virtual-wan/about-internet-routing#known-limitations) and [Secured Virtual Hub public IP limit](https://learn.microsoft.com/en-us/azure/firewall-manager/secured-virtual-hub).
- **Verification (Architecture & Policy Review)**: Export Azure Firewall DNAT Rule Collections (`az network firewall policy rule-collection-group list`) or Cloud NGFW DNAT rules, confirm standard Secured Hub Azure Firewalls stay at `<= 80` public IPs, verify every translated private IP belongs to a spoke VNet or branch attached to **that same regional hub**, and confirm the hub uses **Direct Access** mode (never Hub Forced Tunnel mode).
- **Pass / Fail**: **Pass** if zero cross-hub DNAT targets exist, PIP count stays within limit, and Forced Tunnel hubs host zero inbound DNAT rules.

---

## 5. Performance efficiency verification (`A-PERF`)

### A-PERF-01

- **Checklist control**: [PERF-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-01): Hub placement near latency centers.
- **Learn reference**: [WAF Virtual WAN: Performance Efficiency](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/azure-virtual-wan#performance-efficiency).
- **Verification**: Compare hub `location` values (`A-RES-02`) against ExpressRoute peering cities, major branch populations, and spoke VNet regions; benchmark actual RTT using [`tools/netbench`](/azure-networking/06-operations-reviews/labs-and-tools-guide/).
- **Pass / Fail**: **Pass** if spoke VNets connect to local-region hubs without cross-continent hairpins.

### A-PERF-02

- **Checklist control**: [PERF-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-02): S2S VPN Gateway scale units sized for p95 peak plus ExpressRoute failover.
- **Learn reference**: [Virtual WAN FAQ: Gateway scale units](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-faq#what-are-virtual-wan-gateway-scale-units).
- **Verification (`az` CLI)**:

```bash
az network vpn-gateway list -g <rg> \
  --query "[].{Name:name, Location:location, ScaleUnits:vpnGatewayScaleUnit}" -o table
```

Compare against 30-day p95 `TunnelBandwidth` in Azure Monitor Metrics. Each S2S scale unit (`1-20`) provisions `500 Mbps` per gateway instance across two active-active instances (`1 Gbps/unit` aggregate, up to `10 Gbps` per instance and `20 Gbps` aggregate at `20` units).
- **Pass / Fail**: **Pass** if provisioned gateway capacity (`ScaleUnits * 1 Gbps` aggregate across active-active ECMP tunnels, or `ScaleUnits * 500 Mbps` when pinned to a single instance) exceeds p95 peak plus ExpressRoute failover load with `>= 25%` headroom.

### A-PERF-03

- **Checklist control**: [PERF-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-03): ExpressRoute Gateway scale units (`2 Gbps/unit`) and FastPath evaluation.
- **Learn reference**: [ExpressRoute gateway SKU performance in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/virtual-wan-faq#in-virtual-wan-what-are-the-estimated-performances-by-expressroute-gateway-sku) and [ExpressRoute FastPath & SKUs](/azure-networking/03-hybrid-connectivity/expressroute-fastpath-and-skus/).
- **Verification (`az` CLI)**:

```bash
az network express-route gateway list -g <rg> \
  --query "[].{Name:name, Location:location, MinUnits:autoScaleConfiguration.bounds.min, MaxUnits:autoScaleConfiguration.bounds.max}" -o table
```

- **Pass / Fail**: **Pass** if `MinUnits * 2 Gbps` (and `MinUnits * 200,000 PPS`, `MinUnits >= 2` to avoid maintenance dips on scale unit 1) covers sustained p95 load and FastPath requirements are documented.

### A-PERF-04

- **Checklist control**: [PERF-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-04): Hub router `50 Gbps` aggregate ceiling, `10,000` route limit, and `1.5 Gbps` single-flow limit respected.
- **Learn reference**: [Virtual hub capacity](https://learn.microsoft.com/en-us/azure/virtual-wan/hub-settings#capacity) and [Azure Virtual WAN limits](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits#azure-virtual-wan-limits).
- **Verification**: Inspect Azure Monitor Virtual Hub metric `VirtualHubDataProcessed` over 30 days (`Bytes * 8 / IntervalSeconds / 1e9`) and verify learned routes remain well below `10,000`. Note that traffic steered by Routing Intent bypasses the hub router data plane.
- **Pass / Fail**: **Pass** if peak hub router throughput stays below `40 Gbps` (`80%` of the `50 Gbps` ceiling), workloads use multi-stream transfers below `1.5 Gbps` per TCP flow, and high-throughput intra-region flows above that mark use a second hub or direct VNet peering.

### A-PERF-05

- **Checklist control**: [PERF-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-05): `GCMAES256` IPsec cipher for hardware offload.
- **Verification**: Same query as [A-SEC-07](#a-sec-07).
- **Pass / Fail**: **Pass** if `ipsecEncryption == "GCMAES256"` and `ipsecIntegrity == "GCMAES256"` on high-throughput S2S links.

### A-PERF-06

- **Checklist control**: [PERF-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-06): `hubRoutingPreference` aligned with primary hybrid transport.
- **Learn reference**: [About virtual hub routing preference](https://learn.microsoft.com/en-us/azure/virtual-wan/about-virtual-hub-routing-preference).
- **Verification (`az` CLI)**:

```bash
az network vhub list -g <rg> --query "[].{Hub:name, Location:location, Preference:hubRoutingPreference}" -o table
```

- **Pass / Fail**: **Pass** if set intentionally (`ExpressRoute` for ER-primary WANs without bow-tie VNet hairpins, `ASPath` when preserving BGP AS-path length across multi-hub or bow-tied topologies, `VpnGateway` for VPN/SD-WAN-primary networks).

### A-PERF-07

- **Checklist control**: [PERF-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#perf-07): Proactive 70% and 80% capacity alerts.
- **Verification (`az` CLI)**: Same metric alert audit as [A-OPS-07](#a-ops-07), confirming threshold rules at 70% (warning) and 80% (planned scale-up window).
- **Pass / Fail**: **Pass** if utilization threshold alerts are active and routed to NetOps on-call.

---

## 6. Operational excellence verification (`A-OPS`)

### A-OPS-01

- **Checklist control**: [OPS-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-01): 100% modular Bicep or Terraform IaC coverage.
- **Verification (`Repository & Deployment History Audit`)**:

```bash
az deployment group list -g <connectivity-rg> --query "[0:10].{Name:name, State:properties.provisioningState, Timestamp:properties.timestamp}" -o table
```

- **Pass / Fail**: **Pass** if all hub, gateway, firewall policy, and Routing Intent changes deploy from Git-backed Bicep or Terraform templates (API `2022-05-01` or newer) with zero-drift `what-if` or `terraform plan` output.

### A-OPS-02

- **Checklist control**: [OPS-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-02): CI/CD validation, approval gates, and rollback runbook.
- **Verification**: Inspect GitHub Actions or Azure DevOps environment protection rules and verify `what-if` or `plan` diffs require peer review before production apply.
- **Pass / Fail**: **Pass** if production deployments enforce environment approval gates and automated route-table snapshot steps.

### A-OPS-03

- **Checklist control**: [OPS-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-03): Azure Monitor Insights for Virtual WAN enabled.
- **Learn reference**: [Azure Monitor Insights for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/azure-monitor-insights).
- **Verification (Portal)**: Open **Virtual WAN -> Monitor -> Insights** (or **Azure Monitor -> Networks**) and confirm autodiscovered topology maps and detailed metrics workbooks render across all hubs.
- **Pass / Fail**: **Pass** if dependency maps and metric workbooks populate across all production hubs.

### A-OPS-04

- **Checklist control**: [OPS-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-04): Resource-Specific Diagnostic Settings on all Hubs, Gateways, and Firewalls.
- **Learn reference**: [Monitor Azure Firewall logs and metrics](https://learn.microsoft.com/en-us/azure/firewall/firewall-diagnostics) and [Monitor Virtual WAN reference](https://learn.microsoft.com/en-us/azure/virtual-wan/monitor-virtual-wan-reference).
- **Verification (`az` CLI; `ARG: Microsoft.Insights/diagnosticSettings is not indexed in Resource Graph`)**:

```bash
az resource list -g <connectivity-rg> \
  --query "[?type=='Microsoft.Network/virtualHubs' || type=='Microsoft.Network/vpnGateways' || type=='Microsoft.Network/expressRouteGateways' || type=='Microsoft.Network/p2sVpnGateways' || type=='Microsoft.Network/azureFirewalls'].id" -o tsv | \
while read -r id; do
  echo "=== $id ==="
  az monitor diagnostic-settings list --resource "$id" \
    --query "[].{Name:name, Workspace:workspaceId, DestType:logAnalyticsDestinationType}" -o table
done
```

- **Pass / Fail**: **Pass** if every hub, gateway, and firewall exports diagnostics to Log Analytics (`Workspace` non-empty) and every Azure Firewall sets `DestType == "Dedicated"` (Resource-Specific tables `AZFWNetworkRule`, `AZFWApplicationRule`, `AZFWNatRule`, `AZFWIdpsSignature`).

### A-OPS-05

- **Checklist control**: [OPS-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-05): Network Watcher Connection Monitor synthetic coverage.
- **Learn reference**: [Connection Monitor overview](https://learn.microsoft.com/en-us/azure/network-watcher/connection-monitor-overview).
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/networkwatchers/connectionmonitors'
| project name, location, resourceGroup, testGroups = array_length(properties.testGroups)
```

- **Pass / Fail**: **Pass** if synthetic probes continuously measure TCP or ICMP reachability and packet loss across spoke-to-spoke, inter-hub, and hybrid branch paths.

### A-OPS-06

- **Checklist control**: [OPS-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-06): VNet Flow Logs and Traffic Analytics enabled on spoke VNets.
- **Learn reference**: [Virtual network flow logs overview](https://learn.microsoft.com/en-us/azure/network-watcher/vnet-flow-logs-overview).
- **Common misconfiguration**: Relying on retiring NSG Flow Logs or enabling VNet Flow Logs without turning on Traffic Analytics.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| extend vnetId = tolower(id)
| join kind=leftouter (
    resources
    | where type =~ 'microsoft.network/networkwatchers/flowlogs'
    | where tobool(properties.enabled) == true
    | project flowLogName = name, targetId = tolower(tostring(properties.targetResourceId)),
              trafficAnalytics = tobool(properties.flowAnalyticsConfiguration.networkWatcherFlowAnalyticsConfiguration.enabled)
  ) on $left.vnetId == $right.targetId
| where isempty(flowLogName) or trafficAnalytics != true
| project vnet = name, location, resourceGroup, subscriptionId, flowLogName, trafficAnalytics
```

- **Pass / Fail**: **Pass** if **0 rows** are returned across production spoke VNets (`enabled == true` and `trafficAnalytics == true`).

### A-OPS-07

- **Checklist control**: [OPS-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-07): Alerts on Virtual WAN and Firewall metrics.
- **Learn reference**: [Virtual WAN monitoring data reference](https://learn.microsoft.com/en-us/azure/virtual-wan/monitor-virtual-wan-reference#metrics).
- **Verification (`az` CLI)**:

```bash
az monitor metrics alert list \
  --query '[?enabled==`true`].{Alert:name, RG:resourceGroup, Criteria:criteria.allOf[].metricName}' -o json
```

- **Pass / Fail**: **Pass** if active alerts cover `TunnelEgressPacketDropCount`, `TunnelIngressPacketDropCount`, `BgpPeerStatus`, `RoutingState`, `VirtualHubDataProcessed`, and Firewall `SNATPortUtilization` and `FirewallHealth`.

### A-OPS-08

- **Checklist control**: [OPS-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-08): Staggered customer-controlled maintenance windows (`>= 5 hours` daily).
- **Learn reference**: [Customer-controlled gateway maintenance for Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/customer-controlled-gateway-maintenance) and [Customer-controlled maintenance for Azure Firewall](https://learn.microsoft.com/en-us/azure/firewall/customer-controlled-maintenance).
- **Verification (ARG KQL)**:

```kusto
maintenanceresources
| where type =~ 'microsoft.maintenance/configurationassignments'
| where tostring(properties.resourceId) has_any ('vpnGateways','expressRouteGateways','p2sVpnGateways','azureFirewalls')
| project name, target = tostring(properties.resourceId), configId = tostring(properties.maintenanceConfigurationId)
```

- **Pass / Fail**: **Pass** if primary and secondary regional hub gateways and Azure Firewalls are assigned in `maintenanceresources` to non-overlapping off-hours maintenance windows (minimum 5-hour daily window in the resource's region).

### A-OPS-09

- **Checklist control**: [OPS-09](/azure-networking/06-operations-reviews/vwan-review-checklist/#ops-09): Azure Policy guardrails assigned at Management Group scope.
- **Learn reference**: [Azure Policy built-in definitions](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-policies).
- **Verification (ARG KQL)**:

```kusto
policyresources
| where type =~ 'microsoft.authorization/policyassignments'
| where tostring(properties.displayName) has_any ('Virtual WAN','VPN','ExpressRoute','Firewall','Private Endpoint','Outbound')
| project name, displayName = tostring(properties.displayName), scope = tostring(properties.scope), enforcement = tostring(properties.enforcementMode)
```

- **Pass / Fail**: **Pass** if preventative and DINE policies enforce Standard vWAN SKU, Entra P2S authentication, Private Link DNS zones, and `enforcementMode == "Default"`.

---

## 7. Governance & cost optimization verification (`A-GOV`)

### A-GOV-01

- **Checklist control**: [GOV-01](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-01): Pre-deployment TCO model (fixed hourly units plus per-GB meters).
- **Learn reference**: [About Virtual WAN pricing](https://learn.microsoft.com/en-us/azure/virtual-wan/pricing-concepts) and [Hub-Spoke vs. Virtual WAN](/azure-networking/02-core-topologies/hub-spoke-vs-vwan/).
- **Verification (`Design & FinOps Artifact`)**: Confirm the pricing workbook models Hub Base Fee + Routing Infrastructure Units + Gateway Scale and Connection Units + VNet Peering (`$/GB`, excluding Private Endpoint traffic which bills Private Link data processing) + Hub Router Data Processing (`$/GB` on non-Routing-Intent VNet transit; skipped when traffic is steered via Routing Intent) + Secured Hub Firewall Base and Data Processing (`$/GB`) + Inter-Region Data Transfer.
- **Pass / Fail**: **Pass** if fixed and variable per-GB components are modeled accurately at baseline and peak traffic volumes.

### A-GOV-02

- **Checklist control**: [GOV-02](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-02): FinOps cost-allocation tags enforced on all vWAN resources.
- **Verification (ARG KQL)**:

```kusto
resources
| where type in~ ('microsoft.network/virtualwans','microsoft.network/virtualhubs','microsoft.network/vpngateways','microsoft.network/expressroutegateways','microsoft.network/p2svpngateways','microsoft.network/azurefirewalls')
| where isempty(tostring(tags['CostCenter']))
     or isempty(tostring(tags['Environment']))
     or isempty(tostring(tags['Workload']))
     or isempty(tostring(tags['Owner']))
| project type, name, resourceGroup, existingTags = tags
```

- **Pass / Fail**: **Pass** if **0 rows** are returned across all four required FinOps tags (`CostCenter`, `Environment`, `Workload`, `Owner`).

### A-GOV-03

- **Checklist control**: [GOV-03](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-03): Quarterly scale-unit rightsizing review.
- **Verification**: Compare provisioned VPN/ER gateway scale units and Hub Routing Units (`A-RES-06`, `A-PERF-02`, `A-PERF-03`) against 90-day p95 utilization and connected spoke VM count in Azure Monitor.
- **Pass / Fail**: **Pass** if gateways sustained `< 30%` p95 utilization (outside required DR failover reserve) have scheduled rightsizing changes.

### A-GOV-04

- **Checklist control**: [GOV-04](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-04): Direct VNet peering evaluated for high-volume spoke-to-spoke replication.
- **Verification (ARG KQL)**:

```kusto
resources
| where type =~ 'microsoft.network/virtualnetworks'
| mv-expand peering = properties.virtualNetworkPeerings
| project sourceVnet = name, targetVnet = tostring(peering.properties.remoteVirtualNetwork.id), state = tostring(peering.properties.peeringState)
```

- **Pass / Fail**: **Pass** if high-throughput intra-region storage or database replication spokes either use approved direct VNet peering (with NSG rules) or explicitly budget hub firewall per-GB charges in `A-GOV-01`.

### A-GOV-05

- **Checklist control**: [GOV-05](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-05): Inter-region hub-to-hub bandwidth cost audit.
- **Verification (Azure Cost Management)**: Group Connectivity subscription spend by `MeterCategory == "Bandwidth"` and `MeterSubCategory` over the trailing 90 days.
- **Pass / Fail**: **Pass** if top cross-region talkers (identified via VNet Flow Logs Traffic Analytics) align with approved DR or active-active requirements.

### A-GOV-06

- **Checklist control**: [GOV-06](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-06): Cost Management budgets and anomaly alerts configured.
- **Verification (`az` CLI)**:

```bash
az consumption budget list --subscription <connectivity-sub-id> -o table
```

- **Pass / Fail**: **Pass** if active monthly or quarterly budgets trigger alerts at `80%`, `100%`, and `110%` forecasted spend alongside Cost Anomaly alerts.

### A-GOV-07

- **Checklist control**: [GOV-07](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-07): Branch transport tiering (ExpressRoute vs. S2S VPN) aligned to criticality.
- **Verification**: Cross-reference branch site criticality tiers (Tier 1 DC/HQ vs. Tier 3 small branch) against `expressRouteConnections` and `vpnConnections` per hub.
- **Pass / Fail**: **Pass** if ExpressRoute circuits are reserved for latency, throughput, or SLA-critical sites while small branches use S2S IPsec or SD-WAN.

### A-GOV-08

- **Checklist control**: [GOV-08](/azure-networking/06-operations-reviews/vwan-review-checklist/#gov-08): Cloud NGFW SaaS and Marketplace NVA consumption governed.
- **Learn reference**: [Palo Alto Cloud NGFW in Virtual WAN](https://learn.microsoft.com/en-us/azure/virtual-wan/how-to-palo-alto-cloud-ngfw).
- **Verification**: Filter Azure Cost Management by `PublisherType == "Marketplace"` and resource provider `PaloAltoNetworks.Cloudngfw`, verify committed vs. PAYG tiering, and confirm zero orphaned `Microsoft.Network/networkVirtualAppliances` NVA-IU charges remain on Cloud NGFW hubs.
- **Pass / Fail**: **Pass** if Marketplace SaaS spend has dedicated budget alerts and zero duplicate NVA-IU billing.
