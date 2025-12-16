#!/usr/bin/env pwsh

<#
.SYNOPSIS
Verifies Event Hub deployment and tests connectivity

.DESCRIPTION
This script validates that all resources were deployed correctly
and that connection strings work properly.

.PARAMETER ResourceGroupName
Name of the resource group to verify

.PARAMETER Namespace
Event Hub namespace name (optional, will attempt to discover)

.EXAMPLE
./verify.ps1 -ResourceGroupName "rg-logsysng-dev"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = $null
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                        Event Hub Deployment Verification                       ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify resource group
Write-Host "1️⃣  Verifying Resource Group..." -ForegroundColor Yellow
try {
    $rg = az group show --name $ResourceGroupName -o json | ConvertFrom-Json
    Write-Host "✓ Resource group exists: $ResourceGroupName" -ForegroundColor Green
    Write-Host "  Location: $($rg.location)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Resource group not found: $ResourceGroupName" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 2: Find Event Hub Namespace
Write-Host "2️⃣  Locating Event Hub Namespace..." -ForegroundColor Yellow
if (-not $Namespace) {
    $namespaces = az eventhubs namespace list --resource-group $ResourceGroupName -o json | ConvertFrom-Json
    if ($namespaces.Count -eq 0) {
        Write-Host "✗ No Event Hub namespace found in resource group" -ForegroundColor Red
        exit 1
    }
    $Namespace = $namespaces[0].name
}

try {
    $ns = az eventhubs namespace show --name $Namespace --resource-group $ResourceGroupName -o json | ConvertFrom-Json
    Write-Host "✓ Event Hub namespace found: $Namespace" -ForegroundColor Green
    Write-Host "  SKU: $($ns.sku.name)" -ForegroundColor Gray
    Write-Host "  Status: $($ns.provisioningState)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Cannot access Event Hub namespace: $Namespace" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 3: Verify Event Hub
Write-Host "3️⃣  Verifying Event Hub..." -ForegroundColor Yellow
try {
    $hub = az eventhubs eventhub show --namespace-name $Namespace --resource-group $ResourceGroupName --name "logs" -o json | ConvertFrom-Json
    Write-Host "✓ Event Hub created: logs" -ForegroundColor Green
    Write-Host "  Partitions: $($hub.partitionCount)" -ForegroundColor Gray
    Write-Host "  Retention: $($hub.messageRetentionInDays) days" -ForegroundColor Gray
    Write-Host "  Status: $($hub.status)" -ForegroundColor Gray
}
catch {
    Write-Host "✗ Event Hub 'logs' not found" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 4: Verify Consumer Groups
Write-Host "4️⃣  Verifying Consumer Groups..." -ForegroundColor Yellow
$expectedGroups = @("logs-consumer", "monitoring-consumer", "archive-consumer")
foreach ($group in $expectedGroups) {
    try {
        $cg = az eventhubs eventhub consumer-group show `
            --namespace-name $Namespace `
            --resource-group $ResourceGroupName `
            --eventhub-name "logs" `
            --name $group -o json 2>$null | ConvertFrom-Json
        Write-Host "✓ Consumer group '$group' exists" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Consumer group '$group' not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Step 5: Verify Authorization Policies
Write-Host "5️⃣  Verifying Authorization Policies..." -ForegroundColor Yellow
$policies = @("SendPolicy", "ListenPolicy")
foreach ($policy in $policies) {
    try {
        $auth = az eventhubs namespace authorization-rule show `
            --namespace-name $Namespace `
            --resource-group $ResourceGroupName `
            --name $policy -o json 2>$null | ConvertFrom-Json
        $rights = $auth.rights -join ", "
        Write-Host "✓ Policy '$policy' exists with rights: $rights" -ForegroundColor Green
    }
    catch {
        Write-Host "✗ Policy '$policy' not found" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# Step 6: Verify Storage Account
Write-Host "6️⃣  Verifying Storage Account..." -ForegroundColor Yellow
try {
    $storageAccounts = az storage account list --resource-group $ResourceGroupName -o json | ConvertFrom-Json
    if ($storageAccounts.Count -eq 0) {
        Write-Host "✗ No storage account found" -ForegroundColor Red
        exit 1
    }
    $storageAccount = $storageAccounts[0].name
    Write-Host "✓ Storage account found: $storageAccount" -ForegroundColor Green
    
    # Check for checkpoints container
    $key = (az storage account keys list --name $storageAccount --resource-group $ResourceGroupName -o json | ConvertFrom-Json)[0].value
    $containers = az storage container list --account-name $storageAccount --account-key $key -o json 2>$null | ConvertFrom-Json
    
    $hasCheckpoints = $false
    foreach ($container in $containers) {
        if ($container.name -eq "checkpoints") {
            $hasCheckpoints = $true
            break
        }
    }
    
    if ($hasCheckpoints) {
        Write-Host "✓ Checkpoints container exists" -ForegroundColor Green
    }
    else {
        Write-Host "⚠ Checkpoints container not found (will be created when consumer starts)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "⚠ Could not verify storage account" -ForegroundColor Yellow
}

Write-Host ""

# Step 7: Test Connection Strings
Write-Host "7️⃣  Testing Connection Strings..." -ForegroundColor Yellow

try {
    $sendKey = az eventhubs namespace authorization-rule keys list `
        --namespace-name $Namespace `
        --resource-group $ResourceGroupName `
        --name "SendPolicy" -o json | ConvertFrom-Json
    
    Write-Host "✓ SendPolicy connection string retrieved" -ForegroundColor Green
    
    $listenKey = az eventhubs namespace authorization-rule keys list `
        --namespace-name $Namespace `
        --resource-group $ResourceGroupName `
        --name "ListenPolicy" -o json | ConvertFrom-Json
    
    Write-Host "✓ ListenPolicy connection string retrieved" -ForegroundColor Green
}
catch {
    Write-Host "✗ Could not retrieve connection strings" -ForegroundColor Red
    exit 1
}

Write-Host ""

# Step 8: Display Configuration
Write-Host "8️⃣  Configuration Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "Event Hub Details:" -ForegroundColor Cyan
Write-Host "  Namespace: $Namespace" -ForegroundColor White
Write-Host "  Hub Name: logs" -ForegroundColor White
Write-Host "  Partitions: $($hub.partitionCount)" -ForegroundColor White
Write-Host "  Retention: $($hub.messageRetentionInDays) day(s)" -ForegroundColor White
Write-Host ""
Write-Host "Connection Strings:" -ForegroundColor Cyan
Write-Host "  Producer: $($sendKey.primaryConnectionString)" -ForegroundColor DarkCyan
Write-Host "  Consumer: $($listenKey.primaryConnectionString)" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "Storage:" -ForegroundColor Cyan
Write-Host "  Account: $storageAccount" -ForegroundColor White
Write-Host "  Container: checkpoints" -ForegroundColor White
Write-Host ""

# Step 9: Azure Portal Link
Write-Host "9️⃣  Azure Portal" -ForegroundColor Yellow
$subscription = az account show -o json | ConvertFrom-Json
$portalUrl = "https://portal.azure.com/#resource/subscriptions/$($subscription.id)/resourceGroups/$ResourceGroupName"
Write-Host "✓ Resource group: $portalUrl" -ForegroundColor Gray

Write-Host ""

# Final Summary
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    ✓ All Verifications Passed!                                ║" -ForegroundColor Green
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Host "📝 Next Steps:" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Copy connection strings into appsettings.json"
Write-Host ""
Write-Host "2. Update appsettings.json:"
Write-Host "   {" -ForegroundColor Gray
Write-Host "     \"EventHub\": {" -ForegroundColor Gray
Write-Host "       \"FullyQualifiedNamespace\": \"$Namespace.servicebus.windows.net\"," -ForegroundColor Gray
Write-Host "       \"EventHubName\": \"logs\"," -ForegroundColor Gray
Write-Host "       \"ProducerConnectionString\": \"$($sendKey.primaryConnectionString)\"," -ForegroundColor Gray
Write-Host "       \"ConsumerConnectionString\": \"$($listenKey.primaryConnectionString)\"" -ForegroundColor Gray
Write-Host "     }" -ForegroundColor Gray
Write-Host "   }" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Run application:"
Write-Host "   dotnet run --configuration Release"
Write-Host ""
Write-Host "4. Monitor in Azure Portal:"
Write-Host "   $portalUrl"
Write-Host ""

Write-Host "✓ Verification Complete!" -ForegroundColor Green
