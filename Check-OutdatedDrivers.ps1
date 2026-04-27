<#
.SYNOPSIS
    Check for outdated drivers and alert
.DESCRIPTION
    Scans system drivers and checks for available updates
.PARAMETER LogPath
    Path to log file (default: .\driver_check_log.txt)
.PARAMETER CheckOnStartup
    Run check immediately on script start (default: true)
#>

param(
    [string]$LogPath = ".\driver_check_log.txt",
    [bool]$CheckOnStartup = $true
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    Write-Host $logEntry -ForegroundColor $Color
}

function Get-OutdatedDrivers {
    Write-Host "Scanning for outdated drivers..." -ForegroundColor Cyan
    
    $drivers = @()
    
    try {
        # Get all PnP devices
        $devices = Get-WmiObject Win32_PnPSignedDriver | 
                   Where-Object { $_.DeviceName -and $_.DriverVersion }
        
        foreach ($device in $devices) {
            # Check if driver date is older than 2 years
            $driverDate = $null
            if ($device.DriverDate) {
                try {
                    $year = $device.DriverDate.Substring(0, 4)
                    $month = $device.DriverDate.Substring(4, 2)
                    $day = $device.DriverDate.Substring(6, 2)
                    $driverDate = Get-Date -Year $year -Month $month -Day $day
                }
                catch {}
            }
            
            $isOld = $false
            $age = "Unknown"
            
            if ($driverDate) {
                $daysDiff = (Get-Date) - $driverDate
                $isOld = $daysDiff.TotalDays -gt 730 # 2 years
                $age = "{0:N0} days old" -f $daysDiff.TotalDays
            }
            
            if ($isOld -or -not $driverDate) {
                $drivers += @{
                    DeviceName = $device.DeviceName
                    Manufacturer = $device.Manufacturer
                    DriverVersion = $device.DriverVersion
                    DriverDate = if ($driverDate) { $driverDate.ToString("yyyy-MM-dd") } else { "Unknown" }
                    Age = $age
                    DeviceClass = $device.DeviceClass
                    IsOld = $isOld
                }
            }
        }
    }
    catch {
        Write-Log "Error scanning drivers: $_" -Color "Red"
    }
    
    return $drivers
}

function Get-WindowsUpdateDrivers {
    Write-Host "Checking Windows Update for driver updates..." -ForegroundColor Cyan
    
    try {
        # Check if Windows Update service is running
        $wuService = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
        
        if ($wuService.Status -ne "Running") {
            Write-Log "Windows Update service is not running. Starting..." -Color "Yellow"
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
        }
        
        # Use Windows Update API
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        Write-Host "Searching for driver updates (this may take a minute)..." -ForegroundColor Yellow
        $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Driver'")
        
        if ($searchResult.Updates.Count -gt 0) {
            Write-Log "Found $($searchResult.Updates.Count) driver update(s) available:" -Color "Yellow"
            
            foreach ($update in $searchResult.Updates) {
                Write-Log "  - $($update.Title)" -Color "Cyan"
            }
            
            return $searchResult.Updates.Count
        }
        else {
            Write-Log "No driver updates found via Windows Update" -Color "Green"
            return 0
        }
    }
    catch {
        Write-Log "Unable to check Windows Update: $_" -Color "Yellow"
        Write-Log "Try running: Get-WindowsUpdate -MicrosoftUpdate (requires PSWindowsUpdate module)" -Color "Yellow"
        return -1
    }
}

function Show-DriverReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "    DRIVER UPDATE CHECK REPORT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Log "Starting driver scan..."
    
    # Check for outdated drivers
    $outdatedDrivers = Get-OutdatedDrivers
    
    Write-Host "`n--- Potentially Outdated Drivers (>2 years old) ---" -ForegroundColor Yellow
    if ($outdatedDrivers.Count -gt 0) {
        Write-Log "Found $($outdatedDrivers.Count) potentially outdated driver(s):" -Color "Yellow"
        
        foreach ($driver in $outdatedDrivers | Sort-Object Age -Descending | Select-Object -First 20) {
            $message = "  ⚠️ $($driver.DeviceName)"
            $message += "`n      Manufacturer: $($driver.Manufacturer)"
            $message += "`n      Version: $($driver.DriverVersion) | Date: $($driver.DriverDate) | Age: $($driver.Age)"
            $message += "`n      Class: $($driver.DeviceClass)"
            Write-Log $message -Color "Yellow"
        }
    }
    else {
        Write-Log "No outdated drivers found (all drivers less than 2 years old)" -Color "Green"
    }
    
    # Check Windows Update
    Write-Host "`n--- Windows Update Driver Check ---" -ForegroundColor Yellow
    $updateCount = Get-WindowsUpdateDrivers
    
    # Recommendations
    Write-Host "`n--- Recommendations ---" -ForegroundColor Cyan
    Write-Log "1. Update critical drivers: Graphics (GPU), Network, Chipset" -Color "Cyan"
    Write-Log "2. Visit manufacturer websites for latest drivers:" -Color "Cyan"
    Write-Log "   - NVIDIA: https://www.nvidia.com/drivers" -Color "Gray"
    Write-Log "   - AMD: https://www.amd.com/support" -Color "Gray"
    Write-Log "   - Intel: https://www.intel.com/content/www/us/en/download-center/home.html" -Color "Gray"
    Write-Log "3. Run Windows Update regularly" -Color "Cyan"
    Write-Log "4. Use Device Manager to update individual drivers" -Color "Cyan"
    
    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

# Main execution
Write-Host "=== Driver Update Checker ===" -ForegroundColor Cyan
Write-Host "Log Path: $LogPath" -ForegroundColor Yellow
Write-Host ""

Write-Log "Driver Update Check Script Started"

if ($CheckOnStartup) {
    Show-DriverReport
}

Write-Host "`nDriver check complete. Check the log file for details: $LogPath" -ForegroundColor Green
Write-Host "To run this check again, execute this script.`n" -ForegroundColor Yellow
