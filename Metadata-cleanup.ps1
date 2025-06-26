<#
.SYNOPSIS
    Cleans up Active Directory metadata for a permanently offline domain controller.

.DESCRIPTION
    This script performs post-FSMO seizure cleanup tasks:
      - Removes the DC's NTDS settings object
      - Removes the DC's server object from Sites and Services
      - Removes the computer account from Active Directory
      - Removes the DC from Domain Controllers OU
      - (Optional) Removes stale DNS records

.PARAMETER DeadDCName
    The NetBIOS name of the failed domain controller.

.PARAMETER Force
    Skips confirmation prompts.

.EXAMPLE
    .\Cleanup-DeadDC.ps1 -DeadDCName "DC1"

    .\Cleanup-DeadDC.ps1 -DeadDCName "DC1" -Force
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory)]
    [string]$DeadDCName,

    [switch]$Force
)

function Confirm-Action($Message) {
    if ($Force) { return $true }
    $confirm = Read-Host "$Message [Y/N]"
    return $confirm -match '^[Yy]$'
}

Import-Module ActiveDirectory

$rootDSE = Get-ADRootDSE
$configNC = $rootDSE.configurationNamingContext
$domainNC = $rootDSE.defaultNamingContext

Write-Host "🔍 Starting metadata cleanup for offline DC: $DeadDCName" -ForegroundColor Yellow

# 1. Remove NTDS Settings and Server object
try {
    $ntdsObj = Get-ADObject -LDAPFilter "(cn=NTDS Settings)" -SearchBase "CN=Sites,$configNC" -SearchScope Subtree | Where-Object { $_.DistinguishedName -like "*CN=$DeadDCName,*" }

    if ($ntdsObj) {
        if (Confirm-Action "Delete NTDS Settings object: $($ntdsObj.DistinguishedName)?") {
            Remove-ADObject -Identity $ntdsObj.DistinguishedName -Recursive -Confirm:$false
            Write-Host "✅ Removed NTDS Settings object"
        }
    } else {
        Write-Warning "NTDS Settings object not found for $DeadDCName"
    }
} catch {
    Write-Warning "⚠️ Failed to remove NTDS Settings object: $_"
}

# 2. Remove server object from Sites and Services
try {
    $serverObj = Get-ADObject -LDAPFilter "(objectClass=server)" -SearchBase "CN=Sites,$configNC" -SearchScope Subtree | Where-Object { $_.Name -eq $DeadDCName }

    if ($serverObj) {
        if (Confirm-Action "Delete Server object: $($serverObj.DistinguishedName)?") {
            Remove-ADObject -Identity $serverObj.DistinguishedName -Recursive -Confirm:$false
            Write-Host "✅ Removed Server object from Sites and Services"
        }
    } else {
        Write-Warning "Server object not found for $DeadDCName"
    }
} catch {
    Write-Warning "⚠️ Failed to remove Server object: $_"
}

# 3. Remove computer account from AD
try {
    $comp = Get-ADComputer -Identity $DeadDCName -ErrorAction SilentlyContinue
    if ($comp) {
        if (Confirm-Action "Delete computer account: $($comp.DistinguishedName)?") {
            Remove-ADComputer -Identity $DeadDCName -Confirm:$false
            Write-Host "✅ Removed computer account"
        }
    } else {
        Write-Warning "Computer account not found for $DeadDCName"
    }
} catch {
    Write-Warning "⚠️ Failed to remove computer account: $_"
}

# 4. Remove from Domain Controllers OU
try {
    $dcOU = "OU=Domain Controllers,$domainNC"
    $dcObj = Get-ADObject -LDAPFilter "(cn=$DeadDCName)" -SearchBase $dcOU -SearchScope OneLevel -ErrorAction SilentlyContinue

    if ($dcObj) {
        if (Confirm-Action "Delete object in Domain Controllers OU: $($dcObj.DistinguishedName)?") {
            Remove-ADObject -Identity $dcObj.DistinguishedName -Confirm:$false
            Write-Host "✅ Removed from Domain Controllers OU"
        }
    } else {
        Write-Warning "No object found in Domain Controllers OU for $DeadDCName"
    }
} catch {
    Write-Warning "⚠️ Failed to remove object from Domain Controllers OU: $_"
}

# 5. Optional: Stale DNS cleanup suggestion
Write-Host "`n📌 NOTE: DNS cleanup not included in this script (SRV/A records for $DeadDCName)" -ForegroundColor Yellow
Write-Host "You can manually clean DNS zones via DNS Manager or use 'Remove-DnsServerResourceRecord'." -ForegroundColor Gray

Write-Host "`n✅ Metadata cleanup complete. Run 'repadmin /replsummary' to verify health." -ForegroundColor Green
