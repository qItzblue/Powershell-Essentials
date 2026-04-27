<#
.SYNOPSIS
    Monitor disk health using SMART data
.DESCRIPTION
    Checks disk health status using WMI and SMART data
.PARAMETER LogPath
    Path to log file (default: .\disk_health_log.txt)
.PARAMETER CheckInterval
    Interval between checks in minutes (default: 60)
#>

param(
    [string]$LogPath = ".\disk_health_log.txt",
    [int]$CheckInterval = 60
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    Write-Host $logEntry -ForegroundColor $Color
}

function Get-DiskSMARTStatus {
    $disks = @()
    
    try {
        # Get physical disks
        $physicalDisks = Get-PhysicalDisk
        
        foreach ($disk in $physicalDisks) {
            $health = "Unknown"
            $healthColor = "Yellow"
            
            switch ($disk.HealthStatus) {
                "Healthy" { $health = "Healthy"; $healthColor = "Green" }
                "Warning" { $health = "Warning"; $healthColor = "Yellow" }
                "Unhealthy" { $health = "Unhealthy"; $healthColor = "Red" }
                default { $health = $disk.HealthStatus; $healthColor = "Yellow" }
            }
            
            $diskInfo = @{
                Model = $disk.FriendlyName
                SerialNumber = $disk.SerialNumber
                MediaType = $disk.MediaType
                BusType = $disk.BusType
                Size = [math]::Round($disk.Size / 1GB, 2)
                Health = $health
                HealthColor = $healthColor
                OperationalStatus = $disk.OperationalStatus
            }
            
            $disks += $diskInfo
        }
        
        # Get additional SMART data via WMI
        $wmiDisks = Get-WmiObject -Namespace root\wmi -Class MSStorageDriver_FailurePredictStatus -ErrorAction SilentlyContinue
        
        if ($wmiDisks) {
            $index = 0
            foreach ($wmiDisk in $wmiDisks) {
                if ($index -lt $disks.Count) {
                    $disks[$index].PredictFailure = $wmiDisk.PredictFailure
                    $disks[$index].Reason = $wmiDisk.Reason
                }
                $index++
            }
        }
    }
    catch {
        Write-Log "Error reading disk information: $_" -Color "Red"
    }
    
    return $disks
}

function Get-DiskTemperature {
    try {
        # Try to get temperature from WMI (requires admin rights)
        $temps = Get-WmiObject -Namespace "root\wmi" -Class MSStorageDriver_ATAPISmartData -ErrorAction SilentlyContinue
        
        if ($temps) {
            return "Temperature monitoring available (requires parsing)"
        }
    }
    catch {
        return "Temperature data unavailable"
    }
}

Write-Host "=== Disk Health Monitor (SMART) ===" -ForegroundColor Cyan
Write-Host "Log Path: $LogPath" -ForegroundColor Yellow
Write-Host "Check Interval: $CheckInterval minutes" -ForegroundColor Yellow
Write-Host "Press Ctrl+C to stop monitoring`n" -ForegroundColor Yellow

Write-Log "Disk Health Monitoring Started - Check Interval: $CheckInterval minutes"

$checkCount = 0

while ($true) {
    $checkCount++
    Write-Host "`n=== Disk Health Check #$checkCount ===" -ForegroundColor Cyan
    Write-Log "Performing disk health check #$checkCount"
    
    $disks = Get-DiskSMARTStatus
    
    if ($disks.Count -eq 0) {
        Write-Log "No disks found or insufficient permissions. Run as Administrator for full SMART data." -Color "Yellow"
    }
    else {
        foreach ($disk in $disks) {
            $message = "Disk: $($disk.Model) | Type: $($disk.MediaType) | Size: $($disk.Size) GB | Health: $($disk.Health) | Status: $($disk.OperationalStatus)"
            Write-Log $message -Color $disk.HealthColor
            
            if ($disk.PredictFailure) {
                Write-Log "⚠️ WARNING: Failure predicted for $($disk.Model)! Backup data immediately!" -Color "Red"
                [Console]::Beep(1000, 500)
            }
        }
    }
    
    # Get logical disk space info
    Write-Host "`n--- Logical Disk Space ---" -ForegroundColor Cyan
    $volumes = Get-Volume | Where-Object { $_.DriveLetter -and $_.Size -gt 0 }
    
    foreach ($vol in $volumes) {
        $usedGB = [math]::Round(($vol.Size - $vol.SizeRemaining) / 1GB, 2)
        $totalGB = [math]::Round($vol.Size / 1GB, 2)
        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
        $usedPercent = [math]::Round(($usedGB / $totalGB) * 100, 2)
        
        $color = "Green"
        if ($usedPercent -gt 90) { $color = "Red" }
        elseif ($usedPercent -gt 80) { $color = "Yellow" }
        
        $volMessage = "$($vol.DriveLetter): | Used: $usedGB GB / $totalGB GB ($usedPercent%) | Free: $freeGB GB | Type: $($vol.FileSystemType)"
        Write-Host $volMessage -ForegroundColor $color
        
        if ($usedPercent -gt 90) {
            Write-Log "⚠️ WARNING: Drive $($vol.DriveLetter): is $usedPercent% full!" -Color "Red"
        }
    }
    
    Write-Host "`nNext check in $CheckInterval minutes..." -ForegroundColor Gray
    Start-Sleep -Seconds ($CheckInterval * 60)
}
