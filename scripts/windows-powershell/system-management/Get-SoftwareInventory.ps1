<#
.SYNOPSIS
    Generates comprehensive software inventory reports for Windows systems.

.DESCRIPTION
    Scans installed software on local or remote computers.
    Retrieves information from registry (32-bit and 64-bit) and Windows Installer.
    Generates detailed reports for asset management, licensing, and compliance.

.PARAMETER ComputerName
    Computer name(s) to inventory. Defaults to local computer.

.PARAMETER IncludeUpdates
    Include Windows updates and hotfixes in the inventory.

.PARAMETER FilterPublisher
    Filter results by publisher name (supports wildcards).

.PARAMETER FilterName
    Filter results by software name (supports wildcards).

.PARAMETER ExcludeSystemComponents
    Exclude system components and updates from results.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER CSVPath
    Path for CSV export. Default: C:\Reports\SoftwareInventory.csv

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER HTMLPath
    Path for HTML report. Default: C:\Reports\SoftwareInventory.html

.PARAMETER GroupByPublisher
    Group results by publisher/vendor.

.PARAMETER ShowStatistics
    Display detailed statistics about installed software.

.EXAMPLE
    .\Get-SoftwareInventory.ps1
    Generates software inventory for local computer.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -ComputerName SERVER01,SERVER02 -ExportCSV
    Inventories multiple servers and exports to CSV.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -FilterPublisher "Microsoft*" -GroupByPublisher
    Shows all Microsoft software grouped by product.

.EXAMPLE
    .\Get-SoftwareInventory.ps1 -ExcludeSystemComponents -ShowStatistics -ExportHTML
    Full inventory excluding system components with statistics.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights for remote computers
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [switch]$IncludeUpdates,

    [string]$FilterPublisher,

    [string]$FilterName,

    [switch]$ExcludeSystemComponents,

    [switch]$ExportCSV,

    [string]$CSVPath = "C:\Reports\SoftwareInventory.csv",

    [switch]$ExportHTML,

    [string]$HTMLPath = "C:\Reports\SoftwareInventory.html",

    [switch]$GroupByPublisher,

    [switch]$ShowStatistics
)

$allSoftware = @()

Write-Host "=== Software Inventory ===" -ForegroundColor Cyan
Write-Host ""

foreach ($computer in $ComputerName) {
    Write-Host "Inventorying $computer..." -ForegroundColor Yellow

    try {
        # Test connectivity
        if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
            Write-Host "  WARNING: Unable to reach $computer" -ForegroundColor Yellow
            continue
        }

        # Registry paths to check
        $uninstallPaths = @(
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
            'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
        )

        $software = @()

        foreach ($path in $uninstallPaths) {
            try {
                # Open remote registry
                $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
                $regKey = $reg.OpenSubKey($path)

                if ($regKey) {
                    $subKeys = $regKey.GetSubKeyNames()

                    Write-Host "  Scanning $path ($($subKeys.Count) entries)..." -ForegroundColor Gray

                    foreach ($subKey in $subKeys) {
                        try {
                            $appKey = $reg.OpenSubKey("$path\$subKey")

                            $displayName = $appKey.GetValue('DisplayName')

                            # Skip if no display name
                            if (-not $displayName) {
                                continue
                            }

                            # Check if system component
                            $systemComponent = $appKey.GetValue('SystemComponent')
                            if ($ExcludeSystemComponents -and $systemComponent -eq 1) {
                                continue
                            }

                            # Check if Windows Update
                            $isUpdate = $displayName -like "*Update*" -or $displayName -like "*Hotfix*" -or $displayName -like "KB*"
                            if (-not $IncludeUpdates -and $isUpdate) {
                                continue
                            }

                            # Get software details
                            $publisher = $appKey.GetValue('Publisher')
                            $version = $appKey.GetValue('DisplayVersion')
                            $installDate = $appKey.GetValue('InstallDate')
                            $installLocation = $appKey.GetValue('InstallLocation')
                            $uninstallString = $appKey.GetValue('UninstallString')
                            $estimatedSize = $appKey.GetValue('EstimatedSize')

                            # Parse install date
                            $parsedDate = $null
                            if ($installDate) {
                                try {
                                    if ($installDate -match '^\d{8}$') {
                                        $parsedDate = [DateTime]::ParseExact($installDate, 'yyyyMMdd', $null)
                                    }
                                }
                                catch {
                                    $parsedDate = $null
                                }
                            }

                            # Apply filters
                            if ($FilterPublisher -and $publisher -notlike $FilterPublisher) {
                                continue
                            }

                            if ($FilterName -and $displayName -notlike $FilterName) {
                                continue
                            }

                            # Convert size to MB
                            $sizeMB = if ($estimatedSize) {
                                [math]::Round($estimatedSize / 1024, 2)
                            } else { $null }

                            # Determine architecture
                            $architecture = if ($path -like "*WOW6432Node*") { "32-bit" } else { "64-bit" }

                            # Create software object
                            $softwareItem = [PSCustomObject]@{
                                ComputerName = $computer
                                DisplayName = $displayName
                                Publisher = $publisher
                                Version = $version
                                InstallDate = $parsedDate
                                InstallLocation = $installLocation
                                SizeMB = $sizeMB
                                Architecture = $architecture
                                UninstallString = $uninstallString
                                RegistryKey = $subKey
                            }

                            $software += $softwareItem

                            $appKey.Close()
                        }
                        catch {
                            # Skip entries that can't be read
                            continue
                        }
                    }

                    $regKey.Close()
                }
            }
            catch {
                Write-Host "  Error accessing registry path $path`: $_" -ForegroundColor Red
            }
        }

        $reg.Close()

        Write-Host "  Found $($software.Count) software package(s)" -ForegroundColor Green

        $allSoftware += $software
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
}

