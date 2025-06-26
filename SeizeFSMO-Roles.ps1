<#
.SYNOPSIS
    Safely seizes FSMO roles from failed domain controllers.

.DESCRIPTION
    This script automates FSMO role seizure by:
      - Identifying current FSMO role holders
      - Pinging them to verify if they’re online
      - Seizing roles only from offline holders
    It uses `ntdsutil` and should only be used if the original FSMO DCs are permanently offline.

.PARAMETER NewFSMOHolder
    The domain controller to seize FSMO roles to.

.PARAMETER RolesToSeize
    Optional. Specific roles to seize. Defaults to all.

.EXAMPLE
    .\Seize-FSMORoles.ps1 -NewFSMOHolder "DC2"

    .\Seize-FSMORoles.ps1 -NewFSMOHolder "DC2" -RolesToSeize "PDCEmulator","RIDMaster"
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter(Mandatory)]
    [string]$NewFSMOHolder,

    [Parameter()]
    [ValidateSet("SchemaMaster","DomainNamingMaster","RIDMaster","PDCEmulator","InfrastructureMaster")]
    [string[]]$RolesToSeize = @("SchemaMaster","DomainNamingMaster","RIDMaster","PDCEmulator","InfrastructureMaster")
)

function Confirm-Seizure {
    Write-Warning "⚠️ FSMO Role Seizure is a LAST RESORT action."
    Write-Warning "Only proceed if the current FSMO holder is permanently offline."
    $confirm = Read-Host "Type 'YES' to confirm and proceed"
    if ($confirm -ne "YES") {
        Write-Host "❌ Operation cancelled." -ForegroundColor Red
        exit
    }
}

function Seize-Role {
    param (
        [string]$DC,
        [string]$Role
    )

    Write-Host "`n🔧 Seizing $Role to $DC..." -ForegroundColor Cyan

    $ntdsutilCmds = @"
roles
connections
connect to server $DC
quit
seize $Role
quit
quit
"@

    $tempFile = New-TemporaryFile
    $ntdsutilCmds | Out-File $tempFile -Encoding ASCII

    Start-Process -FilePath "ntdsutil.exe" -ArgumentList "/s `"$tempFile`"" -Wait -NoNewWindow
    Remove-Item $tempFile -Force
}

# --- MAIN EXECUTION ---

Import-Module ActiveDirectory

Write-Host "🔍 Retrieving current FSMO role holders..." -ForegroundColor Yellow

# Step 1: Get FSMO role holders
$fsmo = Get-ADForest | Select-Object -ExpandProperty FSMORoleOwner
$currentRoles = @{
    "SchemaMaster"         = ($fsmo | Where-Object { $_ -like "*Schema*" })
    "DomainNamingMaster"   = ($fsmo | Where-Object { $_ -like "*Naming*" })
}
$domainFSMO = Get-ADDomain
$currentRoles["RIDMaster"]            = $domainFSMO.RIDMaster
$currentRoles["PDCEmulator"]          = $domainFSMO.PDCEmulator
$currentRoles["InfrastructureMaster"] = $domainFSMO.InfrastructureMaster

# Step 2: Extract server names
$FSMOServers = @{}
foreach ($role in $currentRoles.Keys) {
    $dn = $currentRoles[$role]
    if ($dn -match "^CN=NTDS Settings,CN=(.*?),CN=Servers") {
        $server = $matches[1]
        $FSMOServers[$role] = $server
    } elseif ($dn -match "^CN=(.*?),CN=Servers") {
        $server = $matches[1]
        $FSMOServers[$role] = $server
    }
}

Write-Host "`n📃 Current FSMO Role Holders:"
$currentRoles.GetEnumerator() | ForEach-Object {
    Write-Host "$($_.Key): $($_.Value)"
}

Write-Host "`n📍 Target FSMO holder: $NewFSMOHolder"
Write-Host "🎯 Roles requested: $($RolesToSeize -join ', ')"

# Step 3: Confirm
Confirm-Seizure

# Step 4: Ping FSMO holders
Write-Host "`n🌐 Pinging FSMO holders to verify status..." -ForegroundColor Yellow
$OfflineRoles = @()

foreach ($role in $RolesToSeize) {
    $holder = $FSMOServers[$role]
    Write-Host "⏳ Checking $role on $holder..."

    if (Test-Connection -ComputerName $holder -Count 2 -Quiet) {
        Write-Warning "$role holder '$holder' is ONLINE. Skipping seizure of this role."
    } else {
        Write-Host "$role holder '$holder' is OFFLINE. Marking for seizure." -ForegroundColor Green
        $OfflineRoles += $role
    }
}

if ($OfflineRoles.Count -eq 0) {
    Write-Error "`n❌ No FSMO roles will be seized — all role holders are online."
    exit
}

Write-Host "`n📝 Final FSMO roles marked for seizure: $($OfflineRoles -join ', ')" -ForegroundColor Cyan

# Step 5: Seize roles
foreach ($role in $OfflineRoles) {
    if ($PSCmdlet.ShouldProcess("FSMO Role: $role", "Seize to $NewFSMOHolder")) {
        Seize-Role -DC $NewFSMOHolder -Role $role
    }
}

Write-Host "`n✅ FSMO Seizure Complete. Use 'netdom query fsmo' to confirm." -ForegroundColor Green
