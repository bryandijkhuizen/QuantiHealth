#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_ID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, rows in devices.items() if ".iOS-" in runtime
          for d in rows if d.get("isAvailable") and d["name"].startswith("iPhone")]
if not phones:
    sys.exit("No available iPhone simulator installed")
print(phones[0]["udid"])
')"

xcodebuild test \
  -project "$PROJECT_ROOT/QuantivitaNative/QuantivitaNative.xcodeproj" \
  -scheme QuantivitaNative \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -parallel-testing-enabled NO \
  -only-testing:QuantivitaNativeTests \
  CODE_SIGNING_ALLOWED=NO
