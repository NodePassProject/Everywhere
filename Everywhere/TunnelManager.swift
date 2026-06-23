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
    
    private var didConnect: Bool = false
    
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
                pendingReconnect = false
                try await disableTunnel()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
    
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
    
    func applyAlwaysOn(_ enabled: Bool) async {
        if status.isActive {
            await reconnect()
            return
        }
        
        guard !enabled else { return }
        
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let m = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == EVCore.Identifier.networkExtension
            }), m.isOnDemandEnabled else { return }
            m.isOnDemandEnabled = false
            m.onDemandRules = nil
            try await m.saveToPreferences()
            manager = m
        } catch {
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
    
    private func queryCoreStatus() {
        guard let session = manager?.connection as? NETunnelProviderSession else { return }
        let message: [String: Any] = ["type": "core-status"]
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        try? session.sendProviderMessage(data) { [weak self] response in
            guard let self,
                  let response,
                  let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any]
            else { return }
            let running = json["running"] as? Bool ?? true
            let error = json["error"] as? String
            DispatchQueue.main.async {
                guard self.status == .connected else { return }
                if running {
                    self.coreRunning = true
                } else {
                    self.coreRunning = false
                    self.lastError = error ?? "Core failed to start."
                    Task { try? await self.disableTunnel() }
                }
            }
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
