//
//  DashboardStore.swift
//  Everywhere
//
//  Created by NodePassProject on 11/15/26.
//

import Combine
import Foundation

enum DashboardPreferences {
    static let testURLKey = "dashboard.testURL"
    static let closeOnSwitchKey = "dashboard.closeConnectionsOnSwitch"
    static let sortKey = "dashboard.proxySort"
    static let hideUnavailableKey = "dashboard.hideUnavailableNodes"
    static let logLevelKey = "dashboard.logLevel"

    static var delayOptions: DelayTestOptions {
        var options = DelayTestOptions()
        if let url = UserDefaults.standard.string(forKey: testURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            options.url = url
        }
        return options
    }

    static var closeOnSwitch: Bool {
        UserDefaults.standard.object(forKey: closeOnSwitchKey) as? Bool ?? true
    }
}

@MainActor
final class DashboardStore: ObservableObject {
    let core: CoreType
    let backend: DashboardBackend

    let overview: OverviewModel
    let proxies: ProxiesModel
    let connections: ConnectionsModel
    let rules: RulesModel
    let logs: LogsModel

    private var isRunning = false

    init(core: CoreType, configID: UUID?) {
        let backend = DashboardBackendFactory.make(for: core, configID: configID)
        self.core = core
        self.backend = backend
        overview = OverviewModel(backend: backend)
        connections = ConnectionsModel(backend: backend)
        proxies = ProxiesModel(backend: backend)
        rules = RulesModel(backend: backend)
        logs = LogsModel(backend: backend)

        proxies.connections = connections
        connections.onSnapshot = { [weak overview] snapshot in
            overview?.connectionCount = snapshot.connections.count
            if overview?.totalsFromTrafficStream == false {
                overview?.totals = snapshot.totals
            }
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        overview.start()
        connections.start()
        logs.resumeIfWanted()
        Task { await proxies.refresh() }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        overview.stop()
        connections.stop()
        logs.suspend()
    }
}

@MainActor
private func keepConsuming<T>(
    _ make: @escaping () -> AsyncThrowingStream<T, Error>,
    onFailure: (Error) -> Void = { _ in },
    onValue: (T) -> Void
) async {
    while !Task.isCancelled {
        do {
            for try await value in make() {
                onValue(value)
            }
        } catch DashboardError.unsupported {
            return
        } catch {
            if Task.isCancelled { return }
            onFailure(error)
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
}

// MARK: - Overview

@MainActor
final class OverviewModel: ObservableObject {
    enum Link: Equatable {
        case connecting
        case connected
        case failed(String)
    }

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var isError: Bool
    }

    static let historyLength = 60

    @Published private(set) var link: Link = .connecting
    @Published private(set) var version: String?
    @Published private(set) var rate = TrafficSample()
    @Published private(set) var history = [TrafficSample](repeating: TrafficSample(), count: OverviewModel.historyLength)
    @Published fileprivate(set) var totals: TrafficTotals?
    @Published private(set) var outboundTraffic: [(tag: String, totals: TrafficTotals)] = []
    @Published private(set) var runtime: ExtensionRuntime?
    @Published fileprivate(set) var connectionCount: Int?
    @Published private(set) var mode: String?
    @Published private(set) var modes: [String] = []
    @Published private(set) var busyTools: Set<DashboardFeature> = []
    @Published var notice: Notice?

    fileprivate var totalsFromTrafficStream = false

    private let backend: DashboardBackend
    private var tasks: [Task<Void, Never>] = []

    init(backend: DashboardBackend) {
        self.backend = backend
    }

    func start() {
        let backend = self.backend
        tasks.append(Task { [weak self] in
            await keepConsuming(
                { backend.traffic() },
                onFailure: { self?.link = .failed($0.localizedDescription) },
                onValue: { self?.apply($0) }
            )
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshRuntime()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.version == nil { self.version = try? await backend.version() }
                await self.refreshMode()
                if self.version != nil { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        rate = TrafficSample()
    }

    private func apply(_ update: TrafficUpdate) {
        link = .connected
        rate = update.rate
        history.removeFirst()
        history.append(update.rate)
        if let totals = update.totals {
            totalsFromTrafficStream = true
            self.totals = totals
        }
        if let outbounds = update.outbounds {
            outboundTraffic = outbounds
                .map { (tag: $0.key, totals: $0.value) }
                .sorted {
                    let (lhs, rhs) = ($0.totals.up + $0.totals.down, $1.totals.up + $1.totals.down)
                    return lhs != rhs ? lhs > rhs : $0.tag < $1.tag
                }
        }
    }

    private func refreshRuntime() async {
        guard let reply = try? await TunnelManager.shared.sendMessage(["type": "runtime"], timeout: 5),
              let footprint = (reply["footprint"] as? NSNumber)?.int64Value else { return }
        runtime = ExtensionRuntime(
            footprint: footprint,
            available: (reply["available"] as? NSNumber)?.int64Value ?? 0
        )
    }

    func refreshMode() async {
        guard DashboardFeature.outboundMode.isAvailable(on: backend.core),
              let result = try? await backend.outboundMode() else { return }
        mode = result.current
        modes = result.all
    }

    func setMode(_ newMode: String) {
        let previous = mode
        mode = newMode
        Task {
            do {
                try await backend.setOutboundMode(newMode)
                await refreshMode()
            } catch {
                mode = previous
                notice = Notice(message: error.localizedDescription, isError: true)
            }
        }
    }

    func run(_ feature: DashboardFeature, success: String) {
        guard !busyTools.contains(feature) else { return }
        busyTools.insert(feature)
        Task {
            defer { busyTools.remove(feature) }
            do {
                switch feature {
                case .flushFakeIP: try await backend.flushFakeIP()
                case .flushDNSCache: try await backend.flushDNSCache()
                case .updateGeoData: try await backend.updateGeoData()
                default: return
                }
                notice = Notice(message: success, isError: false)
            } catch {
                notice = Notice(message: error.localizedDescription, isError: true)
            }
        }
    }

    func queryDNS(name: String, type: String) async throws -> [DNSAnswer] {
        try await backend.queryDNS(name: name, type: type)
    }
}

// MARK: - Proxies

@MainActor
final class ProxiesModel: ObservableObject {
    @Published private(set) var topology = ProxyTopology()
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var testingGroups: Set<String> = []
    @Published private(set) var testingNodes: Set<String> = []
    @Published private(set) var providers: [ProxyProvider] = []
    @Published private(set) var busyProviders: Set<String> = []
    @Published var expanded: Set<String> = []
    @Published var actionError: String?

    fileprivate weak var connections: ConnectionsModel?

    private let backend: DashboardBackend
    private var failedLocally: Set<String> = []
    private var refreshGeneration = 0

    init(backend: DashboardBackend) {
        self.backend = backend
    }

    var core: CoreType { backend.core }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            var fresh = try await backend.proxies()
            guard generation == refreshGeneration else { return }
            for (name, node) in fresh.nodes {
                switch node.delay {
                case .untested where failedLocally.contains(name):
                    fresh.nodes[name]?.delay = .failed
                case .milliseconds:
                    failedLocally.remove(name)
                default:
                    break
                }
            }
            if topology != fresh { topology = fresh }
            loadError = nil
            isLoaded = true
        } catch {
            guard generation == refreshGeneration else { return }
            loadError = error.localizedDescription
        }
        if DashboardFeature.proxyProviders.isAvailable(on: core),
           let providers = try? await backend.proxyProviders(), providers != self.providers {
            self.providers = providers
        }
    }

    func select(_ member: String, in group: ProxyGroup) {
        let current = group.picksAutomatically ? group.pinned : group.selected
        guard group.isSelectable, current != member else { return }
        setSelection(of: group.name, to: member, pinned: group.picksAutomatically ? member : nil)
        Task {
            do {
                try await backend.select(member, in: group.name)
                await closeConnections(through: group.name)
            } catch {
                actionError = error.localizedDescription
            }
            await refresh()
        }
    }

    func unpin(_ group: ProxyGroup) {
        guard group.pinned != nil else { return }
        Task {
            do {
                try await backend.unpin(group: group.name)
            } catch {
                actionError = error.localizedDescription
            }
            await refresh()
        }
    }

    private func setSelection(of groupName: String, to member: String, pinned: String?) {
        guard let index = topology.groups.firstIndex(where: { $0.name == groupName }) else { return }
        topology.groups[index].selected = member
        topology.groups[index].pinned = pinned
    }

    private func closeConnections(through groupName: String) async {
        guard DashboardPreferences.closeOnSwitch,
              DashboardFeature.connections.isAvailable(on: core),
              let connections else { return }
        for connection in connections.items where connection.chain.contains(groupName) {
            try? await backend.closeConnection(connection.id)
        }
    }

    func test(node: String) {
        guard testingNodes.insert(node).inserted else { return }
        Task {
            defer { testingNodes.remove(node) }
            do {
                record([node: try await backend.testDelay(of: node, options: DashboardPreferences.delayOptions)])
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func test(group: ProxyGroup) {
        guard testingGroups.insert(group.name).inserted else { return }
        Task {
            defer { testingGroups.remove(group.name) }
            do {
                for try await results in backend.testDelays(inGroup: group, options: DashboardPreferences.delayOptions) {
                    record(results)
                }
            } catch {
                actionError = error.localizedDescription
            }
            await refresh()
        }
    }

    private func record(_ results: [String: Delay]) {
        for (name, delay) in results {
            let target = topology.leaf(of: name)
            if delay == .failed { failedLocally.insert(target) } else { failedLocally.remove(target) }
            topology.nodes[target]?.delay = delay
        }
    }

    func updateProvider(_ name: String) {
        runOnProvider(name) { try await $0.updateProxyProvider(name) }
    }

    func healthCheckProvider(_ name: String) {
        runOnProvider(name) { try await $0.healthCheckProxyProvider(name) }
    }

    private func runOnProvider(_ name: String, _ action: @escaping (DashboardBackend) async throws -> Void) {
        guard busyProviders.insert(name).inserted else { return }
        Task {
            defer { busyProviders.remove(name) }
            do {
                try await action(backend)
            } catch {
                actionError = error.localizedDescription
            }
            await refresh()
        }
    }
}

// MARK: - Connections

@MainActor
final class ConnectionsModel: ObservableObject {
    @Published private(set) var items: [ConnectionInfo] = []
    @Published var isPaused = false
    @Published var actionError: String?

    fileprivate var onSnapshot: ((ConnectionsSnapshot) -> Void)?

    private let backend: DashboardBackend
    private var task: Task<Void, Never>?
    private var previous: [String: (upload: Int64, download: Int64)] = [:]
    private var previousTime: Date?

    init(backend: DashboardBackend) {
        self.backend = backend
    }

    var isSupported: Bool { DashboardFeature.connections.isAvailable(on: backend.core) }

    func start() {
        guard isSupported, task == nil else { return }
        let backend = self.backend
        task = Task { [weak self] in
            await keepConsuming({ backend.connections() }) { self?.apply($0) }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        previous.removeAll()
        previousTime = nil
    }

    private func apply(_ snapshot: ConnectionsSnapshot) {
        let now = Date()
        let elapsed = previousTime.map { max(now.timeIntervalSince($0), 0.001) }
        var connections = snapshot.connections
        var current: [String: (upload: Int64, download: Int64)] = [:]
        current.reserveCapacity(connections.count)
        for index in connections.indices {
            let connection = connections[index]
            current[connection.id] = (connection.upload, connection.download)
            if let elapsed, let last = previous[connection.id] {
                connections[index].uploadSpeed = Int64(Double(max(connection.upload - last.upload, 0)) / elapsed)
                connections[index].downloadSpeed = Int64(Double(max(connection.download - last.download, 0)) / elapsed)
            }
        }
        previous = current
        previousTime = now

        onSnapshot?(snapshot)
        if !isPaused { items = connections }
    }

    func close(_ connection: ConnectionInfo) {
        items.removeAll { $0.id == connection.id }
        Task {
            do {
                try await backend.closeConnection(connection.id)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func closeAll() {
        items.removeAll()
        Task {
            do {
                try await backend.closeAllConnections()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}

// MARK: - Rules

@MainActor
final class RulesModel: ObservableObject {
    @Published private(set) var rules: [RoutingRule] = []
    @Published private(set) var providers: [RuleProvider] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var busyProviders: Set<String> = []
    @Published var actionError: String?

    private let backend: DashboardBackend

    init(backend: DashboardBackend) {
        self.backend = backend
    }

    var core: CoreType { backend.core }

    func refresh() async {
        do {
            let fresh = try await backend.rules()
            if fresh != rules { rules = fresh }
            loadError = nil
            isLoaded = true
        } catch {
            loadError = error.localizedDescription
        }
        if DashboardFeature.ruleProviders.isAvailable(on: core),
           let providers = try? await backend.ruleProviders(), providers != self.providers {
            self.providers = providers
        }
    }

    func updateProvider(_ name: String) {
        guard busyProviders.insert(name).inserted else { return }
        Task {
            defer { busyProviders.remove(name) }
            do {
                try await backend.updateRuleProvider(name)
            } catch {
                actionError = error.localizedDescription
            }
            await refresh()
        }
    }
}

// MARK: - Logs

@MainActor
final class LogsModel: ObservableObject {
    static let capacity = 500

    @Published private(set) var entries: [LogEntry] = []
    @Published var isPaused = false
    @Published private(set) var level: LogLevel

    private let backend: DashboardBackend
    private var streamTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var pending: [LogLine] = []
    private var nextID = 0
    private var isWanted = false

    init(backend: DashboardBackend) {
        self.backend = backend
        level = UserDefaults.standard.string(forKey: DashboardPreferences.logLevelKey)
            .flatMap(LogLevel.init(rawValue:)) ?? .info
    }

    func activate() {
        isWanted = true
        resumeIfWanted()
    }

    fileprivate func resumeIfWanted() {
        guard isWanted, streamTask == nil else { return }
        let backend = self.backend
        let level = self.level
        streamTask = Task { [weak self] in
            await keepConsuming({ backend.logs(level: level) }) { lines in
                self?.pending.append(contentsOf: lines)
            }
        }
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.flush()
            }
        }
    }

    fileprivate func suspend() {
        streamTask?.cancel()
        flushTask?.cancel()
        streamTask = nil
        flushTask = nil
    }

    private func flush() {
        guard !pending.isEmpty, !isPaused else {
            if pending.count > Self.capacity { pending.removeFirst(pending.count - Self.capacity) }
            return
        }
        let fresh = pending.suffix(Self.capacity).map { line -> LogEntry in
            nextID += 1
            return LogEntry(id: nextID, time: line.time, level: line.level, text: line.text)
        }
        pending.removeAll(keepingCapacity: true)
        entries.insert(contentsOf: fresh.reversed(), at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    func setLevel(_ newLevel: LogLevel) {
        guard newLevel != level else { return }
        level = newLevel
        UserDefaults.standard.set(newLevel.rawValue, forKey: DashboardPreferences.logLevelKey)
        let wasRunning = streamTask != nil
        suspend()
        pending.removeAll()
        if wasRunning { resumeIfWanted() }
    }

    func clear() {
        pending.removeAll()
        entries.removeAll()
    }
}
