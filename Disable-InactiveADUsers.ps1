<#
.SYNOPSIS
  Disables AD users who haven’t logged on in X days.

.DESCRIPTION
  Scans for enabled user accounts in AD that haven’t logged on in the last N days.
  Outputs a report and disables those accounts.

.PARAMETER DaysInactive
  Number of days since last logon before disabling the user.

.PARAMETER ReportPath
  Optional path to save a CSV report of disabled users.

.EXAMPLE
  PS> .\Disable-InactiveADUsers.ps1 -DaysInactive 90
#>



[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [int]$DaysInactive,

    [string]$ReportPath = ".\disabled_users_report.csv"
)

Import-Module ActiveDirectory

$cutoffDate = (Get-Date).AddDays(-$DaysInactive)

Write-Host "Searching for users inactive since before $cutoffDate..." -ForegroundColor Cyan

$inactiveUsers = Get-ADUser -Filter {
    Enabled -eq $true -and LastLogonTimeStamp -lt $cutoffDate
} -Properties Name, LastLogonDate, SamAccountName, Enabled, LastLogonTimeStamp

if ($inactiveUsers.Count -eq 0) {
    Write-Host "No inactive users found." -ForegroundColor Yellow
    return
}

$disabledList = @()

foreach ($user in $inactiveUsers) {
    try {
        Disable-ADAccount -Identity $user.SamAccountName -Confirm:$false
        Write-Host "Disabled: $($user.SamAccountName)" -ForegroundColor Green

        $disabledList += [PSCustomObject]@{
            SamAccountName = $user.SamAccountName
            Name           = $user.Name
            LastLogon      = $user.LastLogonDate
        }
    }
    catch {
        Write-Warning "Failed to disable $($user.SamAccountName): $($_.Exception.Message)"
    }
}

$disabledList | Export-Csv -Path $ReportPath -NoTypeInformation
Write-Host "Report saved to $ReportPath" -ForegroundColor Cyan
