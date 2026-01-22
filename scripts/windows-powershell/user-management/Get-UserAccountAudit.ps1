<#
.SYNOPSIS
    Audits local and Active Directory user accounts for security and compliance.

.DESCRIPTION
    Generates comprehensive reports on user accounts including:
    - Inactive users
    - Password expiration status
    - Group memberships
    - Account status (enabled/disabled/locked)
    - Last logon information
    - Password age and policy compliance

.PARAMETER ComputerName
    Computer name(s) to audit local accounts. Defaults to local computer.

.PARAMETER Domain
    Active Directory domain to audit. If specified, audits AD users instead of local.

.PARAMETER InactiveDays
    Number of days to consider a user inactive. Default: 90

.PARAMETER PasswordExpiringDays
    Alert on passwords expiring within this many days. Default: 14

.PARAMETER IncludeGroups
    Include detailed group membership information.

.PARAMETER LocalAccountsOnly
    Audit only local user accounts (not domain).

.PARAMETER ExportCSV
    Export results to CSV file.

.PARAMETER CSVPath
    Path for CSV export. Default: C:\Reports\UserAccountAudit.csv

.PARAMETER ExportHTML
    Export results to HTML report.

.PARAMETER HTMLPath
    Path for HTML report. Default: C:\Reports\UserAccountAudit.html

.PARAMETER ShowDisabledAccounts
    Include disabled accounts in the report.

.EXAMPLE
    .\Get-UserAccountAudit.ps1
    Audits local user accounts on the local computer.

.EXAMPLE
    .\Get-UserAccountAudit.ps1 -ComputerName SERVER01,SERVER02 -InactiveDays 60
    Audits local accounts on multiple servers, 60-day inactivity threshold.

.EXAMPLE
    .\Get-UserAccountAudit.ps1 -Domain contoso.com -InactiveDays 90 -ExportHTML
    Audits Active Directory users in contoso.com domain, exports to HTML.

.EXAMPLE
    .\Get-UserAccountAudit.ps1 -IncludeGroups -ShowDisabledAccounts
    Full audit including group memberships and disabled accounts.

.NOTES
    Author: MFLIT Script Library
    Requires: PowerShell 3.0+, Administrator rights, ActiveDirectory module for AD audits
    License: GPL-3.0
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline=$true)]
    [string[]]$ComputerName = $env:COMPUTERNAME,

    [string]$Domain,

    [int]$InactiveDays = 90,

    [int]$PasswordExpiringDays = 14,

    [switch]$IncludeGroups,

    [switch]$LocalAccountsOnly,

    [switch]$ExportCSV,

    [string]$CSVPath = "C:\Reports\UserAccountAudit.csv",

    [switch]$ExportHTML,

    [string]$HTMLPath = "C:\Reports\UserAccountAudit.html",

    [switch]$ShowDisabledAccounts
)

$results = @()
$inactiveDate = (Get-Date).AddDays(-$InactiveDays)
$passwordExpiryWarning = (Get-Date).AddDays($PasswordExpiringDays)

Write-Host "=== User Account Audit ===" -ForegroundColor Cyan
Write-Host "Inactive Threshold: $InactiveDays days" -ForegroundColor Gray
Write-Host "Password Expiry Warning: $PasswordExpiringDays days" -ForegroundColor Gray
Write-Host ""

# Function to get group memberships
function Get-UserGroups {
    param(
        [string]$Username,
        [string]$Computer = $null
    )

    try {
        if ($Computer) {
            $user = [ADSI]"WinNT://$Computer/$Username,user"
            $groups = $user.Groups() | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) }
        }
        else {
            $groups = (Get-ADUser $Username -Properties MemberOf).MemberOf |
                ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }
        }
        return $groups -join '; '
    }
    catch {
        return "Error retrieving groups"
    }
}

