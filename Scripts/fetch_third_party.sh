#!/usr/bin/env bash
# Builds the yacd dashboard from source. Idempotent — an already-built
# dist is left alone.
#
# The Go cores (xray, sing-box, mihomo) are no longer fetched here:
# EverywhereCore ships them as a prebuilt xcframework via SwiftPM.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY="$ROOT/ThirdParty"
mkdir -p "$THIRD_PARTY"

# yacd dashboard. The fork has no gh-pages branch / Pages site / release
# tarball, so we clone master and run the Vite build ourselves. The
# resulting `dist/` is what ControllerView serves over the yacd:// URL
# scheme — Scripts/wire_project.rb registers ThirdParty/yacd-gh-pages
# as a "blue folder" resource.
YACD_REPO=https://github.com/hiDandelion/Yacd-meta.git
YACD_SRC="$THIRD_PARTY/yacd-source"
YACD_DIST="$THIRD_PARTY/yacd-gh-pages"

if [[ ! -d "$YACD_SRC/.git" ]]; then
  echo "⤓ yacd-source (hiDandelion/Yacd-meta master)"
  git clone --depth 1 "$YACD_REPO" "$YACD_SRC"
else
  echo "✓ yacd-source (cached)"
fi

if [[ ! -d "$YACD_DIST" || -z "$(ls -A "$YACD_DIST" 2>/dev/null)" ]]; then
  echo "→ pnpm install + build (yacd)"
  ( cd "$YACD_SRC" && pnpm install --frozen-lockfile && pnpm build )
  # vite.config.ts overrides outDir to `public/`, not the default `dist/`
  rm -rf "$YACD_DIST"
  cp -R "$YACD_SRC/public" "$YACD_DIST"
  echo "✓ yacd build → $YACD_DIST"
else
  echo "✓ yacd-gh-pages (cached)"
fi
