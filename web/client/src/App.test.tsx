// @vitest-environment jsdom
import { render, screen, waitFor } from '@testing-library/react';
import { vi } from 'vitest';
import { App } from './App.js';

vi.mock('./api.js', () => ({
  getStatus: vi.fn(async () => ({
    latestRun: {
      runId: 'run-1',
      path: '/tmp/run-1.json',
      artifactType: 'WorkerPreview',
      mode: 'Review',
      dryRun: true,
      status: 'Succeeded',
      startedAt: '2026-03-20T10:00:00Z',
      durationSeconds: 300,
      creates: 0,
      updates: 1,
      enables: 0,
      disables: 0,
      deletions: 0,
      quarantined: 0,
      conflicts: 0,
      guardrailFailures: 0,
      manualReview: 1,
      unchanged: 0,
    },
    currentRun: {
      status: 'InProgress',
      stage: 'ProcessingWorkers',
      processedWorkers: 2,
      totalWorkers: 10,
      currentWorkerId: '1001',
      lastAction: 'Evaluating worker 1001.',
    },
    recentRuns: [
      {
        runId: 'run-1',
        path: '/tmp/run-1.json',
        artifactType: 'WorkerPreview',
        mode: 'Review',
        dryRun: true,
        status: 'Succeeded',
        startedAt: '2026-03-20T10:00:00Z',
        durationSeconds: 300,
        creates: 0,
        updates: 1,
        enables: 0,
        disables: 0,
        deletions: 0,
        quarantined: 0,
        conflicts: 0,
        guardrailFailures: 0,
        manualReview: 1,
        unchanged: 0,
      },
    ],
    summary: {
      lastCheckpoint: '2026-03-20T09:00:00Z',
      totalTrackedWorkers: 7,
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
      reportDirectory: '/tmp/reports',
      reviewReportDirectory: '/tmp/review',
    },
    warnings: [],
  })),
  getRun: vi.fn(async () => ({
    run: {
      runId: 'run-1',
      path: '/tmp/run-1.json',
      artifactType: 'WorkerPreview',
      mode: 'Review',
      dryRun: true,
      status: 'Succeeded',
      startedAt: '2026-03-20T10:00:00Z',
      durationSeconds: 300,
      creates: 0,
      updates: 1,
      enables: 0,
      disables: 0,
      deletions: 0,
      quarantined: 0,
      conflicts: 0,
      guardrailFailures: 0,
      manualReview: 1,
      unchanged: 0,
    },
    report: {},
    bucketCounts: {
      updates: 1,
      manualReview: 1,
      creates: 0,
      deletions: 0,
      quarantined: 0,
      conflicts: 0,
      guardrailFailures: 0,
      enables: 0,
      disables: 0,
      graveyardMoves: 0,
      unchanged: 0,
    },
  })),
  getRunEntries: vi.fn(async () => ({
    run: {
      runId: 'run-1',
    },
    total: 1,
    warnings: [],
    entries: [
      {
        bucket: 'updates',
        bucketLabel: 'Updates',
        workerId: '1001',
        samAccountName: 'jdoe',
        reason: 'AttributeDelta',
        reviewCategory: 'ExistingUserChanges',
        reviewCaseType: 'RehireCase',
        operatorActionSummary: 'Confirm how this rehire should reuse or restore the existing AD identity.',
        operatorActions: [{ label: 'Confirm account reuse', description: 'Reuse the prior account.' }],
        item: {
          changedAttributeDetails: [{ targetAttribute: 'department', currentAdValue: 'Finance', proposedValue: 'Sales' }],
        },
      },
    ],
  })),
  getWorkerHistory: vi.fn(async () => ({
    workerId: '1001',
    warnings: [],
    entries: [
      {
        runId: 'run-1',
        bucketLabel: 'Updates',
        reason: 'AttributeDelta',
      },
    ],
  })),
}));

describe('App', () => {
  it('renders dashboard, selected run details, and manual review panel', async () => {
    render(<App />);

    await waitFor(() => expect(screen.getByText(/SyncFactors Web Dashboard/i)).toBeInTheDocument());
    await waitFor(() => expect(screen.getByText(/Recent runs/i)).toBeInTheDocument());
    await waitFor(() => expect(screen.getByText(/Manual review workflow/i)).toBeInTheDocument());

    expect(screen.getByText(/Confirm account reuse/i)).toBeInTheDocument();
    expect(screen.getByText(/Changed attributes/i)).toBeInTheDocument();
    expect(screen.getByText(/Worker view/i)).toBeInTheDocument();
  });
});
