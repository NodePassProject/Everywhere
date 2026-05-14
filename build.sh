#!/usr/bin/env bash
# Top-level: fetch yacd dashboard → wire project. The Go cores ship as a
# prebuilt xcframework via the EverywhereCore SwiftPM package, so there
# is no local Go build step anymore.
#
# Pass `--build-app` as a final step to also run `xcodebuild` for the
# iOS Simulator as a smoke test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

bash Scripts/fetch_third_party.sh
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
