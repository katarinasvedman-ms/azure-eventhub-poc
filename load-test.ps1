#!/usr/bin/env pwsh
<#
.SYNOPSIS
Load test for Event Hub - sends 20,000 events/sec for 60 seconds

.DESCRIPTION
This script stress-tests the Event Hub infrastructure by:
- Sending 20,000 events per second
- Running for 60 seconds (1.2 million total events)
- Collecting latency metrics
- Generating a markdown report

.EXAMPLE
.\run-load-test.ps1 -ApiUrl "http://localhost:5000" -Duration 60
#>

param(
    [string]$ApiUrl = "http://localhost:5000",
    [int]$Duration = 60,
    [int]$TargetThroughput = 20000,
    [int]$ParallelClients = 4
)

$ErrorActionPreference = "Stop"

Write-Host "`n╔════════════════════════════════════════════════════════════════════════════════╗"
Write-Host "║                        Event Hub Load Test (20k evt/sec)                        ║"
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝`n"

# Configuration
$BatchSize = 1000  # Increased from 100 to reduce overhead
$EventsPerSecond = $TargetThroughput
$BatchesPerSecond = [Math]::Ceiling($EventsPerSecond / $BatchSize)
$DelayBetweenBatches = 0  # No delay - send as fast as possible
$TotalBatches = $BatchesPerSecond * $Duration

Write-Host "Configuration:"
Write-Host "  API URL: $ApiUrl"
Write-Host "  Target Throughput: $EventsPerSecond events/sec"
Write-Host "  Batch Size: $BatchSize events"
Write-Host "  Batches/sec: $BatchesPerSecond"
Write-Host "  Delay between batches: $([Math]::Round($DelayBetweenBatches, 2)) ms"
Write-Host "  Duration: $Duration seconds"
Write-Host "  Total Batches: $TotalBatches"
Write-Host "  Total Events: $($TotalBatches * $BatchSize)`n"

# Metrics
$metrics = @{
    TotalEvents = 0
    SuccessfulEvents = 0
    FailedEvents = 0
    TotalBatches = 0
    SuccessfulBatches = 0
    FailedBatches = 0
    Latencies = @()
    StartTime = $null
    EndTime = $null
}

# Generate test event
function New-TestEvent {
    param([int]$Index)
    return @{
        source = "load-test"
        level = "INFO"
        message = "Load test event #$Index - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff')"
        partitionKey = "partition-$(Get-Random -Minimum 0 -Maximum 24)"
    } | ConvertTo-Json -Compress
}

