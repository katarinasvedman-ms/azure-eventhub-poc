param location string = resourceGroup().location
param appName string = 'funcapp-eventhub-${uniqueString(resourceGroup().id)}'
param eventHubConnectionString string
param sqlConnectionString string

// Create Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-logsysng-${uniqueString(resourceGroup().id)}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 30
  }
}

// Create Flex Consumption Plan
resource flexPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true
  }
}

// Create Function App
resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: flexPlan.id
    siteConfig: {
      alwaysOn: true
      numberOfWorkers: 2
      functionsRuntimeScaleMonitoringEnabled: true
      linuxFxVersion: 'DOTNET-ISOLATED|8.0'
      appSettings: [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet-isolated'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '8.0'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=sablobfuwf32lf57ise;AccountKey=${listKeys(resourceId('rg-logsysng-dev', 'Microsoft.Storage/storageAccounts', 'sablobfuwf32lf57ise'), '2021-06-01').keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'EventHubConnection'
          value: eventHubConnectionString
        }
        {
          name: 'SQL_CONNECTION_STRING'
          value: sqlConnectionString
        }
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
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: 'DefaultEndpointsProtocol=https;AccountName=sablobfuwf32lf57ise;AccountKey=${listKeys(resourceId('rg-logsysng-dev', 'Microsoft.Storage/storageAccounts', 'sablobfuwf32lf57ise'), '2021-06-01').keys[0].value};EndpointSuffix=core.windows.net'
          authentication: 'StorageConnectionString'
        }
      }
      runtime: {
        name: 'dotnet-isolated'
        version: '8.0'
      }
    }
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output identityPrincipalId string = functionApp.identity.principalId
