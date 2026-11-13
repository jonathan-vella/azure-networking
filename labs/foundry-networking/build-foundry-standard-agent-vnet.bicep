// =============================================================================
// Microsoft Foundry (AI Services & Project) — Standard Agent BYO-VNet Lab
//
// Deploys an enterprise-isolated Microsoft Foundry Standard Agent environment:
//   - Spoke/Workload VNet with:
//       * snet-foundry-agent (/24) delegated to Microsoft.App/environments
//       * snet-private-endpoints (/24) with privateEndpointNetworkPolicies Disabled
//   - Optional Hub VNet (AzureFirewallSubnet + AzureBastionSubnet) + VNet Peering
//   - Private DNS Zones + VNet Links:
//       * privatelink.cognitiveservices.azure.com
//       * privatelink.openai.azure.com
//       * privatelink.services.ai.azure.com
//       * privatelink.blob.core.windows.net
//       * privatelink.documents.azure.com
//       * privatelink.search.windows.net
//       * privatelink.vaultcore.azure.net
//   - BYO Agent State & Secrets Resources (all publicNetworkAccess: Disabled):
//       * Azure Storage Account (Blob Private Endpoint)
//       * Azure Key Vault (RBAC + Vault Private Endpoint)
//       * Azure Cosmos DB for NoSQL (Sql Private Endpoint)
//       * Azure AI Search (searchService Private Endpoint)
//       * Microsoft Foundry Account (kind: AIServices, allowProjectManagement: true,
//         VNet agent subnet injection) + Foundry Project + Connections + Capability Hosts
// =============================================================================

targetScope = 'resourceGroup'

@description('Azure region for all regional resources. Must support Foundry Agent Service VNet injection.')
param location string = resourceGroup().location

@minLength(3)
@maxLength(12)
@description('Short alphanumeric name prefix used to generate globally unique resource names.')
param namePrefix string = 'foundrylab'

@description('Deploy an optional Hub VNet (with AzureFirewallSubnet & AzureBastionSubnet) peered to the Foundry Spoke VNet.')
param deployHubVnet bool = false

@description('CIDR block for the Foundry workload (spoke) VNet.')
param spokeVnetAddressPrefix string = '10.110.0.0/16'

@description('CIDR block for the Foundry Agent subnet (/27 minimum, /24 recommended; delegated to Microsoft.App/environments).')
param agentSubnetPrefix string = '10.110.1.0/24'

@description('CIDR block for the Private Endpoint subnet.')
param privateEndpointSubnetPrefix string = '10.110.2.0/24'

@description('CIDR block for the optional Hub VNet.')
param hubVnetAddressPrefix string = '10.100.0.0/16'

@description('CIDR block for AzureFirewallSubnet when deployHubVnet is true.')
param hubFirewallSubnetPrefix string = '10.100.1.0/26'

@description('CIDR block for AzureBastionSubnet when deployHubVnet is true.')
param hubBastionSubnetPrefix string = '10.100.2.0/26'

@description('Name of the Microsoft Foundry Project created inside the Foundry Account.')
param projectName string = 'agent-project'

@description('Deploy a default gpt-4o model deployment inside the Foundry Account.')
param deployModel bool = true

@description('Model name when deployModel is true.')
param modelName string = 'gpt-4o'

@description('Model version when deployModel is true.')
param modelVersion string = '2024-11-20'

@description('Model capacity (in thousands of tokens per minute) when deployModel is true.')
param modelCapacity int = 10

@description('Deploy Project Capability Host (and optional Account Capability Host when createAccountCapabilityHost is true). Requires caller to hold Storage Blob Data Contributor & Cosmos DB Operator.')
param deployCapabilityHosts bool = true

@description('Explicitly create the account-level Capability Host (<account>@aml_aiagentservice). Keep false on fresh networkInjections deployments because Microsoft.CognitiveServices auto-creates it; set true only when recreating a deleted account Capability Host.')
param createAccountCapabilityHost bool = false

@description('Tags applied to all provisioned resources.')
param tags object = {
  workload: 'microsoft-foundry-standard-agent'
  environment: 'lab'
}

