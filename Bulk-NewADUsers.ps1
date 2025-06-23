<#
.SYNOPSIS
  Bulk‐create new AD users from a CSV.

.DESCRIPTION
  Imports ActiveDirectory, reads the CSV at S:\ad-automation\UsersToCreate.csv,
  and runs New-ADUser for each row. CSV must have headers matching the parameters
  you want to use (e.g. Name, SamAccountName, GivenName, Surname, UserPrincipalName,
  Path (OU DN), Password).

.EXAMPLE
  PS C:\Scripts> .\Bulk-NewADUsers.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$CsvPath = 'S:\ad-automation\UsersToCreate.csv'
)

# 0) Verify CSV exists
if (-not (Test-Path $CsvPath)) {
    Write-Error "CSV file not found at '$CsvPath'"
    exit 1
}

# 1) Import AD module
Import-Module ActiveDirectory -ErrorAction Stop

# 2) Read CSV
$users = Import-Csv -Path $CsvPath

# 3) Loop and create
foreach ($u in $users) {
    try {
        # Build a secure password
        $securePwd = ConvertTo-SecureString $u.Password -AsPlainText -Force

        # Create the account
        New-ADUser `
            -Name               $u.Name `
            -SamAccountName     $u.SamAccountName `
            -UserPrincipalName  $u.UserPrincipalName `
            -GivenName          $u.GivenName `
            -Surname            $u.Surname `
            -Path               $u.Path `
            -AccountPassword    $securePwd `
            -Enabled            $true `
            -ChangePasswordAtLogon:$false `
            -PasswordNeverExpires:$false `
            -ErrorAction Stop

        Write-Host "Created user:" $u.SamAccountName -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to create $($u.SamAccountName): $($_.Exception.Message)"
    }
}

Write-Host "All done." -ForegroundColor Cyan
