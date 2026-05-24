//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

// Rewrites the user's config so that, regardless of what they put in it,
// the active core ends up consuming the iOS NEPacketTunnelProvider's utun
// directly via a TUN inbound. Each core handles the FD differently (Xray
// reads `xray.tun.fd` env, sing-box reads it via an injected
// adapter.PlatformInterface, mihomo reads it from `tun.file-descriptor`),
// so the normalizers only ensure the *declaration* of the inbound carries
// the fields that have to match what the NE configured — the FD itself
// is plumbed by EverywhereCore at start time.
//
// We also pin the Clash RESTful API to 127.0.0.1:9090 with no
// auth, no dashboard, and no CORS allow-list — that's the address
// the host app attaches to for runtime queries, and a user-supplied
// secret or non-loopback bind would otherwise lock us out. For
// sing-box we overwrite `experimental.clash_api` with a single
// `external_controller` field; for mihomo we strip the user's
// top-level `external-controller*`, `external-ui*`,
// `external-doh-server`, and `secret` keys and append our own.
//
// TUN strategy: patch the user's TUN inbound (if any) in place to
// force the fields the iOS NE depends on (type, address, mtu, stack
// for sing-box; enable/stack/mtu/inet4-address/inet6-address for
// mihomo) and strip the ones that conflict with the NE-supplied fd
// (`interface_name`/`platform` for sing-box; `device`/`file-descriptor`
// for mihomo). Everything else the user wrote on the TUN inbound —
// `loopback_address` / `loopback-address`, `dns_*` / `dns-hijack`,
// `route_address` / `route-address`, `strict_route`, `udp_timeout`,
// `exclude_mptcp`, `endpoint-independent-nat`, etc. — flows through
// untouched. If no TUN inbound is declared, we append a minimal
// canonical one. For mihomo the sub-block is walked line by line;
// no YAML parser is involved.
//
// The per-core rewriting lives in one `CoreNormalizer` per core
// (`XrayNormalizer`, `SingBoxNormalizer`, `MihomoNormalizer`); this
// type is just the entry point that dispatches to the right one.
enum ConfigNormalizer {
    static func normalize(_ content: String, for core: CoreType) throws -> String {
        switch core {
        case .xray: return try XrayNormalizer.normalize(content)
        case .singbox: return try SingBoxNormalizer.normalize(content)
        case .mihomo: return try MihomoNormalizer.normalize(content)
        }
    }
}
