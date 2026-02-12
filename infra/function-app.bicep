// ============================================================================
// Function App — Flex Consumption plan with system-assigned managed identity
//
// Flex Consumption (FC1) replaces Linux Consumption (Y1, EOL Sep 2028).
// Benefits: faster cold start, per-function scaling, always-ready instances.
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

// Connection strings passed from main.bicep
param storageAccountName string
param eventHubListenConnectionString string
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

var storageConnectionString = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'

// ── Flex Consumption Plan (FC1) — replaces Linux Consumption (Y1, EOL Sep 2028) ──
resource flexPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true // required for Linux
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
    serverFarmId: flexPlan.id
    httpsOnly: true
    siteConfig: {
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
        // ── Storage (host + checkpoint store) ──
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'CheckpointStoreConnection'
          value: storageConnectionString
        }
        // ── Event Hub ──
        {
          name: 'EventHubConnection'
          value: eventHubListenConnectionString
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
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'StorageAccountConnectionString'
            storageAccountConnectionStringName: 'AzureWebJobsStorage'
          }
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
    }
  }
}

// ── Blob container for Flex Consumption deployment storage ──
resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/deployments'
  properties: {
    publicAccess: 'None'
  }
}

output functionAppName string = functionApp.name
output functionAppDefaultHostName string = functionApp.properties.defaultHostName
output identityPrincipalId string = functionApp.identity.principalId
output identityTenantId string = functionApp.identity.tenantId
