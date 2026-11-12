# ExpressRoute datapath, FastPath and FastPath IP limits 

This article is co-authored by Microsoft colleague [David Santiago](https://github.com/davidsntg). The content is now also available and updated on the [Microsoft Tech Community blog](https://techcommunity.microsoft.com/t5/azure-networking-blog/expressroute-fastpath-for-udrs-and-vnet-peering/ba-p/4171115), go and check it out!

## Default behavior

The data flow between On-Prem and Azure using ExpressRoute is asymmetric by design. 

Traffic from On-Prem to Azure transits via the ExpressRoute Gateway but the return traffic (Azure to On-Prem) bypasses the ExpressRoute Gateway and is forwarded directly to the MSEEs.

![](images/ExRGwDataPath.gif)

If multiple ExpressRoute Circuits are advertising copies of the same On-Prem routes and are connected to the same ExpressRoute Gateway, Azure to On-Prem traffic is ECMPed across the different ExpressRoute Circuits available unless traffic engineering is configured to prioritise 1 path over the others.

## With ExpressRoute FastPath

Enabling the [ExpressRoute FastPath](https://learn.microsoft.com/en-us/azure/expressroute/about-fastpath) feature allows On-Prem to Azure traffic to bypass the ExpressRoute Gateway as well, leading to improved data path performances: 

![](images/ExRGwDataPathFastPath.gif)

This results in reduced latency and the ability to exceed the ExpressRoute Gateway maximum throughput limit of 10 Gbps.

Current constraints and limitations (as of November 2023):
- **Available only on Ultra Performance or ErGw3AZ**
- [IP address limit*](https://learn.microsoft.com/en-us/azure/expressroute/about-fastpath#ip-address-limits)
- Limited support of Private Link for ExpressRoute Direct circuits only, not supported at all on ExpresRoute partner circuits
- FastPath support for [UDRs](https://learn.microsoft.com/en-us/azure/expressroute/about-fastpath#user-defined-routes-udrs) on the Gateway subnet and for [VNet peering](https://learn.microsoft.com/en-us/azure/expressroute/about-fastpath#virtual-network-vnet-peering) is still in preview and available for ExpressDirect circuits only

> ExpressRoute FastPath is configured [**per connection**](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-howto-linkvnet-arm#configure-expressroute-fastpath).

## *About the FastPath IP address limit

In our documentation, we specify the following limits for the number of **FastPath IPs**: 

| **ExpressRoute SKU** | **Bandwidth** | **FastPath IP limit** |
|-|-|-|
| ExpressRoute Direct | 100 Gbps | **200k** |
| ExpressRoute Direct | 10 Gbps | **100k** |
|ExpressRoute provider circuit | =< 10 Gbps| **25k** |

When FastPath is enabled, this limit is the maximum number of Azure endpoints in the VNet environment that will be configured to bypass the ExpressRoute Gateway. Whenever a new IP address is added or removed, the FastPath IPs are automatically reprogrammed to reflect that change, keeping the FastPath IP list up to date. 

The limit is on customer private IPs, a VM with 3 NICs requires 3 FastPath routes counting towards the limit (reminder: FastPath is configured per connection, not per circuit).

> It is important to note that when calculating the limit for FastPath IPs, only endpoints with assigned private IP addresses within a subnet or VNet range are counted. The entire address range won't be included in the calculation of consumed IPs.

Azure Monitor offers metrics for ExpressRoute Direct resources, which includes the ability to track the number of [configured FastPath routes](https://learn.microsoft.com/en-us/azure/expressroute/expressroute-monitoring-metrics-alerts#fastpath-routes-count-at-port-level) at the port level.
