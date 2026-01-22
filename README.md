# MFLITScriptLibrary

A comprehensive collection of PowerShell scripts for Managed Service Providers (MSPs) to automate common system administration, security, and monitoring tasks.

## Overview

This library provides production-ready PowerShell scripts designed to help MSPs manage Windows environments efficiently. All scripts include comprehensive error handling, logging capabilities, and flexible reporting options.

## Features

- **System Management** - Monitor and maintain system health
- **User Management** - Audit and manage user accounts
- **Security Auditing** - Identify security issues and compliance violations
- **Automated Reporting** - Generate HTML and CSV reports
- **Email Alerts** - Built-in notification capabilities
- **Remote Management** - Manage multiple computers simultaneously

## Requirements

- **PowerShell**: Version 3.0 or higher
- **Permissions**: Administrator rights (for most scripts)
- **Remote Management**: WinRM enabled for remote computer access
- **Active Directory**: AD PowerShell module (for domain-related scripts)

## Installation

1. Clone this repository:
   ```powershell
   git clone https://github.com/billcd/MFLITScriptLibrary.git
   ```

2. Navigate to the script directory:
   ```powershell
   cd MFLITScriptLibrary\scripts\windows-powershell
   ```

3. Ensure execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Script Library

### System Management

#### 1. Get-DiskSpaceAlert.ps1
Monitors disk space and generates alerts when thresholds are exceeded.

**Features:**
- Configurable warning and critical thresholds
- Email notifications
- HTML and CSV reports
- Multi-computer support

**Basic Usage:**
```powershell
.\Get-DiskSpaceAlert.ps1 -WarningThreshold 20 -CriticalThreshold 10
```

**Advanced Usage:**
```powershell
.\Get-DiskSpaceAlert.ps1 -ComputerName SERVER01,SERVER02 `
    -CriticalThreshold 5 `
    -SendEmail `
    -EmailTo admin@company.com `
    -EmailFrom alerts@company.com `
    -SmtpServer mail.company.com `
    -ExportHTML
```

---

#### 2. Get-WindowsUpdateStatus.ps1
Checks Windows Update status including pending updates and reboot requirements.

**Features:**
- Pending update detection
- Reboot requirement checking
- Update history retrieval
- Multi-computer scanning

**Basic Usage:**
```powershell
.\Get-WindowsUpdateStatus.ps1
```

**Advanced Usage:**
```powershell
.\Get-WindowsUpdateStatus.ps1 -ComputerName SERVER01,SERVER02 `
    -IncludeHistory `
    -HistoryDays 30 `
    -ExportCSV -CSVPath C:\Reports\Updates.csv
```

---

#### 3. Monitor-ServiceAutoRestart.ps1
Monitors critical services and automatically restarts them if stopped.

**Features:**
- Automatic service restart
- Configurable retry attempts
- Continuous monitoring mode
- Email alerts for failures
- Service list file support

**Basic Usage:**
```powershell
.\Monitor-ServiceAutoRestart.ps1 -ServiceName "Spooler","W32Time"
```

**Continuous Monitoring:**
```powershell
.\Monitor-ServiceAutoRestart.ps1 -ServiceName "MSSQLSERVER" `
    -ContinuousMonitoring `
    -MonitorInterval 60 `
    -MaxRestartAttempts 3
```

---

#### 4. Get-EventLogAnalysis.ps1
Analyzes Windows Event Logs for critical errors, warnings, and security events.

**Features:**
- Multi-log scanning (Application, System, Security)
- Severity filtering
- Event ID filtering
- Time range specification
- Top errors analysis
- Group by source

**Basic Usage:**
```powershell
.\Get-EventLogAnalysis.ps1 -Hours 24
```

**Advanced Usage:**
```powershell
.\Get-EventLogAnalysis.ps1 -ComputerName SERVER01 `
    -LogName System,Application `
    -Level Error,Critical `
    -Hours 48 `
    -GroupBySource `
    -TopErrors 20 `
    -ExportHTML
```

**Security Event Analysis:**
```powershell
.\Get-EventLogAnalysis.ps1 -LogName Security `
    -EventID 4625,4624 `
    -Hours 12
```

---

#### 5. Get-SoftwareInventory.ps1
Generates comprehensive software inventory reports.

**Features:**
- Registry-based inventory (32-bit and 64-bit)
- Publisher filtering
- Size and installation date tracking
- Statistics and grouping
- Multi-computer support

**Basic Usage:**
```powershell
.\Get-SoftwareInventory.ps1
```

**Advanced Usage:**
```powershell
.\Get-SoftwareInventory.ps1 -ComputerName WORKSTATION01,WORKSTATION02 `
    -ExcludeSystemComponents `
    -ShowStatistics `
    -GroupByPublisher `
    -ExportHTML
```

**Filtered Inventory:**
```powershell
.\Get-SoftwareInventory.ps1 -FilterPublisher "Microsoft*" -ExportCSV
```

---

### User Management

#### 6. Get-UserAccountAudit.ps1
Audits user accounts for security and compliance.

**Features:**
- Inactive user detection
- Password expiration tracking
- Group membership reporting
- Local and Active Directory support
- Account status monitoring

