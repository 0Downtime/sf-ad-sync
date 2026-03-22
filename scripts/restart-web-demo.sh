#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_path="${1:-./reports/demo-rich/config/demo.mock-sync-config.json}"
port="${PORT:-4280}"
pattern="tsx web/server/index.ts --config ${config_path}"

cd "$repo_root"

existing_pids="$(pgrep -f "$pattern" || true)"
if [[ -n "$existing_pids" ]]; then
  echo "Stopping existing demo web server: $existing_pids"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid"
  done <<< "$existing_pids"
  sleep 1
fi

echo "Starting demo web server on http://127.0.0.1:${port}"
exec npm run web:dev -- --config "$config_path"
