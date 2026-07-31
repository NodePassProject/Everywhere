//
//  ConfigNormalizer.swift
//  Everywhere
//
//  Created by NodePassProject on 5/24/26.
//

import Foundation

enum ConfigNormalizer {
    static func normalize(_ content: String, for core: CoreType, useZashboard: Bool) throws -> String {
        switch core {
        case .xray: return try XrayNormalizer.normalize(content, useZashboard: useZashboard)
        case .singbox: return try SingBoxNormalizer.normalize(content, useZashboard: useZashboard)
        case .mihomo: return try MihomoNormalizer.normalize(content, useZashboard: useZashboard)
        }
    }
}
