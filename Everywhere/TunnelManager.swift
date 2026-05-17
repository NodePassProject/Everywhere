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

    private init() {
        setupStatusObserver()
        Task { await reload() }
    }

    func reload() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let m = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == AppGroup.extensionBundleID
            }) ?? managers.first ?? NETunnelProviderManager()
            self.manager = m
            self.status = m.connection.status
            self.isReady = true
            if m.connection.status == .connected {
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
        proto.providerBundleIdentifier = AppGroup.extensionBundleID
        proto.serverAddress = "Everywhere"
        // Carry only metadata — iOS caps providerConfiguration at 512 KB,
        // and large rulesets blow past that. The NE reads the active
        // config's `content` directly from the shared Core Data store.
        proto.providerConfiguration = [
            "coreType": coreType.rawValue,
            "configID": configID.uuidString,
            "dnsServers": AppState.shared.dnsServers
        ]
        m.protocolConfiguration = proto
        m.localizedDescription = AppGroup.tunnelDescription
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

    /// Disable on-demand (so iOS doesn't immediately relaunch the NE) and
    /// then stop the tunnel.
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
                self.status = connection.status
                if connection.status == .connected {
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
                        session.stopVPNTunnel()
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
