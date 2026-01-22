<#
.SYNOPSIS
    Checks Windows Update status including pending updates and reboot requirements.

.DESCRIPTION
    Queries Windows Update status on local or remote computers.
    Reports pending updates, last installation date, reboot requirements, and update history.
    Supports multiple computers and generates detailed reports.

.PARAMETER ComputerName
    Computer name(s) to check. Defaults to local computer.

.PARAMETER IncludeHistory
    Include update installation history in the report.

.PARAMETER HistoryDays
    Number of days of update history to retrieve. Default: 30

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER CSVPath
    Path for CSV export. Default: C:\Reports\WindowsUpdateStatus.csv

.PARAMETER CheckPendingOnly
    Only check for pending updates, skip history.

.EXAMPLE
    .\Get-WindowsUpdateStatus.ps1
    Checks Windows Update status on local computer.

.EXAMPLE
    .\Get-WindowsUpdateStatus.ps1 -ComputerName SERVER01,SERVER02 -IncludeHistory
    Checks update status on multiple servers with history.

.EXAMPLE
    .\Get-WindowsUpdateStatus.ps1 -ComputerName SERVER01 -ExportCSV -CSVPath C:\Reports\Updates.csv
    Checks update status and exports to CSV.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights for remote computers
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [switch]$IncludeHistory,

    [int]$HistoryDays = 30,

    [switch]$ExportCSV,

    [string]$CSVPath = "C:\Reports\WindowsUpdateStatus.csv",

    [switch]$CheckPendingOnly
)

$results = @()

# Function to check if reboot is pending
function Test-PendingReboot {
    param([string]$Computer)

    try {
        $rebootPending = $false
        $reasons = @()

        # Check Component Based Servicing
        $cbs = Invoke-Command -ComputerName $Computer -ScriptBlock {
            Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
        } -ErrorAction SilentlyContinue

        if ($cbs) {
            $rebootPending = $true
            $reasons += "Component Based Servicing"
        }

        # Check Windows Update
        $wuReboot = Invoke-Command -ComputerName $Computer -ScriptBlock {
            Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
        } -ErrorAction SilentlyContinue

        if ($wuReboot) {
            $rebootPending = $true
            $reasons += "Windows Update"
        }

        # Check pending file rename operations
        $fileRename = Invoke-Command -ComputerName $Computer -ScriptBlock {
            Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        } -ErrorAction SilentlyContinue

        if ($fileRename) {
            $rebootPending = $true
            $reasons += "Pending File Rename"
        }

        return @{
            IsPending = $rebootPending
            Reasons = $reasons -join ", "
        }
    }
    catch {
        return @{
            IsPending = "Unknown"
            Reasons = "Error checking: $_"
        }
    }
}

Write-Host "=== Windows Update Status Check ===" -ForegroundColor Cyan
Write-Host ""

