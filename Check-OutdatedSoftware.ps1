<#
.SYNOPSIS
    Check for outdated software and alert
.DESCRIPTION
    Scans installed software and checks versions against common update sources
.PARAMETER LogPath
    Path to log file (default: .\software_check_log.txt)
.PARAMETER ExportCSV
    Export results to CSV file (default: true)
#>

param(
    [string]$LogPath = ".\software_check_log.txt",
    [bool]$ExportCSV = $true
)

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $LogPath -Value $logEntry
    Write-Host $logEntry -ForegroundColor $Color
}

function Get-InstalledSoftware {
    $software = @()
    
    # Registry paths for installed software
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    
    foreach ($path in $paths) {
        try {
            $apps = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -and $_.DisplayVersion } |
                    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, @{N='Source';E={$path}}
            
            $software += $apps
        }
        catch {
            # Skip if path doesn't exist
        }
    }
    
    # Remove duplicates
    $uniqueSoftware = $software | Sort-Object DisplayName -Unique
    
    return $uniqueSoftware
}

function Get-WinGetUpdates {
    Write-Host "Checking for updates via winget..." -ForegroundColor Cyan
    
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        
        if (-not $wingetPath) {
            Write-Log "winget not found. Install Windows Package Manager for automatic update checking." -Color "Yellow"
            return $null
        }
        
        # Run winget upgrade
        $output = winget upgrade 2>&1
        
        # Parse output for available updates
        $updates = @()
        $lines = $output -split "`n"
        $inList = $false
        
        foreach ($line in $lines) {
            if ($line -match "^-+$") {
                $inList = $true
                continue
            }
            
            if ($inList -and $line.Trim() -and $line -notmatch "upgrades available") {
                # Parse winget output
                $parts = $line -split '\s{2,}'
                if ($parts.Count -ge 3) {
                    $updates += @{
                        Name = $parts[0].Trim()
                        CurrentVersion = $parts[1].Trim()
                        AvailableVersion = $parts[2].Trim()
                    }
                }
            }
        }
        
        return $updates
    }
    catch {
        Write-Log "Error checking winget: $_" -Color "Yellow"
        return $null
    }
}

function Get-CommonSoftwareVersions {
    # Check versions of commonly outdated software
    $commonSoftware = @()
    
    $checks = @(
        @{Name="Google Chrome"; Process="chrome"; RegistryPath="HKLM:\SOFTWARE\Google\Chrome\BLBeacon"},
        @{Name="Mozilla Firefox"; Process="firefox"; RegistryPath="HKLM:\SOFTWARE\Mozilla\Mozilla Firefox"},
        @{Name="Adobe Reader"; Process="AcroRd32"; RegistryPath="HKLM:\SOFTWARE\Adobe\Acrobat Reader"},
        @{Name="Java"; RegistryPath="HKLM:\SOFTWARE\JavaSoft\Java Runtime Environment"},
        @{Name="VLC Media Player"; Process="vlc"; RegistryPath="HKLM:\SOFTWARE\VideoLAN\VLC"},
        @{Name="7-Zip"; RegistryPath="HKLM:\SOFTWARE\7-Zip"}
    )
    
    foreach ($check in $checks) {
        try {
            if ($check.RegistryPath -and (Test-Path $check.RegistryPath)) {
                $version = (Get-ItemProperty $check.RegistryPath -ErrorAction SilentlyContinue).Version
                if ($version) {
                    $commonSoftware += @{
                        Name = $check.Name
                        Version = $version
                        Found = $true
                    }
                }
            }
        }
        catch {
            # Software not installed
        }
    }
    
    return $commonSoftware
}

function Show-SoftwareReport {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "   SOFTWARE UPDATE CHECK REPORT" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    
    Write-Log "Starting software scan..."
    
    # Get all installed software
    $installedSoftware = Get-InstalledSoftware
    Write-Log "Found $($installedSoftware.Count) installed programs" -Color "Cyan"
    
    # Check winget for updates
    Write-Host "`n--- Available Updates (via winget) ---" -ForegroundColor Yellow
    $wingetUpdates = Get-WinGetUpdates
    
    if ($wingetUpdates -and $wingetUpdates.Count -gt 0) {
        Write-Log "Found $($wingetUpdates.Count) update(s) available:" -Color "Yellow"
        
        foreach ($update in $wingetUpdates) {
            $message = "  🔄 $($update.Name): $($update.CurrentVersion) → $($update.AvailableVersion)"
            Write-Log $message -Color "Yellow"
        }
        
        Write-Host "`nTo update all: winget upgrade --all" -ForegroundColor Cyan
    }
    elseif ($wingetUpdates) {
        Write-Log "All winget-managed software is up to date!" -Color "Green"
    }
    
    # Check common software
    Write-Host "`n--- Common Software Versions ---" -ForegroundColor Yellow
    $commonSoftware = Get-CommonSoftwareVersions
    
    if ($commonSoftware.Count -gt 0) {
        foreach ($soft in $commonSoftware) {
            Write-Log "  ✓ $($soft.Name): v$($soft.Version)" -Color "Cyan"
        }
    }
    
    # Export to CSV
    if ($ExportCSV) {
        $csvPath = ".\installed_software_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $installedSoftware | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Log "Exported software list to: $csvPath" -Color "Green"
    }
    
    # Recommendations
    Write-Host "`n--- Recommendations ---" -ForegroundColor Cyan
    Write-Log "1. Install winget if not available: https://aka.ms/getwinget" -Color "Cyan"
    Write-Log "2. Run 'winget upgrade --all' to update all software" -Color "Cyan"
    Write-Log "3. Check for updates manually for:" -Color "Cyan"
    Write-Log "   - Security software (antivirus, firewall)" -Color "Gray"
    Write-Log "   - Web browsers (Chrome, Firefox, Edge)" -Color "Gray"
    Write-Log "   - Adobe products (Reader, Flash)" -Color "Gray"
    Write-Log "   - Java Runtime Environment" -Color "Gray"
    Write-Log "4. Enable automatic updates where possible" -Color "Cyan"
    Write-Log "5. Uninstall unused software to reduce attack surface" -Color "Cyan"
    
    Write-Host "`n========================================`n" -ForegroundColor Cyan
}

# Main execution
Write-Host "=== Software Update Checker ===" -ForegroundColor Cyan
Write-Host "Log Path: $LogPath" -ForegroundColor Yellow
Write-Host ""

Write-Log "Software Update Check Script Started"

Show-SoftwareReport

Write-Host "`nSoftware check complete. Check the log file for details: $LogPath" -ForegroundColor Green
