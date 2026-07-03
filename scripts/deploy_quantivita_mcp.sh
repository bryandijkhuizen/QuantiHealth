#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load_env.sh
load_quantivita_env "$(pwd)"

HOST="${QUANTIVITA_HOMESERVER_HOST:-192.168.178.20}"
USER="${QUANTIVITA_HOMESERVER_USER:-bryan}"
KEY="${QUANTIVITA_HOMESERVER_KEY:-/Users/bryandijkh/.ssh/codex_homeserver}"
REMOTE_DIR="${QUANTIVITA_HOMESERVER_DIR:-/home/bryan/stacks/quantivita}"
PORT="${QUANTIVITA_API_PORT:-8088}"

SSH=(ssh -i "${KEY}" -o BatchMode=yes "${USER}@${HOST}")
RSYNC_RSH="ssh -i ${KEY} -o BatchMode=yes"

run_local() {
  if command -v rtk >/dev/null 2>&1; then
    rtk "$@"
  else
    "$@"
  fi
}

echo "Preparing Quantivita stack on ${USER}@${HOST}:${REMOTE_DIR}..."
"${SSH[@]}" "mkdir -p '${REMOTE_DIR}'"

echo "Syncing server files..."
run_local rsync -az --delete \
  -e "${RSYNC_RSH}" \
  services/quantivita-mcp/server services/quantivita-mcp/docker-compose.yml \
  "${USER}@${HOST}:${REMOTE_DIR}/"

echo "Writing remote stack environment..."
REMOTE_ENV=$(cat <<EOF
QUANTIVITA_PUBLIC_BASE_URL=${QUANTIVITA_PUBLIC_BASE_URL:-https://api.quantivita.bryandijkh.com}
QUANTIVITA_SESSION_SECRET=${QUANTIVITA_SESSION_SECRET:-dev-change-me}
APPLE_WEB_CLIENT_ID=${APPLE_WEB_CLIENT_ID:-}
PROGRESSA_API_BASE_URL=${PROGRESSA_API_BASE_URL:-https://api.progressa.bryandijkh.com}
STRAVA_CLIENT_ID=${STRAVA_CLIENT_ID:-}
STRAVA_CLIENT_SECRET=${STRAVA_CLIENT_SECRET:-}
STRAVA_REDIRECT_URI=${STRAVA_REDIRECT_URI:-quantivita://quantivita.app/strava-auth}
STRAVA_API_BASE_URL=${STRAVA_API_BASE_URL:-https://www.strava.com}
EOF
)
"${SSH[@]}" "cat > '${REMOTE_DIR}/.env'" <<< "${REMOTE_ENV}"

echo "Building and starting Docker stack..."
"${SSH[@]}" "cd '${REMOTE_DIR}' && docker compose up -d --build"

echo "Checking container..."
"${SSH[@]}" "docker ps --filter name=quantivita --format '{{.Names}} {{.Status}} {{.Ports}}'"

echo "Checking API health..."
"${SSH[@]}" "for attempt in 1 2 3 4 5 6; do curl -fsS 'http://127.0.0.1:${PORT}/healthz' && exit 0; sleep 2; done; docker logs --tail 50 quantivita >&2; exit 1"

echo
echo "Quantivita dashboard: ${QUANTIVITA_PUBLIC_BASE_URL:-http://${HOST}:${PORT}}"
