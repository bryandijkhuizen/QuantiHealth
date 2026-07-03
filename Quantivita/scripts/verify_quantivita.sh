#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/load_env.sh
load_quantivita_env "$(pwd)"

echo "Running Flutter analyzer..."
rtk flutter analyze

echo "Building iOS debug app without codesigning..."
rtk flutter build ios --debug --no-codesign

echo "Installing server dependencies..."
(cd server && rtk npm install)

API_BASE_URL="${QUANTIVITA_API_BASE_URL:-https://api.quantivita.bryandijkh.com}"
PROGRESSA_API_BASE_URL="${PROGRESSA_API_BASE_URL:-https://api.progressa.bryandijkh.com}"

echo "Verifying public Quantivita API..."
if rtk curl -fsS "${API_BASE_URL}/healthz" >/dev/null; then
  rtk curl -fsS "${API_BASE_URL}/healthz"
  echo
else
  echo "Quantivita API is not reachable at ${API_BASE_URL}."
  echo "Check DNS, reverse proxy, TLS, and scripts/deploy_homeserver.sh."
  exit 1
fi

echo "Verifying public Progressa API..."
if rtk curl -fsS "${PROGRESSA_API_BASE_URL}/healthz" >/dev/null; then
  rtk curl -fsS "${PROGRESSA_API_BASE_URL}/healthz"
  echo
else
  echo "Progressa API is not reachable at ${PROGRESSA_API_BASE_URL}."
  exit 1
fi

echo "Authenticated user endpoints require the account id and sync token shown in the app settings."

echo
echo "Verification complete."
