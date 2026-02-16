// ============================================================================
// Function App — Elastic Premium (EP1) with system-assigned managed identity
//
// Elastic Premium provides dedicated compute with elastic scale-out,
// VNET integration, and no cold-start penalty.
//
// Deployed as a module from main.bicep. Receives connection strings and
// storage account name as parameters so nothing is hardcoded.
//
// After deployment:
//   1. Grant the managed identity db_datareader + db_datawriter on Azure SQL
//   2. Publish the function code with `func azure functionapp publish <name>`
// ============================================================================

param location string = resourceGroup().location
param appName string = 'func-logsysng-${uniqueString(resourceGroup().id)}'

// Resource references passed from main.bicep (no connection strings — uses managed identity)
param storageAccountName string
param eventHubNamespaceFqdn string
param eventHubNamespaceId string
param sqlConnectionString string

// Event Hub consumer settings
param eventHubName string = 'logs'
param eventHubConsumerGroup string = 'logs-consumer'

// ── Application Insights ──
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-logsysng-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 30
  }
}

// ── Reference existing storage account (created by main.bicep) ──
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// No storage connection string needed — using managed identity with AzureWebJobsStorage__accountName

// ── Elastic Premium Plan (EP1) — dedicated instances with elastic scale-out ──
resource premiumPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'elastic'
  sku: {
    name: 'EP2'
    tier: 'ElasticPremium'
  }
  properties: {
    reserved: true // required for Linux
    maximumElasticWorkerCount: 20
  }
}

// ── Function App ──
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: premiumPlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        // ── Runtime ──
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        // ── Storage (managed identity — no account key) ──
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'CheckpointStoreConnection__blobServiceUri'
          value: 'https://${storageAccount.name}.blob.${environment().suffixes.storage}'
        }
        // ── Event Hub (managed identity — no SAS key) ──
        {
          name: 'EventHubConnection__fullyQualifiedNamespace'
          value: eventHubNamespaceFqdn
        }
        {
          name: 'EventHubName'
          value: eventHubName
        }
        {
          name: 'EventHubConsumerGroup'
          value: eventHubConsumerGroup
        }
        // ── SQL (AAD-only auth — managed identity will get an access token at runtime) ──
        {
          name: 'SqlConnectionString'
          value: sqlConnectionString
        }
        // ── Observability ──
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
      ]
    }
  }
}

// ── Role Assignments for Managed Identity ──

// Storage Blob Data Owner — required for AzureWebJobsStorage + checkpoint store
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
resource storageBlobDataOwnerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageBlobDataOwnerRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor — required for AzureWebJobsStorage internal queues
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
resource storageQueueDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageQueueDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Table Data Contributor — required for AzureWebJobsStorage timer triggers
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
resource storageTableDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, functionApp.id, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Azure Event Hubs Data Receiver — required for Event Hub trigger
var eventHubsDataReceiverRoleId = 'a638d3c7-ab3a-418d-83e6-5f17a39d4fde'
resource eventHubReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespaceId, functionApp.id, eventHubsDataReceiverRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataReceiverRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output identityPrincipalId string = functionApp.identity.principalId
output identityTenantId string = functionApp.identity.tenantId
