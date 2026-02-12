# Quick Start: Bicep Deployment

## 1️⃣ Prerequisites

```powershell
# Install Azure CLI
# https://learn.microsoft.com/cli/azure/install-azure-cli

# Install Azure Functions Core Tools v4
npm install -g azure-functions-core-tools@4

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
.\deploy.ps1 -ResourceGroupName "rg-eventhub-dev" -Location "eastus"
```

### Linux/Mac (Bash)

```bash
cd deploy

# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh -g "rg-eventhub-dev" -l "eastus" -e "dev"
```

### Manual Azure CLI

```powershell
# Create resource group
az group create --name "rg-eventhub-dev" --location "eastus"

# Deploy template
az deployment group create `
  --resource-group "rg-eventhub-dev" `
  --template-file main.bicep `
  --parameters parameters.dev.json `
  --parameters environment=dev
```

## 3️⃣ Get Output

The deployment script automatically creates `appsettings.generated.json` with all connection strings.

If you deployed manually:

```powershell
az deployment group show `
  --resource-group "rg-eventhub-dev" `
  --name "main" `
  --query "properties.outputs" `
  --output json
```

## 4️⃣ Configure Connection Strings

The deployment script generates connection strings. Configure each component:

**Producer** (`src/appsettings.json`):
```json
{
  "EventHub": {
    "FullyQualifiedNamespace": "your-namespace.servicebus.windows.net",
    "HubName": "logs",
    "ConnectionString": "Endpoint=sb://...;SharedAccessKeyName=SendPolicy;SharedAccessKey=...",
    "UseKeyAuthentication": true
  }
}
```

**Consumer** (`src-function/local.settings.json`):
```json
{
  "Values": {
    "AzureWebJobsStorage": "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...",
    "CheckpointStoreConnection": "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...",
    "EventHubConnection": "Endpoint=sb://...;SharedAccessKeyName=ListenPolicy;SharedAccessKey=...",
    "EventHubName": "logs",
    "EventHubConsumerGroup": "logs-consumer",
    "SqlConnectionString": "Server=tcp:your-server.database.windows.net,1433;Database=your-db;Encrypt=True;TrustServerCertificate=False"
  }
}
```

## 5️⃣ Apply SQL Migration

```powershell
# Run the idempotency migration (first time only)
$token = (az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv)
# Execute infra/migrations/001_add_idempotency.sql against your SQL database
```

## 6️⃣ Run Consumer (Azure Functions)

```powershell
cd src-function

# Build and publish
dotnet publish -c Release -o publish

# Start the function
cd publish
$token = (az account get-access-token --resource "https://database.windows.net/" --query accessToken -o tsv)
$env:SqlAccessToken = $token
func start
```

## 7️⃣ Send Events (Producer Load Test)

```powershell
cd src

# Quick test (~7,000 events)
dotnet run -c Release -- --load-test=5

# Sustained test
dotnet run -c Release -- --load-test=30
```

## 6️⃣ Monitor

### Azure Portal
https://portal.azure.com → Search for your resource group

### Azure CLI
```powershell
# Get resource group
az group show --name "rg-eventhub-dev" --output table

# List resources
az resource list --resource-group "rg-eventhub-dev" --output table

# Get Event Hub details
az eventhubs namespace show `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev" `
  --output table
```

### View Logs (Application Insights if configured)
```powershell
# Check if Application Insights is available
az resource list --resource-group "rg-eventhub-dev" --output table
```

## 7️⃣ Cleanup

```powershell
# Delete entire resource group (removes ALL resources)
az group delete --name "rg-eventhub-dev" --yes --no-wait

# Or keep storage for compliance/archival
az eventhubs namespace delete `
  --name "eventhub-dev-xxx" `
  --resource-group "rg-eventhub-dev"
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
| **Event Hub Namespace** | Standard SKU, auto-inflate enabled |
| **Event Hub (logs)** | 24 partitions, 24h retention |
| **Consumer Groups** | `logs-consumer` |
| **Storage Account** | For checkpoint storage (blob) and function host |
| **SQL Database** | With `EventLogs` table and idempotency index |
| **Authorization Policies** | `SendPolicy` (producer), `ListenPolicy` (consumer) |

**Estimated Cost:** ~$75-100/month

---

For complete documentation, see `README.md` and `DEPLOYMENT.md`.
