#!/usr/bin/env bash
# Clones the upstream Go repos at the tags pinned in PATCHES.md.
# Idempotent — already-cloned repos at the right tag are left alone.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY="$ROOT/ThirdParty"
mkdir -p "$THIRD_PARTY"

clone_at_tag() {
  local url="$1" tag="$2" dest="$3"
  local path="$THIRD_PARTY/$dest"
  if [[ -d "$path/.git" ]]; then
    local current
    current="$(git -C "$path" describe --tags --exact-match 2>/dev/null || echo "")"
    if [[ "$current" == "$tag" ]]; then
      echo "✓ $dest @ $tag (cached)"
      return
    fi
    echo "↻ $dest at $current → $tag (rm + reclone)"
    rm -rf "$path"
  fi
  echo "⤓ $dest @ $tag"
  git clone --depth 1 --branch "$tag" "$url" "$path"
}

clone_at_tag https://github.com/xjasonlyu/tun2socks.git v2.6.0    tun2socks
clone_at_tag https://github.com/XTLS/Xray-core.git       v26.3.27 Xray-core
clone_at_tag https://github.com/SagerNet/sing-box.git    v1.13.11 sing-box
clone_at_tag https://github.com/MetaCubeX/mihomo.git     v1.19.24 mihomo
