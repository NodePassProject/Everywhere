# Everywhere

**One iPhone app. Three networking engines. Your rules.**

Everywhere is a powerful proxy and tunneling app for iOS that puts you in
charge of how your device talks to the internet. Bring your own
configuration, pick the engine you trust, and flip a switch. That's it.

---

## Why Everywhere?

Most networking apps lock you into a single backend and a single way of
doing things. Everywhere doesn't. It bundles three of the most popular
open-source proxy cores in one place, gives them a clean home, and lets
you move between them whenever you like.

- **Choose your engine.** Xray, sing-box, or mihomo — switch with a tap.
- **Edit configs on-device.** A real code editor with line numbers,
  syntax highlighting, and a tab key that does what you'd expect.
- **Bring configs from anywhere.** Type one in, import a file, or paste
  a URL and let the app fetch it.

---

## The three engines

Everywhere doesn't reinvent networking — it stands on the shoulders of
projects loved by the community.

| Engine     | Best for                                         | Configs |
| ---------- | ------------------------------------------------ | ------- |
| **Xray**   | Battle-tested, broad protocol support            | JSON    |
| **sing-box** | Modern, modular, great rule engine             | JSON    |
| **mihomo** | Clash-flavored ergonomics, rich proxy groups     | YAML    |

Each engine keeps its own list of configurations, so your Xray setups
don't get tangled up with your mihomo ones. Pick a core on the Home
screen, choose a configuration, and start the tunnel.

---

## Editing configurations

The built-in editor is the kind of thing you'd actually want to use:

- Tree-sitter syntax highlighting for JSON and YAML
- Line numbers and an 80-column page guide
- Light and dark themes that follow your system
- No autocorrect "helping" you turn `"server"` into `"sever"`

When you save, Everywhere stores the configuration locally. Nothing
leaves your device unless you ask it to.

---

## Getting it running

This is the source for the iOS app. To build it yourself:

```bash
./build.sh
open Everywhere.xcodeproj
```

The script fetches the upstream sources, builds the Go core into a
framework, and wires it into the Xcode project. Then open the project,
plug in your signing identity, and run on a device or the simulator.

---

## Credits

Everywhere wouldn't exist without the work of these wonderful projects:

- [Xray-core](https://github.com/XTLS/Xray-core)
- [sing-box](https://github.com/SagerNet/sing-box)
- [mihomo](https://github.com/MetaCubeX/mihomo)
- [tun2socks](https://github.com/xjasonlyu/tun2socks)
- [yacd](https://github.com/MetaCubeX/Yacd-meta)
- [Runestone](https://github.com/simonbs/Runestone)

Huge thanks to everyone who maintains them.

---

## License

Everywhere is licensed under the **GNU General Public License v3.0**.

Copyright © 2026 Argsment Limited.

If you ship a modification, ship the source too. That's the deal.