if ($allSoftware.Count -eq 0) {
    Write-Host "`nNo software found matching criteria." -ForegroundColor Yellow
    return
}

# Display summary statistics
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Software Packages: $($allSoftware.Count)" -ForegroundColor White

$uniquePublishers = ($allSoftware | Where-Object { $_.Publisher } | Select-Object -Unique Publisher).Count
$uniqueSoftware = ($allSoftware | Select-Object -Unique DisplayName).Count

Write-Host "Unique Software Titles: $uniqueSoftware" -ForegroundColor White
Write-Host "Unique Publishers: $uniquePublishers" -ForegroundColor White

# Show architecture breakdown
$arch64 = ($allSoftware | Where-Object { $_.Architecture -eq "64-bit" }).Count
$arch32 = ($allSoftware | Where-Object { $_.Architecture -eq "32-bit" }).Count

Write-Host "64-bit: $arch64 | 32-bit: $arch32" -ForegroundColor Gray

if ($ShowStatistics) {
    Write-Host "`n=== DETAILED STATISTICS ===" -ForegroundColor Cyan

    # Top publishers
    Write-Host "`nTop 10 Publishers by Software Count:" -ForegroundColor Yellow
    $topPublishers = $allSoftware |
        Where-Object { $_.Publisher } |
        Group-Object Publisher |
        Sort-Object Count -Descending |
        Select-Object -First 10

    foreach ($pub in $topPublishers) {
        Write-Host "  $($pub.Name): $($pub.Count) package(s)" -ForegroundColor White
    }

    # Installation timeline (if dates available)
    $withDates = $allSoftware | Where-Object { $_.InstallDate }

    if ($withDates) {
        Write-Host "`nRecent Installations (Last 30 days):" -ForegroundColor Yellow
        $recentInstalls = $withDates |
            Where-Object { $_.InstallDate -ge (Get-Date).AddDays(-30) } |
            Sort-Object InstallDate -Descending |
            Select-Object -First 10

        if ($recentInstalls) {
            $recentInstalls | Format-Table InstallDate, DisplayName, Publisher -AutoSize
        }
        else {
            Write-Host "  No installations in the last 30 days" -ForegroundColor Gray
        }
    }

    # Largest software
    $withSize = $allSoftware | Where-Object { $_.SizeMB -gt 0 }

    if ($withSize) {
        Write-Host "`nLargest Software Packages:" -ForegroundColor Yellow
        $withSize |
            Sort-Object SizeMB -Descending |
            Select-Object -First 10 |
            Format-Table DisplayName, Publisher, SizeMB -AutoSize
    }
}

