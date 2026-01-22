<#
.SYNOPSIS
    Audits local administrators across workstations and servers.

.DESCRIPTION
    Scans local or remote computers to identify members of the local Administrators group.
    Helps detect unauthorized admin access, shadow admins, and compliance violations.
    Generates reports for security auditing and compliance documentation.

.PARAMETER ComputerName
    Computer name(s) to audit. Accepts single computer, array, or pipeline input.

.PARAMETER ComputerList
    Path to text file containing computer names (one per line).

.PARAMETER ExcludeBuiltIn
    Exclude built-in accounts (Administrator, Domain Admins, etc.) from report.

.PARAMETER HighlightUnexpected
    Highlight users that are not in the expected administrators list.

.PARAMETER ExpectedAdmins
    Array of expected admin usernames/groups. Used with HighlightUnexpected.

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER CSVPath
    Path for CSV export. Default: C:\Reports\LocalAdminAudit.csv

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER HTMLPath
    Path for HTML report. Default: C:\Reports\LocalAdminAudit.html

.PARAMETER IncludeDomainInfo
    Include domain information for domain accounts.

.EXAMPLE
    .\Get-LocalAdminReport.ps1 -ComputerName WORKSTATION01
    Audits local administrators on a single computer.

.EXAMPLE
    .\Get-LocalAdminReport.ps1 -ComputerList C:\computers.txt -ExportCSV
    Audits computers from file and exports to CSV.

.EXAMPLE
    Get-ADComputer -Filter * | Select -ExpandProperty Name | .\Get-LocalAdminReport.ps1 -ExportHTML
    Audits all domain computers and exports to HTML.

.EXAMPLE
    .\Get-LocalAdminReport.ps1 -ComputerName SERVER01,SERVER02 -ExpectedAdmins "Domain Admins","ITAdmin" -HighlightUnexpected
    Audits servers and highlights unexpected administrators.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights for remote computers
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [Alias("Name")]
    [string[]]$ComputerName,

    [string]$ComputerList,

    [switch]$ExcludeBuiltIn,

    [switch]$HighlightUnexpected,

    [string[]]$ExpectedAdmins = @("Domain Admins", "Enterprise Admins"),

    [switch]$ExportCSV,

    [string]$CSVPath = "C:\Reports\LocalAdminAudit.csv",

    [switch]$ExportHTML,

    [string]$HTMLPath = "C:\Reports\LocalAdminAudit.html",

    [switch]$IncludeDomainInfo
)

begin {
    $results = @()
    $builtInSIDs = @(
        'S-1-5-32-544',  # Administrators
        'S-1-5-32-545',  # Users
        'S-1-5-32-546',  # Guests
        'S-1-5-18',      # Local System
        'S-1-5-19',      # Local Service
        'S-1-5-20'       # Network Service
    )

    $builtInNames = @(
        'Administrator',
        'Domain Admins',
        'Enterprise Admins',
        'Administrators'
    )

    Write-Host "=== Local Administrator Audit ===" -ForegroundColor Cyan
    Write-Host ""

    # Build computer list
    $computerList = @()

    if ($ComputerName) {
        $computerList += $ComputerName
    }

    if ($ComputerList -and (Test-Path $ComputerList)) {
        $computerList += Get-Content $ComputerList | Where-Object { $_ -notmatch '^\s*#' -and $_ -ne '' }
    }

    if ($computerList.Count -eq 0) {
        $computerList = @($env:COMPUTERNAME)
    }
}

process {
    # This allows pipeline input
    if ($_ -and $_ -notin $computerList) {
        $computerList += $_
    }
}

