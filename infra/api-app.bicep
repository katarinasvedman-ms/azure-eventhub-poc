// ============================================================================
// API Web App — ASP.NET Core on App Service P1v3 with managed identity
//
// Receives HTTP requests (1-10 logs each), buffers internally, and publishes
// batches to Event Hub using the SDK's built-in batching.
//
// The app uses DefaultAzureCredential → system-assigned managed identity
// to authenticate to Event Hub (no connection strings).
//
// After deployment:
//   1. Publish the app code: az webapp deploy --name <name> --src-path publish.zip --type zip
//   2. Autoscale is configured via this template (CPU-based, 1-5 instances).
// ============================================================================

param location string = resourceGroup().location
param appName string = 'api-logsysng-${uniqueString(resourceGroup().id)}'

// Event Hub settings (namespace FQDN, not connection string — uses managed identity)
param eventHubNamespaceFqdn string
param eventHubName string = 'logs'

// Optional: Application Insights connection string for observability
param appInsightsConnectionString string = ''

// ── App Service Plan (P1v3 — 2 vCPU, 8 GB RAM) ──
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${appName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'P1v3'
    tier: 'PremiumV3'
    capacity: 1
  }
  properties: {
    reserved: true // required for Linux
  }
}

// ── Web App ──
resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      alwaysOn: true
      http20Enabled: true
      appSettings: [
        {
          name: 'EventHub__FullyQualifiedNamespace'
          value: eventHubNamespaceFqdn
        }
        {
          name: 'EventHub__HubName'
          value: eventHubName
        }
        {
          name: 'EventHub__UseKeyAuthentication'
          value: 'false'
        }
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

// ── Autoscale: CPU-based, 1-5 instances ──
resource autoscale 'Microsoft.Insights/autoscalesettings@2022-10-01' = {
  name: '${appName}-autoscale'
  location: location
  properties: {
    enabled: true
    targetResourceUri: appServicePlan.id
    profiles: [
      {
        name: 'CPU-based scaling'
        capacity: {
          minimum: '3'
          maximum: '15'
          default: '3'
        }
        rules: [
          // Scale OUT when CPU > 70% for 5 minutes
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          // Scale IN when CPU < 30% for 10 minutes
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT10M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT10M'
            }
          }
        ]
      }
    ]
  }
}

// ── Grant "Azure Event Hubs Data Sender" to the managed identity ──
// Role definition ID for Azure Event Hubs Data Sender
var eventHubsDataSenderRoleId = '2b629674-e913-4c01-ae53-ef4638d8f975'

param eventHubNamespaceId string

resource eventHubSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(eventHubNamespaceId, webApp.id, eventHubsDataSenderRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventHubsDataSenderRoleId)
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ──
output webAppName string = webApp.name
output webAppDefaultHostName string = webApp.properties.defaultHostName
output identityPrincipalId string = webApp.identity.principalId
