<#
.SYNOPSIS
    Analyzes Windows Event Logs for critical errors, warnings, and security events.

.DESCRIPTION
    Scans Windows Event Logs on local or remote computers for important events.
    Filters by severity, event ID, time range, and source.
    Generates reports for troubleshooting and security auditing.

.PARAMETER ComputerName
    Computer name(s) to analyze. Defaults to local computer.

.PARAMETER LogName
    Event log name(s) to analyze. Default: Application, System, Security

.PARAMETER Level
    Event level to filter. Options: Error, Warning, Information, Critical
    Default: Error, Warning, Critical

.PARAMETER Hours
    Number of hours to look back. Default: 24

.PARAMETER EventID
    Specific event ID(s) to search for.

.PARAMETER Source
    Event source/provider name to filter.

.PARAMETER MaxEvents
    Maximum number of events to retrieve per log. Default: 1000

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER HTMLPath
    Path for HTML report. Default: C:\Reports\EventLogAnalysis.html

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER CSVPath
    Path for CSV export. Default: C:\Reports\EventLogAnalysis.csv

.PARAMETER GroupBySource
    Group results by event source.

.PARAMETER TopErrors
    Show top N most common errors. Default: 10

.EXAMPLE
    .\Get-EventLogAnalysis.ps1
    Analyzes Application and System logs for errors in last 24 hours.

.EXAMPLE
    .\Get-EventLogAnalysis.ps1 -ComputerName SERVER01 -LogName System -Hours 48 -Level Error,Critical
    Analyzes System log on SERVER01 for errors in last 48 hours.

.EXAMPLE
    .\Get-EventLogAnalysis.ps1 -LogName Security -EventID 4625,4624 -Hours 12
    Analyzes failed and successful logon events in last 12 hours.

.EXAMPLE
    .\Get-EventLogAnalysis.ps1 -GroupBySource -TopErrors 20 -ExportHTML
    Groups errors by source, shows top 20, exports to HTML.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights for Security log
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [string[]]$LogName = @("Application", "System"),

    [ValidateSet("Error", "Warning", "Information", "Critical", "Verbose")]
    [string[]]$Level = @("Error", "Warning", "Critical"),

    [int]$Hours = 24,

    [int[]]$EventID,

    [string]$Source,

    [int]$MaxEvents = 1000,

    [switch]$ExportHTML,

    [string]$HTMLPath = "C:\Reports\EventLogAnalysis.html",

    [switch]$ExportCSV,

    [string]$CSVPath = "C:\Reports\EventLogAnalysis.csv",

    [switch]$GroupBySource,

    [int]$TopErrors = 10
)

$allEvents = @()
$startTime = (Get-Date).AddHours(-$Hours)

Write-Host "=== Event Log Analysis ===" -ForegroundColor Cyan
Write-Host "Time Range: $startTime to $(Get-Date)" -ForegroundColor Gray
Write-Host "Severity Levels: $($Level -join ', ')" -ForegroundColor Gray
Write-Host ""

foreach ($computer in $ComputerName) {
    Write-Host "Analyzing $computer..." -ForegroundColor Yellow

    foreach ($log in $LogName) {
        Write-Host "  Checking $log log..." -ForegroundColor Gray

        try {
            # Build filter hashtable
            $filterHash = @{
                LogName = $log
                StartTime = $startTime
            }

            if ($EventID) {
                $filterHash['ID'] = $EventID
            }

            # Map level names to integers
            $levelValues = @()
            foreach ($lvl in $Level) {
                switch ($lvl) {
                    "Critical" { $levelValues += 1 }
                    "Error" { $levelValues += 2 }
                    "Warning" { $levelValues += 3 }
                    "Information" { $levelValues += 4 }
                    "Verbose" { $levelValues += 5 }
                }
            }

            if ($levelValues.Count -gt 0) {
                $filterHash['Level'] = $levelValues
            }

            # Get events
            $events = Get-WinEvent -ComputerName $computer -FilterHashtable $filterHash -MaxEvents $MaxEvents -ErrorAction Stop

            # Apply additional filtering
            if ($Source) {
                $events = $events | Where-Object { $_.ProviderName -like "*$Source*" }
            }

            Write-Host "    Found $($events.Count) events" -ForegroundColor Green

            # Process events
            foreach ($event in $events) {
                $eventObject = [PSCustomObject]@{
                    Computer = $computer
                    LogName = $event.LogName
                    TimeCreated = $event.TimeCreated
                    Level = $event.LevelDisplayName
                    EventID = $event.Id
                    Source = $event.ProviderName
                    Message = $event.Message
                    User = if ($event.UserId) { $event.UserId.Value } else { "N/A" }
                    RecordId = $event.RecordId
                }

                $allEvents += $eventObject
            }
        }
        catch {
            if ($_.Exception.Message -like "*No events were found*") {
                Write-Host "    No events found matching criteria" -ForegroundColor Gray
            }
            else {
                Write-Host "    ERROR: $_" -ForegroundColor Red
            }
        }
    }
}

Write-Host ""

if ($allEvents.Count -eq 0) {
    Write-Host "No events found matching the specified criteria." -ForegroundColor Yellow
    return
}

# Display summary statistics
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Events Found: $($allEvents.Count)" -ForegroundColor White

$criticalCount = ($allEvents | Where-Object { $_.Level -eq "Critical" }).Count
$errorCount = ($allEvents | Where-Object { $_.Level -eq "Error" }).Count
$warningCount = ($allEvents | Where-Object { $_.Level -eq "Warning" }).Count

