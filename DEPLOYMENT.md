# LogsysNG Event Hub PoC - Setup & Deployment Guide

## Quick Start

### Prerequisites
- .NET 8 SDK
- Azure CLI
- Docker & Docker Compose (for local testing)
- K6 (for load testing)

### Local Development Setup

#### 1. Configure Azure Credentials
```bash
# Using DefaultAzureCredential (recommended)
az login
az account set --subscription <your-subscription-id>
```

#### 2. Create Event Hub Resources
```bash
# Set variables
$resourceGroup = "logsysng-poc"
$namespace = "logsysng-ns"
$hubName = "logsysng-hub"
$region = "westeurope"

# Create resource group
az group create --name $resourceGroup --location $region

# Create Event Hub namespace (Basic tier for PoC)
az eventhubs namespace create `
  --resource-group $resourceGroup `
  --name $namespace `
  --location $region `
  --sku Basic `
  --enable-auto-inflate false

# Create Event Hub with 4 partitions
az eventhubs eventhub create `
  --resource-group $resourceGroup `
  --namespace-name $namespace `
  --name $hubName `
  --partition-count 4 `
  --retention-in-days 1

# Create consumer group
az eventhubs eventhub consumer-group create `
  --resource-group $resourceGroup `
  --namespace-name $namespace `
  --eventhub-name $hubName `
  --name default
```

#### 3. Create Storage Account for Checkpointing
```bash
$storageAccountName = "logsyngstorage"

# Create storage account
az storage account create `
  --resource-group $resourceGroup `
  --name $storageAccountName `
  --location $region `
  --sku Standard_LRS

# Create blob container for checkpoints
az storage container create `
  --account-name $storageAccountName `
  --name event-hub-checkpoints
```

#### 4. Update Configuration
```bash
# Get connection string
$connString = az eventhubs namespace authorization-rule keys list `
  --resource-group $resourceGroup `
  --namespace-name $namespace `
  --name RootManageSharedAccessKey `
  --query primaryConnectionString -o tsv

# Update appsettings.json
# Replace EventHub__FullyQualifiedNamespace and storage connection string
```

#### 5. Run Locally with Docker Compose
```bash
# Build and start services
docker-compose up -d

# Check logs
docker-compose logs -f api

# Run load test
docker-compose exec load-test k6 run /scripts/load-test.js

# Stop
docker-compose down
```

#### 6. Test Manually
```bash
# Single event
curl -X POST http://localhost:5000/api/logs/ingest \
  -H "Content-Type: application/json" \
  -d '{"message":"Test event","source":"Manual","partitionKey":"user-1"}'

# Batch
curl -X POST http://localhost:5000/api/logs/ingest-batch \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {"message":"Event 1","source":"Manual","partitionKey":"user-1"},
      {"message":"Event 2","source":"Manual","partitionKey":"user-2"}
    ]
  }'

# Queue stats
curl http://localhost:5000/api/logs/queue-stats

# Health check
curl http://localhost:5000/health
```

---

## Deployment to Azure Container Apps

### Prerequisites
- Azure Container Registry
- Azure Container Apps environment

### Deployment Steps

#### 1. Build and Push Docker Image
```bash
$acrName = "logsyngregistry"
$imageName = "logsysng-api"

# Login to ACR
az acr login --name $acrName

# Build image
docker build -f src/Dockerfile -t $acrName.azurecr.io/$imageName:latest src/

# Push to ACR
docker push $acrName.azurecr.io/$imageName:latest
```

#### 2. Create Container App
```bash
$containerAppName = "logsysng-api-app"
$environmentName = "logsysng-env"

# Create container app
az containerapp create `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --environment $environmentName `
  --image "$acrName.azurecr.io/$imageName:latest" `
  --target-port 5000 `
  --ingress external `
  --registry-server "$acrName.azurecr.io" `
  --min-replicas 2 `
  --max-replicas 10

# Set environment variables
az containerapp update `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --set-env-vars `
    EventHub__FullyQualifiedNamespace="$namespace.servicebus.windows.net" `
    EventHub__HubName="$hubName" `
    EventHub__StorageConnectionString="$storageConnectionString" `
    Api__BatchSize=100 `
    Api__BatchTimeoutMs=1000

# Get the URL
az containerapp show `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --query properties.configuration.ingress.fqdn
```

#### 3. Configure Autoscaling
```bash
# Update autoscaling rules
az containerapp update `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --scale-rule-name cpu-scale `
  --scale-rule-type cpu `
  --scale-rule-http-concurrency 100
```

#### 4. Load Test Production Deployment
```bash
$appUrl = "https://<your-container-app>.azurecontainerapps.io"

# Run K6 test
k6 run -e BASE_URL=$appUrl load-test.js
```

---

## Monitoring & Observability

### Enable Application Insights
```bash
# Create Application Insights instance
az monitor app-insights component create `
  --resource-group $resourceGroup `
  --app logsysng-insights `
  --location $region

# Get instrumentation key
$instrumentationKey = az monitor app-insights component show `
  --resource-group $resourceGroup `
  --app logsysng-insights `
  --query instrumentationKey -o tsv

# Update container app
az containerapp update `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --set-env-vars APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=$instrumentationKey"
```

