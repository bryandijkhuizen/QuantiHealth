#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${1:-00008150-001E439C2242401C}"
BUNDLE_ID="com.bryandijkh.quantivita"

cd "$(dirname "$0")/.."

echo "Building signed iOS profile app with console logs..."
rtk flutter build ios --profile

echo "Installing on device ${DEVICE_ID}..."
rtk flutter install -d "${DEVICE_ID}"

echo "Launching ${BUNDLE_ID} with live console logs. Stop with Ctrl-C."
rtk xcrun devicectl device process launch \
  --device "${DEVICE_ID}" \
  --terminate-existing \
  --console \
  "${BUNDLE_ID}"
