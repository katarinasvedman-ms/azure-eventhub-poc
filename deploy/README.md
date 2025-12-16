# Bicep Deployment - Azure Event Hub

## Prerequisites

1. **Azure CLI** installed: https://learn.microsoft.com/cli/azure/install-azure-cli
2. **Bicep CLI** (included with recent Azure CLI versions, or install separately)
3. **PowerShell** 7+ (if using PowerShell deployment script)
4. **Azure subscription** with appropriate permissions
5. Authenticated with Azure:
   ```powershell
   az login
   az account set --subscription "your-subscription-id"
   ```

## Files

- `main.bicep` - Main infrastructure definition (Event Hub, Storage Account)
- `parameters.dev.json` - Parameter file for development environment
- `deploy.ps1` - PowerShell deployment script
- `deploy.sh` - Bash deployment script

## Deployment

### Option 1: Using PowerShell

```powershell
# Set variables
$ResourceGroupName = "rg-logsysng-dev"
$Location = "eastus"
$Environment = "dev"

# Create resource group
az group create `
  --name $ResourceGroupName `
  --location $Location

# Deploy Bicep template
az deployment group create `
  --resource-group $ResourceGroupName `
  --template-file main.bicep `
  --parameters parameters.dev.json `
  --parameters environment=$Environment
```

### Option 2: Using Bash

```bash
export ResourceGroupName="rg-logsysng-dev"
export Location="eastus"
export Environment="dev"

# Create resource group
az group create \
  --name $ResourceGroupName \
  --location $Location

# Deploy Bicep template
az deployment group create \
  --resource-group $ResourceGroupName \
  --template-file main.bicep \
  --parameters parameters.dev.json \
  --parameters environment=$Environment
```

### Option 3: Using Azure Portal

1. Go to Azure Portal
2. Click "Create a resource" → Search for "Template deployment"
3. Click "Build your own template in the editor"
4. Copy contents of `main.bicep`
5. Click Save
6. Fill in parameter values
7. Review and create

## Deployment Output

After successful deployment, you'll receive:

```json
{
  "eventHubNamespaceName": "eventhub-dev-xxxxxxxxxxxx",
  "eventHubName": "logs",
  "eventHubNamespaceId": "/subscriptions/.../Microsoft.EventHub/namespaces/eventhub-dev-xxxxxxxxxxxx",
  "eventHubId": "/subscriptions/.../Microsoft.EventHub/namespaces/eventhub-dev-xxxxxxxxxxxx/eventhubs/logs",
  "partitionCount": 24,
  "storageAccountName": "sablobcheckpointxxxxxxxxxxxx",
  "storageAccountConnectionString": "DefaultEndpointsProtocol=https;...",
  "sendPolicyConnectionString": "Endpoint=sb://eventhub-dev-xxxxxxxxxxxx.servicebus.windows.net/;SharedAccessKeyName=SendPolicy;...",
  "listenPolicyConnectionString": "Endpoint=sb://eventhub-dev-xxxxxxxxxxxx.servicebus.windows.net/;SharedAccessKeyName=ListenPolicy;..."
}
```

## Configure Your Application

### Update `appsettings.json`

Use the connection strings from deployment output:

```json
{
  "EventHub": {
    "FullyQualifiedNamespace": "eventhub-dev-xxxxxxxxxxxx.servicebus.windows.net",
    "EventHubName": "logs",
    "ProducerConnectionString": "Endpoint=sb://eventhub-dev-xxxxxxxxxxxx.servicebus.windows.net/;SharedAccessKeyName=SendPolicy;SharedAccessKey=xxx...",
    "ConsumerConnectionString": "Endpoint=sb://eventhub-dev-xxxxxxxxxxxx.servicebus.windows.net/;SharedAccessKeyName=ListenPolicy;SharedAccessKey=xxx...",
    "BatchSize": 100,
    "BatchTimeoutMs": 1000
  },
  "Storage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;AccountName=sablobcheckpointxxxxxxxxxxxx;AccountKey=xxx...;EndpointSuffix=core.windows.net",
    "ContainerName": "checkpoints"
  }
}
```

## What Gets Deployed

### Event Hub Namespace (Standard SKU)
- **Name**: `eventhub-{environment}-{uniqueId}`
- **SKU**: Standard tier
- **Capacity**: 1 throughput unit
- **Features**:
  - Supports up to 32 partitions
  - Up to 32,000 events/sec
  - 20 consumer groups
  - Public network access enabled

