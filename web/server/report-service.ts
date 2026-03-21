import fs from 'node:fs/promises';
import path from 'node:path';
import type { DashboardStatus, EntryListResponse, EntryRecord, RunDetailResponse, RunSummary, WorkerHistoryResponse } from './types.js';

const BUCKET_LABELS: Record<string, string> = {
  creates: 'Creates',
  updates: 'Updates',
  enables: 'Enables',
  disables: 'Disables',
  graveyardMoves: 'Graveyard Moves',
  deletions: 'Deletions',
  quarantined: 'Quarantined',
  conflicts: 'Conflicts',
  guardrailFailures: 'Guardrails',
  manualReview: 'Manual Review',
  unchanged: 'Unchanged',
};

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
] as const;

type ReportCacheEntry = {
  mtimeMs: number;
  report: Record<string, unknown>;
};

export class ReportService {
  private readonly reportCache = new Map<string, ReportCacheEntry>();

  async listRuns(
    status: DashboardStatus,
    filters: { mode?: string; artifact?: string; status?: string; page?: number; pageSize?: number },
  ): Promise<{ items: RunSummary[]; total: number; page: number; pageSize: number }> {
    const page = Math.max(filters.page ?? 1, 1);
    const pageSize = Math.min(Math.max(filters.pageSize ?? 25, 1), 100);
    const filtered = status.recentRuns.filter((run) => {
      if (filters.mode && `${run.mode ?? ''}`.toLowerCase() !== filters.mode.toLowerCase()) {
        return false;
      }
      if (filters.artifact && `${run.artifactType}`.toLowerCase() !== filters.artifact.toLowerCase()) {
        return false;
      }
      if (filters.status && `${run.status ?? ''}`.toLowerCase() !== filters.status.toLowerCase()) {
        return false;
      }
      return true;
    });

    const start = (page - 1) * pageSize;
    return {
      items: filtered.slice(start, start + pageSize),
      total: filtered.length,
      page,
      pageSize,
    };
  }

  async getRun(status: DashboardStatus, runId: string): Promise<RunDetailResponse> {
    const run = this.findRun(status, runId);
    const report = await this.readReport(run.path);
    const bucketCounts = Object.fromEntries(
      BUCKET_ORDER.map((bucket) => [bucket, Array.isArray(report[bucket]) ? (report[bucket] as unknown[]).length : 0]),
    );

    return { run, report, bucketCounts };
  }

  async getRunEntries(
    status: DashboardStatus,
    runId: string,
    filters: { bucket?: string; workerId?: string; reason?: string; filter?: string },
  ): Promise<EntryListResponse> {
    const run = this.findRun(status, runId);
    const report = await this.readReport(run.path);
    const entries = flattenEntries(run, report).filter((entry) => {
      if (filters.bucket && entry.bucket !== filters.bucket) {
        return false;
      }
      if (filters.workerId && entry.workerId !== filters.workerId) {
        return false;
      }
      if (filters.reason && `${entry.reason ?? ''}`.toLowerCase() !== filters.reason.toLowerCase()) {
        return false;
      }
      if (filters.filter && !matchesFilter(entry, filters.filter)) {
        return false;
      }
      return true;
    });

    return { run, entries, total: entries.length, warnings: [] };
  }

  async getWorkerHistory(
    status: DashboardStatus,
    workerId: string,
    limit = 100,
  ): Promise<WorkerHistoryResponse> {
    const warnings: string[] = [];
    const entries: EntryRecord[] = [];

    for (const run of status.recentRuns) {
      if (!run.path) {
        continue;
      }

      try {
        const report = await this.readReport(run.path);
        for (const entry of flattenEntries(run, report)) {
          if (entry.workerId === workerId) {
            entries.push(entry);
            if (entries.length >= limit) {
              return { workerId, entries, warnings };
            }
          }
        }
      } catch (error) {
        warnings.push(`Skipped unreadable report ${path.basename(run.path)}.`);
      }
    }

    return { workerId, entries, warnings };
  }

  private findRun(status: DashboardStatus, runId: string): RunSummary {
    const run = status.recentRuns.find((candidate) => candidate.runId === runId);
    if (!run || !run.path) {
      throw new Error(`Run '${runId}' was not found.`);
    }

    return run;
  }

  private async readReport(reportPath: string | null): Promise<Record<string, unknown>> {
    if (!reportPath) {
      throw new Error('Report path is unavailable.');
    }

    const stat = await fs.stat(reportPath);
    const cached = this.reportCache.get(reportPath);
    if (cached && cached.mtimeMs === stat.mtimeMs) {
      return cached.report;
    }

    const raw = await fs.readFile(reportPath, 'utf8');
    const report = JSON.parse(raw) as Record<string, unknown>;
    this.reportCache.set(reportPath, { mtimeMs: stat.mtimeMs, report });
    return report;
  }
}

function flattenEntries(run: RunSummary, report: Record<string, unknown>): EntryRecord[] {
  const entries: EntryRecord[] = [];
  for (const bucket of BUCKET_ORDER) {
    const items = Array.isArray(report[bucket]) ? (report[bucket] as Array<Record<string, unknown>>) : [];
    for (const item of items) {
      const changedDetails = Array.isArray(item.changedAttributeDetails) ? item.changedAttributeDetails : [];
      const attributeRows = Array.isArray(item.attributeRows) ? item.attributeRows.filter((row) => row && typeof row === 'object') : [];
      entries.push({
        runId: run.runId,
        reportPath: run.path,
        artifactType: run.artifactType,
        mode: run.mode,
        bucket,
        bucketLabel: BUCKET_LABELS[bucket] ?? bucket,
        workerId: asString(item.workerId),
        samAccountName: asString(item.samAccountName),
        reason: asString(item.reason),
        reviewCategory: asString(item.reviewCategory),
        reviewCaseType: asString(item.reviewCaseType),
        operatorActionSummary: asString(item.operatorActionSummary),
        operatorActions: Array.isArray(item.operatorActions) ? (item.operatorActions as EntryRecord['operatorActions']) : [],
        targetOu: asString(item.targetOu),
        currentDistinguishedName: asString(item.currentDistinguishedName ?? item.distinguishedName),
        currentEnabled: asBoolean(item.currentEnabled),
        proposedEnable: asBoolean(item.proposedEnable),
        matchedExistingUser: asBoolean(item.matchedExistingUser),
        changeCount: changedDetails.length || attributeRows.filter((row) => Boolean((row as { changed?: boolean }).changed)).length,
        item,
      });
    }
  }

  return entries;
}

function matchesFilter(entry: EntryRecord, filter: string): boolean {
  const needle = filter.trim().toLowerCase();
  if (!needle) {
    return true;
  }

  const haystack = JSON.stringify({
    workerId: entry.workerId,
    samAccountName: entry.samAccountName,
    reason: entry.reason,
    reviewCategory: entry.reviewCategory,
    reviewCaseType: entry.reviewCaseType,
    bucketLabel: entry.bucketLabel,
    item: entry.item,
  }).toLowerCase();

  return haystack.includes(needle);
}

function asString(value: unknown): string | null {
  if (typeof value === 'string' && value.trim()) {
    return value;
  }

  return null;
}

function asBoolean(value: unknown): boolean | null {
  if (typeof value === 'boolean') {
    return value;
  }

  return null;
}
