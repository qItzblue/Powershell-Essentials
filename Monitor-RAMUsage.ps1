<#
.SYNOPSIS
    Monitor RAM usage and alert when above threshold
.DESCRIPTION
    Continuously monitors RAM usage and alerts when usage exceeds specified percentage
.PARAMETER ThresholdPercent
    RAM usage threshold percentage (default: 85)
.PARAMETER LogPath
    Path to log file (default: .\ram_usage_log.txt)
.PARAMETER CheckInterval
    Interval between checks in seconds (default: 10)
.PARAMETER ShowTopProcesses
    Number of top RAM-consuming processes to show on alert (default: 5)
#>

param(
    [int]$ThresholdPercent = 85,
    [string]$LogPath = ".\ram_usage_log.txt",
    [int]$CheckInterval = 10,
    [int]$ShowTopProcesses = 5
)

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    Write-Host $logEntry -ForegroundColor $(if($Message -match "ALERT") {"Red"} else {"Cyan"})
}

function Format-Bytes {
    param([long]$Bytes)
    $sizes = 'B','KB','MB','GB','TB'
    $index = 0
    $value = $Bytes
    while ($value -ge 1024 -and $index -lt $sizes.Length - 1) {
        $value = $value / 1024
        $index++
    }
    return "{0:N2} {1}" -f $value, $sizes[$index]
}

function Get-TopRAMProcesses {
    param([int]$Count = 5)
    
    Get-Process | 
        Where-Object { $_.WorkingSet64 -gt 0 } |
        Sort-Object WorkingSet64 -Descending | 
        Select-Object -First $Count |
        ForEach-Object {
            @{
                Name = $_.ProcessName
                PID = $_.Id
                RAM = Format-Bytes $_.WorkingSet64
                RAMBytes = $_.WorkingSet64
            }
        }
}

Write-Host "=== RAM Usage Monitor ===" -ForegroundColor Cyan
Write-Host "Threshold: $ThresholdPercent%" -ForegroundColor Yellow
Write-Host "Log Path: $LogPath" -ForegroundColor Yellow
Write-Host "Check Interval: $CheckInterval seconds" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop monitoring`n" -ForegroundColor Yellow

Write-Log "RAM Usage Monitoring Started - Threshold: $ThresholdPercent%"

$alertCount = 0
$lastAlertTime = [DateTime]::MinValue

while ($true) {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRAM = $os.TotalVisibleMemorySize
    $freeRAM = $os.FreePhysicalMemory
    $usedRAM = $totalRAM - $freeRAM
    $usagePercent = [math]::Round(($usedRAM / $totalRAM) * 100, 2)
    
    $totalGB = [math]::Round($totalRAM / 1MB, 2)
    $usedGB = [math]::Round($usedRAM / 1MB, 2)
    $freeGB = [math]::Round($freeRAM / 1MB, 2)
    
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $message = "$timestamp - RAM: $usedGB GB / $totalGB GB ($usagePercent%) | Free: $freeGB GB"
    
    if ($usagePercent -gt $ThresholdPercent) {
        $alertCount++
        $timeSinceLastAlert = (Get-Date) - $lastAlertTime
        
        # Only log detailed alert every 60 seconds to avoid spam
        if ($timeSinceLastAlert.TotalSeconds -gt 60) {
            Write-Log "⚠️ ALERT! RAM Usage: $usagePercent% (Alert #$alertCount)"
            
            $topProcesses = Get-TopRAMProcesses -Count $ShowTopProcesses
            Write-Log "Top $ShowTopProcesses RAM-consuming processes:"
            
            foreach ($proc in $topProcesses) {
                $procMessage = "  - $($proc.Name) (PID: $($proc.PID)): $($proc.RAM)"
                Write-Log $procMessage
            }
            
            $lastAlertTime = Get-Date
            [Console]::Beep(800, 300)
        }
        else {
            Write-Host $message -ForegroundColor Red
        }
    }
    else {
        $color = if ($usagePercent -gt 70) { "Yellow" } else { "Green" }
        Write-Host $message -ForegroundColor $color
    }
    
    Start-Sleep -Seconds $CheckInterval
}
