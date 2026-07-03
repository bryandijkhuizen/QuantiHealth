#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load_env.sh
load_quantivita_env "$(pwd)"

DEVICE_ID="${QUANTIVITA_DEVICE_ID:-00008150-001E439C2242401C}"
API_BASE_URL="${QUANTIVITA_API_BASE_URL:-https://api.quantivita.bryandijkh.com}"
STRAVA_REDIRECT_URI="${STRAVA_REDIRECT_URI:-quantivita://quantivita.app/strava-auth}"
PROGRESSA_AUTH_BASE_URL="${PROGRESSA_AUTH_BASE_URL:-https://api.progressa.bryandijkh.com}"
PROGRESSA_REDIRECT_URI="${PROGRESSA_REDIRECT_URI:-quantivita://quantivita.app/progressa-auth}"

usage() {
  cat <<'EOF'
Usage: scripts/run_app.sh [options]

Options:
  --device-id ID              iPhone device id
  --api-base-url URL          Quantivita API base URL
  --strava-client-id ID       Numeric Strava client id
  --strava-client-secret KEY  Strava client secret
  --strava-redirect-uri URI   Strava OAuth redirect URI
  --progressa-auth-base-url URL
                              Progressa web consent base URL
  --progressa-redirect-uri URI
                              Quantivita Progressa callback URI
  -h, --help                  Show help

Environment variables with the same names also work:
  QUANTIVITA_DEVICE_ID, QUANTIVITA_API_BASE_URL,
  STRAVA_CLIENT_ID, STRAVA_CLIENT_SECRET, STRAVA_REDIRECT_URI,
  PROGRESSA_AUTH_BASE_URL, PROGRESSA_REDIRECT_URI

Values are loaded from .env by default. Override with QUANTIVITA_ENV_FILE=/path/to/file.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      DEVICE_ID="$2"
      shift 2
      ;;
    --api-base-url)
      API_BASE_URL="$2"
      shift 2
      ;;
    --strava-client-id)
      STRAVA_CLIENT_ID="$2"
      shift 2
      ;;
    --strava-client-secret)
      STRAVA_CLIENT_SECRET="$2"
      shift 2
      ;;
    --strava-redirect-uri)
      STRAVA_REDIRECT_URI="$2"
      shift 2
      ;;
    --progressa-auth-base-url)
      PROGRESSA_AUTH_BASE_URL="$2"
      shift 2
      ;;
    --progressa-redirect-uri)
      PROGRESSA_REDIRECT_URI="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      DEVICE_ID="$1"
      shift
      ;;
  esac
done

ARGS=(
  flutter run
  -d "${DEVICE_ID}"
  --dart-define="QUANTIVITA_API_BASE_URL=${API_BASE_URL}"
  --dart-define="STRAVA_REDIRECT_URI=${STRAVA_REDIRECT_URI}"
  --dart-define="PROGRESSA_AUTH_BASE_URL=${PROGRESSA_AUTH_BASE_URL}"
  --dart-define="PROGRESSA_REDIRECT_URI=${PROGRESSA_REDIRECT_URI}"
)

if [[ -n "${STRAVA_CLIENT_ID:-}" ]]; then
  ARGS+=(--dart-define="STRAVA_CLIENT_ID=${STRAVA_CLIENT_ID}")
fi

if [[ -n "${STRAVA_CLIENT_SECRET:-}" ]]; then
  ARGS+=(--dart-define="STRAVA_CLIENT_SECRET=${STRAVA_CLIENT_SECRET}")
fi

echo "Starting Quantivita on ${DEVICE_ID}..."
echo "API: ${API_BASE_URL}"
echo "Progressa auth: ${PROGRESSA_AUTH_BASE_URL}"
if [[ -z "${STRAVA_CLIENT_ID:-}" || -z "${STRAVA_CLIENT_SECRET:-}" ]]; then
  echo "Strava credentials not set; Strava Connect will show a config message."
else
  echo "Strava credentials: configured for client ${STRAVA_CLIENT_ID}"
fi

rtk "${ARGS[@]}"
