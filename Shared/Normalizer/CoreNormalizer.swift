//
//  CoreNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

// A config rewriter for one proxy core. `ConfigNormalizer.normalize(_:for:)`
// dispatches to a concrete conformer (XrayNormalizer / SingBoxNormalizer /
// MihomoNormalizer) per `CoreType`. Shared constants and the log-verbosity
// cap live in the protocol extension below so every core reaches them
// unqualified; JSON-only helpers live on `JSONCoreNormalizer`.
protocol CoreNormalizer {
    static func normalize(_ content: String) throws -> String
}

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

// MARK: - Shared constants & log capping

extension CoreNormalizer {
    static var tunnelHost: String { "198.18.0.1" }
    static var tunnelPrefix: String { "198.18.0.1/16" }
    static var tunnelHost6: String { "fd00::1" }
    static var tunnelPrefix6: String { "fd00::1/126" }
    static var tunnelMTU: Int { 1500 }
    static var everywhereTag: String { "everywhere-tun" }
    static var tunStack: String { "gvisor" }
    static var clashAPIAddress: String { "127.0.0.1:9090" }

    // Returns `level` clamped so it is no more verbose than `floor`.
    // Levels in `order` run most-verbose → quietest. A nil/empty/unknown
    // input becomes `floor`; a value already at or below the floor is
    // returned unchanged — we never raise verbosity, so a user who chose
    // `error`/`silent` for battery keeps it.
    //
    // High-verbosity logging in the Network Extension is a steady battery
    // + flash-I/O drain: every connection and DNS query gets formatted and
    // written, and for sing-box/mihomo it's also streamed over the
    // clash-API `/logs` socket.
    static func cappedLevel(_ level: String?, order: [String], floor: String) -> String {
        guard let level = level?.trimmingCharacters(in: .whitespaces), !level.isEmpty else { return floor }
        guard let idx = order.firstIndex(of: level.lowercased()),
              let floorIdx = order.firstIndex(of: floor) else { return level }
        return idx < floorIdx ? floor : level
    }
}

// MARK: - JSON cores (Xray, sing-box)

// Helpers shared by the JSON-configured cores. mihomo is YAML and walks
// lines instead, so it deliberately doesn't get these.
protocol JSONCoreNormalizer: CoreNormalizer {}

extension JSONCoreNormalizer {
    static func parseJSONObject(_ content: String) throws -> [String: Any] {
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

    static func serializeJSON(_ object: [String: Any]) throws -> String {
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

    static func isTunInbound(_ inbound: [String: Any], typeKey: String) -> Bool {
        (inbound[typeKey] as? String)?.lowercased() == "tun"
    }

    // Reverse-iterate so removals at higher indices don't shift the
    // index we want to keep.
    static func removeOtherTunInbounds(_ inbounds: inout [[String: Any]], keep: Int, typeKey: String) {
        for idx in inbounds.indices.reversed() where idx != keep && isTunInbound(inbounds[idx], typeKey: typeKey) {
            inbounds.remove(at: idx)
        }
    }

    // A log destination that writes to disk — anything other than the
    // stdout/stderr sentinels (or Xray's `none`). Used to redirect file
    // logging off-disk; os_log still captures stderr, so logs stay
    // reachable from Console without the per-event disk write.
    static func isLogFilePath(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        return !v.isEmpty && v != "none" && v != "stdout" && v != "stderr"
    }
}
