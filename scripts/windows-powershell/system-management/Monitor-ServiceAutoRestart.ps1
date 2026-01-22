<#
.SYNOPSIS
    Monitors critical Windows services and automatically restarts them if stopped.

.DESCRIPTION
    Monitors specified Windows services on local or remote computers.
    Automatically attempts to restart services that are stopped when they should be running.
    Logs all actions and optionally sends alerts for service failures.

.PARAMETER ComputerName
    Computer name(s) to monitor. Defaults to local computer.

.PARAMETER ServiceName
    Service name(s) to monitor. Can be display name or service name.

.PARAMETER ServiceList
    Path to text file containing list of services to monitor (one per line).

.PARAMETER AutoRestart
    Automatically restart stopped services. Default: $true

.PARAMETER MaxRestartAttempts
    Maximum number of restart attempts before giving up. Default: 3

.PARAMETER RestartDelay
    Delay in seconds between restart attempts. Default: 30

.PARAMETER LogPath
    Path to log file. Default: C:\Logs\ServiceMonitor.log

.PARAMETER SendEmail
    Send email alerts for service failures.

.PARAMETER EmailTo
    Email recipient address(es).

.PARAMETER EmailFrom
    Email sender address.

.PARAMETER SmtpServer
    SMTP server for sending email alerts.

.PARAMETER ContinuousMonitoring
    Run in continuous monitoring mode (loops indefinitely).

.PARAMETER MonitorInterval
    Interval in seconds between monitoring checks (for continuous mode). Default: 300 (5 minutes)

.EXAMPLE
    .\Monitor-ServiceAutoRestart.ps1 -ServiceName "Spooler","W32Time"
    Monitors Print Spooler and Windows Time services on local computer.

.EXAMPLE
    .\Monitor-ServiceAutoRestart.ps1 -ComputerName SERVER01 -ServiceList C:\services.txt -AutoRestart
    Monitors services from file on remote server with auto-restart.

.EXAMPLE
    .\Monitor-ServiceAutoRestart.ps1 -ServiceName "MSSQLSERVER" -ContinuousMonitoring -MonitorInterval 60
    Continuously monitors SQL Server service every 60 seconds.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [string[]]$ServiceName,

    [string]$ServiceList,

    [bool]$AutoRestart = $true,

    [int]$MaxRestartAttempts = 3,

    [int]$RestartDelay = 30,

    [string]$LogPath = "C:\Logs\ServiceMonitor.log",

    [switch]$SendEmail,

    [string[]]$EmailTo,

    [string]$EmailFrom,

    [string]$SmtpServer,

    [switch]$ContinuousMonitoring,

    [int]$MonitorInterval = 300
)

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
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

