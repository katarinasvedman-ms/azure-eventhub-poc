# Event Hub PoC - Setup & Deployment Guide

## Quick Start

### Prerequisites
- .NET 8 SDK
- Azure CLI
- Azure Subscription

### Local Development Setup

#### 1. Configure Azure Credentials
```powershell
# Using DefaultAzureCredential (recommended)
az login
az account set --subscription <your-subscription-id>
```

#### 2. Deploy Infrastructure (Bicep)
```powershell
cd deploy

# Deploy via script (recommended)
.\deploy.ps1 -ResourceGroupName "rg-eventhub-dev" -Location "eastus"

# Or manually
az group create --name "rg-eventhub-dev" --location "eastus"
az deployment group create `
  --resource-group "rg-eventhub-dev" `
  --template-file main.bicep `
  --parameters parameters.dev.json
```

This creates:
- Event Hub Namespace (Standard SKU, 24 partitions)
- Event Hub (24 MB/sec capacity)
- Storage Account (for checkpoint management)
- SQL Database (Basic SKU, 2GB)

#### 3. Get Configuration
```powershell
# Configuration is automatically saved to appsettings.generated.json by deploy script
# If manual deployment, retrieve outputs:

az deployment group show `
  --resource-group "rg-eventhub-dev" `
  --name "main" `
  --query "properties.outputs" `
  --output json
```

#### 4. Run Producer/Consumer Locally
```powershell
cd src

# Run with default settings
dotnet run --configuration Release

# Or build release binary
dotnet publish -c Release
.\bin\Release\net8.0\publish\MetricSysPoC.exe
```

#### 5. Run Consumer Only (Skip Database)
```powershell
cd src-consumer

# Test consumer throughput without database bottleneck
dotnet run -- --no-db

# Results show actual event consumption rate from Event Hub
```

---

## Monitoring & Diagnostics

### Azure Portal
```powershell
# View Event Hub namespace
https://portal.azure.com → Search "rg-eventhub-dev"

# Key metrics to monitor:
# - Event Hub → Overview: Incoming Messages (events/sec)
# - Event Hub → Throughput Units (TUs): Should be 1
# - Consumer Groups → Default: Latest offset shows consumer lag
```

### Azure CLI
```powershell
# Get Event Hub status
az eventhubs namespace show `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev" `
  --output table

# Get throughput metrics
az monitor metrics list `
  --resource-group "rg-eventhub-dev" `
  --resource-type "Microsoft.EventHub/namespaces/eventhubs" `
  --resource "eventhub-dev-xxx/logs" `
  --metric "IncomingMessages" `
  --aggregation Total
```

### Application Logs
```powershell
# Producer console output shows:
# - Events published per second
# - Batch latencies
# - Errors (if any)

# Example output:
# Batch 1: 1000 events in 45ms (22.2k evt/sec)
# Batch 2: 1000 events in 43ms (23.3k evt/sec)
```

---

## Performance Configuration

### Batch Size Settings
```json
{
  "EventHub": {
    "BatchSize": 1000,
    "BatchTimeoutMs": 1000
  }
}
```

**Recommendations:**
- Batch size 1,000: Proven optimal throughput (26.7k evt/sec)
- Timeout 1,000ms: Ensures timely flush even with slow input
- **DO NOT use explicit MaximumSizeInBytes** (causes 64% throughput loss)

### Partition Count
```
Current: 24 partitions
Utilization: ~1.1k evt/sec per partition
Headroom: 32 max for Standard tier

If throughput < 20k evt/sec:
- Check CreateBatchOptions (don't use explicit options)
- Verify producer client is singleton (connection pooling)
- Monitor Event Hub metrics for errors/throttling
```

### Database Configuration
```
Current SKU: Basic (2GB, 5 DTU)
Consumer: Sequential (1.3k evt/sec max)

For 20k+ evt/sec:
- Implement parallel processing (batch writes per partition)
- Not yet implemented (next optimization)
```

### Connection Pooling
✅ **Singleton EventHubProducerClient** already implemented  
✅ Reuse same instance across app lifetime  
❌ Don't create new clients per request

---

## Troubleshooting

### "Cannot connect to Event Hub"
```powershell
# Verify connection string in appsettings.json
# Check resource group and namespace exist:
az eventhubs namespace show `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev"

# Verify Event Hub credentials (DefaultAzureCredential):
az account show
```

### "Throughput lower than expected"
**Checklist:**
1. ✅ No explicit `MaximumSizeInBytes` in `CreateBatchOptions`
2. ✅ Producer client is singleton (check Program.cs)
3. ✅ Batch size at least 1,000 events
4. ✅ Event Hub has 24 partitions (check Azure Portal)
5. ✅ No throttling errors in console output

**Debug:**
```powershell
# Check Event Hub metrics
az monitor metrics list `
  --resource-group "rg-eventhub-dev" `
  --resource-type "Microsoft.EventHub/namespaces/eventhubs" `
  --metric "IncomingMessages"

# Check for throttling (429 errors)
# If present, verify partition count and batch sizes
```

### "Consumer falling behind"
**Current limitation:** Single-threaded consumer = ~1.3k evt/sec max

**Workaround:** Use `--no-db` flag to measure raw Event Hub throughput
```powershell
cd src-consumer
dotnet run -- --no-db
```

**Solution:** Implement parallel processing per partition (TODO)

### "Data loss after restart"
```powershell
# Verify checkpoint storage exists
az storage account show `
  --name "sablobfuwf32lf57ise" `
  --resource-group "rg-eventhub-dev"

# Check checkpoint container
az storage container list `
  --account-name "sablobfuwf32lf57ise"

# Verify checkpoints are being created:
az storage blob list `
  --account-name "sablobfuwf32lf57ise" `
  --container-name "eventhub-checkpoints"
```

---

## Cleanup

```powershell
# Delete all resources in resource group
az group delete --name "rg-eventhub-dev" --yes --no-wait

# Or individual cleanup:
az eventhubs namespace delete `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev"

az storage account delete `
  --name "sablobfuwf32lf57ise" `
  --resource-group "rg-eventhub-dev"

az sql server delete `
  --name "sqlserver-xxx" `
  --resource-group "rg-eventhub-dev"
```

---

## Quick Reference

```powershell
# View Event Hub status
az eventhubs namespace show --name "eventhub-dev-xxx" --resource-group "rg-eventhub-dev" --output table

# Scale Event Hub (if needed)
az eventhubs namespace update `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev" `
  --sku Standard `
  --capacity 4

# Get all resources in group
az resource list --resource-group "rg-eventhub-dev" --output table

# Build and run locally
cd src
dotnet build -c Release
dotnet run --configuration Release

# Test consumer only (skip database)
cd src-consumer
dotnet run -- --no-db
```

---

*Version*: 2.0  
*Last Updated*: December 17, 2025  
*Status*: PoC Complete (Proven 26.7k evt/sec)
