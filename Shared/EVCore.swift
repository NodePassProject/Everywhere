//
//  EVCore.swift
//  Everywhere
//
//  Created by NodePassProject on 5/17/26.
//

import Foundation
import Security

nonisolated final class EVCore {
    // MARK: - Identifiers

    enum Identifier {
        static let bundle = "com.argsment.Everywhere"
        static let appGroupSuite = "group.\(bundle)"
        static let networkExtension = "\(bundle).EverywhereNE"
        static let tunnelDescription = "Everywhere"
    }

    private static let userDefaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: Identifier.appGroupSuite)!
        defaults.register(defaults: registeredDefaults)
        return defaults
    }()

    private static let registeredDefaults: [String: Any] = [
        UserDefaultsKey.selectedCore: CoreType.xray.rawValue,
        UserDefaultsKey.dashboardEnabled: true,
    ]

    // MARK: - UserDefaults Keys

    private enum UserDefaultsKey {
        static let activeByCoreType = "activeByCoreType"
        static let alwaysOnEnabled = "alwaysOnEnabled"
        static let controllerSecret = "controllerSecret"
        static let dashboardEnabled = "useZashboard"
        static let dnsServers = "dnsServers"
        static let selectedCore = "selectedCore"
        static let tunnelIncludeAPNs = "tunnelIncludeAPNs"
        static let tunnelIncludeAllNetworks = "tunnelIncludeAllNetworks"
        static let tunnelIncludeCellularServices = "tunnelIncludeCellularServices"
        static let tunnelIncludeLocalNetworks = "tunnelIncludeLocalNetworks"
        static let tunnelNetworkSettings = "tunnelNetworkSettings"
        static let xraySelections = "xraySelections"
    }

    // MARK: - App Group Container

    static var containerURL: URL {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Identifier.appGroupSuite
        ) else {
            fatalError("App Group container missing for \(Identifier.appGroupSuite).")
        }
        return url
    }

    static func resourcesURL(for core: CoreType) -> URL {
        let url = containerURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent(core.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Typed UserDefaults Accessors
    
    static func getActiveByCoreType() -> [String: String] {
        userDefaults.dictionary(forKey: UserDefaultsKey.activeByCoreType) as? [String: String] ?? [:]
    }

    static func setActiveByCoreType(_ map: [String: String]) {
        userDefaults.set(map, forKey: UserDefaultsKey.activeByCoreType)
    }
    
    static func getAlwaysOnEnabled() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.alwaysOnEnabled)
    }

    static func setAlwaysOnEnabled(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.alwaysOnEnabled)
    }
    
    static func getSelectedCore() -> CoreType {
        CoreType(rawValue: userDefaults.string(forKey: UserDefaultsKey.selectedCore)!) ?? .xray
    }

    static func setSelectedCore(_ core: CoreType) {
        userDefaults.set(core.rawValue, forKey: UserDefaultsKey.selectedCore)
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
    
    static func getDashboardEnabled() -> Bool {
        userDefaults.bool(forKey: UserDefaultsKey.dashboardEnabled)
    }

    static func setDashboardEnabled(_ value: Bool) {
        userDefaults.set(value, forKey: UserDefaultsKey.dashboardEnabled)
    }

    // MARK: - Tunnel Network Settings

    static func getTunnelNetworkSettings() -> TunnelNetworkSettings {
        if let data = userDefaults.data(forKey: UserDefaultsKey.tunnelNetworkSettings),
           let settings = try? JSONDecoder().decode(TunnelNetworkSettings.self, from: data) {
            return settings
        }
        var settings = TunnelNetworkSettings()
        let legacyServers = (userDefaults.stringArray(forKey: UserDefaultsKey.dnsServers) ?? [])
            .filter { IPNetwork.isAddress($0) }
        if !legacyServers.isEmpty { settings.dns.servers = legacyServers }
        return settings
    }

    static func setTunnelNetworkSettings(_ settings: TunnelNetworkSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        userDefaults.set(data, forKey: UserDefaultsKey.tunnelNetworkSettings)
    }

    // MARK: - Dashboard Controller

    static let controllerAddress = "127.0.0.1:9090"

    static func getControllerSecret() -> String? {
        let secret = userDefaults.string(forKey: UserDefaultsKey.controllerSecret)
        return secret?.isEmpty == false ? secret : nil
    }

    static func makeControllerSecret() -> String {
        if let existing = getControllerSecret() { return existing }
        var bytes = [UInt8](repeating: 0, count: 24)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            bytes = (0..<bytes.count).map { _ in UInt8.random(in: .min ... .max) }
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        userDefaults.set(secret, forKey: UserDefaultsKey.controllerSecret)
        return secret
    }

    // MARK: - Xray Balancer Selections

    static func getXraySelections(configID: UUID) -> [String: String] {
        let all = userDefaults.dictionary(forKey: UserDefaultsKey.xraySelections) as? [String: [String: String]]
        return all?[configID.uuidString] ?? [:]
    }

    static func setXraySelection(configID: UUID, balancer: String, target: String?) {
        var all = userDefaults.dictionary(forKey: UserDefaultsKey.xraySelections) as? [String: [String: String]] ?? [:]
        var selections = all[configID.uuidString] ?? [:]
        selections[balancer] = target?.isEmpty == false ? target : nil
        all[configID.uuidString] = selections.isEmpty ? nil : selections
        userDefaults.set(all, forKey: UserDefaultsKey.xraySelections)
    }

    static func removeXraySelections(configID: UUID) {
        guard var all = userDefaults.dictionary(forKey: UserDefaultsKey.xraySelections) as? [String: [String: String]],
              all.removeValue(forKey: configID.uuidString) != nil else { return }
        userDefaults.set(all, forKey: UserDefaultsKey.xraySelections)
    }
}
