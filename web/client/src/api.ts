import type { DashboardStatus, EntryListResponse, RunDetailResponse, WorkerHistoryResponse } from './types.js';

async function fetchJson<T>(url: string): Promise<T> {
  const response = await fetch(url);
  if (!response.ok) {
    const payload = (await response.json().catch(() => null)) as { error?: string; detail?: string } | null;
    throw new Error(payload?.detail ?? payload?.error ?? `Request failed: ${response.status}`);
  }

  return (await response.json()) as T;
}

export async function getStatus(): Promise<DashboardStatus> {
  const response = await fetchJson<{ status: DashboardStatus }>('/api/status');
  return response.status;
}

export async function getRun(runId: string): Promise<RunDetailResponse> {
  return fetchJson<RunDetailResponse>(`/api/runs/${encodeURIComponent(runId)}`);
}

export async function getRunEntries(
  runId: string,
  query: { bucket?: string; filter?: string } = {},
): Promise<EntryListResponse> {
  const params = new URLSearchParams();
  if (query.bucket) {
    params.set('bucket', query.bucket);
  }
  if (query.filter) {
    params.set('filter', query.filter);
  }

  const suffix = params.toString() ? `?${params.toString()}` : '';
  return fetchJson<EntryListResponse>(`/api/runs/${encodeURIComponent(runId)}/entries${suffix}`);
}

export async function getWorkerHistory(workerId: string): Promise<WorkerHistoryResponse> {
  return fetchJson<WorkerHistoryResponse>(`/api/workers/${encodeURIComponent(workerId)}/history`);
}
