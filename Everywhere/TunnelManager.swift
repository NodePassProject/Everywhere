//
//  TunnelManager.swift
//  Everywhere
//
//  Created by NodePassProject on 5/2/26.
//

import Combine
import Foundation
import NetworkExtension

final class TunnelManager: ObservableObject {
    static let shared = TunnelManager()

    @Published private(set) var status: NEVPNStatus = .disconnected
    @Published private(set) var isReady: Bool = false
    @Published private(set) var coreRunning: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var pendingReconnect: Bool = false
    private var manager: NETunnelProviderManager?
    private var statusObserver: AnyCancellable?

    // True once the tunnel has reached .connected in the current
    // session. We only tear on-demand down for *initial* connect
    // failures (broken config); a tunnel that worked and later drops
    // mid-session should stay in iOS's on-demand retry loop.
    private var didConnect: Bool = false

    // Backstop for when iOS sits in Connecting or Disconnecting
    // indefinitely — usually because the NE or its Go core hung.
    private var transitionTimeoutTask: Task<Void, Never>?
    private static let transitionTimeoutNanos: UInt64 = 30 * 1_000_000_000

    private init() {
        setupStatusObserver()
        Task { await reload() }
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == EVCore.Identifier.networkExtension
            }) ?? managers.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            self.isReady = true
            if m.connection.status == .connected {
                // The tunnel was already up from a previous launch —
                // treat it as having connected so a later transient
                // failure isn't misread as an initial failure.
                self.didConnect = true
                queryCoreStatus()
            }
        } catch {
            self.lastError = error.localizedDescription
            self.isReady = true
        }
    }

    func setEnabled(_ on: Bool, configuration: Configuration?) async {
        guard let configuration else {
            lastError = "No configuration is active."
            return
        }
        do {
            if on {
                didConnect = false
                let m = try await ensureManager(
                    coreType: configuration.coreType,
                    configID: configuration.id
                )
                try m.connection.startVPNTunnel()
            } else {
                // An explicit disable should never auto-reconnect.
                pendingReconnect = false
                try await disableTunnel()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Stop the running tunnel and let the status observer reconnect once
    /// it transitions to `.disconnected`. Used when an Always-On change
    /// needs the on-demand rules re-applied while the tunnel is up.
    func reconnect() async {
        guard manager != nil, status.isActive else { return }
        do {
            pendingReconnect = true
            try await disableTunnel()
        } catch {
            pendingReconnect = false
            lastError = error.localizedDescription
        }
    }

    func clearLastError() {
        lastError = nil
    }

    private func ensureManager(coreType: CoreType, configID: UUID) async throws -> NETunnelProviderManager {
        let m = manager ?? NETunnelProviderManager()
        let proto = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        proto.providerBundleIdentifier = EVCore.Identifier.networkExtension
        proto.serverAddress = "Everywhere"
        // Carry only metadata — iOS caps providerConfiguration at 512 KB,
        // and large rulesets blow past that. The NE reads the active
        // config's `content` directly from the shared Core Data store.
        proto.providerConfiguration = [
            "coreType": coreType.rawValue,
            "configID": configID.uuidString,
            "dnsServers": AppState.shared.dnsServers
        ]
        proto.includeAllNetworks = AppState.shared.tunnelIncludeAllNetworks
        proto.excludeLocalNetworks = !AppState.shared.tunnelIncludeLocalNetworks
        if #available(iOS 16.4, *) {
            proto.excludeCellularServices = !AppState.shared.tunnelIncludeCellularServices
        }
        if #available(iOS 17.0, *) {
            proto.excludeAPNs = !AppState.shared.tunnelIncludeAPNs
        }
        m.protocolConfiguration = proto
        m.localizedDescription = EVCore.Identifier.tunnelDescription
        m.isEnabled = true

        if AppState.shared.alwaysOnEnabled {
            let rule = NEOnDemandRuleConnect()
            rule.interfaceTypeMatch = .any
            m.onDemandRules = [rule]
            m.isOnDemandEnabled = true
        } else {
            m.onDemandRules = nil
            m.isOnDemandEnabled = false
        }

        try await m.saveToPreferences()
        try await m.loadFromPreferences()
        manager = m
        return m
    }

    /// Disable the manager's on-demand flag (so iOS doesn't immediately
    /// relaunch the NE) and then stop the tunnel. The user's Always On
    /// preference in `AppState` is intentionally not touched here —
    /// `ensureManager` re-reads it on the next start and re-applies the
    /// on-demand rules accordingly.
    private func disableTunnel() async throws {
        guard let m = manager else { return }
        if m.isOnDemandEnabled {
            m.isOnDemandEnabled = false
            try await m.saveToPreferences()
        }
        m.connection.stopVPNTunnel()
    }

    private func setupStatusObserver() {
        statusObserver = NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .compactMap { $0.object as? NEVPNConnection }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connection in
                guard let self else { return }
                guard connection === self.manager?.connection else { return }
                let previous = self.status
                self.status = connection.status
                self.scheduleTransitionTimeout(for: connection.status)
                self.trackConnectFailures(previous: previous, current: connection.status)
                if connection.status == .connected {
                    self.didConnect = true
                    self.queryCoreStatus()
                } else {
                    self.coreRunning = false
                    if (connection.status == .disconnected || connection.status == .invalid)
                        && self.pendingReconnect {
                        self.pendingReconnect = false
                        if let active = ConfigurationStore.shared.active {
                            Task { await self.setEnabled(true, configuration: active) }
                        }
                    }
                }
            }
    }

    // A Connecting -> Disconnected transition that never reached
    // Connected is a failed start. With on-demand on, iOS would
    // relaunch the NE into the same broken config forever — disable
    // the manager's on-demand flag (the user's Always On preference
    // in AppState is left untouched, so on-demand re-applies on the
    // next start).
    //
    // Only initial failures qualify: once `didConnect` is true the
    // tunnel worked in this session, so a later drop stays in iOS's
    // on-demand retry loop instead of being shut down here.
    private func trackConnectFailures(previous: NEVPNStatus, current: NEVPNStatus) {
        guard !didConnect,
              let m = manager, m.isOnDemandEnabled,
              previous == .connecting,
              current == .disconnected || current == .disconnecting else { return }
        Task { try? await self.disableTunnel() }
        if lastError == nil {
            lastError = "Connection failed. On-demand was disabled — re-enable the tunnel to retry."
        }
    }

    private func scheduleTransitionTimeout(for status: NEVPNStatus) {
        transitionTimeoutTask?.cancel()
        transitionTimeoutTask = nil
        guard status.isTransitioning else { return }
        transitionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.transitionTimeoutNanos)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.status.isTransitioning else { return }
                Task { await self.forceReset() }
            }
        }
    }

    // Last-resort recovery for a tunnel wedged in Connecting or
    // Disconnecting. Drops on-demand so iOS will not relaunch the NE
    // and asks the connection to stop; if the NE itself is hung this
    // at least leaves the user a clear error to act on.
    private func forceReset() async {
        pendingReconnect = false
        do {
            try await disableTunnel()
            if lastError == nil {
                lastError = "Tunnel reset after timing out. Check the configuration and try again."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // The NE keeps itself alive on a core start failure so we can fetch the
    // reason here. When the response says the core isn't running, surface
    // the message and tear the tunnel down — the NE has nothing useful to
    // route through, but iOS thinks it's connected.
    private func queryCoreStatus() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message: [String: Any] = ["type": "core-status"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        do {
            try session.sendProviderMessage(data) { [weak self] response in
                guard let self,
                      let response,
                      let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
                else { return }
                let running = json["running"] as? Bool ?? true
                let error = json["error"] as? String
                DispatchQueue.main.async {
                    // Status may have changed while the IPC was in flight;
                    // only mark the core as running if we're still connected.
                    guard self.status == .connected else { return }
                    if running {
                        self.coreRunning = true
                    } else {
                        self.coreRunning = false
                        self.lastError = error ?? "Core failed to start."
                        // Disable on-demand before stopping — otherwise iOS
                        // immediately relaunches the NE into the same failed
                        // config and the tunnel loops between Connecting and
                        // Disconnecting.
                        Task { try? await self.disableTunnel() }
                    }
                }
            }
        } catch {
            // ignore — NE may have died between the status flip and the send
        }
    }
}

extension NEVPNStatus {
    var isTransitioning: Bool {
        self == .connecting || self == .disconnecting || self == .reasserting
    }

    var isActive: Bool {
        self == .connected || isTransitioning
    }
}