var suffix = substring(uniqueString(subscription().id, resourceGroup().id, namePrefix), 0, 6)
var cleanPrefix = toLower(replace(replace(namePrefix, '-', ''), '_', ''))

var spokeVnetName = 'vnet-${namePrefix}-spoke-${suffix}'
var hubVnetName = 'vnet-${namePrefix}-hub-${suffix}'
var agentNsgName = 'nsg-${namePrefix}-agent-${suffix}'
var peNsgName = 'nsg-${namePrefix}-pe-${suffix}'

var storageAccountName = take('${cleanPrefix}st${suffix}', 24)
var keyVaultName = take('kv-${namePrefix}-${suffix}', 24)
var cosmosAccountName = take('cosmos-${namePrefix}-${suffix}', 44)
var searchServiceName = take('srch-${namePrefix}-${suffix}', 60)
var foundryAccountName = take('ais-${namePrefix}-${suffix}', 64)

var storageConnectionName = 'conn-byo-storage'
var cosmosConnectionName = 'conn-byo-cosmos'
var searchConnectionName = 'conn-byo-search'

var privateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.documents.azure.com'
  'privatelink.search.windows.net'
  'privatelink.vaultcore.azure.net'
]

// Built-in RBAC role definition IDs for Project Managed Identity runtime access
var storageBlobDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var searchIndexDataContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
var searchServiceContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
var cosmosDbOperatorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '230815da-be43-4aae-9cb4-875f7bd000aa')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')

// -----------------------------------------------------------------------------
// 1. Network Security Groups & Virtual Networks (Isolated or Hub-and-Spoke)
// -----------------------------------------------------------------------------
resource agentNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: agentNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-EntraID-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource peNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: peNsgName
  location: location
  tags: tags
  properties: {
    securityRules: []
  }
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: spokeVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        spokeVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-foundry-agent'
        properties: {
          addressPrefix: agentSubnetPrefix
          defaultOutboundAccess: false
          networkSecurityGroup: {
            id: agentNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          defaultOutboundAccess: false
          privateEndpointNetworkPolicies: 'Disabled'
          networkSecurityGroup: {
            id: peNsg.id
          }
        }
      }
    ]
  }
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = if (deployHubVnet) {
  name: hubVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubVnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: hubFirewallSubnetPrefix
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: hubBastionSubnetPrefix
        }
      }
    ]
  }
}

resource peeringSpokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (deployHubVnet) {
  parent: spokeVnet
  name: 'peer-spoke-to-hub'
  properties: {
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource peeringHubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (deployHubVnet) {
  parent: hubVnet
  name: 'peer-hub-to-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

var agentSubnetId = '${spokeVnet.id}/subnets/snet-foundry-agent'
var peSubnetId = '${spokeVnet.id}/subnets/snet-private-endpoints'

// -----------------------------------------------------------------------------
// 2. Private DNS Zones & Virtual Network Links
// -----------------------------------------------------------------------------
resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zoneName in privateDnsZoneNames: {
    name: zoneName
    location: 'global'
    tags: tags
  }
]

resource spokeDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zoneName, i) in privateDnsZoneNames: {
    parent: privateDnsZones[i]
    name: 'link-${spokeVnetName}'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: spokeVnet.id
      }
    }
  }
]

resource hubDnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zoneName, i) in privateDnsZoneNames: if (deployHubVnet) {
    parent: privateDnsZones[i]
    name: 'link-${hubVnetName}'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: hubVnet.id
      }
    }
  }
]

// -----------------------------------------------------------------------------
// 3. BYO Storage, Key Vault, Cosmos DB & AI Search (Public Access Disabled)
// -----------------------------------------------------------------------------
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-blob'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource storageDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones[3].id
        }
      }
    ]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
    }
  }
}

resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${keyVaultName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-vault'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource keyVaultDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-vaultcore-azure-net'
        properties: {
          privateDnsZoneId: privateDnsZones[6].id
        }
      }
    ]
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource cosmosPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmosAccountName}-sql'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-cosmos-sql'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource cosmosDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-documents-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones[4].id
        }
      }
    ]
  }
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  tags: tags
  sku: {
    name: 'standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'disabled'
    disableLocalAuth: true
    networkRuleSet: {
      ipRules: []
      bypass: 'None'
    }
  }
}