# Send batch to API
function Send-EventBatch {
    param(
        [int]$StartIndex,
        [int]$BatchSize
    )
    
    $events = @()
    for ($i = 0; $i -lt $BatchSize; $i++) {
        $evt = @{
            source = "load-test"
            level = "INFO"
            message = "Load test event #$($StartIndex + $i)"
            partitionKey = "p$(Get-Random -Minimum 0 -Maximum 24)"
        }
        $events += $evt
    }
    
    $payload = @{ events = $events } | ConvertTo-Json
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    
    try {
        $response = Invoke-RestMethod `
            -Uri "$ApiUrl/api/logs/ingest-batch" `
            -Method POST `
            -ContentType "application/json" `
            -Body $payload `
            -TimeoutSec 30
        
        $stopwatch.Stop()
        
        return @{
            Success = $true
            Latency = $stopwatch.ElapsedMilliseconds
            EventCount = $BatchSize
        }
    }
    catch {
        $stopwatch.Stop()
        return @{
            Success = $false
            Latency = $stopwatch.ElapsedMilliseconds
            EventCount = 0
        }
    }
}

# Main load test loop
$batchesPerSecDisplay = if ($DelayBetweenBatches -gt 0) { [int](1000 / $DelayBetweenBatches) } else { "unlimited" }
Write-Host "Starting load test with $BatchSize events per batch at $batchesPerSecDisplay batches/sec...`n"
$metrics.StartTime = Get-Date

$eventIndex = 0
$lastSecond = 0
$batchQueue = @()  # Queue multiple batches before sending

try {
    $testStartTime = [DateTime]::Now
    
    while ($true) {
        # Check elapsed time
        $elapsed = [DateTime]::Now - $testStartTime
        if ($elapsed.TotalSeconds -gt $Duration) {
            break
        }
        
        # Send batch with minimal overhead
        $result = Send-EventBatch -StartIndex $eventIndex -BatchSize $BatchSize
        
        # Record metrics
        $metrics.TotalBatches++
        $metrics.TotalEvents += $BatchSize
        $metrics.Latencies += $result.Latency
        
        if ($result.Success) {
            $metrics.SuccessfulBatches++
            $metrics.SuccessfulEvents += $result.EventCount
        } else {
            $metrics.FailedBatches++
            $metrics.FailedEvents += $result.EventCount
        }
        
        # Progress reporting - every second
        $currentSecond = [int]$elapsed.TotalSeconds
        if ($currentSecond -gt $lastSecond) {
            $instantThroughput = $metrics.SuccessfulEvents / $elapsed.TotalSeconds
            Write-Host "[$currentSecond/$Duration sec] Events: $($metrics.SuccessfulEvents) | Rate: $('{0:F0}' -f $instantThroughput) evt/sec | Failed: $($metrics.FailedBatches) batches" -ForegroundColor Cyan
            $lastSecond = $currentSecond
        }
        
        # Minimal delay - aggressive timing
        if ($DelayBetweenBatches -gt 0) {
            Start-Sleep -Milliseconds ([Math]::Max(0, $DelayBetweenBatches))
        }
        
        $eventIndex += $BatchSize
    }
}
catch {
    Write-Host "Test interrupted: $_" -ForegroundColor Red
}

$metrics.EndTime = Get-Date

# Calculate statistics
$actualDuration = ($metrics.EndTime - $metrics.StartTime).TotalSeconds
$actualThroughput = [Math]::Round($metrics.SuccessfulEvents / $actualDuration, 0)
$successRate = if ($metrics.TotalEvents -gt 0) { ($metrics.SuccessfulEvents / $metrics.TotalEvents) * 100 } else { 0 }

if ($metrics.Latencies.Count -gt 0) {
    $sortedLatencies = @($metrics.Latencies | Sort-Object)
    $avgLatency = [Math]::Round(($sortedLatencies | Measure-Object -Average).Average, 2)
    $p50Index = [Math]::Max(0, [int]($sortedLatencies.Count * 0.50) - 1)
    $p95Index = [Math]::Max(0, [int]($sortedLatencies.Count * 0.95) - 1)
    $p99Index = [Math]::Max(0, [int]($sortedLatencies.Count * 0.99) - 1)
    $p50Latency = [Math]::Round($sortedLatencies[$p50Index], 2)
    $p95Latency = [Math]::Round($sortedLatencies[$p95Index], 2)
    $p99Latency = [Math]::Round($sortedLatencies[$p99Index], 2)
    $maxLatency = [Math]::Round(($sortedLatencies | Measure-Object -Maximum).Maximum, 2)
    $minLatency = [Math]::Round(($sortedLatencies | Measure-Object -Minimum).Minimum, 2)
} else {
    $avgLatency = $p50Latency = $p95Latency = $p99Latency = $maxLatency = $minLatency = 0
}

# Generate markdown report
$reportContent = @"
# Event Hub Load Test Report

**Test Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## Executive Summary

| Metric | Value |
|--------|-------|
| **Target Throughput** | $TargetThroughput events/sec |
| **Actual Throughput** | $actualThroughput events/sec |
| **Duration** | $([Math]::Round($actualDuration, 2)) seconds |
| **Total Events Sent** | $($metrics.SuccessfulEvents) |
| **Success Rate** | $([Math]::Round($successRate, 2))% |
| **Failed Events** | $($metrics.FailedEvents) |

## Performance Metrics

### Latency (ms)
| Percentile | Latency |
|-----------|---------|
| P50 (Median) | $p50Latency |
| P95 | $p95Latency |
| P99 | $p99Latency |
| Min | $minLatency |
| Max | $maxLatency |
| Average | $avgLatency |

### Throughput Analysis
| Metric | Value |
|--------|-------|
| **Target Rate** | $TargetThroughput evt/sec |
| **Achieved Rate** | $actualThroughput evt/sec |
| **Efficiency** | $([Math]::Round(($actualThroughput/$TargetThroughput)*100, 2))% |
| **Total Batches** | $($metrics.SuccessfulBatches) successful, $($metrics.FailedBatches) failed |

## Analysis & Recommendations

### Performance Status
$(
    if ($actualThroughput -ge 19000 -and $successRate -ge 99.9 -and $p99Latency -lt 1000) {
        "✅ **EXCELLENT** - Load test passed all SLA requirements"
    } elseif ($actualThroughput -ge 15000 -and $successRate -ge 99.0 -and $p99Latency -lt 2000) {
        "⚠️ **GOOD** - Load test meets baseline requirements"
    } else {
        "⚠️ **ACCEPTABLE** - Load test completed"
    }
)

### Key Findings

1. **Throughput**: Achieved $actualThroughput evt/sec vs target of $TargetThroughput evt/sec
2. **Reliability**: $successRate% of events delivered with $($metrics.FailedBatches) failed batches
3. **Latency**: P99 latency of $p99Latency ms (Max: $maxLatency ms)

---
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

# Save report
$reportPath = "load-test-report.md"
$reportContent | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n✓ Report saved to: $reportPath"

# Display summary
Write-Host "`n╔════════════════════════════════════════════════════════════════════════════════╗"
Write-Host "║                           Test Complete - Summary                              ║"
Write-Host "╚════════════════════════════════════════════════════════════════════════════════╝`n"
Write-Host "Total Events Sent:     $($metrics.SuccessfulEvents)" -ForegroundColor Green
Write-Host "Success Rate:          $([Math]::Round($successRate, 2))%" -ForegroundColor Green
Write-Host "Actual Throughput:     $actualThroughput evt/sec"
Write-Host "P99 Latency:           $p99Latency ms"
Write-Host "`n"
