#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load_env.sh
load_quantivita_env "$(pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/run_full_stack.sh [options]

Deploys the homeserver stack, then starts the iPhone app.

Options:
  --device-id ID              iPhone device id
  --api-base-url URL          Quantivita API base URL
  --strava-client-id ID       Numeric Strava client id
  --strava-client-secret KEY  Strava client secret
  --strava-redirect-uri URI   Strava OAuth redirect URI
  -h, --help                  Show help

Example:
  scripts/run_full_stack.sh \
    --strava-client-id 123456 \
    --strava-client-secret your_secret

Environment variables with the same names also work:
  QUANTIVITA_DEVICE_ID, QUANTIVITA_API_BASE_URL,
  STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, STRAVA_REDIRECT_URI

Values are loaded from .env by default. Override with QUANTIVITA_ENV_FILE=/path/to/file.
EOF
}

APP_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id|--api-base-url|--strava-client-id|--strava-client-secret|--strava-redirect-uri)
      APP_ARGS+=("$1" "$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      APP_ARGS+=("--device-id" "$1")
      shift
      ;;
  esac
done

echo "Deploying Quantivita homeserver stack..."
scripts/deploy_homeserver.sh

echo
echo "Starting Quantivita app..."
if (( ${#APP_ARGS[@]} > 0 )); then
  scripts/run_app.sh "${APP_ARGS[@]}"
else
  scripts/run_app.sh
fi
