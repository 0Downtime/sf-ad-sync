Set-StrictMode -Version Latest

function Get-SfAdCollectionCount {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return 0
    }

    return @($Value).Count
}

function Get-SfAdRuntimeStatusPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $directory = Split-Path -Path $StatePath -Parent
    if ([string]::IsNullOrWhiteSpace($directory)) {
        return 'runtime-status.json'
    }

    return Join-Path -Path $directory -ChildPath 'runtime-status.json'
}

function New-SfAdIdleRuntimeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    return [pscustomobject]@{
        runId = $null
        status = 'Idle'
        mode = $null
        dryRun = $false
        stage = 'Completed'
        startedAt = $null
        lastUpdatedAt = $null
        completedAt = $null
        currentWorkerId = $null
        lastAction = 'No active sync run.'
        processedWorkers = 0
        totalWorkers = 0
        creates = 0
        updates = 0
        enables = 0
        disables = 0
        graveyardMoves = 0
        deletions = 0
        quarantined = 0
        conflicts = 0
        guardrailFailures = 0
        manualReview = 0
        unchanged = 0
        errorMessage = $null
        runtimeStatusPath = Get-SfAdRuntimeStatusPath -StatePath $StatePath
    }
}

function New-SfAdRuntimeStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)]
        [string]$StatePath,
        [Parameter(Mandatory)]
        [string]$Stage,
        [string]$Status,
        [int]$ProcessedWorkers = 0,
        [int]$TotalWorkers = 0,
        [string]$CurrentWorkerId,
        [string]$LastAction,
        [string]$CompletedAt,
        [string]$ErrorMessage
    )

    $effectiveStatus = if ($PSBoundParameters.ContainsKey('Status') -and -not [string]::IsNullOrWhiteSpace($Status)) {
        $Status
    } elseif ($Report.Contains('status') -and -not [string]::IsNullOrWhiteSpace("$($Report['status'])")) {
        "$($Report['status'])"
    } else {
        'Idle'
    }

    return [pscustomobject][ordered]@{
        runId = if ($Report.Contains('runId')) { $Report['runId'] } else { $null }
        status = $effectiveStatus
        mode = if ($Report.Contains('mode')) { $Report['mode'] } else { $null }
        dryRun = if ($Report.Contains('dryRun')) { [bool]$Report['dryRun'] } else { $false }
        stage = $Stage
        startedAt = if ($Report.Contains('startedAt')) { $Report['startedAt'] } else { $null }
        lastUpdatedAt = (Get-Date).ToString('o')
        completedAt = $CompletedAt
        currentWorkerId = $CurrentWorkerId
        lastAction = $LastAction
        processedWorkers = $ProcessedWorkers
        totalWorkers = $TotalWorkers
        creates = if ($Report.Contains('creates')) { Get-SfAdCollectionCount -Value $Report['creates'] } else { 0 }
        updates = if ($Report.Contains('updates')) { Get-SfAdCollectionCount -Value $Report['updates'] } else { 0 }
        enables = if ($Report.Contains('enables')) { Get-SfAdCollectionCount -Value $Report['enables'] } else { 0 }
        disables = if ($Report.Contains('disables')) { Get-SfAdCollectionCount -Value $Report['disables'] } else { 0 }
        graveyardMoves = if ($Report.Contains('graveyardMoves')) { Get-SfAdCollectionCount -Value $Report['graveyardMoves'] } else { 0 }
        deletions = if ($Report.Contains('deletions')) { Get-SfAdCollectionCount -Value $Report['deletions'] } else { 0 }
        quarantined = if ($Report.Contains('quarantined')) { Get-SfAdCollectionCount -Value $Report['quarantined'] } else { 0 }
        conflicts = if ($Report.Contains('conflicts')) { Get-SfAdCollectionCount -Value $Report['conflicts'] } else { 0 }
        guardrailFailures = if ($Report.Contains('guardrailFailures')) { Get-SfAdCollectionCount -Value $Report['guardrailFailures'] } else { 0 }
        manualReview = if ($Report.Contains('manualReview')) { Get-SfAdCollectionCount -Value $Report['manualReview'] } else { 0 }
        unchanged = if ($Report.Contains('unchanged')) { Get-SfAdCollectionCount -Value $Report['unchanged'] } else { 0 }
        errorMessage = $ErrorMessage
        runtimeStatusPath = Get-SfAdRuntimeStatusPath -StatePath $StatePath
    }
}

