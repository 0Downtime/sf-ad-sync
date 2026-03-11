Set-StrictMode -Version Latest

function Get-SfAdResolvedSetting {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [string]$EnvironmentVariableName
    )

    if ($EnvironmentVariableName) {
        $environmentValue = [System.Environment]::GetEnvironmentVariable($EnvironmentVariableName)
        if (-not [string]::IsNullOrWhiteSpace($environmentValue)) {
            return $environmentValue
        }
    }

    return $Value
}

function Test-SfAdHasProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,
        [Parameter(Mandatory)]
        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return $false
    }

    return $InputObject.PSObject.Properties.Name -contains $PropertyName
}

function Assert-SfAdRequiredString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,
        [Parameter(Mandatory)]
        [string]$PropertyPath
    )

    if ([string]::IsNullOrWhiteSpace("$Value")) {
        throw "Sync config must define $PropertyPath."
    }
}

function Resolve-SfAdSyncSecrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $secrets = if (Test-SfAdHasProperty -InputObject $Config -PropertyName 'secrets') { $Config.secrets } else { $null }

    $oauth = $Config.successFactors.oauth
    $oauth.clientId = Get-SfAdResolvedSetting -Value $oauth.clientId -EnvironmentVariableName $(if ($secrets -and (Test-SfAdHasProperty -InputObject $secrets -PropertyName 'successFactorsClientIdEnv')) { $secrets.successFactorsClientIdEnv } else { 'SF_AD_SYNC_SF_CLIENT_ID' })
    $oauth.clientSecret = Get-SfAdResolvedSetting -Value $oauth.clientSecret -EnvironmentVariableName $(if ($secrets -and (Test-SfAdHasProperty -InputObject $secrets -PropertyName 'successFactorsClientSecretEnv')) { $secrets.successFactorsClientSecretEnv } else { 'SF_AD_SYNC_SF_CLIENT_SECRET' })
    $Config.ad.defaultPassword = Get-SfAdResolvedSetting -Value $Config.ad.defaultPassword -EnvironmentVariableName $(if ($secrets -and (Test-SfAdHasProperty -InputObject $secrets -PropertyName 'defaultAdPasswordEnv')) { $secrets.defaultAdPasswordEnv } else { 'SF_AD_SYNC_AD_DEFAULT_PASSWORD' })

    return $Config
}

function Test-SfAdSyncMappingConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    if (-not $Config.mappings) {
        throw "Mapping config must contain a 'mappings' array."
    }

    $supportedTransforms = @('Trim', 'Upper', 'Lower', 'DateOnly', $null, '')
    $index = 0
    foreach ($mapping in @($Config.mappings)) {
        if ([string]::IsNullOrWhiteSpace("$($mapping.source)")) {
            throw "Mapping at index $index must define source."
        }

        if ([string]::IsNullOrWhiteSpace("$($mapping.target)")) {
            throw "Mapping at index $index must define target."
        }

        if (-not (Test-SfAdHasProperty -InputObject $mapping -PropertyName 'enabled')) {
            throw "Mapping at index $index must define enabled."
        }

        if (-not (Test-SfAdHasProperty -InputObject $mapping -PropertyName 'required')) {
            throw "Mapping at index $index must define required."
        }

        if ($supportedTransforms -notcontains $mapping.transform) {
            throw "Mapping at index $index has unsupported transform '$($mapping.transform)'."
        }

        $index += 1
    }
}

function Get-SfAdSyncConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Sync config file not found: $Path"
    }

    $config = Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 20
    $config = Resolve-SfAdSyncSecrets -Config $config
    Test-SfAdSyncConfig -Config $config
    return $config
}

function Get-SfAdSyncMappingConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "Mapping config file not found: $Path"
    }

    $config = Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 20
    Test-SfAdSyncMappingConfig -Config $config
    return $config
}

function Test-SfAdSyncConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $requiredProperties = @(
        'successFactors',
        'ad',
        'sync',
        'state',
        'reporting'
    )

    foreach ($property in $requiredProperties) {
        if (-not $Config.PSObject.Properties.Name.Contains($property)) {
            throw "Sync config is missing required property '$property'."
        }
    }

    Assert-SfAdRequiredString -Value $Config.successFactors.baseUrl -PropertyPath 'successFactors.baseUrl'
    Assert-SfAdRequiredString -Value $Config.successFactors.oauth.tokenUrl -PropertyPath 'successFactors.oauth.tokenUrl'
    Assert-SfAdRequiredString -Value $Config.successFactors.oauth.clientId -PropertyPath 'successFactors.oauth.clientId'
    Assert-SfAdRequiredString -Value $Config.successFactors.oauth.clientSecret -PropertyPath 'successFactors.oauth.clientSecret'
    Assert-SfAdRequiredString -Value $Config.successFactors.query.entitySet -PropertyPath 'successFactors.query.entitySet'
    Assert-SfAdRequiredString -Value $Config.successFactors.query.identityField -PropertyPath 'successFactors.query.identityField'
    Assert-SfAdRequiredString -Value $Config.successFactors.query.deltaField -PropertyPath 'successFactors.query.deltaField'

    if (@($Config.successFactors.query.select).Count -eq 0) {
        throw "Sync config must define successFactors.query.select."
    }

    if (@($Config.successFactors.query.expand).Count -eq 0) {
        throw "Sync config must define successFactors.query.expand."
    }

    Assert-SfAdRequiredString -Value $Config.ad.identityAttribute -PropertyPath 'ad.identityAttribute'
    Assert-SfAdRequiredString -Value $Config.ad.defaultActiveOu -PropertyPath 'ad.defaultActiveOu'
    Assert-SfAdRequiredString -Value $Config.ad.graveyardOu -PropertyPath 'ad.graveyardOu'
    Assert-SfAdRequiredString -Value $Config.ad.defaultPassword -PropertyPath 'ad.defaultPassword'
    Assert-SfAdRequiredString -Value $Config.state.path -PropertyPath 'state.path'
    Assert-SfAdRequiredString -Value $Config.reporting.outputDirectory -PropertyPath 'reporting.outputDirectory'

    if ([int]$Config.sync.enableBeforeStartDays -lt 0) {
        throw 'Sync config must define sync.enableBeforeStartDays as a non-negative integer.'
    }

    if ([int]$Config.sync.deletionRetentionDays -lt 0) {
        throw 'Sync config must define sync.deletionRetentionDays as a non-negative integer.'
    }

    if (Test-SfAdHasProperty -InputObject $Config -PropertyName 'safety') {
        foreach ($threshold in @('maxCreatesPerRun', 'maxDisablesPerRun', 'maxDeletionsPerRun')) {
            if (-not (Test-SfAdHasProperty -InputObject $Config.safety -PropertyName $threshold)) {
                continue
            }

            $value = $Config.safety.$threshold
            if ($null -eq $value -or "$value" -eq '') {
                continue
            }

            if ([int]$value -lt 0) {
                throw "Sync config must define safety.$threshold as a non-negative integer when provided."
            }
        }
    }
}

Export-ModuleMember -Function Get-SfAdResolvedSetting, Resolve-SfAdSyncSecrets, Get-SfAdSyncConfig, Get-SfAdSyncMappingConfig, Test-SfAdSyncConfig, Test-SfAdSyncMappingConfig
