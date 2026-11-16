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

    private static let strippedClashAPIKeys = [
        "external_ui",
        "external_ui_download_url",
        "external_ui_download_detour",
        "access_control_allow_origin",
        "access_control_allow_private_network",
    ]

    static func normalize(_ content: String, tunnel: TunnelNetworkSettings, dashboard: DashboardAccess?) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        if let first = inbounds.firstIndex(where: { isTunInbound($0, typeKey: "type") }) {
            var patched = inbounds[first]
            patched["type"] = "tun"
            patched["tag"] = everywhereTag
            patched["address"] = tunnel.coreAddresses
            patched["mtu"] = tunnel.mtu
            patched["stack"] = tunStack
            patched.removeValue(forKey: "interface_name")
            patched.removeValue(forKey: "platform")
            inbounds[first] = patched
            removeOtherTunInbounds(&inbounds, keep: first, typeKey: "type")
        } else {
            inbounds.append([
                "type": "tun",
                "tag": everywhereTag,
                "address": tunnel.coreAddresses,
                "mtu": tunnel.mtu,
                "stack": tunStack,
            ])
        }
        root["inbounds"] = inbounds
        
        if var route = root["route"] as? [String: Any] {
            route.removeValue(forKey: "auto_detect_interface")
            route.removeValue(forKey: "default_interface")
            root["route"] = route
        }
        
        if let dashboard {
            var experimental = (root["experimental"] as? [String: Any]) ?? [:]
            var clashAPI = (experimental["clash_api"] as? [String: Any]) ?? [:]
            for key in strippedClashAPIKeys { clashAPI.removeValue(forKey: key) }
            clashAPI["external_controller"] = clashAPIAddress
            clashAPI["secret"] = dashboard.secret
            experimental["clash_api"] = clashAPI
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
