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
    isAutoInflateEnabled: true
    maximumThroughputUnits: 40
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
  }
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

// Shared Access Policies removed — all services use managed identity.
// If you need SAS keys for external consumers, add them back here.

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

// ── SQL Server Module ──
param aadAdminLogin string
param aadAdminSid string

module sqlServer 'sql.bicep' = {
  name: 'sqlServer'
  params: {
    location: location
    aadAdminLogin: aadAdminLogin
    aadAdminSid: aadAdminSid
  }
}

// ── Function App Module ──
module functionApp 'function-app.bicep' = {
  name: 'functionApp'
  params: {
    location: location
    storageAccountName: storageAccount.name
    eventHubNamespaceFqdn: '${eventHubNamespace.name}.servicebus.windows.net'
    eventHubNamespaceId: eventHubNamespace.id
    sqlConnectionString: sqlServer.outputs.connectionString
    eventHubName: eventHubName
  }
}

// ── API Web App Module ──
module apiApp 'api-app.bicep' = {
  name: 'apiApp'
  params: {
    location: location
    eventHubNamespaceFqdn: '${eventHubNamespace.name}.servicebus.windows.net'
    eventHubName: eventHubName
    eventHubNamespaceId: eventHubNamespace.id
  }
}

// Outputs
output eventHubNamespaceName string = eventHubNamespace.name
output eventHubName string = eventHub.name
output eventHubNamespaceId string = eventHubNamespace.id
output eventHubId string = eventHub.id
output partitionCount int = partitionCount
output storageAccountName string = storageAccount.name

// Connection strings removed from outputs — secrets should not be exposed in deployment history.
// They are passed internally to modules (function-app.bicep) via parameters.
// Use `az storage account keys list` or `az eventhubs namespace authorization-rule keys list` if needed.
output sqlServerName string = sqlServer.outputs.sqlServerName
output sqlServerFqdn string = sqlServer.outputs.fullyQualifiedDomainName
output sqlDatabaseName string = sqlServer.outputs.databaseName
output sqlConnectionString string = sqlServer.outputs.connectionString
output functionAppName string = functionApp.outputs.functionAppName
output functionAppDefaultHostName string = functionApp.outputs.functionAppDefaultHostName
output functionAppIdentityPrincipalId string = functionApp.outputs.identityPrincipalId
output apiAppName string = apiApp.outputs.webAppName
output apiAppDefaultHostName string = apiApp.outputs.webAppDefaultHostName
output apiAppIdentityPrincipalId string = apiApp.outputs.identityPrincipalId
