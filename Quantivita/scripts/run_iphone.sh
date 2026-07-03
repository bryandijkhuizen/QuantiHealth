#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${1:-00008150-001E439C2242401C}"
BUNDLE_ID="com.bryandijkh.quantivita"

cd "$(dirname "$0")/.."

echo "Starting Flutter debug session on ${DEVICE_ID}..."
echo "Hot reload: press r. Hot restart: press R. Quit: press q."
rtk flutter run -d "${DEVICE_ID}"
