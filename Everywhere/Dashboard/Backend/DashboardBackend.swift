//
//  DashboardBackend.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Foundation

nonisolated enum DashboardError: LocalizedError {
    case unsupported(DashboardFeature, CoreType)
    case http(status: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unsupported(_, let core):
            return core.unavailableLabel
        case .http(let status, let message):
            return message.isEmpty ? "HTTP \(status)" : message
        case .invalidResponse:
            return String(localized: "The core returned an unexpected response.")
        }
    }
}

nonisolated struct DelayTestOptions: Sendable {
    static let defaultURL = "https://www.gstatic.com/generate_204"
    static let defaultTimeout = 5000

    var url: String = DelayTestOptions.defaultURL
    var timeout: Int = DelayTestOptions.defaultTimeout
}

nonisolated protocol DashboardBackend: AnyObject, Sendable {
    var core: CoreType { get }

    func version() async throws -> String

    func proxies() async throws -> ProxyTopology
    func select(_ member: String, in group: String) async throws
    func unpin(group: String) async throws
    func testDelay(of node: String, options: DelayTestOptions) async throws -> Delay
    func testDelays(inGroup group: ProxyGroup, options: DelayTestOptions) -> AsyncThrowingStream<[String: Delay], Error>
    func proxyProviders() async throws -> [ProxyProvider]
    func updateProxyProvider(_ name: String) async throws
    func healthCheckProxyProvider(_ name: String) async throws

    func traffic() -> AsyncThrowingStream<TrafficUpdate, Error>
    func connections() -> AsyncThrowingStream<ConnectionsSnapshot, Error>
    func closeConnection(_ id: String) async throws
    func closeAllConnections() async throws
    func logs(level: LogLevel) -> AsyncThrowingStream<[LogLine], Error>

    func rules() async throws -> [RoutingRule]
    func ruleProviders() async throws -> [RuleProvider]
    func updateRuleProvider(_ name: String) async throws

    func outboundMode() async throws -> (current: String, all: [String])
    func setOutboundMode(_ mode: String) async throws
    func flushFakeIP() async throws
    func flushDNSCache() async throws
    func updateGeoData() async throws
    func queryDNS(name: String, type: String) async throws -> [DNSAnswer]
}

nonisolated extension DashboardBackend {
    private func unsupported(_ feature: DashboardFeature) -> DashboardError {
        .unsupported(feature, core)
    }

    private func unsupportedStream<T>(_ feature: DashboardFeature) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { $0.finish(throwing: unsupported(feature)) }
    }

    func unpin(group: String) async throws { throw unsupported(.unpinGroup) }
    func proxyProviders() async throws -> [ProxyProvider] { throw unsupported(.proxyProviders) }
    func updateProxyProvider(_ name: String) async throws { throw unsupported(.proxyProviders) }
    func healthCheckProxyProvider(_ name: String) async throws { throw unsupported(.proxyProviders) }

    func connections() -> AsyncThrowingStream<ConnectionsSnapshot, Error> { unsupportedStream(.connections) }
    func closeConnection(_ id: String) async throws { throw unsupported(.connections) }
    func closeAllConnections() async throws { throw unsupported(.connections) }

    func ruleProviders() async throws -> [RuleProvider] { throw unsupported(.ruleProviders) }
    func updateRuleProvider(_ name: String) async throws { throw unsupported(.ruleProviders) }

    func outboundMode() async throws -> (current: String, all: [String]) { throw unsupported(.outboundMode) }
    func setOutboundMode(_ mode: String) async throws { throw unsupported(.outboundMode) }
    func flushFakeIP() async throws { throw unsupported(.flushFakeIP) }
    func flushDNSCache() async throws { throw unsupported(.flushDNSCache) }
    func updateGeoData() async throws { throw unsupported(.updateGeoData) }
    func queryDNS(name: String, type: String) async throws -> [DNSAnswer] { throw unsupported(.dnsQuery) }
}

enum DashboardBackendFactory {
    @MainActor
    static func make(for core: CoreType, configID: UUID?) -> DashboardBackend {
        switch core {
        case .mihomo, .singbox:
            return ClashBackend(core: core)
        case .xray:
            return XrayBackend(configID: configID)
        }
    }
}