# Audit Active Directory users
if ($Domain -and -not $LocalAccountsOnly) {
    Write-Host "Auditing Active Directory domain: $Domain" -ForegroundColor Yellow

    try {
        # Check if ActiveDirectory module is available
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Host "ERROR: ActiveDirectory PowerShell module not available" -ForegroundColor Red
            Write-Host "Install RSAT tools or run on a Domain Controller" -ForegroundColor Yellow
            return
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        # Get all users
        $adUsers = Get-ADUser -Filter * -Properties *

        foreach ($user in $adUsers) {
            # Skip disabled accounts unless requested
            if (-not $ShowDisabledAccounts -and -not $user.Enabled) {
                continue
            }

            # Calculate password age
            $passwordAge = if ($user.PasswordLastSet) {
                (New-TimeSpan -Start $user.PasswordLastSet -End (Get-Date)).Days
            } else { $null }

            # Determine password expiry
            $passwordExpiry = $null
            $passwordExpiring = $false

            if ($user.PasswordNeverExpires -eq $false -and $user.PasswordLastSet) {
                $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
                $passwordExpiry = $user.PasswordLastSet.AddDays($maxPasswordAge)
                $passwordExpiring = $passwordExpiry -le $passwordExpiryWarning
            }

            # Determine if inactive
            $lastLogon = $user.LastLogonDate
            $isInactive = $false

            if ($lastLogon) {
                $isInactive = $lastLogon -lt $inactiveDate
            }
            elseif ($user.whenCreated -lt $inactiveDate) {
                $isInactive = $true
            }

            # Get groups if requested
            $groups = if ($IncludeGroups) {
                Get-UserGroups -Username $user.SamAccountName
            } else { "Not retrieved" }

            # Create result object
            $result = [PSCustomObject]@{
                Domain = $Domain
                Username = $user.SamAccountName
                DisplayName = $user.DisplayName
                Enabled = $user.Enabled
                Locked = $user.LockedOut
                LastLogon = $lastLogon
                IsInactive = $isInactive
                PasswordLastSet = $user.PasswordLastSet
                PasswordAge = $passwordAge
                PasswordExpiry = $passwordExpiry
                PasswordExpiring = $passwordExpiring
                PasswordNeverExpires = $user.PasswordNeverExpires
                AccountExpires = $user.AccountExpirationDate
                Created = $user.whenCreated
                Groups = $groups
                Description = $user.Description
            }

            $results += $result
        }

        Write-Host "Found $($adUsers.Count) AD users" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR auditing Active Directory: $_" -ForegroundColor Red
    }
}

