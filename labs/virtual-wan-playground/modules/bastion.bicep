param location string
param bastionName string
param subnetID string
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionSku string = 'Standard'
param tagsByResource object = {}

var isStandardOrPremium = bastionSku == 'Standard' || bastionSku == 'Premium'

resource bastion 'Microsoft.Network/bastionHosts@2025-05-01' = {
  name: bastionName
  location: location
  properties: {
    enableIpConnect: isStandardOrPremium
    enableTunneling: isStandardOrPremium
    scaleUnits: isStandardOrPremium ? 2 : null
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: subnetID
          }
          publicIPAddress: {
            id: bastionpip.id
          }
        }
      }
    ]
  }
  sku: {
    name: bastionSku
  }
  tags: tagsByResource[?'Microsoft.Network/bastionHosts'] ?? {}
}

resource bastionpip 'Microsoft.Network/publicIPAddresses@2025-05-01' = {
  name: '${bastionName}-pip'
  location: location
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
  }
  sku: {
    tier: 'Regional'
    name: 'Standard'
  }
  tags: tagsByResource[?'Microsoft.Network/publicIPAddresses'] ?? {}
}
