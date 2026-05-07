//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Foundation
import YAML

// Rewrites the user's config so that, regardless of what they put in it,
// the active core ends up listening on socks5://127.0.0.1:10808 — the
// address PacketTunnelProvider hands to tun2socks. For Xray and sing-box
// we strip any inbound that would collide on the canonical port (either
// the one we previously appended, matched by tag, or one the user wrote
// that happens to listen on 10808 — sing-box would otherwise fail to
// bind with "address already in use") and then append our own. For
// mihomo we just force socks-port, which is the only knob it exposes.
enum ConfigNormalizer {
    static let socksHost = "127.0.0.1"
    static let socksPort = 10808
    static let everywhereTag = "everywhere-socks"

    enum NormalizeError: LocalizedError {
        case notUTF8
        case jsonRootNotObject
        case yamlRootNotMap
        case parseFailed(String)
        case serializeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notUTF8: return "Configuration is not UTF-8."
            case .jsonRootNotObject: return "JSON root must be an object."
            case .yamlRootNotMap: return "YAML root must be a mapping."
            case .parseFailed(let m): return "Could not parse configuration: \(m)"
            case .serializeFailed(let m): return "Could not serialize configuration: \(m)"
            }
        }
    }

    static func normalize(_ content: String, for core: CoreType) throws -> String {
        switch core {
        case .xray: return try normalizeXray(content)
        case .singbox: return try normalizeSingBox(content)
        case .mihomo: return try normalizeMihomo(content)
        }
    }

    // MARK: - Xray (JSON)

    static func normalizeXray(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        inbounds.removeAll { conflictsOnSocksPort($0, portKey: "port") }
        inbounds.append([
            "tag": everywhereTag,
            "port": socksPort,
            "listen": socksHost,
            "protocol": "socks",
            "settings": ["udp": true, "auth": "noauth"],
        ])
        root["inbounds"] = inbounds
        return try serializeJSON(root)
    }

    // MARK: - sing-box (JSON)

    static func normalizeSingBox(_ content: String) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        inbounds.removeAll { conflictsOnSocksPort($0, portKey: "listen_port") }
        inbounds.append([
            "type": "socks",
            "tag": everywhereTag,
            "listen": socksHost,
            "listen_port": socksPort,
        ])
        root["inbounds"] = inbounds
        return try serializeJSON(root)
    }

    private static func conflictsOnSocksPort(_ inbound: [String: Any], portKey: String) -> Bool {
        if (inbound["tag"] as? String) == everywhereTag { return true }
        if let p = inbound[portKey] as? Int, p == socksPort { return true }
        if let p = inbound[portKey] as? String, p == String(socksPort) { return true }
        return false
    }

    // MARK: - mihomo (YAML)

    static func normalizeMihomo(_ content: String) throws -> String {
        let root: Node
        do {
            root = try YAML.load(content)
        } catch {
            throw NormalizeError.parseFailed(error.localizedDescription)
        }
        guard root.isMap else { throw NormalizeError.yamlRootNotMap }
        // mihomo only binds one socks-port; force ours.
        root["socks-port"] = yamlScalar(String(socksPort))
        root["bind-address"] = yamlScalar(socksHost)
        return YAML.dump(root)
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

    private static func yamlScalar(_ s: String) -> Node {
        let n = Node()
        n.set(s)
        return n
    }
}
