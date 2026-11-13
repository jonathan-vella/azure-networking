targetScope = 'subscription'

import { _Locations } from './types.bicep'

// Define the locations for the Lab deployment. max 2 locations. min 1 location.
param locations _Locations = [
  {
    region: 'swedencentral'
    addressSpace: '172.16.0.0/16'
    hubSubscriptionID: subscription().subscriptionId
    spokeSubscriptionID: subscription().subscriptionId
    onPremSubscriptionID: subscription().subscriptionId
  }

  // {
  //   region: 'germanywestcentral'
  //   addressSpace: '172.31.0.0/16'
  //   hubSubscriptionID: subscription().subscriptionId
  //   spokeSubscriptionID: subscription().subscriptionId
  //   onPremSubscriptionID: subscription().subscriptionId
  // }
]

// Virtual Machine parameters
@description('Admin username for Virtual Machines')
param adminUsername string = ''

@description('Admin Password for Virtual Machines')
@secure()
param adminPassword string = ''

@description('Spoke Virtual Machine SKU. Default = Standard_B2ls_v2')
param vmSizeSpoke string = 'Standard_B2ls_v2'

@description('OnPrem Virtual Machine SKU. Default = Standard_B2ls_v2')
param vmSizeOnPrem string = 'Standard_B2ls_v2'

@description('Spoke Virtual Machine(s) OS type. Windows or Linux. Default = Windows')
@allowed([
  'Linux'
  'Windows'
])
param osTypeSpoke string = 'Windows'
@description('OnPrem Virtual Machine OS type. Windows or Linux. Default = Windows')
@allowed([
  'Linux'
  'Windows'
])
param osTypeOnPrem string = 'Windows'

// Shared parameters
@description('Tags by resource types. Default = empty')
param tagsByResource object = {}

@description('LogAnalytics Workspace resourceID')
param diagnosticWorkspaceId string = ''

@description('Resource group name for DCR')
param dcrRgName string = 'rg-dcr'

// Spoke VNET Parameters
@description('Deploy Spoke VNETs. Default = false')
param deploySpokes bool = false

@description('Spoke resource group prefix name. Default = rg-spoke')
param spokeRgNamePrefix string = 'rg-spoke'

@description('Amount of Spoke VNETs you want to deploy. Default = 2')
param amountOfSpokes int = 2

@description('Deploy VM in every Spoke VNET')
param deployVMsInSpokes bool = false

@description('Directly connect VNET Spokes (Fully Meshed Topology)')
param deployVnetPeeringMesh bool = false

@description('Let Azure Virtual Network Manager manage UDRs in Spoke VNETs')
param deployAvnmUDRs bool = false

@description('Enable or Disable default outbound access on Subnets. Default = true')
param defaultOutboundAccess bool = true

// Hub VNET Parameters
@description('Deploy Hub')
param deployHUB bool = true

@description('Deploy Hub VNET or Azure vWAN. Default = VNET')
@allowed([
  'VNET'
  'VWAN'
])
param hubType string = 'VNET'

@description('Hub resource group prefix name. Default = rg-hub')
param hubRgName string = 'rg-hub'

@description('Deploy Bastion Host in Hub VNET. Default = false')
param deployBastionInHub bool = false

@description('Hub Bastion SKU. Default = Standard')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionInHubSKU string = 'Standard'

@description('Deploy Virtual Network Gateway in Hub VNET')
param deployGatewayInHub bool = false

@description('Deploy Azure Firewall in Hub VNET. includes deployment of custom route tables in Spokes and Hub VNETs')
param deployFirewallInHub bool = false

@description('Azure Firewall Tier: Standard or Premium')
@allowed([
  'Standard'
  'Premium'
])
param AzureFirewallTier string = 'Standard'

@description('Deploy Firewall policy Rule Collection group which allows spoke-to-spoke and internet traffic')
param deployFirewallrules bool = false

@description('Enable Azure Firewall DNS Proxy')
param firewallDNSproxy bool = false

@description('Deploy route tables (UDRs) to VM subnet(s) in Hub and Spokes')
param deployUDRs bool = true

@description('Enable BGP on Hub Gateway')
param hubBgp bool = true

@description('Hub BGP ASN')
@minValue(1)
@maxValue(4294967294)
param hubBgpAsn int = 65515

// AVNM parameters
@description('AVNM resource group name. Default = rg-avnm')
param avnmRgName string = 'rg-avnm'

@description('Let Azure Virtual Network Manager manage Peerings in Hub&Spoke')
param deployVnetPeeringAVNM bool = false

// Routing Intent Policy parameters for vWAN
@description('Enable Azure vWAN routing Intent Policy for Internet Traffic')
param internetTrafficRoutingPolicy bool = false

