# Patches

Ledger of every change made on top of upstream sources or that is needed
to make the three upstreams co-exist in one Go module. When bumping an
upstream tag, walk this list and re-apply anything still needed.

## Pinned tags

| Upstream  | Tag       | Module path                          |
| --------- | --------- | ------------------------------------ |
| Xray-core | v26.3.27  | github.com/xtls/xray-core            |
| sing-box  | v1.13.11  | github.com/sagernet/sing-box         |
| mihomo    | v1.19.24  | github.com/metacubex/mihomo          |

## go.mod overrides (`EverywhereCore/go.mod`)

### tools.go to anchor `golang.org/x/mobile/bind`

`gomobile bind` invokes `gobind` from a temporary directory, and `gobind`
imports `golang.org/x/mobile/bind`. In module mode, that import has to
appear somewhere in our module's import graph for `go list` to find it.
`EverywhereCore/tools.go` does so under `//go:build tools`, so the
package never compiles into the framework but `go.mod` keeps the require.

**On upstream bump.** No action — this is a gomobile mechanic.

### `-ldflags="-s -w"` so archive validation doesn't demand a dSYM

`Scripts/build_core.sh` strips Go-side debug info via
`-ldflags="-s -w"` (`-s` = strip symbol table, `-w` = strip DWARF). With
no DWARF in the binary the validator does not look for a dSYM and the
warning goes away. Side effects:

- Framework is much smaller.
- No Go-side symbolication in iOS crash reports.

**On upstream bump.** No action — this is a gomobile mechanic.

## Source patches

None right now. Xray-core, sing-box, and mihomo all build unmodified
at the pinned tags.

## Wiring quirks per core

These are not patches but call-site requirements that the wrappers in
`EverywhereCore/` already encode. Listed here so they survive a future
rewrite.

### TUN inbound: each core consumes the iOS utun fd directly

We don't ship a userland tun→socks bridge. Each core owns its own TUN
inbound, with the FD plumbed differently:

- **Xray-core**: read from the `xray.tun.fd` env var (see
  `proxy/tun/tun_darwin.go`). `EverywhereCore/xray.go` sets it before
  `core.StartInstance`.
- **sing-box**: read via an `adapter.PlatformInterface` whose
  `OpenInterface` is invoked by the tun inbound. The interface is
  registered on the `box.Options.Context` via
  `service.ContextWith[adapter.PlatformInterface]`. See
  `EverywhereCore/singbox.go` for the minimal implementation; only
  `OpenInterface`, `UnderNetworkExtension` and the
  `CreateDefaultInterfaceMonitor` no-op stub do meaningful work.
- **mihomo**: written into `cfg.General.Tun.FileDescriptor` between
  `executor.ParseWithBytes` and `hub.ApplyConfig`. The wire-level
  YAML key is `tun.file-descriptor`, but we keep the FD out of the
  config string so users can't accidentally pin a stale value.

For sing-box and mihomo we `syscall.Dup` the FD before handing it to
sing-tun — its `Close()` always closes the wrapped `os.File`, so a
non-dup'd path would tear down NEPacketTunnelFlow's underlying utun
out from under the Network Extension. Xray's iOS tun_darwin path
checks `ownsFd` and skips `Close()` when the FD came in externally,
so we don't dup there.

### Xray-core: needs `_ "main/distro/all"` and `_ "main/json"`

`distro/all` registers every inbound/outbound/transport via init().
`main/json` registers the JSON config loader and transitively pulls
in `infra/conf` and `proxy/tun`, which is what registers the `tun`
inbound type in the JSON loader's protocol map.
`core.StartInstance("json", …)` fails without both. See
`EverywhereCore/xray.go`.

### sing-box: gomobile bind needs `-tags=with_*`

sing-box keeps optional subsystems behind Go build tags. With no tag
set, the corresponding `*_stub.go` files compile in and the feature
returns "not included in this build" errors at runtime.

