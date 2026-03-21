export type HealthStatus = {
  status: string;
  detail: string;
};

export type RunSummary = {
  runId: string | null;
  path: string | null;
  artifactType: string;
  workerScope?: { workerId?: string | null; identityField?: string | null } | null;
  mode: string | null;
  dryRun: boolean;
  status: string | null;
  startedAt: string | null;
  durationSeconds: number | null;
  creates: number;
  updates: number;
  enables: number;
  disables: number;
  deletions: number;
  quarantined: number;
  conflicts: number;
  guardrailFailures: number;
  manualReview: number;
  unchanged: number;
  reviewSummary?: Record<string, unknown> | null;
};

export type DashboardStatus = {
  latestRun: RunSummary;
  currentRun: Record<string, unknown>;
  recentRuns: RunSummary[];
  summary: {
    lastCheckpoint: string | null;
    totalTrackedWorkers: number;
    suppressedWorkers: number;
    pendingDeletionWorkers: number;
  };
  health: {
    successFactors: HealthStatus;
    activeDirectory: HealthStatus;
  };
  trackedWorkers: Array<Record<string, unknown>>;
  context: Record<string, unknown>;
  paths: {
    configPath: string;
    reportDirectory: string;
    reviewReportDirectory: string;
  };
  warnings?: string[];
};

export type OperatorAction = {
  code?: string;
  label?: string;
  description?: string;
};

export type EntryRecord = {
  runId: string | null;
  reportPath: string | null;
  artifactType: string;
  mode: string | null;
  bucket: string;
  bucketLabel: string;
  workerId: string | null;
  samAccountName: string | null;
  reason: string | null;
  reviewCategory: string | null;
  reviewCaseType: string | null;
  operatorActionSummary: string | null;
  operatorActions: OperatorAction[];
  targetOu: string | null;
  currentDistinguishedName: string | null;
  currentEnabled: boolean | null;
  proposedEnable: boolean | null;
  matchedExistingUser: boolean | null;
  changeCount: number;
  item: Record<string, unknown>;
};

export type RunDetailResponse = {
  run: RunSummary;
  report: Record<string, unknown>;
  bucketCounts: Record<string, number>;
};

export type EntryListResponse = {
  run: RunSummary;
  entries: EntryRecord[];
  total: number;
  warnings: string[];
};

export type WorkerHistoryResponse = {
  workerId: string;
  entries: EntryRecord[];
  warnings: string[];
};