end {
    Write-Host "Auditing $($computerList.Count) computer(s)..." -ForegroundColor Yellow
    Write-Host ""

    foreach ($computer in $computerList) {
        Write-Host "Checking $computer..." -ForegroundColor Gray

        try {
            # Test connectivity
            if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
                Write-Host "  WARNING: Unable to ping $computer" -ForegroundColor Yellow

                $result = [PSCustomObject]@{
                    ComputerName = $computer
                    AccountName = "N/A"
                    AccountType = "N/A"
                    Domain = "N/A"
                    SID = "N/A"
                    IsExpected = $false
                    Status = "Unreachable"
                    ErrorMessage = "Computer did not respond to ping"
                }

                $results += $result
                continue
            }

            # Get local administrators group members
            $admins = Get-WmiObject -Class Win32_GroupUser -ComputerName $computer -ErrorAction Stop |
                Where-Object { $_.GroupComponent -like '*"Administrators"' }

            if (-not $admins) {
                Write-Host "  No administrators found or access denied" -ForegroundColor Yellow
                continue
            }

            $adminCount = 0

            foreach ($admin in $admins) {
                # Parse the account information
                $accountInfo = $admin.PartComponent

                # Extract domain and name
                if ($accountInfo -match 'Domain="([^"]+)".*Name="([^"]+)"') {
                    $domain = $matches[1]
                    $name = $matches[2]
                    $fullName = "$domain\$name"
                }
                else {
                    $fullName = $accountInfo
                    $domain = "Unknown"
                    $name = "Unknown"
                }

                # Get account details
                try {
                    $account = [ADSI]"WinNT://$domain/$name"
                    $accountType = $account.SchemaClassName

                    # Get SID if possible
                    try {
                        $sid = (New-Object System.Security.Principal.NTAccount($fullName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                    }
                    catch {
                        $sid = "Unable to resolve"
                    }
                }
                catch {
                    $accountType = "Unknown"
                    $sid = "Unknown"
                }

                # Check if built-in
                $isBuiltIn = $false

                if ($ExcludeBuiltIn) {
                    if ($builtInNames -contains $name -or $builtInSIDs -contains $sid) {
                        $isBuiltIn = $true
                        continue
                    }
                }

                # Check if expected
                $isExpected = $false
                if ($ExpectedAdmins) {
                    foreach ($expected in $ExpectedAdmins) {
                        if ($name -like "*$expected*" -or $fullName -like "*$expected*") {
                            $isExpected = $true
                            break
                        }
                    }
                }

                # Get additional domain info if requested
                $additionalInfo = ""
                if ($IncludeDomainInfo -and $domain -ne $computer -and $domain -ne "Unknown") {
                    try {
                        # Try to get AD info
                        $adUser = Get-ADUser -Identity $name -Properties Description, Enabled -ErrorAction SilentlyContinue
                        if ($adUser) {
                            $additionalInfo = "Enabled: $($adUser.Enabled); Description: $($adUser.Description)"
                        }
                    }
                    catch {
                        # AD module not available or user not in AD
                    }
                }

                # Create result object
                $result = [PSCustomObject]@{
                    ComputerName = $computer
                    AccountName = $name
                    FullName = $fullName
                    AccountType = $accountType
                    Domain = $domain
                    SID = $sid
                    IsExpected = $isExpected
                    IsBuiltIn = $isBuiltIn
                    Status = "Success"
                    AdditionalInfo = $additionalInfo
                }

                $results += $result
                $adminCount++

                # Display with color coding
                $color = if ($HighlightUnexpected -and -not $isExpected) { "Yellow" } else { "Green" }
                $flag = if ($HighlightUnexpected -and -not $isExpected) { " [UNEXPECTED]" } else { "" }

                Write-Host "  - $fullName ($accountType)$flag" -ForegroundColor $color
            }

            Write-Host "  Found $adminCount administrator(s)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ERROR: $_" -ForegroundColor Red

            $result = [PSCustomObject]@{
                ComputerName = $computer
                AccountName = "N/A"
                AccountType = "N/A"
                Domain = "N/A"
                SID = "N/A"
                IsExpected = $false
                Status = "Error"
                ErrorMessage = $_.Exception.Message
            }

            $results += $result
        }

        Write-Host ""
    }

    # Display summary
    Write-Host "=== SUMMARY ===" -ForegroundColor Cyan

    $successfulScans = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $totalAdmins = ($results | Where-Object { $_.Status -eq "Success" -and $_.AccountName -ne "N/A" }).Count
    $uniqueAdmins = ($results | Where-Object { $_.Status -eq "Success" } | Select-Object -Unique FullName).Count

    Write-Host "Computers Scanned: $($computerList.Count)" -ForegroundColor White
    Write-Host "Successful Scans: $successfulScans" -ForegroundColor Green
    Write-Host "Total Admin Entries: $totalAdmins" -ForegroundColor White
    Write-Host "Unique Admins: $uniqueAdmins" -ForegroundColor White

    if ($HighlightUnexpected) {
        $unexpectedCount = ($results | Where-Object { $_.IsExpected -eq $false -and $_.Status -eq "Success" }).Count
        Write-Host "Unexpected Admins: $unexpectedCount" -ForegroundColor Yellow
    }

    # Show computers with issues
    $errorComputers = $results | Where-Object { $_.Status -ne "Success" } | Select-Object -Unique ComputerName

    if ($errorComputers) {
        Write-Host "`nComputers with Issues:" -ForegroundColor Red
        $errorComputers | ForEach-Object { Write-Host "  - $($_.ComputerName)" -ForegroundColor Red }
    }

    # Show unexpected admins if highlighting
    if ($HighlightUnexpected) {
        $unexpected = $results | Where-Object { $_.IsExpected -eq $false -and $_.Status -eq "Success" -and -not $_.IsBuiltIn }

        if ($unexpected) {
            Write-Host "`n=== UNEXPECTED ADMINISTRATORS ===" -ForegroundColor Yellow
            $unexpected | Format-Table ComputerName, FullName, AccountType -AutoSize
        }
    }

    # Show detailed results
    Write-Host "`n=== ALL RESULTS ===" -ForegroundColor Cyan
    $results | Where-Object { $_.Status -eq "Success" } |
        Format-Table ComputerName, FullName, AccountType, Domain -AutoSize

    # Export to CSV if requested
    if ($ExportCSV) {
        $csvDir = Split-Path -Path $CSVPath -Parent
        if ($csvDir -and -not (Test-Path $csvDir)) {
            New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
        }

        $results | Export-Csv -Path $CSVPath -NoTypeInformation -Force
        Write-Host "`nResults exported to CSV: $CSVPath" -ForegroundColor Green
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
    .unexpected { background-color: #ff9800; }
    .error { background-color: #f44336; color: white; }
    .summary { background-color: #f5f5f5; padding: 15px; border-left: 4px solid #4CAF50; margin-bottom: 20px; }
</style>
<h1>Local Administrator Audit Report</h1>
<p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Computers Audited:</strong> $($computerList.Count)</p>

<div class="summary">
<h2>Summary</h2>
<p><strong>Successful Scans:</strong> $successfulScans</p>
<p><strong>Total Admin Entries:</strong> $totalAdmins</p>
<p><strong>Unique Admins:</strong> $uniqueAdmins</p>
</div>

<h2>Administrator Details</h2>
"@

        $htmlFull = $htmlHeader + ($results | ConvertTo-Html -Fragment) + "</body></html>"
        $htmlFull | Out-File -FilePath $HTMLPath -Encoding UTF8

        Write-Host "Results exported to HTML: $HTMLPath" -ForegroundColor Green
    }

    return $results
}