@description('Enable Azure vWAN routing Intent Policy for Private Traffic')
param privateTrafficRoutingPolicy bool = false

// OnPrem parameters
@description('Deploy simulated OnPrem VNET')
param deployOnPrem bool = false

@description('OnPrem Resource Group Name')
param onpremRgName string = 'rg-onprem'

@description('Deploy Bastion Host in OnPrem VNET')
param deployBastionInOnPrem bool = false

@description('OnPrem Bastion SKU. Default = Standard')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionInOnPremSKU string = 'Standard'

@description('Deploy VM in OnPrem VNET')
param deployVMinOnPrem bool = false

@description('Deploy Virtual Network Gateway in OnPrem VNET')
param deployGatewayinOnPrem bool = false

@description('Deploy Site-to-Site VPN connection between OnPrem and Hub Gateways')
param deploySiteToSite bool = false

@description('Site-to-Site ShareKey')
@secure()
param sharedKey string = ''

@description('Enable BGP on OnPrem Gateway')
param onpremBgp bool = true

@description('OnPrem BGP ASN')
@minValue(1)
@maxValue(4294967294)
param onpremBgpAsn int = 65020

// Define unique short codes for Azure Public Cloud regions, with automatic fallback for newly added regions.
var regionShortCodes = {
  southafricanorth: 'SAN'
  southafricawest: 'SAW'
  australiaeast: 'AUE'
  australiacentral: 'AUC'
  australiacentral2: 'AU2'
  australiasoutheast: 'AUS'
  centralindia: 'CIN'
  indiasouthcentral: 'INS'
  jioindiacentral: 'JIC'
  jioindiawest: 'JIW'
  southindia: 'SIN'
  westindia: 'WIN'
  eastasia: 'EAS'
  indonesiacentral: 'IDC'
  japaneast: 'JAE'
  japanwest: 'JAW'
  koreacentral: 'KOC'
  koreasouth: 'KOS'
  malaysiawest: 'MYW'
  newzealandnorth: 'NZN'
  southeastasia: 'SEA'
  taiwannorth: 'TWN'
  canadacentral: 'CAC'
  canadaeast: 'CAE'
  austriaeast: 'ATE'
  belgiumcentral: 'BEC'
  denmarkeast: 'DKE'
  francecentral: 'FRC'
  francesouth: 'FRS'
  germanynorth: 'GNO'
  germanywestcentral: 'GWC'
  italynorth: 'ITN'
  northeurope: 'NEU'
  norwayeast: 'NOE'
  norwaywest: 'NOW'
  polandcentral: 'POC'
  spaincentral: 'SPC'
  swedencentral: 'SCE'
  swedensouth: 'SCS'
  switzerlandnorth: 'SWN'
  switzerlandwest: 'SWW'
  uksouth: 'UKS'
  ukwest: 'UKW'
  westeurope: 'WEU'
  chilecentral: 'CLC'
  mexicocentral: 'MEC'
  israelcentral: 'ISC'
  qatarcentral: 'QAC'
  uaecentral: 'UAC'
  uaenorth: 'UAE'
  brazilsouth: 'BRS'
  brazilsoutheast: 'BSE'
  centralus: 'CUS'
  eastus: 'EUS'
  eastus2: 'EUS2'
  northcentralus: 'NCU'
  southcentralus: 'SCU'
  westcentralus: 'WCU'
  westus: 'WUS'
  westus2: 'WUS2'
  westus3: 'WUS3'
}

var isMultiRegion = length(locations) > 1
var firstRegionShortCode = regionShortCodes[?locations[0].region] ?? toUpper(take(locations[0].region, 4))
var secondRegionShortCode = isMultiRegion
  ? (regionShortCodes[?locations[1].region] ?? toUpper(take(locations[1].region, 4)))
  : 'SingleRegion'
var isVnetHub = hubType == 'VNET'
var isVwanHub = hubType == 'VWAN'

var avnmSubscriptions = [
  for (location, i) in locations: deployAVNM
    ? [
        '/subscriptions/${subscription().subscriptionId}'
        '/subscriptions/${location.?hubSubscriptionID}'
        '/subscriptions/${location.?spokeSubscriptionID}'
      ]
    : [
        'NoAVNM'
      ]
]
var avnmSubscriptionScopes = union(flatten(avnmSubscriptions), flatten(avnmSubscriptions))

// validate if we need to deploy vWAN
var deployVWAN = deployHUB && isVwanHub