# Function to send email alert
function Send-ServiceAlert {
    param(
        [string]$Computer,
        [string]$Service,
        [string]$Action,
        [string]$Result
    )

    if (-not $SendEmail -or -not $EmailTo -or -not $EmailFrom -or -not $SmtpServer) {
        return
    }

    $subject = "Service Alert: $Service on $Computer - $Action"
    $body = @"
<html>
<body>
<h2>Service Monitor Alert</h2>
<p><strong>Computer:</strong> $Computer</p>
<p><strong>Service:</strong> $Service</p>
<p><strong>Action:</strong> $Action</p>
<p><strong>Result:</strong> $Result</p>
<p><strong>Time:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
</body>
</html>
"@

    try {
        Send-MailMessage -To $EmailTo -From $EmailFrom -Subject $subject `
            -Body $body -BodyAsHtml -SmtpServer $SmtpServer -ErrorAction Stop
    }
    catch {
        Write-Log "Failed to send email alert: $_" -Level "ERROR"
    }
}

# Function to monitor and restart services
function Monitor-Services {
    $results = @()

    foreach ($computer in $ComputerName) {
        Write-Log "Checking services on $computer..."

        # Build service list
        $servicesToMonitor = @()

        if ($ServiceName) {
            $servicesToMonitor += $ServiceName
        }

        if ($ServiceList -and (Test-Path $ServiceList)) {
            $servicesToMonitor += Get-Content $ServiceList | Where-Object { $_ -notmatch '^\s*#' -and $_ -ne '' }
        }

        if ($servicesToMonitor.Count -eq 0) {
            Write-Log "No services specified to monitor" -Level "WARN"
            continue
        }

        foreach ($svcName in $servicesToMonitor) {
            try {
                # Get service - try both display name and service name
                $service = Get-Service -ComputerName $computer -DisplayName $svcName -ErrorAction SilentlyContinue
                if (-not $service) {
                    $service = Get-Service -ComputerName $computer -Name $svcName -ErrorAction Stop
                }

                $serviceName = $service.Name
                $displayName = $service.DisplayName
                $status = $service.Status
                $startType = $service.StartType

                Write-Log "  $displayName ($serviceName): $status (StartType: $startType)"

                # Check if service should be running
                $shouldBeRunning = $startType -eq 'Automatic' -or $startType -eq 'AutomaticDelayedStart'

                if ($shouldBeRunning -and $status -ne 'Running') {
                    Write-Log "  Service $displayName is $status but should be Running!" -Level "WARN"

                    if ($AutoRestart) {
                        $restartSuccess = $false
                        $attemptCount = 0

                        while ($attemptCount -lt $MaxRestartAttempts -and -not $restartSuccess) {
                            $attemptCount++
                            Write-Log "  Restart attempt $attemptCount of $MaxRestartAttempts..." -Level "INFO"

                            try {
                                Start-Service -InputObject $service -ErrorAction Stop
                                Start-Sleep -Seconds 5

                                # Refresh service status
                                $service.Refresh()

                                if ($service.Status -eq 'Running') {
                                    Write-Log "  Service $displayName restarted successfully!" -Level "SUCCESS"
                                    $restartSuccess = $true
                                    Send-ServiceAlert -Computer $computer -Service $displayName -Action "Auto-Restart" -Result "Success"
                                }
                                else {
                                    Write-Log "  Service status is $($service.Status) after restart attempt" -Level "WARN"
                                }
                            }
                            catch {
                                Write-Log "  Failed to restart service: $_" -Level "ERROR"
                            }

                            if (-not $restartSuccess -and $attemptCount -lt $MaxRestartAttempts) {
                                Write-Log "  Waiting $RestartDelay seconds before next attempt..." -Level "INFO"
                                Start-Sleep -Seconds $RestartDelay
                            }
                        }

                        if (-not $restartSuccess) {
                            Write-Log "  CRITICAL: Failed to restart $displayName after $MaxRestartAttempts attempts!" -Level "CRITICAL"
                            Send-ServiceAlert -Computer $computer -Service $displayName -Action "Auto-Restart" -Result "Failed after $MaxRestartAttempts attempts"
                        }

                        # Create result object
                        $result = [PSCustomObject]@{
                            Computer = $computer
                            ServiceName = $serviceName
                            DisplayName = $displayName
                            OriginalStatus = $status
                            CurrentStatus = $service.Status
                            StartType = $startType
                            RestartAttempted = $true
                            RestartSuccess = $restartSuccess
                            Attempts = $attemptCount
                            Timestamp = Get-Date
                        }
                    }
                    else {
                        # Not auto-restarting, just report
                        $result = [PSCustomObject]@{
                            Computer = $computer
                            ServiceName = $serviceName
                            DisplayName = $displayName
                            OriginalStatus = $status
                            CurrentStatus = $status
                            StartType = $startType
                            RestartAttempted = $false
                            RestartSuccess = $false
                            Attempts = 0
                            Timestamp = Get-Date
                        }

                        Send-ServiceAlert -Computer $computer -Service $displayName -Action "Status Check" -Result "Stopped (Auto-restart disabled)"
                    }

                    $results += $result
                }
                else {
                    # Service is in expected state
                    $result = [PSCustomObject]@{
                        Computer = $computer
                        ServiceName = $serviceName
                        DisplayName = $displayName
                        OriginalStatus = $status
                        CurrentStatus = $status
                        StartType = $startType
                        RestartAttempted = $false
                        RestartSuccess = $null
                        Attempts = 0
                        Timestamp = Get-Date
                    }

                    $results += $result
                }
            }
            catch {
                Write-Log "  ERROR checking service '$svcName': $_" -Level "ERROR"

                $result = [PSCustomObject]@{
                    Computer = $computer
                    ServiceName = $svcName
                    DisplayName = $svcName
                    OriginalStatus = "Error"
                    CurrentStatus = "Error"
                    StartType = "Unknown"
                    RestartAttempted = $false
                    RestartSuccess = $false
                    Attempts = 0
                    Timestamp = Get-Date
                }

                $results += $result
            }
        }
    }

    return $results
}

# Main execution
Write-Log "=== Service Monitor Started ==="
Write-Log "AutoRestart: $AutoRestart"
Write-Log "Max Restart Attempts: $MaxRestartAttempts"
Write-Log "Continuous Monitoring: $ContinuousMonitoring"

if ($ContinuousMonitoring) {
    Write-Log "Running in continuous monitoring mode (Interval: $MonitorInterval seconds)"
    Write-Log "Press Ctrl+C to stop"

    try {
        while ($true) {
            $results = Monitor-Services

            if ($results) {
                Write-Host "`n=== Service Status Summary ===" -ForegroundColor Cyan
                $results | Format-Table Computer, DisplayName, OriginalStatus, CurrentStatus, RestartAttempted, RestartSuccess -AutoSize
            }

            Write-Log "Next check in $MonitorInterval seconds..."
            Start-Sleep -Seconds $MonitorInterval
        }
    }
    catch {
        Write-Log "Monitoring stopped: $_" -Level "WARN"
    }
}
else {
    # Single run
    $results = Monitor-Services

    if ($results) {
        Write-Host "`n=== Service Status Summary ===" -ForegroundColor Cyan
        $results | Format-Table Computer, DisplayName, OriginalStatus, CurrentStatus, RestartAttempted, RestartSuccess -AutoSize
    }

    Write-Log "=== Service Monitor Complete ==="
    return $results
}
