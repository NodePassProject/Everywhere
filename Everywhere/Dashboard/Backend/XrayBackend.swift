//
//  XrayBackend.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Foundation

nonisolated final class XrayBackend: DashboardBackend, @unchecked Sendable {
    let core = CoreType.xray
    private let configID: UUID?

    private static let probeBatchSize = 8

    init(configID: UUID?) {
        self.configID = configID
    }

    private func call<T: Decodable>(
        _ type: T.Type = T.self,
        _ method: String,
        _ params: [String: Any]? = nil,
        timeout: TimeInterval = 10
    ) async throws -> T {
        let json = try params.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
        }
        let data = try await TunnelManager.shared.control(method, params: json, timeout: timeout)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw DashboardError.invalidResponse
        }
    }

    // MARK: Wire types

    private struct Empty: Decodable, Sendable {}

    private struct Info: Decodable, Sendable {
        let version: String
        let rules: [JSONValue]
    }

    private struct Proxies: Decodable, Sendable {
        let `default`: String
        let outbounds: [Outbound]
        let balancers: [Balancer]

        struct Outbound: Decodable, Sendable {
            let tag: String
            let `protocol`: String
            let delay: Int
            let testedAt: Int
        }

        struct Balancer: Decodable, Sendable {
            let tag: String
            let strategy: String
            let candidates: [String]
            let override: String
            let targets: [String]
        }
    }

    private struct DelayResult: Decodable, Sendable {
        let delay: Int
    }

    private struct Stats: Decodable, Sendable {
        let up: Int64
        let down: Int64
        let outbounds: [String: Traffic]

        struct Traffic: Decodable, Sendable {
            let up: Int64
            let down: Int64
        }
    }

    private struct LogPage: Decodable, Sendable {
        let entries: [Entry]
        let next: Int

        struct Entry: Decodable, Sendable {
            let time: Double
            let level: String
            let kind: String
            let text: String
        }
    }

    func version() async throws -> String {
        try await call(Info.self, "info").version
    }

    // MARK: Proxies

    static var outboundsGroupName: String { String(localized: "Outbounds") }

    func proxies() async throws -> ProxyTopology {
        let state = try await call(Proxies.self, "proxies")
        var topology = ProxyTopology()
        topology.groupsCanNest = false
        for outbound in state.outbounds {
            var node = ProxyNode(name: outbound.tag, type: outbound.protocol)
            if outbound.testedAt > 0 {
                node.delay = outbound.delay > 0 ? .milliseconds(outbound.delay) : .failed
            }
            topology.nodes[outbound.tag] = node
        }
        topology.groups = state.balancers.map { balancer in
            let preferred = balancer.targets.count < balancer.candidates.count ? balancer.targets.first : nil
            return ProxyGroup(
                name: balancer.tag,
                type: Self.strategyName(balancer.strategy),
                members: balancer.candidates,
                selected: balancer.override.isEmpty ? preferred : balancer.override,
                isSelectable: true,
                picksAutomatically: true,
                pinned: balancer.override.isEmpty ? nil : balancer.override
            )
        }
        topology.groups.append(ProxyGroup(
            name: Self.outboundsGroupName,
            type: "",
            members: state.outbounds.map(\.tag),
            selected: state.default.isEmpty ? nil : state.default,
            isSelectable: false,
            isSynthetic: true
        ))
        return topology
    }

    private static func strategyName(_ strategy: String) -> String {
        switch strategy {
        case "leastping": return "leastPing"
        case "leastload": return "leastLoad"
        case "roundrobin": return "roundRobin"
        default: return strategy
        }
    }

    func select(_ member: String, in group: String) async throws {
        _ = try await call(Empty.self, "select", ["balancer": group, "target": member])
        if let configID {
            EVCore.setXraySelection(configID: configID, balancer: group, target: member)
        }
    }

    func unpin(group: String) async throws {
        _ = try await call(Empty.self, "select", ["balancer": group, "target": ""])
        if let configID {
            EVCore.setXraySelection(configID: configID, balancer: group, target: nil)
        }
    }

    private func probe(_ tags: [String], options: DelayTestOptions) async throws -> [String: Delay] {
        let results = try await call(
            [String: DelayResult].self, "delay",
            ["tags": tags, "url": options.url, "timeout": options.timeout],
            timeout: TimeInterval(options.timeout) / 1000 + 10
        )
        return Dictionary(uniqueKeysWithValues: tags.map { tag in
            (tag, (results[tag]?.delay ?? 0) > 0 ? Delay.milliseconds(results[tag]!.delay) : .failed)
        })
    }

    func testDelay(of node: String, options: DelayTestOptions) async throws -> Delay {
        try await probe([node], options: options)[node] ?? .failed
    }

    func testDelays(inGroup group: ProxyGroup, options: DelayTestOptions) -> AsyncThrowingStream<[String: Delay], Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var seen: Set<String> = []
                    let tags = group.members.filter { seen.insert($0).inserted }
                    for start in stride(from: 0, to: tags.count, by: Self.probeBatchSize) {
                        try Task.checkCancellation()
                        let batch = Array(tags[start..<min(start + Self.probeBatchSize, tags.count)])
                        continuation.yield(try await probe(batch, options: options))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Live data

    private func polling<T>(_ poll: @escaping @Sendable () async throws -> T?) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        if let value = try await poll() { continuation.yield(value) }
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func traffic() -> AsyncThrowingStream<TrafficUpdate, Error> {
        let previous = LockedBox<(stats: Stats, at: Date)?>(nil)
        return polling { [self] in
            let stats = try await call(Stats.self, "stats")
            let now = Date()
            let last = previous.exchange((stats, now))
            var rate = TrafficSample()
            if let last {
                let elapsed = max(now.timeIntervalSince(last.at), 0.001)
                rate.up = Double(max(stats.up - last.stats.up, 0)) / elapsed
                rate.down = Double(max(stats.down - last.stats.down, 0)) / elapsed
            }
            return TrafficUpdate(
                rate: rate,
                totals: TrafficTotals(up: stats.up, down: stats.down),
                outbounds: stats.outbounds.mapValues { TrafficTotals(up: $0.up, down: $0.down) }
            )
        }
    }

    func logs(level: LogLevel) -> AsyncThrowingStream<[LogLine], Error> {
        let cursor = LockedBox<Int>(0)
        return polling { [self] in
            let page = try await call(
                LogPage.self, "logs",
                ["after": cursor.value, "limit": 200, "level": level.rawValue]
            )
            cursor.exchange(page.next)
            let lines = page.entries
                .map { entry in
                    LogLine(
                        time: Date(timeIntervalSince1970: entry.time / 1000),
                        level: LogLevel(wire: entry.level),
                        text: entry.kind == "general" ? entry.text : "[\(entry.kind)] \(entry.text)"
                    )
                }
                .filter { $0.level >= level }
            return lines.isEmpty ? nil : lines
        }
    }

    // MARK: Rules

    func rules() async throws -> [RoutingRule] {
        try await call(Info.self, "info").rules.enumerated().map { index, rule in
            Self.rule(from: rule, index: index)
        }
    }

    private static let nonMatcherKeys: Set<String> = ["type", "outboundTag", "balancerTag", "ruleTag", "webhook"]

    private static func rule(from value: JSONValue, index: Int) -> RoutingRule {
        guard case .object(let fields) = value else {
            return RoutingRule(id: index, type: "", payload: value.summary, target: "")
        }
        let matchers = fields.keys.filter { !nonMatcherKeys.contains($0) }.sorted()
        let payload = matchers
            .map { key in matchers.count > 1 ? "\(key): \(fields[key]!.summary)" : fields[key]!.summary }
            .joined(separator: "\n")
        let target: String
        if case .string(let tag)? = fields["outboundTag"], !tag.isEmpty {
            target = tag
        } else if case .string(let tag)? = fields["balancerTag"], !tag.isEmpty {
            target = tag
        } else {
            target = ""
        }
        return RoutingRule(
            id: index,
            type: matchers.isEmpty ? String(localized: "All traffic") : matchers.joined(separator: " + "),
            payload: payload,
            target: target
        )
    }
}

nonisolated private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    @discardableResult
    func exchange(_ newValue: Value) -> Value {
        lock.lock(); defer { lock.unlock() }
        let old = storage
        storage = newValue
        return old
    }
}

nonisolated enum JSONValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    var summary: String {
        switch self {
        case .string(let value): return value
        case .number(let value):
            return value == value.rounded() ? String(Int64(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return ""
        case .array(let values):
            let limit = 4
            let shown = values.prefix(limit).map(\.summary).joined(separator: ", ")
            return values.count > limit ? "\(shown), +\(values.count - limit)" : shown
        case .object(let fields):
            return fields.keys.sorted().map { "\($0)=\(fields[$0]!.summary)" }.joined(separator: ", ")
        }
    }
}
