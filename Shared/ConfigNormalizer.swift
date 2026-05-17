//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Foundation

// Rewrites the user's config so that, regardless of what they put in it,
// the active core ends up consuming the iOS NEPacketTunnelProvider's utun
// directly via a TUN inbound. Each core handles the FD differently (Xray
// reads `xray.tun.fd` env, sing-box reads it via an injected
// adapter.PlatformInterface, mihomo reads it from `tun.file-descriptor`),
// so this file only ensures the *declaration* of the inbound carries
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
enum ConfigNormalizer {
    static let tunnelHost = "198.18.0.1"
    static let tunnelPrefix = "198.18.0.1/16"
    static let tunnelHost6 = "fd00::1"
    static let tunnelPrefix6 = "fd00::1/126"
    static let tunnelMTU = 1500
    static let everywhereTag = "everywhere-tun"
    static let tunStack = "gvisor"
    static let clashAPIAddress = "127.0.0.1:9090"

    enum NormalizeError: LocalizedError {
        case notUTF8
        case jsonRootNotObject
        case parseFailed(String)
        case serializeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notUTF8: return "Configuration is not UTF-8."
            case .jsonRootNotObject: return "JSON root must be an object."
            case .parseFailed(let m): return "Could not parse configuration: \(m)"
            case .serializeFailed(let m): return "Could not serialize configuration: \(m)"
            }
        }
    }

    static func normalize(_ content: String, for core: CoreType) throws -> String {
        switch core {
        case .xray: return try normalizeXray(content)
        case .singbox: return try normalizeSingBox(content)
        case .mihomo: return normalizeMihomo(content)
        }
    }

    // MARK: - Xray (JSON)
    //
    // Xray's TUN inbound docs say port/listen are ignored for protocol
    // "tun". `name` is required by the schema and used on macOS to pick
    // a utunN device — on iOS it's overridden by the FD coming through
    // the `xray.tun.fd` env var, but the schema still wants a value.
    // We patch the first existing TUN inbound to force protocol/tag and
    // settings.name/MTU; other top-level inbound fields (sniffing,
    // streamSettings, …) and other `settings.*` keys are preserved. If
    // none exists we append a minimal one.

    static func normalizeXray(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        if let first = inbounds.firstIndex(where: { isTunInbound($0, typeKey: "protocol") }) {
            var patched = inbounds[first]
            patched["protocol"] = "tun"
            patched["tag"] = everywhereTag
            var settings = (patched["settings"] as? [String: Any]) ?? [:]
            settings["name"] = "utun"
            settings["MTU"] = tunnelMTU
            patched["settings"] = settings
            inbounds[first] = patched
            removeOtherTunInbounds(&inbounds, keep: first, typeKey: "protocol")
        } else {
            inbounds.append([
                "tag": everywhereTag,
                "protocol": "tun",
                "settings": [
                    "name": "utun",
                    "MTU": tunnelMTU,
                ],
            ])
        }
        root["inbounds"] = inbounds
        return try serializeJSON(root)
    }

    // MARK: - sing-box (JSON)
    //
    // The TUN fd is injected via adapter.PlatformInterface in Go, which
    // means the JSON only has to declare an inbound the NE can recognize.
    // `address` mirrors what NEPacketTunnelNetworkSettings advertises so
    // the gvisor stack can compute matching gateway addresses; `stack`
    // is forced to gvisor because the system stack needs syscalls the
    // NE doesn't expose. `interface_name` and `platform` are stripped —
    // the NE owns the utun. Everything else stays.

    static func normalizeSingBox(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        if let first = inbounds.firstIndex(where: { isTunInbound($0, typeKey: "type") }) {
            var patched = inbounds[first]
            patched["type"] = "tun"
            patched["tag"] = everywhereTag
            patched["address"] = [tunnelPrefix, tunnelPrefix6]
            patched["mtu"] = tunnelMTU
            patched["stack"] = tunStack
            patched.removeValue(forKey: "interface_name")
            patched.removeValue(forKey: "platform")
            inbounds[first] = patched
            removeOtherTunInbounds(&inbounds, keep: first, typeKey: "type")
        } else {
            inbounds.append([
                "type": "tun",
                "tag": everywhereTag,
                "address": [tunnelPrefix, tunnelPrefix6],
                "mtu": tunnelMTU,
                "stack": tunStack,
            ])
        }
        root["inbounds"] = inbounds

        // Strip outbound interface-binding options from `route`. Both
        // would have sing-box's dialer pin sockets to a specific
        // physical interface:
        //
        //  - `auto_detect_interface` routes through
        //    `NetworkManager.AutoDetectInterfaceFunc`, which consults
        //    our no-op DefaultInterfaceMonitor and fails with
        //    ErrNoRoute.
        //  - `default_interface` names a specific NIC (e.g. "en0"),
        //    which inside an NEPacketTunnelProvider may resolve to
        //    something that doesn't behave as expected.
        //
        // iOS already routes sockets created inside the NE through
        // the underlying physical interface, so neither option is
        // needed. Remove unconditionally.
        if var route = root["route"] as? [String: Any] {
            route.removeValue(forKey: "auto_detect_interface")
            route.removeValue(forKey: "default_interface")
            root["route"] = route
        }

        // Pin the Clash API to 127.0.0.1:9090 and discard every other
        // `clash_api` option (external_ui, secret, default_mode,
        // access_control_*, …). The host app attaches to the
        // controller by hitting this exact address; a user-supplied
        // secret or non-loopback bind would lock us out. Leave any
        // sibling `experimental.*` blocks (e.g. `cache_file`) alone.
        var experimental = (root["experimental"] as? [String: Any]) ?? [:]
        experimental["clash_api"] = ["external_controller": clashAPIAddress]
        root["experimental"] = experimental

        return try serializeJSON(root)
    }

    private static func isTunInbound(_ inbound: [String: Any], typeKey: String) -> Bool {
        (inbound[typeKey] as? String)?.lowercased() == "tun"
    }

    // Reverse-iterate so removals at higher indices don't shift the
    // index we want to keep.
    private static func removeOtherTunInbounds(_ inbounds: inout [[String: Any]], keep: Int, typeKey: String) {
        for idx in inbounds.indices.reversed() where idx != keep && isTunInbound(inbounds[idx], typeKey: typeKey) {
            inbounds.remove(at: idx)
        }
    }

    // MARK: - mihomo (YAML)
    //
    // mihomo's YAML grammar is loose — it tolerates duplicate keys,
    // mixed tabs/spaces, and other shapes a strict parser rejects. We
    // don't want to gatekeep the user's config, so we walk lines and
    // touch only what has to change:
    //
    //  - At `tun:` (column 0), enter sub-block mode. For each sub-key
    //    in `mihomoTunForcedKeys` ∪ `mihomoTunStrippedKeys`, drop that
    //    line and any deeper-indented children; everything else
    //    (loopback-address, dns-hijack, route-address, strict-route,
    //    udp-timeout, endpoint-independent-nat, …) passes through.
    //    After the block, inject our forced lines at the sub-block's
    //    detected indent.
    //  - At any Clash-API surface key (`external-controller*`,
    //    `external-ui*`, `external-doh-server`, `secret`), drop the
    //    entire sub-block; our canonical `external-controller` is
    //    appended at the end.

    // Force-set sub-keys inside `tun:`. We drop the user's version and
    // emit ours at the end of the block.
    private static let mihomoTunForcedKeys: Set<String> = [
        "enable",
        "stack",
        "mtu",
        "inet4-address",
        "inet6-address",
    ]

    // Stripped sub-keys inside `tun:`. We drop the user's version and
    // don't emit a replacement — EverywhereCore plumbs the fd through
    // the Go bridge, and a user-supplied `device` or `file-descriptor`
    // would compete with that.
    private static let mihomoTunStrippedKeys: Set<String> = [
        "device",
        "file-descriptor",
    ]

    static func normalizeMihomo(_ content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var i = 0
        var sawTunBlock = false

        while i < lines.count {
            let line = lines[i]

            if matchesTopLevelKey(line, key: "tun") {
                sawTunBlock = true
                // Normalize the header to a bare `tun:` so an inline
                // scalar (`tun: false`) or trailing comment can't
                // confuse the YAML parser once we add children.
                output.append("tun:")
                i += 1
                var subIndent: Int? = nil
                while i < lines.count {
                    let sub = lines[i]
                    if isColumnZeroContent(sub) { break }
                    if let key = extractSubKey(sub) {
                        let indent = leadingWhitespaceCount(sub)
                        if subIndent == nil { subIndent = indent }
                        if mihomoTunForcedKeys.contains(key) || mihomoTunStrippedKeys.contains(key) {
                            i += 1
                            // Skip any deeper-indented children of the
                            // dropped key, tolerating blank lines.
                            while i < lines.count {
                                let next = lines[i]
                                if isColumnZeroContent(next) { break }
                                let trimmed = next.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty || leadingWhitespaceCount(next) > indent {
                                    i += 1
                                    continue
                                }
                                break
                            }
                            continue
                        }
                    }
                    output.append(sub)
                    i += 1
                }
                output.append(contentsOf: mihomoTunForcedLines(indent: subIndent ?? 2))
                continue
            }

            if matchesStrippedTopLevelKey(line) {
                i += 1
                while i < lines.count {
                    if isColumnZeroContent(lines[i]) { break }
                    i += 1
                }
                continue
            }

            output.append(line)
            i += 1
        }

        if !sawTunBlock {
            if let last = output.last, !last.isEmpty {
                output.append("")
            }
            output.append("tun:")
            output.append(contentsOf: mihomoTunForcedLines(indent: 2))
        }

        if let last = output.last, !last.isEmpty {
            output.append("")
        }
        output.append("external-controller: \(clashAPIAddress)")

        return output.joined(separator: "\n")
    }

    private static func mihomoTunForcedLines(indent: Int) -> [String] {
        let pad = String(repeating: " ", count: max(indent, 1))
        let listPad = pad + "  "
        return [
            "\(pad)enable: true",
            "\(pad)stack: \(tunStack)",
            "\(pad)mtu: \(tunnelMTU)",
            "\(pad)inet4-address:",
            "\(listPad)- \(tunnelPrefix)",
            "\(pad)inet6-address:",
            "\(listPad)- \(tunnelPrefix6)",
        ]
    }

    // Top-level keys whose entire sub-block we drop wholesale. `tun` is
    // handled by the sub-key walker above and is intentionally not in
    // this list.
    private static let strippedTopLevelKeys: [String] = [
        "external-controller",
        "external-controller-tls",
        "external-controller-unix",
        "external-controller-pipe",
        "external-controller-cors",
        "external-ui",
        "external-ui-url",
        "external-ui-name",
        "external-doh-server",
        "secret",
    ]

    private static func matchesStrippedTopLevelKey(_ line: String) -> Bool {
        for key in strippedTopLevelKeys {
            if matchesTopLevelKey(line, key: key) { return true }
        }
        return false
    }

    // True when the line declares a top-level mapping with the given
    // key. Matches `key:`, `key: <value>`, `key:  # comment`, etc.
    // — but not `keyfoo:`, `  key:` (nested), or `# key:` (comment).
    private static func matchesTopLevelKey(_ line: String, key: String) -> Bool {
        guard line.hasPrefix(key + ":") else { return false }
        let rest = line.dropFirst(key.count + 1)
        guard let next = rest.first else { return true }
        return next == " " || next == "\t" || next == "#"
    }

    // True when the line has non-whitespace content at column 0 that
    // isn't a comment. Inside a block we treat blank lines and column-0
    // comments as still inside; only real content resumes the document.
    private static func isColumnZeroContent(_ line: String) -> Bool {
        guard let first = line.first else { return false }
        if first == " " || first == "\t" { return false }
        if first == "#" { return false }
        return true
    }

    // Returns the bare sub-key on a line like "  loopback-address: …"
    // or "  stack: gvisor". Returns nil for blank lines, comments, list
    // items ("  - foo"), or otherwise shapes that don't have a leading
    // `key:`.
    private static func extractSubKey(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first else { return nil }
        if first == "#" || first == "-" { return nil }
        guard let colon = trimmed.firstIndex(of: ":") else { return nil }
        let key = String(trimmed[..<colon])
        return key.isEmpty ? nil : key
    }

    private static func leadingWhitespaceCount(_ line: String) -> Int {
        var count = 0
        for c in line {
            if c == " " || c == "\t" { count += 1 } else { break }
        }
        return count
    }

    // MARK: - Helpers

    private static func parseJSONObject(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8) else { throw NormalizeError.notUTF8 }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
        } catch {
            throw NormalizeError.parseFailed(error.localizedDescription)
        }
        guard let object = parsed as? [String: Any] else {
            throw NormalizeError.jsonRootNotObject
        }
        return object
    }

    private static func serializeJSON(_ object: [String: Any]) throws -> String {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            throw NormalizeError.serializeFailed(error.localizedDescription)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
