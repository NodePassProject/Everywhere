//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Foundation

// Rewrites the user's config so that, regardless of what they put in it,
// the active core ends up consuming the iOS NEPacketTunnelProvider's utun
// directly via a TUN inbound. Each core handles the FD differently (Xray
// reads `xray.tun.fd` env, sing-box reads it via an injected
// adapter.PlatformInterface, mihomo reads it from `tun.file-descriptor`),
// so this file only ensures the *declaration* of the inbound is present
// with consistent MTU/address/stack — the FD itself is plumbed by
// EverywhereCore at start time.
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
// Strategy: strip any user-declared TUN inbound that would conflict
// (matched by tag for the ones we previously appended, or by being a
// TUN type), then append our canonical one. For mihomo we replace the
// top-level `tun` mapping outright since YAML only allows one.
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

    static func normalizeXray(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        inbounds.removeAll { isEverywhereOrTunInbound($0, typeKey: "protocol") }
        inbounds.append([
            "tag": everywhereTag,
            "protocol": "tun",
            "settings": [
                "name": "utun",
                "MTU": tunnelMTU,
            ],
        ])
        root["inbounds"] = inbounds
        return try serializeJSON(root)
    }

    // MARK: - sing-box (JSON)
    //
    // The TUN fd is injected via adapter.PlatformInterface in Go, which
    // means the JSON only has to declare the inbound shape. `address`
    // takes a list of IPv4 and IPv6 prefixes; we use the same values
    // as NEPacketTunnelNetworkSettings so sing-box's gvisor stack can
    // compute matching gateway addresses.

    static func normalizeSingBox(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        inbounds.removeAll { isEverywhereOrTunInbound($0, typeKey: "type") }
        inbounds.append([
            "type": "tun",
            "tag": everywhereTag,
            "address": [tunnelPrefix, tunnelPrefix6],
            "mtu": tunnelMTU,
            "stack": tunStack,
        ])
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

    private static func isEverywhereOrTunInbound(_ inbound: [String: Any], typeKey: String) -> Bool {
        if (inbound["tag"] as? String) == everywhereTag { return true }
        if (inbound[typeKey] as? String)?.lowercased() == "tun" { return true }
        return false
    }

    // MARK: - mihomo (YAML)
    //
    // mihomo's YAML grammar is loose — it tolerates duplicate keys,
    // mixed tabs/spaces, and other shapes a strict parser rejects. We
    // don't want to gatekeep the user's config, so instead of round-
    // tripping through a parser we excise any column-0 block whose
    // top-level key we own (`tun:`, plus the Clash-API surface:
    // `external-controller(-tls|-unix|-pipe|-cors)?`, `external-ui*`,
    // `external-doh-server`, `secret`) and append our canonical
    // versions. This leaves the rest of the document byte-identical
    // to the user's input.
    //
    // A stripped block ends at the first line that has non-whitespace
    // content at column 0 — comments and blank lines mid-block don't
    // terminate it, matching YAML's own indentation rule that block
    // scope is whatever's *more* indented than the mapping key. When
    // a stripped block ends, the resuming column-0 line is re-checked
    // against the strip-set so back-to-back stripped keys all get
    // caught.

    static func normalizeMihomo(_ content: String) -> String {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var output: [String] = []
        var skipping = false

        for line in normalized.components(separatedBy: "\n") {
            if skipping {
                guard isColumnZeroContent(line) else { continue }
                skipping = false
                // Re-check the resuming line against the strip-set
                // below so back-to-back stripped blocks all get
                // caught.
            }
            if matchesStrippedTopLevelKey(line) {
                skipping = true
                continue
            }
            output.append(line)
        }

        if let last = output.last, !last.isEmpty {
            output.append("")
        }
        output.append(contentsOf: [
            "tun:",
            "  enable: true",
            "  stack: \(tunStack)",
            "  mtu: \(tunnelMTU)",
            "  inet4-address:",
            "    - \(tunnelPrefix)",
            "  inet6-address:",
            "    - \(tunnelPrefix6)",
            "external-controller: \(clashAPIAddress)",
        ])
        return output.joined(separator: "\n")
    }

    // Top-level keys we own and replace wholesale in the user's
    // config. `tun` is our utun declaration; the rest are the Clash
    // RESTful API surface that we pin via a single
    // `external-controller`.
    private static let strippedTopLevelKeys: [String] = [
        "tun",
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
