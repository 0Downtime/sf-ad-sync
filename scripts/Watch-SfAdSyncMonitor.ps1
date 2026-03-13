[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath,
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

function Show-SfAdMonitorFrame {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ResolvedConfigPath,
        [Parameter(Mandatory)]
        [int]$HistoryDepth,
        [switch]$AsTextOutput
    )

    try {
        $status = Get-SfAdMonitorStatus -ConfigPath $ResolvedConfigPath -HistoryLimit $HistoryDepth
        $lines = @(Format-SfAdMonitorView -Status $status)
    } catch {
        $lines = @(
            'SuccessFactors AD Sync Monitor',
            "Config: $ResolvedConfigPath",
            "Refreshed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
            '',
            'Monitor error',
            $_.Exception.Message,
            '',
            'Keys: q quit, r refresh'
        )
    }

    if ($AsTextOutput) {
        $lines -join [Environment]::NewLine
        return
    }

    Clear-Host
    foreach ($line in $lines) {
        Write-Host $line
    }
}

$resolvedConfigPath = (Resolve-Path -Path $ConfigPath).Path

do {
    Show-SfAdMonitorFrame -ResolvedConfigPath $resolvedConfigPath -HistoryDepth $HistoryLimit -AsTextOutput:$AsText

    if ($RunOnce -or $AsText) {
        break
    }

    $quitRequested = $false
    for ($second = 0; $second -lt $RefreshIntervalSeconds; $second += 1) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Q') {
                $quitRequested = $true
                break
            }

            if ($key.Key -eq 'R') {
                break
            }
        }

        Start-Sleep -Seconds 1
    }
} while (-not $quitRequested)
