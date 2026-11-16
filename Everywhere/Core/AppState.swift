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

    @Published var tunnelNetworkSettings: TunnelNetworkSettings {
        didSet { EVCore.setTunnelNetworkSettings(tunnelNetworkSettings) }
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
    
    @Published var dashboardEnabled: Bool {
        didSet { EVCore.setDashboardEnabled(dashboardEnabled) }
    }

    @Published var dashboardHidden = false

    private init() {
        self.alwaysOnEnabled = EVCore.getAlwaysOnEnabled()
        self.tunnelNetworkSettings = EVCore.getTunnelNetworkSettings()
        self.tunnelIncludeAllNetworks = EVCore.getTunnelIncludeAllNetworks()
        self.tunnelIncludeLocalNetworks = EVCore.getTunnelIncludeLocalNetworks()
        self.tunnelIncludeAPNs = EVCore.getTunnelIncludeAPNs()
        self.tunnelIncludeCellularServices = EVCore.getTunnelIncludeCellularServices()
        self.dashboardEnabled = EVCore.getDashboardEnabled()
    }
}
