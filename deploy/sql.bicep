// Azure SQL Server and Database for Event Hub PoC
// Uses Azure AD-only authentication to comply with security policies

param location string = 'swedencentral'
param environmentName string = 'dev'
param serverNameSuffix string = uniqueString(resourceGroup().id)

var sqlServerName = 'sqlserver-logsysng-${serverNameSuffix}'
var databaseName = 'eventhub-logs-db'

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
      login: 'kapeltol_microsoft.com#EXT#@fdpo.onmicrosoft.com'
      tenantId: subscription().tenantId
      sid: '7305afcc-e26e-486f-bb5b-fc910fade69a'
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
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824 // 1 GB
  }
}

// Output the connection details
output sqlServerName string = sqlServer.name
output databaseName string = database.name
output fullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output connectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${databaseName};Persist Security Info=False;User ID=your-user@yourdomain.com;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Integrated;'
