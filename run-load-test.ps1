#!/usr/bin/env pwsh

<#
.SYNOPSIS
Load test runner for Event Hub PoC

.DESCRIPTION
Runs the 20k events/sec load test via the API and displays results

.PARAMETER Duration
Test duration in seconds (default: 60)

.PARAMETER ReportPath
Output report file path (default: load-test-report.md)

.PARAMETER Endpoint
API endpoint URL (default: https://localhost:5001)

.EXAMPLE
./run-load-test.ps1 -Duration 60
./run-load-test.ps1 -Duration 120 -ReportPath ./my-report.md
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$Duration = 60,
    
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = "load-test-report.md",
    
    [Parameter(Mandatory = $false)]
    [string]$Endpoint = "http://localhost:5000"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Event Hub Load Test Runner                                 ║" -ForegroundColor Cyan
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Duration: $Duration seconds"
Write-Host "  Report Path: $ReportPath"
Write-Host "  API Endpoint: $Endpoint"
Write-Host ""

Write-Host "Starting load test..." -ForegroundColor Yellow
Write-Host "  Target: 20,000 events/sec"
Write-Host "  Batch Size: 100 events"
Write-Host ""

try {
    $startTime = Get-Date
    
    $response = Invoke-WebRequest `
        -Uri "$Endpoint/api/loadtest/run?duration=$Duration&reportPath=$ReportPath" `
        -Method Get `
        -ContentType "application/json" `
        -SkipCertificateCheck
    
    $endTime = Get-Date
    $actualDuration = ($endTime - $startTime).TotalSeconds
    
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Load test completed successfully" -ForegroundColor Green
        Write-Host ""
        Write-Host "Results:" -ForegroundColor Yellow
        Write-Host "  Actual Duration: $($actualDuration.ToString('F2'))s"
        
        $report = Get-Content -Path $ReportPath
        
        # Extract key metrics from report
        if ($report -match "Actual Throughput.*?\|\s*(\d+[\,\d]*)\s*evt/sec") {
            Write-Host "  Throughput: $($Matches[1]) evt/sec"
        }
        if ($report -match "Success Rate.*?\|\s*([\d.]+)%") {
            Write-Host "  Success Rate: $($Matches[1])%"
        }
        
        Write-Host ""
        Write-Host "📊 Report Details:" -ForegroundColor Cyan
        Write-Host ""
        
        # Show first 50 lines of report
        $lines = $report -split "`n" | Select-Object -First 50
        foreach ($line in $lines) {
            Write-Host $line
        }
        
        Write-Host ""
        Write-Host "📄 Full report saved to: $(Resolve-Path $ReportPath)" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Unexpected response: $($response.StatusCode)" -ForegroundColor Red
    }
}
catch {
    Write-Host "❌ Error running load test:" -ForegroundColor Red
    Write-Host "   $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Is the API running? dotnet run"
    Write-Host "  2. Is the endpoint correct? (-Endpoint parameter)"
    Write-Host "  3. Check firewall/network connectivity"
    exit 1
}

Write-Host ""
Write-Host "✅ Load test completed!" -ForegroundColor Green