function Save-SfAdRuntimeStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Snapshot,
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $runtimeStatusPath = Get-SfAdRuntimeStatusPath -StatePath $StatePath
    $runtimeDirectory = Split-Path -Path $runtimeStatusPath -Parent
    if ($runtimeDirectory -and -not (Test-Path -Path $runtimeDirectory -PathType Container)) {
        New-Item -Path $runtimeDirectory -ItemType Directory -Force | Out-Null
    }

    $Snapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $runtimeStatusPath
    return $runtimeStatusPath
}

function Write-SfAdRuntimeStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)]
        [string]$StatePath,
        [Parameter(Mandatory)]
        [string]$Stage,
        [string]$Status,
        [int]$ProcessedWorkers = 0,
        [int]$TotalWorkers = 0,
        [string]$CurrentWorkerId,
        [string]$LastAction,
        [string]$CompletedAt,
        [string]$ErrorMessage
    )

    $snapshot = New-SfAdRuntimeStatusSnapshot -Report $Report -StatePath $StatePath -Stage $Stage -Status $Status -ProcessedWorkers $ProcessedWorkers -TotalWorkers $TotalWorkers -CurrentWorkerId $CurrentWorkerId -LastAction $LastAction -CompletedAt $CompletedAt -ErrorMessage $ErrorMessage
    [void](Save-SfAdRuntimeStatusSnapshot -Snapshot $snapshot -StatePath $StatePath)
    return $snapshot
}

function Get-SfAdRuntimeStatusSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $runtimeStatusPath = Get-SfAdRuntimeStatusPath -StatePath $StatePath
    if (-not (Test-Path -Path $runtimeStatusPath -PathType Leaf)) {
        return $null
    }

    return Get-Content -Path $runtimeStatusPath -Raw | ConvertFrom-Json -Depth 20
}

function Get-SfAdWorkerEntries {
    [CmdletBinding()]
    param($Workers)

    if ($null -eq $Workers) {
        return @()
    }

    if ($Workers -is [System.Collections.IDictionary]) {
        return @(
            foreach ($key in $Workers.Keys) {
                [pscustomobject]@{
                    Name = $key
                    Value = $Workers[$key]
                }
            }
        )
    }

    return @($Workers.PSObject.Properties | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Value = $_.Value
        }
    })
}

function Get-SfAdDateTimeOrNull {
    [CmdletBinding()]
    param($Value)

    if ([string]::IsNullOrWhiteSpace("$Value")) {
        return $null
    }

    try {
        return [datetimeoffset](Get-Date $Value)
    } catch {
        return $null
    }
}

function Get-SfAdDurationSeconds {
    [CmdletBinding()]
    param(
        $StartedAt,
        $CompletedAt
    )

    $start = Get-SfAdDateTimeOrNull -Value $StartedAt
    $end = Get-SfAdDateTimeOrNull -Value $CompletedAt
    if ($null -eq $start -or $null -eq $end) {
        return $null
    }

    return [int][math]::Max(0, [math]::Round(($end - $start).TotalSeconds))
}

function New-SfAdEmptyRunSummary {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        runId = $null
        path = $null
        mode = $null
        dryRun = $false
        status = $null
        startedAt = $null
        completedAt = $null
        durationSeconds = $null
        reversibleOperations = 0
        creates = 0
        updates = 0
        enables = 0
        disables = 0
        graveyardMoves = 0
        deletions = 0
        quarantined = 0
        conflicts = 0
        guardrailFailures = 0
        manualReview = 0
        unchanged = 0
    }
}

