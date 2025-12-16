# Quick Start: Bicep Deployment

## 1️⃣ Prerequisites

```powershell
# Install Azure CLI (if not already installed)
# https://learn.microsoft.com/cli/azure/install-azure-cli

# Login to Azure
az login

# List subscriptions
az account list --output table

# Set your subscription
az account set --subscription "your-subscription-id"
```

## 2️⃣ Deploy Infrastructure

### Windows (PowerShell)

```powershell
cd deploy

# Make script executable (might not be needed on Windows)
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Run deployment
.\deploy.ps1 -ResourceGroupName "rg-logsysng-dev" -Location "eastus"
```

### Linux/Mac (Bash)

```bash
cd deploy

# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh -g "rg-logsysng-dev" -l "eastus" -e "dev"
```

### Manual Azure CLI

```powershell
# Create resource group
az group create --name "rg-logsysng-dev" --location "eastus"

# Deploy template
az deployment group create `
  --resource-group "rg-logsysng-dev" `
  --template-file main.bicep `
  --parameters parameters.dev.json `
  --parameters environment=dev
```

## 3️⃣ Get Output

The deployment script automatically creates `appsettings.generated.json` with all connection strings.

If you deployed manually:

```powershell
az deployment group show `
  --resource-group "rg-logsysng-dev" `
  --name "main" `
  --query "properties.outputs" `
  --output json
```

## 4️⃣ Configure Your App

Copy the generated configuration into your `appsettings.json`:

```json
{
  "EventHub": {
    "FullyQualifiedNamespace": "eventhub-dev-xxx.servicebus.windows.net",
    "EventHubName": "logs",
    "ProducerConnectionString": "Endpoint=sb://eventhub-dev-xxx.servicebus.windows.net/;SharedAccessKeyName=SendPolicy;SharedAccessKey=...",
    "ConsumerConnectionString": "Endpoint=sb://eventhub-dev-xxx.servicebus.windows.net/;SharedAccessKeyName=ListenPolicy;SharedAccessKey=...",
    "BatchSize": 100,
    "BatchTimeoutMs": 1000
  },
  "Storage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;AccountName=sablobcheckpointxxx;AccountKey=...;EndpointSuffix=core.windows.net",
    "ContainerName": "checkpoints"
  }
}
```

## 5️⃣ Run Locally

```powershell
# Go to project root
cd ..

# Run producer/consumer
dotnet run --configuration Release

# Or with specific environment
dotnet run --configuration Release --launch-profile Development
```

## 6️⃣ Monitor

### Azure Portal
https://portal.azure.com → Search for your resource group

### Azure CLI
```powershell
# Get resource group
az group show --name "rg-logsysng-dev" --output table

# List resources
az resource list --resource-group "rg-logsysng-dev" --output table

# Get Event Hub details
az eventhubs namespace show `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-logsysng-dev" `
  --output table
```

### View Logs (Application Insights if configured)
```powershell
# Check if Application Insights is available
az resource list --resource-group "rg-logsysng-dev" --output table
```

## 7️⃣ Cleanup

```powershell
# Delete entire resource group (removes ALL resources)
az group delete --name "rg-logsysng-dev" --yes --no-wait

# Or keep storage for compliance/archival
az eventhubs namespace delete `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-logsysng-dev"
```

---

## Troubleshooting

### "Namespace already exists"
- Namespace names must be globally unique
- Edit `parameters.dev.json` and change the name

### "Insufficient quota"
- Standard tier limited to 40 TUs per region
- Try a different region or contact support

### "Cannot connect"
- Verify connection string copied correctly
- Check firewall: Event Hub should be publicly accessible
- Verify local machine can reach outbound HTTPS

### "Storage account not found"
- Check `appsettings.json` has correct storage connection string
- Verify container name is "checkpoints"
- Check storage account exists in Azure Portal

---

## What Gets Deployed?

| Resource | Details |
|---|---|
| **Event Hub Namespace** | Standard SKU, 1 TU, allows 32 partitions |
| **Event Hub (logs)** | 24 partitions, 1 day retention |
| **Consumer Groups** | logs-consumer, monitoring-consumer, archive-consumer |
| **Storage Account** | For checkpoint storage (blob storage) |
| **Authorization Policies** | SendPolicy (producer), ListenPolicy (consumer) |

**Total Cost:** ~$75-100/month

---

## Next: Load Testing

```bash
cd load-test
k6 run load-test.js --vus 100 --duration 30s
```

---

For complete documentation, see `README.md` in the `deploy` folder.
