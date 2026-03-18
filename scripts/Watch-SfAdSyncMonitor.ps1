[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,
    [string]$MappingConfigPath,
    [ValidateRange(1, 3600)]
    [int]$RefreshIntervalSeconds = 3,
    [ValidateRange(1, 1000)]
    [int]$HistoryLimit = 10,
    [switch]$RunOnce,
    [switch]$AsText
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'src/Modules/SfAdSync'
Import-Module (Join-Path $moduleRoot 'Config.psm1') -Force
Import-Module (Join-Path $moduleRoot 'State.psm1') -Force
Import-Module (Join-Path $moduleRoot 'Monitoring.psm1') -Force

function Get-OptionalResolvedPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        return $null
    }

    return (Resolve-Path -Path $Path).Path
}

function Show-SfAdMonitorFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResolvedConfigPath,
        [string]$ResolvedMappingConfigPath,
        [Parameter(Mandatory)]
        [int]$HistoryDepth,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState,
        [switch]$AsTextOutput
    )

    try {
        $status = Get-SfAdMonitorStatus -ConfigPath $ResolvedConfigPath -HistoryLimit $HistoryDepth
        $lines = if ($AsTextOutput) {
            @(Format-SfAdMonitorView -Status $status)
        } else {
            @(Format-SfAdMonitorDashboardView -Status $status -UiState $UiState)
        }
    } catch {
        $lines = @(
            'SuccessFactors AD Sync Dashboard',
            "Config: $ResolvedConfigPath",
            "Refreshed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
            '',
            'Monitor error',
            $_.Exception.Message,
            '',
            'Keys: q quit, r refresh'
        )
        $status = $null
    }

    if ($AsTextOutput) {
        return [pscustomobject]@{
            Status = $status
            Lines = $lines
        }
    }

    Clear-Host
    Write-SfAdStyledMonitorFrame -Lines $lines

    return [pscustomobject]@{
        Status = $status
        Lines = $lines
    }
}

function Write-SfAdStyledMonitorFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $palette = @{
        Header = 'Cyan'
        Border = 'DarkCyan'
        Section = 'Yellow'
        Active = 'Green'
        Warning = 'Yellow'
        Error = 'Red'
        Selection = 'Magenta'
        Muted = 'DarkGray'
        Detail = 'Gray'
        Footer = 'Cyan'
        Default = 'White'
    }

    foreach ($line in $Lines) {
        $color = $palette.Default

        if ($line -match '^[╔╠╚].*[╗╣╝]$' -or $line -match '^─+$') {
            $color = $palette.Border
        } elseif ($line -match '^║ SuccessFactors AD Sync Dashboard') {
            $color = $palette.Header
        } elseif ($line -match '^▓ ') {
            $color = $palette.Section
        } elseif ($line -match '^\s+>\s' -or $line -match '^\s+>') {
            $color = $palette.Selection
        } elseif ($line -match '^Status: .*InProgress' -or $line -match '\[ACTIVE\]') {
            $color = $palette.Active
        } elseif ($line -match '^Status: .*Failed' -or $line -match '\[ERROR\]' -or $line -match '^Error:') {
            $color = $palette.Error
        } elseif ($line -match 'Q=\d*[1-9]\d*' -or $line -match 'F=\d*[1-9]\d*' -or $line -match 'GF=\d*[1-9]\d*' -or $line -match 'MR=\d*[1-9]\d*') {
            $color = $palette.Warning
        } elseif ($line -match '^║ Status:' -or $line -match '^║ Keys:') {
            $color = $palette.Footer
        } elseif ($line -match '^-' -or $line -match '^No entries' -or $line -match '^Command Output$') {
            $color = $palette.Detail
        } elseif ([string]::IsNullOrWhiteSpace($line)) {
            $color = $palette.Muted
        }

        Write-Host $line -ForegroundColor $color
    }
}

function Read-SfAdMonitorFilterText {
    [CmdletBinding()]
    param(
        [string]$CurrentFilter
    )

    Write-Host ''
    Write-Host "Filter current bucket entries. Leave blank to clear the filter." -ForegroundColor Cyan
    $prompt = if ([string]::IsNullOrWhiteSpace($CurrentFilter)) { 'Filter' } else { "Filter [$CurrentFilter]" }
    return Read-Host -Prompt $prompt
}