# Audit Local user accounts
if ($LocalAccountsOnly -or -not $Domain) {
    foreach ($computer in $ComputerName) {
        Write-Host "Auditing local accounts on $computer..." -ForegroundColor Yellow

        try {
            # Get local users
            $localUsers = Get-WmiObject -Class Win32_UserAccount -ComputerName $computer -Filter "LocalAccount=True"

            foreach ($user in $localUsers) {
                # Skip disabled accounts unless requested
                if (-not $ShowDisabledAccounts -and $user.Disabled) {
                    continue
                }

                # Get additional user properties from ADSI
                try {
                    $adsiUser = [ADSI]"WinNT://$computer/$($user.Name),user"

                    $passwordAge = $adsiUser.PasswordAge[0]
                    $passwordAgeDays = [math]::Round($passwordAge / 86400)

                    $lastLogin = $adsiUser.LastLogin[0]
                    if ($lastLogin -is [System.Int64] -and $lastLogin -gt 0) {
                        $lastLoginDate = [DateTime]::FromFileTime($lastLogin)
                    }
                    else {
                        $lastLoginDate = $null
                    }

                    $isInactive = if ($lastLoginDate) {
                        $lastLoginDate -lt $inactiveDate
                    }
                    else {
                        $true  # Never logged in
                    }

                    # Get groups if requested
                    $groups = if ($IncludeGroups) {
                        Get-UserGroups -Username $user.Name -Computer $computer
                    } else { "Not retrieved" }
                }
                catch {
                    $passwordAgeDays = $null
                    $lastLoginDate = $null
                    $isInactive = "Unknown"
                    $groups = "Error"
                }

                # Create result object
                $result = [PSCustomObject]@{
                    Computer = $computer
                    Username = $user.Name
                    FullName = $user.FullName
                    Enabled = -not $user.Disabled
                    Locked = $user.Lockout
                    LastLogon = $lastLoginDate
                    IsInactive = $isInactive
                    PasswordAge = $passwordAgeDays
                    PasswordExpires = -not $user.PasswordExpires
                    Description = $user.Description
                    Groups = $groups
                    SID = $user.SID
                }

                $results += $result
            }

            Write-Host "  Found $($localUsers.Count) local users" -ForegroundColor Green
        }
        catch {
            Write-Host "  ERROR: $_" -ForegroundColor Red
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "No user accounts found matching criteria." -ForegroundColor Yellow
    return
}

# Display summary statistics
Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Accounts: $($results.Count)" -ForegroundColor White

$enabledCount = ($results | Where-Object { $_.Enabled -eq $true }).Count
$disabledCount = ($results | Where-Object { $_.Enabled -eq $false }).Count
$lockedCount = ($results | Where-Object { $_.Locked -eq $true }).Count
$inactiveCount = ($results | Where-Object { $_.IsInactive -eq $true }).Count

Write-Host "  Enabled: $enabledCount" -ForegroundColor Green
Write-Host "  Disabled: $disabledCount" -ForegroundColor Gray
Write-Host "  Locked: $lockedCount" -ForegroundColor Red
Write-Host "  Inactive ($InactiveDays+ days): $inactiveCount" -ForegroundColor Yellow

if ($Domain) {
    $passwordExpiringCount = ($results | Where-Object { $_.PasswordExpiring -eq $true }).Count
    $passwordNeverExpiresCount = ($results | Where-Object { $_.PasswordNeverExpires -eq $true }).Count

    Write-Host "  Password Expiring Soon: $passwordExpiringCount" -ForegroundColor Yellow
    Write-Host "  Password Never Expires: $passwordNeverExpiresCount" -ForegroundColor Cyan
}

# Show inactive users
$inactiveUsers = $results | Where-Object { $_.IsInactive -eq $true }

if ($inactiveUsers) {
    Write-Host "`n=== INACTIVE USERS ===" -ForegroundColor Cyan
    if ($Domain) {
        $inactiveUsers | Format-Table Username, DisplayName, LastLogon, Enabled -AutoSize
    }
    else {
        $inactiveUsers | Format-Table Computer, Username, LastLogon, Enabled -AutoSize
    }
}

# Show locked accounts
$lockedUsers = $results | Where-Object { $_.Locked -eq $true }

if ($lockedUsers) {
    Write-Host "`n=== LOCKED ACCOUNTS ===" -ForegroundColor Red
    if ($Domain) {
        $lockedUsers | Format-Table Username, DisplayName, LastLogon -AutoSize
    }
    else {
        $lockedUsers | Format-Table Computer, Username, LastLogon -AutoSize
    }
}

# Show passwords expiring soon (AD only)
if ($Domain) {
    $expiringPasswords = $results | Where-Object { $_.PasswordExpiring -eq $true }

    if ($expiringPasswords) {
        Write-Host "`n=== PASSWORDS EXPIRING SOON ===" -ForegroundColor Yellow
        $expiringPasswords | Format-Table Username, DisplayName, PasswordExpiry -AutoSize
    }
}

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
    .inactive { background-color: #ff9800; }
    .locked { background-color: #f44336; color: white; }
    .disabled { background-color: #999; color: white; }
    .summary { background-color: #f5f5f5; padding: 15px; border-left: 4px solid #4CAF50; margin-bottom: 20px; }
</style>
<h1>User Account Audit Report</h1>
<p><strong>Generated:</strong> $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
<p><strong>Inactive Threshold:</strong> $InactiveDays days</p>

<div class="summary">
<h2>Summary Statistics</h2>
<p><strong>Total Accounts:</strong> $($results.Count)</p>
<p><strong>Enabled:</strong> $enabledCount | <strong>Disabled:</strong> $disabledCount | <strong>Locked:</strong> $lockedCount</p>
<p><strong>Inactive:</strong> $inactiveCount</p>
</div>

<h2>User Account Details</h2>
"@

    $htmlFull = $htmlHeader + ($results | ConvertTo-Html -Fragment) + "</body></html>"
    $htmlFull | Out-File -FilePath $HTMLPath -Encoding UTF8

    Write-Host "Results exported to HTML: $HTMLPath" -ForegroundColor Green
}

return $results