### Key Metrics to Monitor
```bash
# Event Hub metrics
az monitor metrics list `
  --resource-group $resourceGroup `
  --resource-type "Microsoft.EventHub/namespaces" `
  --resource-namespace "logsysng-ns" `
  --metric "IncomingMessages" `
  --start-time "2024-01-01T00:00:00Z" `
  --end-time "2024-01-02T00:00:00Z"

# Container App metrics
az containerapp show `
  --resource-group $resourceGroup `
  --name $containerAppName `
  --query properties.template.scale
```

### Application Insights Queries
```kusto
// Throughput per minute
customMetrics
| where name == "EventsPublished"
| summarize EventCount=sum(value) by bin(timestamp, 1m)
| render timechart

// API response time distribution
requests
| where name contains "ingest"
| summarize 
    p50=percentile(duration, 50),
    p95=percentile(duration, 95),
    p99=percentile(duration, 99)
    by bin(timestamp, 1m)

// Error rates by partition
customEvents
| where name == "BatchPublishError"
| summarize ErrorCount=count() by tostring(customDimensions.partition)
```

---

## Performance Tuning

### Throughput Optimization

#### Batch Size Tuning
```json
{
  "Api": {
    "BatchSize": 100,        // Start: 100
    "BatchTimeoutMs": 1000   // If latency > 200ms, increase to 200-300
  }
}
```

**Guideline:**
- If **response time > 200ms**: Increase BatchSize (e.g., 100→200)
- If **throughput < target**: Increase BatchSize and/or reduce BatchTimeoutMs

#### Partition Count Tuning
```bash
# Monitor throughput per partition
# Target: 2,500-5,000 events/sec per partition for 20k total

# If uneven distribution: Check partition key cardinality
# If hotspot detected: Add more partitions (up to 10 max)

# Scale partitions (requires Event Hub Standard or Premium)
az eventhubs eventhub update \
  --resource-group $resourceGroup \
  --namespace-name $namespace \
  --name $hubName \
  --partition-count 8
```

#### Connection Pooling
- ✅ Singleton EventHubProducerClient already implemented
- ✅ Reuse same instance across requests
- ❌ Don't create new clients per request

### Latency Optimization

```csharp
// Current implementation achieves <200ms via:
// 1. Non-blocking async/await
await batchingService.EnqueueEventAsync(evt); // Returns immediately

// 2. Batch publishing (batches sent separately)
await producerService.PublishEventBatchAsync(batch);

// 3. Partition-aware routing (no random lookups)
var partition = GetPartitionFor(event.PartitionKey);

// Further optimization if needed:
// - Enable compression in Event Hub SDK
// - Use network-accelerated compute
// - Regional Event Hub namespace
```

---

## Troubleshooting Deployment

### Container App Won't Start
```bash
# Check logs
az containerapp logs show \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --follow

# Common issues:
# - Event Hub connection string incorrect
# - Storage account not accessible
# - Missing DefaultAzureCredential setup
```

### High Latency in Production
```bash
# Check throughput vs partition count
az monitor metrics list \
  --resource-group $resourceGroup \
  --resource-type "Microsoft.EventHub/namespaces/eventhubs" \
  --resource "logsysng-ns/logsysng-hub" \
  --metric "IncomingMessagesPerSecond"

# If uneven: Check partition key distribution
# If spiky: Increase batch size
# If CPU high: Scale up container replicas
```

### Data Loss After Consumer Restart
```bash
# Verify blob storage checkpoints are being created
az storage blob list \
  --account-name $storageAccountName \
  --container-name event-hub-checkpoints

# If empty: Check consumer service is running
# If latest offset behind: Investigate processing errors
az monitor app-insights query \
  --app logsysng-insights \
  --analytics-query "customEvents | where name == 'BatchPublishError'"
```

---

## Rollback Procedures

### Rollback to Previous Version
```bash
# Get revision history
az containerapp revision list \
  --resource-group $resourceGroup \
  --name $containerAppName

# Switch to previous revision
az containerapp revision activate \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --revision $containerAppName--<revision>
```

### Rollback Event Hub Configuration
```bash
# Keep old hub running during deployment
# If issues detected, switch back:

# Update API to use old hub
az containerapp update \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --set-env-vars EventHub__HubName="logsysng-hub-v1"

# After stabilization, delete new hub
az eventhubs eventhub delete \
  --resource-group $resourceGroup \
  --namespace-name $namespace \
  --name logsysng-hub-v2
```

---

## Cleanup

```bash
# Delete all resources
az group delete --resource-group $resourceGroup --yes

# Or individual cleanup:
az containerapp delete --resource-group $resourceGroup --name $containerAppName
az eventhubs namespace delete --resource-group $resourceGroup --name $namespace
az storage account delete --resource-group $resourceGroup --name $storageAccountName
```

---

## Quick Reference Commands

```bash
# View Event Hub metrics
az monitor metrics list \
  --resource /subscriptions/{sub}/resourceGroups/$resourceGroup/providers/Microsoft.EventHub/namespaces/$namespace/eventhubs/$hubName \
  --metric IncomingMessages \
  --start-time 2024-01-01T00:00:00 \
  --end-time 2024-01-02T00:00:00 \
  --interval PT1M

# Stream container logs
az containerapp logs show \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --follow

# Get app URL
az containerapp show \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --query properties.configuration.ingress.fqdn

# Scale container app
az containerapp update \
  --resource-group $resourceGroup \
  --name $containerAppName \
  --min-replicas 3 \
  --max-replicas 20
```

---

*Version*: 1.0
*Last Updated*: December 16, 2024