# Group by publisher if requested
if ($GroupByPublisher) {
    Write-Host "`n=== SOFTWARE BY PUBLISHER ===" -ForegroundColor Cyan

    $grouped = $allSoftware |
        Where-Object { $_.Publisher } |
        Group-Object Publisher |
        Sort-Object Name

    foreach ($group in $grouped) {
        Write-Host "`n$($group.Name) ($($group.Count) packages):" -ForegroundColor Yellow

        $group.Group |
            Sort-Object DisplayName |
            Select-Object DisplayName, Version, Architecture |
            Format-Table -AutoSize
    }
}

# Show sample of all software
Write-Host "`n=== SOFTWARE INVENTORY (Sample - First 25) ===" -ForegroundColor Cyan
$allSoftware |
    Sort-Object ComputerName, DisplayName |
    Select-Object -First 25 |
    Format-Table ComputerName, DisplayName, Publisher, Version, Architecture -AutoSize

if ($allSoftware.Count -gt 25) {
    Write-Host "... and $($allSoftware.Count - 25) more entries" -ForegroundColor Gray
    Write-Host "Use -ExportCSV or -ExportHTML to see all results" -ForegroundColor Gray
}

# Export to CSV if requested
if ($ExportCSV) {
    $csvDir = Split-Path -Path $CSVPath -Parent
    if ($csvDir -and -not (Test-Path $csvDir)) {
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
    }

    $allSoftware | Export-Csv -Path $CSVPath -NoTypeInformation -Force
    Write-Host "`nResults exported to CSV: $CSVPath" -ForegroundColor Green
}

# Export to HTML if requested
if ($ExportHTML) {
    $htmlDir = Split-Path -Path $HTMLPath -Parent
    if ($htmlDir -and -not (Test-Path $htmlDir)) {
        New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
    }

    # Create publisher summary for HTML
    $publisherSummary = $allSoftware |
        Where-Object { $_.Publisher } |
        Group-Object Publisher |
        Sort-Object Count -Descending |
        Select-Object -First 20 |
        ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.Count)</td></tr>"
        }

    $publisherTable = @"
<h2>Top 20 Publishers</h2>
<table>
<tr><th>Publisher</th><th>Package Count</th></tr>
$($publisherSummary -join "`n")
</table>
"@

    $htmlHeader = @"
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1 { color: #333; }
    h2 { color: #666; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; font-size: 12px; }
    th { background-color: #4CAF50; color: white; padding: 8px; text-align: left; position: sticky; top: 0; }
    td { border: 1px solid #ddd; padding: 6px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .summary { background-color: #f5f5f5; padding: 15px; border-left: 4px solid #4CAF50; margin-bottom: 20px; }
    .arch64 { background-color: #e3f2fd; }
    .arch32 { background-color: #fff3e0; }
</style>
<h1>Software Inventory Report</h1>
<p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Computers:</strong> $($ComputerName -join ', ')</p>

<div class="summary">
<h2>Summary</h2>
<p><strong>Total Packages:</strong> $($allSoftware.Count)</p>
<p><strong>Unique Software:</strong> $uniqueSoftware</p>
<p><strong>Unique Publishers:</strong> $uniquePublishers</p>
<p><strong>64-bit:</strong> $arch64 | <strong>32-bit:</strong> $arch32</p>
</div>

$publisherTable

<h2>Complete Software Inventory</h2>
"@

    $htmlBody = $allSoftware |
        Sort-Object ComputerName, DisplayName |
        Select-Object ComputerName, DisplayName, Publisher, Version, InstallDate, Architecture, SizeMB |
        ConvertTo-Html -Fragment

    $htmlFull = $htmlHeader + $htmlBody + "</body></html>"
    $htmlFull | Out-File -FilePath $HTMLPath -Encoding UTF8

    Write-Host "Results exported to HTML: $HTMLPath" -ForegroundColor Green
}

return $allSoftware
