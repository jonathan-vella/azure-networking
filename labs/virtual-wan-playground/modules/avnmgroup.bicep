param avnmName string
param avnmGroupName string
param spokeVNETids array

resource avnmNetworkGroup 'Microsoft.Network/networkManagers/networkGroups@2025-01-01' = {
  name: '${avnmName}/${avnmGroupName}'
  properties: {
    description: 'LabBuilder AVNM - Network Group'
  }
}

resource avnmNetworkGroupMember 'Microsoft.Network/networkManagers/networkGroups/staticMembers@2025-01-01' = [
  for (vnetid, i) in spokeVNETids: {
    name: 'avnmNetworkGroupMember${i}'
    parent: avnmNetworkGroup
    properties: {
      resourceId: vnetid
    }
  }
]

output id string = avnmNetworkGroup.id
