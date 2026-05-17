//
//  AppState.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Combine
import Foundation

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var alwaysOnEnabled: Bool {
        didSet { EVCore.setAlwaysOnEnabled(alwaysOnEnabled) }
    }

    @Published var dnsServers: [String] {
        didSet { EVCore.setDNSServers(dnsServers) }
    }

    @Published var tunnelIncludeAllNetworks: Bool {
        didSet { EVCore.setTunnelIncludeAllNetworks(tunnelIncludeAllNetworks) }
    }

    @Published var tunnelIncludeLocalNetworks: Bool {
        didSet { EVCore.setTunnelIncludeLocalNetworks(tunnelIncludeLocalNetworks) }
    }

    @Published var tunnelIncludeAPNs: Bool {
        didSet { EVCore.setTunnelIncludeAPNs(tunnelIncludeAPNs) }
    }

    @Published var tunnelIncludeCellularServices: Bool {
        didSet { EVCore.setTunnelIncludeCellularServices(tunnelIncludeCellularServices) }
    }

    private init() {
        self.alwaysOnEnabled = EVCore.getAlwaysOnEnabled()
        self.tunnelIncludeAllNetworks = EVCore.getTunnelIncludeAllNetworks()
        self.tunnelIncludeLocalNetworks = EVCore.getTunnelIncludeLocalNetworks()
        self.tunnelIncludeAPNs = EVCore.getTunnelIncludeAPNs()
        self.tunnelIncludeCellularServices = EVCore.getTunnelIncludeCellularServices()

        let stored = EVCore.getDNSServers()
        self.dnsServers = stored.isEmpty ? EVCore.defaultDNSServers : stored
    }
}
