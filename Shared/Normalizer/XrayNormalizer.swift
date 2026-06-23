//
//  XrayNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

// Xray (JSON).
//
// Xray's TUN inbound docs say port/listen are ignored for protocol
// "tun". `name` is required by the schema and used on macOS to pick
// a utunN device — on iOS it's overridden by the FD coming through
// the `xray.tun.fd` env var, but the schema still wants a value.
// We patch the first existing TUN inbound to force protocol/tag and
// settings.name/MTU; other top-level inbound fields (sniffing,
// streamSettings, …) and other `settings.*` keys are preserved. If
// none exists we append a minimal one.
enum XrayNormalizer: JSONCoreNormalizer {
    private static let logFloor = "warning"
    private static let logOrder = ["debug", "info", "warning", "error", "none"]

    // `useZashboard` is accepted for protocol conformance but unused —
    // Xray exposes no Clash API, so there is no UI surface to gate.
    static func normalize(_ content: String, useZashboard _: Bool) throws -> String {
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
        root["log"] = cappedLog(root["log"] as? [String: Any])
        return try serializeJSON(root)
    }

    // Cap `loglevel` down to `logFloor` and redirect any file-based
    // `access`/`error` paths to stderr (empty string) so the core stops
    // writing a line to disk on every connection / DNS query. Xray has no
    // clash-API log consumer on iOS, so nothing in the app depends on the
    // verbosity here.
    private static func cappedLog(_ existing: [String: Any]?) -> [String: Any] {
        var log = existing ?? [:]
        log["loglevel"] = cappedLevel(log["loglevel"] as? String, order: logOrder, floor: logFloor)
        if let access = log["access"] as? String, isLogFilePath(access) { log["access"] = "" }
        if let error = log["error"] as? String, isLogFilePath(error) { log["error"] = "" }
        return log
    }
}
