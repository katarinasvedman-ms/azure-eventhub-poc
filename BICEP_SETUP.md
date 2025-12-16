# Bicep Deployment - Complete Setup

## 📁 What's Included

```
deploy/
├── main.bicep                 # Main infrastructure definition
├── parameters.dev.json        # Parameter file for dev environment
├── deploy.ps1                 # PowerShell deployment script (Windows)
├── deploy.sh                  # Bash deployment script (Linux/Mac)
├── README.md                  # Comprehensive deployment guide
├── VARIABLES.md               # Parameter reference guide
└── appsettings.generated.json # Auto-generated after deployment
```

## 🚀 Quick Start (3 Steps)

### Step 1: Authenticate with Azure
```powershell
az login
az account set --subscription "your-subscription-id"
```

### Step 2: Deploy Infrastructure
```powershell
cd deploy
.\deploy.ps1 -ResourceGroupName "rg-logsysng-dev" -Location "eastus"
```

### Step 3: Update Your App Config
Copy connection strings from `appsettings.generated.json` into your `appsettings.json`

---

## 📊 What Gets Deployed

### Event Hub (Standard SKU)
- **Namespace**: Globally unique name (auto-generated)
- **Hub Name**: `logs`
- **Partitions**: 24 (supports 20k events/sec)
- **Retention**: 1 day
- **Capacity**: 1 TU (Throughput Unit)
- **Max Throughput**: 32 MB/sec (32,000 events/sec @ 1KB)
- **Max Consumer Groups**: 20

### Consumer Groups (3 created)
1. **logs-consumer** - Main event processing
2. **monitoring-consumer** - Monitoring and diagnostics
3. **archive-consumer** - Archival and backup

### Storage Account
- **Purpose**: Checkpoint storage for consumer group state
- **SKU**: Standard LRS (Locally Redundant Storage)
- **Container**: `checkpoints`
- **Access**: HTTPS only, TLS 1.2 minimum

### Authorization Policies
- **SendPolicy** - For producers (Send permission)
- **ListenPolicy** - For consumers (Listen + Manage permissions)

---

## 🔧 Configuration Reference

### Event Hub Parameters
| Parameter | Default | Range | Notes |
|---|---|---|---|
| location | Resource group location | Azure regions | Where to deploy |
| environment | dev | dev/test/prod | Used in naming |
| partitionCount | 24 | 1-32 (Standard) | Affects throughput |
| messageRetentionInDays | 1 | 1-90 | Event retention period |
| storageAccountSku | Standard_LRS | See VARIABLES.md | Storage redundancy |

### Outputs Provided
- Event Hub namespace name and ID
- Event Hub name and ID
- Storage account connection string
- Producer connection string (SendPolicy)
- Consumer connection string (ListenPolicy)
- Storage connection string

---

## 📝 How to Deploy

### Option A: PowerShell (Windows Recommended)

```powershell
cd deploy

# Run with defaults (eastus, dev environment)
.\deploy.ps1 -ResourceGroupName "rg-logsysng-dev"

# Run with custom location
.\deploy.ps1 -ResourceGroupName "rg-logsysng-prod" `
  -Location "westus2" `
  -Environment "prod"
```

**What the script does:**
✓ Validates prerequisites (Azure CLI, Bicep)  
✓ Creates resource group  
✓ Validates Bicep template  
✓ Deploys infrastructure  
✓ Extracts outputs  
✓ Generates appsettings.json  
✓ Opens Azure Portal (optional)

### Option B: Bash (Linux/Mac)

```bash
cd deploy
chmod +x deploy.sh

# Run with defaults
./deploy.sh -g "rg-logsysng-dev"

# Run with custom parameters
./deploy.sh -g "rg-logsysng-prod" \
  -l "westus2" \
  -e "prod"
```

### Option C: Azure CLI (Manual)

```powershell
# Create resource group
az group create --name "rg-logsysng-dev" --location "eastus"

# Deploy template
az deployment group create `
  --resource-group "rg-logsysng-dev" `
  --template-file main.bicep `
  --parameters parameters.dev.json `
  --parameters environment=dev

# Get outputs
az deployment group show `
  --resource-group "rg-logsysng-dev" `
  --name "main" `
  --query "properties.outputs" `
  --output json
```

---

## ✅ Post-Deployment Checklist

- [ ] Deployment script completed successfully
- [ ] `appsettings.generated.json` created
- [ ] Connection strings copied to `appsettings.json`
- [ ] Resource group visible in Azure Portal
- [ ] Event Hub namespace accessible
- [ ] Storage account created with checkpoints container
- [ ] Consumer groups (3) visible in Event Hub
- [ ] Authorization policies (SendPolicy, ListenPolicy) created

---

## 🔌 Connect Your Application

### 1. Copy Configuration
From `appsettings.generated.json`:

```json
{
  "EventHub": {
    "FullyQualifiedNamespace": "eventhub-dev-xxx.servicebus.windows.net",
    "EventHubName": "logs",
    "ProducerConnectionString": "Endpoint=sb://...",
    "ConsumerConnectionString": "Endpoint=sb://...",
    "BatchSize": 100,
    "BatchTimeoutMs": 1000
  },
  "Storage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;...",
    "ContainerName": "checkpoints"
  }
}
```

### 2. Update appsettings.json
Merge above into your `appsettings.json`

### 3. Run Application
```powershell
dotnet run --configuration Release
```

### 4. Verify Connection
Look for logs:
```
Connecting to Event Hub: eventhub-dev-xxx
Producer connected successfully
Consumer connected successfully
Checkpoint manager initialized
```

---

## 📊 Monitoring

### Azure Portal
1. Go to resource group: `rg-logsysng-dev`
2. Click Event Hub namespace
3. View metrics:
   - **Incoming Messages** - Events received
   - **Outgoing Messages** - Events consumed
   - **Active Connections** - Connected clients
   - **Throttled Requests** - Rate limiting (429 errors)

### Azure CLI
```powershell
# View Event Hub properties
az eventhubs eventhub show `
  --namespace-name "eventhub-dev-xxx" `
  --resource-group "rg-logsysng-dev" `
  --name "logs" `
  --output table

# View consumer group status
az eventhubs eventhub consumer-group show `
  --namespace-name "eventhub-dev-xxx" `
  --resource-group "rg-logsysng-dev" `
  --eventhub-name "logs" `
  --name "logs-consumer" `
  --output table

# View storage account
az storage account show `
  --name "sablobcheckpointxxx" `
  --resource-group "rg-logsysng-dev" `
  --output table
```

---

## 🚨 Troubleshooting

### Deployment Fails: "Namespace already exists"
**Cause**: Namespace names must be globally unique  
**Solution**: Don't specify namespace name; let bicep auto-generate it

### Deployment Fails: "InvalidStorageAccountName"
**Cause**: Storage account names: 3-24 chars, lowercase, alphanumeric only  
**Solution**: Let bicep auto-generate the name

### Cannot Connect: "ConnectionRefused"
**Cause**: Connection string incorrect or Event Hub not accessible  
**Solution**: 
1. Verify connection string from `appsettings.generated.json`
2. Verify Event Hub namespace is "Publicly accessible"
3. Check firewall: Allow outbound HTTPS (port 443)

### Cannot Access Checkpoints
**Cause**: Storage account connection string incorrect  
**Solution**:
1. Verify storage connection string
2. Check container name is exactly "checkpoints"
3. Verify storage account exists and is accessible

---

## 💰 Cost Breakdown

**Monthly (Approximate)**

| Component | Cost |
|---|---|
| Event Hub Namespace (Standard, 1 TU) | $50 |
| 24 Partitions | Included in above |
| Ingestion (20k evt/sec × 30 days) | +$200 |
| Storage Account (1 GB/month) | +$0.50 |
| **Total** | **~$75-100/month** |

*Costs vary by region. Premium tier would be 5-6x higher. Use Azure Cost Calculator for precise estimates.*

---

## 🔄 Scaling Path

| Year | Events/Sec | Partitions | SKU | Action |
|---|---|---|---|---|
| 1 (Now) | 20,000 | 24 | Standard | ✅ Deploy |
| 2 | 40,000 | 40 | Premium | Upgrade when needed |
| 3+ | 100,000+ | 100+ | Premium/Dedicated | Contact support |

**Upgrade procedure** (when ready):
1. Edit `main.bicep` - change SKU to Premium
2. Redeploy using deployment script
3. Increase partitions in parameters file
4. No downtime - Azure handles migration

---

## 🧹 Cleanup

```powershell
# Delete everything (Event Hub, Storage, Resource Group)
az group delete --name "rg-logsysng-dev" --yes --no-wait

# Or delete just Event Hub (keep storage)
az eventhubs namespace delete `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-logsysng-dev"
```

---

## 📚 Additional Resources

- **[Event Hub Overview](https://learn.microsoft.com/azure/event-hubs/event-hubs-about)**
- **[Event Hub Quotas & Limits](https://learn.microsoft.com/azure/event-hubs/event-hubs-quotas)**
- **[Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)**
- **[Azure CLI Reference](https://learn.microsoft.com/cli/azure/eventhubs/)**

---

## 📖 For Complete Details

See:
- `README.md` - Full deployment guide
- `VARIABLES.md` - Parameter reference
- `main.bicep` - Infrastructure code
- `SKU_RECOMMENDATION.md` - Sizing guidance

---

**Status**: ✅ Ready for Deployment  
**Last Updated**: December 16, 2025  
**Target**: Azure Event Hub Standard SKU for 20,000 events/sec