// VWAN
// Create resource group for the vWAN
resource vwanhubrg 'Microsoft.Resources/resourceGroups@2025-04-01' = if (deployVWAN) {
  name: hubRgName
  location: locations[0].region
  tags: tagsByResource[?'Microsoft.Resources/subscriptions/resourceGroups'] ?? {}
}

// Create vWAN instance in the vWAN Hub resource group
module vwan 'modules/vwan.bicep' = if (deployVWAN) {
  scope: vwanhubrg
  name: 'vWAN'
  params: {
    location: locations[0].region
    tagsByResource: tagsByResource
    vWanName: 'vWAN'
  }
}

// validate if we need to deploy AVNM
var deployAVNM = deployHUB && deploySpokes && isVnetHub && deployVnetPeeringAVNM

// AVNM
// Create resource group for AVNM
resource avnmrg 'Microsoft.Resources/resourceGroups@2025-04-01' = if (deployAVNM) {
  name: avnmRgName
  location: locations[0].region
  tags: tagsByResource[?'Microsoft.Resources/subscriptions/resourceGroups'] ?? {}
}

// create AVNM instance in AVNM resource group
module avnmmanager 'modules/avnmmanager.bicep' = if (deployAVNM) {
  scope: avnmrg
  name: 'AVNM'
  params: {
    location: locations[0].region
    tagsByResource: tagsByResource
    avnmName: 'AVNM'
    avnmSubscriptionScopes: avnmSubscriptionScopes
  }
}

// VMInsights DCR
// Create resource group for DCR
resource dcrrg 'Microsoft.Resources/resourceGroups@2025-04-01' = if (!empty(diagnosticWorkspaceId)) {
  name: dcrRgName
  location: locations[0].region
  tags: tagsByResource[?'Microsoft.Resources/subscriptions/resourceGroups'] ?? {}
}

// create DCR instance in DCR resource group
module dcrvminsights 'modules/dcrvminsights.bicep' = if (!empty(diagnosticWorkspaceId)) {
  scope: dcrrg
  name: 'dcr-vminsights'
  params: {
    diagnosticWorkspaceId: diagnosticWorkspaceId ?? ''
    location: locations[0].region
    tagsByResource: tagsByResource
  }
}

// REGIONS
// Deploy region(s)
module deployRegion 'mainRegion.bicep' = [
  for (location, i) in locations: {
    scope: subscription(location.hubSubscriptionID)
    name: 'deployRegion-${regionShortCodes[?location.region] ?? toUpper(take(location.region, 4))}'
    params: {
      location: location.region
      isMultiRegion: isMultiRegion
      shortLocationCode: regionShortCodes[?location.region] ?? toUpper(take(location.region, 4))
      rootSubscriptionID: subscription().subscriptionId
      hubSubscriptionID: location.hubSubscriptionID
      spokeSubscriptionID: location.spokeSubscriptionID
      onPremSubscriptionID: location.onPremSubscriptionID
      adminUsername: adminUsername
      adminPassword: adminPassword
      vmSizeSpoke: vmSizeSpoke
      vmSizeOnPrem: vmSizeOnPrem
      osTypeSpoke: osTypeSpoke
      osTypeOnPrem: osTypeOnPrem
      AddressSpace: location.addressSpace
      SecondRegionAddressSpace: i == 0 ? locations[?1].?addressSpace ?? 'NoSecondRegion' : locations[0].addressSpace
      amountOfSpokes: amountOfSpokes
      spokeRgNamePrefix: spokeRgNamePrefix
      AzureFirewallTier: AzureFirewallTier
      bastionInHubSKU: bastionInHubSKU
      bastionInOnPremSKU: bastionInOnPremSKU
      hubBgp: hubBgp
      defaultOutboundAccess: defaultOutboundAccess
      deployAvnmUDRs: deployAvnmUDRs
      deployBastionInHub: deployBastionInHub
      deployBastionInOnPrem: deployBastionInOnPrem
      deployFirewallInHub: deployFirewallInHub
      deployGatewayInHub: deployGatewayInHub
      deployGatewayinOnPrem: deployGatewayinOnPrem
      deployHUB: deployHUB
      deployOnPrem: deployOnPrem
      deploySpokes: deploySpokes
      deployVMsInSpokes: deployVMsInSpokes
      deployVnetPeeringMesh: deployVnetPeeringMesh
      avnmRgName: deployAVNM ? avnmrg.name : 'noAVNM'
      avnmName: deployAVNM ? avnmmanager!.outputs.name : 'noAVNM'
      avnmUserAssignedIdentityId: deployAVNM ? avnmmanager!.outputs.uaiId : 'noAVNM'
      deployVnetPeeringAVNM: deployVnetPeeringAVNM
      deployUDRs: deployUDRs
      tagsByResource: tagsByResource
      internetTrafficRoutingPolicy: internetTrafficRoutingPolicy
      privateTrafficRoutingPolicy: privateTrafficRoutingPolicy
      sharedKey: sharedKey
      hubBgpAsn: hubBgpAsn
      onpremBgpAsn: onpremBgpAsn + i
      onpremBgp: onpremBgp
      deployFirewallrules: deployFirewallrules
      firewallDNSproxy: firewallDNSproxy
      deploySiteToSite: deploySiteToSite
      deployVMinOnPrem: deployVMinOnPrem
      hubRgName: vwanhubrg.name
      onpremRgName: onpremRgName
      hubType: hubType
      vWanID: deployVWAN ? vwan!.outputs.ID : 'noVWAN'
      dcrID: !empty(diagnosticWorkspaceId) ? dcrvminsights!.outputs.dcrID : ''
    }
  }
]