function Invoke-SfAdMonitorShortcut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Preflight','DryRun','OpenReport','CopyReportPath')]
        [string]$Action,
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState,
        [string]$ResolvedMappingConfigPath
    )

    $context = Get-SfAdMonitorActionContext -Status $Status -UiState $UiState -MappingConfigPath $ResolvedMappingConfigPath
    $projectRoot = Split-Path -Path $PSScriptRoot -Parent

    switch ($Action) {
        'Preflight' {
            if (-not $context.mappingConfigPath) {
                $UiState.statusMessage = 'Preflight unavailable: no mapping config path was provided and none could be inferred from recent runs.'
                $UiState.commandOutput = @()
                return
            }

            try {
                $output = & pwsh -NoLogo -NoProfile -File (Join-Path $projectRoot 'scripts/Invoke-SfAdPreflight.ps1') -ConfigPath $context.configPath -MappingConfigPath $context.mappingConfigPath 2>&1
                $UiState.statusMessage = 'Preflight completed.'
                $UiState.commandOutput = @($output | ForEach-Object { "$_" })
            } catch {
                $UiState.statusMessage = 'Preflight failed.'
                $UiState.commandOutput = @($_.Exception.Message)
            }
        }
        'DryRun' {
            if (-not $context.mappingConfigPath) {
                $UiState.statusMessage = 'Dry-run unavailable: no mapping config path was provided and none could be inferred from recent runs.'
                $UiState.commandOutput = @()
                return
            }

            $argumentList = @(
                '-NoLogo'
                '-NoProfile'
                '-File'
                (Join-Path $projectRoot 'src/Invoke-SfAdSync.ps1')
                '-ConfigPath'
                $context.configPath
                '-MappingConfigPath'
                $context.mappingConfigPath
                '-Mode'
                'Delta'
                '-DryRun'
            )

            try {
                Start-Process -FilePath 'pwsh' -ArgumentList $argumentList | Out-Null
                $UiState.statusMessage = 'Started dry-run sync in a new PowerShell process.'
                $UiState.commandOutput = @("Config=$($context.configPath)", "Mapping=$($context.mappingConfigPath)")
            } catch {
                $UiState.statusMessage = 'Failed to start dry-run sync.'
                $UiState.commandOutput = @($_.Exception.Message)
            }
        }
        'OpenReport' {
            if (-not $context.reportPath) {
                $UiState.statusMessage = 'Open report unavailable: no selected report path.'
                $UiState.commandOutput = @()
                return
            }

            try {
                Start-Process -FilePath $context.reportPath | Out-Null
                $UiState.statusMessage = "Opened report: $($context.reportPath)"
                $UiState.commandOutput = @($context.reportPath)
            } catch {
                $UiState.statusMessage = 'Failed to open report path.'
                $UiState.commandOutput = @($context.reportPath, $_.Exception.Message)
            }
        }
        'CopyReportPath' {
            if (-not $context.reportPath) {
                $UiState.statusMessage = 'Copy report path unavailable: no selected report path.'
                $UiState.commandOutput = @()
                return
            }

            if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) {
                Set-Clipboard -Value $context.reportPath
                $UiState.statusMessage = 'Copied selected report path to clipboard.'
                $UiState.commandOutput = @($context.reportPath)
                return
            }

            $UiState.statusMessage = 'Clipboard command not available. Report path shown below.'
            $UiState.commandOutput = @($context.reportPath)
        }
    }
}

$resolvedConfigPath = (Resolve-Path -Path $ConfigPath).Path
$resolvedMappingConfigPath = Get-OptionalResolvedPath -Path $MappingConfigPath
$uiState = New-SfAdMonitorUiState
$lastStatus = $null

