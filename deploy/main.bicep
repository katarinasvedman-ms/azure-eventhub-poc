param location string = resourceGroup().location
param environment string = 'dev'
param eventHubName string = 'logs'
param partitionCount int = 24
param messageRetentionInDays int = 1
param storageAccountSku string = 'Standard_LRS'

var eventHubNamespaceName = 'eventhub-${environment}-${uniqueString(resourceGroup().id)}'
var storageAccountName = 'sablob${uniqueString(resourceGroup().id)}'

// Event Hub Namespace (Standard SKU)
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' = {
  name: eventHubNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    isAutoInflateEnabled: false
    maximumThroughputUnits: 0
    kafkaEnabled: false
    zoneRedundant: false
  }
}

// Event Hub (Topic) - nested under namespace
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2021-11-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: messageRetentionInDays
    partitionCount: partitionCount
    captureDescription: {
      enabled: false
    }
  }
  dependsOn: [
    eventHubNamespace
  ]
}

// Consumer Group 1: Logs Consumption
resource consumerGroupLogs 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventHub
  name: 'logs-consumer'
  properties: {
    userMetadata: 'Consumer group for log event processing'
  }
}

// Consumer Group 2: Monitoring
resource consumerGroupMonitoring 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventHub
  name: 'monitoring-consumer'
  properties: {
    userMetadata: 'Consumer group for monitoring and diagnostics'
  }
}

// Consumer Group 3: Archival/Backup
resource consumerGroupArchive 'Microsoft.EventHub/namespaces/eventhubs/consumergroups@2021-11-01' = {
  parent: eventHub
  name: 'archive-consumer'
  properties: {
    userMetadata: 'Consumer group for archival and backup'
  }
}

// Shared Access Policy for Sender (Producer)
resource sendAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2021-11-01' = {
  parent: eventHubNamespace
  name: 'SendPolicy'
  properties: {
    rights: [
      'Send'
    ]
  }
}

// Shared Access Policy for Listener (Consumer)
resource listenAuthRule 'Microsoft.EventHub/namespaces/authorizationRules@2021-11-01' = {
  parent: eventHubNamespace
  name: 'ListenPolicy'
  properties: {
    rights: [
      'Listen'
      'Manage'
    ]
  }
}

// Storage Account for Checkpointing
resource storageAccount 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: storageAccountSku
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Blob Container for Checkpointing
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-09-01' = {
  name: '${storageAccount.name}/default/checkpoints'
  properties: {
    publicAccess: 'None'
  }
}

// Outputs
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output eventHubNamespaceId string = eventHubNamespace.id
output eventHubId string = eventHub.id
output partitionCount int = partitionCount
output storageAccountName string = storageAccount.name
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${listKeys(storageAccount.id, '2021-09-01').keys[0].value};EndpointSuffix=core.windows.net'
output sendPolicyConnectionString string = listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'SendPolicy'), '2021-11-01').primaryConnectionString
output listenPolicyConnectionString string = listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'ListenPolicy'), '2021-11-01').primaryConnectionString