// variable to validate if we need to deploy global vnet peering
var deployGlobalVnetPeerings = isMultiRegion && isVnetHub && deployHUB

// If MultiRegion and VnetHub, deploy Global Vnet Peerings
module GlobalVnetPeerings 'VnetPeerings.bicep' = if (deployGlobalVnetPeerings) {
  name: 'deployGlobalVnetPeerings-${firstRegionShortCode}-${secondRegionShortCode}'
  params: {
    vnetIDA: deployGlobalVnetPeerings ? deployRegion[0].outputs.HubVnetID : 'noMultiRegion'
    vnetIDB: deployGlobalVnetPeerings ? deployRegion[1].outputs.HubVnetID : 'noMultiRegion'
  }
}

// variable to validate if we need to deploy these routes
var deployRoutes = isMultiRegion && deployFirewallInHub && deployUDRs && isVnetHub && deployHUB

// If MultiRegion and deployFirewallInHub and deployUDRs, deploy routes in both Hubs
module route 'modules/route.bicep' = [
  for (location, i) in locations: if (deployRoutes) {
    scope: resourceGroup(
      location.hubSubscriptionID,
      '${hubRgName}-${regionShortCodes[?location.region] ?? toUpper(take(location.region, 4))}'
    )
    name: 'DeployRegionRoute-${regionShortCodes[?location.region] ?? toUpper(take(location.region, 4))}'
    params: {
      routeName: deployRoutes
        ? '${deployRegion[i].outputs.HubRtFirewallName}/toRegion${i == 0 ? secondRegionShortCode : firstRegionShortCode}'
        : 'noRoute'
      routeNextHopType: 'VirtualAppliance'
      routeNextHopIpAddress: deployRoutes
        ? deployRegion[length(locations) == 2 && i == 0 ? 1 : 0].outputs.VNET_AzFwPrivateIp
        : 'noRoute'
      routeAddressPrefix: deployRoutes ? locations[length(locations) == 2 && i == 0 ? 1 : 0].addressSpace : 'noRoute'
    }
  }
]

// variable to validate if we need to deploy VPN connections
var deployCrossRegionVPNConnections = deployGatewayInHub && deployGatewayinOnPrem && deploySiteToSite && deployHUB && deployOnPrem && isMultiRegion && (isVnetHub || isVwanHub)

module CrossRegionVPNConnections 'VpnCrossRegionConnections.bicep' = [
  for (location, i) in locations: if (deployCrossRegionVPNConnections) {
    name: 'CrossRegionVPNConnections${i+1}-${firstRegionShortCode}-${secondRegionShortCode}'
    params: {
      HubVPN: deployCrossRegionVPNConnections
        ? deployRegion[length(locations) == 2 && i == 0 ? 1 : 0].outputs.VpnSettings.Hub
        : deployRegion[0].outputs.VpnSettings.Hub

      OnPrem: deployCrossRegionVPNConnections
        ? deployRegion[length(locations) == 2 && i == 0 ? 0 : 1].outputs.VpnSettings.OnPrem
        : deployRegion[0].outputs.VpnSettings.OnPrem

      sharedKey: sharedKey
      tagsByResource: tagsByResource
      routingIntent: internetTrafficRoutingPolicy || privateTrafficRoutingPolicy
    }
  }
]

// Outputs
output vWanHubIDs array = [for (location, i) in locations: deployVWAN ? deployRegion[i].outputs.vWanHubID : 'noVWAN']
output subscriptionIDs array = union(
  deployHUB ? map(locations, loc => loc.hubSubscriptionID) : [],
  deploySpokes ? map(locations, loc => loc.spokeSubscriptionID) : [],
  deployOnPrem ? map(locations, loc => loc.onPremSubscriptionID) : []
)
