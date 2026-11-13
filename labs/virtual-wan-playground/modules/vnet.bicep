param location string
param vnetname string
param vnetAddressSpace string
param defaultSubnetPrefix string = ''
param bastionSubnetPrefix string = ''
param firewallSubnetPrefix string = ''
param GatewaySubnetPrefix string = ''
param nsgID string = 'none'
param bastionNSGID string = 'none'
param rtDefID string = 'none'
param rtGwID string = 'none'
param rtFwID string = 'none'
param deployDefaultSubnet bool
param deployBastionSubnet bool = false
param deployFirewallSubnet bool = false
param deployGatewaySubnet bool = false
param tagsByResource object = {}
param firewallDNSproxy bool = false
param azFwIp string = ''
param defaultOutboundAccess bool = true

var defaultSubnet = deployDefaultSubnet
  ? [
      {
        name: 'default'
        properties: {
          addressPrefix: defaultSubnetPrefix
          networkSecurityGroup: nsgID == 'none'
            ? null
            : {
                id: nsgID
              }
          routeTable: rtDefID == 'none'
            ? null
            : {
                id: rtDefID
              }
          defaultOutboundAccess: defaultOutboundAccess
        }
      }
    ]
  : []

var bastionSubnet = deployBastionSubnet
  ? [
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: bastionNSGID == 'none'
            ? null
            : {
                id: bastionNSGID
              }
        }
      }
    ]
  : []

var firewallSubnet = deployFirewallSubnet
  ? [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: firewallSubnetPrefix
          routeTable: rtFwID == 'none'
            ? null
            : {
                id: rtFwID
              }
        }
      }
    ]
  : []

var gatewaySubnet = deployGatewaySubnet
  ? [
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: GatewaySubnetPrefix
          routeTable: rtGwID == 'none'
            ? null
            : {
                id: rtGwID
              }
        }
      }
    ]
  : []

resource vnet 'Microsoft.Network/virtualNetworks@2025-01-01' = {
  name: vnetname
  location: location
  properties: {
    dhcpOptions: {
      dnsServers: firewallDNSproxy ? array(azFwIp) : []
    }
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: concat(defaultSubnet, bastionSubnet, firewallSubnet, gatewaySubnet)
  }
  tags: tagsByResource[?'Microsoft.Network/virtualNetworks'] ?? {}
}

output vnetName string = vnet.name
output vnetID string = vnet.id
output vnetAddressSpace array = vnet.properties.addressSpace.addressPrefixes
output defaultSubnetID string = deployDefaultSubnet
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, 'default')
  : 'Not deployed'
output bastionSubnetID string = deployBastionSubnet
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, 'AzureBastionSubnet')
  : 'Not deployed'
output firewallSubnetID string = deployFirewallSubnet
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, 'AzureFirewallSubnet')
  : 'Not deployed'
output gatewaySubnetID string = deployGatewaySubnet
  ? resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, 'GatewaySubnet')
  : 'Not deployed'