### Event Hub (Topic)
- **Name**: `logs`
- **Partitions**: 24 (configurable)
- **Retention**: 1 day (configurable)
- **Status**: Active

### Consumer Groups
1. `logs-consumer` - Main event processing
2. `monitoring-consumer` - Monitoring/diagnostics
3. `archive-consumer` - Archival/backup

### Authorization Policies
- **SendPolicy**: Full Send rights for producers
- **ListenPolicy**: Listen + Manage rights for consumers

### Storage Account
- **Name**: `saBlobCheckpoint{uniqueId}`
- **SKU**: Standard LRS
- **Container**: `checkpoints` (for consumer group checkpoints)
- **Access**: HTTPS only, minimum TLS 1.2

## Customization

### Adjust Parameters

Edit `parameters.dev.json`:

```json
{
  "parameters": {
    "location": {
      "value": "westus2"  // Change region
    },
    "partitionCount": {
      "value": 32  // Up to 32 for Standard SKU
    },
    "messageRetentionInDays": {
      "value": 7  // Increase retention
    }
  }
}
```

### Scale Up Event Hub (Later)

To upgrade from Standard to Premium:

1. Edit `main.bicep`
2. Change SKU:
   ```bicep
   sku: {
     name: 'Premium'
     tier: 'Premium'
     capacity: 1  // Premium pricing unit (1-16)
   }
   ```
3. Increase max partitions to up to 100
4. Redeploy

## Verification

### List Deployed Resources

```powershell
az resource list --resource-group "rg-logsysng-dev" --output table
```

### Get Deployment Outputs

```powershell
az deployment group show \
  --resource-group "rg-logsysng-dev" \
  --name "main" \
  --query "properties.outputs" \
  --output json
```

### Test Connectivity

```powershell
$ConnStr = "Endpoint=sb://eventhub-dev-xxx.servicebus.windows.net/;SharedAccessKeyName=SendPolicy;SharedAccessKey=xxx..."
az eventhubs namespace authorization-rule keys list \
  --resource-group "rg-logsysng-dev" \
  --namespace-name "eventhub-dev-xxx" \
  --name "SendPolicy"
```

## Cleanup

```powershell
# Delete entire resource group (removes all resources)
az group delete --name "rg-logsysng-dev" --yes --no-wait

# Or delete just Event Hub (keep storage)
az eventhubs namespace delete \
  --resource-group "rg-logsysng-dev" \
  --name "eventhub-dev-xxx"
```

## Cost Estimation (Monthly)

| Component | Cost |
|---|---|
| Event Hub Namespace (Standard, 1 TU) | ~$49-75 |
| 24 Partitions | Included in above |
| Storage Account (Blob, 1GB used) | ~$0.50 |
| Transactions | ~$0-5 |
| **Total** | **~$50-80/month** |

*Actual costs depend on region and usage patterns. Use Azure Cost Calculator for precise estimates.*

## Troubleshooting

### Deployment Fails: "Namespace already exists"
- Event Hub namespaces must have globally unique names
- Solution: Change `environment` parameter or use a different unique suffix

### Deployment Fails: "Insufficient quota"
- Standard tier limited to 40 throughput units per region
- Solution: Try a different region or contact Azure support

### Cannot connect to Event Hub from local app
- Verify firewall rules: Event Hub should have "Public network access: Enabled"
- Verify connection string uses correct policy name (SendPolicy vs ListenPolicy)
- Check network: Local machine must have outbound HTTPS access to service bus

### Storage account connection fails
- Verify storage account name in connection string
- Check that checkpoints container exists
- Verify access key is current (may need to regenerate)

## Next Steps

1. **Deploy infrastructure** using one of the scripts above
2. **Update appsettings.json** with output connection strings
3. **Run producer/consumer locally**:
   ```powershell
   dotnet run --configuration Release
   ```
4. **Load test** using K6 script:
   ```bash
   k6 run load-test.js
   ```
5. **Monitor** in Azure Portal:
   - Event Hub → Metrics → Messages received/sent
   - Storage Account → Container → Blobs (checkpoints)

---

For questions or issues, see `SKU_RECOMMENDATION.md` for sizing guidance.
