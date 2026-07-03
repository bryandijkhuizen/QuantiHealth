#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${1:-00008150-001E439C2242401C}"
BUNDLE_ID="com.bryandijkh.quantivita"

cd "$(dirname "$0")/.."

echo "Building signed iOS profile app..."
rtk flutter build ios --profile

echo "Installing on device ${DEVICE_ID}..."
rtk flutter install -d "${DEVICE_ID}"

echo "Launching ${BUNDLE_ID}..."
rtk xcrun devicectl device process launch --device "${DEVICE_ID}" "${BUNDLE_ID}"

echo "Done."
