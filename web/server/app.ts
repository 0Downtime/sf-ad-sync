import express from 'express';
import type { Express, Request, Response } from 'express';
import type { DashboardStatus } from './types.js';
import { PowerShellStatusProvider, type StatusProvider } from './status-provider.js';
import { ReportService } from './report-service.js';

export type AppDependencies = {
  configPath: string;
  historyLimit?: number;
  statusProvider?: StatusProvider;
  reportService?: ReportService;
};

export function createApp(dependencies: AppDependencies): Express {
  const app = express();
  const historyLimit = dependencies.historyLimit ?? 25;
  const statusProvider = dependencies.statusProvider ?? new PowerShellStatusProvider();
  const reportService = dependencies.reportService ?? new ReportService();

  app.get('/api/status', async (_request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      response.json({ status });
    } catch (error) {
      respondWithError(response, 500, 'Failed to load dashboard status.', error);
    }
  });

  app.get('/api/runs', async (request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      const result = await reportService.listRuns(status, {
        mode: asQueryString(request.query.mode),
        artifact: asQueryString(request.query.artifact),
        status: asQueryString(request.query.status),
        page: asQueryNumber(request.query.page),
        pageSize: asQueryNumber(request.query.pageSize),
      });
      response.json(result);
    } catch (error) {
      respondWithError(response, 500, 'Failed to list runs.', error);
    }
  });

  app.get('/api/runs/:runId', async (request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      const result = await reportService.getRun(status, request.params.runId);
      response.json(result);
    } catch (error) {
      respondWithError(response, 404, 'Failed to load the selected run.', error);
    }
  });

  app.get('/api/runs/:runId/entries', async (request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      const result = await reportService.getRunEntries(status, request.params.runId, {
        bucket: asQueryString(request.query.bucket),
        workerId: asQueryString(request.query.workerId),
        reason: asQueryString(request.query.reason),
        filter: asQueryString(request.query.filter),
      });
      response.json(result);
    } catch (error) {
      respondWithError(response, 404, 'Failed to load run entries.', error);
    }
  });

  app.get('/api/workers/:workerId/history', async (request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      const result = await reportService.getWorkerHistory(
        status,
        request.params.workerId,
        asQueryNumber(request.query.limit) ?? 100,
      );
      response.json(result);
    } catch (error) {
      respondWithError(response, 500, 'Failed to load worker history.', error);
    }
  });

  app.get('/api/health', async (_request, response) => {
    try {
      const status = await statusProvider.getStatus(dependencies.configPath, historyLimit);
      response.json({
        ok: true,
        configPath: dependencies.configPath,
        currentRunStatus: (status.currentRun.status as string | undefined) ?? null,
      });
    } catch (error) {
      respondWithError(response, 500, 'Dashboard health check failed.', error);
    }
  });

  return app;
}

function respondWithError(response: Response, statusCode: number, message: string, error: unknown): void {
  response.status(statusCode).json({
    error: message,
    detail: error instanceof Error ? error.message : 'Unknown error.',
  });
}

function asQueryString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value : undefined;
}

function asQueryNumber(value: unknown): number | undefined {
  if (typeof value !== 'string' || !value.trim()) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function createMockStatusProvider(status: DashboardStatus): StatusProvider {
  return {
    async getStatus() {
      return status;
    },
  };
}
