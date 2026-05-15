//
//  AppState.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Combine
import Foundation

final class AppState: ObservableObject {
    static let shared = AppState()

    static let defaultDNSServers = ["1.1.1.1", "8.8.8.8"]

    private enum Keys {
        static let coreType = "coreType"
        static let xrayConfig = "config.xray"
        static let singboxConfig = "config.singbox"
        static let mihomoConfig = "config.mihomo"
        static let dnsServers = "dnsServers"
        static let alwaysOnEnabled = "alwaysOnEnabled"
    }

    private let store = AppGroup.defaults

    @Published var coreType: CoreType {
        didSet { store.set(coreType.rawValue, forKey: Keys.coreType) }
    }

    @Published var xrayConfig: String {
        didSet { store.set(xrayConfig, forKey: Keys.xrayConfig) }
    }

    @Published var singboxConfig: String {
        didSet { store.set(singboxConfig, forKey: Keys.singboxConfig) }
    }

    @Published var mihomoConfig: String {
        didSet { store.set(mihomoConfig, forKey: Keys.mihomoConfig) }
    }

    @Published var alwaysOnEnabled: Bool {
        didSet { store.set(alwaysOnEnabled, forKey: Keys.alwaysOnEnabled) }
    }

    @Published var dnsServers: [String] {
        didSet { store.set(dnsServers, forKey: Keys.dnsServers) }
    }

    private init() {
        let rawCoreType = AppGroup.defaults.string(forKey: Keys.coreType) ?? CoreType.xray.rawValue
        self.coreType = CoreType(rawValue: rawCoreType) ?? .xray
        
        self.xrayConfig = AppGroup.defaults.string(forKey: Keys.xrayConfig) ?? ExampleConfigs.xray
        self.singboxConfig = AppGroup.defaults.string(forKey: Keys.singboxConfig) ?? ExampleConfigs.singbox
        self.mihomoConfig = AppGroup.defaults.string(forKey: Keys.mihomoConfig) ?? ExampleConfigs.mihomo
        
        self.alwaysOnEnabled = AppGroup.defaults.bool(forKey: Keys.alwaysOnEnabled)
        
        let storedDNS = AppGroup.defaults.stringArray(forKey: Keys.dnsServers)
        self.dnsServers = (storedDNS?.isEmpty == false ? storedDNS! : Self.defaultDNSServers)
    }

    func currentConfig(for core: CoreType) -> String {
        switch core {
        case .xray: return xrayConfig
        case .singbox: return singboxConfig
        case .mihomo: return mihomoConfig
        }
    }

    func setCurrentConfig(_ value: String, for core: CoreType) {
        switch core {
        case .xray: xrayConfig = value
        case .singbox: singboxConfig = value
        case .mihomo: mihomoConfig = value
        }
    }
}
