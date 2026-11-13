#!/usr/bin/env bash
set -euo pipefail
stack_root="${HEALTH_STACK_ROOT:-$HOME/stacks}"
# Use the existing Compose projects and their host-managed credentials and data volumes.
rsync -a --exclude=node_modules --exclude=.env Progressa/progressa-quantivita-api/ "$stack_root/progressa-api/server/"
docker compose --project-directory "$stack_root/progressa-api" -p progressa-api up -d --build progressa-api
curl --retry 8 --retry-all-errors --retry-delay 2 -fsS http://127.0.0.1:3002/healthz
rsync -a --exclude=node_modules --exclude=.env services/quantivita-mcp/server/ "$stack_root/quantivita/server/"
rsync -a services/quantivita-mcp/docker-compose.yml "$stack_root/quantivita/"
docker compose --project-directory "$stack_root/quantivita" -p quantivita up -d --build quantivita
curl --retry 8 --retry-all-errors --retry-delay 2 -fsS http://127.0.0.1:8088/healthz
