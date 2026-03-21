import { useEffect, useMemo, useState } from 'react';
import { getRun, getRunEntries, getStatus, getWorkerHistory } from './api.js';
import type { DashboardStatus, EntryListResponse, EntryRecord, RunDetailResponse, WorkerHistoryResponse } from './types.js';

const BUCKET_ORDER = [
  'quarantined',
  'conflicts',
  'manualReview',
  'guardrailFailures',
  'creates',
  'updates',
  'enables',
  'disables',
  'graveyardMoves',
  'deletions',
  'unchanged',
];

export function App() {
  const [status, setStatus] = useState<DashboardStatus | null>(null);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [selectedBucket, setSelectedBucket] = useState<string>('quarantined');
  const [runDetail, setRunDetail] = useState<RunDetailResponse | null>(null);
  const [entryResponse, setEntryResponse] = useState<EntryListResponse | null>(null);
  const [selectedEntryIndex, setSelectedEntryIndex] = useState(0);
  const [workerHistory, setWorkerHistory] = useState<WorkerHistoryResponse | null>(null);
  const [filterText, setFilterText] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    const loadStatus = async () => {
      try {
        const nextStatus = await getStatus();
        if (cancelled) {
          return;
        }

        setStatus(nextStatus);
        setSelectedRunId((current) => current ?? nextStatus.recentRuns[0]?.runId ?? null);
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load dashboard status.');
        }
      }
    };

    void loadStatus();
    const interval = window.setInterval(() => void loadStatus(), 10000);
    return () => {
      cancelled = true;
      window.clearInterval(interval);
    };
  }, []);

  useEffect(() => {
    if (!selectedRunId) {
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        const [nextRunDetail, nextEntries] = await Promise.all([
          getRun(selectedRunId),
          getRunEntries(selectedRunId, { bucket: selectedBucket, filter: filterText }),
        ]);
        if (cancelled) {
          return;
        }

        setRunDetail(nextRunDetail);
        setEntryResponse(nextEntries);
        setSelectedEntryIndex(0);
      } catch (loadError) {
        if (!cancelled) {
          setError(loadError instanceof Error ? loadError.message : 'Failed to load run detail.');
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedRunId, selectedBucket, filterText]);

  const selectedEntry = entryResponse?.entries[selectedEntryIndex] ?? null;

  useEffect(() => {
    if (!selectedEntry?.workerId) {
      setWorkerHistory(null);
      return;
    }

    let cancelled = false;
    void (async () => {
      try {
        const nextHistory = await getWorkerHistory(selectedEntry.workerId!);
        if (!cancelled) {
          setWorkerHistory(nextHistory);
        }
      } catch {
        if (!cancelled) {
          setWorkerHistory(null);
        }
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [selectedEntry?.workerId]);

  const runBuckets = useMemo(() => {
    if (!runDetail) {
      return [];
    }

    return BUCKET_ORDER.filter((bucket) => (runDetail.bucketCounts[bucket] ?? 0) > 0)
      .map((bucket) => ({
        bucket,
        count: runDetail.bucketCounts[bucket] ?? 0,
      }));
  }, [runDetail]);

  useEffect(() => {
    if (runBuckets.length === 0) {
      return;
    }

    if (!runBuckets.some((entry) => entry.bucket === selectedBucket)) {
      setSelectedBucket(runBuckets[0].bucket);
    }
  }, [runBuckets, selectedBucket]);

  return (
    <div className="app-shell">
      <header className="hero">
        <div>
          <p className="eyebrow">SyncFactors Web Dashboard</p>
          <h1>Read-only operator view for runtime status, reports, and manual review.</h1>
          <p className="lede">
            Localhost-only v1. Browser visibility replaces the TUI read path; PowerShell remains the source of truth for sync execution.
          </p>
        </div>
        <div className="hero-card">
          <span className="badge">Read-only</span>
          <p>{status?.paths.configPath ?? 'Loading config path...'}</p>
          <p>{status?.paths.reportDirectory ?? 'Waiting for report directory...'}</p>
        </div>
      </header>

      {error ? <section className="error-banner">{error}</section> : null}

      <section className="status-grid">
        <StatusPanel title="SuccessFactors" health={status?.health.successFactors} />
        <StatusPanel title="Active Directory" health={status?.health.activeDirectory} />
        <SummaryPanel status={status} />
        <CurrentRunPanel currentRun={status?.currentRun ?? null} />
      </section>

      <main className="main-grid">
        <section className="card runs-card">
          <div className="card-header">
            <div>
              <p className="section-kicker">Run History</p>
              <h2>Recent runs</h2>
            </div>
          </div>
          <div className="runs-table">
            {status?.recentRuns.map((run) => (
              <button
                key={run.runId ?? run.path ?? Math.random()}
                className={`run-row ${selectedRunId === run.runId ? 'selected' : ''}`}
                onClick={() => setSelectedRunId(run.runId)}
                type="button"
              >
                <span>{run.status ?? 'Unknown'}</span>
                <span>{run.mode ?? '-'}</span>
                <span>{run.artifactType}</span>
                <span>{run.startedAt ?? '-'}</span>
                <span>C {run.creates} / U {run.updates} / MR {run.manualReview}</span>
              </button>
            )) ?? <p>No recent runs.</p>}
          </div>
        </section>

        <section className="card detail-card">
          <div className="card-header">
            <div>
              <p className="section-kicker">Run Detail</p>
              <h2>{runDetail?.run.runId ?? 'Select a run'}</h2>
            </div>
            {runDetail?.run ? <span className="badge ghost">{runDetail.run.artifactType}</span> : null}
          </div>

          {runDetail?.run ? (
            <>
              <div className="detail-summary">
                <SummaryMetric label="Mode" value={runDetail.run.mode ?? '-'} />
                <SummaryMetric label="Status" value={runDetail.run.status ?? '-'} />
                <SummaryMetric label="Duration" value={runDetail.run.durationSeconds?.toString() ?? '-'} />
                <SummaryMetric label="Manual review" value={runDetail.run.manualReview.toString()} />
              </div>

              <div className="toolbar">
                <div className="bucket-tabs">
                  {runBuckets.map(({ bucket, count }) => (
                    <button
                      key={bucket}
                      type="button"
                      className={selectedBucket === bucket ? 'active' : ''}
                      onClick={() => setSelectedBucket(bucket)}
                    >
                      {bucket} ({count})
                    </button>
                  ))}
                </div>
                <input
                  aria-label="Filter entries"
                  placeholder="Filter by worker, reason, or category"
                  value={filterText}
                  onChange={(event) => setFilterText(event.target.value)}
                />
              </div>

              <div className="detail-content">
                <div className="entry-list">
                  {(entryResponse?.entries ?? []).map((entry, index) => (
                    <button
                      key={`${entry.bucket}-${entry.workerId ?? index}-${index}`}
                      type="button"
                      className={`entry-row ${selectedEntryIndex === index ? 'selected' : ''}`}
                      onClick={() => setSelectedEntryIndex(index)}
                    >
                      <strong>{entry.workerId ?? 'Unknown worker'}</strong>
                      <span>{entry.bucketLabel}</span>
                      <span>{entry.reason ?? entry.reviewCategory ?? 'No reason provided'}</span>
                    </button>
                  ))}
                </div>

                <SelectedEntryPanel entry={selectedEntry} workerHistory={workerHistory} run={runDetail} />
              </div>

              {runDetail.run.mode === 'Review' ? (
                <section className="review-strip">
                  <h3>Report explorer</h3>
                  <p>
                    Created {runDetail.bucketCounts.creates ?? 0} | Changed {runDetail.bucketCounts.updates ?? 0} | Deleted {runDetail.bucketCounts.deletions ?? 0}
                  </p>
                </section>
              ) : null}
            </>
          ) : (
            <p className="empty-state">Choose a run to inspect report buckets and selected-object details.</p>
          )}
        </section>
      </main>
    </div>
  );
}

function StatusPanel({ title, health }: { title: string; health?: { status: string; detail: string } }) {
  return (
    <section className="card status-card">
      <p className="section-kicker">{title}</p>
      <h2>{health?.status ?? 'UNKNOWN'}</h2>
      <p>{health?.detail ?? 'Waiting for probe details.'}</p>
    </section>
  );
}

function SummaryPanel({ status }: { status: DashboardStatus | null }) {
  return (
    <section className="card status-card">
      <p className="section-kicker">State Summary</p>
      <h2>{status?.summary.totalTrackedWorkers ?? 0} tracked workers</h2>
      <p>
        Suppressed {status?.summary.suppressedWorkers ?? 0} | Pending deletion {status?.summary.pendingDeletionWorkers ?? 0}
      </p>
      <p>Checkpoint {status?.summary.lastCheckpoint ?? 'none'}</p>
    </section>
  );
}

function CurrentRunPanel({ currentRun }: { currentRun: Record<string, unknown> | null }) {
  return (
    <section className="card current-run-card">
      <p className="section-kicker">Current Run</p>
      <h2>{`${currentRun?.status ?? 'Idle'} / ${currentRun?.stage ?? 'Completed'}`}</h2>
      <p>{`${currentRun?.lastAction ?? 'No active sync run.'}`}</p>
      <p>
        Progress {`${currentRun?.processedWorkers ?? 0}`} / {`${currentRun?.totalWorkers ?? 0}`} | Worker {`${currentRun?.currentWorkerId ?? '-'}`}
      </p>
    </section>
  );
}

function SummaryMetric({ label, value }: { label: string; value: string }) {
  return (
    <div className="metric">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function SelectedEntryPanel({
  entry,
  workerHistory,
  run,
}: {
  entry: EntryRecord | null;
  workerHistory: WorkerHistoryResponse | null;
  run: RunDetailResponse | null;
}) {
  if (!entry) {
    return <div className="selected-panel empty-state">No entry selected for this bucket.</div>;
  }

  const changedAttributes =
    (Array.isArray(entry.item.changedAttributeDetails) ? entry.item.changedAttributeDetails : []) as Array<Record<string, unknown>>;

  return (
    <div className="selected-panel">
      <div className="selected-header">
        <div>
          <p className="section-kicker">Selected Object</p>
          <h3>{entry.workerId ?? entry.samAccountName ?? 'Unknown object'}</h3>
        </div>
        <span className="badge">{entry.bucketLabel}</span>
      </div>

      <dl className="detail-list">
        <DetailRow label="Reason" value={entry.reason ?? '-'} />
        <DetailRow label="Review category" value={entry.reviewCategory ?? '-'} />
        <DetailRow label="Review case" value={entry.reviewCaseType ?? '-'} />
        <DetailRow label="SamAccountName" value={entry.samAccountName ?? '-'} />
        <DetailRow label="Target OU" value={entry.targetOu ?? '-'} />
        <DetailRow label="Current DN" value={entry.currentDistinguishedName ?? '-'} />
      </dl>

      {entry.operatorActionSummary ? (
        <section className="operator-panel">
          <h4>Manual review workflow</h4>
          <p>{entry.operatorActionSummary}</p>
          {entry.operatorActions.length > 0 ? (
            <ul>
              {entry.operatorActions.map((action, index) => (
                <li key={`${action.code ?? action.label ?? index}`}>
                  <strong>{action.label ?? action.code ?? 'Action'}</strong>: {action.description ?? 'No description provided.'}
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}

      {changedAttributes.length > 0 ? (
        <section className="changes-panel">
          <h4>Changed attributes</h4>
          <ul>
            {changedAttributes.slice(0, 8).map((row, index) => (
              <li key={`${row.targetAttribute ?? index}`}>
                <strong>{`${row.targetAttribute ?? 'attribute'}`}</strong>: {`${row.currentAdValue ?? '(unset)'}`} → {`${row.proposedValue ?? '(unset)'}`}
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {workerHistory?.entries?.length ? (
        <section className="history-panel">
          <h4>Worker view</h4>
          <p>{workerHistory.entries.length} related entries across recent reports.</p>
          <ul>
            {workerHistory.entries.slice(0, 5).map((historyEntry, index) => (
              <li key={`${historyEntry.runId ?? index}-${index}`}>
                {historyEntry.bucketLabel} · {historyEntry.reason ?? historyEntry.reviewCategory ?? 'No reason'} · {historyEntry.runId ?? run?.run.runId ?? '-'}
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <>
      <dt>{label}</dt>
      <dd>{value}</dd>
    </>
  );
}
