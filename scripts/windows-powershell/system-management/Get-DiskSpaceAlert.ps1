<#
.SYNOPSIS
    Monitors disk space across local or remote systems and generates alerts.

.DESCRIPTION
    Scans all local disks or specified remote computers for disk space usage.
    Generates alerts when free space falls below specified thresholds.
    Supports email notifications, log file output, and HTML reports.

.PARAMETER ComputerName
    Computer name(s) to check. Defaults to local computer.

.PARAMETER WarningThreshold
    Warning threshold percentage for free space. Default: 20%

.PARAMETER CriticalThreshold
    Critical threshold percentage for free space. Default: 10%

.PARAMETER SendEmail
    Send email alerts when thresholds are exceeded.

.PARAMETER EmailTo
    Email recipient address(es).

.PARAMETER EmailFrom
    Email sender address.

.PARAMETER SmtpServer
    SMTP server for sending email alerts.

.PARAMETER LogPath
    Path to log file. Default: C:\Logs\DiskSpaceMonitor.log

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER HTMLPath
    Path for HTML report. Default: C:\Reports\DiskSpace.html

.EXAMPLE
    .\Get-DiskSpaceAlert.ps1
    Checks disk space on local computer with default thresholds.

.EXAMPLE
    .\Get-DiskSpaceAlert.ps1 -ComputerName SERVER01,SERVER02 -CriticalThreshold 5
    Checks disk space on multiple servers with 5% critical threshold.

.EXAMPLE
    .\Get-DiskSpaceAlert.ps1 -SendEmail -EmailTo admin@company.com -EmailFrom alerts@company.com -SmtpServer mail.company.com
    Checks disk space and sends email alerts.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights for remote computers
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [ValidateRange(1,99)]
    [int]$WarningThreshold = 20,

    [ValidateRange(1,99)]
    [int]$CriticalThreshold = 10,

    [switch]$SendEmail,

    [string[]]$EmailTo,

    [string]$EmailFrom,

    [string]$SmtpServer,

    [string]$LogPath = "C:\Logs\DiskSpaceMonitor.log",

    [switch]$ExportHTML,

    [string]$HTMLPath = "C:\Reports\DiskSpace.html"
)

# Initialize results array
$results = @()
$alertCount = 0

# Function to write log entries
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Create log directory if it doesn't exist
    $logDir = Split-Path -Path $LogPath -Parent
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    # Write to log file
    Add-Content -Path $LogPath -Value $logMessage

    # Also write to console with color
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN"  { Write-Host $logMessage -ForegroundColor Yellow }
        "CRITICAL" { Write-Host $logMessage -ForegroundColor Magenta }
        default { Write-Host $logMessage }
    }
}

# Start monitoring
Write-Log "Starting disk space monitoring..."

foreach ($computer in $ComputerName) {
    Write-Log "Checking $computer..."

    try {
        # Get disk information
        $disks = Get-WmiObject Win32_LogicalDisk -ComputerName $computer -Filter "DriveType=3" -ErrorAction Stop

        foreach ($disk in $disks) {
            $totalSpace = [math]::Round($disk.Size / 1GB, 2)
            $freeSpace = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedSpace = $totalSpace - $freeSpace
            $percentFree = [math]::Round(($freeSpace / $totalSpace) * 100, 2)

            # Determine status
            $status = "OK"
            $level = "INFO"

            if ($percentFree -le $CriticalThreshold) {
                $status = "CRITICAL"
                $level = "CRITICAL"
                $alertCount++
            }
            elseif ($percentFree -le $WarningThreshold) {
                $status = "WARNING"
                $level = "WARN"
                $alertCount++
            }

            # Create result object
            $result = [PSCustomObject]@{
                Computer = $computer
                Drive = $disk.DeviceID
                Label = $disk.VolumeName
                TotalGB = $totalSpace
                UsedGB = $usedSpace
                FreeGB = $freeSpace
                PercentFree = $percentFree
                Status = $status
                Timestamp = Get-Date
            }

            $results += $result

            # Log the result
            $logMsg = "$computer - Drive $($disk.DeviceID): $percentFree% free ($freeSpace GB / $totalSpace GB) - $status"
            Write-Log -Message $logMsg -Level $level
        }
    }
    catch {
        Write-Log "ERROR checking $computer`: $_" -Level "ERROR"
    }
}

# Display results summary
Write-Host "`n=== DISK SPACE SUMMARY ===" -ForegroundColor Cyan
$results | Format-Table Computer, Drive, TotalGB, FreeGB, PercentFree, Status -AutoSize

# Export to HTML if requested
if ($ExportHTML) {
    Write-Log "Generating HTML report..."

    $htmlDir = Split-Path -Path $HTMLPath -Parent
    if ($htmlDir -and -not (Test-Path $htmlDir)) {
        New-Item -ItemType Directory -Path $htmlDir -Force | Out-Null
    }

    $htmlHeader = @"
<style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1 { color: #333; }
    table { border-collapse: collapse; width: 100%; }
    th { background-color: #4CAF50; color: white; padding: 10px; text-align: left; }
    td { border: 1px solid #ddd; padding: 8px; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .critical { background-color: #f44336; color: white; }
    .warning { background-color: #ff9800; color: white; }
    .ok { background-color: #4CAF50; color: white; }
</style>
<h1>Disk Space Report</h1>
<p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
"@

    $results | ConvertTo-Html -Head $htmlHeader -Property Computer, Drive, Label, TotalGB, FreeGB, PercentFree, Status |
        Out-File -FilePath $HTMLPath -Encoding UTF8

    Write-Log "HTML report saved to $HTMLPath"
}

# Send email alert if requested and alerts exist
if ($SendEmail -and $alertCount -gt 0) {
    if (-not $EmailTo -or -not $EmailFrom -or -not $SmtpServer) {
        Write-Log "Email parameters missing. Skipping email notification." -Level "WARN"
    }
    else {
        Write-Log "Sending email alert..."

        $alertDisks = $results | Where-Object { $_.Status -ne "OK" }

        $emailBody = @"
<html>
<body>
<h2>Disk Space Alert</h2>
<p><strong>$alertCount disk(s) require attention</strong></p>
<table border='1' style='border-collapse: collapse;'>
<tr style='background-color: #4CAF50; color: white;'>
    <th>Computer</th>
    <th>Drive</th>
    <th>Free Space</th>
    <th>Percent Free</th>
    <th>Status</th>
</tr>
"@

        foreach ($disk in $alertDisks) {
            $rowColor = if ($disk.Status -eq "CRITICAL") { "#f44336" } else { "#ff9800" }
            $emailBody += @"
<tr style='background-color: $rowColor; color: white;'>
    <td>$($disk.Computer)</td>
    <td>$($disk.Drive)</td>
    <td>$($disk.FreeGB) GB</td>
    <td>$($disk.PercentFree)%</td>
    <td>$($disk.Status)</td>
</tr>
"@
        }

        $emailBody += @"
</table>
</body>
</html>
"@

        try {
            Send-MailMessage -To $EmailTo -From $EmailFrom -Subject "Disk Space Alert: $alertCount disk(s) need attention" `
                -Body $emailBody -BodyAsHtml -SmtpServer $SmtpServer -ErrorAction Stop
            Write-Log "Email alert sent successfully"
        }
        catch {
            Write-Log "Failed to send email: $_" -Level "ERROR"
        }
    }
}

Write-Log "Disk space monitoring complete. Total alerts: $alertCount"

# Return results object
return $results
