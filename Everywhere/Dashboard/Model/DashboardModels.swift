//
//  DashboardModels.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Foundation

// MARK: - Features

nonisolated enum DashboardFeature: CaseIterable {
    case selectNode
    case delayTest
    case rules
    case logs
    case unpinGroup
    case connections
    case outboundMode
    case flushFakeIP
    case proxyProviders
    case ruleProviders
    case flushDNSCache
    case updateGeoData
    case dnsQuery
    case outboundTraffic

    var cores: Set<CoreType> {
        switch self {
        case .selectNode, .delayTest, .rules, .logs:
            return [.xray, .singbox, .mihomo]
        case .unpinGroup:
            return [.xray, .mihomo]
        case .connections, .outboundMode, .flushFakeIP, .flushDNSCache, .dnsQuery:
            return [.singbox, .mihomo]
        case .proxyProviders, .ruleProviders, .updateGeoData:
            return [.mihomo]
        case .outboundTraffic:
            return [.xray]
        }
    }

    func isAvailable(on core: CoreType) -> Bool { cores.contains(core) }
}

nonisolated extension CoreType {
    var unavailableLabel: String {
        String(localized: "Unavailable on \(displayName)")
    }
}

// MARK: - Proxies

nonisolated enum Delay: Equatable {
    case untested
    case failed
    case milliseconds(Int)

    var sortKey: Int {
        switch self {
        case .milliseconds(let ms): return ms
        case .failed: return .max - 1
        case .untested: return .max
        }
    }
}

nonisolated struct ProxyNode: Identifiable, Equatable {
    let name: String
    var type: String
    var delay: Delay = .untested
    var supportsUDP: Bool?

    var id: String { name }
}

nonisolated struct ProxyGroup: Identifiable, Equatable {
    let name: String
    var type: String
    var members: [String]
    var selected: String?
    var isSelectable: Bool
    var picksAutomatically = false
    var pinned: String?
    var isHidden = false
    var testURL: String?
    var isSynthetic = false

    var id: String { name }
}

nonisolated struct ProxyTopology: Equatable {
    var groups: [ProxyGroup] = []
    var nodes: [String: ProxyNode] = [:]
    var groupsCanNest = true

    func group(named name: String) -> ProxyGroup? {
        groups.first { $0.name == name }
    }

    func leaf(of name: String) -> String {
        guard groupsCanNest else { return name }
        var current = name
        var visited: Set<String> = []
        while visited.insert(current).inserted,
              let next = group(named: current)?.selected, !next.isEmpty {
            current = next
        }
        return current
    }

    func delay(of name: String) -> Delay {
        nodes[leaf(of: name)]?.delay ?? .untested
    }
}

nonisolated struct ProxyProvider: Identifiable, Equatable {
    let name: String
    var vehicleType: String
    var nodeCount: Int
    var updatedAt: Date?
    var subscription: Subscription?

    var id: String { name }

    struct Subscription: Equatable {
        var upload: Int64
        var download: Int64
        var total: Int64
        var expire: Date?

        var used: Int64 { upload + download }
        var fraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }
    }
}

// MARK: - Traffic

nonisolated struct TrafficSample: Equatable {
    var up: Double = 0
    var down: Double = 0
}

nonisolated struct TrafficTotals: Equatable {
    var up: Int64 = 0
    var down: Int64 = 0
}

nonisolated struct TrafficUpdate {
    var rate: TrafficSample
    var totals: TrafficTotals?
    var outbounds: [String: TrafficTotals]?
}

nonisolated struct ExtensionRuntime: Equatable {
    var footprint: Int64
    var available: Int64
}

// MARK: - Connections

nonisolated struct ConnectionInfo: Identifiable, Equatable {
    let id: String
    var network: String
    var inbound: String
    var host: String
    var destinationIP: String
    var destinationPort: String
    var sourceIP: String
    var sourcePort: String
    var sniffHost: String
    var remoteDestination: String
    var process: String
    var dnsMode: String
    var chain: [String]
    var rule: String
    var rulePayload: String
    var upload: Int64
    var download: Int64
    var start: Date
    var uploadSpeed: Int64 = 0
    var downloadSpeed: Int64 = 0

    var destination: String {
        let name = !host.isEmpty ? host : (!sniffHost.isEmpty ? sniffHost : destinationIP)
        let display = name.contains(":") && host.isEmpty ? "[\(name)]" : name
        return destinationPort.isEmpty ? display : "\(display):\(destinationPort)"
    }

    var ruleDescription: String {
        rulePayload.isEmpty ? rule : "\(rule) (\(rulePayload))"
    }
}

nonisolated struct ConnectionsSnapshot {
    var connections: [ConnectionInfo]
    var totals: TrafficTotals
}

// MARK: - Rules

nonisolated struct RoutingRule: Identifiable, Equatable {
    let id: Int
    var type: String
    var payload: String
    var target: String
}

nonisolated struct RuleProvider: Identifiable, Equatable {
    let name: String
    var behavior: String
    var format: String
    var vehicleType: String
    var ruleCount: Int
    var updatedAt: Date?

    var id: String { name }
}

// MARK: - Logs

nonisolated enum LogLevel: String, CaseIterable, Identifiable, Comparable {
    case debug, info, warning, error

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }

    init(wire: String) {
        switch wire.lowercased() {
        case "trace", "debug": self = .debug
        case "warn", "warning": self = .warning
        case "error", "fatal", "panic": self = .error
        default: self = .info
        }
    }

    var title: String {
        switch self {
        case .debug: return String(localized: "Debug")
        case .info: return String(localized: "Info")
        case .warning: return String(localized: "Warning")
        case .error: return String(localized: "Error")
        }
    }
}

nonisolated struct LogLine {
    var time: Date
    var level: LogLevel
    var text: String
}

nonisolated struct LogEntry: Identifiable, Equatable {
    let id: Int
    var time: Date
    var level: LogLevel
    var text: String
}

// MARK: - DNS

nonisolated struct DNSAnswer: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var type: String
    var ttl: Int
    var data: String
}
