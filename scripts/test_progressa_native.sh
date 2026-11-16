#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="$(xcrun simctl list devices available --json | python3 -c '
import json,sys
phones=[d for runtime,rows in json.load(sys.stdin)["devices"].items() if ".iOS-" in runtime for d in rows if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not phones: sys.exit("No iPhone simulator installed")
print(phones[0]["udid"])
')"
xcodebuild test -project "$PROJECT_ROOT/ProgressaNative/ProgressaNative.xcodeproj" \
  -scheme ProgressaNativeTests -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -parallel-testing-enabled NO \
  -only-testing:ProgressaNativeTests/WorkoutAPIContractTests \
  -only-testing:ProgressaNativeTests/WorkoutSliceTests \
  -only-testing:ProgressaNativeTests/HealthMetadataTests \
  -only-testing:ProgressaNativeTests/AuthProfileTests \
  -only-testing:ProgressaNativeTests/QuantivitaConnectTests \
  CODE_SIGNING_ALLOWED=NO
