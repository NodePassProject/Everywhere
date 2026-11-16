# Patches

Consumer-side notes for `Everywhere` (iOS). Build mechanics, upstream
tag matrix, `gomobile bind` flags, and per-core wiring quirks now live
upstream at
[NodePassProject/EverywhereCore](https://github.com/NodePassProject/EverywhereCore) —
see its README and `Scripts/build.sh` if you need to touch the Go side.

## EverywhereCore version range

`Scripts/wire_project.rb` pins the SwiftPM dependency to a calver range
rather than an exact tag:

```ruby
EVERYWHERE_CORE_MIN_VERSION = '2026.11.15'
EVERYWHERE_CORE_REQ = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => EVERYWHERE_CORE_MIN_VERSION }
```

`upToNextMajor` against a `vYYYY.MM.DD` tag accepts every release inside
the same calendar year, so a fresh `xcodebuild -resolvePackageDependencies`
rolls forward to the newest daily tag automatically. Bump the floor only
when the upstream drops a tag with a breaking-change marker or when you
want to abandon stale releases. Tracking `branch main` is **not** a viable
alternative here: upstream's main-branch `Package.swift` references a
local `EverywhereCore.xcframework` path that only exists during their dev
work — `Scripts/release.sh` rewrites it to `binaryTarget(url:, checksum:)`
on each tag, so only tagged releases are consumable downstream.

## SwiftPM packages

`Scripts/wire_project.rb` registers four remote packages on the project:

| Package                                                    | Targets   | Pin                          |
| ---------------------------------------------------------- | --------- | ---------------------------- |
| `NodePassProject/EverywhereCore`                           | app + NE  | `upToNextMajor 2026.11.15`   |
| `simonbs/Runestone`                                        | app       | `upToNextMajor 0.5.0`        |
| `simonbs/TreeSitterLanguages` (JSON + YAML products)       | app       | `upToNextMajor 0.1.10`       |
| `Argsment/YAML`                                            | app       | `branch main`                |

Runestone is iOS-only — it powers the Tree-sitter editor that
ConfigEditor uses. The macOS sibling uses an `NSTextView`-backed editor
instead and pulls no Runestone-style dependencies.

## Wiring requirements `Scripts/wire_project.rb` enforces

These are not patches — they are settings that the Xcode project needs
on both targets for the framework to load and the Go runtime to find
its DNS resolver. The wire script is idempotent, so running it after
an Xcode UI edit reasserts them.

- `IPHONEOS_DEPLOYMENT_TARGET = 15.0` — the app's lower bound. Upstream
  `EverywhereCore`'s `Package.swift` requires `.iOS(.v15)`, so this is
  the floor.
- `libresolv.tbd` linked into both `Everywhere` and `EverywhereNE` —
  the Go runtime's DNS resolver path on darwin pulls `res_*` symbols
  from `libresolv`.
- No manual `Embed Frameworks` entry for the SwiftPM product. Xcode
  auto-embeds binary targets that appear in the Frameworks build phase.
  Adding the product to a Copy Files phase by `productRef` double-
  resolves and fails with `No such file or directory` on the bare
  product name.
- No dashboard resource bundle. The dashboard used to be a prebuilt
  zashboard checked into `ThirdParty/` and registered as a folder
  reference on the app target; it is native SwiftUI now, and the wire
  script removes that reference from projects wired before the change.

## Dashboard ↔ core wiring

The native dashboard (`Everywhere/Dashboard/`) talks to the running
core in one of two ways, hidden behind `DashboardBackend`:

- **mihomo, sing-box** — the clash API. While the dashboard is enabled
  `ConfigNormalizer` forces the controller to `127.0.0.1:9090` and sets
  a `secret`. Loopback is reachable by every app on the device, so the
  controller is never left open: the Network Extension generates the
  secret on first start and keeps it in the App Group defaults
  (`EVCore.makeControllerSecret()`); the app only reads it.
- **Xray-core** — no clash API. EverywhereCore's `Control(method,
  params)` serves the dashboard in-process and the app reaches it with
  `sendProviderMessage` (`{"type": "control", …}` in
  `PacketTunnelProvider.handleAppMessage`). For traffic figures the
  normalizer adds `stats: {}` and `policy.system.statsOutbound*`.
  A balancer pick is an in-memory override in Xray, so it is stored per
  configuration (`EVCore.setXraySelection`) and replayed by the
  extension on the next start.

`Control` exists from EverywhereCore `v2026.11.15`, which is why
`EVERYWHERE_CORE_MIN_VERSION` is pinned there. To develop against a Go
symbol no release has yet, wire a local checkout:

```bash
( cd ../EverywhereCore && Scripts/build.sh )
EVERYWHERE_CORE_PATH=../EverywhereCore ./build.sh
```

## NEPacketTunnelProvider on iOS

The Network Extension is shipped as an `.appex` bundled in
`Everywhere.app/PlugIns/`. The provider is loaded by the system's
`nesessionmanager`, talks to the app over the App Group container
`group.com.argsment.Everywhere`, and owns the `utun` device. The
extension links against the same `EverywhereCore` SwiftPM product as
the app and resolves the framework at runtime from the host app's
`Frameworks/` directory — only the app target embeds, not the extension.
