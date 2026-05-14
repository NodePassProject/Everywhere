# Patches

Consumer-side notes for `Everywhere` (iOS). Build mechanics, upstream
tag matrix, `gomobile bind` flags, and per-core wiring quirks now live
upstream at
[NodePassProject/EverywhereCore](https://github.com/NodePassProject/EverywhereCore) —
see its README and `Scripts/build.sh` if you need to touch the Go side.

## Pinned EverywhereCore version

`Scripts/wire_project.rb` pins the SwiftPM dependency to a single tag:

```ruby
EVERYWHERE_CORE_VERSION = '2026.05.14'
```

Bump that string and rerun `./build.sh` to roll forward. The upstream
ships a daily-rolled `vYYYY.MM.DD` tag whenever Xray / sing-box / mihomo
release; pick the latest tag that has had time to soak.

## SwiftPM packages

`Scripts/wire_project.rb` registers four remote packages on the project:

| Package                                                    | Targets   | Pin                          |
| ---------------------------------------------------------- | --------- | ---------------------------- |
| `NodePassProject/EverywhereCore`                           | app + NE  | `exactVersion 2026.05.14`    |
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
- `yacd-gh-pages` registered as a folder reference (blue folder,
  `lastKnownFileType = folder`) on the app target's Resources phase —
  yacd's `index.html` references its bundled assets via relative paths
  (`./assets/index-*.js`), which only works if Xcode preserves the
  directory layout on copy.

## NEPacketTunnelProvider on iOS

The Network Extension is shipped as an `.appex` bundled in
`Everywhere.app/PlugIns/`. The provider is loaded by the system's
`nesessionmanager`, talks to the app over the App Group container
`group.com.argsment.Everywhere`, and owns the `utun` device. The
extension links against the same `EverywhereCore` SwiftPM product as
the app and resolves the framework at runtime from the host app's
`Frameworks/` directory — only the app target embeds, not the extension.
