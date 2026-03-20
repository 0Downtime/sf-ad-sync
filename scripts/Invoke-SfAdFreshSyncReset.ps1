[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SfAdSync'
Import-Module (Join-Path $moduleRoot 'Config.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'State.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $moduleRoot 'ActiveDirectorySync.psm1') -Force -DisableNameChecking

function Read-SfAdResetConfirmation {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [string]$ExpectedValue
    )

    $response = Read-Host -Prompt $Prompt
    return "$response".Trim() -ceq $ExpectedValue
}

function Get-SfAdFreshResetLogPath {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,
        [string]$RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        $requestedDirectory = Split-Path -Path $RequestedPath -Parent
        if (-not [string]::IsNullOrWhiteSpace($requestedDirectory) -and -not (Test-Path -Path $requestedDirectory -PathType Container)) {
            New-Item -Path $requestedDirectory -ItemType Directory -Force | Out-Null
        }

        return $RequestedPath
    }

    $directory = if (
    $Config.PSObject.Properties.Name -contains 'reporting' -and
    $Config.reporting -and
    $Config.reporting.PSObject.Properties.Name -contains 'outputDirectory' -and
    -not [string]::IsNullOrWhiteSpace("$($Config.reporting.outputDirectory)")
    ) {
        "$($Config.reporting.outputDirectory)"
    } else {
        [System.IO.Path]::GetTempPath()
    }

    if (-not (Test-Path -Path $directory -PathType Container)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path -Path $directory -ChildPath "sf-ad-sync-fresh-reset-$timestamp.log"
}

function Write-SfAdFreshResetLog {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $line = "[{0}][{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpperInvariant(), $Message
    Add-Content -Path $Path -Value $line
    Write-Host $line
}

function Get-SfAdFreshResetUserLabel {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$User
    )

    $samAccountName = if ($User.PSObject.Properties.Name -contains 'SamAccountName' -and -not [string]::IsNullOrWhiteSpace("$($User.SamAccountName)")) {
        "$($User.SamAccountName)"
    } else {
        '(unknown-sam)'
    }
    $distinguishedName = if ($User.PSObject.Properties.Name -contains 'DistinguishedName' -and -not [string]::IsNullOrWhiteSpace("$($User.DistinguishedName)")) {
        "$($User.DistinguishedName)"
    } else {
        '(unknown-dn)'
    }

    return "samAccountName=$samAccountName dn=$distinguishedName"
}

$resolvedConfigPath = (Resolve-Path -Path $ConfigPath).Path
$config = Get-SfAdSyncConfig -Path $resolvedConfigPath
$logPath = Get-SfAdFreshResetLogPath -Config $config -RequestedPath $LogPath
$managedOus = @(Get-SfAdManagedOus -Config $config)
$users = @(Get-SfAdUsersInOrganizationalUnits -Config $config -OrganizationalUnits $managedOus)

Write-SfAdFreshResetLog -Path $logPath -Message 'SuccessFactors Fresh Sync Reset'
Write-SfAdFreshResetLog -Path $logPath -Message "Config: $resolvedConfigPath"
Write-SfAdFreshResetLog -Path $logPath -Message "Log: $logPath"
Write-Host ''
Write-Host 'Managed sync OUs'
foreach ($ou in $managedOus) {
    Write-Host "- $ou"
    Write-SfAdFreshResetLog -Path $logPath -Message "Managed OU: $ou"
}
Write-Host ''
Write-Host "Discovered AD user objects: $($users.Count)"
Write-SfAdFreshResetLog -Path $logPath -Message "Discovered AD user objects: $($users.Count)"
foreach ($user in $users) {
    Write-SfAdFreshResetLog -Path $logPath -Message "Discovered user: $(Get-SfAdFreshResetUserLabel -User $user)"
}
Write-Host ''
Write-Host 'Warning 1: This permanently deletes AD user objects found recursively under the managed sync OUs above.' -ForegroundColor Yellow
Write-Host 'Warning 2: This is intended for a true fresh sync reset and cannot be undone by a normal sync run.' -ForegroundColor Yellow
Write-Host 'Warning 3: This also resets the local sync state checkpoint and tracked worker state.' -ForegroundColor Yellow
Write-Host ''

if (-not (Read-SfAdResetConfirmation -Prompt 'Type DELETE to continue' -ExpectedValue 'DELETE')) {
    Write-SfAdFreshResetLog -Path $logPath -Message 'Fresh sync reset cancelled at confirmation 1.'
    Write-Host 'Fresh sync reset cancelled at confirmation 1.'
    return
}

if (-not (Read-SfAdResetConfirmation -Prompt "Type $($users.Count) to confirm the discovered AD user count" -ExpectedValue "$($users.Count)")) {
    Write-SfAdFreshResetLog -Path $logPath -Message 'Fresh sync reset cancelled at confirmation 2.'
    Write-Host 'Fresh sync reset cancelled at confirmation 2.'
    return
}

$finalPhrase = 'DELETE ALL SYNCED OU USERS'
if (-not (Read-SfAdResetConfirmation -Prompt "Type '$finalPhrase' to permanently delete the users and reset local sync state" -ExpectedValue $finalPhrase)) {
    Write-SfAdFreshResetLog -Path $logPath -Message 'Fresh sync reset cancelled at confirmation 3.'
    Write-Host 'Fresh sync reset cancelled at confirmation 3.'
    return
}

$deleteFailures = [System.Collections.Generic.List[string]]::new()
foreach ($user in $users) {
    $userLabel = Get-SfAdFreshResetUserLabel -User $user
    try {
        Write-SfAdFreshResetLog -Path $logPath -Message "Deleting user: $userLabel"
        Remove-SfAdUser -Config $config -User $user
        Write-SfAdFreshResetLog -Path $logPath -Message "Deleted user: $userLabel"
    } catch {
        $failureMessage = "Failed to delete user: $userLabel :: $($_.Exception.Message)"
        $deleteFailures.Add($failureMessage)
        Write-SfAdFreshResetLog -Path $logPath -Message $failureMessage -Level 'ERROR'
    }
}

if ($deleteFailures.Count -gt 0) {
    Write-SfAdFreshResetLog -Path $logPath -Message 'Fresh sync reset aborted before state reset because one or more AD deletions failed.' -Level 'ERROR'
    throw "Fresh sync reset failed before state reset. See log: $logPath"
}

$emptyState = [pscustomobject]@{
    checkpoint = $null
    workers = @{}
}
Save-SfAdSyncState -State $emptyState -Path $config.state.path
Write-SfAdFreshResetLog -Path $logPath -Message "Reset sync state: $($config.state.path)"

Write-Host ''
Write-SfAdFreshResetLog -Path $logPath -Message 'Fresh sync reset completed.'
Write-SfAdFreshResetLog -Path $logPath -Message "Deleted AD user objects: $($users.Count)"
Write-Host 'Fresh sync reset completed.'
Write-Host "Deleted AD user objects: $($users.Count)"
Write-Host "Reset sync state: $($config.state.path)"
Write-Host "Log: $logPath"