resource searchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${searchServiceName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-search'
        properties: {
          privateLinkServiceId: searchService.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
  }
}

resource searchDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: searchPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-search-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZones[5].id
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// 4. Microsoft Foundry Account, VNet Injection, Project, Connections & RBAC
// -----------------------------------------------------------------------------
resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: foundryAccountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: foundryAccountName
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

resource foundryPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${foundryAccountName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-foundry-account'
        properties: {
          privateLinkServiceId: foundryAccount.id
          groupIds: [
            'account'
          ]
        }
      }
    ]
  }
}

resource foundryDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: foundryPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-cognitiveservices-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones[0].id
        }
      }
      {
        name: 'privatelink-openai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones[1].id
        }
      }
      {
        name: 'privatelink-services-ai-azure-com'
        properties: {
          privateDnsZoneId: privateDnsZones[2].id
        }
      }
    ]
  }
}

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployModel) {
  parent: foundryAccount
  name: modelName
  sku: {
    name: 'GlobalStandard'
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

resource foundryProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundryAccount
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'Network-isolated Microsoft Foundry Standard Agent project'
  }
  dependsOn: [
    foundryDnsZoneGroup
    spokeDnsLinks
  ]
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: storageConnectionName
  properties: {
    authType: 'AAD'
    category: 'AzureStorageAccount'
    target: storageAccount.properties.primaryEndpoints.blob
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
    }
  }
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: cosmosConnectionName
  properties: {
    authType: 'AAD'
    category: 'AzureCosmosDb'
    target: cosmosAccount.properties.documentEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccount.id
    }
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01' = {
  parent: foundryProject
  name: searchConnectionName
  properties: {
    authType: 'AAD'
    category: 'CognitiveSearch'
    target: 'https://${searchService.name}.search.windows.net'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
    }
  }
}

// Least-privilege runtime RBAC for Project System-Assigned Managed Identity
resource projectStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, foundryProject.id, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: storageBlobDataContributorRoleId
  }
}

resource projectCosmosRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, foundryProject.id, cosmosDbOperatorRoleId)
  scope: cosmosAccount
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cosmosDbOperatorRoleId
  }
}

resource projectSearchIndexRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, foundryProject.id, searchIndexDataContributorRoleId)
  scope: searchService
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchIndexDataContributorRoleId
  }
}

resource projectSearchServiceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, foundryProject.id, searchServiceContributorRoleId)
  scope: searchService
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: searchServiceContributorRoleId
  }
}

resource projectKeyVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, foundryProject.id, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    principalId: foundryProject.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleId
  }
}

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-09-01' = if (deployCapabilityHosts && createAccountCapabilityHost) {
  parent: foundryAccount
  name: '${foundryAccountName}@aml_aiagentservice'
  properties: {
    capabilityHostKind: 'Agents'
    #disable-next-line BCP037
    customerSubnet: agentSubnetId
  }
  dependsOn: [
    foundryProject
  ]
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-09-01' = if (deployCapabilityHosts) {
  parent: foundryProject
  name: 'caphost-project'
  properties: {
    // ARM requires capabilityHostKind: 'Agents' at runtime; Bicep Swagger omits it on ProjectCapabilityHostProperties.
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnection.name
    ]
    threadStorageConnections: [
      cosmosConnection.name
    ]
    vectorStoreConnections: [
      searchConnection.name
    ]
  }
  dependsOn: [
    accountCapabilityHost
    projectStorageRole
    projectCosmosRole
    projectSearchIndexRole
    projectSearchServiceRole
    storageDnsZoneGroup
    cosmosDnsZoneGroup
    searchDnsZoneGroup
    spokeDnsLinks
  ]
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output spokeVnetId string = spokeVnet.id
output agentSubnetId string = agentSubnetId
output privateEndpointSubnetId string = peSubnetId
output foundryAccountName string = foundryAccount.name
output foundryEndpoint string = foundryAccount.properties.endpoint
output foundryProjectId string = foundryProject.id
output storageAccountName string = storageAccount.name
output keyVaultName string = keyVault.name
output cosmosAccountName string = cosmosAccount.name
output searchServiceName string = searchService.name