function ConvertTo-SfAdRunSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [pscustomobject]$Report
    )

    return [pscustomobject]@{
        runId = if ($Report.PSObject.Properties.Name -contains 'runId') { $Report.runId } else { $null }
        path = $Path
        configPath = if ($Report.PSObject.Properties.Name -contains 'configPath') { $Report.configPath } else { $null }
        mappingConfigPath = if ($Report.PSObject.Properties.Name -contains 'mappingConfigPath') { $Report.mappingConfigPath } else { $null }
        mode = if ($Report.PSObject.Properties.Name -contains 'mode') { $Report.mode } else { $null }
        dryRun = if ($Report.PSObject.Properties.Name -contains 'dryRun') { [bool]$Report.dryRun } else { $false }
        status = if ($Report.PSObject.Properties.Name -contains 'status') { $Report.status } else { $null }
        startedAt = if ($Report.PSObject.Properties.Name -contains 'startedAt') { $Report.startedAt } else { $null }
        completedAt = if ($Report.PSObject.Properties.Name -contains 'completedAt') { $Report.completedAt } else { $null }
        durationSeconds = Get-SfAdDurationSeconds -StartedAt $(if ($Report.PSObject.Properties.Name -contains 'startedAt') { $Report.startedAt } else { $null }) -CompletedAt $(if ($Report.PSObject.Properties.Name -contains 'completedAt') { $Report.completedAt } else { $null })
        reversibleOperations = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'operations') { $Report.operations } else { @() })
        creates = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'creates') { $Report.creates } else { @() })
        updates = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'updates') { $Report.updates } else { @() })
        enables = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'enables') { $Report.enables } else { @() })
        disables = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'disables') { $Report.disables } else { @() })
        graveyardMoves = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'graveyardMoves') { $Report.graveyardMoves } else { @() })
        deletions = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'deletions') { $Report.deletions } else { @() })
        quarantined = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'quarantined') { $Report.quarantined } else { @() })
        conflicts = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'conflicts') { $Report.conflicts } else { @() })
        guardrailFailures = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'guardrailFailures') { $Report.guardrailFailures } else { @() })
        manualReview = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'manualReview') { $Report.manualReview } else { @() })
        unchanged = Get-SfAdCollectionCount -Value $(if ($Report.PSObject.Properties.Name -contains 'unchanged') { $Report.unchanged } else { @() })
    }
}

function Get-SfAdRecentRunSummaries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,
        [ValidateRange(1, 1000)]
        [int]$Limit = 10
    )

    if (-not (Test-Path -Path $Directory -PathType Container)) {
        return @()
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    return @(
        Get-ChildItem -Path $Directory -Filter 'sf-ad-sync-*.json' -File |
            Sort-Object `
                @{ Expression = {
                        if ($_.BaseName -match '(\d{8}-\d{6})$') {
                            return [datetime]::ParseExact($Matches[1], 'yyyyMMdd-HHmmss', $culture)
                        }

                        return $_.LastWriteTime
                    }; Descending = $true }, `
                @{ Expression = { $_.Name }; Descending = $true } |
            Select-Object -First $Limit |
            ForEach-Object {
                $report = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json -Depth 20
                ConvertTo-SfAdRunSummary -Path $_.FullName -Report $report
            }
    )
}

