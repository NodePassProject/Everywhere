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

<div>
    <a href="https://apps.apple.com/app/id6766003090">
        <img width="128" src="https://storage.argsment.com/Download%20on%20the%20App%20Store.png" />
    </a>
</div>

</div>

---

## Why Everywhere?

Most networking apps lock you into a single backend and a single way of
doing things. Everywhere doesn't. It bundles three of the most popular
open-source proxy cores in one place, gives them a clean home, and lets
you move between them whenever you like.

## Supported Protocols

| Protocol         | Xray-core    | sing-box     | mihomo       | Everywhere   |
|------------------|--------------|--------------|--------------|--------------|
| VLESS            | ✓            | ✓            | ✓            | ✓            |
| VMess            | ✓            | ✓            | ✓            | ✓            |
| Trojan           | ✓            | ✓            | ✓            | ✓            |
| Shadowsocks      | ✓            | ✓            | ✓            | ✓            |
| ShadowsocksR     | —            | ✓            | ✓            | ✓            |
| Hysteria2        | ✓            | ✓            | ✓            | ✓            |
| TUIC             | —            | ✓ (v5)       | ✓ (v4 + v5)  | ✓ (v4 + v5)  |
| WireGuard        | ✓            | ✓            | ✓            | ✓            |
| Naive            | —            | ✓            | —            | ✓            |
| AnyTLS           | —            | ✓            | ✓            | ✓            |
| SSH              | —            | ✓            | ✓            | ✓            |
| Tor              | —            | ✓            | —            | ✓            |
| HTTP / SOCKS     | ✓            | ✓            | ✓            | ✓            |
| Tailscale        | -            | ✓            | ✓            | ✓            |

## Supported Cores

| Core      | Config    | Supported? |
|-----------|-----------|------------|
| Xray-core | JSON      | ✓          |
| sing-box  | JSON      | ✓          |
| mihomo    | YAML      | ✓          |

## Features

- **Maximum flexibility** - Switch cores whenever you want. Three
  engines live side by side in the same app, one tap apart.
- **Universal experience** - Same UI, same editor, same dashboard
  wiring no matter which core you picked. Switching engines doesn't
  mean relearning the app.
- **Low overhead** - Only one core runs at a time, talking directly
  to the iOS `utun` device. No userspace `tun→socks` bridge, no
  extra hops, no idle daemons in the background.
- **BYOC (Bring Your Own Config)** - Paste a URL, import a file, or
  type one in. Whatever config you already have, it just works — no
  conversion, no lock-in.
- **Configuration as craft** - Your config decides how your phone
  meets the internet. The editor inside Everywhere gives it the
  treatment it deserves, so writing it feels less like filling a
  form and more like making something.
- **Total transparency** - Nothing about the tunnel is hidden from
  you. Every byte, every connection, every routing decision shows
  up the moment it happens, right inside the app.
- **Engineered isolation** - Three engines in one app, never in
  each other's way. Each lives in its own world, with its own
  files, its own state, its own rules.
- **Beyond reboot** - Reboots, network drops, the leap from
  cellular to Wi-Fi — your tunnel survives all of it. You don't
  open the app; iOS does that for you whenever the network needs
  the tunnel back.
- **Sovereign resolution** - Every connection starts with a name
  lookup. You decide who gets to answer that question — Cloudflare,
  Google, your own resolver, whatever you trust.

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
