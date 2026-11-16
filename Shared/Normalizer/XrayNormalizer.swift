//
//  XrayNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

enum XrayNormalizer: JSONCoreNormalizer {
    private static let logFloor = "warning"
    private static let logOrder = ["debug", "info", "warning", "error", "none"]
    
    static func normalize(_ content: String, tunnel: TunnelNetworkSettings, dashboard: DashboardAccess?) throws -> String {
        var root = try parseJSONObject(content)
        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []
        if let first = inbounds.firstIndex(where: { isTunInbound($0, typeKey: "protocol") }) {
            var patched = inbounds[first]
            patched["protocol"] = "tun"
            patched["tag"] = everywhereTag
            var settings = (patched["settings"] as? [String: Any]) ?? [:]
            settings["name"] = "utun"
            settings["MTU"] = tunnel.mtu
            patched["settings"] = settings
            inbounds[first] = patched
            removeOtherTunInbounds(&inbounds, keep: first, typeKey: "protocol")
        } else {
            inbounds.append([
                "tag": everywhereTag,
                "protocol": "tun",
                "settings": [
                    "name": "utun",
                    "MTU": tunnel.mtu,
                ],
            ])
        }
        root["inbounds"] = inbounds
        root["log"] = cappedLog(root["log"] as? [String: Any])
        if dashboard != nil { enableOutboundStats(&root) }
        return try serializeJSON(root)
    }

    private static func enableOutboundStats(_ root: inout [String: Any]) {
        if !(root["stats"] is [String: Any]) { root["stats"] = [String: Any]() }
        var policy = (root["policy"] as? [String: Any]) ?? [:]
        var system = (policy["system"] as? [String: Any]) ?? [:]
        system["statsOutboundUplink"] = true
        system["statsOutboundDownlink"] = true
        policy["system"] = system
        root["policy"] = policy
    }
    
    private static func cappedLog(_ existing: [String: Any]?) -> [String: Any] {
        var log = existing ?? [:]
        log["loglevel"] = cappedLevel(log["loglevel"] as? String, order: logOrder, floor: logFloor)
        if let access = log["access"] as? String, isLogFilePath(access) { log["access"] = "" }
        if let error = log["error"] as? String, isLogFilePath(error) { log["error"] = "" }
        return log
    }
}
