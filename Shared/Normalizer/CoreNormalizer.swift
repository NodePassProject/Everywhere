//
//  CoreNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

protocol CoreNormalizer {
    static func normalize(_ content: String, useZashboard: Bool) throws -> String
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
    
    static func cappedLevel(_ level: String?, order: [String], floor: String) -> String {
        guard let level = level?.trimmingCharacters(in: .whitespaces), !level.isEmpty else { return floor }
        guard let idx = order.firstIndex(of: level.lowercased()),
              let floorIdx = order.firstIndex(of: floor) else { return level }
        return idx < floorIdx ? floor : level
    }
}

// MARK: - JSON cores (Xray, sing-box)

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
    
    static func removeOtherTunInbounds(_ inbounds: inout [[String: Any]], keep: Int, typeKey: String) {
        for idx in inbounds.indices.reversed() where idx != keep && isTunInbound(inbounds[idx], typeKey: typeKey) {
            inbounds.remove(at: idx)
        }
    }
    
    static func isLogFilePath(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespaces).lowercased()
        return !v.isEmpty && v != "none" && v != "stdout" && v != "stderr"
    }
}
