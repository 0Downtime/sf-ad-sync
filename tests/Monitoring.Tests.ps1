Describe 'Monitoring module' {
    BeforeAll {
        Import-Module "$PSScriptRoot/../src/Modules/SfAdSync/Monitoring.psm1" -Force
    }

    It 'includes config and mapping paths in run summaries' {
        $reportDirectory = Join-Path $TestDrive 'reports'
        $reportPath = Join-Path $reportDirectory 'sf-ad-sync-Delta-20260312-220000.json'
        New-Item -Path $reportDirectory -ItemType Directory -Force | Out-Null

        @{
            runId = 'run-123'
            configPath = 'config.json'
            mappingConfigPath = 'mapping.json'
            mode = 'Delta'
            dryRun = $false
            startedAt = '2026-03-12T21:30:00'
            completedAt = '2026-03-12T21:35:00'
            status = 'Succeeded'
            operations = @()
            creates = @()
            updates = @()
            enables = @()
            disables = @()
            graveyardMoves = @()
            deletions = @()
            quarantined = @()
            conflicts = @()
            guardrailFailures = @()
            manualReview = @()
            unchanged = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath

        $result = @(Get-SfAdRecentRunSummaries -Directory $reportDirectory -Limit 5)

        $result[0].configPath | Should -Be 'config.json'
        $result[0].mappingConfigPath | Should -Be 'mapping.json'
    }

    It 'resolves mapping config path from recent runs when no override is provided' {
        $mappingPath = Join-Path $TestDrive 'mapping.json'
        '{}' | Set-Content -Path $mappingPath

        $status = [pscustomobject]@{
            recentRuns = @(
                [pscustomobject]@{
                    mappingConfigPath = $mappingPath
                }
            )
        }

        $resolved = Resolve-SfAdMonitorMappingConfigPath -Status $status

        $resolved | Should -Be (Resolve-Path -Path $mappingPath).Path
    }

    It 'includes all operation buckets in the dashboard browser' {
        $bucketNames = @(Get-SfAdMonitorBucketDefinitions | ForEach-Object { $_.Name })

        $bucketNames | Should -Contain 'creates'
        $bucketNames | Should -Contain 'updates'
        $bucketNames | Should -Contain 'enables'
        $bucketNames | Should -Contain 'disables'
        $bucketNames | Should -Contain 'graveyardMoves'
        $bucketNames | Should -Contain 'deletions'
        $bucketNames | Should -Contain 'unchanged'
    }

    It 'filters selected bucket items by text across object fields' {
        $bucketSelection = [pscustomobject]@{
            Bucket = [pscustomobject]@{
                Name = 'creates'
                Label = 'Creates'
            }
            Items = @(
                [pscustomobject]@{ workerId = '1001'; samAccountName = 'jdoe'; department = 'Sales' }
                [pscustomobject]@{ workerId = '1002'; samAccountName = 'asmith'; department = 'Finance' }
            )
        }
        $uiState = New-SfAdMonitorUiState
        $uiState.filterText = 'finance'

        $items = @(Get-SfAdMonitorFilteredBucketItems -BucketSelection $bucketSelection -UiState $uiState)

        $items.Count | Should -Be 1
        $items[0].workerId | Should -Be '1002'
    }

    It 'formats dashboard view with selected run and selected bucket details' {
        $reportPath = Join-Path $TestDrive 'sf-ad-sync-Delta-20260312-220000.json'
        @{
            runId = 'run-123'
            configPath = 'config.json'
            mappingConfigPath = 'mapping.json'
            mode = 'Delta'
            dryRun = $true
            startedAt = '2026-03-12T21:30:00'
            completedAt = '2026-03-12T21:35:00'
            status = 'Succeeded'
            operations = @()
            creates = @(@{ workerId = '1001'; samAccountName = 'jdoe' })
            updates = @()
            enables = @()
            disables = @(@{ workerId = '1004'; samAccountName = 'legacy.user'; targetState = 'Disabled' })
            graveyardMoves = @()
            deletions = @()
            quarantined = @(@{ workerId = '1002'; reason = 'ManagerNotResolved' })
            conflicts = @()
            guardrailFailures = @()
            manualReview = @()
            unchanged = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $reportPath

        $status = [pscustomobject]@{
            paths = [pscustomobject]@{
                configPath = 'config.json'
            }
            currentRun = [pscustomobject]@{
                status = 'InProgress'
                stage = 'ProcessingWorkers'
                mode = 'Delta'
                dryRun = $true
                startedAt = '2026-03-12T21:40:00'
                processedWorkers = 3
                totalWorkers = 5
                currentWorkerId = '1003'
                lastAction = 'Updated attributes for worker 1003.'
                errorMessage = $null
                creates = 1
                updates = 1
                enables = 0
                disables = 0
                graveyardMoves = 0
                deletions = 0
                quarantined = 1
                conflicts = 0
                guardrailFailures = 0
                manualReview = 0
                unchanged = 1
            }
            latestRun = [pscustomobject]@{
                status = 'Succeeded'
                mode = 'Delta'
                dryRun = $true
                startedAt = '2026-03-12T21:30:00'
                durationSeconds = 300
                reversibleOperations = 0
                creates = 1
                updates = 0
                enables = 0
                disables = 0
                graveyardMoves = 0
                deletions = 0
                quarantined = 1
                conflicts = 0
                guardrailFailures = 0
                manualReview = 0
                unchanged = 0
            }
            summary = [pscustomobject]@{
                lastCheckpoint = '2026-03-12T21:00:00'
                totalTrackedWorkers = 10
                suppressedWorkers = 1
                pendingDeletionWorkers = 0
            }
            recentRuns = @(
                [pscustomobject]@{
                    runId = 'run-123'
                    path = $reportPath
                    configPath = 'config.json'
                    mappingConfigPath = 'mapping.json'
                    status = 'Succeeded'
                    mode = 'Delta'
                    dryRun = $true
                    startedAt = '2026-03-12T21:30:00'
                    durationSeconds = 300
                    creates = 1
                    updates = 0
                    disables = 0
                    deletions = 0
                    conflicts = 0
                    guardrailFailures = 0
                }
            )
        }
        $uiState = New-SfAdMonitorUiState
        $uiState.filterText = 'manager'

        $lines = @(Format-SfAdMonitorDashboardView -Status $status -UiState $uiState)

        ($lines -join "`n") | Should -Match 'SuccessFactors AD Sync Dashboard'
        ($lines -join "`n") | Should -Match 'Detail: Quarantined'
        ($lines -join "`n") | Should -Match 'Filter: manager'
        ($lines -join "`n") | Should -Match 'workerId=1002'
    }
}
