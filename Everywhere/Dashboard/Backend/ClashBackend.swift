//
//  ClashBackend.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Foundation

nonisolated final class ClashBackend: DashboardBackend, @unchecked Sendable {
    let core: CoreType
    private let api = ClashAPI()

    private let lock = NSLock()
    private var providerOfNode: [String: String] = [:]

    init(core: CoreType) {
        self.core = core
    }

    private var isMihomo: Bool { core == .mihomo }

    func version() async throws -> String {
        let version = try await api.get(ClashVersion.self, "/version").version
        let prefix = "sing-box "
        return version.hasPrefix(prefix) ? String(version.dropFirst(prefix.count)) : version
    }

    // MARK: Proxies

    func proxies() async throws -> ProxyTopology {
        async let proxiesRequest = api.get(ClashProxies.self, "/proxies")
        async let providersRequest = providerEntries()
        let entries = try await proxiesRequest.proxies
        let providers = await providersRequest

        var topology = ProxyTopology()
        for entry in entries.values {
            topology.nodes[entry.name] = Self.node(from: entry)
        }
        var providerOfNode: [String: String] = [:]
        for provider in providers.values where provider.vehicleType != "Compatible" {
            for entry in provider.proxies ?? [] where topology.nodes[entry.name] == nil {
                topology.nodes[entry.name] = Self.node(from: entry)
                providerOfNode[entry.name] = provider.name
            }
        }
        lock.withLock { self.providerOfNode = providerOfNode }

        let order = entries["GLOBAL"]?.all ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let groups = entries.values
            .filter { $0.all != nil && $0.hidden != true }
            .filter { isMihomo || $0.name != "GLOBAL" }
            .sorted { lhs, rhs in
                if (lhs.name == "GLOBAL") != (rhs.name == "GLOBAL") { return rhs.name == "GLOBAL" }
                switch (rank[lhs.name], rank[rhs.name]) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
        topology.groups = groups.map(group(from:))
        return topology
    }

    private func providerEntries() async -> [String: ClashProxyProvider] {
        guard isMihomo else { return [:] }
        return (try? await api.get(ClashProxyProviders.self, "/providers/proxies"))?.providers ?? [:]
    }

    private static func node(from entry: ClashProxy) -> ProxyNode {
        var node = ProxyNode(name: entry.name, type: entry.type, supportsUDP: entry.udp)
        if let last = entry.history?.last {
            node.delay = last.delay > 0 ? .milliseconds(last.delay) : .failed
        }
        return node
    }

    private func group(from entry: ClashProxy) -> ProxyGroup {
        let selectable: Bool
        switch entry.type {
        case "Selector": selectable = true
        case "URLTest", "Fallback": selectable = isMihomo
        default: selectable = false
        }
        return ProxyGroup(
            name: entry.name,
            type: entry.type,
            members: entry.all ?? [],
            selected: entry.now?.isEmpty == false ? entry.now : nil,
            isSelectable: selectable,
            picksAutomatically: entry.type != "Selector",
            pinned: entry.type != "Selector" && entry.fixed?.isEmpty == false ? entry.fixed : nil,
            isHidden: entry.hidden ?? false,
            testURL: entry.testUrl?.isEmpty == false ? entry.testUrl : nil
        )
    }

    func select(_ member: String, in group: String) async throws {
        try await api.send("PUT", "/proxies/\(ClashAPI.segment(group))", body: ["name": member])
    }

    func unpin(group: String) async throws {
        guard isMihomo else { throw DashboardError.unsupported(.unpinGroup, core) }
        try await api.send("DELETE", "/proxies/\(ClashAPI.segment(group))")
    }

    private func delayQuery(_ options: DelayTestOptions) -> [URLQueryItem] {
        [
            URLQueryItem(name: "url", value: options.url),
            URLQueryItem(name: "timeout", value: String(min(max(options.timeout, 1), 32767))),
        ]
    }

    func testDelay(of node: String, options: DelayTestOptions) async throws -> Delay {
        let provider = lock.withLock { providerOfNode[node] }
        let path = provider.map {
            "/providers/proxies/\(ClashAPI.segment($0))/\(ClashAPI.segment(node))/healthcheck"
        } ?? "/proxies/\(ClashAPI.segment(node))/delay"
        do {
            let result = try await api.get(
                ClashDelay.self, path,
                query: delayQuery(options),
                timeout: TimeInterval(options.timeout) / 1000 + 5
            )
            return result.delay > 0 ? .milliseconds(result.delay) : .failed
        } catch DashboardError.http(let status, _) where status == 503 || status == 504 {
            return .failed
        }
    }

    func testDelays(inGroup group: ProxyGroup, options: DelayTestOptions) -> AsyncThrowingStream<[String: Delay], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var measured: [String: Int] = [:]
                    do {
                        measured = try await api.get(
                            [String: Int].self,
                            "/group/\(ClashAPI.segment(group.name))/delay",
                            query: delayQuery(options),
                            timeout: TimeInterval(options.timeout) / 1000 + 10
                        )
                    } catch DashboardError.http(let status, _) where status == 504 {
                    }
                    var results: [String: Delay] = [:]
                    for member in group.members {
                        results[member] = measured[member].map { $0 > 0 ? .milliseconds($0) : .failed } ?? .failed
                    }
                    continuation.yield(results)

                    if isMihomo, let pinned = group.pinned {
                        try? await select(pinned, in: group.name)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func proxyProviders() async throws -> [ProxyProvider] {
        guard isMihomo else { throw DashboardError.unsupported(.proxyProviders, core) }
        let providers = try await api.get(ClashProxyProviders.self, "/providers/proxies").providers
        return providers.values
            .filter { $0.name != "default" && $0.vehicleType != "Compatible" }
            .map { provider in
                ProxyProvider(
                    name: provider.name,
                    vehicleType: provider.vehicleType,
                    nodeCount: provider.proxies?.count ?? 0,
                    updatedAt: ClashDate.parse(provider.updatedAt),
                    subscription: provider.subscriptionInfo.flatMap { info in
                        guard let total = info.Total, total > 0 else { return nil }
                        return ProxyProvider.Subscription(
                            upload: info.Upload ?? 0,
                            download: info.Download ?? 0,
                            total: total,
                            expire: (info.Expire ?? 0) > 0 ? Date(timeIntervalSince1970: TimeInterval(info.Expire!)) : nil
                        )
                    }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func updateProxyProvider(_ name: String) async throws {
        guard isMihomo else { throw DashboardError.unsupported(.proxyProviders, core) }
        try await api.send("PUT", "/providers/proxies/\(ClashAPI.segment(name))", timeout: 60)
    }

    func healthCheckProxyProvider(_ name: String) async throws {
        guard isMihomo else { throw DashboardError.unsupported(.proxyProviders, core) }
        try await api.send("GET", "/providers/proxies/\(ClashAPI.segment(name))/healthcheck", timeout: 60)
    }

    // MARK: Live data

    func traffic() -> AsyncThrowingStream<TrafficUpdate, Error> {
        mapStream(api.stream(ClashTraffic.self, "/traffic")) { sample in
            TrafficUpdate(
                rate: TrafficSample(up: Double(sample.up), down: Double(sample.down)),
                totals: sample.upTotal.flatMap { up in
                    sample.downTotal.map { TrafficTotals(up: up, down: $0) }
                }
            )
        }
    }

    func connections() -> AsyncThrowingStream<ConnectionsSnapshot, Error> {
        let stream = api.stream(
            ClashConnections.self, "/connections",
            query: [URLQueryItem(name: "interval", value: "1000")]
        )
        return mapStream(stream) { snapshot in
            ConnectionsSnapshot(
                connections: (snapshot.connections ?? []).map(Self.connection(from:)),
                totals: TrafficTotals(up: snapshot.uploadTotal, down: snapshot.downloadTotal)
            )
        }
    }

    private static func connection(from wire: ClashConnections.Connection) -> ConnectionInfo {
        let metadata = wire.metadata
        return ConnectionInfo(
            id: wire.id,
            network: metadata.network ?? "",
            inbound: metadata.type ?? "",
            host: metadata.host ?? "",
            destinationIP: metadata.destinationIP ?? "",
            destinationPort: metadata.destinationPort ?? "",
            sourceIP: metadata.sourceIP ?? "",
            sourcePort: metadata.sourcePort ?? "",
            sniffHost: metadata.sniffHost ?? "",
            remoteDestination: metadata.remoteDestination ?? "",
            process: metadata.process?.isEmpty == false ? metadata.process! : (metadata.processPath ?? ""),
            dnsMode: metadata.dnsMode ?? "",
            chain: (wire.chains ?? []).reversed(),
            rule: wire.rule ?? "",
            rulePayload: wire.rulePayload ?? "",
            upload: wire.upload,
            download: wire.download,
            start: ClashDate.parse(wire.start) ?? Date()
        )
    }

    func closeConnection(_ id: String) async throws {
        try await api.send("DELETE", "/connections/\(ClashAPI.segment(id))")
    }

    func closeAllConnections() async throws {
        try await api.send("DELETE", "/connections")
    }

    func logs(level: LogLevel) -> AsyncThrowingStream<[LogLine], Error> {
        let wireLevel = level == .warning && !isMihomo ? "warn" : level.rawValue
        let stream = api.stream(ClashLog.self, "/logs", query: [URLQueryItem(name: "level", value: wireLevel)])
        return mapStream(stream) { log in
            [LogLine(time: Date(), level: LogLevel(wire: log.type), text: log.payload)]
        }
    }

    // MARK: Rules

    func rules() async throws -> [RoutingRule] {
        let rules = try await api.get(ClashRules.self, "/rules").rules ?? []
        return rules.enumerated().map { index, rule in
            RoutingRule(
                id: index,
                type: rule.type == "default" ? "" : rule.type,
                payload: rule.payload,
                target: Self.ruleTarget(rule.proxy)
            )
        }
    }

    private static func ruleTarget(_ action: String) -> String {
        let prefix = "route("
        guard action.hasPrefix(prefix), action.hasSuffix(")") else { return action }
        return String(action.dropFirst(prefix.count).dropLast())
    }

    func ruleProviders() async throws -> [RuleProvider] {
        guard isMihomo else { throw DashboardError.unsupported(.ruleProviders, core) }
        let providers = try await api.get(ClashRuleProviders.self, "/providers/rules").providers
        return providers.values
            .map { provider in
                RuleProvider(
                    name: provider.name,
                    behavior: provider.behavior ?? "",
                    format: provider.format ?? "",
                    vehicleType: provider.vehicleType ?? "",
                    ruleCount: provider.ruleCount ?? 0,
                    updatedAt: ClashDate.parse(provider.updatedAt)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func updateRuleProvider(_ name: String) async throws {
        guard isMihomo else { throw DashboardError.unsupported(.ruleProviders, core) }
        try await api.send("PUT", "/providers/rules/\(ClashAPI.segment(name))", timeout: 60)
    }

    // MARK: Mode & maintenance

    func outboundMode() async throws -> (current: String, all: [String]) {
        let configs = try await api.get(ClashConfigs.self, "/configs")
        let current = configs.mode ?? ""
        let all = configs.modeList ?? ["rule", "global", "direct"]
        return (current, all.contains(current) || current.isEmpty ? all : [current] + all)
    }

    func setOutboundMode(_ mode: String) async throws {
        try await api.send("PATCH", "/configs", body: ["mode": mode])
    }

    func flushFakeIP() async throws {
        try await api.send("POST", "/cache/fakeip/flush")
    }

    func flushDNSCache() async throws {
        try await api.send("POST", "/cache/dns/flush")
    }

    func updateGeoData() async throws {
        guard isMihomo else { throw DashboardError.unsupported(.updateGeoData, core) }
        try await api.send("POST", "/configs/geo", timeout: 180)
    }

    func queryDNS(name: String, type: String) async throws -> [DNSAnswer] {
        let response = try await api.get(
            ClashDNSResponse.self, "/dns/query",
            query: [URLQueryItem(name: "name", value: name), URLQueryItem(name: "type", value: type)]
        )
        return (response.Answer ?? []).map {
            DNSAnswer(name: $0.name, type: Self.recordType($0.type), ttl: $0.TTL, data: $0.data)
        }
    }

    private static func recordType(_ value: Int) -> String {
        switch value {
        case 1: return "A"
        case 2: return "NS"
        case 5: return "CNAME"
        case 6: return "SOA"
        case 12: return "PTR"
        case 15: return "MX"
        case 16: return "TXT"
        case 28: return "AAAA"
        case 33: return "SRV"
        case 64: return "SVCB"
        case 65: return "HTTPS"
        default: return "TYPE\(value)"
        }
    }
}

nonisolated private func mapStream<Input: Sendable, Output: Sendable>(
    _ source: AsyncThrowingStream<Input, Error>,
    _ transform: @escaping @Sendable (Input) -> Output
) -> AsyncThrowingStream<Output, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await element in source {
                    continuation.yield(transform(element))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

nonisolated enum ClashDate {
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String?) -> Date? {
        guard var string, !string.isEmpty, !string.hasPrefix("0001-") else { return nil }
        var fraction = 0.0
        if let dot = string.firstIndex(of: ".") {
            let digitsEnd = string[string.index(after: dot)...].firstIndex { !$0.isNumber } ?? string.endIndex
            fraction = Double("0" + string[dot..<digitsEnd]) ?? 0
            string.removeSubrange(dot..<digitsEnd)
        }
        return plain.date(from: string)?.addingTimeInterval(fraction)
    }
}
