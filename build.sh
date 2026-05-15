#!/usr/bin/env bash
# Top-level: wire the Xcode project. The zashboard dashboard is checked
# into ThirdParty/zashboard/ as a prebuilt static bundle, and the Go
# cores ship as a prebuilt xcframework via the EverywhereCore SwiftPM
# package — so there is no local source build step.
#
# Pass `--build-app` as a final step to also run `xcodebuild` for the
# iOS Simulator as a smoke test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ruby Scripts/wire_project.rb

if [[ "${1:-}" == "--build-app" ]]; then
  echo "→ xcodebuild simulator smoke test"
  xcodebuild \
    -project Everywhere.xcodeproj \
    -scheme Everywhere \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

echo "✓ done"
