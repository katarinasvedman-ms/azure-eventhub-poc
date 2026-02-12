param eventHubNamespaceName string
param eventHubName string = 'logs'
param partitionCount int = 24
param messageRetentionInDays int = 1

// Reference the existing Event Hub namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2021-11-01' existing = {
  name: eventHubNamespaceName
}

// Create Event Hub topic
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
    ]
  }
}

// Outputs
output eventHubName string = eventHub.name
output eventHubId string = eventHub.id
output partitionCount int = partitionCount
output sendPolicyConnectionString string = listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'SendPolicy'), '2021-11-01').primaryConnectionString
output listenPolicyConnectionString string = listKeys(resourceId('Microsoft.EventHub/namespaces/authorizationRules', eventHubNamespace.name, 'ListenPolicy'), '2021-11-01').primaryConnectionString
