import request from 'supertest';
import { describe, expect, it } from 'vitest';
import { createApp, createMockStatusProvider } from './app.js';

const dashboardStatus = {
  configPath: '/tmp/config.json',
  latestRun: {
    runId: 'run-1',
    path: '/tmp/run-1.json',
    artifactType: 'WorkerPreview',
    mode: 'Review',
    dryRun: true,
    status: 'Succeeded',
    startedAt: '2026-03-20T10:00:00Z',
    completedAt: '2026-03-20T10:05:00Z',
    durationSeconds: 300,
    reversibleOperations: 1,
    creates: 0,
    updates: 1,
    enables: 0,
    disables: 0,
    graveyardMoves: 0,
    deletions: 0,
    quarantined: 1,
    conflicts: 0,
    guardrailFailures: 0,
    manualReview: 1,
    unchanged: 0,
  },
  currentRun: {
    status: 'Idle',
    stage: 'Completed',
    processedWorkers: 0,
    totalWorkers: 0,
    currentWorkerId: null,
    lastAction: 'No active sync run.',
  },
  recentRuns: [],
  summary: {
    lastCheckpoint: '2026-03-20T10:00:00Z',
    totalTrackedWorkers: 3,
    suppressedWorkers: 1,
    pendingDeletionWorkers: 0,
  },
  health: {
    successFactors: { status: 'OK', detail: 'oauth' },
    activeDirectory: { status: 'OK', detail: 'dc01' },
  },
  trackedWorkers: [],
  context: {},
  paths: {
    configPath: '/tmp/config.json',
    statePath: '/tmp/state.json',
    reportDirectory: '/tmp/reports',
    reviewReportDirectory: '/tmp/review',
    reportDirectories: ['/tmp/reports', '/tmp/review'],
    runtimeStatusPath: '/tmp/runtime-status.json',
  },
  warnings: [],
};

describe('web api', () => {
  it('returns dashboard status', async () => {
    const app = createApp({
      configPath: '/tmp/config.json',
      statusProvider: createMockStatusProvider({
        ...dashboardStatus,
        recentRuns: [dashboardStatus.latestRun],
      }),
    });

    const response = await request(app).get('/api/status');

    expect(response.status).toBe(200);
    expect(response.body.status.latestRun.runId).toBe('run-1');
  });
});