foreach ($computer in $ComputerName) {
    Write-Host "Checking $computer..." -ForegroundColor Yellow

    try {
        # Create update session
        $updateSession = Invoke-Command -ComputerName $computer -ScriptBlock {
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()

                # Search for updates
                $searchResult = $searcher.Search("IsInstalled=0")

                $pendingUpdates = @()
                foreach ($update in $searchResult.Updates) {
                    $pendingUpdates += [PSCustomObject]@{
                        Title = $update.Title
                        IsDownloaded = $update.IsDownloaded
                        IsMandatory = $update.IsMandatory
                        SizeInMB = [math]::Round($update.MaxDownloadSize / 1MB, 2)
                    }
                }

                return @{
                    PendingCount = $searchResult.Updates.Count
                    PendingUpdates = $pendingUpdates
                    Success = $true
                }
            }
            catch {
                return @{
                    PendingCount = -1
                    PendingUpdates = @()
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        } -ErrorAction Stop

        # Get last update installation time
        $lastUpdate = Invoke-Command -ComputerName $computer -ScriptBlock {
            try {
                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $historyCount = $searcher.GetTotalHistoryCount()

                if ($historyCount -gt 0) {
                    $history = $searcher.QueryHistory(0, 1)
                    return $history[0].Date
                }
                return $null
            }
            catch {
                return $null
            }
        } -ErrorAction SilentlyContinue

        # Check reboot status
        $rebootStatus = Test-PendingReboot -Computer $computer

        # Get Windows Update service status
        $wuServiceStatus = Get-Service -ComputerName $computer -Name wuauserv -ErrorAction SilentlyContinue

        # Create result object
        $result = [PSCustomObject]@{
            ComputerName = $computer
            PendingUpdateCount = $updateSession.PendingCount
            LastUpdateInstalled = $lastUpdate
            RebootRequired = $rebootStatus.IsPending
            RebootReason = $rebootStatus.Reasons
            UpdateServiceStatus = $wuServiceStatus.Status
            UpdateServiceStartType = $wuServiceStatus.StartType
            CheckDate = Get-Date
            Status = if ($updateSession.Success) { "Success" } else { "Error" }
            ErrorMessage = $updateSession.Error
        }

        $results += $result

        # Display summary
        Write-Host "  Pending Updates: " -NoNewline
        if ($result.PendingUpdateCount -eq 0) {
            Write-Host $result.PendingUpdateCount -ForegroundColor Green
        }
        elseif ($result.PendingUpdateCount -gt 0) {
            Write-Host $result.PendingUpdateCount -ForegroundColor Yellow
        }
        else {
            Write-Host "Error" -ForegroundColor Red
        }

        Write-Host "  Last Update: " -NoNewline
        if ($lastUpdate) {
            Write-Host $lastUpdate -ForegroundColor Green
        }
        else {
            Write-Host "Unknown" -ForegroundColor Gray
        }

        Write-Host "  Reboot Required: " -NoNewline
        if ($result.RebootRequired -eq $true) {
            Write-Host "YES ($($result.RebootReason))" -ForegroundColor Red
        }
        elseif ($result.RebootRequired -eq $false) {
            Write-Host "NO" -ForegroundColor Green
        }
        else {
            Write-Host "Unknown" -ForegroundColor Gray
        }

        Write-Host "  Update Service: " -NoNewline
        if ($wuServiceStatus.Status -eq "Running") {
            Write-Host $wuServiceStatus.Status -ForegroundColor Green
        }
        else {
            Write-Host $wuServiceStatus.Status -ForegroundColor Red
        }

        # Show pending update details if requested
        if ($updateSession.PendingCount -gt 0 -and $updateSession.PendingUpdates) {
            Write-Host "`n  Pending Updates:" -ForegroundColor Cyan
            foreach ($update in $updateSession.PendingUpdates) {
                $downloadStatus = if ($update.IsDownloaded) { "[Downloaded]" } else { "[Not Downloaded]" }
                $mandatory = if ($update.IsMandatory) { "[MANDATORY]" } else { "" }
                Write-Host "    - $($update.Title) $downloadStatus $mandatory" -ForegroundColor Gray
                Write-Host "      Size: $($update.SizeInMB) MB" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
        Write-Host ""

        $result = [PSCustomObject]@{
            ComputerName = $computer
            PendingUpdateCount = -1
            LastUpdateInstalled = $null
            RebootRequired = "Unknown"
            RebootReason = ""
            UpdateServiceStatus = "Unknown"
            UpdateServiceStartType = "Unknown"
            CheckDate = Get-Date
            Status = "Error"
            ErrorMessage = $_.Exception.Message
        }

        $results += $result
    }
}

# Display summary table
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
$results | Format-Table ComputerName, PendingUpdateCount, LastUpdateInstalled, RebootRequired, UpdateServiceStatus, Status -AutoSize

# Export to CSV if requested
if ($ExportCSV) {
    $csvDir = Split-Path -Path $CSVPath -Parent
    if ($csvDir -and -not (Test-Path $csvDir)) {
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
    }

    $results | Export-Csv -Path $CSVPath -NoTypeInformation -Force
    Write-Host "Results exported to: $CSVPath" -ForegroundColor Green
}

# Get update history if requested
if ($IncludeHistory -and -not $CheckPendingOnly) {
    Write-Host "`n=== UPDATE HISTORY (Last $HistoryDays days) ===" -ForegroundColor Cyan

    foreach ($computer in $ComputerName) {
        Write-Host "`n$computer`:" -ForegroundColor Yellow

        try {
            $history = Invoke-Command -ComputerName $computer -ScriptBlock {
                param($Days)

                $session = New-Object -ComObject Microsoft.Update.Session
                $searcher = $session.CreateUpdateSearcher()
                $historyCount = $searcher.GetTotalHistoryCount()

                $cutoffDate = (Get-Date).AddDays(-$Days)
                $recentHistory = @()

                if ($historyCount -gt 0) {
                    $allHistory = $searcher.QueryHistory(0, $historyCount)

                    foreach ($item in $allHistory) {
                        if ($item.Date -ge $cutoffDate) {
                            $recentHistory += [PSCustomObject]@{
                                Date = $item.Date
                                Title = $item.Title
                                Operation = switch ($item.Operation) {
                                    1 { "Installation" }
                                    2 { "Uninstallation" }
                                    3 { "Other" }
                                    default { "Unknown" }
                                }
                                Status = switch ($item.ResultCode) {
                                    0 { "Not Started" }
                                    1 { "In Progress" }
                                    2 { "Succeeded" }
                                    3 { "Succeeded With Errors" }
                                    4 { "Failed" }
                                    5 { "Aborted" }
                                    default { "Unknown" }
                                }
                            }
                        }
                    }
                }

                return $recentHistory
            } -ArgumentList $HistoryDays -ErrorAction Stop

            if ($history) {
                $history | Sort-Object Date -Descending | Format-Table Date, Operation, Status, Title -AutoSize
            }
            else {
                Write-Host "  No update history found for the specified period." -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "  Error retrieving history: $_" -ForegroundColor Red
        }
    }
}

return $results
