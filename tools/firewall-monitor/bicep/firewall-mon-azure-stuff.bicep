@description('Namespace for the Event Hub')
param namespace string = 'fwmonns${uniqueString(resourceGroup().id, deployment().name)}'

@description('Name of the Event Hub instance')
param hubname string = 'fwmonhub'

@description('Name of the least-privilege Listen Shared Access Policy')
param sharedkey string = 'fwmonkey'

@description('Location for the Event Hub Namespace')
param location string = resourceGroup().location

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: namespace
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

resource eventhub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: hubname
  properties: {
    messageRetentionInDays: 1
    partitionCount: 1
  }
}

resource firewallMonHub 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventhub
  name: sharedkey
  properties: {
    rights: [
      'Listen'
    ]
  }
}


