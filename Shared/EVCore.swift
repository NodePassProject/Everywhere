//
//  EVCore.swift
//  Everywhere
//
//  Created by NodePassProject on 5/17/26.
//

import Foundation

final class EVCore {
    // MARK: - Identifiers

    enum Identifier {
        /// Bundle identifier prefix for the Everywhere app family.
        static let bundle = "com.argsment.Everywhere"
        /// App Group suite shared between the app and Network Extension.
        static let appGroupSuite = "group.\(bundle)"
        /// Bundle identifier of the packet tunnel Network Extension.
        static let networkExtension = "\(bundle).EverywhereNE"
        /// Description shown for the VPN profile in iOS Settings.
        static let tunnelDescription = "Everywhere"
    }

    /// Fallback DNS servers used when the user hasn't customized them.
    static let defaultDNSServers = ["1.1.1.1", "8.8.8.8"]

    /// App Group `UserDefaults` shared between the app and Network Extension.
    /// Prefer the typed `getX` / `setX` accessors below over direct access.
    ///
    /// Lazily initialized: the first access registers the values in
    /// ``registeredDefaults``. `register(defaults:)` only affects keys that
    /// have not been explicitly written, so user-set values always win.
    /// Swift's `static let` semantics make this thread-safe and run-once.
    private static let userDefaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: Identifier.appGroupSuite)!
        defaults.register(defaults: registeredDefaults)
        return defaults
    }()

    /// Defaults applied to App Group `UserDefaults` on first access.
    /// The single source of truth for any setting whose unset value isn't
    /// the type's natural zero (`false`/`""`/`nil`/empty collection). Bool
    /// settings that default to `false` are omitted because `bool(forKey:)`
    /// already returns `false` for unset keys.
    private static let registeredDefaults: [String: Any] = [
        UserDefaultsKey.selectedCore: CoreType.xray.rawValue,
        UserDefaultsKey.dnsServers: defaultDNSServers,
    ]

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKey {
        static let selectedCore = "selectedCore"
        static let activeByCoreType = "activeByCoreType"
        static let alwaysOnEnabled = "alwaysOnEnabled"
        static let tunnelIncludeAPNs = "tunnelIncludeAPNs"
        static let tunnelIncludeAllNetworks = "tunnelIncludeAllNetworks"
        static let tunnelIncludeCellularServices = "tunnelIncludeCellularServices"
        static let tunnelIncludeLocalNetworks = "tunnelIncludeLocalNetworks"
        static let dnsServers = "dnsServers"
    }

    // MARK: - App Group Container

    /// On-disk container shared between the app and Network Extension.
    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Identifier.appGroupSuite
        ) else {
            fatalError("App Group container missing for \(Identifier.appGroupSuite).")
        }
        return url
    }

    /// Per-core directory for user-injected assets (geoip/geosite,
    /// mmdb, certs, sing-box rule_set files, mihomo cache.db, …).
    /// Each core gets its own subfolder so colliding filenames like
    /// `cache.db` don't clobber each other. The Network Extension
    /// reads from the matching subfolder and points the active core
    /// at it via EvcoreSetResourcesPath.
    static func resourcesURL(for core: CoreType) -> URL {
        let url = containerURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(core.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Typed UserDefaults Accessors

    // Selection
    static func getSelectedCore() -> CoreType {
        CoreType(rawValue: userDefaults.string(forKey: UserDefaultsKey.selectedCore)!) ?? .xray
    }

    static func setSelectedCore(_ core: CoreType) {
        userDefaults.set(core.rawValue, forKey: UserDefaultsKey.selectedCore)
    }
    
    static func getActiveByCoreType() -> [String: String] {
        userDefaults.dictionary(forKey: UserDefaultsKey.activeByCoreType) as? [String: String] ?? [:]
    }

    static func setActiveByCoreType(_ map: [String: String]) {
        userDefaults.set(map, forKey: UserDefaultsKey.activeByCoreType)
    }

    // Tunnel
    static func getAlwaysOnEnabled() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.alwaysOnEnabled)
    }

    static func setAlwaysOnEnabled(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.alwaysOnEnabled)
    }

    static func getTunnelIncludeAllNetworks() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.tunnelIncludeAllNetworks)
    }

    static func setTunnelIncludeAllNetworks(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.tunnelIncludeAllNetworks)
    }

    static func getTunnelIncludeLocalNetworks() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.tunnelIncludeLocalNetworks)
    }

    static func setTunnelIncludeLocalNetworks(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.tunnelIncludeLocalNetworks)
    }

    static func getTunnelIncludeAPNs() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.tunnelIncludeAPNs)
    }

    static func setTunnelIncludeAPNs(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.tunnelIncludeAPNs)
    }

    static func getTunnelIncludeCellularServices() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.tunnelIncludeCellularServices)
    }

    static func setTunnelIncludeCellularServices(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.tunnelIncludeCellularServices)
    }
    
    static func getDNSServers() -> [String] {
        userDefaults.stringArray(forKey: UserDefaultsKey.dnsServers)!
    }

    static func setDNSServers(_ servers: [String]) {
        userDefaults.set(servers, forKey: UserDefaultsKey.dnsServers)
    }
}