function Get-SfAdMonitorStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,
        [ValidateRange(1, 1000)]
        [int]$HistoryLimit = 10
    )

    $config = Get-SfAdSyncConfig -Path $ConfigPath
    $state = if ($config.state.path) { Get-SfAdSyncState -Path $config.state.path } else { [pscustomobject]@{ checkpoint = $null; workers = @{} } }
    $workerProperties = @(Get-SfAdWorkerEntries -Workers $state.workers)
    $suppressedWorkers = @($workerProperties | Where-Object { $_.Value.suppressed })
    $pendingDeletionWorkers = @(
        $suppressedWorkers | Where-Object {
            $_.Value.deleteAfter -and ((Get-Date $_.Value.deleteAfter) -le (Get-Date))
        }
    )

    $recentRuns = @(Get-SfAdRecentRunSummaries -Directory $config.reporting.outputDirectory -Limit $HistoryLimit)
    $latestRun = if ($recentRuns.Count -gt 0) { $recentRuns[0] } else { New-SfAdEmptyRunSummary }
    $currentRun = Get-SfAdRuntimeStatusSnapshot -StatePath $config.state.path
    if (-not $currentRun) {
        $currentRun = New-SfAdIdleRuntimeStatus -StatePath $config.state.path
    }

    $resolvedConfigPath = (Resolve-Path -Path $ConfigPath).Path
    return [pscustomobject]@{
        configPath = $resolvedConfigPath
        lastCheckpoint = $state.checkpoint
        totalTrackedWorkers = $workerProperties.Count
        suppressedWorkers = $suppressedWorkers.Count
        pendingDeletionWorkers = $pendingDeletionWorkers.Count
        latestReport = $latestRun
        latestRun = $latestRun
        currentRun = $currentRun
        recentRuns = $recentRuns
        summary = [pscustomobject]@{
            lastCheckpoint = $state.checkpoint
            totalTrackedWorkers = $workerProperties.Count
            suppressedWorkers = $suppressedWorkers.Count
            pendingDeletionWorkers = $pendingDeletionWorkers.Count
        }
        paths = [pscustomobject]@{
            configPath = $resolvedConfigPath
            statePath = $config.state.path
            reportDirectory = $config.reporting.outputDirectory
            runtimeStatusPath = Get-SfAdRuntimeStatusPath -StatePath $config.state.path
        }
    }
}

function Format-SfAdMonitorView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('SuccessFactors AD Sync Monitor')
    $lines.Add("Config: $($Status.paths.configPath)")
    $lines.Add("Refreshed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))")
    $lines.Add('')
    $lines.Add('Current Run')
    $lines.Add("Status: $($Status.currentRun.status)    Stage: $($Status.currentRun.stage)    Mode: $($Status.currentRun.mode)    DryRun: $($Status.currentRun.dryRun)")
    $lines.Add("Started: $($Status.currentRun.startedAt)    Completed: $($Status.currentRun.completedAt)")
    $lines.Add("Progress: $($Status.currentRun.processedWorkers) / $($Status.currentRun.totalWorkers)    Worker: $($Status.currentRun.currentWorkerId)")
    $lines.Add("Last action: $($Status.currentRun.lastAction)")
    if ($Status.currentRun.errorMessage) {
        $lines.Add("Error: $($Status.currentRun.errorMessage)")
    }
    $lines.Add("Counts: C=$($Status.currentRun.creates) U=$($Status.currentRun.updates) E=$($Status.currentRun.enables) D=$($Status.currentRun.disables) G=$($Status.currentRun.graveyardMoves) X=$($Status.currentRun.deletions) Q=$($Status.currentRun.quarantined) F=$($Status.currentRun.conflicts) GF=$($Status.currentRun.guardrailFailures) MR=$($Status.currentRun.manualReview) NC=$($Status.currentRun.unchanged)")
    $lines.Add('')
    $lines.Add('State Summary')
    $lines.Add("Checkpoint: $($Status.summary.lastCheckpoint)")
    $lines.Add("Tracked: $($Status.summary.totalTrackedWorkers)    Suppressed: $($Status.summary.suppressedWorkers)    Pending deletion: $($Status.summary.pendingDeletionWorkers)")
    $lines.Add('')
    $lines.Add('Recent Runs')
    $lines.Add('Status     Mode  Started             Dur(s) Create Update Disable Delete Conflict Guardrail')
    foreach ($run in @($Status.recentRuns)) {
        $lines.Add(("{0,-10} {1,-5} {2,-19} {3,6} {4,6} {5,6} {6,7} {7,6} {8,8} {9,9}" -f `
                $(if ($run.status) { $run.status } else { '-' }), `
                $(if ($run.mode) { $run.mode } else { '-' }), `
                $(if ($run.startedAt) { $run.startedAt } else { '-' }), `
                $(if ($null -ne $run.durationSeconds) { $run.durationSeconds } else { '-' }), `
                $run.creates, `
                $run.updates, `
                $run.disables, `
                $run.deletions, `
                $run.conflicts, `
                $run.guardrailFailures))
    }

    if (@($Status.recentRuns).Count -eq 0) {
        $lines.Add('No sync reports found.')
    }

    $lines.Add('')
    $lines.Add('Keys: q quit, r refresh')
    return $lines
}

