#!/usr/bin/env bash
# Builds EverywhereCore.xcframework via gomobile bind. Installs gomobile
# and gobind into $GOPATH/bin if they are missing. Run from any cwd.
#
# gomobile produces a *static* framework on iOS — the binary inside
# .framework is an `ar` archive of object files, not a Mach-O dylib.
# dsymutil cannot process that, so we strip Go-side debug info via
# -ldflags="-s -w" instead. Result: no dSYM is needed (or expected by
# Apple's archive validator), and the framework is also smaller. The
# trade-off is no Go stack symbolication in iOS crash reports — but
# Go panics surface inside the runtime's own panic handler and rarely
# show up in Apple crash reports anyway.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT/EverywhereCore"
OUT="$ROOT/Frameworks/EverywhereCore.xcframework"

GOPATH="$(go env GOPATH)"
GOBIN="$GOPATH/bin"
PATH="$GOBIN:$PATH"
export PATH

if ! command -v gomobile >/dev/null 2>&1; then
  echo "→ installing gomobile + gobind"
  go install golang.org/x/mobile/cmd/gomobile@latest
  go install golang.org/x/mobile/cmd/gobind@latest
fi

mkdir -p "$ROOT/Frameworks"

cd "$CORE_DIR"
echo "→ go mod tidy"
go mod tidy

# Build tags enable optional features in upstream cores. We enable
# every with_* tag sing-box ships, in alphabetical order — see
# PATCHES.md for what each one unlocks. Trim if binary size becomes
# a concern.
BUILD_TAGS="\
with_acme \
with_ccm \
with_clash_api \
with_dhcp \
with_grpc \
with_gvisor \
with_ocm \
with_quic \
with_tailscale \
with_utls \
with_v2ray_api \
with_wireguard"

# -s: strip Go symbol table.  -w: strip DWARF.  Together they remove
# both the metadata Apple's archive validator wants a dSYM for and a
# noticeable chunk of binary size.
LDFLAGS="-s -w"

echo "→ gomobile bind tags=$BUILD_TAGS ldflags=$LDFLAGS"
rm -rf "$OUT"
gomobile bind \
  -target=ios,iossimulator \
  -tags="$BUILD_TAGS" \
  -ldflags="$LDFLAGS" \
  -o "$OUT" .

echo "✓ built $OUT"
du -sh "$OUT"
