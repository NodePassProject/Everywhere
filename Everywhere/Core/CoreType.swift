//
//  CoreType.swift
//  Everywhere
//
//  Created by Argsment Limited on 5/2/26.
//

import Foundation

enum CoreType: String, CaseIterable, Identifiable {
    case xray
    case singbox
    case mihomo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xray: return "Xray"
        case .singbox: return "sing-box"
        case .mihomo: return "mihomo"
        }
    }

    var configLanguage: String {
        switch self {
        case .xray, .singbox: return "json"
        case .mihomo: return "yaml"
        }
    }

    var defaultConfig: String {
        switch self {
        case .xray: return ExampleConfigs.xray
        case .singbox: return ExampleConfigs.singbox
        case .mihomo: return ExampleConfigs.mihomo
        }
    }
}