function New-SfAdMonitorUiState {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        selectedRunIndex = 0
        selectedBucketIndex = 0
        focus = 'History'
        statusMessage = 'Ready. Keys: q quit, r refresh, tab focus, arrows or j/k select run, [ ] bucket, p preflight, d dry-run, o open path, y copy path.'
        commandOutput = @()
    }
}

function Get-SfAdMonitorBucketDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Name = 'quarantined'; Label = 'Quarantined' }
        [pscustomobject]@{ Name = 'conflicts'; Label = 'Conflicts' }
        [pscustomobject]@{ Name = 'manualReview'; Label = 'Manual Review' }
        [pscustomobject]@{ Name = 'guardrailFailures'; Label = 'Guardrails' }
        [pscustomobject]@{ Name = 'creates'; Label = 'Creates' }
        [pscustomobject]@{ Name = 'updates'; Label = 'Updates' }
    )
}

function Get-SfAdMonitorSelectedRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState
    )

    $runs = @($Status.recentRuns)
    if ($runs.Count -eq 0) {
        return $Status.latestRun
    }

    $index = [math]::Min([math]::Max([int]$UiState.selectedRunIndex, 0), $runs.Count - 1)
    return $runs[$index]
}

function Get-SfAdMonitorSelectedRunReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState
    )

    $selectedRun = Get-SfAdMonitorSelectedRun -Status $Status -UiState $UiState
    if (-not $selectedRun -or [string]::IsNullOrWhiteSpace("$($selectedRun.path)")) {
        return $null
    }

    return Get-Content -Path $selectedRun.path -Raw | ConvertFrom-Json -Depth 20
}

function Get-SfAdMonitorSelectedBucket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState
    )

    $buckets = @(Get-SfAdMonitorBucketDefinitions)
    $index = if ($buckets.Count -eq 0) { 0 } else { [math]::Min([math]::Max([int]$UiState.selectedBucketIndex, 0), $buckets.Count - 1) }
    $bucket = if ($buckets.Count -eq 0) { [pscustomobject]@{ Name = 'quarantined'; Label = 'Quarantined' } } else { $buckets[$index] }

    $report = Get-SfAdMonitorSelectedRunReport -Status $Status -UiState $UiState
    $items = @()
    if ($report -and $report.PSObject.Properties.Name -contains $bucket.Name) {
        $items = @($report.$($bucket.Name))
    }

    return [pscustomobject]@{
        Bucket = $bucket
        Items = $items
    }
}

function Resolve-SfAdMonitorMappingConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [string]$MappingConfigPath
    )

    if (-not [string]::IsNullOrWhiteSpace($MappingConfigPath)) {
        return (Resolve-Path -Path $MappingConfigPath).Path
    }

    foreach ($run in @($Status.recentRuns)) {
        if ($run -and $run.PSObject.Properties.Name -contains 'mappingConfigPath' -and -not [string]::IsNullOrWhiteSpace("$($run.mappingConfigPath)") -and (Test-Path -Path $run.mappingConfigPath -PathType Leaf)) {
            return (Resolve-Path -Path $run.mappingConfigPath).Path
        }
    }

    return $null
}

function Resolve-SfAdMonitorSelectedReportPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState
    )

    $selectedRun = Get-SfAdMonitorSelectedRun -Status $Status -UiState $UiState
    if (-not $selectedRun -or [string]::IsNullOrWhiteSpace("$($selectedRun.path)")) {
        return $null
    }

    return $selectedRun.path
}

function Get-SfAdMonitorActionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState,
        [string]$MappingConfigPath
    )

    $selectedRun = Get-SfAdMonitorSelectedRun -Status $Status -UiState $UiState
    return [pscustomobject]@{
        configPath = $Status.paths.configPath
        mappingConfigPath = Resolve-SfAdMonitorMappingConfigPath -Status $Status -MappingConfigPath $MappingConfigPath
        reportPath = Resolve-SfAdMonitorSelectedReportPath -Status $Status -UiState $UiState
        selectedRun = $selectedRun
        selectedBucket = Get-SfAdMonitorSelectedBucket -Status $Status -UiState $UiState
    }
}

