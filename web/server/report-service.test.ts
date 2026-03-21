import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';
import { ReportService } from './report-service.js';
import type { DashboardStatus, RunSummary } from './types.js';

const tempPaths: string[] = [];

async function writeReport(report: Record<string, unknown>) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'syncfactors-web-'));
  tempPaths.push(directory);
  const reportPath = path.join(directory, 'syncfactors-run.json');
  await fs.writeFile(reportPath, JSON.stringify(report));
  return reportPath;
}

afterEach(async () => {
  await Promise.all(tempPaths.splice(0).map((tempPath) => fs.rm(tempPath, { recursive: true, force: true })));
});

describe('ReportService', () => {
  it('loads one report and filters entries by bucket and text', async () => {
    const reportPath = await writeReport({
      runId: 'run-1',
      updates: [
        {
          workerId: '1001',
          samAccountName: 'jdoe',
          reason: 'AttributeDelta',
          reviewCaseType: 'RehireCase',
          operatorActionSummary: 'Review before retry.',
          operatorActions: [{ label: 'Confirm account reuse', description: 'Reuse the former account.' }],
        },
      ],
      manualReview: [],
      quarantined: [],
      conflicts: [],
      guardrailFailures: [],
      creates: [],
      enables: [],
      disables: [],
      graveyardMoves: [],
      deletions: [],
      unchanged: [],
    });

    const run: RunSummary = {
      runId: 'run-1',
      path: reportPath,
      artifactType: 'WorkerPreview',
      mode: 'Review',
      dryRun: true,
      status: 'Succeeded',
      startedAt: '2026-03-20T10:00:00Z',
      completedAt: '2026-03-20T10:05:00Z',
      durationSeconds: 300,
      reversibleOperations: 0,
      creates: 0,
      updates: 1,
      enables: 0,
      disables: 0,
      graveyardMoves: 0,
      deletions: 0,
      quarantined: 0,
      conflicts: 0,
      guardrailFailures: 0,
      manualReview: 0,
      unchanged: 0,
    };

    const status = {
      recentRuns: [run],
    } as DashboardStatus;

    const service = new ReportService();
    const detail = await service.getRun(status, 'run-1');
    const entries = await service.getRunEntries(status, 'run-1', { bucket: 'updates', filter: 'rehire' });
    const workerHistory = await service.getWorkerHistory(status, '1001');

    expect(detail.bucketCounts.updates).toBe(1);
    expect(entries.entries).toHaveLength(1);
    expect(entries.entries[0].operatorActions[0]?.label).toBe('Confirm account reuse');
    expect(workerHistory.entries).toHaveLength(1);
  });
});
