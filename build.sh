#!/usr/bin/env bash
# Wires the Xcode project; pass --build-app for a simulator smoke build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ruby -e "require 'xcodeproj'" 2>/dev/null || gem install --user-install xcodeproj

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
