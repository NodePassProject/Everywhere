//
//  AppGroup.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.argsment.Everywhere"
    static let extensionBundleID = "com.argsment.Everywhere.EverywhereNE"
    static let tunnelDescription = "Everywhere"

    static var defaults: UserDefaults {
        guard let d = UserDefaults(suiteName: identifier) else {
            fatalError("App Group \(identifier) is not configured. Check entitlements.")
        }
        return d
    }

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            fatalError("App Group container missing for \(identifier).")
        }
        return url
    }

    // Per-core directory for user-injected assets (geoip/geosite,
    // mmdb, certs, sing-box rule_set files, mihomo cache.db, …).
    // Each core gets its own subfolder so colliding filenames like
    // `cache.db` don't clobber each other. The Network Extension
    // reads from the matching subfolder and points the active core
    // at it via EvcoreSetResourcesPath.
    static func resourcesURL(for core: CoreType) -> URL {
        let url = containerURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(core.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