do {
    $frame = Show-SfAdMonitorFrame -ResolvedConfigPath $resolvedConfigPath -ResolvedMappingConfigPath $resolvedMappingConfigPath -HistoryDepth $HistoryLimit -UiState $uiState -AsTextOutput:$AsText
    $lastStatus = $frame.Status

    if ($RunOnce -or $AsText) {
        if ($AsText) {
            $frame.Lines -join [Environment]::NewLine
        }
        break
    }

    $quitRequested = $false
    $refreshRequested = $false
    for ($second = 0; $second -lt $RefreshIntervalSeconds; $second += 1) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'Q' {
                    $quitRequested = $true
                    break
                }
                'R' {
                    $refreshRequested = $true
                    break
                }
                'UpArrow' {
                    $uiState.selectedRunIndex = [math]::Max([int]$uiState.selectedRunIndex - 1, 0)
                    $uiState.focus = 'History'
                    $uiState.statusMessage = 'Selected previous run.'
                    $refreshRequested = $true
                    break
                }
                'DownArrow' {
                    $maxRunIndex = if ($lastStatus) { [math]::Max(@($lastStatus.recentRuns).Count - 1, 0) } else { 0 }
                    $uiState.selectedRunIndex = [math]::Min([int]$uiState.selectedRunIndex + 1, $maxRunIndex)
                    $uiState.focus = 'History'
                    $uiState.statusMessage = 'Selected next run.'
                    $refreshRequested = $true
                    break
                }
                'Tab' {
                    $focusOrder = @('Overview', 'History', 'Detail')
                    $currentIndex = [array]::IndexOf($focusOrder, $uiState.focus)
                    if ($currentIndex -lt 0) {
                        $currentIndex = 0
                    }
                    $uiState.focus = $focusOrder[($currentIndex + 1) % $focusOrder.Count]
                    $uiState.statusMessage = "Focus: $($uiState.focus)"
                    $refreshRequested = $true
                    break
                }
                'Enter' {
                    $uiState.focus = 'Detail'
                    $uiState.statusMessage = 'Inspecting selected run details.'
                    $refreshRequested = $true
                    break
                }
                default {
                    switch ($key.KeyChar) {
                        'j' {
                            $maxRunIndex = if ($lastStatus) { [math]::Max(@($lastStatus.recentRuns).Count - 1, 0) } else { 0 }
                            $uiState.selectedRunIndex = [math]::Min([int]$uiState.selectedRunIndex + 1, $maxRunIndex)
                            $uiState.focus = 'History'
                            $uiState.statusMessage = 'Selected next run.'
                            $refreshRequested = $true
                            break
                        }
                        'k' {
                            $uiState.selectedRunIndex = [math]::Max([int]$uiState.selectedRunIndex - 1, 0)
                            $uiState.focus = 'History'
                            $uiState.statusMessage = 'Selected previous run.'
                            $refreshRequested = $true
                            break
                        }
                        '[' {
                            $uiState.selectedBucketIndex = [math]::Max([int]$uiState.selectedBucketIndex - 1, 0)
                            $uiState.focus = 'Detail'
                            $uiState.statusMessage = 'Selected previous detail bucket.'
                            $refreshRequested = $true
                            break
                        }
                        ']' {
                            $maxBucketIndex = [math]::Max(@(Get-SfAdMonitorBucketDefinitions).Count - 1, 0)
                            $uiState.selectedBucketIndex = [math]::Min([int]$uiState.selectedBucketIndex + 1, $maxBucketIndex)
                            $uiState.focus = 'Detail'
                            $uiState.statusMessage = 'Selected next detail bucket.'
                            $refreshRequested = $true
                            break
                        }
                        'p' {
                            if ($lastStatus) {
                                Invoke-SfAdMonitorShortcut -Action Preflight -Status $lastStatus -UiState $uiState -ResolvedMappingConfigPath $resolvedMappingConfigPath
                            }
                            $refreshRequested = $true
                            break
                        }
                        'd' {
                            if ($lastStatus) {
                                Invoke-SfAdMonitorShortcut -Action DryRun -Status $lastStatus -UiState $uiState -ResolvedMappingConfigPath $resolvedMappingConfigPath
                            }
                            $refreshRequested = $true
                            break
                        }
                        'o' {
                            if ($lastStatus) {
                                Invoke-SfAdMonitorShortcut -Action OpenReport -Status $lastStatus -UiState $uiState -ResolvedMappingConfigPath $resolvedMappingConfigPath
                            }
                            $refreshRequested = $true
                            break
                        }
                        'y' {
                            if ($lastStatus) {
                                Invoke-SfAdMonitorShortcut -Action CopyReportPath -Status $lastStatus -UiState $uiState -ResolvedMappingConfigPath $resolvedMappingConfigPath
                            }
                            $refreshRequested = $true
                            break
                        }
                        '/' {
                            $uiState.focus = 'Detail'
                            $filterText = Read-SfAdMonitorFilterText -CurrentFilter $uiState.filterText
                            $uiState.filterText = if ([string]::IsNullOrWhiteSpace($filterText)) { '' } else { $filterText.Trim() }
                            if ([string]::IsNullOrWhiteSpace($uiState.filterText)) {
                                $uiState.statusMessage = 'Cleared detail filter.'
                            } else {
                                $uiState.statusMessage = "Filter applied: $($uiState.filterText)"
                            }
                            $refreshRequested = $true
                            break
                        }
                        'c' {
                            $uiState.filterText = ''
                            $uiState.statusMessage = 'Cleared detail filter.'
                            $refreshRequested = $true
                            break
                        }
                    }
                }
            }
        }

        if ($quitRequested -or $refreshRequested) {
            break
        }

        Start-Sleep -Seconds 1
    }
} while (-not $quitRequested)