Write-Host "  Critical: $criticalCount" -ForegroundColor Magenta
Write-Host "  Errors: $errorCount" -ForegroundColor Red
Write-Host "  Warnings: $warningCount" -ForegroundColor Yellow
Write-Host ""

# Group by source if requested
if ($GroupBySource) {
    Write-Host "=== EVENTS BY SOURCE ===" -ForegroundColor Cyan

    $groupedBySource = $allEvents | Group-Object Source | Sort-Object Count -Descending | Select-Object -First $TopErrors

    foreach ($group in $groupedBySource) {
        Write-Host "  $($group.Name): $($group.Count) events" -ForegroundColor White

        # Show breakdown by level
        $levels = $group.Group | Group-Object Level
        foreach ($lvl in $levels) {
            $color = switch ($lvl.Name) {
                "Critical" { "Magenta" }
                "Error" { "Red" }
                "Warning" { "Yellow" }
                default { "Gray" }
            }
            Write-Host "    - $($lvl.Name): $($lvl.Count)" -ForegroundColor $color
        }
    }
    Write-Host ""
}

# Show top errors by Event ID
Write-Host "=== TOP $TopErrors MOST COMMON EVENT IDs ===" -ForegroundColor Cyan

$topEventIDs = $allEvents | Group-Object EventID, Source |
    Sort-Object Count -Descending |
    Select-Object -First $TopErrors

foreach ($eventGroup in $topEventIDs) {
    $firstEvent = $eventGroup.Group[0]
    Write-Host "  Event ID $($firstEvent.EventID) from $($firstEvent.Source): $($eventGroup.Count) occurrences" -ForegroundColor White

    # Show first line of message
    $messagePreview = ($firstEvent.Message -split "`n")[0]
    if ($messagePreview.Length -gt 100) {
        $messagePreview = $messagePreview.Substring(0, 100) + "..."
    }
    Write-Host "    $messagePreview" -ForegroundColor Gray
}
Write-Host ""

# Show recent critical/error events
$criticalErrors = $allEvents | Where-Object { $_.Level -in @("Critical", "Error") } |
    Sort-Object TimeCreated -Descending |
    Select-Object -First 20

if ($criticalErrors) {
    Write-Host "=== RECENT CRITICAL EVENTS & ERRORS ===" -ForegroundColor Cyan
    $criticalErrors | Format-Table TimeCreated, Computer, Level, EventID, Source -AutoSize
}

# Export to CSV if requested
if ($ExportCSV) {
    $csvDir = Split-Path -Path $CSVPath -Parent
    if ($csvDir -and -not (Test-Path $csvDir)) {
        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
    }

    $allEvents | Export-Csv -Path $CSVPath -NoTypeInformation -Force
    Write-Host "Results exported to CSV: $CSVPath" -ForegroundColor Green
}

# Export to HTML if requested
if ($ExportHTML) {
    $htmlDir = Split-Path -Path $HTMLPath -Parent
    if ($htmlDir -and -not (Test-Path $htmlDir)) {
        New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
    }

    $htmlHeader = @"
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1 { color: #333; }
    h2 { color: #666; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
    th { background-color: #4CAF50; color: white; padding: 10px; text-align: left; }
    td { border: 1px solid #ddd; padding: 8px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .critical { background-color: #9c27b0; color: white; font-weight: bold; }
    .error { background-color: #f44336; color: white; }
    .warning { background-color: #ff9800; color: white; }
    .info { background-color: #2196f3; color: white; }
    .summary { background-color: #f5f5f5; padding: 15px; border-left: 4px solid #4CAF50; margin-bottom: 20px; }
</style>
<h1>Event Log Analysis Report</h1>
<p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Time Range:</strong> $startTime to $(Get-Date)</p>
<p><strong>Computers:</strong> $($ComputerName -join ', ')</p>

<div class="summary">
<h2>Summary Statistics</h2>
<p><strong>Total Events:</strong> $($allEvents.Count)</p>
<p><strong>Critical:</strong> $criticalCount | <strong>Errors:</strong> $errorCount | <strong>Warnings:</strong> $warningCount</p>
</div>

<h2>Event Details</h2>
"@

    # Create HTML table with row coloring based on level
    $htmlBody = $allEvents | Sort-Object TimeCreated -Descending |
        Select-Object TimeCreated, Computer, LogName, Level, EventID, Source,
            @{Name='MessagePreview'; Expression={
                $msg = ($_.Message -split "`n")[0]
                if ($msg.Length -gt 150) { $msg.Substring(0, 150) + "..." } else { $msg }
            }} |
        ConvertTo-Html -Fragment

    # Add row classes based on level
    $htmlBody = $htmlBody -replace '<tr><td>([^<]+)</td><td>([^<]+)</td><td>([^<]+)</td><td>Critical</td>', '<tr class="critical"><td>$1</td><td>$2</td><td>$3</td><td>Critical</td>'
    $htmlBody = $htmlBody -replace '<tr><td>([^<]+)</td><td>([^<]+)</td><td>([^<]+)</td><td>Error</td>', '<tr class="error"><td>$1</td><td>$2</td><td>$3</td><td>Error</td>'
    $htmlBody = $htmlBody -replace '<tr><td>([^<]+)</td><td>([^<]+)</td><td>([^<]+)</td><td>Warning</td>', '<tr class="warning"><td>$1</td><td>$2</td><td>$3</td><td>Warning</td>'

    $htmlFull = $htmlHeader + $htmlBody + "</body></html>"
    $htmlFull | Out-File -FilePath $HTMLPath -Encoding UTF8

    Write-Host "Results exported to HTML: $HTMLPath" -ForegroundColor Green
}

return $allEvents
