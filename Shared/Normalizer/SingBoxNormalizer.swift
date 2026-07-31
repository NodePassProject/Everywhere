//
//  SingBoxNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

enum SingBoxNormalizer: JSONCoreNormalizer {
    private static let logFloor = "warn"
    private static let logOrder = ["trace", "debug", "info", "warn", "error", "fatal", "panic"]

    static func normalize(_ content: String, useZashboard: Bool) throws -> String {
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
        
        if var route = root["route"] as? [String: Any] {
            route.removeValue(forKey: "auto_detect_interface")
            route.removeValue(forKey: "default_interface")
            root["route"] = route
        }
        
        if useZashboard {
            var experimental = (root["experimental"] as? [String: Any]) ?? [:]
            experimental["clash_api"] = ["external_controller": clashAPIAddress]
            root["experimental"] = experimental
        }

        root["log"] = cappedLog(root["log"] as? [String: Any])

        return try serializeJSON(root)
    }
    
    private static func cappedLog(_ existing: [String: Any]?) -> [String: Any] {
        var log = existing ?? [:]
        log["level"] = cappedLevel(log["level"] as? String, order: logOrder, floor: logFloor)
        if let output = log["output"] as? String, isLogFilePath(output) { log["output"] = "" }
        return log
    }
}
