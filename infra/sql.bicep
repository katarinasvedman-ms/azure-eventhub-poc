// Azure SQL Server and Database for Event Hub PoC
// Uses Azure AD-only authentication to comply with security policies

param location string = resourceGroup().location
param serverNameSuffix string = uniqueString(resourceGroup().id)
param databaseName string = 'eventhub-logs-db'

// AAD admin — pass from parent or parameters file
param aadAdminLogin string
param aadAdminSid string
param aadAdminTenantId string = subscription().tenantId

var sqlServerName = 'sqlserver-logsysng-${serverNameSuffix}'

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: sqlServerName
  location: location
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: aadAdminLogin
      tenantId: aadAdminTenantId
      sid: aadAdminSid
      principalType: 'User'
    }
  }
}

// Allow Azure services to access the database
resource sqlServerFirewall 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create the database
resource database 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: 'S2'
    tier: 'Standard'
    capacity: 50
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 268435456000 // 250 GB
  }
}

// Output the connection details
output sqlServerName string = sqlServer.name
output databaseName string = database.name
output fullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
// AAD-only connection string (no password — managed identity acquires token at runtime)
output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
