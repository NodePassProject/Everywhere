//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

enum ConfigNormalizer {
    static func normalize(_ content: String, for core: CoreType, tunnel: TunnelNetworkSettings, dashboard: DashboardAccess?) throws -> String {
        switch core {
        case .xray: return try XrayNormalizer.normalize(content, tunnel: tunnel, dashboard: dashboard)
        case .singbox: return try SingBoxNormalizer.normalize(content, tunnel: tunnel, dashboard: dashboard)
        case .mihomo: return try MihomoNormalizer.normalize(content, tunnel: tunnel, dashboard: dashboard)
        }
    }
}
