<div align="center">

<div>
    <a href="https://apps.apple.com/app/id6766003090">
        <img width="100" height="100" alt="Everywhere" src="https://storage.argsment.com/Everywhere-AppIcon-iOS.png" />
    </a>
</div>

# Everywhere

**One app. Three networking engines. Your rules.**

Everywhere is a powerful proxy and tunneling app for iOS that puts you in
charge of how your device talks to the internet. Bring your own
configuration, pick the engine you trust, and flip a switch. That's it.

</div>

---

## Why Everywhere?

Most networking apps lock you into a single backend and a single way of
doing things. Everywhere doesn't. It bundles three of the most popular
open-source proxy cores in one place, gives them a clean home, and lets
you move between them whenever you like.

## Features

### Cores

- **Xray-core** `v26.3.27` — battle-tested VLESS / VMess / Trojan /
  Shadowsocks with the full XTLS / Reality / XHTTP transport matrix
- **sing-box** `v1.13.11` — modern modular core with a strong rule
  engine, built with the client-relevant `with_*` tags (`clash_api`,
  `grpc`, `gvisor`, `quic`, `utls`, `wireguard`); inbound/server-only
  and big-tree extras (Tailscale, ACME, v2ray stats, DHCP DNS) are
  dropped upstream
- **mihomo** `v1.19.24` — Clash-flavored ergonomics with rich proxy
  groups, fake-IP, and rule providers
- **Live core switching** — change engines from the Home tab whenever
  the tunnel is stopped; configurations don't get tangled across cores
- **Native TUN inbound per core** — each engine consumes the iOS `utun`
  file descriptor directly. No userspace `tun→socks` bridge, no extra
  hop, no extra latency

### App

- **Built-in code editor** — Tree-sitter syntax highlighting for JSON
  and YAML, line numbers, 80-column page guide, no autocorrect
  "helping" you turn `"server"` into `"sever"`
- **Bring configs from anywhere** — type one in, import a file, or paste
  a URL and let the app fetch it
- **Per-core configuration lists** — your Xray setups don't get mixed
  up with your mihomo ones
- **zashboard** — bundled Clash dashboard for live traffic, proxy
  groups, and rule inspection (works with sing-box and mihomo; Xray
  has no clash API)
- **Resource management** — drop `geoip.dat`, `geosite.dat`, `ASN.mmdb`,
  cache files, or PEMs into per-core resource folders; each engine sees
  them in the right place automatically
- **Always-On** — opt in to an `NEOnDemandRuleConnect` rule so iOS
  brings the tunnel back up after a reboot or network flap
- **Custom DNS** — set the resolvers the `NEPacketTunnelNetworkSettings`
  advertises to the system; defaults to `1.1.1.1` / `8.8.8.8`

### Architecture

- **Native Network Extension** — `NEPacketTunnelProvider` owns the
  `utun` device; the extension and the app share configurations through
  an App Group container
- **Prebuilt `EverywhereCore.xcframework`** — Xray, sing-box, and mihomo
  are compiled upstream by
  [NodePassProject/EverywhereCore](https://github.com/NodePassProject/EverywhereCore)
  and consumed as a SwiftPM binary target pinned to a daily-rolled tag
- **Tree-sitter editor** — [Runestone](https://github.com/simonbs/Runestone)
  with the JSON and YAML grammars compiled in
- **Bundled web dashboard** — zashboard is served from the app bundle
  via a custom `zashboard://` URL scheme.

## Getting Started

### Build from Source

```bash
git clone https://github.com/NodePassProject/Everywhere.git
cd Everywhere
./build.sh
open Everywhere.xcodeproj
```

`build.sh` wires the `EverywhereCore` SwiftPM dependency + Runestone +
the bundled zashboard into the Xcode project. The Go cores themselves
are downloaded as a prebuilt xcframework by SwiftPM on first resolve,
and the zashboard is checked into `ThirdParty/zashboard/` as a prebuilt
static bundle — no Node, no pnpm, no Vite step. Plug in your signing
identity and run on a device or the simulator.

To run an `xcodebuild` simulator smoke test as the final step:

```bash
./build.sh --build-app
```

## Patches & Upstream Tracking

The Go cores live in their own repository,
[NodePassProject/EverywhereCore](https://github.com/NodePassProject/EverywhereCore),
which a daily GitHub Actions job auto-releases against the latest
upstream tags. Tag matrix, `gomobile bind` mechanics, and per-core
wiring quirks are documented there. Consumer-side notes for this app
(deployment target, `libresolv.tbd`, zashboard folder reference) live
in [`PATCHES.md`](PATCHES.md). Bump `EVERYWHERE_CORE_VERSION` in
`Scripts/wire_project.rb` and re-run `./build.sh` to roll forward.

## Acknowledgements

Everywhere stands on the shoulders of the projects that do the real
networking work:

- [Xray-core](https://github.com/XTLS/Xray-core)
- [sing-box](https://github.com/SagerNet/sing-box)
- [mihomo](https://github.com/MetaCubeX/mihomo)
- [zashboard](https://github.com/Zephyruso/zashboard)
- [Runestone](https://github.com/simonbs/Runestone)

Huge thanks to everyone who maintains them.

## License

Everywhere is licensed under the [GNU General Public License v3.0](LICENSE).

Copyright © 2026 NodePassProject.

If you ship a modification, ship the source too. That's the deal.

---

If Everywhere makes your phone's network behave the way you want, give
the repo a star — it helps others find it.