`Scripts/build_core.sh` enables the full sing-box tag matrix minus
three known-broken-on-iOS or known-deprecated tags (see exclusions
below). The advertised list is reproducible — re-derive it any time
with:

```bash
grep -rh '^//go:build' ThirdParty/sing-box/ \
  | grep -oE 'with_[a-zA-Z0-9_]+' | sort -u
```

Currently shipped (12):

| Tag                   | Unlocks                                        |
| --------------------- | ---------------------------------------------- |
| `with_acme`           | ACME certificate provisioning for inbounds     |
| `with_ccm`            | Apple-CCM service registry                     |
| `with_clash_api`      | clash REST/WebSocket API (yacd talks to this)  |
| `with_dhcp`           | DHCP DNS transport                             |
| `with_grpc`           | gRPC transport                                 |
| `with_gvisor`         | gVisor netstack for TUN inbound                |
| `with_ocm`            | Outbound Connection Management                 |
| `with_quic`           | QUIC transports — Hysteria/Hysteria2/TUIC      |
| `with_tailscale`      | Tailscale endpoint                             |
| `with_utls`           | uTLS fingerprinting (and inbound REALITY)      |
| `with_v2ray_api`      | v2ray stats API                                |
| `with_wireguard`      | wireguard outbound                             |

Excluded:

| Tag                   | Why                                                                |
| --------------------- | ------------------------------------------------------------------ |
| `with_naive_outbound` | Pulls in `sagernet/cronet-go/all`, which has no Go files for iOS.  |
| `with_ech`            | Deprecated in 1.13 — ECH moved to Go stdlib; tag's `_stub.go` now intentionally fails the build with that explanation. |
| `with_reality_server` | Deprecated in 1.13 — folded into `with_utls`; same intentional-build-error pattern. |

When sing-box adds a new `with_*` stub, the grep above will surface
it; append to `BUILD_TAGS` in `Scripts/build_core.sh`. If a new tag's
stub fails the build the way `with_ech` does, that's sing-box telling
you the feature has been merged elsewhere.

### sing-box: must pass `include.Context(ctx)` into `box.New`

sing-box 1.10+ requires the inbound/outbound/endpoint/DNS-transport/
service registries to be attached to the context that `box.New` is
called with. The `github.com/sagernet/sing-box/include` package's
`Context(ctx)` helper bundles them in one call.

If you only pass `context.Background()`, `box.New` parses the JSON but
cannot instantiate `socks`, `direct`, `vmess`, etc., and returns an
error. From iOS's perspective the Network Extension dies the instant
the tunnel comes up. See `EverywhereCore/singbox.go`.

**On upstream bump.** Verify `include.Context` is still the canonical
entry point — the registry surface has been refactored a couple of
times in 1.x.

### mihomo: must call `hub.ApplyConfig`, not `executor.ApplyConfig`

mihomo has two `ApplyConfig` functions:

- `executor.ApplyConfig(cfg, force)` — sets up DNS, proxies, rules,
  inbound listeners (socks-port, http-port, mixed-port…). Does **not**
  start the external-controller HTTP/WS API server.
- `hub.ApplyConfig(cfg)` — wraps `applyRoute(cfg)` (which calls
  `route.ReCreateServer` and *that* boots the API server) followed by
  `executor.ApplyConfig(cfg, true)`.

If you call only `executor.ApplyConfig`, the SOCKS inbound and the
tunnel work fine, but the clash REST API never starts and yacd shows
"cannot connect to 127.0.0.1:9090". `EverywhereCore/mihomo.go` calls
`hub.ApplyConfig`.

`hub.ApplyConfig` returns no error — failures inside it are logged via
mihomo's own logger.

When future bumps require source-level changes:

1. Apply the change to `ThirdParty/<repo>/...`.
2. Append a section here describing **why**, **what file**, and **what
   the upstream-correct fix would be** (so we can drop the patch when
   upstream catches up).
3. Optional: stash the patch as `Scripts/patches/<repo>-NN-name.patch`
   so `Scripts/fetch_third_party.sh` can re-apply it after a fresh clone.
