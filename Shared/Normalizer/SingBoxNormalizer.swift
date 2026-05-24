//
//  SingBoxNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

// sing-box (JSON).
//
// The TUN fd is injected via adapter.PlatformInterface in Go, which
// means the JSON only has to declare an inbound the NE can recognize.
// `address` mirrors what NEPacketTunnelNetworkSettings advertises so
// the gvisor stack can compute matching gateway addresses; `stack`
// is forced to gvisor because the system stack needs syscalls the
// NE doesn't expose. `interface_name` and `platform` are stripped —
// the NE owns the utun. Everything else stays.
enum SingBoxNormalizer: JSONCoreNormalizer {
    private static let logFloor = "warn"
    private static let logOrder = ["trace", "debug", "info", "warn", "error", "fatal", "panic"]

    static func normalize(_ content: String) throws -> String {
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

        root["log"] = cappedLog(root["log"] as? [String: Any])

        return try serializeJSON(root)
    }

    // Cap `level` down to `logFloor` and redirect a file `output` to
    // stderr. The clash-API `/logs` socket streams at this level, so a
    // verbose config also means a busier socket — the cap quiets both. A
    // user-set `disabled: true` is left untouched.
    private static func cappedLog(_ existing: [String: Any]?) -> [String: Any] {
        var log = existing ?? [:]
        log["level"] = cappedLevel(log["level"] as? String, order: logOrder, floor: logFloor)
        if let output = log["output"] as? String, isLogFilePath(output) { log["output"] = "" }
        return log
    }
}