function ConvertTo-SfAdMonitorInlineText {
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) {
        return ''
    }

    if ($Value -is [System.Array]) {
        return (@($Value) -join ', ')
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return (@($Value.Keys | ForEach-Object { "$_=$($Value[$_])" }) -join ', ')
    }

    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 0 -and -not ($Value -is [string])) {
        return (@($properties | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')
    }

    return "$Value"
}

function Format-SfAdMonitorDashboardView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Status,
        [Parameter(Mandatory)]
        [pscustomobject]$UiState
    )

    $selectedRun = Get-SfAdMonitorSelectedRun -Status $Status -UiState $UiState
    $selectedBucket = Get-SfAdMonitorSelectedBucket -Status $Status -UiState $UiState
    $bucketIndex = [math]::Min([math]::Max([int]$UiState.selectedBucketIndex, 0), (@(Get-SfAdMonitorBucketDefinitions).Count - 1))
    $lines = [System.Collections.Generic.List[string]]::new()
    $panelWidth = 110
    $topBorder = "╔" + ("═" * ($panelWidth - 2)) + "╗"
    $midBorder = "╠" + ("═" * ($panelWidth - 2)) + "╣"
    $bottomBorder = "╚" + ("═" * ($panelWidth - 2)) + "╝"
    $rule = "─" * $panelWidth

    $latestState = if ($Status.latestRun.status -eq 'Failed' -or $Status.currentRun.errorMessage) { 'ERROR' } elseif ($Status.currentRun.status -eq 'InProgress') { 'ACTIVE' } else { 'OK' }
    $lines.Add($topBorder)
    $lines.Add("║ SuccessFactors AD Sync Dashboard [$latestState]")
    $lines.Add("║ Config: $($Status.paths.configPath)")
    $lines.Add("║ Refreshed: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))    Focus: $($UiState.focus)    Selected run: $([math]::Min([int]$UiState.selectedRunIndex + 1, [math]::Max(@($Status.recentRuns).Count, 1))) / $([math]::Max(@($Status.recentRuns).Count, 1))    Bucket: $($selectedBucket.Bucket.Label)")
    $lines.Add($midBorder)
    $lines.Add('▓ Current Run')
    $lines.Add("Status: $($Status.currentRun.status)    Stage: $($Status.currentRun.stage)    Mode: $($Status.currentRun.mode)    DryRun: $($Status.currentRun.dryRun)")
    $lines.Add("Started: $($Status.currentRun.startedAt)    Progress: $($Status.currentRun.processedWorkers) / $($Status.currentRun.totalWorkers)    Worker: $($Status.currentRun.currentWorkerId)")
    $lines.Add("Last action: $($Status.currentRun.lastAction)")
    if ($Status.currentRun.errorMessage) {
        $lines.Add("Error: $($Status.currentRun.errorMessage)")
    }
    $lines.Add("Live counts: C=$($Status.currentRun.creates) U=$($Status.currentRun.updates) E=$($Status.currentRun.enables) D=$($Status.currentRun.disables) G=$($Status.currentRun.graveyardMoves) X=$($Status.currentRun.deletions) Q=$($Status.currentRun.quarantined) F=$($Status.currentRun.conflicts) GF=$($Status.currentRun.guardrailFailures) MR=$($Status.currentRun.manualReview) NC=$($Status.currentRun.unchanged)")
    $lines.Add($rule)
    $lines.Add('▓ Latest Run Summary')
    $lines.Add("Status: $($Status.latestRun.status)    Mode: $($Status.latestRun.mode)    DryRun: $($Status.latestRun.dryRun)    Started: $($Status.latestRun.startedAt)")
    $lines.Add("Duration(s): $($Status.latestRun.durationSeconds)    Reversible ops: $($Status.latestRun.reversibleOperations)")
    $lines.Add("Totals: C=$($Status.latestRun.creates) U=$($Status.latestRun.updates) E=$($Status.latestRun.enables) D=$($Status.latestRun.disables) G=$($Status.latestRun.graveyardMoves) X=$($Status.latestRun.deletions) Q=$($Status.latestRun.quarantined) F=$($Status.latestRun.conflicts) GF=$($Status.latestRun.guardrailFailures) MR=$($Status.latestRun.manualReview) NC=$($Status.latestRun.unchanged)")
    $lines.Add($rule)
    $lines.Add('▓ State Summary')
    $lines.Add("Checkpoint: $($Status.summary.lastCheckpoint)")
    $lines.Add("Tracked: $($Status.summary.totalTrackedWorkers)    Suppressed: $($Status.summary.suppressedWorkers)    Pending deletion: $($Status.summary.pendingDeletionWorkers)")
    $lines.Add($rule)
    $lines.Add('▓ Recent Runs')
    $lines.Add(' Sel Status     Mode  Dry  Started             Dur(s) Create Update Disable Delete Conflict Guardrail')
    $runs = @($Status.recentRuns)
    if ($runs.Count -eq 0) {
        $lines.Add('  -  No sync reports found.')
    } else {
        for ($i = 0; $i -lt $runs.Count; $i += 1) {
            $run = $runs[$i]
            $marker = if ($i -eq [math]::Min([math]::Max([int]$UiState.selectedRunIndex, 0), $runs.Count - 1)) { ' > ' } else { '   ' }
            $lines.Add(("{0}{1,-10} {2,-5} {3,-4} {4,-19} {5,6} {6,6} {7,6} {8,7} {9,6} {10,8} {11,9}" -f `
                    $marker, `
                    $(if ($run.status) { $run.status } else { '-' }), `
                    $(if ($run.mode) { $run.mode } else { '-' }), `
                    $(if ($run.dryRun) { 'yes' } else { 'no' }), `
                    $(if ($run.startedAt) { $run.startedAt } else { '-' }), `
                    $(if ($null -ne $run.durationSeconds) { $run.durationSeconds } else { '-' }), `
                    $run.creates, `
                    $run.updates, `
                    $run.disables, `
                    $run.deletions, `
                    $run.conflicts, `
                    $run.guardrailFailures))
        }
    }

    $lines.Add($rule)
    $lines.Add("▓ Detail: $($selectedBucket.Bucket.Label) for $(if ($selectedRun.runId) { $selectedRun.runId } else { 'no-run' })")
    if (@($selectedBucket.Items).Count -eq 0) {
        $lines.Add('No entries in the selected bucket.')
    } else {
        foreach ($item in @($selectedBucket.Items) | Select-Object -First 8) {
            $lines.Add("- $(ConvertTo-SfAdMonitorInlineText -Value $item)")
        }

        if (@($selectedBucket.Items).Count -gt 8) {
            $lines.Add("... $(@($selectedBucket.Items).Count - 8) more")
        }
    }

    if (@($UiState.commandOutput).Count -gt 0) {
        $lines.Add($rule)
        $lines.Add('▓ Command Output')
        foreach ($line in @($UiState.commandOutput) | Select-Object -First 6) {
            $lines.Add($line)
        }
    }

    $lines.Add($midBorder)
    $lines.Add("║ Status: $($UiState.statusMessage)")
    $lines.Add('║ Keys: q quit, r refresh, tab focus, up/down or j/k select run, [ or ] bucket, enter inspect, p preflight, d dry-run, o open report, y copy report path')
    $lines.Add($bottomBorder)
    return $lines
}

Export-ModuleMember -Function Get-SfAdRuntimeStatusPath, New-SfAdIdleRuntimeStatus, New-SfAdRuntimeStatusSnapshot, Save-SfAdRuntimeStatusSnapshot, Write-SfAdRuntimeStatusSnapshot, Get-SfAdRuntimeStatusSnapshot, Get-SfAdRecentRunSummaries, Get-SfAdMonitorStatus, Format-SfAdMonitorView, New-SfAdMonitorUiState, Get-SfAdMonitorBucketDefinitions, Get-SfAdMonitorSelectedRun, Get-SfAdMonitorSelectedRunReport, Get-SfAdMonitorSelectedBucket, Resolve-SfAdMonitorMappingConfigPath, Resolve-SfAdMonitorSelectedReportPath, Get-SfAdMonitorActionContext, Format-SfAdMonitorDashboardView
