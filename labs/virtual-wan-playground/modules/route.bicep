param routeName string
@allowed([
  'VirtualAppliance'
  'Internet'
  'VnetLocal'
  'VirtualNetworkGateway'
  'None'
])
param routeNextHopType string = 'VirtualAppliance'
param routeAddressPrefix string
param routeNextHopIpAddress string = ''

resource route 'Microsoft.Network/routeTables/routes@2025-01-01' = {
  name: routeName
  properties: {
    nextHopType: routeNextHopType
    addressPrefix: routeAddressPrefix
    nextHopIpAddress: routeNextHopIpAddress
  }
}