**Local Accounts:**
```powershell
.\Get-UserAccountAudit.ps1 -ComputerName SERVER01,SERVER02 `
    -InactiveDays 90 `
    -IncludeGroups
```

**Active Directory:**
```powershell
.\Get-UserAccountAudit.ps1 -Domain contoso.com `
    -InactiveDays 90 `
    -PasswordExpiringDays 14 `
    -ShowDisabledAccounts `
    -ExportHTML
```

---

### Security

#### 7. Get-LocalAdminReport.ps1
Audits local administrators across workstations and servers.

**Features:**
- Multi-computer scanning
- Unexpected admin detection
- Built-in account filtering
- Domain account identification
- CSV and HTML reporting

**Basic Usage:**
```powershell
.\Get-LocalAdminReport.ps1 -ComputerName WORKSTATION01
```

**Advanced Usage:**
```powershell
.\Get-LocalAdminReport.ps1 -ComputerList C:\computers.txt `
    -ExpectedAdmins "Domain Admins","ITAdmin","BackupAdmin" `
    -HighlightUnexpected `
    -ExcludeBuiltIn `
    -ExportHTML
```

**Pipeline Input:**
```powershell
Get-ADComputer -Filter * | Select -ExpandProperty Name | `
    .\Get-LocalAdminReport.ps1 -ExportCSV
```

---

## Common Parameters

Most scripts support these common parameters:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ComputerName` | Target computer(s) | Local computer |
| `-ExportCSV` | Export to CSV file | False |
| `-CSVPath` | CSV file path | C:\Reports\*.csv |
| `-ExportHTML` | Export to HTML report | False |
| `-HTMLPath` | HTML file path | C:\Reports\*.html |

## Email Notifications

Scripts with email support require these parameters:

```powershell
-SendEmail `
-EmailTo "admin@company.com" `
-EmailFrom "alerts@company.com" `
-SmtpServer "mail.company.com"
```

## Logging

Scripts automatically create logs in `C:\Logs\` directory. Log format:
```
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message
```

Log levels: INFO, WARN, ERROR, CRITICAL, SUCCESS

## Scheduling with Task Scheduler

Create automated monitoring by scheduling scripts with Windows Task Scheduler:

```powershell
# Example: Schedule disk space monitoring
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\Get-DiskSpaceAlert.ps1 -CriticalThreshold 10 -SendEmail"

$trigger = New-ScheduledTaskTrigger -Daily -At "6:00AM"

Register-ScheduledTask -TaskName "Daily Disk Space Check" `
    -Action $action -Trigger $trigger -RunLevel Highest
```

## Best Practices

1. **Test First**: Always test scripts in a non-production environment
2. **Use Least Privilege**: Run with minimum required permissions when possible
3. **Review Logs**: Check log files regularly for errors
4. **Secure Credentials**: Never hardcode passwords; use secure methods
5. **Document Changes**: Keep track of customizations
6. **Schedule Wisely**: Run resource-intensive scripts during off-hours

## Troubleshooting

### Common Issues

**Access Denied Errors:**
- Ensure you're running as Administrator
- Check WinRM is enabled for remote computers
- Verify firewall rules allow remote management

**Remote Computer Unreachable:**
- Test connectivity with `Test-Connection`
- Verify DNS resolution
- Check network firewall rules

**ActiveDirectory Module Not Found:**
- Install RSAT tools
- Or run scripts on a Domain Controller

**Email Alerts Not Working:**
- Verify SMTP server settings
- Check firewall allows SMTP traffic
- Test with `Send-MailMessage` cmdlet directly

## Examples

### Daily Health Check
```powershell
# Check disk space, updates, and event logs
.\Get-DiskSpaceAlert.ps1 -CriticalThreshold 10 -ExportHTML
.\Get-WindowsUpdateStatus.ps1 -ExportHTML
.\Get-EventLogAnalysis.ps1 -Hours 24 -ExportHTML
```

### Weekly Security Audit
```powershell
# Audit users and local admins
.\Get-UserAccountAudit.ps1 -InactiveDays 90 -ExportCSV
.\Get-LocalAdminReport.ps1 -ComputerList C:\servers.txt -HighlightUnexpected -ExportCSV
```

### Monthly Compliance Report
```powershell
# Generate comprehensive reports
.\Get-SoftwareInventory.ps1 -ShowStatistics -ExportHTML
.\Get-UserAccountAudit.ps1 -Domain contoso.com -ExportHTML
.\Get-LocalAdminReport.ps1 -ComputerList C:\all-computers.txt -ExportHTML
```

## Contributing

Contributions are welcome! Please ensure:
- Scripts follow PowerShell best practices
- Include comprehensive help documentation
- Add error handling and logging
- Test on multiple systems
- Update this README

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Submit a pull request for improvements

## Version History

### Version 1.0.0 (2026-01-22)
- Initial release
- 7 PowerShell scripts for Windows management
- System management tools (5 scripts)
- User management tools (1 script)
- Security auditing tools (1 script)

## Author

MFLIT Script Library

---

**Happy Scripting!** 🚀
