#!/usr/bin/env bash
set -euo pipefail
stack_root="${HEALTH_STACK_ROOT:-$HOME/stacks}"
# Use the existing Compose projects and their host-managed credentials and data volumes.
rsync -a --exclude=node_modules --exclude=.env Progressa/progressa-quantivita-api/ "$stack_root/progressa-api/server/"
rsync -a Progressa/progressa-quantivita-api/docker-compose.override.yml "$stack_root/progressa-api/"
docker compose --project-directory "$stack_root/progressa-api" -p progressa-api up -d --build progressa-api
curl --retry 8 --retry-all-errors --retry-delay 2 -fsS http://127.0.0.1:3002/healthz
# A healthy HTTP listener can still reject every login if upstream DNS is broken.
docker exec -i progressa-api node --input-type=module <<'NODE'
const base = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL;
const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || process.env.SUPABASE_ANON_KEY;
const response = await fetch(`${base}/auth/v1/health`, {
  headers: { apikey: key }, signal: AbortSignal.timeout(15000),
});
if (!response.ok) throw new Error(`Progressa authentication upstream failed: HTTP ${response.status}`);
console.log('Progressa authentication upstream is reachable');
NODE
rsync -a --exclude=node_modules --exclude=.env services/quantivita-mcp/server/ "$stack_root/quantivita/server/"
rsync -a services/quantivita-mcp/docker-compose.yml "$stack_root/quantivita/"
docker compose --project-directory "$stack_root/quantivita" -p quantivita up -d --build quantivita
curl --retry 8 --retry-all-errors --retry-delay 2 -fsS http://127.0.0.1:8088/healthz

docker exec -i quantivita node --input-type=module <<'NODE'
const response = await fetch(new URL('/healthz', process.env.PROGRESSA_API_BASE_URL), {
  signal: AbortSignal.timeout(15000),
});
if (!response.ok) throw new Error(`Quantivita to Progressa upstream failed: HTTP ${response.status}`);
console.log('Quantivita can reach Progressa');
NODE
