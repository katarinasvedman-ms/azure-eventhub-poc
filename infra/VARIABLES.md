# Bicep Deployment - Variables Reference

## main.bicep Parameters

All parameters can be customized in `parameters.dev.json`

### location
- **Type**: `string`
- **Default**: `resourceGroup().location`
- **Description**: Azure region for deployment
- **Examples**: `eastus`, `westus2`, `northeurope`, `southeastasia`

### environment
- **Type**: `string`
- **Default**: `dev`
- **Description**: Environment name (used in naming convention)
- **Options**: `dev`, `test`, `staging`, `prod`

### eventHubNamespaceName
- **Type**: `string`
- **Default**: `eventhub-${environment}-${uniqueString(resourceGroup().id)}`
- **Description**: Name of Event Hub namespace (auto-generated if empty)
- **Note**: Must be globally unique; auto-generation recommended

### eventHubName
- **Type**: `string`
- **Default**: `logs`
- **Description**: Name of the Event Hub topic

### partitionCount
- **Type**: `int`
- **Default**: `24`
- **Allowed Range**: 
  - Standard SKU: 1-32
  - Premium SKU: 1-100
  - Dedicated SKU: 1-1024
- **Description**: Number of partitions (affects throughput)
- **Recommendation**: 
  - 20k events/sec → 24 partitions (with 20% headroom)
  - 40k events/sec → 40 partitions (requires Premium)

### messageRetentionInDays
- **Type**: `int`
- **Default**: `1`
- **Allowed Range**: 1-90 (varies by SKU)
- **Description**: Event retention period

### storageAccountName
- **Type**: `string`
- **Default**: `saBlobCheckpoint${uniqueString(resourceGroup().id)}`
- **Description**: Name of storage account (auto-generated if empty)
- **Note**: Must be 3-24 chars, lowercase alphanumeric only

### storageAccountSku
- **Type**: `string`
- **Default**: `Standard_LRS`
- **Options**:
  - `Standard_LRS` (Recommended)
  - `Standard_GRS`
  - `Standard_RAGRS`
  - `Premium_LRS`

---

## Scaling Guide

### For 5k events/sec
```json
{
  "parameters": {
    "partitionCount": { "value": 5 },
    "storageAccountSku": { "value": "Standard_LRS" }
  }
}
```

### For 20k events/sec (Current LogsysNG)
```json
{
  "parameters": {
    "partitionCount": { "value": 24 },
    "messageRetentionInDays": { "value": 1 }
  }
}
```

### For 40k events/sec (Future Growth)
**Note**: Requires Premium SKU upgrade in main.bicep

```json
{
  "parameters": {
    "partitionCount": { "value": 40 }
  }
}
```

### For 100k events/sec (Enterprise)
**Note**: Requires Premium SKU with max PU in main.bicep

```json
{
  "parameters": {
    "partitionCount": { "value": 100 }
  }
}
```

---

## SKU Comparison (in main.bicep)

### Standard (Current)
```bicep
sku: {
  name: 'Standard'
  tier: 'Standard'
  capacity: 1  // 1 TU (Throughput Unit)
}
```

### Premium (Future)
```bicep
sku: {
  name: 'Premium'
  tier: 'Premium'
  capacity: 1  // 1 PU (Premium Unit)
}
```

### Dedicated (Enterprise)
```bicep
sku: {
  name: 'Dedicated'
  tier: 'Dedicated'
  capacity: 1  // 1 CU (Capacity Unit)
}
```

---

## Resource Naming Convention

| Resource | Naming Pattern | Example |
|---|---|---|
| Event Hub Namespace | `eventhub-{env}-{uniqueId}` | `eventhub-dev-a1b2c3d4` |
| Storage Account | `saBlobCheckpoint{uniqueId}` | `sablobcheckpointa1b2c3d4` |
| Event Hub | `{eventHubName}` | `logs` |
| Consumer Group | `{name}-consumer` | `logs-consumer` |

---

## Output Values

After deployment, outputs are available:

```powershell
# Get all outputs
az deployment group show --resource-group "rg-logsysng-dev" --name "main" --query "properties.outputs" --output json

# Get specific output
az deployment group show --resource-group "rg-logsysng-dev" --name "main" --query "properties.outputs.eventHubNamespaceName.value" --output tsv
```

Available outputs:
- `eventHubNamespaceName` - Full namespace name
- `eventHubName` - Hub name
- `eventHubNamespaceId` - ARM resource ID
- `eventHubId` - Event Hub resource ID
- `partitionCount` - Number of partitions
- `storageAccountName` - Storage account name
- `storageAccountConnectionString` - Connection string for storage
- `sendPolicyConnectionString` - Producer connection string
- `listenPolicyConnectionString` - Consumer connection string

---

## Cost Estimation

### Monthly Costs (approximate)

| SKU | Base Cost | Per GB Retention | Per Million Ops | Total (Typical) |
|---|---|---|---|---|
| Basic | $10/month | $0.111 | $0.44 | $15-20 |
| Standard | $50/month | $0.111 | $0.44 | $75-100 |
| Premium (1 PU) | $300/month | $0.111 | $0.44 | $350-400 |
| Dedicated (1 CU) | $2,000/month | Included | Included | $2,000+ |

*Actual costs vary by region and workload*

### For LogsysNG (20k evt/sec)
- **Ingestion**: ~50,000 GB throughput/month → ~$220
- **Storage**: ~0.5 GB/day × 30 days → ~$2
- **Egress**: Regional (free if in same region) → $0
- **Total**: ~$75-100/month

---

## Customization Examples

### Add Application Insights Monitoring

Edit `main.bicep`:

```bicep
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'ai-eventhub-${environment}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 30
  }
}

output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
```

### Enable Event Hub Capture (Archival)

Edit event hub resource:

```bicep
captureDescription: {
  enabled: true
  encoding: 'Avro'
  intervalInSeconds: 300
  sizeLimitInBytes: 314572800
  destination: {
    name: 'EventHubArchive.AzureBlockBlobs'
    properties: {
      storageAccountResourceId: storageAccount.id
      blobContainer: 'archive'
      archiveNameFormat: '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}'
    }
  }
}
```

### Add Virtual Network Integration

Edit namespace properties:

```bicep
properties: {
  // ... existing properties ...
  publicNetworkAccess: 'Disabled'
  minimumTlsVersion: '1.2'
}
```

---

## Troubleshooting Parameters

If deployment fails, check:

1. **Namespace name uniqueness**: Try without custom name (auto-generation)
2. **Storage name rules**: 3-24 chars, lowercase, alphanumeric only
3. **Partition count**: 1-32 for Standard, 1-100 for Premium
4. **Location validity**: Use `az account list-locations --output table`
5. **Quota exceeded**: Contact Azure support to increase regional limits

---

For full documentation, see `README.md` in the `deploy` folder.
