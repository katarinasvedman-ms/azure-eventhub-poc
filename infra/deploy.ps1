#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploys Azure Event Hub infrastructure using Bicep template

.DESCRIPTION
This script deploys an Azure Event Hub (Standard SKU) with 24 partitions,
storage account for checkpointing, and consumer groups for local development.

.PARAMETER ResourceGroupName
Name of the resource group to create/deploy to

.PARAMETER Location
Azure region for deployment (default: eastus)

.PARAMETER Environment
Environment name - dev, test, prod (default: dev)

.PARAMETER Subscription
Azure subscription ID or name to deploy to (optional, uses current if not specified)

.EXAMPLE
./deploy.ps1 -ResourceGroupName "rg-logsysng-dev" -Location "eastus"

.EXAMPLE
./deploy.ps1 -ResourceGroupName "rg-logsysng-prod" -Environment "prod" -Location "westus2"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory = $false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory = $false)]
    [string]$Subscription = $null
)

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                   Azure Event Hub Bicep Deployment Script                      ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Validate prerequisites
Write-Host "🔍 Validating prerequisites..." -ForegroundColor Yellow
try {
    $azVersion = az version | ConvertFrom-Json
    Write-Host "✓ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
}
catch {
    Write-Host "✗ Azure CLI not found. Please install: https://learn.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Red
    exit 1
}

# Check if Bicep CLI is available
try {
    $bicepVersion = az bicep version
    Write-Host "✓ Bicep CLI available" -ForegroundColor Green
}
catch {
    Write-Host "⚠ Bicep CLI not found. Installing..." -ForegroundColor Yellow
    az bicep install
}

# Verify templates exist
if (-not (Test-Path "main.bicep")) {
    Write-Host "✗ main.bicep not found in current directory" -ForegroundColor Red
    exit 1
}
Write-Host "✓ main.bicep found" -ForegroundColor Green

if (-not (Test-Path "parameters.$Environment.json")) {
    Write-Host "✗ parameters.$Environment.json not found" -ForegroundColor Red
    exit 1
}
Write-Host "✓ parameters.$Environment.json found" -ForegroundColor Green

Write-Host ""

# Set subscription if provided
if ($Subscription) {
    Write-Host "🔑 Setting subscription..." -ForegroundColor Yellow
    az account set --subscription $Subscription
    Write-Host "✓ Subscription set" -ForegroundColor Green
}

# Get current subscription info
$currentSubscription = az account show | ConvertFrom-Json
Write-Host "📋 Current subscription: $($currentSubscription.name) ($($currentSubscription.id))" -ForegroundColor Cyan

Write-Host ""

# Create resource group
Write-Host "📁 Creating resource group..." -ForegroundColor Yellow
$rg = az group create `
    --name $ResourceGroupName `
    --location $Location | ConvertFrom-Json

Write-Host "✓ Resource group created/verified: $ResourceGroupName" -ForegroundColor Green
Write-Host "  Location: $($rg.location)" -ForegroundColor Gray

Write-Host ""

# Validate Bicep template
Write-Host "🔎 Validating Bicep template..." -ForegroundColor Yellow
try {
    az deployment group validate `
        --resource-group $ResourceGroupName `
        --template-file main.bicep `
        --parameters parameters.$Environment.json `
        --parameters environment=$Environment | Out-Null
    Write-Host "✓ Template validation passed" -ForegroundColor Green
}
catch {
    Write-Host "✗ Template validation failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Deploy
Write-Host "🚀 Deploying Event Hub infrastructure..." -ForegroundColor Yellow
Write-Host "   Template: main.bicep" -ForegroundColor Gray
Write-Host "   Parameters: parameters.$Environment.json" -ForegroundColor Gray
Write-Host "   Environment: $Environment" -ForegroundColor Gray
Write-Host ""

try {
    $deployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file main.bicep `
        --parameters parameters.$Environment.json `
        --parameters environment=$Environment `
        --output json | ConvertFrom-Json
    
    Write-Host "✓ Deployment completed successfully" -ForegroundColor Green
}
catch {
    Write-Host "✗ Deployment failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Extract outputs
Write-Host "📤 Deployment Outputs:" -ForegroundColor Yellow
Write-Host ""

if ($deployment.properties.outputs) {
    $outputs = $deployment.properties.outputs
    
    $eventHubNamespace = $outputs.eventHubNamespaceName.value
    $eventHubName = $outputs.eventHubName.value
    $partitionCount = $outputs.partitionCount.value
    $storageAccount = $outputs.storageAccountName.value
    $sendConnStr = $outputs.sendPolicyConnectionString.value
    $listenConnStr = $outputs.listenPolicyConnectionString.value
    $storageConnStr = $outputs.storageAccountConnectionString.value
    
    Write-Host "Event Hub Namespace:" -ForegroundColor Cyan
    Write-Host "  Name: $eventHubNamespace" -ForegroundColor White
    Write-Host "  Region: $Location" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Event Hub Details:" -ForegroundColor Cyan
    Write-Host "  Hub Name: $eventHubName" -ForegroundColor White
    Write-Host "  Partitions: $partitionCount" -ForegroundColor White
    Write-Host "  Retention: 1 day" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Storage Account:" -ForegroundColor Cyan
    Write-Host "  Name: $storageAccount" -ForegroundColor White
    Write-Host "  Container: checkpoints" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Connection Strings:" -ForegroundColor Cyan
    Write-Host "  Producer (Send):" -ForegroundColor White
    Write-Host "  $sendConnStr" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Consumer (Listen):" -ForegroundColor White
    Write-Host "  $listenConnStr" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Storage Account:" -ForegroundColor White
    Write-Host "  $storageConnStr" -ForegroundColor DarkCyan
    Write-Host ""
}

Write-Host ""

# Create appsettings fragment
Write-Host "📝 Creating appsettings.json configuration fragment..." -ForegroundColor Yellow

$appSettingsFragment = @{
    "EventHub" = @{
        "FullyQualifiedNamespace" = "$eventHubNamespace.servicebus.windows.net"
        "EventHubName"             = $eventHubName
        "ProducerConnectionString" = $sendConnStr
        "ConsumerConnectionString" = $listenConnStr
        "BatchSize"                = 100
        "BatchTimeoutMs"           = 1000
    }
    "Storage" = @{
        "ConnectionString" = $storageConnStr
        "ContainerName"    = "checkpoints"
    }
} | ConvertTo-Json -Depth 10

# Save to file
$configFile = "appsettings.generated.json"
$appSettingsFragment | Out-File -FilePath $configFile -Encoding utf8
Write-Host "✓ Configuration saved to: $configFile" -ForegroundColor Green
Write-Host ""

# Final summary
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                         ✓ Deployment Successful!                              ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "🎯 Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Update your appsettings.json with configuration from appsettings.generated.json"
Write-Host "   Copy the EventHub and Storage sections into your appsettings.json"
Write-Host ""
Write-Host "2. Run your producer/consumer application:"
Write-Host "   dotnet run --configuration Release"
Write-Host ""
Write-Host "3. Monitor in Azure Portal:"
Write-Host "   https://portal.azure.com/#resource/subscriptions/$($currentSubscription.id)/resourceGroups/$ResourceGroupName"
Write-Host ""
Write-Host "4. View metrics:"
Write-Host "   Event Hub → Metrics → Incoming/Outgoing Messages"
Write-Host ""
Write-Host "5. Load test (optional):"
Write-Host "   k6 run load-test.js"
Write-Host ""

# Optional: Open portal
$openPortal = Read-Host "Open Azure Portal? (y/n)"
if ($openPortal -eq "y" -or $openPortal -eq "yes") {
    $portalUrl = "https://portal.azure.com/#resource/subscriptions/$($currentSubscription.id)/resourceGroups/$ResourceGroupName"
    Start-Process $portalUrl
}

Write-Host "✓ Done!" -ForegroundColor Green
